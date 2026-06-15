// cache_l2.sv
// Caché L2 unificada para el procesador TEA-ISA.
//
// Actúa como intermediario entre L1 y la memoria principal. Ante un miss de L1
// busca la línea en su arreglo; si hay hit responde en 8 ciclos, si no lanza
// un burst hacia data_memoryv2 y devuelve la línea cuando llega.
//
// Parámetros fijos según especificación:
//   Tamaño: 16 KB, 4-way set associative, líneas de 32 bytes (8 palabras)
//   128 sets, write-back obligatorio, hit time de 8 ciclos de CPU
//
// Organización de la dirección de 32 bits:
//   [31:12] tag (20 bits) | [11:5] index (7 bits) | [4:2] offset (3 bits) | [1:0] byte
//
// Reemplazo Pseudo-LRU con árbol de 3 bits por set {b2, b1, b0}:
//   b2 apunta al subárbol (0=vías 0-1, 1=vías 2-3), b1 y b0 desempatan dentro.
//   Al acceder a una vía los bits se actualizan en dirección contraria.
//
// Compatibilidad Icarus Verilog:
//   Icarus no soporta indexar arreglos multidimensionales con señal variable
//   en ningún bloque always. La solución es un estado S_LOOKUP que captura
//   valid/tag/dirty/plru del set activo en registros simples (cur_*), y en
//   el ciclo siguiente S_DECIDE opera sobre esos registros para decidir
//   hit vs miss sin tocar el arreglo multidim. Los writes usan case expandido.
//   Arreglos desempacados en puertos se conectan con genvar en el módulo superior.
//
// Autores: [Nombres del grupo]
// CE-4301 Arquitectura de Computadores I, I Semestre 2026

module cache_l2 #(
    parameter DATA_WIDTH  = 32,
    parameter NUM_SETS    = 128,
    parameter NUM_WAYS    = 4,
    parameter LINE_WORDS  = 8,
    parameter HIT_LATENCY = 8,
    parameter WB_DEPTH    = 4,
    parameter INDEX_BITS  = 7,
    parameter OFFSET_BITS = 3,
    parameter TAG_BITS    = 20
)(
    input  logic clk,
    input  logic rst_n,

    // L1 activa l1_req=1 en un miss y lo mantiene hasta que l2_valid=1.
    // l1_dirty_writeback indica que L1 también evicta una línea dirty propia.
    // l1_dirty_line: conectar con genvar en el módulo superior.
    input  logic        l1_req,
    input  logic [31:0] l1_addr,
    input  logic        l1_wr_en,
    input  logic [31:0] l1_write_word,
    input  logic        l1_dirty_writeback,
    input  logic [31:0] l1_dirty_line [0:LINE_WORDS-1],

    // l2_ready: L2 puede aceptar un nuevo request (estado IDLE o LOOKUP).
    // l2_valid: pulso de 1 ciclo, L1 captura l2_line en ese ciclo.
    // l2_line: conectar con genvar en el módulo superior.
    output logic        l2_ready,
    output logic        l2_valid,
    output logic [31:0] l2_line [0:LINE_WORDS-1],

    // Interfaz hacia data_memoryv2. L2 es el único master del bus.
    // mem_burst_data: conectar con genvar en el módulo superior.
    output logic        mem_req,
    output logic [31:0] mem_addr,
    output logic        mem_wr_en,
    output logic        mem_burst_en,
    output logic [31:0] mem_write_data,
    input  logic        mem_ready,
    input  logic        mem_valid,
    input  logic [31:0] mem_burst_data [0:LINE_WORDS-1],

    output logic [31:0] l2_read_hits,
    output logic [31:0] l2_read_misses,
    output logic [31:0] l2_write_hits,
    output logic [31:0] l2_write_misses,
    output logic        stall_l2_miss
);

// Arreglos de almacenamiento
logic              valid [0:NUM_SETS-1][0:NUM_WAYS-1];
logic              dirty [0:NUM_SETS-1][0:NUM_WAYS-1];
logic [TAG_BITS-1:0] tag [0:NUM_SETS-1][0:NUM_WAYS-1];
logic [31:0]        data [0:NUM_SETS-1][0:NUM_WAYS-1][0:LINE_WORDS-1];
logic [2:0]         plru [0:NUM_SETS-1];

