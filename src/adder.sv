// Módulo sumador parametrizable
// Realiza la suma combinacional de dos operandos de WIDTH bits.
// Se utiliza en el datapath para operaciones como:
// - calcular PC + 4
// - calcular direcciones de branch/jump

module adder #(parameter WIDTH = 32) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] result
);
    assign result = a + b;
endmodule