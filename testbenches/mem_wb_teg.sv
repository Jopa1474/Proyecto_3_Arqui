// Testbench: mem_wb_reg_tb
// Verifica reset, enable y paso de señales MEM/WB

`timescale 1ns/1ps

module mem_wb_reg_tb;

    logic clk, rst;
    logic en;

    logic in_is_halt;
    logic in_reg_write;
    logic [1:0] in_wb_sel;

    logic [31:0] in_read_data;
    logic [31:0] in_alu_result;
    logic [31:0] in_pc_plus4;
    logic [3:0]  in_rd;

    logic is_halt;
    logic reg_write;
    logic [1:0] wb_sel;

    logic [31:0] read_data;
    logic [31:0] alu_result;
    logic [31:0] pc_plus4;
    logic [3:0]  rd;

    mem_wb_reg dut (
        .clk(clk),
        .rst(rst),
        .en(en),

        .in_is_halt(in_is_halt),
        .in_reg_write(in_reg_write),
        .in_wb_sel(in_wb_sel),

        .in_read_data(in_read_data),
        .in_alu_result(in_alu_result),
        .in_pc_plus4(in_pc_plus4),
        .in_rd(in_rd),

        .is_halt(is_halt),
        .reg_write(reg_write),
        .wb_sel(wb_sel),

        .read_data(read_data),
        .alu_result(alu_result),
        .pc_plus4(pc_plus4),
        .rd(rd)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/mem_wb_reg_tb.vcd");    
        $dumpvars(0, mem_wb_reg_tb);

        $display("=== mem_wb_reg_tb start ===");

        $monitor("t=%0t | rst=%b en=%b | in: halt=%b rw=%b wb=%b read=0x%08h alu=0x%08h pc4=0x%08h rd=%0d || out: halt=%b rw=%b wb=%b read=0x%08h alu=0x%08h pc4=0x%08h rd=%0d",
                 $time, rst, en,
                 in_is_halt, in_reg_write, in_wb_sel,
                 in_read_data, in_alu_result, in_pc_plus4, in_rd,
                 is_halt, reg_write, wb_sel,
                 read_data, alu_result, pc_plus4, rd);

        clk = 0;
        rst = 1;
        en = 0;

        in_is_halt = 0;
        in_reg_write = 0;
        in_wb_sel = 2'b00;

        in_read_data = 32'd0;
        in_alu_result = 32'd0;
        in_pc_plus4 = 32'd0;
        in_rd = 4'd0;

        // Reset
        #10 rst = 0;

        // Caso 1: en=1, carga resultado de ALU
        #5 en = 1;
           in_is_halt = 0;
           in_reg_write = 1;
           in_wb_sel = 2'b00;
           in_read_data = 32'h00000000;
           in_alu_result = 32'h0000000F;
           in_pc_plus4 = 32'h00000004;
           in_rd = 4'd3;

        // Caso 2: carga dato de memoria LOAD
        #10 in_reg_write = 1;
            in_wb_sel = 2'b01;
            in_read_data = 32'hAAAA5555;
            in_alu_result = 32'h00001000;
            in_pc_plus4 = 32'h00000008;
            in_rd = 4'd4;

        // Caso 3: carga PC+4 para JAL
        #10 in_reg_write = 1;
            in_wb_sel = 2'b10;
            in_read_data = 32'h11111111;
            in_alu_result = 32'h22222222;
            in_pc_plus4 = 32'h0000000C;
            in_rd = 4'd1;

        // Caso 4: en=0, NO debe cambiar salida
        #10 en = 0;
            in_is_halt = 1;
            in_reg_write = 0;
            in_wb_sel = 2'b00;
            in_read_data = 32'hFFFFFFFF;
            in_alu_result = 32'hDEADBEEF;
            in_pc_plus4 = 32'h12345678;
            in_rd = 4'd9;

        // Caso 5: en=1, ahora sí carga lo anterior
        #10 en = 1;

        // Caso 6: reset vuelve todo a 0
        #10 rst = 1;
        #10 rst = 0;

        #10;
        $display("=== mem_wb_reg_tb end ===");
        $finish;
    end

endmodule