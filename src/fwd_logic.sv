// Lógica de forwarding (bypass) para evitar stalls en el pipeline
// Decide si tomar datos desde etapas posteriores (EX/MEM o MEM/WB)
// en lugar de usar los valores normales del register file
// Se debe poner con un mux para asignar los valores

module fwd_logic (

    // Señales de escritura en etapas posteriores

    input logic EX_MEM_MemtoReg,

    input  logic        EX_MEM_RegWrite,   // EX/MEM va a escribir en registro
    input  logic [3:0]  EX_MEM_Rd,         // Registro destino en EX/MEM

    input  logic        MEM_WB_RegWrite,   // MEM/WB va a escribir en registro
    input  logic [3:0]  MEM_WB_Rd,         // Registro destino en MEM/WB

    // Registros fuente de la instrucción actual (en etapa EX)
    input  logic [3:0]  ID_EX_Rs1,         // Primer operando
    input  logic [3:0]  ID_EX_Rs2,         // Segundo operando

    // Salidas que controlan multiplexores
    output logic [1:0]  forwardA,          // Control para operando A
    output logic [1:0]  forwardB           // Control para operando B
);

    always_comb begin
        forwardA = 2'b00;
        forwardB = 2'b00;
        // Forward para operando A
        if (EX_MEM_RegWrite && !EX_MEM_MemtoReg &&
            (EX_MEM_Rd != 4'd0) && (EX_MEM_Rd == ID_EX_Rs1))
            forwardA = 2'b10;
        else if (MEM_WB_RegWrite &&
                (MEM_WB_Rd != 4'd0) && (MEM_WB_Rd == ID_EX_Rs1))
            forwardA = 2'b01;
        else
            forwardA = 2'b00;


        if (EX_MEM_RegWrite && !EX_MEM_MemtoReg &&
            (EX_MEM_Rd != 4'd0) && (EX_MEM_Rd == ID_EX_Rs2))
            forwardB = 2'b10;
        else if (MEM_WB_RegWrite &&
                (MEM_WB_Rd != 4'd0) && (MEM_WB_Rd == ID_EX_Rs2))
            forwardB = 2'b01;  // Forward desde MEM/WB

        else
            forwardB = 2'b00;

        // Nunca hacer forwarding si el registro fuente es R0
        if (ID_EX_Rs1 == 4'd0)
            forwardA = 2'b00;

        if (ID_EX_Rs2 == 4'd0)
            forwardB = 2'b00;
    end

endmodule

/*
Casi todo viene de los regstros de pipeline, despues de pasar de EX a MEM y luego a WB

Luego en el mux se elige si hay forwarding en A o en B.
y según el binario, 
si es 0 se tira el dato normales reg_data1_EX
si es 10 elige el dato de la alu alu_result_MEM
Si es 01 elige el dato de WB write_data
Y así igual pero con el B

*/