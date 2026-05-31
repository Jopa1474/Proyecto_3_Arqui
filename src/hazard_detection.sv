
// hazard_detection
// ID lee en posedge -> WB escribe en negedge del mismo ciclo -> WB->ID es hazard.
//
// ForwardAD / ForwardBD son de 2 bits y controlan un mux4 en ID:
//   2'b00 -> register file (src_a_d / src_b_d)
//   2'b10 -> alu_result_mem ( en etapa MEM)
//   2'b01 -> result_wb( en etapa WB — wire combinacional del mux de WB)
//
// Result_wb: aunque el regfile aún no fue escrito en ese
// ciclo, result_wb es el WIRE de salida del mux de WB y ya tiene el valor
// correcto. El mux_brA/mux_brB puede usarlo directamente -> forwarding válido.
// La auth_unit en cambio lee el regfile -> necesita stall también en WB.


module hazard_detection (

    // Etapa ID 
    input  logic [3:0]  IF_ID_Rs1, // rs1_eff del datapath
    input  logic [3:0]  IF_ID_Rs2, // rs2_read del datapath
    input  logic BranchD,   // BranchTypeD != 2'b00
    input  logic JumpRegD,  // instrucción en ID es JR
    input  logic IsAuthD,   // LOGIN | SETPWD | AUTHORIZE | VKLOAD

    // Etapa EX (salidas ID/EX) 
    input logic ID_EX_MemRead,    // instrucción en EX es LOAD
    input logic ID_EX_RegWrite,   // instrucción en EX escribe rd
    input logic [3:0]  ID_EX_Rd,

    // Etapa MEM (salidas EX/MEM)
    input logic EX_MEM_RegWrite,  // instrucción en MEM escribe rd
    input logic MEM_MemtoReg,     // instrucción en MEM es LOAD
    input logic [3:0]  EX_MEM_Rd,

    //Etapa WB (salidas MEM/WB) 
    input logic MEM_WB_RegWrite,  // instrucción en WB escribe rd
    input logic [3:0]  MEM_WB_Rd,

    //Forwarding hacia ID (mux4)
    output logic [1:0]  ForwardAD,
    output logic [1:0]  ForwardBD,

    //Control de pipeline 
    output logic PCWrite,
    output logic IF_ID_Write,
    output logic control_mux_sel
);

    logic load_use_stall;
    logic branch_stall;
    logic auth_stall;

    // FORWARDING A ID
    // Prioridad EX/MEM (10) > MEM/WB (01). Nunca forward desde R0.
    // Dos niveles necesarios porque negedge write hace que WB->ID sea hazard.
    // result_wb es wire combinacional -> mux_brA/B pueden usarlo sin esperar.

    always_comb begin
        if      (EX_MEM_RegWrite && (EX_MEM_Rd != 4'd0) && (EX_MEM_Rd == IF_ID_Rs1))
            ForwardAD = 2'b10;
        else if (MEM_WB_RegWrite && (MEM_WB_Rd != 4'd0) && (MEM_WB_Rd == IF_ID_Rs1))
            ForwardAD = 2'b01;
        else
            ForwardAD = 2'b00;

        if      (EX_MEM_RegWrite && (EX_MEM_Rd != 4'd0) && (EX_MEM_Rd == IF_ID_Rs2))
            ForwardBD = 2'b10;
        else if (MEM_WB_RegWrite && (MEM_WB_Rd != 4'd0) && (MEM_WB_Rd == IF_ID_Rs2))
            ForwardBD = 2'b01;
        else
            ForwardBD = 2'b00;
    end

    // LOAD en EX no puede forwarded a EX del siguiente ciclo -> stall 1 ciclo.
    always_comb begin
        load_use_stall = 1'b0;
        if (ID_EX_MemRead && (ID_EX_Rd != 4'd0))
            if ((ID_EX_Rd == IF_ID_Rs1) || (ID_EX_Rd == IF_ID_Rs2))
                load_use_stall = 1'b1;
    end

    // BRANCH / JR HAZARD
    // Caso A — ALU en EX: alu_result_mem aún no tiene el valor.
    //          -> stall 1. Al siguiente ciclo ForwardAD/BD=10 resuelve.
    // Caso B — LOAD en MEM: dato no disponible como wire -> stall 1.
    // Caso C — ALU en MEM: ForwardAD/BD=10 -> sin stall.
    // Caso D —  en WB: ForwardAD/BD=01 (result_wb wire) -> sin stall.
    //
    // Aplica igual para JR (usa BrA como jr_target en ID).

    always_comb begin
        branch_stall = 1'b0;
        if (BranchD || JumpRegD) begin
            // Caso A: instrucción en EX (cualquiera que no sea load)
            if (ID_EX_RegWrite && (ID_EX_Rd != 4'd0))
                if ((ID_EX_Rd == IF_ID_Rs1) || (ID_EX_Rd == IF_ID_Rs2))
                    branch_stall = 1'b1;  // Stall siempre, no solo si !MemRead
            // Caso B: LOAD en MEM
            if (MEM_MemtoReg && (EX_MEM_Rd != 4'd0))
                if ((EX_MEM_Rd == IF_ID_Rs1) || (EX_MEM_Rd == IF_ID_Rs2))
                    branch_stall = 1'b1;
        end
    end

    // AUTH-UNIT HAZARD
    // auth_unit lee el regfile en ID, sin forwarding path.
    // El negedge write de WB ocurre después del posedge read de ID.
    // Stall mientras el productor esté en EX, MEM (ALU), MEM (LOAD) o WB.
    //
    // Diferencia respecto a branch: branch usa result_wb (wire) -> sin stall en WB.
    //                               auth_unit lee regs[] físico -> stall en WB.
    always_comb begin
        auth_stall = 1'b0;
        if (IsAuthD) begin
            // en EX
            if (ID_EX_RegWrite && (ID_EX_Rd != 4'd0))
                if ((ID_EX_Rd == IF_ID_Rs1) || (ID_EX_Rd == IF_ID_Rs2))
                    auth_stall = 1'b1;
            // ALU en MEM
            if (EX_MEM_RegWrite && !MEM_MemtoReg && (EX_MEM_Rd != 4'd0))
                if ((EX_MEM_Rd == IF_ID_Rs1) || (EX_MEM_Rd == IF_ID_Rs2))
                    auth_stall = 1'b1;
            // LOAD en MEM
            if (EX_MEM_RegWrite && MEM_MemtoReg && (EX_MEM_Rd != 4'd0))
                if ((EX_MEM_Rd == IF_ID_Rs1) || (EX_MEM_Rd == IF_ID_Rs2))
                    auth_stall = 1'b1;
            //WB (negedge escribe después del posedge de ID)
            if (MEM_WB_RegWrite && (MEM_WB_Rd != 4'd0))
                if ((MEM_WB_Rd == IF_ID_Rs1) || (MEM_WB_Rd == IF_ID_Rs2))
                    auth_stall = 1'b1;
        end
    end

    // CONTROL 
    always_comb begin
        PCWrite = 1'b1;
        IF_ID_Write = 1'b1;
        control_mux_sel = 1'b0;

        if (load_use_stall || branch_stall || auth_stall) begin
            PCWrite  = 1'b0;
            IF_ID_Write = 1'b0;
            control_mux_sel = 1'b1;
        end
    end

endmodule

