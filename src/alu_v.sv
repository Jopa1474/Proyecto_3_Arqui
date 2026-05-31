// Modulo ALU para las instrucciones criptográficas:
// TEA_ADD1: rd = (rs1 << 4) + K[i]
// TEA_ADD2: rd = (rs1 >> 5) + K[i]

module alu_v (
    input logic [31:0] rs1, // Primer operando
    input logic [31:0] K,   // Clave para operaciones TEA
    input logic [1:0] tea_op, // Operacion seleccionada
    output logic [31:0] result // Resultado
);

always_comb begin
    case (tea_op)
        2'b01: result = (rs1 << 4) + K; // TEA_ADD1 parte shift
        2'b10: result = (rs1 >> 5) + K; // TEA_ADD2 parte shift
        default: result = 32'b0;
    endcase
end

endmodule