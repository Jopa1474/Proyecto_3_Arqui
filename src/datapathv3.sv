// =============================================================================
// datapathv3.sv — Pipeline del Datapath con Cache Hierarchy
// =============================================================================

// Este módulo representa el datapath principal del procesador con pipeline.
// Integra las etapas IF, ID, EX, MEM y WB.
// En esta versión, la etapa MEM ya no accede directamente a memoria,
// sino que usa cache_hierarchy, que conecta L1, L2 y memoria principal.
// 
// Flujo general del pipeline:
// IF -> Busca la instrucción
// ID -> Decodifica la instrucción y lee registros
// EX -> Ejecuta operaciones en la ALU
// MEM -> Accede a caché/memoria si es LOAD o STORE
// WB -> Escribe el resultado final en el banco de registros
//
// Cambio principal respecto a datapathv2:
// data_memoryv2 fue reemplazado por cache_hierarchy.
// Ahora la memoria se accede mediante:
//  cache_l1 -> cache_l2 -> data_memoryv2
// 
// Señal clave:
// cache_stall congela el pipeline mientras se resuelve un miss de caché.

module datapathv3 #(
    parameter INST_INIT_FILE = "mem/instructions.mem" // archivo donde están las instrucciones iniciales
)(
    input logic clk, // Reloj principal del procesador 
    input logic rst  // Reset activo en alto 
);

// =============================================================================
//Declaraciones internas
// Todas las señales se declaran al inicio para evitar problemas de compilación 
// en Icarus Verilog por referencias adelantadas. 
// =============================================================================

// Cache stall (reemplaza mem_stall de datapathv2)
logic cache_stall; // Señal de cache que, indica si el pipeline avanza o no.
                   // cache_stall = 0, entonces el pipeline puede avanzar normalmente
                   // cache_stall = 1, entonces el pipeline se congela porque la caché está atendiendo un miss.

// IF Stage: Instruction Fetch
logic [31:0] pc_out, pc_plus4, pc_next; // Dirección actual del PC, Dirección de la siguiente instrucción normal, y Próximo valor que tendrá el PC
logic [31:0] branch_target, jr_target;  // Dirección destino de un branch, Dirección destino de un jump register
logic [22:0] instr_if; // Instrucción leída desde memoria de instrucciones
logic pc_write, pc_write_final; // Permiso para actualizar el PC, Permiso final, ya considerando cache_stall
logic halted;   // Indica que el procesador ya se detuvo
logic halt_ex, halt_mem, halt_wb;  // Señal HALT viajando por el pipeline, primero etapa EX, luego MEM y luego WB 
logic [1:0] pc_src_s; // Selecciona de dónde sale el próximo PC

// IF/ID
logic [22:0] instr;      // Instrucción que llega a ID
logic [31:0] pc_id;      // PC de esa instrucción
logic if_id_en, flush;   // Permite actualizar el registro IF/ID, y Borra una instrucción incorrecta por branch o jump. 

// -----------------------------------------------------------------------------
// ID Stage — decode
// -----------------------------------------------------------------------------

//Estas señales salen de partir la instrucción en campos.
logic [3:0] opcode, rd_d, rs1_d, rs1_eff, rs2_rtype, rs2_read; // Valor leído del primer registro, Valor leído del segundo registro, Resultado final que se escribe en WB, Registro destino en WB, Habilita escritura en el banco de registros
logic [2:0] funct3; // Campo funct3 de la instrucción
logic [8:0] funct9; // Campo funct9 de la instrucción
logic [1:0] ki_d;   // Campo de selección de llave para instrucciones vault
logic cond_bit;     // Bit de condición usado por algunas instrucciones
logic [31:0] imm_d;  // Inmediato extendido a 32 bits
logic [1:0]  byte_sel; // Selección de byte para operaciones especiales

// -----------------------------------------------------------------------------
// ID Stage — register file
// -----------------------------------------------------------------------------
logic [31:0] src_a_d;  // Primer dato leído del register file
logic [31:0] src_b_d;  // Segundo dato leído del register file
logic [31:0] result_wb; // Resultado final que se escribirá en WB
logic [3:0]  rd_wb;  // Registro destino en la etapa WB
logic reg_write_wb;  // Habilita escritura en el register file desde WB

