// Testbench: key_vault_tb
// Verifica reset, VKLOAD, lectura e invalidacion VKINV

`timescale 1ns/1ps

module key_vault_tb;

    logic clk;
    logic rst;

    logic vault_we;
    logic vault_invalidate;
    logic [1:0] vault_key_sel;
    logic [1:0] vault_word_sel;
    logic [31:0] vault_data_in;

    logic [1:0] ki_activo;
    logic [1:0] ki;
    logic [31:0] key_word_out;

    key_vault dut (
        .clk (clk),
        .rst (rst),
        .vault_we (vault_we),
        .vault_invalidate (vault_invalidate),
        .vault_key_sel (vault_key_sel),
        .vault_word_sel (vault_word_sel),
        .vault_data_in (vault_data_in),
        .ki_activo (ki_activo),
        .ki (ki),
        .key_word_out (key_word_out)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/key_vault_tb.vcd");     
        $dumpvars(0, key_vault_tb);

        $display("=== key_vault_tb start ===");

        clk = 0;
        rst = 1;

        vault_we = 0;
        vault_invalidate = 0;
        vault_key_sel = 0;
        vault_word_sel = 0;
        vault_data_in = 0;

        ki_activo = 0;
        ki = 0;

        // Reset
        #12 rst = 0;

        #5 ki_activo = 2'd0; ki = 2'd0;
        #1 $display("Lectura reset -> out=%h", key_word_out);

        // VKLOAD llave 1 palabra 0 = 11111111
        @(negedge clk);
        vault_we = 1;
        vault_key_sel = 2'd1;
        vault_word_sel = 2'd0;
        vault_data_in = 32'h11111111;

        @(negedge clk);
        vault_we = 0;

        #5 ki_activo = 2'd1; ki = 2'd0;
        #1 $display("Lectura llave1 palabra0 -> out=%h", key_word_out);

        // VKLOAD llave 1 palabra 1 = 22222222
        @(negedge clk);
        vault_we = 1;
        vault_key_sel = 2'd1;
        vault_word_sel = 2'd1;
        vault_data_in = 32'h22222222;

        @(negedge clk);
        vault_we = 0;

        #5 ki_activo = 2'd1; ki = 2'd1;
        #1 $display("Lectura llave1 palabra1 -> out=%h", key_word_out);

        // Leer una llave no escrita
        #5 ki_activo = 2'd2; ki = 2'd1;
        #1 $display("Lectura llave2 palabra1 (sin escribir) -> out=%h", key_word_out);

        // VKLOAD llave 2 palabra 3 = AABBCCDD
        @(negedge clk);
        vault_we = 1;
        vault_key_sel = 2'd2;
        vault_word_sel = 2'd3;
        vault_data_in = 32'hAABBCCDD;

        @(negedge clk);
        vault_we = 0;

        #5 ki_activo = 2'd2; ki = 2'd3;
        #1 $display("Lectura llave2 palabra3 -> out=%h", key_word_out);

        // VKINV llave 1 completa
        @(negedge clk);
        vault_invalidate = 1;
        vault_key_sel = 2'd1;

        @(negedge clk);
        vault_invalidate = 0;

        #5 ki_activo = 2'd1; ki = 2'd0;
        #1 $display("Lectura llave1 palabra0 tras VKINV -> out=%h", key_word_out);

        #5 ki_activo = 2'd1; ki = 2'd1;
        #1 $display("Lectura llave1 palabra1 tras VKINV -> out=%h", key_word_out);

        // Verificar que llave 2 sigue intacta
        #5 ki_activo = 2'd2; ki = 2'd3;
        #1 $display("Lectura llave2 palabra3 final -> out=%h", key_word_out);

        $display("=== key_vault_tb end ===");
        $finish;
    end

endmodule