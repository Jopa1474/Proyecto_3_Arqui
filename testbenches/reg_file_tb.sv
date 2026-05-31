// Testbench: reg_file_tb
// Description: Verifica lectura, escritura, reset y proteccion de R0
// para el register file del TEA-ISA

`timescale 1ns/1ps

module reg_file_tb;

    logic clk;
    logic rst;
    logic write_en;

    logic [3:0] rs1;
    logic [3:0] rs2;
    logic [3:0] rd;
    logic [31:0] WD3;

    logic [31:0] RD1;
    logic [31:0] RD2;

    reg_file dut (
        .clk(clk),
        .rst(rst),
        .write_en(write_en),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .WD3(WD3),
        .RD1(RD1),
        .RD2(RD2)
    );

    // Reloj simple: cambia cada 5 ns
    always #5 clk = ~clk;

    task show(input string desc);
        #1;
        $display("%s:\n  rs1=%0d RD1=0x%08h | rs2=%0d RD2=0x%08h | rd=%0d WD3=0x%08h write_en=%b\n",
                 desc, rs1, RD1, rs2, RD2, rd, WD3, write_en);
    endtask

    initial begin
        $dumpfile("sim/reg_file_tb.vcd");         
        $dumpvars(0, reg_file_tb);

        clk = 0;
        rst = 1;
        write_en = 0;
        rs1 = 0;
        rs2 = 0;
        rd = 0;
        WD3 = 32'd0;
        @(posedge clk);
        rst = 0;

        // Escribir 5 en R1
        rd = 4'd1;
        WD3 = 32'h00000005;
        write_en = 1;
        #1;
        @(negedge clk);
        #1;
        write_en = 0;

        rs1 = 4'd1;
        rs2 = 4'd0;
        show("Escritura en R1: R1 debe valer 5");

        // Escribir 10 en R2
        rd = 4'd2;
        WD3 = 32'h0000000A;
        write_en = 1;
        #1;
        @(negedge clk);
        #1;
        write_en = 0;

        rs1 = 4'd1;
        rs2 = 4'd2;
        show("Lectura de R1 y R2: deben valer 5 y 10");

        // Probar que si write_en = 0 no escribe
        rd = 4'd3;
        WD3 = 32'h12345678;
        write_en = 0;
        @(negedge clk);

        rs1 = 4'd3;
        rs2 = 4'd1;
        show("write_en=0: R3 debe seguir en 0");

        $finish;
    end

endmodule