// -----------------------------------------------------------------------------
// ID Stage — forwarding / branch
// Estas señales sirven para resolver dependencias cuando un branch necesita valores recientes.
// -----------------------------------------------------------------------------
logic TakenD; // Indica si un branch debe tomarse
logic [1:0] ForwardAD;  // Control de forwarding para el primer operando del branch
logic [1:0] ForwardBD;  // Control de forwarding para el segundo operando del branch
logic [31:0] BrA;  // Primer operando final usado para comparar branch
logic [31:0] BrB;  // Segundo operando final usado para comparar branch
logic [31:0] alu_result_mem; // Resultado de ALU que viene desde la etapa MEM


// -----------------------------------------------------------------------------
// ID Stage : Señales generadas por la unidad de control.
// -----------------------------------------------------------------------------
logic reg_write_cu, mem_write_cu, mem_read_cu, alu_src_cu;
logic [1:0] wb_sel_cu; // Selecciona qué dato se escribe en WB
logic [1:0] BranchTypeD; // Tipo de branch
logic BranchCondD;  // Condición del branch
logic JumpD;       // Indica si la instrucción es jump inmediato
logic JumpRegD;      // Indica si la instrucción es jump register
logic [2:0] alu_op_cu; // Operación que realizará la ALU
logic is_vault_cu; // Indica si la instrucción usa la ALU de vault
logic is_lli_cu;   // Indica si la instrucción es LLI
logic halt_cu;     // Indica si la instrucción es HALT

// Señales de control relacionadas con autenticación y seguridad
logic do_setpwd, do_login, do_logout, do_authorize;
logic do_vkload, do_vkinv, do_authchk, auth_denied;
logic [1:0] tea_op_cu; // Operación especial para ALU vault
logic auth_ok; // Indica que la autenticación es válida


// -----------------------------------------------------------------------------
// ID Stage — Unidad de hazard detection 
// -----------------------------------------------------------------------------
logic nop;             // Inserta una burbuja o NOP en el pipeline
logic IsAuthD;         // Indica si la instrucción actual es de autenticación
logic reg_write_ex;    // Señal reg_write en la etapa EX
logic [3:0] rd_ex_w;   // Registro destino en EX
logic mem_read_ex_w;   // Indica si la instrucción en EX lee memoria
logic reg_write_mem_w; // Señal reg_write en MEM
logic [3:0] rd_mem_w;  // Registro destino en MEM

// ----------------------------------------------------------------------------- 
// ID Stage: selección del PC 
// -----------------------------------------------------------------------------
logic [1:0]  PCSrcD;     // Selección del próximo PC calculada en ID
logic [31:0] PCBranchD;  // Dirección calculada para branch
logic [31:0] imm_shifted_d; // Inmediato desplazado dos bits para calcular branch

// ----------------------------------------------------------------------------- 
// ID Stage: autenticación y vault 
// -----------------------------------------------------------------------------
logic [1:0] ki_activo, vault_key_sel, vault_word_sel;
logic vault_we;   // Habilita escritura en el vault
logic vault_inv;  // Invalida una llave del vault
logic [31:0] vault_data_in, sr;// Dato que entra al vault y Registro de estado de autenticació
logic vf_flag;    // Bandera relacionada con vault/auth
logic [31:0] key_word_d; // Palabra de llave obtenida desde key_vault

// ----------------------------------------------------------------------------- 
// Registro ID/EX: salidas hacia EX 
// ---------------------------------------------------------------------------
logic mem_write_ex;    // Señal de escritura en memoria propagada a EX
logic [1:0] wb_sel_ex; // Selección de WB propagada a EX
logic alu_src_ex;      // Selección de operando ALU propagada a EX
logic [2:0] alu_op_ex; // Operación ALU propagada a EX
logic is_vault_ex, is_lli_ex;
logic [1:0] byte_sel_ex; // Selección de byte en EX
logic [1:0] tea_op_ex;   // Operación TEA/vault en EX
logic [31:0] pc_ex, src_a_ex, src_b_ex, imm_ex;
logic [3:0] rs1_ex, rs2_ex;
logic [31:0] key_word_ex; // Palabra de llave propagada a EX

// -----------------------------------------------------------------------------
// EX Stage
// -----------------------------------------------------------------------------
logic [1:0] ForwardA, ForwardB;
logic [31:0] fwd_a, fwd_b; // Control de forwarding para operando A de la AL y Control de forwarding para operando B de la ALU
logic [31:0] alu_b, alu_result_ex;
logic [31:0] pc_plus4_ex;     // PC + 4 calculado en EX
logic [31:0] vault_result_ex; // Resultado producido por la ALU vault
logic [31:0] alu_result_final; // Resultado final seleccionado entre ALU normal y ALU vault

