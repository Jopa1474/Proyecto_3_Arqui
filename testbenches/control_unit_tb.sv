// Testbench: control_unit_tb
// Verifica señales de control para cada opcode del TEA-ISA 23-bit

`timescale 1ns/1ps

module control_unit_tb;

    logic [3:0] opcode;
    logic [2:0] funct3;
    logic [8:0] funct9;
    logic [1:0] res_bits;
    logic cond_bit;
    logic BrEq, BrLt, auth_ok;

    logic reg_write_en, mem_write, mem_read;
    logic [1:0] wb_sel; 
    logic alu_src, ASel, is_vault, halt;
    logic [2:0] alu_op;
    logic [1:0] pc_src;

    logic do_setpwd, do_login, do_logout, do_authorize;
    logic do_vkload, do_vkinv, do_authchk;
    logic auth_denied;
    logic [1:0] tea_op;

    control_unit dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct9(funct9),
        .res_bits(res_bits),
        .cond_bit(cond_bit),
        .BrEq(BrEq),
        .BrLt(BrLt),
        .auth_ok(auth_ok),
        .reg_write_en(reg_write_en),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .wb_sel(wb_sel),
        .alu_src(alu_src),
        .ASel(ASel),
        .alu_op(alu_op),
        .pc_src(pc_src),
        .is_vault(is_vault),
        .halt(halt),
        .do_setpwd(do_setpwd),
        .do_login(do_login),
        .do_logout(do_logout),
        .do_authorize(do_authorize),
        .do_vkload(do_vkload),
        .do_vkinv(do_vkinv),
        .do_authchk(do_authchk),
        .auth_denied(auth_denied),
        .tea_op(tea_op)
    );

    initial begin
        $dumpfile("sim/control_unit_tb.vcd");  
        $dumpvars(0, control_unit_tb);

        $display("=== control_unit_tb start ===");

        $monitor("t=%0t op=%b f3=%b f9=%b cond=%b eq=%b lt=%b auth=%b | rwe=%b mw=%b mr=%b wb=%b asrc=%b asel=%b aop=%b pcs=%b vault=%b halt=%b | setpwd=%b login=%b logout=%b auth=%b vkl=%b vki=%b achk=%b denied=%b tea_op=%b",
                 $time, opcode, funct3, funct9,cond_bit,
                 BrEq, BrLt, auth_ok,reg_write_en, mem_write, mem_read, wb_sel, alu_src,
                 ASel, alu_op, pc_src, is_vault, halt,
                 do_setpwd, do_login, do_logout, do_authorize,
                 do_vkload, do_vkinv, do_authchk,
                 auth_denied, tea_op);

        // Valores por defecto
        opcode = 4'b1111;
        funct3 = 3'b000;
        funct9 = 9'b000000000;
        res_bits = 2'b00;
        cond_bit = 1'b0;
        BrEq = 1'b0;
        BrLt = 1'b0;
        auth_ok  = 1'b0;

        // NOP
        #5 opcode = 4'b0000;

        // R-TYPE opcode = 1100
        #5 opcode=4'b1100; funct3=3'b000; // ADD
        #5 funct3=3'b001; // SUB
        #5 funct3=3'b010; // AND
        #5 funct3=3'b011; // OR
        #5 funct3=3'b100; // XOR
        #5 funct3=3'b101; // SLL
        #5 funct3=3'b110; // SRL
        #5 funct3=3'b111; // SRA

        // I / MEM
        #5 opcode=4'b0001; funct3=3'b000; // ADDI
        #5 opcode=4'b0010; // LLI
        #5 opcode=4'b0011; // LOAD
        #5 opcode=4'b0100; // STORE

        // BRANCHES

        // BEQ
        #5 opcode=4'b0101; cond_bit=1'b0; BrEq=1'b1; BrLt=1'b0; // taken
        #5 BrEq=1'b0;  // not taken

        // BNE
        #5 cond_bit=1'b1; BrEq=1'b0; // taken
        #5 BrEq=1'b1; // not taken

        // BGE
        #5 opcode=4'b0110; cond_bit=1'b0; BrEq=1'b0; BrLt=1'b0; // taken
        #5 BrLt=1'b1;  // not taken

        // BGT
        #5 cond_bit=1'b1; BrLt=1'b0; BrEq=1'b0; // taken
        #5 BrEq=1'b1; // not taken porque son iguales

        // JUMPS
        #5 opcode=4'b0111; cond_bit=1'b0; BrEq=1'b0; BrLt=1'b0; // JAL
        #5 opcode=4'b1000; // JR

        // HALT
        #5 opcode=4'b1001;

        // TEA_ADD1
        #5 opcode=4'b1010; auth_ok=1'b1; // AUTH=1
        #5 auth_ok=1'b0;  // AUTH=0: va a Auth Unit, sin writeback

        // TEA_ADD2
        #5 opcode=4'b1011; auth_ok=1'b1; // AUTH=1
        #5 auth_ok=1'b0; // AUTH=0: va a Auth Unit, sin writeback

        // AUTH / VAULT opcode = 1101

        // VKLOAD
        #5 opcode=4'b1101; funct9=9'b000000100; auth_ok=1'b1; // AUTH=1
        #5 auth_ok=1'b0; // AUTH=0: Auth Unit marca excepción

        // VKINV
        #5 funct9=9'b000000101; auth_ok=1'b1; // AUTH=1
        #5 auth_ok=1'b0; // AUTH=0: Auth Unit marca excepción

        // SETPWD / LOGIN / LOGOUT / AUTHORIZE
        #5 funct9=9'b000000000; auth_ok=1'b0; // SETPWD
        #5 funct9=9'b000000001;  // LOGIN
        #5 funct9=9'b000000010; // LOGOUT
        #5 funct9=9'b000000011; // AUTHORIZE

        // opcode 1101 inválido -> NOP
        #5 funct9=9'b000000111;

        // AUTHCHK válido
        #5 opcode=4'b1110; funct9=9'b000000011;

        // AUTHCHK inválido -> NOP
        #5 funct9=9'b000000000;

        // Reservado -> NOP
        #5 opcode=4'b1111;

        #5;
        $display("=== control_unit_tb end ===");
        $finish;
    end

endmodule