//  Registro de pipeline paramétrico con reset, enable y flush
module pipe_reg #(
    parameter WIDTH = 32
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic flush,

    input logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    always_ff @(posedge clk) begin
        if (rst || flush)
            q <= '0;
        else if (en)
            q <= d;
    end

endmodule