// ----------------------------------------------------------------------------- 
// Registro EX/MEM: salidas hacia MEM 
// --------------------------------------------------------------------------
logic [1:0] wb_sel_mem; // Selección de WB en MEM
logic [31:0] write_data_mem, pc_plus4_mem;
logic mem_read_mem, mem_write_mem;


// -----------------------------------------------------------------------------
// MEM Stage
// -----------------------------------------------------------------------------
logic [31:0] read_data; // Dato leído desde cache_hierarchy
logic cpu_req_mem; // Solicitud hacia cache_hierarchy

// -----------------------------------------------------------------------------
// Contadores de rendimiento de cache_hierarchy
// -----------------------------------------------------------------------------
logic [31:0] l1_read_hits, l1_read_misses, l1_write_hits, l1_write_misses;
logic [31:0] l2_read_hits, l2_read_misses, l2_write_hits, l2_write_misses;
logic [31:0] mem_accesses, mem_cycles;
logic stall_l1_miss;
logic stall_l2_miss;

// -----------------------------------------------------------------------------
// Registro MEM/WB: Salidas hacia WB
// -----------------------------------------------------------------------------
logic [1:0] wb_sel_wb;
logic [31:0] read_data_wb, alu_result_wb, pc_plus4_wb;

// Contadores de rendimiento del procesador
logic [31:0] perf_cycle_count;        // Cuenta ciclos totales ejecutados
logic [31:0] perf_instr_count;        // Cuenta instrucciones retiradas
logic [31:0] perf_cache_stall_cycles; // Cuenta ciclos perdidos por cache_stall
logic [31:0] perf_stall_l1miss_cycles;// Cuenta ciclos de stall por miss de L1
logic [31:0] perf_stall_l2miss_cycles;// Cuenta ciclos de stall por miss de L2
logic [31:0] perf_branch_stalls;      // Cuenta stalls/flushes por branch
logic [31:0] perf_load_use_stalls;    // Cuenta stalls por dependencia load-use
logic [31:0] perf_ipc_x1000;          // IPC en punto fijo x1000
logic [31:0] perf_l1_hit_rate_x1000;  // Hit rate L1 en punto fijo x1000
logic [31:0] perf_l2_hit_rate_x1000;  // Hit rate L2 en punto fijo x1000
logic [31:0] perf_l1_miss_rate_x1000; // Miss rate L1 en punto fijo x1000
logic [31:0] perf_l2_miss_rate_x1000; // Miss rate L2 en punto fijo x1000
logic [31:0] perf_amat_x1000;         // AMAT en punto fijo x1000
logic [31:0] perf_l1_read_accesses;   // Accesos de lectura en L1
logic [31:0] perf_l1_write_accesses;  // Accesos de escritura en L1
logic [31:0] perf_l1_total_accesses;  // Accesos totales en L1
logic [31:0] perf_l2_read_accesses;   // Accesos de lectura en L2
logic [31:0] perf_l2_write_accesses;  // Accesos de escritura en L2
logic [31:0] perf_l2_total_accesses;  // Accesos totales en L2
logic [31:0] perf_mem_accesses;       // Accesos a memoria principal
logic [31:0] perf_mem_cycles_used;    // Ciclos usados por memoria principal
logic mem_write_wb;                   // STORE propagado hasta WB para contarlo como instrucción completada
logic was_branch_ex, was_branch_mem, was_branch_wb; // Indica si hubo branch en EX, MEM O WB
logic wb_valid;     // Indica si una instruccion valida llegó a WB.

// =============================================================================
// Assign combinacionales
// =============================================================================

// Permite escribir el PC solamente si no hay halt y no hay stall de caché.
// También  permite actualizar el PC cuando hay branch o jump. 
// Si cache_stall está activo, el PC se congela. 

