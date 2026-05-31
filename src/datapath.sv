// Datapath
module datapath (
    input logic clk, rst
);

// IF ----------------------------------------------------------------------------------
logic [31:0] pc_out, pc_plus4, pc_next;
logic [31:0] branch_target, jr_target;
logic [22:0] instr_if;
logic pc_write;
logic halted;
logic halt_ex, halt_mem, halt_wb;
logic [1:0] pc_src_s;

adder #(32) add_pc4 (pc_out, 32'd4, pc_plus4);
mux4 #(32) mux_pc (pc_plus4, branch_target, jr_target, 32'd0, pc_src_s, pc_next);
program_counter pc_reg (.clk(clk), .rst(rst), .PCWrite((pc_write && !halt_cu && !halted) || 
         ((pc_src_s != 2'b00) && !nop && !halt_cu && !halted)), .pc_next(pc_next), .pc_out(pc_out));
inst_mem  imem (.addr(pc_out), .inst(instr_if));

// IF/ID
logic [22:0] instr;
logic [31:0] pc_id;
logic  if_id_en, flush;

if_id_reg if_id (
    .clk(clk), .rst(rst),
    .en(if_id_en && !halted),
    .flush(flush || halt_cu),
    .in_instr(instr_if),
    .in_pc(pc_out),
    .instr(instr),
    .pc(pc_id));

// ID ----------------------------------------------------------------------------------
logic [3:0] opcode, rd_d, rs1_d, rs1_eff, rs2_rtype, rs2_read;
logic [2:0] funct3;
logic [8:0] funct9;
logic [1:0] ki_d;
logic cond_bit;

assign opcode = instr[22:19];
assign rd_d = instr[18:15];
assign rs1_d = instr[14:11];
assign rs2_rtype = instr[10:7];
assign rs2_read = (opcode == 4'b1100) ? rs2_rtype : instr[18:15];
assign funct3 = instr[6:4];
assign funct9 = instr[8:0];
assign ki_d = instr[10:9];
assign cond_bit = instr[10];
assign rs1_eff = (opcode == 4'b0010 || opcode == 4'b1000) ? rd_d : rs1_d;

logic [31:0] imm_d;
logic [1:0]  byte_sel;
imm_gen imm_gen (
    .instruction(instr),
    .imm_out(imm_d),
    .byte_sel);

logic [31:0] src_a_d, src_b_d, result_wb;
logic [3:0] rd_wb;
logic reg_write_wb;

reg_file rf (
    .clk(clk), .rst(rst),
    .write_en(reg_write_wb),
    .rs1(rs1_eff),
    .rs2(rs2_read),
    .rd(rd_wb),
    .WD3(result_wb),
    .RD1(src_a_d),
    .RD2(src_b_d));

// Forwarding hacia Decode + branch_compare
// ForwardAD/BD: 00=regfile  01=result_wb(WB)  10=alu_result_mem(MEM)
logic TakenD;
logic [1:0] ForwardAD, ForwardBD;
logic [31:0] BrA, BrB;
logic [31:0] alu_result_mem;

mux4 #(32) mux_brA (src_a_d, result_wb, alu_result_mem, 32'd0, ForwardAD, BrA);
mux4 #(32) mux_brB (src_b_d, result_wb, alu_result_mem, 32'd0, ForwardBD, BrB);

branch_compare brcmp (
    .a(BrA),
    .b(BrB),
    .BranchTypeD(BranchTypeD),
    .BranchCondD(BranchCondD),
    .TakenD(TakenD));

// Control unit
logic reg_write_cu, mem_write_cu, mem_read_cu, alu_src_cu;
logic [1:0] wb_sel_cu;
logic [1:0] BranchTypeD;
logic BranchCondD, JumpD, JumpRegD;
logic [2:0] alu_op_cu;
logic is_vault_cu, is_lli_cu, halt_cu;
logic do_setpwd, do_login, do_logout, do_authorize;
logic do_vkload, do_vkinv, do_authchk, auth_denied;
logic [1:0] tea_op_cu;
logic auth_ok;

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

logic reg_write_ex;
logic [3:0] rd_ex_w;
logic mem_read_ex_w;
logic reg_write_mem_w;
logic mem_read_mem;
logic [3:0] rd_mem_w;

// IsAuthD: instrucción en ID consume rs1/rs2 en la etapa ID sin forwarding
logic IsAuthD;
assign IsAuthD = do_login | do_setpwd | do_authorize | do_vkload;

// Hazard detection
logic nop;

hazard_detection haz (
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

always_ff @(posedge clk or posedge rst) begin
    if (rst)
        halted <= 1'b0;
    else if (halt_wb)
        halted <= 1'b1;
end

// PCSrcD
logic [1:0] PCSrcD;

assign PCSrcD = nop ? 2'b00 :
                JumpRegD ? 2'b10 :
                (JumpD || TakenD) ? 2'b01 :
                2'b00;
assign pc_src_s = (halted || halt_cu) ? 2'b00 : PCSrcD;
assign flush = (pc_src_s != 2'b00) && !halted;

// Branch target y JR target calculados en Decode
logic [31:0] PCBranchD;
logic [31:0] imm_shifted_d;
assign imm_shifted_d = imm_d << 2;
adder #(32) add_branch_d (
    pc_id,
    imm_shifted_d,
    PCBranchD
);
assign branch_target = PCBranchD;
assign jr_target     = BrA;

// auth_unit en ID
logic [1:0] ki_activo, vault_key_sel, vault_word_sel;
logic vault_we, vault_inv;
logic [31:0] vault_data_in, sr;
logic vf_flag;

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
    .instr_retired(!nop && !halt_cu && !halted),
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


logic [31:0] key_word_d;

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
    .key_word_out(key_word_d)
);

// ID/EX
logic mem_write_ex;
logic [1:0] wb_sel_ex;
logic alu_src_ex;
logic [2:0] alu_op_ex;
logic is_vault_ex, is_lli_ex;
logic [1:0] byte_sel_ex;
logic [1:0] tea_op_ex;
logic [31:0] pc_ex, src_a_ex, src_b_ex, imm_ex;
logic [3:0] rs1_ex, rs2_ex;
logic [31:0] key_word_ex;

id_ex_reg id_ex (
    .clk(clk), .rst(rst),
    .en(!halted),
    .nop(nop && !halt_cu),
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

// EX ----------------------------------------------------------------------------------
logic [1:0] ForwardA, ForwardB;
logic [31:0] fwd_a, fwd_b;

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

// 00=regfile  01=result_wb(WB)  10=alu_result_mem(MEM)
mux4 #(32) mux_fwd_a (src_a_ex, result_wb, alu_result_mem, 32'd0, ForwardA, fwd_a);
mux4 #(32) mux_fwd_b (src_b_ex, result_wb, alu_result_mem, 32'd0, ForwardB, fwd_b);

logic [31:0] alu_b, alu_result_ex;
mux2 #(32) mux_b_sel (fwd_b, imm_ex, alu_src_ex, alu_b);

alu alu (
    .rs1(fwd_a),
    .rs2(alu_b),
    .funct(alu_op_ex),
    .byte_sel(byte_sel_ex),
    .is_lli(is_lli_ex),
    .result(alu_result_ex));

logic [31:0] pc_plus4_ex;
adder #(32) add_pc4_ex (pc_ex, 32'd4, pc_plus4_ex);
logic [31:0] vault_result_ex;

alu_v alu_v (
    .rs1(fwd_a),
    .K(key_word_ex),
    .tea_op(tea_op_ex),
    .result(vault_result_ex));

// Mux ALU vs ALU_V: selecciona resultado final de EX
logic [31:0] alu_result_final;
mux2 #(32) mux_alu_sel (alu_result_ex, vault_result_ex, is_vault_ex, alu_result_final);

// EX/MEM
logic mem_write_mem;
logic [1:0] wb_sel_mem;
logic [31:0] write_data_mem, pc_plus4_mem;

ex_mem_reg ex_mem (
    .clk(clk), .rst(rst),
    .en(!halted),
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

// MEM ----------------------------------------------------------------------------------
logic [31:0] read_data;
logic align_fault;

data_memory dmem (
    .clk(clk), .rst_n(~rst),
    .addr(alu_result_mem),
    .write_data(write_data_mem),
    .mem_read(mem_read_mem),
    .mem_write(mem_write_mem),
    .read_data(read_data),
    .align_fault(align_fault));

// MEM/WB
logic [1:0] wb_sel_wb;
logic [31:0] read_data_wb, alu_result_wb, pc_plus4_wb;

mem_wb_reg mem_wb (
    .clk(clk), .rst(rst),
    .en(!halted),
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

// WB ----------------------------------------------------------------------------------
// 00=ALU/TEA  01=Mem  10=PC+4(JAL)
mux4 #(32) mux_wb (alu_result_wb, read_data_wb, pc_plus4_wb, 32'd0,
                   wb_sel_wb, result_wb);

endmodule