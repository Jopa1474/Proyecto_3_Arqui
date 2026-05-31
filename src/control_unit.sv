// Control signal generator 
// Si AUTH=0 en instruccion protegida:
// - se enruta a la Security/Auth Unit

module control_unit (
    input  logic [3:0] opcode,
    input  logic [2:0] funct3,    // R-type funct: instruction[6:4]
    input  logic [8:0] funct9,    // V-type funct: instruction[8:0]
    input  logic [1:0] res_bits,  // reservado / no usado por ahora
    input  logic cond_bit,
    input  logic auth_ok,

    output logic reg_write_en,
    output logic mem_write,
    output logic mem_read,
    output logic [1:0] wb_sel,
    output logic alu_src,
    output logic [2:0] alu_op,
    output logic is_lli,
    output logic [1:0] pc_src,    // 00=PC+4, 01=branch/JAL, 10=JR
    output logic is_vault,
    output logic halt,

    output logic [1:0] BranchTypeD,  // 00=no branch, 01=BEQ/BNE, 10=BGE/BGT
    output logic BranchCondD, // cond_bit: 0=eq/ge, 1=ne/gt (offset[10])
    output logic JumpD,        // JAL (incondicional, siempre toma)
    output logic JumpRegD,     // JR

    // Comandos hacia auth_state
    output logic do_setpwd,
    output logic do_login,
    output logic do_logout,
    output logic do_authorize,
    output logic do_vkload,
    output logic do_vkinv,
    output logic do_authchk,

    // Seguridad
    output logic auth_denied,

    // Control hacia ALU_VAULT
    output logic [1:0] tea_op // 00=none, 01=TEA_ADD1, 10=TEA_ADD2
);

    always_comb begin
        // Defaults = NOP
        reg_write_en = 1'b0;
        mem_write = 1'b0;
        mem_read = 1'b0;
        wb_sel = 2'b00;
        alu_src = 1'b0;
        alu_op = 3'b000;
        is_lli = 1'b0; 
        pc_src = 2'b00;
        is_vault = 1'b0;
        halt = 1'b0;

        BranchTypeD = 2'b00;
        BranchCondD  = 1'b0;
        JumpD = 1'b0;
        JumpRegD = 1'b0;

        do_setpwd = 1'b0;
        do_login = 1'b0;
        do_logout = 1'b0;
        do_authorize = 1'b0;
        do_vkload = 1'b0;
        do_vkinv = 1'b0;
        do_authchk = 1'b0;

        auth_denied = 1'b0;
        tea_op = 2'b00;

        case (opcode)

            4'b0000: begin // NOP
            end

            4'b0001: begin // ADDI
                reg_write_en = 1'b1;
                alu_src = 1'b1;
                alu_op = 3'b000; // ADD
            end
            4'b0010: begin // LLI
                reg_write_en = 1'b1;
                alu_src = 1'b1; // ALU_B = imm (byte shifteado)
                is_lli = 1'b1;

            end
            4'b0011: begin // LOAD
                reg_write_en = 1'b1;
                mem_read = 1'b1;  
                wb_sel = 2'b01;
                alu_src = 1'b1;
                alu_op = 3'b000;
            end

            4'b0100: begin // STORE
                mem_write = 1'b1;
                alu_src = 1'b1;
                alu_op = 3'b000; // address = rs1 + offset
            end

            4'b0101: begin  // BEQ / BNE
                BranchTypeD = 2'b01;
                BranchCondD = cond_bit;  // cond_bit sigue siendo entrada, pero solo para clasificar
            end
            4'b0110: begin  // BGE / BGT
                BranchTypeD = 2'b10;
                BranchCondD = cond_bit;
            end
            4'b0111: begin  // JAL
                JumpD = 1'b1;
                reg_write_en = 1'b1;
                wb_sel = 2'b10;
            end
            4'b1000: begin  // JR
                JumpRegD = 1'b1;
            end

            4'b1001: begin // HALT
                halt = 1'b1;
            end

            4'b1010: begin // TEA_ADD1
                is_vault = 1'b1;
                if (auth_ok) begin
                    reg_write_en = 1'b1;
                    tea_op = 2'b01;
                    wb_sel = 2'b00;
                end else begin
                    auth_denied = 1'b1;
                end
            end

            4'b1011: begin // TEA_ADD2
                is_vault = 1'b1;
                if (auth_ok) begin
                    reg_write_en = 1'b1;
                    tea_op = 2'b10;
                    wb_sel = 2'b00;// resultado de ALU_VAULT va a rd
                end else begin
                    auth_denied = 1'b1;
                end
            end

            4'b1100: begin // R-TYPE
                reg_write_en = 1'b1;

                case (funct3)
                    3'b000: alu_op = 3'b000; // ADD
                    3'b001: alu_op = 3'b001; // SUB
                    3'b010: alu_op = 3'b010; // AND
                    3'b011: alu_op = 3'b011; // OR
                    3'b100: alu_op = 3'b100; // XOR
                    3'b101: alu_op = 3'b101; // SLL
                    3'b110: alu_op = 3'b110; // SRL
                    3'b111: alu_op = 3'b111; // SRA
                    default: alu_op = 3'b000;
                endcase
            end

            4'b1101: begin // AUTH / VAULT
                is_vault = 1'b1;

                case (funct9)

                    9'b000000000: begin // SETPWD
                        do_setpwd = 1'b1;
                    end

                    9'b000000001: begin // LOGIN
                        do_login = 1'b1;
                    end

                    9'b000000010: begin // LOGOUT
                        do_logout = 1'b1;
                    end

                    9'b000000011: begin // AUTHORIZE
                        do_authorize = 1'b1;
                    end

                    9'b000000100: begin // VKLOAD
                        do_vkload = 1'b1;

                        if (!auth_ok)
                            auth_denied = 1'b1;
                    end

                    9'b000000101: begin // VKINV
                        do_vkinv = 1'b1;

                        if (!auth_ok)
                            auth_denied = 1'b1;
                    end

                    default: begin
                        // funct9 inválido = NOP
                    end

                endcase
            end

            4'b1110: begin // AUTHCHK
                is_vault = 1'b1;

                if (funct9 == 9'b000000011)
                    do_authchk = 1'b1;
            end

            default: begin
                // reservado = NOP
            end

        endcase
    end

endmodule