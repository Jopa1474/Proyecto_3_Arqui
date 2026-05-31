//I-type, S-type, B-type, J-type
// LLI es caso especial 

module imm_gen (
    input  logic [22:0] instruction,
    output logic [31:0] imm_out,
    output logic [1:0]  byte_sel
);

    logic [3:0]  opcode;
    logic [10:0] imm11;
    logic [14:0] imm15;
    logic [7:0]  imm8;
    logic [9:0]  imm10;
    logic sign11, sign10, sign15;

    assign opcode = instruction[22:19];
    assign imm11 = instruction[10:0];
    assign imm15 = instruction[14:0];
    assign imm8 = instruction[7:0];
    assign imm10 = instruction[9:0];
    assign byte_sel = instruction[10:9];
    assign sign11 = instruction[10];
    assign sign10 = instruction[9];
    assign sign15 = instruction[14];

    always_comb begin
        case (opcode)
            4'b0001: imm_out = {{21{sign11}}, imm11};  // ADDI
            4'b0010: begin // LLI — shift del byte a su posición
                case (byte_sel)
                    2'b00: imm_out = {24'b0, imm8};
                    2'b01: imm_out = {16'b0, imm8, 8'b0};
                    2'b10: imm_out = {8'b0,  imm8, 16'b0};
                    2'b11: imm_out = {imm8,  24'b0};
                endcase
            end
            4'b0011: imm_out = {{21{sign11}}, imm11};  // LOAD
            4'b0100: imm_out = {{21{sign11}}, imm11};  // STORE
            4'b0101: imm_out = {{22{sign10}}, imm10};  // BEQ/BNE
            4'b0110: imm_out = {{22{sign10}}, imm10};  // BGE/BGT
            4'b0111: imm_out = {{17{sign15}}, imm15};  // JAL
            default: imm_out = 32'd0;
        endcase
    end


endmodule