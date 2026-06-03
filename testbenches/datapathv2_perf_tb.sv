`timescale 1ns/1ps
// =============================================================================
// datapathv2_perf_tb.sv — Full-System Performance Baseline Testbench
// =============================================================================
// Integration testbench for datapathv2 (Iteration 2).
// Loads a memory-intensive test program and reports baseline performance
// metrics without caching, establishing the reference for cache benefit analysis.
//
// Metrics reported:
//   - Total execution cycles
//   - Instructions executed (retired from WB)
//   - IPC (Instructions Per Cycle)
//   - Memory stall cycles
//   - Branch stall cycles
//   - Load-use stall cycles
//   - Stall fraction
//   - Memory accesses and average access time
// =============================================================================

module datapathv2_perf_tb;

    logic clk, rst;

    datapathv2 #(.INST_INIT_FILE("mem/instructions_perfv2.mem")) dut (.clk(clk), .rst(rst));

    // 100 MHz clock → 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    logic halt_seen;

    // =========================================================================
    // Reset and Init
    // =========================================================================
    initial begin
        $dumpfile("sim/datapathv2_perf_tb.vcd");
        $dumpvars(0, datapathv2_perf_tb);

        $display("============================================================");
        $display("  Iteration 2: Performance Baseline (No Cache)");
        $display("  Realistic Main Memory — 25-cycle latency, 50 MHz");
        $display("============================================================");
        $display("");

        cycle_count = 0;
        halt_seen   = 0;

        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
    end

    // =========================================================================
    // Cycle Counter + Halt Detection
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && !halt_seen) begin
            cycle_count <= cycle_count + 1;

            if (dut.halted) begin
                halt_seen <= 1;

                $display("");
                $display("============================================================");
                $display("  PROGRAM HALTED — Cycle %0d", cycle_count);
                $display("============================================================");
                $display("");

                // ---- Performance Report ----
                $display("--- BASELINE PERFORMANCE REPORT (No Cache) ---");
                $display("");

                $display("  Total Execution Cycles:    %0d", dut.perf_cycle_count);
                $display("  Instructions Retired:      %0d", dut.perf_instr_count);

                if (dut.perf_cycle_count > 0) begin
                    // IPC as fixed-point: multiply by 1000 first for 3 decimal places
                    $display("  IPC:                       %0d.%03d",
                        dut.perf_instr_count / dut.perf_cycle_count,
                        ((dut.perf_instr_count * 1000) / dut.perf_cycle_count) % 1000);
                end

                $display("");
                $display("  --- Stall Breakdown ---");
                $display("  Memory Stall Cycles:       %0d", dut.perf_mem_stall_cycles);
                $display("  Branch Flush Cycles:       %0d", dut.perf_branch_stalls);
                $display("  Load-Use Stall Cycles:     %0d", dut.perf_load_use_stalls);

                if (dut.perf_cycle_count > 0) begin
                    $display("  Total Stall Fraction:      %0d.%01d%%",
                        ((dut.perf_mem_stall_cycles + dut.perf_branch_stalls + dut.perf_load_use_stalls) * 100) / dut.perf_cycle_count,
                        (((dut.perf_mem_stall_cycles + dut.perf_branch_stalls + dut.perf_load_use_stalls) * 1000) / dut.perf_cycle_count) % 10);
                    $display("  Mem Stall Fraction:        %0d.%01d%%",
                        (dut.perf_mem_stall_cycles * 100) / dut.perf_cycle_count,
                        ((dut.perf_mem_stall_cycles * 1000) / dut.perf_cycle_count) % 10);
                end

                $display("");
                $display("  --- Main Memory Metrics ---");
                $display("  Total Memory Accesses:     %0d", dut.dmem.total_mem_accesses);
                $display("  Total Memory Busy Cycles:  %0d", dut.dmem.total_mem_cycles);
                if (dut.dmem.total_mem_accesses > 0) begin
                    $display("  Avg Memory Access Time:    %0d CPU cycles",
                        dut.dmem.total_mem_cycles / dut.dmem.total_mem_accesses);
                end
                $display("  Burst Transfers:           %0d", dut.dmem.burst_count);

                $display("");
                $display("  PC at HALT:                0x%08h", dut.pc_out);

                $display("");
                $display("============================================================");
                $display("  END OF BASELINE REPORT");
                $display("============================================================");

                // Dump final register state
                $display("");
                $display("--- Final Register State ---");
                $display("  R0 =%08h  R1 =%08h  R2 =%08h  R3 =%08h",
                    dut.rf.regs[0],  dut.rf.regs[1],
                    dut.rf.regs[2],  dut.rf.regs[3]);
                $display("  R4 =%08h  R5 =%08h  R6 =%08h  R7 =%08h",
                    dut.rf.regs[4],  dut.rf.regs[5],
                    dut.rf.regs[6],  dut.rf.regs[7]);

                // Dump first few data memory locations
                $display("");
                $display("--- Memory Contents (0x100..0x11C) ---");
                $display("  mem[64]=%08h  mem[65]=%08h  mem[66]=%08h  mem[67]=%08h",
                    dut.dmem.mem[64], dut.dmem.mem[65],
                    dut.dmem.mem[66], dut.dmem.mem[67]);
                $display("  mem[68]=%08h  mem[69]=%08h  mem[70]=%08h  mem[71]=%08h",
                    dut.dmem.mem[68], dut.dmem.mem[69],
                    dut.dmem.mem[70], dut.dmem.mem[71]);

                #20;
                $finish;
            end
        end
    end

    // =========================================================================
    // Per-cycle trace (condensed)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && !halt_seen) begin
            // Print every 50th cycle to avoid flooding output
            if (cycle_count % 50 == 0 || dut.mem_stall || 
                dut.mem_req_out || cycle_count < 20) begin
                $display("[C%05d] PC=%08h IF=%06h stall=%b mem_req=%b mem_rdy=%b mem_val=%b | MW=%b MR=%b | R2=%08h R4=%08h R7=%08h",
                    cycle_count,
                    dut.pc_out,
                    dut.instr_if,
                    dut.mem_stall,
                    dut.mem_req_out,
                    dut.mem_ready,
                    dut.mem_valid,
                    dut.mem_write_mem,
                    dut.mem_read_mem,
                    dut.rf.regs[2],
                    dut.rf.regs[4],
                    dut.rf.regs[7]);
            end
        end
    end

    // =========================================================================
    // Writeback monitor
    // =========================================================================
    always @(negedge clk) begin
        if (!rst && !halt_seen) begin
            if (dut.rf.write_en && dut.rf.rd != 4'd0) begin
                $display("[C%05d-WB] Write R%0d = %08h", cycle_count, dut.rf.rd, dut.rf.WD3);
            end
        end
    end

    // =========================================================================
    // Timeout watchdog — realistic memory makes programs much slower
    // =========================================================================
    initial begin
        #20_000_000; // 20 ms = 2,000,000 CPU cycles at 100 MHz
        $display("TIMEOUT: simulation exceeded 20ms / 2M cycles");
        $display("  cycles so far: %0d", cycle_count);
        $display("  perf_cycle_count: %0d", dut.perf_cycle_count);
        $display("  perf_instr_count: %0d", dut.perf_instr_count);
        $finish;
    end

endmodule
