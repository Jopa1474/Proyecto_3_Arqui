// Modulo ALU 

module alu (
    input logic [31:0] rs1, // Primer operando
    input logic [31:0] rs2, // Segundo operando
    input logic [2:0] funct, // Operacion seleccionada
    input logic [1:0] byte_sel, // Operacion de byte (para LLI)
    input logic is_lli, 
    output logic [31:0] result // Resultado
);

logic [4:0] shamt; // Cantidad de bits para shift
logic [31:0] mask;

assign shamt = rs2[4:0]; // Solo se usan los 5 bits para shift

always_comb begin
    case (byte_sel)
        2'b00: mask = 32'h00000000;
        2'b01: mask = 32'hFFFF00FF;
        2'b10: mask = 32'hFF00FFFF;
        2'b11: mask = 32'h00FFFFFF;
    endcase
end

// Definimos los casos para cada operacion
always_comb begin
     if (is_lli)
        result = (rs1 & mask) | rs2; // rs1=rd_actual, rs2=byte shifteado
    else
        case (funct)
            3'b000: result = rs1 + rs2; // ADD
            3'b001: result = rs1 - rs2; // SUB
            3'b010: result = rs1 & rs2; // AND
            3'b011: result = rs1 | rs2; // OR
            3'b100: result = rs1 ^ rs2; // XOR
            3'b101: result = rs1 << shamt; // SLL
            3'b110: result = rs1 >> shamt; // SRL
            3'b111: result = $signed(rs1) >>> shamt; // SRA
            default: result = 32'b0;
        endcase
end
endmodule

