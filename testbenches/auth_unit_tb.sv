`timescale 1ns/1ps

module auth_unit_tb;

    logic clk;
    logic rst;

    logic do_setpwd, do_login, do_logout, do_authorize;
    logic do_vkload, do_vkinv, do_authchk;
    logic auth_denied;

    logic [31:0] rs1_data;
    logic [1:0] uid_field;
    logic [1:0] ki_field;

    logic instr_retired;

    logic auth_ok;
    logic [1:0] ki_activo;
    logic vf_flag;

    logic exc_trigger;
    logic [2:0] exc_cause;

    logic vault_we;
    logic vault_invalidate;

    auth_unit dut (
        .clk(clk),
        .rst(rst),
        .do_setpwd(do_setpwd),
        .do_login(do_login),
        .do_logout(do_logout),
        .do_authorize(do_authorize),
        .do_vkload(do_vkload),
        .do_vkinv(do_vkinv),
        .do_authchk(do_authchk),
        .auth_denied(auth_denied),
        .rs1_data(rs1_data),
        .uid_field(uid_field),
        .ki_field(ki_field),
        .instr_retired(instr_retired),
        .auth_ok(auth_ok),
        .ki_activo(ki_activo),
        .vf_flag(vf_flag),
        .exc_trigger(exc_trigger),
        .exc_cause(exc_cause),
        .vault_we(vault_we),
        .vault_invalidate(vault_invalidate)
    );

    // Clock
    always #2 clk = ~clk;

    initial begin
        $dumpfile("sim/auth_unit_tb.vcd");     
        $dumpvars(0, auth_unit_tb);
        
        $display("=== auth_unit_tb start ===");

        $monitor("t=%0t | AUTH=%b uid=%0d | exc=%b cause=%b | we=%b inv=%b",
                 $time, auth_ok, ki_activo,
                 exc_trigger, exc_cause,
                 vault_we, vault_invalidate);

        clk = 0;
        rst = 1;

        do_setpwd = 0;
        do_login = 0;
        do_logout = 0;
        do_authorize = 0;
        do_vkload = 0;
        do_vkinv = 0;
        do_authchk = 0;
        auth_denied = 0;

        rs1_data = 0;
        uid_field = 0;
        ki_field = 0;
        instr_retired = 0;

        // Reset
        #5 rst = 0;

        // AUTHORIZE correcto
        #4 do_authorize = 1;
           rs1_data = 32'hDDAABBCF;
        #6 do_authorize = 0;

        // SETPWD
        #4 do_setpwd = 1;
           rs1_data = 32'h11111111;
        #6 do_setpwd = 0;

        // LOGOUT
        #4 do_logout = 1;
        #6 do_logout = 0;

        // LOGIN correcto
        #4 do_login = 1;
           rs1_data = 32'h11111111;
        #6 do_login = 0;

        // VKLOAD
        #4 do_vkload = 1;
           rs1_data = 32'hAAAA5555;
        #6 do_vkload = 0;

        // VKINV
        #4 do_vkinv = 1;
        #6 do_vkinv = 0;

        // LOGIN incorrecto
        #4 do_login = 1;
           rs1_data = 32'h99999999;
        #6 do_login = 0;

        // AUTH DENIED externo
        #4 auth_denied = 1;
        #6 auth_denied = 0;

        #10;
        $display("=== auth_unit_tb end ===");
        $finish;
    end

endmodule