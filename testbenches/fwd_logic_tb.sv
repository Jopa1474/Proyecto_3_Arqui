// Testbench: fwd_logic_tb
// Verifica señales de forwarding para fwd_logic

`timescale 1ns/1ps

module fwd_logic_tb;

    logic        EX_MEM_MemtoReg;

    logic        EX_MEM_RegWrite;
    logic [3:0]  EX_MEM_Rd;

    logic        MEM_WB_RegWrite;
    logic [3:0]  MEM_WB_Rd;

    logic [3:0]  ID_EX_Rs1;
    logic [3:0]  ID_EX_Rs2;

    logic [1:0]  forwardA;
    logic [1:0]  forwardB;

    fwd_logic dut (
        .EX_MEM_MemtoReg(EX_MEM_MemtoReg),
        .EX_MEM_RegWrite(EX_MEM_RegWrite),
        .EX_MEM_Rd(EX_MEM_Rd),
        .MEM_WB_RegWrite(MEM_WB_RegWrite),
        .MEM_WB_Rd(MEM_WB_Rd),
        .ID_EX_Rs1(ID_EX_Rs1),
        .ID_EX_Rs2(ID_EX_Rs2),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    initial begin
        $dumpfile("sim/fwd_logic_tb.vcd");         
        $dumpvars(0, fwd_logic_tb);
        
        $display("=== fwd_logic_tb start ===");

        $monitor("t=%0t | EX_MEM: m2r=%b rw=%b rd=%0d | MEM_WB: rw=%b rd=%0d | Rs1=%0d Rs2=%0d || fA=%b fB=%b",
                 $time,
                 EX_MEM_MemtoReg, EX_MEM_RegWrite, EX_MEM_Rd,
                 MEM_WB_RegWrite, MEM_WB_Rd,
                 ID_EX_Rs1, ID_EX_Rs2,
                 forwardA, forwardB);

        // Valores por defecto: no hay forwarding
        EX_MEM_MemtoReg = 1'b0;
        EX_MEM_RegWrite = 1'b0;
        EX_MEM_Rd       = 4'd0;
        MEM_WB_RegWrite = 1'b0;
        MEM_WB_Rd       = 4'd0;
        ID_EX_Rs1       = 4'd1;
        ID_EX_Rs2       = 4'd2;

        // Caso 1: no hay escritura en etapas posteriores
        #5;

        // Caso 2: forwardA desde EX/MEM
        // EX/MEM escribe R1 y Rs1 necesita R1
        #5 EX_MEM_RegWrite = 1'b1;
           EX_MEM_MemtoReg = 1'b0;
           EX_MEM_Rd       = 4'd1;
           ID_EX_Rs1       = 4'd1;
           ID_EX_Rs2       = 4'd2;

        // Caso 3: forwardB desde EX/MEM
        // EX/MEM escribe R2 y Rs2 necesita R2
        #5 EX_MEM_Rd       = 4'd2;
           ID_EX_Rs1       = 4'd1;
           ID_EX_Rs2       = 4'd2;

        // Caso 4: EX/MEM es LOAD, entonces NO debe forwardear desde EX/MEM
        // porque EX_MEM_MemtoReg = 1
        #5 EX_MEM_RegWrite = 1'b1;
           EX_MEM_MemtoReg = 1'b1;
           EX_MEM_Rd       = 4'd3;
           MEM_WB_RegWrite = 1'b0;
           MEM_WB_Rd       = 4'd0;
           ID_EX_Rs1       = 4'd3;
           ID_EX_Rs2       = 4'd4;

        // Caso 5: forwardA desde MEM/WB
        #5 EX_MEM_RegWrite = 1'b0;
           EX_MEM_MemtoReg = 1'b0;
           EX_MEM_Rd       = 4'd0;
           MEM_WB_RegWrite = 1'b1;
           MEM_WB_Rd       = 4'd5;
           ID_EX_Rs1       = 4'd5;
           ID_EX_Rs2       = 4'd6;

        // Caso 6: forwardB desde MEM/WB
        #5 MEM_WB_Rd       = 4'd6;
           ID_EX_Rs1       = 4'd5;
           ID_EX_Rs2       = 4'd6;

        // Caso 7: prioridad EX/MEM sobre MEM/WB
        // Ambos escriben R7 y Rs1 necesita R7
        // Debe dar forwardA = 10
        #5 EX_MEM_RegWrite = 1'b1;
           EX_MEM_MemtoReg = 1'b0;
           EX_MEM_Rd       = 4'd7;
           MEM_WB_RegWrite = 1'b1;
           MEM_WB_Rd       = 4'd7;
           ID_EX_Rs1       = 4'd7;
           ID_EX_Rs2       = 4'd8;

        // Caso 8: no hacer forwarding con R0
        #5 EX_MEM_RegWrite = 1'b1;
           EX_MEM_MemtoReg = 1'b0;
           EX_MEM_Rd       = 4'd0;
           MEM_WB_RegWrite = 1'b1;
           MEM_WB_Rd       = 4'd0;
           ID_EX_Rs1       = 4'd0;
           ID_EX_Rs2       = 4'd0;

        #5;
        $display("=== fwd_logic_tb end ===");
        $finish;
    end

endmodule