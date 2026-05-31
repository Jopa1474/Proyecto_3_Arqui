// Testbench: adder_tb
// Verifica suma de dos operandos

`timescale 1ns/1ps

module adder_tb;

    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] result;

    adder #(32) dut (
        .a(a),
        .b(b),
        .result(result)
    );

    initial begin
        $dumpfile("sim/adder_tb.vcd");         
        $dumpvars(0, adder_tb);

        $display("=== adder_tb start ===");

        $monitor("t=%0t | a=%0d b=%0d || result=%0d (0x%h)",
                 $time, a, b, result, result);

        // Valores iniciales
        a = 0;
        b = 0;

        // Caso 1: 0 + 0
        #5 a = 0; b = 0;

        // Caso 2: suma simple
        #5 a = 5; b = 10;

        // Caso 3: números grandes
        #5 a = 1000; b = 2000;

        // Caso 4: con cero
        #5 a = 25; b = 0;

        // Caso 5: overflow (wrap-around)
        #5 a = 32'hFFFFFFFF; b = 1;

        // Caso 6: valores arbitrarios
        #5 a = 32'h12345678; b = 32'h87654321;

        #5;
        $display("=== adder_tb end ===");
        $finish;
    end

endmodule