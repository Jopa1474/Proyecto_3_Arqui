// Registro de pipeline ID/EX
module id_ex_reg (
    input logic clk, rst,
    input logic en,
    input logic nop,
    //halt in
    input  logic in_is_halt,
    // Control in
    input logic in_reg_write,
    input logic [1:0] in_wb_sel,
    input logic in_mem_write,
    input logic in_mem_read,
    input logic in_alu_src,
    input logic [2:0] in_alu_op,
    input logic in_is_vault,
    input logic [31:0] in_key_word,
    input logic in_is_lli, 
    input logic [1:0] in_byte_sel,
    input logic [1:0] in_tea_op,

    // Data in
    input logic [31:0] in_pc,
    input logic [31:0] in_src_a,
    input logic [31:0] in_src_b,
    input logic [31:0] in_imm,
    input logic [3:0] in_rd,
    input logic [3:0] in_rs1,
    input logic [3:0] in_rs2,

    //halt out
    output logic is_halt, 
    // Control out
    output logic reg_write,
    output logic [1:0] wb_sel,
    output logic mem_write,
    output logic mem_read,
    output logic alu_src,
    output logic [2:0] alu_op,
    output logic is_vault,
    output logic [31:0] key_word,
    output logic is_lli, 
    output logic [1:0] byte_sel,
    output logic [1:0] tea_op,

    // Data out
    output logic [31:0] pc,
    output logic [31:0] src_a,
    output logic [31:0] src_b,
    output logic [31:0] imm,
    output logic [3:0] rd,
    output logic [3:0] rs1,
    output logic [3:0] rs2
);
    always_ff @(posedge clk) begin

        if (rst || nop) begin
            is_halt  <= '0;
            reg_write <= '0;
            wb_sel <= '0;
            mem_write <= '0;
            mem_read <= '0;
            alu_src <= '0;
            alu_op <= '0;
            is_vault <= '0;
            key_word <= '0;
            is_lli <= '0;
            byte_sel <= '0;
            tea_op <= '0;
            pc <= '0;
            src_a <= '0;
            src_b <= '0;
            imm <= '0;
            rd <= '0;
            rs1 <= '0;
            rs2 <= '0;

        end else if (en) begin
            is_halt   <= in_is_halt;
            reg_write <= in_is_halt ? 1'b0 : in_reg_write;
            wb_sel <= in_is_halt ? 1'b0 : in_wb_sel;
            mem_write <= in_is_halt ? 1'b0 : in_mem_write;
            mem_read <= in_is_halt ? 1'b0 : in_mem_read;
            alu_src <= in_is_halt ? 1'b0 : in_alu_src;
            alu_op <= in_is_halt ? 1'b0 : in_alu_op;
            is_vault <= in_is_halt ? 1'b0 : in_is_vault;
            key_word <= in_key_word;
            is_lli <= in_is_halt ? 1'b0 : in_is_lli; 
            byte_sel <= in_byte_sel;
            tea_op <= in_is_halt ? 1'b0 : in_tea_op;
            pc <= in_pc;
            src_a <= in_src_a;
            src_b <= in_src_b;
            imm <= in_imm;
            rd <= in_rd;
            rs1 <= in_rs1;
            rs2 <= in_rs2;
        end

    end
endmodule