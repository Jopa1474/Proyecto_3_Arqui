`timescale 1ns/1ps

`ifndef PROGRAM_FILE
`define PROGRAM_FILE "mem/instructions.mem"
`endif

`ifndef BASELINE_CSV_FILE
`define BASELINE_CSV_FILE "sim/nocache_timeline.csv"
`endif

`ifndef BENCH_ID
`define BENCH_ID 0
`endif

module datapath_benchmark_tb;

    function automatic string benchmark_title();
        case (`BENCH_ID)
            1: benchmark_title = "Benchmark 1 - Sequential";
            2: benchmark_title = "Benchmark 2 - Stride";
            3: benchmark_title = "Benchmark 3 - Random";
            4: benchmark_title = "Benchmark 4 - Thousands";
            default: benchmark_title = "Legacy datapath benchmark";
        endcase
    endfunction

    logic clk, rst;

    datapath #(
        .INST_INIT_FILE(`PROGRAM_FILE)
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int cycle_count;
    int perf_cycle_count;
    int perf_instr_count;
    int perf_mem_reads;
    int perf_mem_writes;
    int perf_mem_accesses;
    int perf_mem_cycles;
    int perf_branch_stalls;
    int perf_load_use_stalls;
    logic halt_reported;
    logic mem_write_wb;
    logic was_branch_ex;
    logic was_branch_mem;
    logic was_branch_wb;
    integer csv_fd;

    wire wb_valid = (dut.reg_write_wb || mem_write_wb || was_branch_wb) && !dut.halted;
    wire [31:0] ipc_x1000 = (perf_cycle_count != 0) ? ((perf_instr_count * 1000) / perf_cycle_count) : 32'd0;

    initial begin
        $dumpfile("sim/datapath_benchmark_tb.vcd");
        $dumpvars(0, datapath_benchmark_tb);

        $display("====================================================================");
        $display("  datapath_benchmark_tb - Datapath Without Cache");
        $display("  Benchmark: %s", benchmark_title());
        $display("====================================================================");
        $display("");

        csv_fd = $fopen(`BASELINE_CSV_FILE, "w");
        if (csv_fd == 0) begin
            $display("[WARN] No se pudo abrir %s para escritura.", `BASELINE_CSV_FILE);
        end else begin
            $fwrite(csv_fd,
                "cycle,mem_read,mem_write,mem_reads,mem_writes,mem_accesses,mem_cycles,perf_cycles,perf_instr,perf_stall_branch,perf_stall_load_use,ipc_x1000\n");
        end

        cycle_count = 0;
        perf_cycle_count = 0;
        perf_instr_count = 0;
        perf_mem_reads = 0;
        perf_mem_writes = 0;
        perf_mem_accesses = 0;
        perf_mem_cycles = 0;
        perf_branch_stalls = 0;
        perf_load_use_stalls = 0;
        halt_reported = 1'b0;
        mem_write_wb = 1'b0;
        was_branch_ex = 1'b0;
        was_branch_mem = 1'b0;
        was_branch_wb = 1'b0;

        rst = 1'b1;
        repeat(3) @(posedge clk);
        rst = 1'b0;

        $display("[INIT] Reset released at cycle 3");
        $display("");
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 0;
            perf_cycle_count <= 0;
            perf_instr_count <= 0;
            perf_mem_reads <= 0;
            perf_mem_writes <= 0;
            perf_mem_accesses <= 0;
            perf_mem_cycles <= 0;
            perf_branch_stalls <= 0;
            perf_load_use_stalls <= 0;
            mem_write_wb <= 1'b0;
            was_branch_ex <= 1'b0;
            was_branch_mem <= 1'b0;
            was_branch_wb <= 1'b0;
        end else if (!dut.halted) begin
            cycle_count <= cycle_count + 1;
            perf_cycle_count <= perf_cycle_count + 1;

            if (wb_valid)
                perf_instr_count <= perf_instr_count + 1;

            if (dut.mem_read_mem)
                perf_mem_reads <= perf_mem_reads + 1;

            if (dut.mem_write_mem)
                perf_mem_writes <= perf_mem_writes + 1;

            if (dut.mem_read_mem || dut.mem_write_mem) begin
                perf_mem_accesses <= perf_mem_accesses + 1;
                perf_mem_cycles <= perf_mem_cycles + 1;
            end

            if (dut.haz.branch_stall)
                perf_branch_stalls <= perf_branch_stalls + 1;

            if (dut.haz.load_use_stall)
                perf_load_use_stalls <= perf_load_use_stalls + 1;

            mem_write_wb <= dut.mem_write_mem;
            was_branch_ex <= dut.flush;
            was_branch_mem <= was_branch_ex;
            was_branch_wb <= was_branch_mem;

            if (csv_fd != 0) begin
                $fwrite(csv_fd,
                    "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    cycle_count,
                    dut.mem_read_mem,
                    dut.mem_write_mem,
                    perf_mem_reads,
                    perf_mem_writes,
                    perf_mem_accesses,
                    perf_mem_cycles,
                    perf_cycle_count,
                    perf_instr_count,
                    perf_branch_stalls,
                    perf_load_use_stalls,
                    ipc_x1000
                );
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && dut.halted && !halt_reported) begin
            halt_reported <= 1'b1;

            $display("");
            $display("====================================================================");
            $display("  PROGRAM HALTED - Cycle %0d", cycle_count);
            $display("  Benchmark: %s", benchmark_title());
            $display("====================================================================");
            $display("");

            $display("--- Legacy Memory Counters ---");
            $display("  Memory reads:         %0d", perf_mem_reads);
            $display("  Memory writes:        %0d", perf_mem_writes);
            $display("  Total data accesses:  %0d", perf_mem_accesses);
            $display("  Memory busy cycles:   %0d", perf_mem_cycles);
            $display("");

            $display("--- Pipeline Performance ---");
            $display("  Total cycles:         %0d", perf_cycle_count);
            $display("  Instructions retired: %0d", perf_instr_count);
            $display("  Branch stall cycles:  %0d", perf_branch_stalls);
            $display("  Load-use stalls:      %0d", perf_load_use_stalls);
            $display("");

            $display("--- Derived Metrics ---");
            $display("  IPC x1000:            %0d", ipc_x1000);
            $display("  IPC:                  %0d.%03d", ipc_x1000 / 1000, ipc_x1000 % 1000);
            $display("");

            if (csv_fd != 0) begin
                $fclose(csv_fd);
                csv_fd = 0;
            end

            // Volcar memoria completa a archivo 
            $writememh("mem/mem_dump.mem", dut.dmem.mem); 
            $display("Dump completo → mem/mem_dump.mem");

            #20;
            $finish;
        end
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT at cycle %0d", cycle_count);
        $display("  halted=%b mem_r=%b mem_w=%b", dut.halted, dut.mem_read_mem, dut.mem_write_mem);
        if (csv_fd != 0) begin
            $fclose(csv_fd);
            csv_fd = 0;
        end
        $finish;
    end

endmodule