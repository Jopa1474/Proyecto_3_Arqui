// Testbench: program_counter_tb
// Description: Verifica reset, PCWrite y avance del PC

`timescale 1ns/1ps

module program_counter_tb;

    logic clk, rst, PCWrite;
    logic [31:0] pc_next, pc_out;

    program_counter dut (.clk(clk), .rst(rst), .PCWrite(PCWrite),
                         .pc_next(pc_next), .pc_out(pc_out));

    always #5 clk = ~clk;
    always @(posedge clk)
        $display("t=%4t | rst=%b PCWrite=%b pc_next=%h pc=%h", $time, rst, PCWrite, pc_next, pc_out);

    initial begin
        $dumpfile("sim/program_counter_tb.vcd");  
        $dumpvars(0, program_counter_tb);
        
        $display("=== program_counter_tb start ===");

        clk=0; rst=1; PCWrite=0; pc_next=0;
        #10; rst=0;                       

        PCWrite=1;
        #10; pc_next=32'h00000004; // avanza a 4
        #10; pc_next=32'h00000008; // avanza a 8
        #10; pc_next=32'h0000000C; // avanza a C

        PCWrite=0;
        #10; pc_next=32'h00000010; // stall, pc no cambia

        PCWrite=1;
        #10; pc_next=32'h00000064; // salto (branch/JAL)

        rst=1;
        #10; rst=0; // reset -> pc=0

        #10;
        $display("=== program_counter_tb end ===");
        $finish;
    end

endmodule