// Write buffer aplanado (sin typedef struct, Icarus no lo soporta con arreglos)
logic [31:0] wb_addr  [0:WB_DEPTH-1];
logic [31:0] wb_words [0:WB_DEPTH-1][0:LINE_WORDS-1];
logic [1:0]  wb_head, wb_tail;
logic [2:0]  wb_count;
logic wb_full, wb_empty;
assign wb_full  = (wb_count == WB_DEPTH[2:0]);
assign wb_empty = (wb_count == 3'd0);

// Decodificación de dirección entrante
logic [TAG_BITS-1:0]    req_tag;
logic [INDEX_BITS-1:0]  req_index;
logic [OFFSET_BITS-1:0] req_offset;
logic [31:0]            line_base_addr;
assign req_tag        = l1_addr[31:12];
assign req_index      = l1_addr[11:5];
assign req_offset     = l1_addr[4:2];
assign line_base_addr = {l1_addr[31:5], 5'b00000};

// Registros intermedios del set activo.
// Se cargan en S_LOOKUP desde el arreglo principal y se usan en S_DECIDE,
// evitando accesos con índice variable en always_ff (no soportado en Icarus).
logic cur_valid0, cur_valid1, cur_valid2, cur_valid3;
logic cur_dirty0, cur_dirty1, cur_dirty2, cur_dirty3;
logic [TAG_BITS-1:0] cur_tag0, cur_tag1, cur_tag2, cur_tag3;
logic [2:0]        cur_plru;

// Latched request — declaradas antes del always_comb que las usa
logic [31:0]            latched_addr;
logic                   latched_wr_en;
logic [31:0]            latched_write_word;
logic [INDEX_BITS-1:0]  latched_index;
logic [TAG_BITS-1:0]    latched_tag;
logic [OFFSET_BITS-1:0] latched_offset;
logic [31:0]            latched_line_base;

// Hit detection y victim selection sobre los registros cur_* (no arreglo multidim)
logic [NUM_WAYS-1:0] way_hit;
logic                l2_hit;
logic [1:0]          hit_way;
logic [1:0]          victim_way;

always @(*) begin
    way_hit[0] = cur_valid0 && (cur_tag0 == latched_tag);
    way_hit[1] = cur_valid1 && (cur_tag1 == latched_tag);
    way_hit[2] = cur_valid2 && (cur_tag2 == latched_tag);
    way_hit[3] = cur_valid3 && (cur_tag3 == latched_tag);

    l2_hit  = |way_hit;
    hit_way = 2'd0;
    if      (way_hit[0]) hit_way = 2'd0;
    else if (way_hit[1]) hit_way = 2'd1;
    else if (way_hit[2]) hit_way = 2'd2;
    else if (way_hit[3]) hit_way = 2'd3;

    if      (!cur_valid0) victim_way = 2'd0;
    else if (!cur_valid1) victim_way = 2'd1;
    else if (!cur_valid2) victim_way = 2'd2;
    else if (!cur_valid3) victim_way = 2'd3;
    else begin
        if (!cur_plru[2]) victim_way = cur_plru[1] ? 2'd0 : 2'd1;
        else              victim_way = cur_plru[0] ? 2'd2 : 2'd3;
    end
end

// FSM — se agrega S_LOOKUP para separar la captura de registros de la decisión
localparam S_IDLE       = 4'd0; // esperando l1_req
localparam S_LOOKUP     = 4'd1; // capturando cur_* del set activo (1 ciclo)
localparam S_DECIDE     = 4'd2; // usando cur_* para decidir hit/miss
localparam S_HIT_WAIT   = 4'd3; // contando 8 ciclos de latencia
localparam S_MEM_REQ    = 4'd4; // enviando burst a data_memoryv2
localparam S_MEM_WAIT   = 4'd5; // esperando mem_valid
localparam S_FILL_L2    = 4'd6; // instalando línea en el arreglo
localparam S_RESPOND_L1 = 4'd7; // pulsando l2_valid
localparam S_WB_DRAIN   = 4'd8; // drenando write buffer

logic [3:0]  state;
logic [3:0]  hit_counter;
logic [1:0]  active_way;
logic [31:0] fill_buffer [0:LINE_WORDS-1];

// Stall específico de miss en L2: activo durante la ruta a memoria principal
assign stall_l2_miss = (state == S_MEM_REQ) || (state == S_MEM_WAIT) || (state == S_FILL_L2);

integer fi, fj;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        hit_counter    <= '0;
        active_way     <= '0;
        l2_valid       <= 1'b0;
        mem_req        <= 1'b0;
        mem_wr_en      <= 1'b0;
        mem_burst_en   <= 1'b1;
        mem_addr       <= '0;
        mem_write_data <= '0;
        latched_addr       <= '0; latched_wr_en      <= 1'b0;
        latched_write_word <= '0; latched_index      <= '0;
        latched_tag        <= '0; latched_offset     <= '0;
        latched_line_base  <= '0;
        wb_head  <= '0; wb_tail <= '0; wb_count <= '0;
        l2_read_hits <= '0; l2_read_misses <= '0;
        l2_write_hits <= '0; l2_write_misses <= '0;
        cur_plru <= '0;
        cur_valid0<=0; cur_valid1<=0; cur_valid2<=0; cur_valid3<=0;
        cur_dirty0<=0; cur_dirty1<=0; cur_dirty2<=0; cur_dirty3<=0;
        cur_tag0<='0; cur_tag1<='0; cur_tag2<='0; cur_tag3<='0;
        for (fi = 0; fi < NUM_SETS; fi++) begin
            plru[fi] <= '0;
            for (fj = 0; fj < NUM_WAYS; fj++) begin
                valid[fi][fj] <= 0; dirty[fi][fj] <= 0; tag[fi][fj] <= '0;
            end
        end
        for (fi = 0; fi < LINE_WORDS; fi++) fill_buffer[fi] <= '0;

    end else begin
        l2_valid <= 1'b0;
        mem_req  <= 1'b0;

        case (state)

            // Esperando request de L1. Al llegar, latchear parámetros y pasar a LOOKUP.
            S_IDLE: begin
                if (l1_req) begin
                    latched_addr       <= l1_addr;
                    latched_wr_en      <= l1_wr_en;
                    latched_write_word <= l1_write_word;
                    latched_index      <= req_index;
                    latched_tag        <= req_tag;
                    latched_offset     <= req_offset;
                    latched_line_base  <= line_base_addr;

                    if (l1_dirty_writeback && !wb_full) begin
                        wb_addr[wb_tail] <= {l1_addr[31:5], 5'b00000};
                        for (fi = 0; fi < LINE_WORDS; fi++)
                            wb_words[wb_tail][fi] <= l1_dirty_line[fi];
                        wb_tail <= wb_tail + 1; wb_count <= wb_count + 1;
                    end

                    state <= S_LOOKUP;
                end else if (!wb_empty && mem_ready) begin
                    state <= S_WB_DRAIN;
                end
            end

            // Capturar valid/tag/dirty/plru del set latched_index en registros cur_*.
            // Esto es necesario porque Icarus no permite valid[variable][w] en always_ff.
            // En el siguiente ciclo (S_DECIDE) los registros ya tienen los valores correctos.
            S_LOOKUP: begin
                // Case-expanded to avoid variable index on multidim array (Icarus limitation)
                case (latched_index)
                    7'd0: begin cur_valid0<=valid[0][0]; cur_tag0<=tag[0][0]; cur_dirty0<=dirty[0][0]; cur_valid1<=valid[0][1]; cur_tag1<=tag[0][1]; cur_dirty1<=dirty[0][1]; cur_valid2<=valid[0][2]; cur_tag2<=tag[0][2]; cur_dirty2<=dirty[0][2]; cur_valid3<=valid[0][3]; cur_tag3<=tag[0][3]; cur_dirty3<=dirty[0][3]; cur_plru<=plru[0]; end
                    7'd1: begin cur_valid0<=valid[1][0]; cur_tag0<=tag[1][0]; cur_dirty0<=dirty[1][0]; cur_valid1<=valid[1][1]; cur_tag1<=tag[1][1]; cur_dirty1<=dirty[1][1]; cur_valid2<=valid[1][2]; cur_tag2<=tag[1][2]; cur_dirty2<=dirty[1][2]; cur_valid3<=valid[1][3]; cur_tag3<=tag[1][3]; cur_dirty3<=dirty[1][3]; cur_plru<=plru[1]; end
                    7'd2: begin cur_valid0<=valid[2][0]; cur_tag0<=tag[2][0]; cur_dirty0<=dirty[2][0]; cur_valid1<=valid[2][1]; cur_tag1<=tag[2][1]; cur_dirty1<=dirty[2][1]; cur_valid2<=valid[2][2]; cur_tag2<=tag[2][2]; cur_dirty2<=dirty[2][2]; cur_valid3<=valid[2][3]; cur_tag3<=tag[2][3]; cur_dirty3<=dirty[2][3]; cur_plru<=plru[2]; end
                    7'd3: begin cur_valid0<=valid[3][0]; cur_tag0<=tag[3][0]; cur_dirty0<=dirty[3][0]; cur_valid1<=valid[3][1]; cur_tag1<=tag[3][1]; cur_dirty1<=dirty[3][1]; cur_valid2<=valid[3][2]; cur_tag2<=tag[3][2]; cur_dirty2<=dirty[3][2]; cur_valid3<=valid[3][3]; cur_tag3<=tag[3][3]; cur_dirty3<=dirty[3][3]; cur_plru<=plru[3]; end
                    7'd4: begin cur_valid0<=valid[4][0]; cur_tag0<=tag[4][0]; cur_dirty0<=dirty[4][0]; cur_valid1<=valid[4][1]; cur_tag1<=tag[4][1]; cur_dirty1<=dirty[4][1]; cur_valid2<=valid[4][2]; cur_tag2<=tag[4][2]; cur_dirty2<=dirty[4][2]; cur_valid3<=valid[4][3]; cur_tag3<=tag[4][3]; cur_dirty3<=dirty[4][3]; cur_plru<=plru[4]; end
                    7'd5: begin cur_valid0<=valid[5][0]; cur_tag0<=tag[5][0]; cur_dirty0<=dirty[5][0]; cur_valid1<=valid[5][1]; cur_tag1<=tag[5][1]; cur_dirty1<=dirty[5][1]; cur_valid2<=valid[5][2]; cur_tag2<=tag[5][2]; cur_dirty2<=dirty[5][2]; cur_valid3<=valid[5][3]; cur_tag3<=tag[5][3]; cur_dirty3<=dirty[5][3]; cur_plru<=plru[5]; end
                    7'd6: begin cur_valid0<=valid[6][0]; cur_tag0<=tag[6][0]; cur_dirty0<=dirty[6][0]; cur_valid1<=valid[6][1]; cur_tag1<=tag[6][1]; cur_dirty1<=dirty[6][1]; cur_valid2<=valid[6][2]; cur_tag2<=tag[6][2]; cur_dirty2<=dirty[6][2]; cur_valid3<=valid[6][3]; cur_tag3<=tag[6][3]; cur_dirty3<=dirty[6][3]; cur_plru<=plru[6]; end
                    7'd7: begin cur_valid0<=valid[7][0]; cur_tag0<=tag[7][0]; cur_dirty0<=dirty[7][0]; cur_valid1<=valid[7][1]; cur_tag1<=tag[7][1]; cur_dirty1<=dirty[7][1]; cur_valid2<=valid[7][2]; cur_tag2<=tag[7][2]; cur_dirty2<=dirty[7][2]; cur_valid3<=valid[7][3]; cur_tag3<=tag[7][3]; cur_dirty3<=dirty[7][3]; cur_plru<=plru[7]; end
                    7'd8: begin cur_valid0<=valid[8][0]; cur_tag0<=tag[8][0]; cur_dirty0<=dirty[8][0]; cur_valid1<=valid[8][1]; cur_tag1<=tag[8][1]; cur_dirty1<=dirty[8][1]; cur_valid2<=valid[8][2]; cur_tag2<=tag[8][2]; cur_dirty2<=dirty[8][2]; cur_valid3<=valid[8][3]; cur_tag3<=tag[8][3]; cur_dirty3<=dirty[8][3]; cur_plru<=plru[8]; end
                    7'd9: begin cur_valid0<=valid[9][0]; cur_tag0<=tag[9][0]; cur_dirty0<=dirty[9][0]; cur_valid1<=valid[9][1]; cur_tag1<=tag[9][1]; cur_dirty1<=dirty[9][1]; cur_valid2<=valid[9][2]; cur_tag2<=tag[9][2]; cur_dirty2<=dirty[9][2]; cur_valid3<=valid[9][3]; cur_tag3<=tag[9][3]; cur_dirty3<=dirty[9][3]; cur_plru<=plru[9]; end
                    7'd10: begin cur_valid0<=valid[10][0]; cur_tag0<=tag[10][0]; cur_dirty0<=dirty[10][0]; cur_valid1<=valid[10][1]; cur_tag1<=tag[10][1]; cur_dirty1<=dirty[10][1]; cur_valid2<=valid[10][2]; cur_tag2<=tag[10][2]; cur_dirty2<=dirty[10][2]; cur_valid3<=valid[10][3]; cur_tag3<=tag[10][3]; cur_dirty3<=dirty[10][3]; cur_plru<=plru[10]; end
                    7'd11: begin cur_valid0<=valid[11][0]; cur_tag0<=tag[11][0]; cur_dirty0<=dirty[11][0]; cur_valid1<=valid[11][1]; cur_tag1<=tag[11][1]; cur_dirty1<=dirty[11][1]; cur_valid2<=valid[11][2]; cur_tag2<=tag[11][2]; cur_dirty2<=dirty[11][2]; cur_valid3<=valid[11][3]; cur_tag3<=tag[11][3]; cur_dirty3<=dirty[11][3]; cur_plru<=plru[11]; end
                    7'd12: begin cur_valid0<=valid[12][0]; cur_tag0<=tag[12][0]; cur_dirty0<=dirty[12][0]; cur_valid1<=valid[12][1]; cur_tag1<=tag[12][1]; cur_dirty1<=dirty[12][1]; cur_valid2<=valid[12][2]; cur_tag2<=tag[12][2]; cur_dirty2<=dirty[12][2]; cur_valid3<=valid[12][3]; cur_tag3<=tag[12][3]; cur_dirty3<=dirty[12][3]; cur_plru<=plru[12]; end
                    7'd13: begin cur_valid0<=valid[13][0]; cur_tag0<=tag[13][0]; cur_dirty0<=dirty[13][0]; cur_valid1<=valid[13][1]; cur_tag1<=tag[13][1]; cur_dirty1<=dirty[13][1]; cur_valid2<=valid[13][2]; cur_tag2<=tag[13][2]; cur_dirty2<=dirty[13][2]; cur_valid3<=valid[13][3]; cur_tag3<=tag[13][3]; cur_dirty3<=dirty[13][3]; cur_plru<=plru[13]; end
                    7'd14: begin cur_valid0<=valid[14][0]; cur_tag0<=tag[14][0]; cur_dirty0<=dirty[14][0]; cur_valid1<=valid[14][1]; cur_tag1<=tag[14][1]; cur_dirty1<=dirty[14][1]; cur_valid2<=valid[14][2]; cur_tag2<=tag[14][2]; cur_dirty2<=dirty[14][2]; cur_valid3<=valid[14][3]; cur_tag3<=tag[14][3]; cur_dirty3<=dirty[14][3]; cur_plru<=plru[14]; end
                    7'd15: begin cur_valid0<=valid[15][0]; cur_tag0<=tag[15][0]; cur_dirty0<=dirty[15][0]; cur_valid1<=valid[15][1]; cur_tag1<=tag[15][1]; cur_dirty1<=dirty[15][1]; cur_valid2<=valid[15][2]; cur_tag2<=tag[15][2]; cur_dirty2<=dirty[15][2]; cur_valid3<=valid[15][3]; cur_tag3<=tag[15][3]; cur_dirty3<=dirty[15][3]; cur_plru<=plru[15]; end
                    7'd16: begin cur_valid0<=valid[16][0]; cur_tag0<=tag[16][0]; cur_dirty0<=dirty[16][0]; cur_valid1<=valid[16][1]; cur_tag1<=tag[16][1]; cur_dirty1<=dirty[16][1]; cur_valid2<=valid[16][2]; cur_tag2<=tag[16][2]; cur_dirty2<=dirty[16][2]; cur_valid3<=valid[16][3]; cur_tag3<=tag[16][3]; cur_dirty3<=dirty[16][3]; cur_plru<=plru[16]; end
                    7'd17: begin cur_valid0<=valid[17][0]; cur_tag0<=tag[17][0]; cur_dirty0<=dirty[17][0]; cur_valid1<=valid[17][1]; cur_tag1<=tag[17][1]; cur_dirty1<=dirty[17][1]; cur_valid2<=valid[17][2]; cur_tag2<=tag[17][2]; cur_dirty2<=dirty[17][2]; cur_valid3<=valid[17][3]; cur_tag3<=tag[17][3]; cur_dirty3<=dirty[17][3]; cur_plru<=plru[17]; end
                    7'd18: begin cur_valid0<=valid[18][0]; cur_tag0<=tag[18][0]; cur_dirty0<=dirty[18][0]; cur_valid1<=valid[18][1]; cur_tag1<=tag[18][1]; cur_dirty1<=dirty[18][1]; cur_valid2<=valid[18][2]; cur_tag2<=tag[18][2]; cur_dirty2<=dirty[18][2]; cur_valid3<=valid[18][3]; cur_tag3<=tag[18][3]; cur_dirty3<=dirty[18][3]; cur_plru<=plru[18]; end
                    7'd19: begin cur_valid0<=valid[19][0]; cur_tag0<=tag[19][0]; cur_dirty0<=dirty[19][0]; cur_valid1<=valid[19][1]; cur_tag1<=tag[19][1]; cur_dirty1<=dirty[19][1]; cur_valid2<=valid[19][2]; cur_tag2<=tag[19][2]; cur_dirty2<=dirty[19][2]; cur_valid3<=valid[19][3]; cur_tag3<=tag[19][3]; cur_dirty3<=dirty[19][3]; cur_plru<=plru[19]; end
                    7'd20: begin cur_valid0<=valid[20][0]; cur_tag0<=tag[20][0]; cur_dirty0<=dirty[20][0]; cur_valid1<=valid[20][1]; cur_tag1<=tag[20][1]; cur_dirty1<=dirty[20][1]; cur_valid2<=valid[20][2]; cur_tag2<=tag[20][2]; cur_dirty2<=dirty[20][2]; cur_valid3<=valid[20][3]; cur_tag3<=tag[20][3]; cur_dirty3<=dirty[20][3]; cur_plru<=plru[20]; end
                    7'd21: begin cur_valid0<=valid[21][0]; cur_tag0<=tag[21][0]; cur_dirty0<=dirty[21][0]; cur_valid1<=valid[21][1]; cur_tag1<=tag[21][1]; cur_dirty1<=dirty[21][1]; cur_valid2<=valid[21][2]; cur_tag2<=tag[21][2]; cur_dirty2<=dirty[21][2]; cur_valid3<=valid[21][3]; cur_tag3<=tag[21][3]; cur_dirty3<=dirty[21][3]; cur_plru<=plru[21]; end
                    7'd22: begin cur_valid0<=valid[22][0]; cur_tag0<=tag[22][0]; cur_dirty0<=dirty[22][0]; cur_valid1<=valid[22][1]; cur_tag1<=tag[22][1]; cur_dirty1<=dirty[22][1]; cur_valid2<=valid[22][2]; cur_tag2<=tag[22][2]; cur_dirty2<=dirty[22][2]; cur_valid3<=valid[22][3]; cur_tag3<=tag[22][3]; cur_dirty3<=dirty[22][3]; cur_plru<=plru[22]; end
                    7'd23: begin cur_valid0<=valid[23][0]; cur_tag0<=tag[23][0]; cur_dirty0<=dirty[23][0]; cur_valid1<=valid[23][1]; cur_tag1<=tag[23][1]; cur_dirty1<=dirty[23][1]; cur_valid2<=valid[23][2]; cur_tag2<=tag[23][2]; cur_dirty2<=dirty[23][2]; cur_valid3<=valid[23][3]; cur_tag3<=tag[23][3]; cur_dirty3<=dirty[23][3]; cur_plru<=plru[23]; end
                    7'd24: begin cur_valid0<=valid[24][0]; cur_tag0<=tag[24][0]; cur_dirty0<=dirty[24][0]; cur_valid1<=valid[24][1]; cur_tag1<=tag[24][1]; cur_dirty1<=dirty[24][1]; cur_valid2<=valid[24][2]; cur_tag2<=tag[24][2]; cur_dirty2<=dirty[24][2]; cur_valid3<=valid[24][3]; cur_tag3<=tag[24][3]; cur_dirty3<=dirty[24][3]; cur_plru<=plru[24]; end
                    7'd25: begin cur_valid0<=valid[25][0]; cur_tag0<=tag[25][0]; cur_dirty0<=dirty[25][0]; cur_valid1<=valid[25][1]; cur_tag1<=tag[25][1]; cur_dirty1<=dirty[25][1]; cur_valid2<=valid[25][2]; cur_tag2<=tag[25][2]; cur_dirty2<=dirty[25][2]; cur_valid3<=valid[25][3]; cur_tag3<=tag[25][3]; cur_dirty3<=dirty[25][3]; cur_plru<=plru[25]; end
                    7'd26: begin cur_valid0<=valid[26][0]; cur_tag0<=tag[26][0]; cur_dirty0<=dirty[26][0]; cur_valid1<=valid[26][1]; cur_tag1<=tag[26][1]; cur_dirty1<=dirty[26][1]; cur_valid2<=valid[26][2]; cur_tag2<=tag[26][2]; cur_dirty2<=dirty[26][2]; cur_valid3<=valid[26][3]; cur_tag3<=tag[26][3]; cur_dirty3<=dirty[26][3]; cur_plru<=plru[26]; end
                    7'd27: begin cur_valid0<=valid[27][0]; cur_tag0<=tag[27][0]; cur_dirty0<=dirty[27][0]; cur_valid1<=valid[27][1]; cur_tag1<=tag[27][1]; cur_dirty1<=dirty[27][1]; cur_valid2<=valid[27][2]; cur_tag2<=tag[27][2]; cur_dirty2<=dirty[27][2]; cur_valid3<=valid[27][3]; cur_tag3<=tag[27][3]; cur_dirty3<=dirty[27][3]; cur_plru<=plru[27]; end
                    7'd28: begin cur_valid0<=valid[28][0]; cur_tag0<=tag[28][0]; cur_dirty0<=dirty[28][0]; cur_valid1<=valid[28][1]; cur_tag1<=tag[28][1]; cur_dirty1<=dirty[28][1]; cur_valid2<=valid[28][2]; cur_tag2<=tag[28][2]; cur_dirty2<=dirty[28][2]; cur_valid3<=valid[28][3]; cur_tag3<=tag[28][3]; cur_dirty3<=dirty[28][3]; cur_plru<=plru[28]; end
                    7'd29: begin cur_valid0<=valid[29][0]; cur_tag0<=tag[29][0]; cur_dirty0<=dirty[29][0]; cur_valid1<=valid[29][1]; cur_tag1<=tag[29][1]; cur_dirty1<=dirty[29][1]; cur_valid2<=valid[29][2]; cur_tag2<=tag[29][2]; cur_dirty2<=dirty[29][2]; cur_valid3<=valid[29][3]; cur_tag3<=tag[29][3]; cur_dirty3<=dirty[29][3]; cur_plru<=plru[29]; end
                    7'd30: begin cur_valid0<=valid[30][0]; cur_tag0<=tag[30][0]; cur_dirty0<=dirty[30][0]; cur_valid1<=valid[30][1]; cur_tag1<=tag[30][1]; cur_dirty1<=dirty[30][1]; cur_valid2<=valid[30][2]; cur_tag2<=tag[30][2]; cur_dirty2<=dirty[30][2]; cur_valid3<=valid[30][3]; cur_tag3<=tag[30][3]; cur_dirty3<=dirty[30][3]; cur_plru<=plru[30]; end
                    7'd31: begin cur_valid0<=valid[31][0]; cur_tag0<=tag[31][0]; cur_dirty0<=dirty[31][0]; cur_valid1<=valid[31][1]; cur_tag1<=tag[31][1]; cur_dirty1<=dirty[31][1]; cur_valid2<=valid[31][2]; cur_tag2<=tag[31][2]; cur_dirty2<=dirty[31][2]; cur_valid3<=valid[31][3]; cur_tag3<=tag[31][3]; cur_dirty3<=dirty[31][3]; cur_plru<=plru[31]; end
                    7'd32: begin cur_valid0<=valid[32][0]; cur_tag0<=tag[32][0]; cur_dirty0<=dirty[32][0]; cur_valid1<=valid[32][1]; cur_tag1<=tag[32][1]; cur_dirty1<=dirty[32][1]; cur_valid2<=valid[32][2]; cur_tag2<=tag[32][2]; cur_dirty2<=dirty[32][2]; cur_valid3<=valid[32][3]; cur_tag3<=tag[32][3]; cur_dirty3<=dirty[32][3]; cur_plru<=plru[32]; end
                    7'd33: begin cur_valid0<=valid[33][0]; cur_tag0<=tag[33][0]; cur_dirty0<=dirty[33][0]; cur_valid1<=valid[33][1]; cur_tag1<=tag[33][1]; cur_dirty1<=dirty[33][1]; cur_valid2<=valid[33][2]; cur_tag2<=tag[33][2]; cur_dirty2<=dirty[33][2]; cur_valid3<=valid[33][3]; cur_tag3<=tag[33][3]; cur_dirty3<=dirty[33][3]; cur_plru<=plru[33]; end
                    7'd34: begin cur_valid0<=valid[34][0]; cur_tag0<=tag[34][0]; cur_dirty0<=dirty[34][0]; cur_valid1<=valid[34][1]; cur_tag1<=tag[34][1]; cur_dirty1<=dirty[34][1]; cur_valid2<=valid[34][2]; cur_tag2<=tag[34][2]; cur_dirty2<=dirty[34][2]; cur_valid3<=valid[34][3]; cur_tag3<=tag[34][3]; cur_dirty3<=dirty[34][3]; cur_plru<=plru[34]; end
                    7'd35: begin cur_valid0<=valid[35][0]; cur_tag0<=tag[35][0]; cur_dirty0<=dirty[35][0]; cur_valid1<=valid[35][1]; cur_tag1<=tag[35][1]; cur_dirty1<=dirty[35][1]; cur_valid2<=valid[35][2]; cur_tag2<=tag[35][2]; cur_dirty2<=dirty[35][2]; cur_valid3<=valid[35][3]; cur_tag3<=tag[35][3]; cur_dirty3<=dirty[35][3]; cur_plru<=plru[35]; end
                    7'd36: begin cur_valid0<=valid[36][0]; cur_tag0<=tag[36][0]; cur_dirty0<=dirty[36][0]; cur_valid1<=valid[36][1]; cur_tag1<=tag[36][1]; cur_dirty1<=dirty[36][1]; cur_valid2<=valid[36][2]; cur_tag2<=tag[36][2]; cur_dirty2<=dirty[36][2]; cur_valid3<=valid[36][3]; cur_tag3<=tag[36][3]; cur_dirty3<=dirty[36][3]; cur_plru<=plru[36]; end
                    7'd37: begin cur_valid0<=valid[37][0]; cur_tag0<=tag[37][0]; cur_dirty0<=dirty[37][0]; cur_valid1<=valid[37][1]; cur_tag1<=tag[37][1]; cur_dirty1<=dirty[37][1]; cur_valid2<=valid[37][2]; cur_tag2<=tag[37][2]; cur_dirty2<=dirty[37][2]; cur_valid3<=valid[37][3]; cur_tag3<=tag[37][3]; cur_dirty3<=dirty[37][3]; cur_plru<=plru[37]; end
                    7'd38: begin cur_valid0<=valid[38][0]; cur_tag0<=tag[38][0]; cur_dirty0<=dirty[38][0]; cur_valid1<=valid[38][1]; cur_tag1<=tag[38][1]; cur_dirty1<=dirty[38][1]; cur_valid2<=valid[38][2]; cur_tag2<=tag[38][2]; cur_dirty2<=dirty[38][2]; cur_valid3<=valid[38][3]; cur_tag3<=tag[38][3]; cur_dirty3<=dirty[38][3]; cur_plru<=plru[38]; end
                    7'd39: begin cur_valid0<=valid[39][0]; cur_tag0<=tag[39][0]; cur_dirty0<=dirty[39][0]; cur_valid1<=valid[39][1]; cur_tag1<=tag[39][1]; cur_dirty1<=dirty[39][1]; cur_valid2<=valid[39][2]; cur_tag2<=tag[39][2]; cur_dirty2<=dirty[39][2]; cur_valid3<=valid[39][3]; cur_tag3<=tag[39][3]; cur_dirty3<=dirty[39][3]; cur_plru<=plru[39]; end
                    7'd40: begin cur_valid0<=valid[40][0]; cur_tag0<=tag[40][0]; cur_dirty0<=dirty[40][0]; cur_valid1<=valid[40][1]; cur_tag1<=tag[40][1]; cur_dirty1<=dirty[40][1]; cur_valid2<=valid[40][2]; cur_tag2<=tag[40][2]; cur_dirty2<=dirty[40][2]; cur_valid3<=valid[40][3]; cur_tag3<=tag[40][3]; cur_dirty3<=dirty[40][3]; cur_plru<=plru[40]; end
                    7'd41: begin cur_valid0<=valid[41][0]; cur_tag0<=tag[41][0]; cur_dirty0<=dirty[41][0]; cur_valid1<=valid[41][1]; cur_tag1<=tag[41][1]; cur_dirty1<=dirty[41][1]; cur_valid2<=valid[41][2]; cur_tag2<=tag[41][2]; cur_dirty2<=dirty[41][2]; cur_valid3<=valid[41][3]; cur_tag3<=tag[41][3]; cur_dirty3<=dirty[41][3]; cur_plru<=plru[41]; end
                    7'd42: begin cur_valid0<=valid[42][0]; cur_tag0<=tag[42][0]; cur_dirty0<=dirty[42][0]; cur_valid1<=valid[42][1]; cur_tag1<=tag[42][1]; cur_dirty1<=dirty[42][1]; cur_valid2<=valid[42][2]; cur_tag2<=tag[42][2]; cur_dirty2<=dirty[42][2]; cur_valid3<=valid[42][3]; cur_tag3<=tag[42][3]; cur_dirty3<=dirty[42][3]; cur_plru<=plru[42]; end
                    7'd43: begin cur_valid0<=valid[43][0]; cur_tag0<=tag[43][0]; cur_dirty0<=dirty[43][0]; cur_valid1<=valid[43][1]; cur_tag1<=tag[43][1]; cur_dirty1<=dirty[43][1]; cur_valid2<=valid[43][2]; cur_tag2<=tag[43][2]; cur_dirty2<=dirty[43][2]; cur_valid3<=valid[43][3]; cur_tag3<=tag[43][3]; cur_dirty3<=dirty[43][3]; cur_plru<=plru[43]; end
                    7'd44: begin cur_valid0<=valid[44][0]; cur_tag0<=tag[44][0]; cur_dirty0<=dirty[44][0]; cur_valid1<=valid[44][1]; cur_tag1<=tag[44][1]; cur_dirty1<=dirty[44][1]; cur_valid2<=valid[44][2]; cur_tag2<=tag[44][2]; cur_dirty2<=dirty[44][2]; cur_valid3<=valid[44][3]; cur_tag3<=tag[44][3]; cur_dirty3<=dirty[44][3]; cur_plru<=plru[44]; end
                    7'd45: begin cur_valid0<=valid[45][0]; cur_tag0<=tag[45][0]; cur_dirty0<=dirty[45][0]; cur_valid1<=valid[45][1]; cur_tag1<=tag[45][1]; cur_dirty1<=dirty[45][1]; cur_valid2<=valid[45][2]; cur_tag2<=tag[45][2]; cur_dirty2<=dirty[45][2]; cur_valid3<=valid[45][3]; cur_tag3<=tag[45][3]; cur_dirty3<=dirty[45][3]; cur_plru<=plru[45]; end
                    7'd46: begin cur_valid0<=valid[46][0]; cur_tag0<=tag[46][0]; cur_dirty0<=dirty[46][0]; cur_valid1<=valid[46][1]; cur_tag1<=tag[46][1]; cur_dirty1<=dirty[46][1]; cur_valid2<=valid[46][2]; cur_tag2<=tag[46][2]; cur_dirty2<=dirty[46][2]; cur_valid3<=valid[46][3]; cur_tag3<=tag[46][3]; cur_dirty3<=dirty[46][3]; cur_plru<=plru[46]; end
                    7'd47: begin cur_valid0<=valid[47][0]; cur_tag0<=tag[47][0]; cur_dirty0<=dirty[47][0]; cur_valid1<=valid[47][1]; cur_tag1<=tag[47][1]; cur_dirty1<=dirty[47][1]; cur_valid2<=valid[47][2]; cur_tag2<=tag[47][2]; cur_dirty2<=dirty[47][2]; cur_valid3<=valid[47][3]; cur_tag3<=tag[47][3]; cur_dirty3<=dirty[47][3]; cur_plru<=plru[47]; end
                    7'd48: begin cur_valid0<=valid[48][0]; cur_tag0<=tag[48][0]; cur_dirty0<=dirty[48][0]; cur_valid1<=valid[48][1]; cur_tag1<=tag[48][1]; cur_dirty1<=dirty[48][1]; cur_valid2<=valid[48][2]; cur_tag2<=tag[48][2]; cur_dirty2<=dirty[48][2]; cur_valid3<=valid[48][3]; cur_tag3<=tag[48][3]; cur_dirty3<=dirty[48][3]; cur_plru<=plru[48]; end
                    7'd49: begin cur_valid0<=valid[49][0]; cur_tag0<=tag[49][0]; cur_dirty0<=dirty[49][0]; cur_valid1<=valid[49][1]; cur_tag1<=tag[49][1]; cur_dirty1<=dirty[49][1]; cur_valid2<=valid[49][2]; cur_tag2<=tag[49][2]; cur_dirty2<=dirty[49][2]; cur_valid3<=valid[49][3]; cur_tag3<=tag[49][3]; cur_dirty3<=dirty[49][3]; cur_plru<=plru[49]; end
                    7'd50: begin cur_valid0<=valid[50][0]; cur_tag0<=tag[50][0]; cur_dirty0<=dirty[50][0]; cur_valid1<=valid[50][1]; cur_tag1<=tag[50][1]; cur_dirty1<=dirty[50][1]; cur_valid2<=valid[50][2]; cur_tag2<=tag[50][2]; cur_dirty2<=dirty[50][2]; cur_valid3<=valid[50][3]; cur_tag3<=tag[50][3]; cur_dirty3<=dirty[50][3]; cur_plru<=plru[50]; end
                    7'd51: begin cur_valid0<=valid[51][0]; cur_tag0<=tag[51][0]; cur_dirty0<=dirty[51][0]; cur_valid1<=valid[51][1]; cur_tag1<=tag[51][1]; cur_dirty1<=dirty[51][1]; cur_valid2<=valid[51][2]; cur_tag2<=tag[51][2]; cur_dirty2<=dirty[51][2]; cur_valid3<=valid[51][3]; cur_tag3<=tag[51][3]; cur_dirty3<=dirty[51][3]; cur_plru<=plru[51]; end
                    7'd52: begin cur_valid0<=valid[52][0]; cur_tag0<=tag[52][0]; cur_dirty0<=dirty[52][0]; cur_valid1<=valid[52][1]; cur_tag1<=tag[52][1]; cur_dirty1<=dirty[52][1]; cur_valid2<=valid[52][2]; cur_tag2<=tag[52][2]; cur_dirty2<=dirty[52][2]; cur_valid3<=valid[52][3]; cur_tag3<=tag[52][3]; cur_dirty3<=dirty[52][3]; cur_plru<=plru[52]; end
                    7'd53: begin cur_valid0<=valid[53][0]; cur_tag0<=tag[53][0]; cur_dirty0<=dirty[53][0]; cur_valid1<=valid[53][1]; cur_tag1<=tag[53][1]; cur_dirty1<=dirty[53][1]; cur_valid2<=valid[53][2]; cur_tag2<=tag[53][2]; cur_dirty2<=dirty[53][2]; cur_valid3<=valid[53][3]; cur_tag3<=tag[53][3]; cur_dirty3<=dirty[53][3]; cur_plru<=plru[53]; end
                    7'd54: begin cur_valid0<=valid[54][0]; cur_tag0<=tag[54][0]; cur_dirty0<=dirty[54][0]; cur_valid1<=valid[54][1]; cur_tag1<=tag[54][1]; cur_dirty1<=dirty[54][1]; cur_valid2<=valid[54][2]; cur_tag2<=tag[54][2]; cur_dirty2<=dirty[54][2]; cur_valid3<=valid[54][3]; cur_tag3<=tag[54][3]; cur_dirty3<=dirty[54][3]; cur_plru<=plru[54]; end
                    7'd55: begin cur_valid0<=valid[55][0]; cur_tag0<=tag[55][0]; cur_dirty0<=dirty[55][0]; cur_valid1<=valid[55][1]; cur_tag1<=tag[55][1]; cur_dirty1<=dirty[55][1]; cur_valid2<=valid[55][2]; cur_tag2<=tag[55][2]; cur_dirty2<=dirty[55][2]; cur_valid3<=valid[55][3]; cur_tag3<=tag[55][3]; cur_dirty3<=dirty[55][3]; cur_plru<=plru[55]; end
                    7'd56: begin cur_valid0<=valid[56][0]; cur_tag0<=tag[56][0]; cur_dirty0<=dirty[56][0]; cur_valid1<=valid[56][1]; cur_tag1<=tag[56][1]; cur_dirty1<=dirty[56][1]; cur_valid2<=valid[56][2]; cur_tag2<=tag[56][2]; cur_dirty2<=dirty[56][2]; cur_valid3<=valid[56][3]; cur_tag3<=tag[56][3]; cur_dirty3<=dirty[56][3]; cur_plru<=plru[56]; end
                    7'd57: begin cur_valid0<=valid[57][0]; cur_tag0<=tag[57][0]; cur_dirty0<=dirty[57][0]; cur_valid1<=valid[57][1]; cur_tag1<=tag[57][1]; cur_dirty1<=dirty[57][1]; cur_valid2<=valid[57][2]; cur_tag2<=tag[57][2]; cur_dirty2<=dirty[57][2]; cur_valid3<=valid[57][3]; cur_tag3<=tag[57][3]; cur_dirty3<=dirty[57][3]; cur_plru<=plru[57]; end
                    7'd58: begin cur_valid0<=valid[58][0]; cur_tag0<=tag[58][0]; cur_dirty0<=dirty[58][0]; cur_valid1<=valid[58][1]; cur_tag1<=tag[58][1]; cur_dirty1<=dirty[58][1]; cur_valid2<=valid[58][2]; cur_tag2<=tag[58][2]; cur_dirty2<=dirty[58][2]; cur_valid3<=valid[58][3]; cur_tag3<=tag[58][3]; cur_dirty3<=dirty[58][3]; cur_plru<=plru[58]; end
                    7'd59: begin cur_valid0<=valid[59][0]; cur_tag0<=tag[59][0]; cur_dirty0<=dirty[59][0]; cur_valid1<=valid[59][1]; cur_tag1<=tag[59][1]; cur_dirty1<=dirty[59][1]; cur_valid2<=valid[59][2]; cur_tag2<=tag[59][2]; cur_dirty2<=dirty[59][2]; cur_valid3<=valid[59][3]; cur_tag3<=tag[59][3]; cur_dirty3<=dirty[59][3]; cur_plru<=plru[59]; end
                    7'd60: begin cur_valid0<=valid[60][0]; cur_tag0<=tag[60][0]; cur_dirty0<=dirty[60][0]; cur_valid1<=valid[60][1]; cur_tag1<=tag[60][1]; cur_dirty1<=dirty[60][1]; cur_valid2<=valid[60][2]; cur_tag2<=tag[60][2]; cur_dirty2<=dirty[60][2]; cur_valid3<=valid[60][3]; cur_tag3<=tag[60][3]; cur_dirty3<=dirty[60][3]; cur_plru<=plru[60]; end
                    7'd61: begin cur_valid0<=valid[61][0]; cur_tag0<=tag[61][0]; cur_dirty0<=dirty[61][0]; cur_valid1<=valid[61][1]; cur_tag1<=tag[61][1]; cur_dirty1<=dirty[61][1]; cur_valid2<=valid[61][2]; cur_tag2<=tag[61][2]; cur_dirty2<=dirty[61][2]; cur_valid3<=valid[61][3]; cur_tag3<=tag[61][3]; cur_dirty3<=dirty[61][3]; cur_plru<=plru[61]; end
                    7'd62: begin cur_valid0<=valid[62][0]; cur_tag0<=tag[62][0]; cur_dirty0<=dirty[62][0]; cur_valid1<=valid[62][1]; cur_tag1<=tag[62][1]; cur_dirty1<=dirty[62][1]; cur_valid2<=valid[62][2]; cur_tag2<=tag[62][2]; cur_dirty2<=dirty[62][2]; cur_valid3<=valid[62][3]; cur_tag3<=tag[62][3]; cur_dirty3<=dirty[62][3]; cur_plru<=plru[62]; end
                    7'd63: begin cur_valid0<=valid[63][0]; cur_tag0<=tag[63][0]; cur_dirty0<=dirty[63][0]; cur_valid1<=valid[63][1]; cur_tag1<=tag[63][1]; cur_dirty1<=dirty[63][1]; cur_valid2<=valid[63][2]; cur_tag2<=tag[63][2]; cur_dirty2<=dirty[63][2]; cur_valid3<=valid[63][3]; cur_tag3<=tag[63][3]; cur_dirty3<=dirty[63][3]; cur_plru<=plru[63]; end
                    7'd64: begin cur_valid0<=valid[64][0]; cur_tag0<=tag[64][0]; cur_dirty0<=dirty[64][0]; cur_valid1<=valid[64][1]; cur_tag1<=tag[64][1]; cur_dirty1<=dirty[64][1]; cur_valid2<=valid[64][2]; cur_tag2<=tag[64][2]; cur_dirty2<=dirty[64][2]; cur_valid3<=valid[64][3]; cur_tag3<=tag[64][3]; cur_dirty3<=dirty[64][3]; cur_plru<=plru[64]; end
                    7'd65: begin cur_valid0<=valid[65][0]; cur_tag0<=tag[65][0]; cur_dirty0<=dirty[65][0]; cur_valid1<=valid[65][1]; cur_tag1<=tag[65][1]; cur_dirty1<=dirty[65][1]; cur_valid2<=valid[65][2]; cur_tag2<=tag[65][2]; cur_dirty2<=dirty[65][2]; cur_valid3<=valid[65][3]; cur_tag3<=tag[65][3]; cur_dirty3<=dirty[65][3]; cur_plru<=plru[65]; end
                    7'd66: begin cur_valid0<=valid[66][0]; cur_tag0<=tag[66][0]; cur_dirty0<=dirty[66][0]; cur_valid1<=valid[66][1]; cur_tag1<=tag[66][1]; cur_dirty1<=dirty[66][1]; cur_valid2<=valid[66][2]; cur_tag2<=tag[66][2]; cur_dirty2<=dirty[66][2]; cur_valid3<=valid[66][3]; cur_tag3<=tag[66][3]; cur_dirty3<=dirty[66][3]; cur_plru<=plru[66]; end
                    7'd67: begin cur_valid0<=valid[67][0]; cur_tag0<=tag[67][0]; cur_dirty0<=dirty[67][0]; cur_valid1<=valid[67][1]; cur_tag1<=tag[67][1]; cur_dirty1<=dirty[67][1]; cur_valid2<=valid[67][2]; cur_tag2<=tag[67][2]; cur_dirty2<=dirty[67][2]; cur_valid3<=valid[67][3]; cur_tag3<=tag[67][3]; cur_dirty3<=dirty[67][3]; cur_plru<=plru[67]; end
                    7'd68: begin cur_valid0<=valid[68][0]; cur_tag0<=tag[68][0]; cur_dirty0<=dirty[68][0]; cur_valid1<=valid[68][1]; cur_tag1<=tag[68][1]; cur_dirty1<=dirty[68][1]; cur_valid2<=valid[68][2]; cur_tag2<=tag[68][2]; cur_dirty2<=dirty[68][2]; cur_valid3<=valid[68][3]; cur_tag3<=tag[68][3]; cur_dirty3<=dirty[68][3]; cur_plru<=plru[68]; end
                    7'd69: begin cur_valid0<=valid[69][0]; cur_tag0<=tag[69][0]; cur_dirty0<=dirty[69][0]; cur_valid1<=valid[69][1]; cur_tag1<=tag[69][1]; cur_dirty1<=dirty[69][1]; cur_valid2<=valid[69][2]; cur_tag2<=tag[69][2]; cur_dirty2<=dirty[69][2]; cur_valid3<=valid[69][3]; cur_tag3<=tag[69][3]; cur_dirty3<=dirty[69][3]; cur_plru<=plru[69]; end
                    7'd70: begin cur_valid0<=valid[70][0]; cur_tag0<=tag[70][0]; cur_dirty0<=dirty[70][0]; cur_valid1<=valid[70][1]; cur_tag1<=tag[70][1]; cur_dirty1<=dirty[70][1]; cur_valid2<=valid[70][2]; cur_tag2<=tag[70][2]; cur_dirty2<=dirty[70][2]; cur_valid3<=valid[70][3]; cur_tag3<=tag[70][3]; cur_dirty3<=dirty[70][3]; cur_plru<=plru[70]; end
                    7'd71: begin cur_valid0<=valid[71][0]; cur_tag0<=tag[71][0]; cur_dirty0<=dirty[71][0]; cur_valid1<=valid[71][1]; cur_tag1<=tag[71][1]; cur_dirty1<=dirty[71][1]; cur_valid2<=valid[71][2]; cur_tag2<=tag[71][2]; cur_dirty2<=dirty[71][2]; cur_valid3<=valid[71][3]; cur_tag3<=tag[71][3]; cur_dirty3<=dirty[71][3]; cur_plru<=plru[71]; end
                    7'd72: begin cur_valid0<=valid[72][0]; cur_tag0<=tag[72][0]; cur_dirty0<=dirty[72][0]; cur_valid1<=valid[72][1]; cur_tag1<=tag[72][1]; cur_dirty1<=dirty[72][1]; cur_valid2<=valid[72][2]; cur_tag2<=tag[72][2]; cur_dirty2<=dirty[72][2]; cur_valid3<=valid[72][3]; cur_tag3<=tag[72][3]; cur_dirty3<=dirty[72][3]; cur_plru<=plru[72]; end
                    7'd73: begin cur_valid0<=valid[73][0]; cur_tag0<=tag[73][0]; cur_dirty0<=dirty[73][0]; cur_valid1<=valid[73][1]; cur_tag1<=tag[73][1]; cur_dirty1<=dirty[73][1]; cur_valid2<=valid[73][2]; cur_tag2<=tag[73][2]; cur_dirty2<=dirty[73][2]; cur_valid3<=valid[73][3]; cur_tag3<=tag[73][3]; cur_dirty3<=dirty[73][3]; cur_plru<=plru[73]; end
                    7'd74: begin cur_valid0<=valid[74][0]; cur_tag0<=tag[74][0]; cur_dirty0<=dirty[74][0]; cur_valid1<=valid[74][1]; cur_tag1<=tag[74][1]; cur_dirty1<=dirty[74][1]; cur_valid2<=valid[74][2]; cur_tag2<=tag[74][2]; cur_dirty2<=dirty[74][2]; cur_valid3<=valid[74][3]; cur_tag3<=tag[74][3]; cur_dirty3<=dirty[74][3]; cur_plru<=plru[74]; end
                    7'd75: begin cur_valid0<=valid[75][0]; cur_tag0<=tag[75][0]; cur_dirty0<=dirty[75][0]; cur_valid1<=valid[75][1]; cur_tag1<=tag[75][1]; cur_dirty1<=dirty[75][1]; cur_valid2<=valid[75][2]; cur_tag2<=tag[75][2]; cur_dirty2<=dirty[75][2]; cur_valid3<=valid[75][3]; cur_tag3<=tag[75][3]; cur_dirty3<=dirty[75][3]; cur_plru<=plru[75]; end
                    7'd76: begin cur_valid0<=valid[76][0]; cur_tag0<=tag[76][0]; cur_dirty0<=dirty[76][0]; cur_valid1<=valid[76][1]; cur_tag1<=tag[76][1]; cur_dirty1<=dirty[76][1]; cur_valid2<=valid[76][2]; cur_tag2<=tag[76][2]; cur_dirty2<=dirty[76][2]; cur_valid3<=valid[76][3]; cur_tag3<=tag[76][3]; cur_dirty3<=dirty[76][3]; cur_plru<=plru[76]; end
                    7'd77: begin cur_valid0<=valid[77][0]; cur_tag0<=tag[77][0]; cur_dirty0<=dirty[77][0]; cur_valid1<=valid[77][1]; cur_tag1<=tag[77][1]; cur_dirty1<=dirty[77][1]; cur_valid2<=valid[77][2]; cur_tag2<=tag[77][2]; cur_dirty2<=dirty[77][2]; cur_valid3<=valid[77][3]; cur_tag3<=tag[77][3]; cur_dirty3<=dirty[77][3]; cur_plru<=plru[77]; end
                    7'd78: begin cur_valid0<=valid[78][0]; cur_tag0<=tag[78][0]; cur_dirty0<=dirty[78][0]; cur_valid1<=valid[78][1]; cur_tag1<=tag[78][1]; cur_dirty1<=dirty[78][1]; cur_valid2<=valid[78][2]; cur_tag2<=tag[78][2]; cur_dirty2<=dirty[78][2]; cur_valid3<=valid[78][3]; cur_tag3<=tag[78][3]; cur_dirty3<=dirty[78][3]; cur_plru<=plru[78]; end
                    7'd79: begin cur_valid0<=valid[79][0]; cur_tag0<=tag[79][0]; cur_dirty0<=dirty[79][0]; cur_valid1<=valid[79][1]; cur_tag1<=tag[79][1]; cur_dirty1<=dirty[79][1]; cur_valid2<=valid[79][2]; cur_tag2<=tag[79][2]; cur_dirty2<=dirty[79][2]; cur_valid3<=valid[79][3]; cur_tag3<=tag[79][3]; cur_dirty3<=dirty[79][3]; cur_plru<=plru[79]; end
                    7'd80: begin cur_valid0<=valid[80][0]; cur_tag0<=tag[80][0]; cur_dirty0<=dirty[80][0]; cur_valid1<=valid[80][1]; cur_tag1<=tag[80][1]; cur_dirty1<=dirty[80][1]; cur_valid2<=valid[80][2]; cur_tag2<=tag[80][2]; cur_dirty2<=dirty[80][2]; cur_valid3<=valid[80][3]; cur_tag3<=tag[80][3]; cur_dirty3<=dirty[80][3]; cur_plru<=plru[80]; end
                    7'd81: begin cur_valid0<=valid[81][0]; cur_tag0<=tag[81][0]; cur_dirty0<=dirty[81][0]; cur_valid1<=valid[81][1]; cur_tag1<=tag[81][1]; cur_dirty1<=dirty[81][1]; cur_valid2<=valid[81][2]; cur_tag2<=tag[81][2]; cur_dirty2<=dirty[81][2]; cur_valid3<=valid[81][3]; cur_tag3<=tag[81][3]; cur_dirty3<=dirty[81][3]; cur_plru<=plru[81]; end
                    7'd82: begin cur_valid0<=valid[82][0]; cur_tag0<=tag[82][0]; cur_dirty0<=dirty[82][0]; cur_valid1<=valid[82][1]; cur_tag1<=tag[82][1]; cur_dirty1<=dirty[82][1]; cur_valid2<=valid[82][2]; cur_tag2<=tag[82][2]; cur_dirty2<=dirty[82][2]; cur_valid3<=valid[82][3]; cur_tag3<=tag[82][3]; cur_dirty3<=dirty[82][3]; cur_plru<=plru[82]; end
                    7'd83: begin cur_valid0<=valid[83][0]; cur_tag0<=tag[83][0]; cur_dirty0<=dirty[83][0]; cur_valid1<=valid[83][1]; cur_tag1<=tag[83][1]; cur_dirty1<=dirty[83][1]; cur_valid2<=valid[83][2]; cur_tag2<=tag[83][2]; cur_dirty2<=dirty[83][2]; cur_valid3<=valid[83][3]; cur_tag3<=tag[83][3]; cur_dirty3<=dirty[83][3]; cur_plru<=plru[83]; end
                    7'd84: begin cur_valid0<=valid[84][0]; cur_tag0<=tag[84][0]; cur_dirty0<=dirty[84][0]; cur_valid1<=valid[84][1]; cur_tag1<=tag[84][1]; cur_dirty1<=dirty[84][1]; cur_valid2<=valid[84][2]; cur_tag2<=tag[84][2]; cur_dirty2<=dirty[84][2]; cur_valid3<=valid[84][3]; cur_tag3<=tag[84][3]; cur_dirty3<=dirty[84][3]; cur_plru<=plru[84]; end
                    7'd85: begin cur_valid0<=valid[85][0]; cur_tag0<=tag[85][0]; cur_dirty0<=dirty[85][0]; cur_valid1<=valid[85][1]; cur_tag1<=tag[85][1]; cur_dirty1<=dirty[85][1]; cur_valid2<=valid[85][2]; cur_tag2<=tag[85][2]; cur_dirty2<=dirty[85][2]; cur_valid3<=valid[85][3]; cur_tag3<=tag[85][3]; cur_dirty3<=dirty[85][3]; cur_plru<=plru[85]; end
                    7'd86: begin cur_valid0<=valid[86][0]; cur_tag0<=tag[86][0]; cur_dirty0<=dirty[86][0]; cur_valid1<=valid[86][1]; cur_tag1<=tag[86][1]; cur_dirty1<=dirty[86][1]; cur_valid2<=valid[86][2]; cur_tag2<=tag[86][2]; cur_dirty2<=dirty[86][2]; cur_valid3<=valid[86][3]; cur_tag3<=tag[86][3]; cur_dirty3<=dirty[86][3]; cur_plru<=plru[86]; end
                    7'd87: begin cur_valid0<=valid[87][0]; cur_tag0<=tag[87][0]; cur_dirty0<=dirty[87][0]; cur_valid1<=valid[87][1]; cur_tag1<=tag[87][1]; cur_dirty1<=dirty[87][1]; cur_valid2<=valid[87][2]; cur_tag2<=tag[87][2]; cur_dirty2<=dirty[87][2]; cur_valid3<=valid[87][3]; cur_tag3<=tag[87][3]; cur_dirty3<=dirty[87][3]; cur_plru<=plru[87]; end
                    7'd88: begin cur_valid0<=valid[88][0]; cur_tag0<=tag[88][0]; cur_dirty0<=dirty[88][0]; cur_valid1<=valid[88][1]; cur_tag1<=tag[88][1]; cur_dirty1<=dirty[88][1]; cur_valid2<=valid[88][2]; cur_tag2<=tag[88][2]; cur_dirty2<=dirty[88][2]; cur_valid3<=valid[88][3]; cur_tag3<=tag[88][3]; cur_dirty3<=dirty[88][3]; cur_plru<=plru[88]; end
                    7'd89: begin cur_valid0<=valid[89][0]; cur_tag0<=tag[89][0]; cur_dirty0<=dirty[89][0]; cur_valid1<=valid[89][1]; cur_tag1<=tag[89][1]; cur_dirty1<=dirty[89][1]; cur_valid2<=valid[89][2]; cur_tag2<=tag[89][2]; cur_dirty2<=dirty[89][2]; cur_valid3<=valid[89][3]; cur_tag3<=tag[89][3]; cur_dirty3<=dirty[89][3]; cur_plru<=plru[89]; end
                    7'd90: begin cur_valid0<=valid[90][0]; cur_tag0<=tag[90][0]; cur_dirty0<=dirty[90][0]; cur_valid1<=valid[90][1]; cur_tag1<=tag[90][1]; cur_dirty1<=dirty[90][1]; cur_valid2<=valid[90][2]; cur_tag2<=tag[90][2]; cur_dirty2<=dirty[90][2]; cur_valid3<=valid[90][3]; cur_tag3<=tag[90][3]; cur_dirty3<=dirty[90][3]; cur_plru<=plru[90]; end
                    7'd91: begin cur_valid0<=valid[91][0]; cur_tag0<=tag[91][0]; cur_dirty0<=dirty[91][0]; cur_valid1<=valid[91][1]; cur_tag1<=tag[91][1]; cur_dirty1<=dirty[91][1]; cur_valid2<=valid[91][2]; cur_tag2<=tag[91][2]; cur_dirty2<=dirty[91][2]; cur_valid3<=valid[91][3]; cur_tag3<=tag[91][3]; cur_dirty3<=dirty[91][3]; cur_plru<=plru[91]; end
                    7'd92: begin cur_valid0<=valid[92][0]; cur_tag0<=tag[92][0]; cur_dirty0<=dirty[92][0]; cur_valid1<=valid[92][1]; cur_tag1<=tag[92][1]; cur_dirty1<=dirty[92][1]; cur_valid2<=valid[92][2]; cur_tag2<=tag[92][2]; cur_dirty2<=dirty[92][2]; cur_valid3<=valid[92][3]; cur_tag3<=tag[92][3]; cur_dirty3<=dirty[92][3]; cur_plru<=plru[92]; end
                    7'd93: begin cur_valid0<=valid[93][0]; cur_tag0<=tag[93][0]; cur_dirty0<=dirty[93][0]; cur_valid1<=valid[93][1]; cur_tag1<=tag[93][1]; cur_dirty1<=dirty[93][1]; cur_valid2<=valid[93][2]; cur_tag2<=tag[93][2]; cur_dirty2<=dirty[93][2]; cur_valid3<=valid[93][3]; cur_tag3<=tag[93][3]; cur_dirty3<=dirty[93][3]; cur_plru<=plru[93]; end
                    7'd94: begin cur_valid0<=valid[94][0]; cur_tag0<=tag[94][0]; cur_dirty0<=dirty[94][0]; cur_valid1<=valid[94][1]; cur_tag1<=tag[94][1]; cur_dirty1<=dirty[94][1]; cur_valid2<=valid[94][2]; cur_tag2<=tag[94][2]; cur_dirty2<=dirty[94][2]; cur_valid3<=valid[94][3]; cur_tag3<=tag[94][3]; cur_dirty3<=dirty[94][3]; cur_plru<=plru[94]; end
                    7'd95: begin cur_valid0<=valid[95][0]; cur_tag0<=tag[95][0]; cur_dirty0<=dirty[95][0]; cur_valid1<=valid[95][1]; cur_tag1<=tag[95][1]; cur_dirty1<=dirty[95][1]; cur_valid2<=valid[95][2]; cur_tag2<=tag[95][2]; cur_dirty2<=dirty[95][2]; cur_valid3<=valid[95][3]; cur_tag3<=tag[95][3]; cur_dirty3<=dirty[95][3]; cur_plru<=plru[95]; end
                    7'd96: begin cur_valid0<=valid[96][0]; cur_tag0<=tag[96][0]; cur_dirty0<=dirty[96][0]; cur_valid1<=valid[96][1]; cur_tag1<=tag[96][1]; cur_dirty1<=dirty[96][1]; cur_valid2<=valid[96][2]; cur_tag2<=tag[96][2]; cur_dirty2<=dirty[96][2]; cur_valid3<=valid[96][3]; cur_tag3<=tag[96][3]; cur_dirty3<=dirty[96][3]; cur_plru<=plru[96]; end
                    7'd97: begin cur_valid0<=valid[97][0]; cur_tag0<=tag[97][0]; cur_dirty0<=dirty[97][0]; cur_valid1<=valid[97][1]; cur_tag1<=tag[97][1]; cur_dirty1<=dirty[97][1]; cur_valid2<=valid[97][2]; cur_tag2<=tag[97][2]; cur_dirty2<=dirty[97][2]; cur_valid3<=valid[97][3]; cur_tag3<=tag[97][3]; cur_dirty3<=dirty[97][3]; cur_plru<=plru[97]; end
                    7'd98: begin cur_valid0<=valid[98][0]; cur_tag0<=tag[98][0]; cur_dirty0<=dirty[98][0]; cur_valid1<=valid[98][1]; cur_tag1<=tag[98][1]; cur_dirty1<=dirty[98][1]; cur_valid2<=valid[98][2]; cur_tag2<=tag[98][2]; cur_dirty2<=dirty[98][2]; cur_valid3<=valid[98][3]; cur_tag3<=tag[98][3]; cur_dirty3<=dirty[98][3]; cur_plru<=plru[98]; end
                    7'd99: begin cur_valid0<=valid[99][0]; cur_tag0<=tag[99][0]; cur_dirty0<=dirty[99][0]; cur_valid1<=valid[99][1]; cur_tag1<=tag[99][1]; cur_dirty1<=dirty[99][1]; cur_valid2<=valid[99][2]; cur_tag2<=tag[99][2]; cur_dirty2<=dirty[99][2]; cur_valid3<=valid[99][3]; cur_tag3<=tag[99][3]; cur_dirty3<=dirty[99][3]; cur_plru<=plru[99]; end
                    7'd100: begin cur_valid0<=valid[100][0]; cur_tag0<=tag[100][0]; cur_dirty0<=dirty[100][0]; cur_valid1<=valid[100][1]; cur_tag1<=tag[100][1]; cur_dirty1<=dirty[100][1]; cur_valid2<=valid[100][2]; cur_tag2<=tag[100][2]; cur_dirty2<=dirty[100][2]; cur_valid3<=valid[100][3]; cur_tag3<=tag[100][3]; cur_dirty3<=dirty[100][3]; cur_plru<=plru[100]; end
                    7'd101: begin cur_valid0<=valid[101][0]; cur_tag0<=tag[101][0]; cur_dirty0<=dirty[101][0]; cur_valid1<=valid[101][1]; cur_tag1<=tag[101][1]; cur_dirty1<=dirty[101][1]; cur_valid2<=valid[101][2]; cur_tag2<=tag[101][2]; cur_dirty2<=dirty[101][2]; cur_valid3<=valid[101][3]; cur_tag3<=tag[101][3]; cur_dirty3<=dirty[101][3]; cur_plru<=plru[101]; end
                    7'd102: begin cur_valid0<=valid[102][0]; cur_tag0<=tag[102][0]; cur_dirty0<=dirty[102][0]; cur_valid1<=valid[102][1]; cur_tag1<=tag[102][1]; cur_dirty1<=dirty[102][1]; cur_valid2<=valid[102][2]; cur_tag2<=tag[102][2]; cur_dirty2<=dirty[102][2]; cur_valid3<=valid[102][3]; cur_tag3<=tag[102][3]; cur_dirty3<=dirty[102][3]; cur_plru<=plru[102]; end
                    7'd103: begin cur_valid0<=valid[103][0]; cur_tag0<=tag[103][0]; cur_dirty0<=dirty[103][0]; cur_valid1<=valid[103][1]; cur_tag1<=tag[103][1]; cur_dirty1<=dirty[103][1]; cur_valid2<=valid[103][2]; cur_tag2<=tag[103][2]; cur_dirty2<=dirty[103][2]; cur_valid3<=valid[103][3]; cur_tag3<=tag[103][3]; cur_dirty3<=dirty[103][3]; cur_plru<=plru[103]; end
                    7'd104: begin cur_valid0<=valid[104][0]; cur_tag0<=tag[104][0]; cur_dirty0<=dirty[104][0]; cur_valid1<=valid[104][1]; cur_tag1<=tag[104][1]; cur_dirty1<=dirty[104][1]; cur_valid2<=valid[104][2]; cur_tag2<=tag[104][2]; cur_dirty2<=dirty[104][2]; cur_valid3<=valid[104][3]; cur_tag3<=tag[104][3]; cur_dirty3<=dirty[104][3]; cur_plru<=plru[104]; end
                    7'd105: begin cur_valid0<=valid[105][0]; cur_tag0<=tag[105][0]; cur_dirty0<=dirty[105][0]; cur_valid1<=valid[105][1]; cur_tag1<=tag[105][1]; cur_dirty1<=dirty[105][1]; cur_valid2<=valid[105][2]; cur_tag2<=tag[105][2]; cur_dirty2<=dirty[105][2]; cur_valid3<=valid[105][3]; cur_tag3<=tag[105][3]; cur_dirty3<=dirty[105][3]; cur_plru<=plru[105]; end
                    7'd106: begin cur_valid0<=valid[106][0]; cur_tag0<=tag[106][0]; cur_dirty0<=dirty[106][0]; cur_valid1<=valid[106][1]; cur_tag1<=tag[106][1]; cur_dirty1<=dirty[106][1]; cur_valid2<=valid[106][2]; cur_tag2<=tag[106][2]; cur_dirty2<=dirty[106][2]; cur_valid3<=valid[106][3]; cur_tag3<=tag[106][3]; cur_dirty3<=dirty[106][3]; cur_plru<=plru[106]; end
                    7'd107: begin cur_valid0<=valid[107][0]; cur_tag0<=tag[107][0]; cur_dirty0<=dirty[107][0]; cur_valid1<=valid[107][1]; cur_tag1<=tag[107][1]; cur_dirty1<=dirty[107][1]; cur_valid2<=valid[107][2]; cur_tag2<=tag[107][2]; cur_dirty2<=dirty[107][2]; cur_valid3<=valid[107][3]; cur_tag3<=tag[107][3]; cur_dirty3<=dirty[107][3]; cur_plru<=plru[107]; end
                    7'd108: begin cur_valid0<=valid[108][0]; cur_tag0<=tag[108][0]; cur_dirty0<=dirty[108][0]; cur_valid1<=valid[108][1]; cur_tag1<=tag[108][1]; cur_dirty1<=dirty[108][1]; cur_valid2<=valid[108][2]; cur_tag2<=tag[108][2]; cur_dirty2<=dirty[108][2]; cur_valid3<=valid[108][3]; cur_tag3<=tag[108][3]; cur_dirty3<=dirty[108][3]; cur_plru<=plru[108]; end
                    7'd109: begin cur_valid0<=valid[109][0]; cur_tag0<=tag[109][0]; cur_dirty0<=dirty[109][0]; cur_valid1<=valid[109][1]; cur_tag1<=tag[109][1]; cur_dirty1<=dirty[109][1]; cur_valid2<=valid[109][2]; cur_tag2<=tag[109][2]; cur_dirty2<=dirty[109][2]; cur_valid3<=valid[109][3]; cur_tag3<=tag[109][3]; cur_dirty3<=dirty[109][3]; cur_plru<=plru[109]; end
                    7'd110: begin cur_valid0<=valid[110][0]; cur_tag0<=tag[110][0]; cur_dirty0<=dirty[110][0]; cur_valid1<=valid[110][1]; cur_tag1<=tag[110][1]; cur_dirty1<=dirty[110][1]; cur_valid2<=valid[110][2]; cur_tag2<=tag[110][2]; cur_dirty2<=dirty[110][2]; cur_valid3<=valid[110][3]; cur_tag3<=tag[110][3]; cur_dirty3<=dirty[110][3]; cur_plru<=plru[110]; end
                    7'd111: begin cur_valid0<=valid[111][0]; cur_tag0<=tag[111][0]; cur_dirty0<=dirty[111][0]; cur_valid1<=valid[111][1]; cur_tag1<=tag[111][1]; cur_dirty1<=dirty[111][1]; cur_valid2<=valid[111][2]; cur_tag2<=tag[111][2]; cur_dirty2<=dirty[111][2]; cur_valid3<=valid[111][3]; cur_tag3<=tag[111][3]; cur_dirty3<=dirty[111][3]; cur_plru<=plru[111]; end
                    7'd112: begin cur_valid0<=valid[112][0]; cur_tag0<=tag[112][0]; cur_dirty0<=dirty[112][0]; cur_valid1<=valid[112][1]; cur_tag1<=tag[112][1]; cur_dirty1<=dirty[112][1]; cur_valid2<=valid[112][2]; cur_tag2<=tag[112][2]; cur_dirty2<=dirty[112][2]; cur_valid3<=valid[112][3]; cur_tag3<=tag[112][3]; cur_dirty3<=dirty[112][3]; cur_plru<=plru[112]; end
                    7'd113: begin cur_valid0<=valid[113][0]; cur_tag0<=tag[113][0]; cur_dirty0<=dirty[113][0]; cur_valid1<=valid[113][1]; cur_tag1<=tag[113][1]; cur_dirty1<=dirty[113][1]; cur_valid2<=valid[113][2]; cur_tag2<=tag[113][2]; cur_dirty2<=dirty[113][2]; cur_valid3<=valid[113][3]; cur_tag3<=tag[113][3]; cur_dirty3<=dirty[113][3]; cur_plru<=plru[113]; end
                    7'd114: begin cur_valid0<=valid[114][0]; cur_tag0<=tag[114][0]; cur_dirty0<=dirty[114][0]; cur_valid1<=valid[114][1]; cur_tag1<=tag[114][1]; cur_dirty1<=dirty[114][1]; cur_valid2<=valid[114][2]; cur_tag2<=tag[114][2]; cur_dirty2<=dirty[114][2]; cur_valid3<=valid[114][3]; cur_tag3<=tag[114][3]; cur_dirty3<=dirty[114][3]; cur_plru<=plru[114]; end
                    7'd115: begin cur_valid0<=valid[115][0]; cur_tag0<=tag[115][0]; cur_dirty0<=dirty[115][0]; cur_valid1<=valid[115][1]; cur_tag1<=tag[115][1]; cur_dirty1<=dirty[115][1]; cur_valid2<=valid[115][2]; cur_tag2<=tag[115][2]; cur_dirty2<=dirty[115][2]; cur_valid3<=valid[115][3]; cur_tag3<=tag[115][3]; cur_dirty3<=dirty[115][3]; cur_plru<=plru[115]; end
                    7'd116: begin cur_valid0<=valid[116][0]; cur_tag0<=tag[116][0]; cur_dirty0<=dirty[116][0]; cur_valid1<=valid[116][1]; cur_tag1<=tag[116][1]; cur_dirty1<=dirty[116][1]; cur_valid2<=valid[116][2]; cur_tag2<=tag[116][2]; cur_dirty2<=dirty[116][2]; cur_valid3<=valid[116][3]; cur_tag3<=tag[116][3]; cur_dirty3<=dirty[116][3]; cur_plru<=plru[116]; end
                    7'd117: begin cur_valid0<=valid[117][0]; cur_tag0<=tag[117][0]; cur_dirty0<=dirty[117][0]; cur_valid1<=valid[117][1]; cur_tag1<=tag[117][1]; cur_dirty1<=dirty[117][1]; cur_valid2<=valid[117][2]; cur_tag2<=tag[117][2]; cur_dirty2<=dirty[117][2]; cur_valid3<=valid[117][3]; cur_tag3<=tag[117][3]; cur_dirty3<=dirty[117][3]; cur_plru<=plru[117]; end
                    7'd118: begin cur_valid0<=valid[118][0]; cur_tag0<=tag[118][0]; cur_dirty0<=dirty[118][0]; cur_valid1<=valid[118][1]; cur_tag1<=tag[118][1]; cur_dirty1<=dirty[118][1]; cur_valid2<=valid[118][2]; cur_tag2<=tag[118][2]; cur_dirty2<=dirty[118][2]; cur_valid3<=valid[118][3]; cur_tag3<=tag[118][3]; cur_dirty3<=dirty[118][3]; cur_plru<=plru[118]; end
                    7'd119: begin cur_valid0<=valid[119][0]; cur_tag0<=tag[119][0]; cur_dirty0<=dirty[119][0]; cur_valid1<=valid[119][1]; cur_tag1<=tag[119][1]; cur_dirty1<=dirty[119][1]; cur_valid2<=valid[119][2]; cur_tag2<=tag[119][2]; cur_dirty2<=dirty[119][2]; cur_valid3<=valid[119][3]; cur_tag3<=tag[119][3]; cur_dirty3<=dirty[119][3]; cur_plru<=plru[119]; end
                    7'd120: begin cur_valid0<=valid[120][0]; cur_tag0<=tag[120][0]; cur_dirty0<=dirty[120][0]; cur_valid1<=valid[120][1]; cur_tag1<=tag[120][1]; cur_dirty1<=dirty[120][1]; cur_valid2<=valid[120][2]; cur_tag2<=tag[120][2]; cur_dirty2<=dirty[120][2]; cur_valid3<=valid[120][3]; cur_tag3<=tag[120][3]; cur_dirty3<=dirty[120][3]; cur_plru<=plru[120]; end
                    7'd121: begin cur_valid0<=valid[121][0]; cur_tag0<=tag[121][0]; cur_dirty0<=dirty[121][0]; cur_valid1<=valid[121][1]; cur_tag1<=tag[121][1]; cur_dirty1<=dirty[121][1]; cur_valid2<=valid[121][2]; cur_tag2<=tag[121][2]; cur_dirty2<=dirty[121][2]; cur_valid3<=valid[121][3]; cur_tag3<=tag[121][3]; cur_dirty3<=dirty[121][3]; cur_plru<=plru[121]; end
                    7'd122: begin cur_valid0<=valid[122][0]; cur_tag0<=tag[122][0]; cur_dirty0<=dirty[122][0]; cur_valid1<=valid[122][1]; cur_tag1<=tag[122][1]; cur_dirty1<=dirty[122][1]; cur_valid2<=valid[122][2]; cur_tag2<=tag[122][2]; cur_dirty2<=dirty[122][2]; cur_valid3<=valid[122][3]; cur_tag3<=tag[122][3]; cur_dirty3<=dirty[122][3]; cur_plru<=plru[122]; end
                    7'd123: begin cur_valid0<=valid[123][0]; cur_tag0<=tag[123][0]; cur_dirty0<=dirty[123][0]; cur_valid1<=valid[123][1]; cur_tag1<=tag[123][1]; cur_dirty1<=dirty[123][1]; cur_valid2<=valid[123][2]; cur_tag2<=tag[123][2]; cur_dirty2<=dirty[123][2]; cur_valid3<=valid[123][3]; cur_tag3<=tag[123][3]; cur_dirty3<=dirty[123][3]; cur_plru<=plru[123]; end
                    7'd124: begin cur_valid0<=valid[124][0]; cur_tag0<=tag[124][0]; cur_dirty0<=dirty[124][0]; cur_valid1<=valid[124][1]; cur_tag1<=tag[124][1]; cur_dirty1<=dirty[124][1]; cur_valid2<=valid[124][2]; cur_tag2<=tag[124][2]; cur_dirty2<=dirty[124][2]; cur_valid3<=valid[124][3]; cur_tag3<=tag[124][3]; cur_dirty3<=dirty[124][3]; cur_plru<=plru[124]; end
                    7'd125: begin cur_valid0<=valid[125][0]; cur_tag0<=tag[125][0]; cur_dirty0<=dirty[125][0]; cur_valid1<=valid[125][1]; cur_tag1<=tag[125][1]; cur_dirty1<=dirty[125][1]; cur_valid2<=valid[125][2]; cur_tag2<=tag[125][2]; cur_dirty2<=dirty[125][2]; cur_valid3<=valid[125][3]; cur_tag3<=tag[125][3]; cur_dirty3<=dirty[125][3]; cur_plru<=plru[125]; end
                    7'd126: begin cur_valid0<=valid[126][0]; cur_tag0<=tag[126][0]; cur_dirty0<=dirty[126][0]; cur_valid1<=valid[126][1]; cur_tag1<=tag[126][1]; cur_dirty1<=dirty[126][1]; cur_valid2<=valid[126][2]; cur_tag2<=tag[126][2]; cur_dirty2<=dirty[126][2]; cur_valid3<=valid[126][3]; cur_tag3<=tag[126][3]; cur_dirty3<=dirty[126][3]; cur_plru<=plru[126]; end
                    7'd127: begin cur_valid0<=valid[127][0]; cur_tag0<=tag[127][0]; cur_dirty0<=dirty[127][0]; cur_valid1<=valid[127][1]; cur_tag1<=tag[127][1]; cur_dirty1<=dirty[127][1]; cur_valid2<=valid[127][2]; cur_tag2<=tag[127][2]; cur_dirty2<=dirty[127][2]; cur_valid3<=valid[127][3]; cur_tag3<=tag[127][3]; cur_dirty3<=dirty[127][3]; cur_plru<=plru[127]; end
                endcase
                state <= S_DECIDE;
            end

            // Con cur_* ya estables, hit_way y victim_way son válidos.
            // Decidir hit vs miss y actuar.
            S_DECIDE: begin
                if (l2_hit) begin
                    case (hit_way)
                        2'd0: plru[latched_index] <= {1'b1, 1'b1, plru[latched_index][0]};
                        2'd1: plru[latched_index] <= {1'b1, 1'b0, plru[latched_index][0]};
                        2'd2: plru[latched_index] <= {1'b0, plru[latched_index][1], 1'b1};
                        2'd3: plru[latched_index] <= {1'b0, plru[latched_index][1], 1'b0};
                    endcase
                    active_way  <= hit_way;
                    hit_counter <= HIT_LATENCY[3:0] - 1;

                    if (latched_wr_en) begin
                        // Write hit: actualizar la palabra específica y marcar dirty
                        case (hit_way)
                            2'd0: case (latched_offset)
                                3'd0: data[latched_index][0][0] <= latched_write_word; 3'd1: data[latched_index][0][1] <= latched_write_word;
                                3'd2: data[latched_index][0][2] <= latched_write_word; 3'd3: data[latched_index][0][3] <= latched_write_word;
                                3'd4: data[latched_index][0][4] <= latched_write_word; 3'd5: data[latched_index][0][5] <= latched_write_word;
                                3'd6: data[latched_index][0][6] <= latched_write_word; 3'd7: data[latched_index][0][7] <= latched_write_word;
                            endcase
                            2'd1: case (latched_offset)
                                3'd0: data[latched_index][1][0] <= latched_write_word; 3'd1: data[latched_index][1][1] <= latched_write_word;
                                3'd2: data[latched_index][1][2] <= latched_write_word; 3'd3: data[latched_index][1][3] <= latched_write_word;
                                3'd4: data[latched_index][1][4] <= latched_write_word; 3'd5: data[latched_index][1][5] <= latched_write_word;
                                3'd6: data[latched_index][1][6] <= latched_write_word; 3'd7: data[latched_index][1][7] <= latched_write_word;
                            endcase
                            2'd2: case (latched_offset)
                                3'd0: data[latched_index][2][0] <= latched_write_word; 3'd1: data[latched_index][2][1] <= latched_write_word;
                                3'd2: data[latched_index][2][2] <= latched_write_word; 3'd3: data[latched_index][2][3] <= latched_write_word;
                                3'd4: data[latched_index][2][4] <= latched_write_word; 3'd5: data[latched_index][2][5] <= latched_write_word;
                                3'd6: data[latched_index][2][6] <= latched_write_word; 3'd7: data[latched_index][2][7] <= latched_write_word;
                            endcase
                            2'd3: case (latched_offset)
                                3'd0: data[latched_index][3][0] <= latched_write_word; 3'd1: data[latched_index][3][1] <= latched_write_word;
                                3'd2: data[latched_index][3][2] <= latched_write_word; 3'd3: data[latched_index][3][3] <= latched_write_word;
                                3'd4: data[latched_index][3][4] <= latched_write_word; 3'd5: data[latched_index][3][5] <= latched_write_word;
                                3'd6: data[latched_index][3][6] <= latched_write_word; 3'd7: data[latched_index][3][7] <= latched_write_word;
                            endcase
                        endcase
                        dirty[latched_index][hit_way] <= 1'b1;
                        l2_write_hits <= l2_write_hits + 1;
                    end else begin
                        l2_read_hits <= l2_read_hits + 1;
                    end
                    state <= S_HIT_WAIT;

                end else begin
                    // Miss: evicar la víctima dirty al write buffer si aplica
                    if (latched_wr_en) l2_write_misses <= l2_write_misses + 1;
                    else               l2_read_misses  <= l2_read_misses  + 1;

                    case (victim_way)
                        2'd0: if (cur_valid0 && cur_dirty0 && !wb_full) begin
                            wb_addr[wb_tail] <= {cur_tag0, latched_index, 5'b00000};
                            for (fi = 0; fi < LINE_WORDS; fi++) wb_words[wb_tail][fi] <= data[latched_index][0][fi];
                            wb_tail <= wb_tail + 1; wb_count <= wb_count + 1;
                        end
                        2'd1: if (cur_valid1 && cur_dirty1 && !wb_full) begin
                            wb_addr[wb_tail] <= {cur_tag1, latched_index, 5'b00000};
                            for (fi = 0; fi < LINE_WORDS; fi++) wb_words[wb_tail][fi] <= data[latched_index][1][fi];
                            wb_tail <= wb_tail + 1; wb_count <= wb_count + 1;
                        end
                        2'd2: if (cur_valid2 && cur_dirty2 && !wb_full) begin
                            wb_addr[wb_tail] <= {cur_tag2, latched_index, 5'b00000};
                            for (fi = 0; fi < LINE_WORDS; fi++) wb_words[wb_tail][fi] <= data[latched_index][2][fi];
                            wb_tail <= wb_tail + 1; wb_count <= wb_count + 1;
                        end
                        2'd3: if (cur_valid3 && cur_dirty3 && !wb_full) begin
                            wb_addr[wb_tail] <= {cur_tag3, latched_index, 5'b00000};
                            for (fi = 0; fi < LINE_WORDS; fi++) wb_words[wb_tail][fi] <= data[latched_index][3][fi];
                            wb_tail <= wb_tail + 1; wb_count <= wb_count + 1;
                        end
                    endcase
                    active_way <= victim_way;
                    state      <= S_MEM_REQ;
                end
            end

            S_HIT_WAIT: begin
                if (hit_counter > 0) begin
                    hit_counter <= hit_counter - 1;
                end else begin
                    case (active_way)
                        2'd0: for (fi = 0; fi < LINE_WORDS; fi++) l2_line[fi] <= data[latched_index][0][fi];
                        2'd1: for (fi = 0; fi < LINE_WORDS; fi++) l2_line[fi] <= data[latched_index][1][fi];
                        2'd2: for (fi = 0; fi < LINE_WORDS; fi++) l2_line[fi] <= data[latched_index][2][fi];
                        2'd3: for (fi = 0; fi < LINE_WORDS; fi++) l2_line[fi] <= data[latched_index][3][fi];
                    endcase
                    state <= S_RESPOND_L1;
                end
            end

            S_MEM_REQ: begin
                if (mem_ready) begin
                    mem_req <= 1'b1; mem_addr <= latched_line_base;
                    mem_wr_en <= 1'b0; mem_burst_en <= 1'b1;
                    state <= S_MEM_WAIT;
                end
            end

            S_MEM_WAIT: begin
                mem_req <= 1'b0;
                if (mem_valid) begin
                    for (fi = 0; fi < LINE_WORDS; fi++) fill_buffer[fi] <= mem_burst_data[fi];
                    state <= S_FILL_L2;
                end
            end

            S_FILL_L2: begin
                case (active_way)
                    2'd0: begin
                        valid[latched_index][0] <= 1'b1; dirty[latched_index][0] <= latched_wr_en; tag[latched_index][0] <= latched_tag;
                        for (fi = 0; fi < LINE_WORDS; fi++) data[latched_index][0][fi] <= fill_buffer[fi];
                        if (latched_wr_en) case (latched_offset)
                            3'd0: data[latched_index][0][0] <= latched_write_word; 3'd1: data[latched_index][0][1] <= latched_write_word;
                            3'd2: data[latched_index][0][2] <= latched_write_word; 3'd3: data[latched_index][0][3] <= latched_write_word;
                            3'd4: data[latched_index][0][4] <= latched_write_word; 3'd5: data[latched_index][0][5] <= latched_write_word;
                            3'd6: data[latched_index][0][6] <= latched_write_word; 3'd7: data[latched_index][0][7] <= latched_write_word;
                        endcase
                    end
                    2'd1: begin
                        valid[latched_index][1] <= 1'b1; dirty[latched_index][1] <= latched_wr_en; tag[latched_index][1] <= latched_tag;
                        for (fi = 0; fi < LINE_WORDS; fi++) data[latched_index][1][fi] <= fill_buffer[fi];
                        if (latched_wr_en) case (latched_offset)
                            3'd0: data[latched_index][1][0] <= latched_write_word; 3'd1: data[latched_index][1][1] <= latched_write_word;
                            3'd2: data[latched_index][1][2] <= latched_write_word; 3'd3: data[latched_index][1][3] <= latched_write_word;
                            3'd4: data[latched_index][1][4] <= latched_write_word; 3'd5: data[latched_index][1][5] <= latched_write_word;
                            3'd6: data[latched_index][1][6] <= latched_write_word; 3'd7: data[latched_index][1][7] <= latched_write_word;
                        endcase
                    end
                    2'd2: begin
                        valid[latched_index][2] <= 1'b1; dirty[latched_index][2] <= latched_wr_en; tag[latched_index][2] <= latched_tag;
                        for (fi = 0; fi < LINE_WORDS; fi++) data[latched_index][2][fi] <= fill_buffer[fi];
                        if (latched_wr_en) case (latched_offset)
                            3'd0: data[latched_index][2][0] <= latched_write_word; 3'd1: data[latched_index][2][1] <= latched_write_word;
                            3'd2: data[latched_index][2][2] <= latched_write_word; 3'd3: data[latched_index][2][3] <= latched_write_word;
                            3'd4: data[latched_index][2][4] <= latched_write_word; 3'd5: data[latched_index][2][5] <= latched_write_word;
                            3'd6: data[latched_index][2][6] <= latched_write_word; 3'd7: data[latched_index][2][7] <= latched_write_word;
                        endcase
                    end
                    2'd3: begin
                        valid[latched_index][3] <= 1'b1; dirty[latched_index][3] <= latched_wr_en; tag[latched_index][3] <= latched_tag;
                        for (fi = 0; fi < LINE_WORDS; fi++) data[latched_index][3][fi] <= fill_buffer[fi];
                        if (latched_wr_en) case (latched_offset)
                            3'd0: data[latched_index][3][0] <= latched_write_word; 3'd1: data[latched_index][3][1] <= latched_write_word;
                            3'd2: data[latched_index][3][2] <= latched_write_word; 3'd3: data[latched_index][3][3] <= latched_write_word;
                            3'd4: data[latched_index][3][4] <= latched_write_word; 3'd5: data[latched_index][3][5] <= latched_write_word;
                            3'd6: data[latched_index][3][6] <= latched_write_word; 3'd7: data[latched_index][3][7] <= latched_write_word;
                        endcase
                    end
                endcase

                case (active_way)
                    2'd0: plru[latched_index] <= {1'b1, 1'b1, plru[latched_index][0]};
                    2'd1: plru[latched_index] <= {1'b1, 1'b0, plru[latched_index][0]};
                    2'd2: plru[latched_index] <= {1'b0, plru[latched_index][1], 1'b1};
                    2'd3: plru[latched_index] <= {1'b0, plru[latched_index][1], 1'b0};
                endcase

                for (fi = 0; fi < LINE_WORDS; fi++) l2_line[fi] <= fill_buffer[fi];
                if (latched_wr_en) case (latched_offset)
                    3'd0: l2_line[0] <= latched_write_word; 3'd1: l2_line[1] <= latched_write_word;
                    3'd2: l2_line[2] <= latched_write_word; 3'd3: l2_line[3] <= latched_write_word;
                    3'd4: l2_line[4] <= latched_write_word; 3'd5: l2_line[5] <= latched_write_word;
                    3'd6: l2_line[6] <= latched_write_word; 3'd7: l2_line[7] <= latched_write_word;
                endcase

                state <= S_RESPOND_L1;
            end

            S_RESPOND_L1: begin
                l2_valid <= 1'b1;
                state    <= (!wb_empty && mem_ready) ? S_WB_DRAIN : S_IDLE;
            end

            S_WB_DRAIN: begin
                if (mem_ready && !l1_req) begin
                    mem_req <= 1'b1; mem_addr <= wb_addr[wb_head];
                    mem_wr_en <= 1'b1; mem_burst_en <= 1'b0;
                    mem_write_data <= wb_words[wb_head][0];
                    wb_head <= wb_head + 1; wb_count <= wb_count - 1;
                    state <= S_IDLE;
                end else if (l1_req) begin
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;

        endcase
    end
end

// l2_ready en IDLE o LOOKUP — L1 puede encolar el siguiente request mientras
// se está procesando el lookup del actual (pipeline de 1 nivel)
assign l2_ready = (state == S_IDLE);

endmodule