// Testbench: hazard_detection_tb
// Verifica stalls y forwarding hacia ID para hazard_detection

`timescale 1ns/1ps

module hazard_detection_tb;

    logic [3:0] IF_ID_Rs1;
    logic [3:0] IF_ID_Rs2;
    logic       BranchD;
    logic       JumpRegD;
    logic       IsAuthD;

    logic       ID_EX_MemRead;
    logic       ID_EX_RegWrite;
    logic [3:0] ID_EX_Rd;

    logic       EX_MEM_RegWrite;
    logic       MEM_MemtoReg;
    logic [3:0] EX_MEM_Rd;

    logic       MEM_WB_RegWrite;
    logic [3:0] MEM_WB_Rd;

    logic [1:0] ForwardAD;
    logic [1:0] ForwardBD;

    logic       PCWrite;
    logic       IF_ID_Write;
    logic       control_mux_sel;

    hazard_detection dut (
        .IF_ID_Rs1(IF_ID_Rs1),
        .IF_ID_Rs2(IF_ID_Rs2),
        .BranchD(BranchD),
        .JumpRegD(JumpRegD),
        .IsAuthD(IsAuthD),

        .ID_EX_MemRead(ID_EX_MemRead),
        .ID_EX_RegWrite(ID_EX_RegWrite),
        .ID_EX_Rd(ID_EX_Rd),

        .EX_MEM_RegWrite(EX_MEM_RegWrite),
        .MEM_MemtoReg(MEM_MemtoReg),
        .EX_MEM_Rd(EX_MEM_Rd),

        .MEM_WB_RegWrite(MEM_WB_RegWrite),
        .MEM_WB_Rd(MEM_WB_Rd),

        .ForwardAD(ForwardAD),
        .ForwardBD(ForwardBD),

        .PCWrite(PCWrite),
        .IF_ID_Write(IF_ID_Write),
        .control_mux_sel(control_mux_sel)
    );

    initial begin
        $dumpfile("sim/hazard_detection_tb.vcd");  
        $dumpvars(0, hazard_detection_tb);

        $display("=== hazard_detection_tb start ===");

        $monitor("t=%0t | ID: Rs1=%0d Rs2=%0d Br=%b JR=%b Auth=%b | EX: mr=%b rw=%b rd=%0d | MEM: rw=%b m2r=%b rd=%0d | WB: rw=%b rd=%0d || FAD=%b FBD=%b PCW=%b IFIDW=%b nop=%b",
                 $time,
                 IF_ID_Rs1, IF_ID_Rs2, BranchD, JumpRegD, IsAuthD,
                 ID_EX_MemRead, ID_EX_RegWrite, ID_EX_Rd,
                 EX_MEM_RegWrite, MEM_MemtoReg, EX_MEM_Rd,
                 MEM_WB_RegWrite, MEM_WB_Rd,
                 ForwardAD, ForwardBD,
                 PCWrite, IF_ID_Write, control_mux_sel);

        // Valores por defecto: no hay hazard
        IF_ID_Rs1        = 4'd1;
        IF_ID_Rs2        = 4'd2;
        BranchD          = 1'b0;
        JumpRegD         = 1'b0;
        IsAuthD          = 1'b0;

        ID_EX_MemRead    = 1'b0;
        ID_EX_RegWrite   = 1'b0;
        ID_EX_Rd         = 4'd0;

        EX_MEM_RegWrite  = 1'b0;
        MEM_MemtoReg     = 1'b0;
        EX_MEM_Rd        = 4'd0;

        MEM_WB_RegWrite  = 1'b0;
        MEM_WB_Rd        = 4'd0;

        // Caso 1: sin hazards
        #5;

        // Caso 2: load-use hazard por Rs1
        // LOAD en EX escribe R1 y la instruccion en ID usa R1
        #5 ID_EX_MemRead  = 1'b1;
           ID_EX_RegWrite = 1'b1;
           ID_EX_Rd       = 4'd1;
           IF_ID_Rs1      = 4'd1;
           IF_ID_Rs2      = 4'd2;

        // Caso 3: load-use hazard por Rs2
        #5 ID_EX_Rd       = 4'd2;
           IF_ID_Rs1      = 4'd1;
           IF_ID_Rs2      = 4'd2;

        // Caso 4: load escribe R0, no debe hacer stall
        #5 ID_EX_Rd       = 4'd0;
           IF_ID_Rs1      = 4'd0;
           IF_ID_Rs2      = 4'd2;

        // Limpiar EX
        #5 ID_EX_MemRead  = 1'b0;
           ID_EX_RegWrite = 1'b0;
           ID_EX_Rd       = 4'd0;
           IF_ID_Rs1      = 4'd3;
           IF_ID_Rs2      = 4'd4;

        // Caso 5: forwarding hacia branch desde EX/MEM para A
        // Branch usa R3 y EX/MEM escribe R3
        #5 BranchD         = 1'b1;
           EX_MEM_RegWrite = 1'b1;
           MEM_MemtoReg    = 1'b0;
           EX_MEM_Rd       = 4'd3;
           IF_ID_Rs1       = 4'd3;
           IF_ID_Rs2       = 4'd4;

        // Caso 6: forwarding hacia branch desde EX/MEM para B
        #5 EX_MEM_Rd       = 4'd4;
           IF_ID_Rs1       = 4'd3;
           IF_ID_Rs2       = 4'd4;

        // Caso 7: forwarding hacia branch desde MEM/WB para A
        #5 EX_MEM_RegWrite = 1'b0;
           EX_MEM_Rd       = 4'd0;
           MEM_WB_RegWrite = 1'b1;
           MEM_WB_Rd       = 4'd5;
           IF_ID_Rs1       = 4'd5;
           IF_ID_Rs2       = 4'd6;

        // Caso 8: forwarding hacia branch desde MEM/WB para B
        #5 MEM_WB_Rd       = 4'd6;
           IF_ID_Rs1       = 4'd5;
           IF_ID_Rs2       = 4'd6;

        // Caso 9: branch stall porque productor esta en EX
        // Branch necesita R7, pero una instruccion en EX va a escribir R7
        #5 MEM_WB_RegWrite = 1'b0;
           MEM_WB_Rd       = 4'd0;
           BranchD         = 1'b1;
           ID_EX_RegWrite  = 1'b1;
           ID_EX_MemRead   = 1'b0;
           ID_EX_Rd        = 4'd7;
           IF_ID_Rs1       = 4'd7;
           IF_ID_Rs2       = 4'd8;

        // Caso 10: branch stall porque hay LOAD en MEM
        #5 ID_EX_RegWrite  = 1'b0;
           ID_EX_Rd        = 4'd0;
           EX_MEM_RegWrite = 1'b1;
           MEM_MemtoReg    = 1'b1;
           EX_MEM_Rd       = 4'd8;
           IF_ID_Rs1       = 4'd7;
           IF_ID_Rs2       = 4'd8;

        // Caso 11: JR se comporta como branch para hazards
        #5 BranchD         = 1'b0;
           JumpRegD        = 1'b1;
           MEM_MemtoReg    = 1'b0;
           EX_MEM_RegWrite = 1'b0;
           EX_MEM_Rd       = 4'd0;
           ID_EX_RegWrite  = 1'b1;
           ID_EX_Rd        = 4'd9;
           IF_ID_Rs1       = 4'd9;
           IF_ID_Rs2       = 4'd1;

        // Caso 12: Auth hazard con productor en WB
        // Auth lee register file, entonces incluso WB puede requerir stall
        #5 JumpRegD         = 1'b0;
           IsAuthD          = 1'b1;
           ID_EX_RegWrite   = 1'b0;
           ID_EX_Rd         = 4'd0;
           EX_MEM_RegWrite  = 1'b0;
           EX_MEM_Rd        = 4'd0;
           MEM_WB_RegWrite  = 1'b1;
           MEM_WB_Rd        = 4'd10;
           IF_ID_Rs1        = 4'd10;
           IF_ID_Rs2        = 4'd1;

        // Caso 13: sin hazard después de limpiar todo
        #5 IsAuthD          = 1'b0;
           BranchD          = 1'b0;
           JumpRegD         = 1'b0;
           ID_EX_MemRead    = 1'b0;
           ID_EX_RegWrite   = 1'b0;
           ID_EX_Rd         = 4'd0;
           EX_MEM_RegWrite  = 1'b0;
           MEM_MemtoReg     = 1'b0;
           EX_MEM_Rd        = 4'd0;
           MEM_WB_RegWrite  = 1'b0;
           MEM_WB_Rd        = 4'd0;
           IF_ID_Rs1        = 4'd1;
           IF_ID_Rs2        = 4'd2;

        #5;
        $display("=== hazard_detection_tb end ===");
        $finish;
    end

endmodule