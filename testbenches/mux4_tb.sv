// Testbench: mux4_tb
// Verifica funcionamiento del multiplexor 4:1

`timescale 1ns/1ps

module mux4_tb;

    logic [31:0] d0, d1, d2, d3;
    logic [1:0] sel;

    logic [31:0] y;

    mux4 #(32) dut (
        .d0(d0),
        .d1(d1),
        .d2(d2),
        .d3(d3),
        .sel(sel),
        .y(y)
    );

    initial begin
        $dumpfile("sim/mux4_tb.vcd");             
        $dumpvars(0, mux4_tb);

        $display("=== mux4_tb start ===");

        $monitor("t=%0t | sel=%b | d0=0x%08h d1=0x%08h d2=0x%08h d3=0x%08h || y=0x%08h",
                 $time, sel, d0, d1, d2, d3, y);

        // Valores iniciales
        d0 = 32'h00000000;
        d1 = 32'h11111111;
        d2 = 32'h22222222;
        d3 = 32'h33333333;
        sel = 2'b00;

        // Caso 1: sel=00 → d0
        #5 sel = 2'b00;

        // Caso 2: sel=01 → d1
        #5 sel = 2'b01;

        // Caso 3: sel=10 → d2
        #5 sel = 2'b10;

        // Caso 4: sel=11 → d3
        #5 sel = 2'b11;

        // Caso 5: cambiar datos dinámicamente
        #5 d0 = 32'hAAAA0000;
           d1 = 32'hBBBB1111;
           d2 = 32'hCCCC2222;
           d3 = 32'hDDDD3333;
           sel = 2'b00;

        #5 sel = 2'b01;
        #5 sel = 2'b10;
        #5 sel = 2'b11;

        // Caso 6: valores iguales
        #5 d0 = 32'hFFFFFFFF;
           d1 = 32'hFFFFFFFF;
           d2 = 32'hFFFFFFFF;
           d3 = 32'hFFFFFFFF;
           sel = 2'b10;

        #5;
        $display("=== mux4_tb end ===");
        $finish;
    end

endmodule