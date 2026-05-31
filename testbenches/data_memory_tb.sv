`timescale 1ns/1ps

module data_memory_tb;

    logic        clk        = 0;
    logic        rst_n      = 0;
    logic [31:0] addr       = 0;
    logic [31:0] write_data = 0;
    logic        mem_read   = 0;
    logic        mem_write  = 0;
    logic [31:0] read_data;
    logic        align_fault;

    always #5 clk = ~clk;

    data_memory dut (.*);

    initial begin
        $dumpfile("sim/data_memory_tb.vcd");        
        $dumpvars(0, data_memory_tb);

        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // Test 1 escribir y leer en la misma dirección
        $display("Test 1: STORE + LOAD basico");
        addr       = 32'h0000_0100;
        write_data = 32'hDEAD_BEEF;
        mem_write  = 1;
        @(posedge clk); #1;
        mem_write = 0;

        mem_read = 1;
        @(posedge clk); #1;
        mem_read = 0;
        @(posedge clk); #1;

        if (read_data == 32'hDEAD_BEEF)
            $display("  bueno: leyo 0x%08X", read_data);
        else
            $display("  malo: esperaba 0xDEADBEEF, leyo 0x%08X", read_data);


        //Test 2 dos direcciones distintas no se sobreponen
        $display("Test 2: dos direcciones independientes");
        addr = 32'h0000_0200; write_data = 32'h1111_1111; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;

        addr = 32'h0000_0204; write_data = 32'h2222_2222; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;

        addr = 32'h0000_0200; mem_read = 1;
        @(posedge clk); #1; mem_read = 0;
        @(posedge clk); #1;
        if (read_data == 32'h1111_1111)
            $display("  bueno: addr 0x200 = 0x%08X", read_data);
        else
            $display("  malo: addr 0x200 esperaba 0x11111111, leyo 0x%08X", read_data);

        addr = 32'h0000_0204; mem_read = 1;
        @(posedge clk); #1; mem_read = 0;
        @(posedge clk); #1;
        if (read_data == 32'h2222_2222)
            $display("  bueno: addr 0x204 = 0x%08X", read_data);
        else
            $display("  malo: addr 0x204 esperaba 0x22222222, leyo 0x%08X", read_data);

        //Test 3 sobrescribir un valor
        $display("Test 3 sobrescribir valor existente");
        addr = 32'h0000_0100; write_data = 32'hCAFE_BABE; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;

        mem_read = 1;
        @(posedge clk); #1; mem_read = 0;
        @(posedge clk); #1;
        if (read_data == 32'hCAFE_BABE)
            $display("  bueno: sobrescritura ok, leyo 0x%08X", read_data);
        else
            $display("  malo: esperaba 0xCAFEBABE, leyo 0x%08X", read_data);


        //Test 4: align_fault en STORE desalineado no debe escribir

        $display("Test 4 STORE desalineado (addr[1:0]=01)");
        addr = 32'h0000_0301; write_data = 32'hBAD0_0000; mem_write = 1;
        #1;
        if (align_fault)
            $display("  bueno: align_fault activo");
        else
            $display("  malo: align_fault deberia estar en 1");
        @(posedge clk); #1; mem_write = 0;

        addr = 32'h0000_0300; mem_read = 1;
        @(posedge clk); #1; mem_read = 0;
        @(posedge clk); #1;
        if (read_data == 32'h0)
            $display("  bueno: memoria intacta en 0x300");
        else
            $display("  malo: se escribio algo en 0x300, leyo 0x%08X", read_data);


        // Test 5 align_fault en LOAD desalineado
        $display("Test 5: LOAD desalineado (addr[1:0]=10)");
        addr = 32'h0000_0202; mem_read = 1;
        #1;
        if (align_fault)
            $display("  bueno: align_fault activo");
        else
            $display("  malo: align_fault deberia estar en 1");
        @(posedge clk); #1; mem_read = 0;


        // Test 6: dirección alineada no genera fault
        $display("Test 6: LOAD alineado no genera fault");
        addr = 32'h0000_0200; mem_read = 1; #1;
        if (!align_fault)
            $display("  bueno: align_fault inactivo");
        else
            $display("  malo: align_fault no deberia estar activo");
        @(posedge clk); #1; mem_read = 0;

        $display("Fin");
        $finish;
    end

endmodule