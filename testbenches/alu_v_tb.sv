`timescale 1ps/1ps

// Testbench para alu_v

module alu_v_tb;

    logic [31:0] rs1, K;
    logic [2:0] tea_op;
    logic [31:0] result;

    // Instancia de la ALU para instrucciones criptográficas
    alu_v uut (
        .rs1(rs1),
        .K(K),
        .tea_op(tea_op),
        .result(result)
    );

    initial begin
        $dumpfile("sim/alu_v_tb.vcd");         
        $dumpvars(0, alu_v_tb);

        // TEA_ADD1: rd = (rs1 << 4) + K[i]
        rs1 = 1; K = 10; tea_op = 3'b01;
        #10;
        $display("TEA_ADD1: %0d", result);

        // TEA_ADD2: rd = (rs1 >> 5) + K[i]
        rs1 = 32; K = 20; tea_op = 3'b10;
        #10;
        $display("TEA_ADD2: %0d", result);
    end




endmodule