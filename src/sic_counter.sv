module sic_counter (
    input  logic clk,
    input  logic rst,
    input  logic enable,
    input  logic clear,
    output logic expired
);

    localparam int SESSION_LIMIT = 4000;
    localparam int COUNT_W = $clog2(SESSION_LIMIT + 1);

    logic [COUNT_W-1:0] count;

    assign expired = (count >= SESSION_LIMIT[COUNT_W-1:0]);

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            count <= '0;
        end else if (enable && !expired) begin
            count <= count + 1'b1;
        end
    end

endmodule