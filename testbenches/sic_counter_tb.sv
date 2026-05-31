// Testbench: sic_counter_tb
// Verifica funcionamiento del contador SIC

`timescale 1ns/1ps

module sic_counter_tb;

    logic clk, rst;
    logic enable, clear;

    logic expired;

    sic_counter dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .clear(clear),
        .expired(expired)
    );

    always #1 clk = ~clk; // más rápido para no esperar mucho

    initial begin
        $dumpfile("sim/sic_counter_tb.vcd");      
        $dumpvars(0, sic_counter_tb);

        $display("=== sic_counter_tb start ===");

        $monitor("t=%0t | rst=%b en=%b clr=%b || expired=%b",
                 $time, rst, enable, clear, expired);

        clk = 0;
        rst = 1;
        enable = 0;
        clear = 0;

        // Reset
        #5 rst = 0;

        // Caso 1: enable=1 → empieza a contar
        #2 enable = 1;

        // Esperar algunos ciclos
        #20;

        // Caso 2: clear → vuelve a 0
        #2 clear = 1;
        #2 clear = 0;

        // Caso 3: vuelve a contar
        #10;

        // Caso 4: esperar hasta que expire
        // (no esperamos 4000 ciclos completos, pero lo dejamos avanzar)
        #5000;

        // Caso 5: desactivar enable
        #5 enable = 0;

        // Caso 6: reset otra vez
        #5 rst = 1;
        #5 rst = 0;

        #10;
        $display("=== sic_counter_tb end ===");
        $finish;
    end

endmodule