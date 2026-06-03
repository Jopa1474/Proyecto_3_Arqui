`timescale 1ns/1ps
// =============================================================================
// data_memoryv2_tb.sv — Unit Testbench for Realistic Main Memory Controller
// =============================================================================
// Verifies:
//   T1: Single-word read latency (25 CPU cycles)
//   T2: Single-word write + readback
//   T3: Burst read (8 words)
//   T4: Back-to-back requests
//   T5: Alignment fault handling
//   T6: Performance counter accuracy
// =============================================================================

module data_memoryv2_tb;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic        clk = 0;
    logic        rst_n = 0;

    logic [31:0] addr = 0;
    logic [31:0] write_data = 0;
    logic        mem_req = 0;
    logic        mem_wr_en = 0;
    logic        burst_en = 0;

    logic [31:0] read_data;
    logic [31:0] burst_data [0:7];
    logic        mem_ready;
    logic        mem_valid;
    logic        align_fault;

    logic [31:0] total_mem_accesses;
    logic [31:0] total_mem_cycles;
    logic [31:0] burst_count;

    // =========================================================================
    // Clock: 100 MHz → 10ns period
    // =========================================================================
    always #5 clk = ~clk;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    data_memoryv2 #(
        .DATA_WIDTH(32),
        .MEM_WORDS(16384),
        .SINGLE_LATENCY(25),
        .BURST_LEN(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr),
        .write_data(write_data),
        .mem_req(mem_req),
        .mem_wr_en(mem_wr_en),
        .burst_en(burst_en),
        .read_data(read_data),
        .burst_data(),
        .mem_ready(mem_ready),
        .mem_valid(mem_valid),
        .align_fault(align_fault),
        .total_mem_accesses(total_mem_accesses),
        .total_mem_cycles(total_mem_cycles),
        .burst_count(burst_count)
    );

    // Bypass port connection because Icarus Verilog has bug with unpacked array ports
    for (genvar i = 0; i < 8; i++) begin : gen_burst_conn
        assign burst_data[i] = dut.burst_data[i];
    end


    // =========================================================================
    // Test Variables
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;
    integer cycle_counter;

    task automatic check(input string test_name, input logic condition);
        if (condition) begin
            $display("  [PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s", test_name);
            fail_count++;
        end
    endtask

    // Count CPU cycles until mem_ready goes HIGH
    task automatic wait_until_ready(output int cycles_waited);
        cycles_waited = 0;
        while (!mem_ready) begin
            @(posedge clk);
            cycles_waited++;
        end
    endtask

    // Count CPU cycles until mem_valid pulse
    task automatic wait_until_valid(output int cycles_waited);
        cycles_waited = 0;
        while (!mem_valid) begin
            @(posedge clk);
            cycles_waited++;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("sim/data_memoryv2_tb.vcd");
        $dumpvars(0, data_memoryv2_tb);

        $display("=== data_memoryv2 Unit Testbench ===");
        $display("");

        // Reset
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;

        // Pre-load some known data directly for read tests
        dut.mem[0]  = 32'hAAAA_0000;
        dut.mem[1]  = 32'hAAAA_0001;
        dut.mem[2]  = 32'hAAAA_0002;
        dut.mem[3]  = 32'hAAAA_0003;
        dut.mem[4]  = 32'hAAAA_0004;
        dut.mem[5]  = 32'hAAAA_0005;
        dut.mem[6]  = 32'hAAAA_0006;
        dut.mem[7]  = 32'hAAAA_0007;
        dut.mem[64] = 32'hDEAD_BEEF; // byte addr 0x100

        // =====================================================================
        // T1: Single-word READ — verify 25-cycle latency
        // =====================================================================
        begin
            int cyc;
            $display("--- T1: Single-word READ latency ---");

            check("T1.0 mem_ready HIGH before request", mem_ready == 1);

            // Issue read request: hold mem_req for 1 cycle
            addr      = 32'h0000_0100;  // word_index = 64
            mem_wr_en = 0;
            burst_en  = 0;
            mem_req   = 1;
            @(posedge clk); #1;
            // mem_ready should drop immediately (combinational)
            check("T1.1 mem_ready LOW after request", mem_ready == 0);
            mem_req = 0;

            // Wait for data valid
            wait_until_valid(cyc);
            $display("  T1: mem_valid after %0d CPU cycles", cyc);
            check("T1.2 latency in [24, 28]", cyc >= 24 && cyc <= 28);
            check("T1.3 read_data == 0xDEADBEEF", read_data == 32'hDEAD_BEEF);

            // Wait for ready to return
            @(posedge clk); #1;
            wait_until_ready(cyc);
            check("T1.4 mem_ready returns HIGH", mem_ready == 1);
        end

        // =====================================================================
        // T2: Single-word WRITE + readback
        // =====================================================================
        begin
            int cyc;
            $display("--- T2: Single-word WRITE + readback ---");

            addr       = 32'h0000_0200; // word_index = 128
            write_data = 32'hCAFE_BABE;
            mem_wr_en  = 1;
            burst_en   = 0;
            mem_req    = 1;
            @(posedge clk); #1;
            check("T2.0 mem_ready LOW after write req", mem_ready == 0);
            mem_req = 0;

            // Wait for controller to become idle (write complete)
            wait_until_ready(cyc);
            $display("  T2: write completed after %0d CPU cycles", cyc);
            check("T2.1 write latency in [24, 30]", cyc >= 24 && cyc <= 30);

            // Readback
            @(posedge clk); #1;
            addr      = 32'h0000_0200;
            mem_wr_en = 0;
            burst_en  = 0;
            mem_req   = 1;
            @(posedge clk); #1;
            mem_req = 0;

            wait_until_valid(cyc);
            check("T2.2 readback == 0xCAFEBABE", read_data == 32'hCAFE_BABE);

            @(posedge clk); #1;
            wait_until_ready(cyc);
        end

        // =====================================================================
        // T3: Burst READ — 8 words
        // =====================================================================
        begin
            int cyc;
            $display("--- T3: Burst READ (8 words) ---");

            @(posedge clk); #1;
            addr      = 32'h0000_0000; // word_index = 0, words 0..7
            mem_wr_en = 0;
            burst_en  = 1;
            mem_req   = 1;
            @(posedge clk); #1;
            mem_req  = 0;
            burst_en = 0;

            // Wait for completion
            wait_until_valid(cyc);
            $display("  T3: burst completed after %0d CPU cycles", cyc);
            check("T3.1 burst latency in [35, 55]", cyc >= 35 && cyc <= 55);

            // Debug: show all burst data
            for (int i = 0; i < 8; i++)
                $display("  burst_data[%0d] = %08h, dut.burst_data = %08h (expected %08h)", i, burst_data[i], dut.burst_data[i], 32'hAAAA_0000 + i);

            // Verify burst data
            check("T3.2 burst_data[0] == 0xAAAA0000", burst_data[0] == 32'hAAAA_0000);
            check("T3.3 burst_data[1] == 0xAAAA0001", burst_data[1] == 32'hAAAA_0001);
            check("T3.4 burst_data[7] == 0xAAAA0007", burst_data[7] == 32'hAAAA_0007);

            @(posedge clk); #1;
            wait_until_ready(cyc);
        end

        // =====================================================================
        // T4: Back-to-back requests
        // =====================================================================
        begin
            int cyc;
            $display("--- T4: Back-to-back requests ---");

            // First request
            @(posedge clk); #1;
            addr      = 32'h0000_0000;
            mem_wr_en = 0;
            burst_en  = 0;
            mem_req   = 1;
            @(posedge clk); #1;
            mem_req = 0;

            // Verify busy
            check("T4.1 mem_ready LOW during first req", mem_ready == 0);

            // Wait for first to complete
            wait_until_ready(cyc);

            // Second request
            @(posedge clk); #1;
            addr      = 32'h0000_0004;
            mem_wr_en = 0;
            burst_en  = 0;
            mem_req   = 1;
            @(posedge clk); #1;
            mem_req = 0;

            wait_until_valid(cyc);
            check("T4.2 second read == 0xAAAA0001", read_data == 32'hAAAA_0001);

            @(posedge clk); #1;
            wait_until_ready(cyc);
        end

        // =====================================================================
        // T5: Alignment fault
        // =====================================================================
        begin
            $display("--- T5: Alignment fault ---");

            @(posedge clk); #1;
            addr      = 32'h0000_0103; // Misaligned
            mem_wr_en = 0;
            burst_en  = 0;
            mem_req   = 1;
            #1;
            check("T5.1 align_fault asserted", align_fault == 1);
            @(posedge clk); #1;
            mem_req = 0;
            @(posedge clk); #1;
            check("T5.2 mem_ready still HIGH", mem_ready == 1);

            // Misaligned write
            @(posedge clk); #1;
            addr       = 32'h0000_0201;
            write_data = 32'hBAD0_0000;
            mem_wr_en  = 1;
            burst_en   = 0;
            mem_req    = 1;
            #1;
            check("T5.3 align_fault on misaligned write", align_fault == 1);
            @(posedge clk); #1;
            mem_req = 0;
            @(posedge clk); #1;
            check("T5.4 mem_ready still HIGH", mem_ready == 1);
        end

        // =====================================================================
        // T6: Performance counters
        // =====================================================================
        begin
            $display("--- T6: Performance counters ---");

            $display("  total_mem_accesses = %0d", total_mem_accesses);
            $display("  total_mem_cycles   = %0d", total_mem_cycles);
            $display("  burst_count        = %0d", burst_count);

            // T1(read) + T2(write+read) + T3(burst) + T4(read+read) = 6 accesses
            check("T6.1 total_mem_accesses == 6", total_mem_accesses == 6);
            check("T6.2 total_mem_cycles > 0", total_mem_cycles > 0);
            check("T6.3 burst_count == 1", burst_count == 1);
        end

        // =====================================================================
        // Summary
        // =====================================================================
        $display("");
        $display("=== RESULTS: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #2000000;
        $display("TIMEOUT: simulation exceeded 2ms");
        $finish;
    end

endmodule
