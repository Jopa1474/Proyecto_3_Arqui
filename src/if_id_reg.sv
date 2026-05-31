// Registro de pipeline IF/ID
module if_id_reg (
    input logic clk, rst,
    input logic en,
    input logic flush,
    
    // Data in
    input logic [22:0] in_instr,
    input logic [31:0] in_pc,

    // Data out
    output logic [22:0] instr,
    output logic [31:0] pc
);
    always_ff @(posedge clk) begin

        if (rst || flush) begin
            instr <= '0;
            pc <= '0;
        end else if (en) begin
            instr <= in_instr;
            pc <= in_pc;
        end

    end
endmodule