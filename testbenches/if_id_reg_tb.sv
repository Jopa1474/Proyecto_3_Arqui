// Testbench: if_id_reg_tb
// Verifica reset, enable y flush del IF/ID

`timescale 1ns/1ps

module if_id_reg_tb;

    logic clk, rst;
    logic en, flush;

    logic [22:0] in_instr;
    logic [31:0] in_pc;

    logic [22:0] instr;
    logic [31:0] pc;

    if_id_reg dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .flush(flush),
        .in_instr(in_instr),
        .in_pc(in_pc),
        .instr(instr),
        .pc(pc)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/if_id_reg_tb.vcd");     
        $dumpvars(0, if_id_reg_tb);

        $display("=== if_id_reg_tb start ===");

        $monitor("t=%0t | rst=%b en=%b flush=%b | in: instr=0x%06h pc=0x%08h || out: instr=0x%06h pc=0x%08h",
                 $time, rst, en, flush,
                 in_instr, in_pc,
                 instr, pc);

        clk = 0;
        rst = 1;
        en = 0;
        flush = 0;

        in_instr = 23'h0;
        in_pc = 32'h0;

        // Reset
        #10 rst = 0;

        // Caso 1: en=1 → carga valores
        #5 en = 1;
           in_instr = 23'h123456;
           in_pc = 32'h00000004;

        // Caso 2: nuevos valores
        #10 in_instr = 23'h654321;
            in_pc = 32'h00000008;

        // Caso 3: en=0 → NO cambia
        #10 en = 0;
            in_instr = 23'hFFFFFF;
            in_pc = 32'hFFFFFFFF;

        // Caso 4: flush=1 → limpia (NOP)
        #10 flush = 1;
            en = 1;

        // quitar flush
        #10 flush = 0;

        // Caso 5: vuelve a cargar
        #10 in_instr = 23'h00ABCD;
            in_pc = 32'h0000000C;

        // Caso 6: reset otra vez
        #10 rst = 1;
        #10 rst = 0;

        #10;
        $display("=== if_id_reg_tb end ===");
        $finish;
    end

endmodule