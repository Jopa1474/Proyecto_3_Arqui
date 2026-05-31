// Testbench: imm_gen_tb
// Description: Verifica generacion de inmediatos para
// cada tipo de instruccion del TEA-ISA 23-bit

`timescale 1ns/1ps

module imm_gen_tb;

    logic [22:0] instruction;
    logic [31:0] imm_out;
    logic [1:0]  byte_sel;

    imm_gen dut (
        .instruction(instruction),
        .imm_out(imm_out),
        .byte_sel(byte_sel)
    );

    task test(input [22:0] instr, input string desc);
        instruction = instr; #1;
        $display("%s:\n  inst=0x%06h | imm=%0d (0x%08h) byte_sel=%b\n",
                 desc, instruction, $signed(imm_out), imm_out, byte_sel);
    endtask

    initial begin
        $dumpfile("sim/imm_gen_tb.vcd");          
        $dumpvars(0, imm_gen_tb);

        $display("=== imm_gen_tb start ===\n");

        test({4'b0001, 4'b0000, 4'b0000, 11'b00000000101}, "ADDI +5");
        test({4'b0001, 4'b0000, 4'b0000, 11'b11111111111}, "ADDI -1");
        test({4'b0001, 4'b0000, 4'b0000, 11'b11111111011}, "ADDI -5");
        test({4'b0001, 4'b0000, 4'b0000, 11'b01111111111}, "ADDI +1023");

        test({4'b0010, 4'b0000, 4'b0000, 2'b00, 1'b0, 8'hB9}, "LLI 0xB9 byte_sel=00");
        test({4'b0010, 4'b0000, 4'b0000, 2'b01, 1'b0, 8'h79}, "LLI 0x79 byte_sel=01");
        test({4'b0010, 4'b0000, 4'b0000, 2'b10, 1'b0, 8'h37}, "LLI 0x37 byte_sel=10");
        test({4'b0010, 4'b0000, 4'b0000, 2'b11, 1'b0, 8'h9E}, "LLI 0x9E byte_sel=11");

        test({4'b0011, 4'b0000, 4'b0000, 11'b00000001000}, "LOAD offset=+8");
        test({4'b0011, 4'b0000, 4'b0000, 11'b10000000100}, "LOAD offset=-1020");

        test({4'b0100, 4'b0000, 4'b0000, 11'b00000000100}, "STORE offset=+4");
        test({4'b0100, 4'b0000, 4'b0000, 11'b11111111000}, "STORE offset=-8");

        test({4'b0101, 4'b0000, 4'b0000, 1'b0, 10'b0111111100}, "BEQ offset=+508");
        test({4'b0101, 4'b0000, 4'b0000, 1'b1, 10'b1000000100}, "BNE offset=-508");

        test({4'b0110, 4'b0000, 4'b0000, 1'b0, 10'b0000001000}, "BGE offset=+8");
        test({4'b0110, 4'b0000, 4'b0000, 1'b1, 10'b1111111000}, "BGT offset=-8");

        test({4'b0111, 4'b0000, 15'b000000001100100}, "JAL offset=+100");
        test({4'b0111, 4'b0000, 15'b111111111111100}, "JAL offset=-4");
        test({4'b0111, 4'b0000, 15'b011111111111111}, "JAL offset=+16383");

        test({4'b1111, 19'b0}, "default reservado");

        $display("=== imm_gen_tb end ===");
        $finish;
    end

endmodule