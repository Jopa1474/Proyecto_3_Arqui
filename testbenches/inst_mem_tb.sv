// Testbench: inst_mem_tb
// Description: Verifica lectura de instrucciones

`timescale 1ns/1ps

module inst_mem_tb;

    logic [31:0] addr;
    logic [22:0] inst;

    inst_mem dut (.addr(addr), .inst(inst));

    initial begin
        $dumpfile("sim/inst_mem_tb.vcd");           
        $dumpvars(0, inst_mem_tb);

        $display("=== inst_mem_tb start ===");
        $monitor("t=%0t addr=%h | inst=%h", $time, addr, inst);

        #5; addr = 32'h00000000; 
        #5; addr = 32'h00000004; 
        #5; addr = 32'h00000008; 
        #5; addr = 32'h0000000C; 
        #5; addr = 32'h00000010; 

        #5;
        $display("=== inst_mem_tb end ===");
        $finish;
    end

endmodule