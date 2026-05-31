`timescale 1ns/1ps

module data_memory_dump_tb;

    logic clk;
    logic rst_n;

    logic [31:0] addr;
    logic [31:0] write_data;
    logic mem_read;
    logic mem_write;

    logic [31:0] read_data;
    logic align_fault;

    // Instancia
    data_memory uut (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr),
        .write_data(write_data),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .read_data(read_data),
        .align_fault(align_fault)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/data_memory_dump_tb.vcd");   
        $dumpvars(0, data_memory_dump_tb);

        // Inicialización
        clk = 0;
        rst_n = 0;
        addr = 0;
        write_data = 0;
        mem_read = 0;
        mem_write = 0;

        // Reset
        #10;
        rst_n = 1;

        // Esperar un poco (simula ejecución)
        #100;

        // Dump de memoria
        $writememh("mem/memory_dump.mem", uut.mem);

        $finish;
    end

endmodule