`timescale 1ns/1ps

module alu_tb;

    logic [31:0] rs1, rs2;
    logic [2:0] funct;
    logic [1:0]  byte_sel;
    logic        is_lli;
    logic [31:0] result;

    // Instancia de la ALU
    alu uut (
        .rs1(rs1),
        .rs2(rs2),
        .funct(funct),
        .byte_sel(byte_sel), 
        .is_lli(is_lli), 
        .result(result)
    );

    initial begin
        $dumpfile("sim/alu_tb.vcd");           
        $dumpvars(0, alu_tb);

        is_lli   = 0;
        byte_sel = 2'b00;

        // ADD
        rs1 = 10; rs2 = 5; funct = 3'b000;
        #10;
        $display("ADD: %0d", result);

        // SUB
        funct = 3'b001;
        #10;
        $display("SUB: %0d", result);

        // AND
        rs1 = 6; rs2 = 3; funct = 3'b010;
        #10;
        $display("AND: %0d", result);

        // OR
        funct = 3'b011;
        #10;
        $display("OR: %0d", result);

        // XOR
        funct = 3'b100;
        #10;
        $display("XOR: %0d", result);

        // SLL
        rs1 = 1; rs2 = 2; funct = 3'b101;
        #10;
        $display("SLL: %0d", result);

        // SRL
        rs1 = 8; rs2 = 1; funct = 3'b110;
        #10;
        $display("SRL: %0d", result);

        // SRA (prueba con negativo)
        rs1 = -8; rs2 = 1; funct = 3'b111;
        #10;
        $display("SRA: %0d", result);

        // Construimos 0x9E3779B9 paso a paso en rs1
        // rs2 = byte ya shifteado a su posicion (lo que hace imm_gen)
        is_lli = 1; funct = 3'bxxx; // funct ignorado cuando is_lli=1
 
        // byte_sel=0: rd=0x00000000  resultado 0x000000B9
        rs1 = 32'h00000000; rs2 = 32'h000000B9; byte_sel = 2'b00; #10;
        $display("LLI b0: 0x%08X ", result);
 
        // byte_sel=1: rd=0x000000B9  resultado 0x000079B9
        rs1 = 32'h000000B9; rs2 = 32'h00007900; byte_sel = 2'b01; #10;
        $display("LLI b1: 0x%08X", result);
 
        // byte_sel=2: rd=0x000079B9  resultado 0x003779B9
        rs1 = 32'h000079B9; rs2 = 32'h00370000; byte_sel = 2'b10; #10;
        $display("LLI b2: 0x%08X", result);
 
        // byte_sel=3: rd=0x003779B9  resultado 0x9E3779B9
        rs1 = 32'h003779B9; rs2 = 32'h9E000000; byte_sel = 2'b11; #10;
        $display("LLI b3: 0x%08X", result);

        $finish;
    end

endmodule