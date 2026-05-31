//Multiplexor 2:1 
//  sel=0 -> y = d0
//  sel=1 -> y = d1
module mux2 #(parameter WIDTH = 32) (
    input  logic [WIDTH-1:0] d0, // sel=0
    input  logic [WIDTH-1:0] d1, // sel=1
    input  logic sel,
    output logic [WIDTH-1:0] y
);
    assign y = sel ? d1 : d0;
endmodule
 