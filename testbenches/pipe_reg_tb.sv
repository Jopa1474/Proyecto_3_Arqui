// Testbench: pipe_reg_tb
// Verifica reset, enable y flush del registro paramétrico

`timescale 1ns/1ps

module pipe_reg_tb;

    logic clk, rst;
    logic en, flush;

    logic [31:0] d;
    logic [31:0] q;

    pipe_reg #(32) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .flush(flush),
        .d(d),
        .q(q)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/pipe_reg_tb.vcd");      
        $dumpvars(0, pipe_reg_tb);

        $display("=== pipe_reg_tb start ===");

        $monitor("t=%0t | rst=%b en=%b flush=%b | d=0x%08h || q=0x%08h",
                 $time, rst, en, flush, d, q);

        clk = 0;
        rst = 1;
        en = 0;
        flush = 0;

        d = 32'h00000000;

        // Reset
        #10 rst = 0;

        // Caso 1: en=1 → carga dato
        #5 en = 1;
           d = 32'h12345678;

        // Caso 2: nuevo dato
        #10 d = 32'h87654321;

        // Caso 3: en=0 → NO cambia
        #10 en = 0;
            d = 32'hFFFFFFFF;

        // Caso 4: flush → limpia
        #10 flush = 1;
            en = 1;

        // quitar flush
        #10 flush = 0;

        // Caso 5: vuelve a cargar
        #10 d = 32'hAAAA5555;

        // Caso 6: reset otra vez
        #10 rst = 1;
        #10 rst = 0;

        #10;
        $display("=== pipe_reg_tb end ===");
        $finish;
    end

endmodule