assign pc_write_final = ((pc_write && !halt_cu && !halted) ||
         ((pc_src_s != 2'b00) && !nop && !halt_cu && !halted)) && !cache_stall;


// ---------------------------------------------------------------------------
// Decodificación directa de campos de la instrucción. 
// ---------------------------------------------------------------------------
assign opcode    = instr[22:19]; // Extrae el opcode de la instrucción.
assign rd_d      = instr[18:15]; // Extrae el registro destino.
assign rs1_d     = instr[14:11]; //  Extra el primer regisstro fuente
assign rs2_rtype = instr[10:7];  // Extrae el segundo registro fuente para tipo R

// Algunas instrucciones usan rs2 en posiciones distintas.
// Si opcode es 1100 se usa rs2_rtype, si no, se usa instr[18:15].
assign rs2_read  = (opcode == 4'b1100) ? rs2_rtype : instr[18:15];

assign funct3    = instr[6:4];  // Extrae funct3
assign funct9    = instr[8:0];  // Extrae funct9
assign ki_d      = instr[10:9]; // Extrae campo de llave 
assign cond_bit  = instr[10];   // Extrae bit de condición 

// Algunas instrucciones usan rd como fuente
// Para esos opcodes, rs1_eff toma rd_d en lugar de rs1_d.
assign rs1_eff   = (opcode == 4'b0010 || opcode == 4'b1000) ? rd_d : rs1_d;

// Indica si la instrucción en ID pertenece al grupo de autenticación.
assign IsAuthD = do_login | do_setpwd | do_authorize | do_vkload;

// -----------------------------------------------------------------------------
// Selección del próximo PC
// -----------------------------------------------------------------------------

// Si no hay NOP, el PC sigue normal
// Si hay jump register, se selecciona jr_target
// Si hay jump o branch tomado, se selecciona branch_target
// Si no hay cambio de flujo, se usa PC + 4

assign PCSrcD   = nop ? 2'b00 :
                  JumpRegD ? 2'b10 :
                  (JumpD || TakenD) ? 2'b01 :
                  2'b00;


// Si e procesador está detenido o hay HALT, no se permite cambio especial de PC. 
assign pc_src_s = (halted || halt_cu) ? 2'b00 : PCSrcD;

// Se hace flush cuando hay branch o jump. 
// No se hace flush durante cache_stall porque el pipeline está congelado
assign flush    = (pc_src_s != 2'b00) && !halted && !cache_stall;

// Cálculo de direcciones de salto (Branch target)
assign imm_shifted_d = imm_d << 2; // Desplaza el inmediato para formar dirección alineada a palabra
assign branch_target = PCBranchD;  // Dirección destino de branch
assign jr_target     = BrA;        // Dirección destino para jump register. 

// -----------------------------------------------------------------------------
//Solicitud hacia la jerarquía de caché
// -----------------------------------------------------------------------------
// Se solicita acceso a memoria si la instrucción  en MEM es LOAD o STORE.
// cache_hierarchy se encarga internamente del handshake con L1, L2 y memoria.
assign cpu_req_mem = mem_read_mem || mem_write_mem;

// Una instrucción se considera válida en WB si escribe registro,
// Si es STORE o si fue branch, siempre que no haya halt ni cache_stall. 
// WB valido para contadores
assign wb_valid = (reg_write_wb || mem_write_wb || was_branch_wb) && !halted && !cache_stall;

// =============================================================================
// IF Stage
// =============================================================================


adder #(32) add_pc4 (pc_out, 32'd4, pc_plus4); // Calcula PC + 4, que es la dirección de la siguiente instrucción secuencial.

// MUX que selecciona el próximo PC. 
// Entrada 0: PC + 4
// Entrada 1: branch_target 
// Entrada 2: jr_target 
// Entrada 3: 0, no usada
mux4  #(32) mux_pc  (
    pc_plus4,        // Siguiente instrucción normal
    branch_target,   // Dirección de branch/jump
    jr_target,       // Dirección de jump register
    32'd0, pc_src_s, // Selector del próximo PC
    pc_next);        // Salida hacia el PC


// Registro del program counter. 
// Solo actualiza si pc_write_final está activo.
program_counter pc_reg (
    .clk(clk), .rst(rst),
    .PCWrite(pc_write_final),
    .pc_next(pc_next),
    .pc_out(pc_out)
);

// Memoria de instrucciones. 
// Lee la instrucción ubicada en pc_out.
inst_mem #(.INIT_FILE(INST_INIT_FILE)) imem (.addr(pc_out), .inst(instr_if));

// Registro IF/ID. 
// Guarda la instrucción y el PC entre IF e ID. 
// Se congela cuando cache_stall está activo.
if_id_reg if_id (
    .clk(clk), .rst(rst),
    .en((if_id_en && !halted) && !cache_stall),
    .flush((flush || halt_cu) && !cache_stall),
    .in_instr(instr_if),
    .in_pc(pc_out),
    .instr(instr),
    .pc(pc_id)
);

// =============================================================================
// ID Stage
// =============================================================================

// Genera el inmediato de 32 bits y la selección de byte a partir de la instrucción.

imm_gen imm_gen (
    .instruction(instr),  // Instrucción en ID
    .imm_out(imm_d),      // Inmediato generado
    .byte_sel(byte_sel)); // Selección de byte

// Banco de registros
// Lee dos registros y escribe el resultado que viene de WB.
// La escritura se bloquea durante cache_stall para evitar cambios incorrectos.

reg_file rf (
    .clk(clk), .rst(rst),
    .write_en(reg_write_wb && !cache_stall), // Significa que no se escribe en los registros si la caché está en stall.
    .rs1(rs1_eff),
    .rs2(rs2_read),
    .rd(rd_wb),
    .WD3(result_wb),
    .RD1(src_a_d),
    .RD2(src_b_d));

// Mux de forwarding para el primer operando usado en branch.
mux4 #(32) mux_brA (src_a_d, result_wb, alu_result_mem, 32'd0, ForwardAD, BrA);

// Mux de forwarding para el segundo operando usado en branch.
mux4 #(32) mux_brB (src_b_d, result_wb, alu_result_mem, 32'd0, ForwardBD, BrB);


// Comparador de branch. 
// Decide si el branch se toma o no según BrA, BrB y el tipo de branch.
branch_compare brcmp (
    .a(BrA), // Primer operando de comparación
    .b(BrB), // Segundo operando de comparación
    .BranchTypeD(BranchTypeD), // Condición de branch
    .BranchCondD(BranchCondD), // Resultado: branch tomado o no
    .TakenD(TakenD));


// Unidad de control.
// Decodifica opcode/funct y genera las señales de control del pipeline.
control_unit cu (
    .opcode(opcode),
    .funct3(funct3),
    .funct9(funct9),
    .res_bits(2'b00),
    .cond_bit(cond_bit),
    .auth_ok(auth_ok),
    .reg_write_en(reg_write_cu),
    .mem_write(mem_write_cu),
    .mem_read(mem_read_cu),
    .wb_sel(wb_sel_cu),
    .alu_src(alu_src_cu),
    .alu_op(alu_op_cu),
    .is_lli(is_lli_cu),
    .is_vault(is_vault_cu),
    .halt(halt_cu),
    .BranchTypeD(BranchTypeD),
    .BranchCondD(BranchCondD),
    .JumpD(JumpD),
    .JumpRegD(JumpRegD),
    .do_setpwd(do_setpwd),
    .do_login(do_login),
    .do_logout(do_logout),
    .do_authorize(do_authorize),
    .do_vkload(do_vkload),
    .do_vkinv(do_vkinv),
    .do_authchk(do_authchk),
    .auth_denied(auth_denied),
    .tea_op(tea_op_cu));

// Unidad de detección de riesgos. 
// Detecta hazards de datos, load-use, branches y forwarding. 
// También considera cache_stall para coordinar el congelamiento del pipeline.
hazard_detection haz (
    .cache_stall(cache_stall),
    .IF_ID_Rs1(rs1_eff),
    .IF_ID_Rs2(rs2_read),
    .BranchD(BranchTypeD != 2'b00),
    .JumpRegD(JumpRegD),
    .IsAuthD(IsAuthD),
    .ID_EX_MemRead (mem_read_ex_w),
    .ID_EX_RegWrite(reg_write_ex),
    .ID_EX_Rd(rd_ex_w),
    .EX_MEM_RegWrite(reg_write_mem_w),
    .MEM_MemtoReg(mem_read_mem),
    .EX_MEM_Rd(rd_mem_w),
    .MEM_WB_RegWrite(reg_write_wb),
    .MEM_WB_Rd(rd_wb),
    .ForwardAD(ForwardAD),
    .ForwardBD(ForwardBD),
    .PCWrite(pc_write),
    .IF_ID_Write(if_id_en),
    .control_mux_sel(nop));


// Registro que indica si el procesador ya se detuvo.
 // halted se activa cuando HALT llega a la etapa WB.
always_ff @(posedge clk or posedge rst) begin
    if (rst) halted <= 1'b0;
    else if (halt_wb) halted <= 1'b1;
end

// Calcula la dirección de branch sumando PC actual en ID + inmediato desplazado.
adder #(32) add_branch_d (pc_id, imm_shifted_d, PCBranchD);


// Unidad de autenticación. 
// Controla login, logout, password, autorización y manejo del vault.
auth_unit auth (
    .clk(clk), .rst(rst),
    .do_setpwd(do_setpwd && !nop),
    .do_login(do_login && !nop),
    .do_logout(do_logout),
    .do_authorize(do_authorize && !nop),
    .do_vkload(do_vkload && !nop),
    .do_vkinv(do_vkinv && !nop),
    .do_authchk(do_authchk),
    .auth_denied(auth_denied && !nop),
    .rs1_data(BrA),
    .uid_field(BrB[1:0]),
    .ki_field(ki_d),
    .instr_retired(!nop && !halt_cu && !halted && !cache_stall),
    .auth_ok(auth_ok),
    .ki_activo(ki_activo),
    .vf_flag(vf_flag),
    .exc_trigger(),
    .exc_cause(),
    .vault_we(vault_we),
    .vault_invalidate(vault_inv),
    .vault_key_sel(vault_key_sel),
    .vault_word_sel(vault_word_sel),
    .vault_data_in(vault_data_in),
    .sr(sr));

// Módulo que almacena las llaves usadas por instrucciones vault.
key_vault key_vault (
    .clk(clk),
    .rst(rst),
    .vault_we(vault_we),
    .vault_invalidate(vault_inv),
    .vault_key_sel(vault_key_sel),
    .vault_word_sel(vault_word_sel),
    .vault_data_in(vault_data_in),
    .ki_activo(ki_activo),
    .ki(ki_d),
    .key_word_out(key_word_d));

// ============================================================================= 
// ID/EX — registro entre ID y EX 
// ============================================================================= 
// Este registro guarda operandos, inmediato, señales de control,
// registros fuente/destino y señales de vault. 
// Se congela cuando cache_stall está activo.
id_ex_reg id_ex (
    .clk(clk), .rst(rst),
    .en(!halted && !cache_stall),
    .nop((nop && !halt_cu) && !cache_stall),
    .in_is_halt(halt_cu),
    .in_reg_write(reg_write_cu),
    .in_wb_sel(wb_sel_cu),
    .in_mem_write(mem_write_cu),
    .in_mem_read(mem_read_cu),
    .in_alu_src(alu_src_cu),
    .in_alu_op(alu_op_cu),
    .in_is_vault(is_vault_cu),
    .in_key_word(key_word_d),
    .in_is_lli(is_lli_cu),
    .in_byte_sel(byte_sel),
    .in_tea_op(tea_op_cu),
    .in_pc(pc_id),
    .in_src_a(BrA),
    .in_src_b(BrB),
    .in_imm(imm_d),
    .in_rd(rd_d),
    .in_rs1(rs1_eff),
    .in_rs2(rs2_read),
    .is_halt(halt_ex),
    .reg_write(reg_write_ex),
    .wb_sel(wb_sel_ex),
    .mem_write(mem_write_ex),
    .mem_read(mem_read_ex_w),
    .alu_src(alu_src_ex),
    .alu_op(alu_op_ex),
    .is_vault(is_vault_ex),
    .key_word(key_word_ex),
    .is_lli(is_lli_ex),
    .byte_sel(byte_sel_ex),
    .tea_op(tea_op_ex),
    .pc(pc_ex),
    .src_a(src_a_ex),
    .src_b(src_b_ex),
    .imm(imm_ex),
    .rd(rd_ex_w),
    .rs1(rs1_ex),
    .rs2(rs2_ex));

// =============================================================================
// EX Stage
// =============================================================================


// Unidad de forwarding para la ALU. 
// Decide si los operandos vienen del registro ID/EX, de MEM o de WB.
fwd_logic fwd (
    .EX_MEM_MemtoReg(mem_read_mem),
    .EX_MEM_RegWrite(reg_write_mem_w),
    .EX_MEM_Rd(rd_mem_w),
    .MEM_WB_RegWrite(reg_write_wb),
    .MEM_WB_Rd(rd_wb),
    .ID_EX_Rs1(rs1_ex),
    .ID_EX_Rs2(rs2_ex),
    .forwardA(ForwardA),
    .forwardB(ForwardB));

// Mux de forwarding para el operando A de la ALU.
mux4 #(32) mux_fwd_a (src_a_ex, result_wb, alu_result_mem, 32'd0, ForwardA, fwd_a);

// Mux de forwarding para el operando B de la ALU.
mux4 #(32) mux_fwd_b (src_b_ex, result_wb, alu_result_mem, 32'd0, ForwardB, fwd_b);

// Selecciona el segundo operando de la ALU. 
// Puede ser un registro reenviado o un inmediato.
mux2 #(32) mux_b_sel (fwd_b, imm_ex, alu_src_ex, alu_b);


// ALU principal. 
// Ejecuta operaciones aritméticas, lógicas y cálculo de direcciones.
alu alu (
    .rs1(fwd_a),
    .rs2(alu_b),
    .funct(alu_op_ex),
    .byte_sel(byte_sel_ex),
    .is_lli(is_lli_ex),
    .result(alu_result_ex));

// Calcula PC + 4 en EX. 
// Se usa para instrucciones que guardan dirección de retorno.

adder #(32) add_pc4_ex (pc_ex, 32'd4, pc_plus4_ex);

// ALU especial para instrucciones vault o cifrado.
alu_v alu_v (
    .rs1(fwd_a),
    .K(key_word_ex),
    .tea_op(tea_op_ex),
    .result(vault_result_ex));

// Selecciona si el resultado final viene de la ALU normal o de la ALU vault.
mux2 #(32) mux_alu_sel (alu_result_ex, vault_result_ex, is_vault_ex, alu_result_final);

// =============================================================================
// EX/MEM — registro entre EX y MEM bloqueado por cache_stall
// =============================================================================

// Guarda los resultados de EX para usarlos en MEM. 
// Se congela cuando cache_stall está activo.
ex_mem_reg ex_mem (
    .clk(clk), .rst(rst),
    .en(!halted && !cache_stall),
    .in_is_halt(halt_ex),
    .in_reg_write(reg_write_ex),
    .in_wb_sel(wb_sel_ex),
    .in_mem_write(mem_write_ex),
    .in_mem_read(mem_read_ex_w),
    .in_alu_result(alu_result_final),
    .in_write_data(fwd_b),
    .in_pc_plus4(pc_plus4_ex),
    .in_rd(rd_ex_w),
    .is_halt(halt_mem),
    .reg_write(reg_write_mem_w),
    .wb_sel(wb_sel_mem),
    .mem_write(mem_write_mem),
    .mem_read(mem_read_mem),
    .alu_result(alu_result_mem),
    .write_data(write_data_mem),
    .pc_plus4(pc_plus4_mem),
    .rd(rd_mem_w));

// =============================================================================
// MEM Stage — cache_hierarchy (L1 → L2 → data_memoryv2)
// =============================================================================


// Jerarquía de memoria. 
// Reemplaza el acceso directo a data_memoryv2. 
// Internamente conecta:
// cache_l1 -> cache_l2 -> data_memoryv2
cache_hierarchy hier (
    .clk            (clk),
    .rst_n          (~rst),
    .cpu_req        (cpu_req_mem),
    .cpu_addr       (alu_result_mem),
    .cpu_wr_en      (mem_write_mem),
    .cpu_write_data (write_data_mem),
    .cpu_read_data  (read_data),
    .cache_stall    (cache_stall),
    .stall_l1_miss  (stall_l1_miss),
    .stall_l2_miss  (stall_l2_miss),
    .l1_read_hits   (l1_read_hits),
    .l1_read_misses (l1_read_misses),
    .l1_write_hits  (l1_write_hits),
    .l1_write_misses(l1_write_misses),
    .l2_read_hits   (l2_read_hits),
    .l2_read_misses (l2_read_misses),
    .l2_write_hits  (l2_write_hits),
    .l2_write_misses(l2_write_misses),
    .mem_accesses   (mem_accesses),
    .mem_cycles     (mem_cycles)
);

// =============================================================================
// MEM/WB — registro entre MEM Y WB 
// =============================================================================

// Guarda los datos que salen de MEM para usarlos en WB. 
// Se congela cuando cache_stall está activo.

mem_wb_reg mem_wb (
    .clk(clk), .rst(rst),
    .en(!halted && !cache_stall),
    .in_is_halt(halt_mem),
    .in_reg_write(reg_write_mem_w),
    .in_wb_sel(wb_sel_mem),
    .in_read_data(read_data),
    .in_alu_result(alu_result_mem),
    .in_pc_plus4(pc_plus4_mem),
    .in_rd(rd_mem_w),
    .is_halt(halt_wb),
    .reg_write(reg_write_wb),
    .wb_sel(wb_sel_wb),
    .read_data(read_data_wb),
    .alu_result(alu_result_wb),
    .pc_plus4(pc_plus4_wb),
    .rd(rd_wb));

// =============================================================================
// WB Stage
// =============================================================================

// Selecciona qué dato se escribirá finalmente en el register file. 
// Puede ser resultado de ALU, dato leído de memoria o PC + 4.

mux4 #(32) mux_wb (alu_result_wb, read_data_wb, pc_plus4_wb, 32'd0,
                   wb_sel_wb, result_wb);

// =============================================================================
// Performance Counters
// =============================================================================

// Contadores consolidados de rendimiento.
perf_counters perf_cnt (
    .clk                  (clk),
    .rst_n                (~rst),
    .instr_retired        (wb_valid),
    .stall_l1miss         (stall_l1_miss),
    .stall_l2miss         (stall_l2_miss),
    .stall_control        (flush && !cache_stall),
    .l1_read_hits         (l1_read_hits),
    .l1_read_misses       (l1_read_misses),
    .l1_write_hits        (l1_write_hits),
    .l1_write_misses      (l1_write_misses),
    .l2_read_hits         (l2_read_hits),
    .l2_read_misses       (l2_read_misses),
    .l2_write_hits        (l2_write_hits),
    .l2_write_misses      (l2_write_misses),
    .total_mem_accesses   (mem_accesses),
    .total_mem_cycles     (mem_cycles),
    .total_cycles         (perf_cycle_count),
    .instructions_completed(perf_instr_count),
    .stall_cycles_l1miss  (perf_stall_l1miss_cycles),
    .stall_cycles_l2miss  (perf_stall_l2miss_cycles),
    .stall_cycles_control (perf_branch_stalls),
    .l1_read_accesses     (perf_l1_read_accesses),
    .l1_write_accesses    (perf_l1_write_accesses),
    .l1_total_accesses    (perf_l1_total_accesses),
    .l2_read_accesses     (perf_l2_read_accesses),
    .l2_write_accesses    (perf_l2_write_accesses),
    .l2_total_accesses    (perf_l2_total_accesses),
    .mem_accesses         (perf_mem_accesses),
    .mem_cycles_used      (perf_mem_cycles_used),
    .ipc_x1000            (perf_ipc_x1000),
    .l1_hit_rate_x1000    (perf_l1_hit_rate_x1000),
    .l2_hit_rate_x1000    (perf_l2_hit_rate_x1000),
    .l1_miss_rate_x1000   (perf_l1_miss_rate_x1000),
    .l2_miss_rate_x1000   (perf_l2_miss_rate_x1000),
    .amat_x1000           (perf_amat_x1000)
);

// Propaga mem_write_mem hacia WB para poder contar STORE como instrucción retirada.
always_ff @(posedge clk) begin
    if (rst)
        mem_write_wb <= 1'b0;          // En reset no hay STORE en WB
    else if (!halted && !cache_stall)
        mem_write_wb <= mem_write_mem; // Si el pipeline avanza, propaga STORE
    else if (!cache_stall)
        mem_write_wb <= 1'b0;          // Si no hay stall pero está halted, limpia la señal end
end

// Propaga información de branch por el pipeline para los contadores.
always_ff @(posedge clk) begin
    if (rst) begin
        was_branch_ex  <= 1'b0; // Limpia branch en EX
        was_branch_mem <= 1'b0; // Limpia branch en MEM
        was_branch_wb  <= 1'b0; // Limpia branch en WB
    end else if (!halted && !cache_stall) begin
        was_branch_ex  <= flush;          // Si hubo flush, se considera branch/jump
        was_branch_mem <= was_branch_ex;  // Propaga branch hacia MEM
        was_branch_wb  <= was_branch_mem; // Propaga branch hacia WB
    end
end


// Contadores principales de rendimiento. 
// Se mantiene local únicamente el contador de stalls por load-use.
always_ff @(posedge clk) begin
    if (rst) begin
        perf_cache_stall_cycles <= 32'd0; // Reinicia contador de stalls globales de caché
        perf_load_use_stalls    <= 32'd0; // Reinicia contador de load-use stalls
    end else if (!halted) begin
        if (cache_stall)
            perf_cache_stall_cycles <= perf_cache_stall_cycles + 1; // Cuenta stalls globales del pipeline por caché

        if (haz.load_use_stall && !cache_stall)
            perf_load_use_stalls <= perf_load_use_stalls + 1; // Cuenta stalls por dependencia load-use
    end
end

endmodule
