// Registro de pipeline MEM/WB
module mem_wb_reg (
    input logic clk, rst,
    input logic en,

    //halt in
    input  logic in_is_halt,
    
    // Control in
    input logic in_reg_write,
    input logic [1:0] in_wb_sel,

    // Data in
    input logic [31:0] in_read_data,
    input logic [31:0] in_alu_result,
    input logic [31:0] in_pc_plus4,
    input logic [3:0] in_rd,

    //halt out
    output logic is_halt, 

    // Control out
    output logic reg_write,
    output logic [1:0] wb_sel,

    // Data out
    output logic [31:0] read_data,
    output logic [31:0] alu_result,
    output logic [31:0] pc_plus4,
    output logic [3:0] rd
);
    always_ff @(posedge clk) begin
        if (rst) begin
            is_halt <= '0;
            reg_write <= '0;
            wb_sel <= '0;
            read_data <= '0;
            alu_result <= '0;
            pc_plus4 <= '0;
            rd <= '0;

        end else if (en) begin
            is_halt <= in_is_halt;
            reg_write <= in_reg_write;
            wb_sel <= in_wb_sel;
            read_data <= in_read_data;
            alu_result <= in_alu_result;
            pc_plus4 <= in_pc_plus4;
            rd <= in_rd;
        end
    end
endmodule