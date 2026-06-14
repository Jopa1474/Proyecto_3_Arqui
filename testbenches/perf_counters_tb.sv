`timescale 1ns/1ps

module perf_counters_tb;

    logic clk;
    logic rst_n;

    logic        instr_retired;
    logic        stall_l1miss;
    logic        stall_l2miss;
    logic        stall_control;

    logic [31:0] l1_read_hits;
    logic [31:0] l1_read_misses;
    logic [31:0] l1_write_hits;
    logic [31:0] l1_write_misses;

    logic [31:0] l2_read_hits;
    logic [31:0] l2_read_misses;
    logic [31:0] l2_write_hits;
    logic [31:0] l2_write_misses;

    logic [31:0] total_mem_accesses;
    logic [31:0] total_mem_cycles;

    logic [31:0] total_cycles;
    logic [31:0] instructions_completed;
    logic [31:0] stall_cycles_l1miss;
    logic [31:0] stall_cycles_l2miss;
    logic [31:0] stall_cycles_control;

    logic [31:0] l1_read_accesses;
    logic [31:0] l1_write_accesses;
    logic [31:0] l1_total_accesses;
    logic [31:0] l2_read_accesses;
    logic [31:0] l2_write_accesses;
    logic [31:0] l2_total_accesses;

    logic [31:0] mem_accesses;
    logic [31:0] mem_cycles_used;

    logic [31:0] ipc_x1000;
    logic [31:0] l1_hit_rate_x1000;
    logic [31:0] l2_hit_rate_x1000;
    logic [31:0] l1_miss_rate_x1000;
    logic [31:0] l2_miss_rate_x1000;
    logic [31:0] amat_x1000;

    perf_counters dut (
        .clk(clk),
        .rst_n(rst_n),
        .instr_retired(instr_retired),
        .stall_l1miss(stall_l1miss),
        .stall_l2miss(stall_l2miss),
        .stall_control(stall_control),
        .l1_read_hits(l1_read_hits),
        .l1_read_misses(l1_read_misses),
        .l1_write_hits(l1_write_hits),
        .l1_write_misses(l1_write_misses),
        .l2_read_hits(l2_read_hits),
        .l2_read_misses(l2_read_misses),
        .l2_write_hits(l2_write_hits),
        .l2_write_misses(l2_write_misses),
        .total_mem_accesses(total_mem_accesses),
        .total_mem_cycles(total_mem_cycles),
        .total_cycles(total_cycles),
        .instructions_completed(instructions_completed),
        .stall_cycles_l1miss(stall_cycles_l1miss),
        .stall_cycles_l2miss(stall_cycles_l2miss),
        .stall_cycles_control(stall_cycles_control),
        .l1_read_accesses(l1_read_accesses),
        .l1_write_accesses(l1_write_accesses),
        .l1_total_accesses(l1_total_accesses),
        .l2_read_accesses(l2_read_accesses),
        .l2_write_accesses(l2_write_accesses),
        .l2_total_accesses(l2_total_accesses),
        .mem_accesses(mem_accesses),
        .mem_cycles_used(mem_cycles_used),
        .ipc_x1000(ipc_x1000),
        .l1_hit_rate_x1000(l1_hit_rate_x1000),
        .l2_hit_rate_x1000(l2_hit_rate_x1000),
        .l1_miss_rate_x1000(l1_miss_rate_x1000),
        .l2_miss_rate_x1000(l2_miss_rate_x1000),
        .amat_x1000(amat_x1000)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic tick(
        input logic retire_i,
        input logic l1_stall_i,
        input logic l2_stall_i,
        input logic ctrl_stall_i
    );
        begin
            instr_retired = retire_i;
            stall_l1miss  = l1_stall_i;
            stall_l2miss  = l2_stall_i;
            stall_control = ctrl_stall_i;
            @(posedge clk);
        end
    endtask

    task automatic check_eq(
        input string name,
        input [31:0] got,
        input [31:0] exp
    );
        begin
            if (got !== exp) begin
                $display("FAIL %s: got=%0d expected=%0d", name, got, exp);
                $fatal(1);
            end else begin
                $display("PASS %s: %0d", name, got);
            end
        end
    endtask

    initial begin
        // Valores por defecto
        instr_retired = 1'b0;
        stall_l1miss  = 1'b0;
        stall_l2miss  = 1'b0;
        stall_control = 1'b0;

        l1_read_hits    = 32'd0;
        l1_read_misses  = 32'd0;
        l1_write_hits   = 32'd0;
        l1_write_misses = 32'd0;

        l2_read_hits    = 32'd0;
        l2_read_misses  = 32'd0;
        l2_write_hits   = 32'd0;
        l2_write_misses = 32'd0;

        total_mem_accesses = 32'd0;
        total_mem_cycles   = 32'd0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // -----------------------------------------------------------------
        // Caso A: incremento de contadores e IPC
        // 10 ciclos, 6 instrucciones retiradas, 3 ciclos de stall por miss L1,
        // 2 ciclos de stall por miss L2 y 2 ciclos de stall de control.
        // -----------------------------------------------------------------
        tick(1'b1, 1'b0, 1'b0, 1'b0); // 1
        tick(1'b0, 1'b1, 1'b0, 1'b0); // 2
        tick(1'b1, 1'b0, 1'b0, 1'b0); // 3
        tick(1'b1, 1'b1, 1'b0, 1'b1); // 4
        tick(1'b0, 1'b0, 1'b1, 1'b0); // 5
        tick(1'b1, 1'b0, 1'b0, 1'b0); // 6
        tick(1'b0, 1'b1, 1'b0, 1'b0); // 7
        tick(1'b1, 1'b0, 1'b1, 1'b1); // 8
        tick(1'b0, 1'b0, 1'b0, 1'b0); // 9
        tick(1'b1, 1'b0, 1'b0, 1'b0); // 10

        check_eq("total_cycles", total_cycles, 32'd10);
        check_eq("instructions_completed", instructions_completed, 32'd6);
        check_eq("stall_cycles_l1miss", stall_cycles_l1miss, 32'd3);
        check_eq("stall_cycles_l2miss", stall_cycles_l2miss, 32'd2);
        check_eq("stall_cycles_control", stall_cycles_control, 32'd2);
        check_eq("ipc_x1000", ipc_x1000, 32'd600);

        // -----------------------------------------------------------------
        // Caso B: MR_L1 = 0  -> AMAT = 1.000
        // -----------------------------------------------------------------
        l1_read_hits    = 32'd100;
        l1_write_hits   = 32'd0;
        l1_read_misses  = 32'd0;
        l1_write_misses = 32'd0;

        l2_read_hits    = 32'd0;
        l2_write_hits   = 32'd0;
        l2_read_misses  = 32'd0;
        l2_write_misses = 32'd0;

        total_mem_accesses = 32'd50;
        total_mem_cycles   = 32'd1200;

        #1;
        check_eq("l1_hit_rate_x1000_caseB", l1_hit_rate_x1000, 32'd1000);
        check_eq("l1_miss_rate_x1000_caseB", l1_miss_rate_x1000, 32'd0);
        check_eq("l1_read_accesses_caseB", l1_read_accesses, 32'd100);
        check_eq("l1_write_accesses_caseB", l1_write_accesses, 32'd0);
        check_eq("l1_total_accesses_caseB", l1_total_accesses, 32'd100);
        check_eq("amat_x1000_caseB", amat_x1000, 32'd1000);
        check_eq("mem_accesses_fwd", mem_accesses, 32'd50);
        check_eq("mem_cycles_used_fwd", mem_cycles_used, 32'd1200);

        // -----------------------------------------------------------------
        // Caso C: MR_L1 = 0.500, MR_L2 = 0.250
        // AMAT esperado = 1 + 0.5 * (8 + 0.25*33) = 9.125 -> 9125 (x1000)
        // -----------------------------------------------------------------
        l1_read_hits    = 32'd50;
        l1_write_hits   = 32'd0;
        l1_read_misses  = 32'd50;
        l1_write_misses = 32'd0;

        l2_read_hits    = 32'd75;
        l2_write_hits   = 32'd0;
        l2_read_misses  = 32'd25;
        l2_write_misses = 32'd0;

        #1;
        check_eq("l1_miss_rate_x1000_caseC", l1_miss_rate_x1000, 32'd500);
        check_eq("l2_miss_rate_x1000_caseC", l2_miss_rate_x1000, 32'd250);
        check_eq("l2_hit_rate_x1000_caseC", l2_hit_rate_x1000, 32'd750);
        check_eq("l2_read_accesses_caseC", l2_read_accesses, 32'd100);
        check_eq("l2_write_accesses_caseC", l2_write_accesses, 32'd0);
        check_eq("l2_total_accesses_caseC", l2_total_accesses, 32'd100);
        check_eq("amat_x1000_caseC", amat_x1000, 32'd9125);

        $display("Todas las pruebas de perf_counters pasaron.");
        $finish;
    end

endmodule
