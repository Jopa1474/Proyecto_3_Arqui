// Testbench: id_ex_reg_tb
// Verifica reset, enable, nop y paso de señales ID/EX

`timescale 1ns/1ps

module id_ex_reg_tb;

    logic clk, rst;
    logic en, nop;

    logic in_is_halt;
    logic in_reg_write;
    logic [1:0] in_wb_sel;
    logic in_mem_write;
    logic in_mem_read;
    logic in_alu_src;
    logic [2:0] in_alu_op;
    logic in_is_vault;
    logic [31:0] in_key_word;
    logic in_is_lli;
    logic [1:0] in_byte_sel;
    logic [1:0] in_tea_op;

    logic [31:0] in_pc;
    logic [31:0] in_src_a;
    logic [31:0] in_src_b;
    logic [31:0] in_imm;
    logic [3:0]  in_rd;
    logic [3:0]  in_rs1;
    logic [3:0]  in_rs2;

    logic is_halt;
    logic reg_write;
    logic [1:0] wb_sel;
    logic mem_write;
    logic mem_read;
    logic alu_src;
    logic [2:0] alu_op;
    logic is_vault;
    logic [31:0] key_word;
    logic is_lli;
    logic [1:0] byte_sel;
    logic [1:0] tea_op;

    logic [31:0] pc;
    logic [31:0] src_a;
    logic [31:0] src_b;
    logic [31:0] imm;
    logic [3:0]  rd;
    logic [3:0]  rs1;
    logic [3:0]  rs2;

    id_ex_reg dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .nop(nop),

        .in_is_halt(in_is_halt),
        .in_reg_write(in_reg_write),
        .in_wb_sel(in_wb_sel),
        .in_mem_write(in_mem_write),
        .in_mem_read(in_mem_read),
        .in_alu_src(in_alu_src),
        .in_alu_op(in_alu_op),
        .in_is_vault(in_is_vault),
        .in_key_word(in_key_word),
        .in_is_lli(in_is_lli),
        .in_byte_sel(in_byte_sel),
        .in_tea_op(in_tea_op),

        .in_pc(in_pc),
        .in_src_a(in_src_a),
        .in_src_b(in_src_b),
        .in_imm(in_imm),
        .in_rd(in_rd),
        .in_rs1(in_rs1),
        .in_rs2(in_rs2),

        .is_halt(is_halt),
        .reg_write(reg_write),
        .wb_sel(wb_sel),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .alu_src(alu_src),
        .alu_op(alu_op),
        .is_vault(is_vault),
        .key_word(key_word),
        .is_lli(is_lli),
        .byte_sel(byte_sel),
        .tea_op(tea_op),

        .pc(pc),
        .src_a(src_a),
        .src_b(src_b),
        .imm(imm),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/id_ex_reg_tb.vcd");     
        $dumpvars(0, id_ex_reg_tb);

        $display("=== id_ex_reg_tb start ===");

        $monitor("t=%0t | rst=%b en=%b nop=%b | in: halt=%b rw=%b wb=%b mw=%b mr=%b asrc=%b aop=%b vault=%b lli=%b pc=0x%08h a=0x%08h b=0x%08h imm=0x%08h rd=%0d rs1=%0d rs2=%0d || out: halt=%b rw=%b wb=%b mw=%b mr=%b asrc=%b aop=%b vault=%b lli=%b pc=0x%08h a=0x%08h b=0x%08h imm=0x%08h rd=%0d rs1=%0d rs2=%0d",
                 $time, rst, en, nop,
                 in_is_halt, in_reg_write, in_wb_sel, in_mem_write, in_mem_read,
                 in_alu_src, in_alu_op, in_is_vault, in_is_lli,
                 in_pc, in_src_a, in_src_b, in_imm, in_rd, in_rs1, in_rs2,
                 is_halt, reg_write, wb_sel, mem_write, mem_read,
                 alu_src, alu_op, is_vault, is_lli,
                 pc, src_a, src_b, imm, rd, rs1, rs2);

        clk = 0;
        rst = 1;
        en = 0;
        nop = 0;

        in_is_halt = 0;
        in_reg_write = 0;
        in_wb_sel = 2'b00;
        in_mem_write = 0;
        in_mem_read = 0;
        in_alu_src = 0;
        in_alu_op = 3'b000;
        in_is_vault = 0;
        in_key_word = 32'd0;
        in_is_lli = 0;
        in_byte_sel = 2'b00;
        in_tea_op = 2'b00;

        in_pc = 32'd0;
        in_src_a = 32'd0;
        in_src_b = 32'd0;
        in_imm = 32'd0;
        in_rd = 4'd0;
        in_rs1 = 4'd0;
        in_rs2 = 4'd0;

        // Reset
        #10 rst = 0;

        // Caso 1: en=1, debe cargar valores normales
        #5 en = 1;
           in_is_halt = 0;
           in_reg_write = 1;
           in_wb_sel = 2'b00;
           in_mem_write = 0;
           in_mem_read = 0;
           in_alu_src = 0;
           in_alu_op = 3'b001;
           in_is_vault = 0;
           in_key_word = 32'h11112222;
           in_is_lli = 0;
           in_byte_sel = 2'b00;
           in_tea_op = 2'b00;

           in_pc = 32'h00000004;
           in_src_a = 32'h00000005;
           in_src_b = 32'h0000000A;
           in_imm = 32'h00000000;
           in_rd = 4'd3;
           in_rs1 = 4'd1;
           in_rs2 = 4'd2;

        // Caso 2: cargar valores de LOAD
        #10 in_reg_write = 1;
            in_wb_sel = 2'b01;
            in_mem_write = 0;
            in_mem_read = 1;
            in_alu_src = 1;
            in_alu_op = 3'b000;
            in_pc = 32'h00000008;
            in_src_a = 32'h00001000;
            in_src_b = 32'h00000000;
            in_imm = 32'h00000004;
            in_rd = 4'd4;
            in_rs1 = 4'd2;
            in_rs2 = 4'd0;

        // Caso 3: en=0, NO debe cambiar salidas
        #10 en = 0;
            in_reg_write = 0;
            in_wb_sel = 2'b10;
            in_mem_write = 1;
            in_mem_read = 0;
            in_alu_src = 1;
            in_alu_op = 3'b111;
            in_pc = 32'hFFFFFFFF;
            in_src_a = 32'hAAAA5555;
            in_src_b = 32'h12345678;
            in_imm = 32'hDEADBEEF;
            in_rd = 4'd9;
            in_rs1 = 4'd8;
            in_rs2 = 4'd7;

        // Caso 4: nop=1, debe limpiar salidas
        #10 nop = 1;
            en = 1;

        // Quitar nop
        #10 nop = 0;

        // Caso 5: halt=1, pasa is_halt pero limpia señales de control
        #10 in_is_halt = 1;
            in_reg_write = 1;
            in_wb_sel = 2'b01;
            in_mem_write = 1;
            in_mem_read = 1;
            in_alu_src = 1;
            in_alu_op = 3'b101;
            in_is_vault = 1;
            in_is_lli = 1;
            in_tea_op = 2'b10;
            in_pc = 32'h00000020;
            in_src_a = 32'h000000AA;
            in_src_b = 32'h000000BB;
            in_imm = 32'h000000CC;
            in_rd = 4'd5;
            in_rs1 = 4'd6;
            in_rs2 = 4'd7;

        // Caso 6: reset vuelve todo a 0
        #10 rst = 1;
        #10 rst = 0;

        #10;
        $display("=== id_ex_reg_tb end ===");
        $finish;
    end

endmodule