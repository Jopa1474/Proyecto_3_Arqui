// Testbench: branch_compare_tb
// Verifica condiciones de branch para TEA-ISA

`timescale 1ns/1ps

module branch_compare_tb;

    logic [31:0] a;
    logic [31:0] b;

    logic [1:0] BranchTypeD;
    logic BranchCondD;

    logic TakenD;

    branch_compare dut (
        .a(a),
        .b(b),
        .BranchTypeD(BranchTypeD),
        .BranchCondD(BranchCondD),
        .TakenD(TakenD)
    );

    initial begin
        $dumpfile("sim/branch_compare_tb.vcd");
        $dumpvars(0, branch_compare_tb);

        $display("=== branch_compare_tb start ===");

        $monitor("t=%0t | a=%0d b=%0d type=%b cond=%b || TakenD=%b",
                 $time, $signed(a), $signed(b), BranchTypeD, BranchCondD, TakenD);

        // Valores iniciales
        a = 32'd0;
        b = 32'd0;
        BranchTypeD = 2'b00;
        BranchCondD = 1'b0;

        // Sin branch
        #5 BranchTypeD = 2'b00; BranchCondD = 1'b0; a = 32'd5; b = 32'd5;

        // BEQ: tomado si a == b
        #5 BranchTypeD = 2'b01; BranchCondD = 1'b0; a = 32'd5; b = 32'd5;

        // BEQ: no tomado si a != b
        #5 BranchTypeD = 2'b01; BranchCondD = 1'b0; a = 32'd5; b = 32'd10;

        // BNE: tomado si a != b
        #5 BranchTypeD = 2'b01; BranchCondD = 1'b1; a = 32'd5; b = 32'd10;

        // BNE: no tomado si a == b
        #5 BranchTypeD = 2'b01; BranchCondD = 1'b1; a = 32'd5; b = 32'd5;

        // BGE: tomado si a >= b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b0; a = 32'd10; b = 32'd5;

        // BGE: tomado si a == b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b0; a = 32'd5; b = 32'd5;

        // BGE: no tomado si a < b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b0; a = 32'd3; b = 32'd5;

        // BGT: tomado si a > b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b1; a = 32'd10; b = 32'd5;

        // BGT: no tomado si a == b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b1; a = 32'd5; b = 32'd5;

        // BGT: no tomado si a < b
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b1; a = 32'd3; b = 32'd5;

        // Prueba con signed: -1 > -5
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b1; a = -32'sd1; b = -32'sd5;

        // Prueba con signed: -5 < 1, entonces BGE no tomado
        #5 BranchTypeD = 2'b10; BranchCondD = 1'b0; a = -32'sd5; b = 32'sd1;

        #5;
        $display("=== branch_compare_tb end ===");
        $finish;
    end

endmodule