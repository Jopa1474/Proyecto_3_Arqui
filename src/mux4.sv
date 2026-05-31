//Multiplexor 4:1
//  sel=2'b00 -> y = d0
//  sel=2'b01 -> y = d1
//  sel=2'b10 -> y = d2
//  sel=2'b11 -> y = d3
//  default   -> y = d0 
module mux4 #(parameter WIDTH = 32) (
    input  logic [WIDTH-1:0] d0, // sel=00
    input  logic [WIDTH-1:0] d1, // sel=01
    input  logic [WIDTH-1:0] d2, // sel=10
    input  logic [WIDTH-1:0] d3, // sel=11
    input  logic [1:0] sel,
    output logic [WIDTH-1:0] y
);
    always_comb begin
        case (sel)
            2'b00: y = d0;
            2'b01: y = d1;
            2'b10: y = d2;
            2'b11: y = d3;
        endcase
    end
endmodule