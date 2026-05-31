// Testbench: mux2_tb
// Verifica funcionamiento del multiplexor 2:1

`timescale 1ns/1ps

module mux2_tb;

    logic [31:0] d0;
    logic [31:0] d1;
    logic sel;

    logic [31:0] y;

    mux2 #(32) dut (
        .d0(d0),
        .d1(d1),
        .sel(sel),
        .y(y)
    );

    initial begin
        $dumpfile("sim/mux2_tb.vcd");             
        $dumpvars(0, mux2_tb);

        $display("=== mux2_tb start ===");

        $monitor("t=%0t | sel=%b | d0=0x%08h d1=0x%08h || y=0x%08h",
                 $time, sel, d0, d1, y);

        // Valores iniciales
        d0 = 32'h00000000;
        d1 = 32'hFFFFFFFF;
        sel = 0;

        // Caso 1: sel = 0 → y = d0
        #5 sel = 0;

        // Caso 2: sel = 1 → y = d1
        #5 sel = 1;

        // Caso 3: cambiar datos con sel=0
        #5 sel = 0;
           d0 = 32'h12345678;
           d1 = 32'h87654321;

        // Caso 4: sel=1 con nuevos valores
        #5 sel = 1;

        // Caso 5: valores iguales
        #5 d0 = 32'hAAAAAAAA;
           d1 = 32'hAAAAAAAA;
           sel = 0;

        #5 sel = 1;

        #5;
        $display("=== mux2_tb end ===");
        $finish;
    end

endmodule