`timescale 1ns/1ps

// Metricas para performance del pipeline, contadores de cache L1, L2 y contadores de memoria principal
// Calcula IPC, tasas de hit/miss y AMAT, ciclos totales, instrucciones retiradas y ciclos de stall por miss L1/L2
// AMAT se calcula como: 1 + MR_L1 * (8 + MR_L2 * 33)

module perf_counters (
    input  logic        clk,
    input  logic        rst_n,

    // Eventos del pipeline
    input  logic        instr_retired,
    input  logic        stall_l1miss,
    input  logic        stall_l2miss,

    // Contadores acumulativos de L1
    input  logic [31:0] l1_read_hits,
    input  logic [31:0] l1_read_misses,
    input  logic [31:0] l1_write_hits,
    input  logic [31:0] l1_write_misses,

    // Contadores acumulativos de L2
    input  logic [31:0] l2_read_hits,
    input  logic [31:0] l2_read_misses,
    input  logic [31:0] l2_write_hits,
    input  logic [31:0] l2_write_misses,

    // Contadores acumulativos de memoria principal
    input  logic [31:0] total_mem_accesses,
    input  logic [31:0] total_mem_cycles,

    // Contadores base
    output logic [31:0] total_cycles,
    output logic [31:0] instructions_completed,
    output logic [31:0] stall_cycles_l1miss,
    output logic [31:0] stall_cycles_l2miss,

    // Contadores de memoria propagados directamente
    output logic [31:0] mem_accesses,
    output logic [31:0] mem_cycles_used,

    // Metricas derivadas en punto fijo x1000
    output logic [31:0] ipc_x1000,
    output logic [31:0] l1_hit_rate_x1000,
    output logic [31:0] l2_hit_rate_x1000,
    output logic [31:0] l1_miss_rate_x1000,
    output logic [31:0] l2_miss_rate_x1000,
    output logic [31:0] amat_x1000
);

    logic [31:0] l1_hits;
    logic [31:0] l1_misses;
    logic [31:0] l1_accesses;

    logic [31:0] l2_hits;
    logic [31:0] l2_misses;
    logic [31:0] l2_accesses;

    logic [63:0] inner_term_x1000;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles            <= 32'd0;
            instructions_completed  <= 32'd0;
            stall_cycles_l1miss     <= 32'd0;
            stall_cycles_l2miss     <= 32'd0;
        end else begin
            total_cycles <= total_cycles + 32'd1;

            if (instr_retired)
                instructions_completed <= instructions_completed + 32'd1;

            if (stall_l1miss)
                stall_cycles_l1miss <= stall_cycles_l1miss + 32'd1;

            if (stall_l2miss)
                stall_cycles_l2miss <= stall_cycles_l2miss + 32'd1;
        end
    end

    always_comb begin
        l1_hits     = l1_read_hits + l1_write_hits;
        l1_misses   = l1_read_misses + l1_write_misses;
        l1_accesses = l1_hits + l1_misses;

        l2_hits     = l2_read_hits + l2_write_hits;
        l2_misses   = l2_read_misses + l2_write_misses;
        l2_accesses = l2_hits + l2_misses;

        mem_accesses   = total_mem_accesses;
        mem_cycles_used = total_mem_cycles;

        if (total_cycles != 0)
            ipc_x1000 = (instructions_completed * 32'd1000) / total_cycles;
        else
            ipc_x1000 = 32'd0;

        if (l1_accesses != 0) begin
            l1_hit_rate_x1000  = (l1_hits   * 32'd1000) / l1_accesses;
            l1_miss_rate_x1000 = (l1_misses * 32'd1000) / l1_accesses;
        end else begin
            l1_hit_rate_x1000  = 32'd0;
            l1_miss_rate_x1000 = 32'd0;
        end

        if (l2_accesses != 0) begin
            l2_hit_rate_x1000  = (l2_hits   * 32'd1000) / l2_accesses;
            l2_miss_rate_x1000 = (l2_misses * 32'd1000) / l2_accesses;
        end else begin
            l2_hit_rate_x1000  = 32'd0;
            l2_miss_rate_x1000 = 32'd0;
        end

        // AMAT (x1000): 1000 + MR_L1 * (8000 + MR_L2 * 33000)
        // donde las tasas de miss se representan en x1000.
        inner_term_x1000 = 64'd8000 + ((l2_miss_rate_x1000 * 64'd33000) / 64'd1000);
        amat_x1000       = 32'd1000 + ((l1_miss_rate_x1000 * inner_term_x1000) / 64'd1000);
    end

endmodule
