// =============================================================================
// data_memoryv2.sv — Realistic Main Memory Controller (Iteration 2)
// =============================================================================
// Models an external DRAM-like memory with:
//   - 50 MHz memory clock (CPU_CLK ÷ 2) via internal divider
//   - 25 CPU-cycle latency for single reads/writes
//   - 8-word burst transfers (for future cache line fills)
//   - Handshake protocol: mem_req / mem_ready / mem_valid
//   - Integrated performance counters
//
// The FSM runs entirely in the CPU clock domain. The memory array is accessed
// synchronously. The latency counter models the speed difference between
// the CPU (100 MHz) and external memory (50 MHz).
// =============================================================================

module data_memoryv2 #(
    parameter DATA_WIDTH     = 32,
    parameter MEM_WORDS      = 16384,    // 16384 × 4 = 64 KB
    parameter SINGLE_LATENCY = 25,       // CPU cycles for single access
    parameter BURST_LEN      = 8         // Words per burst (cache line)
)(
    // CPU-domain clock and reset
    input  logic                  clk,       // 100 MHz CPU clock
    input  logic                  rst_n,

    // CPU-side interface (from pipeline MEM stage or cache controller)
    input  logic [DATA_WIDTH-1:0] addr,        // Byte address
    input  logic [DATA_WIDTH-1:0] write_data,  // Data for single writes
    input  logic                  mem_req,      // Request strobe (1 = new request)
    input  logic                  mem_wr_en,    // 1 = write, 0 = read
    input  logic                  burst_en,     // 1 = burst (8 words), 0 = single

    // Read outputs
    output logic [DATA_WIDTH-1:0] read_data,                    // Single-word read
    output logic [DATA_WIDTH-1:0] burst_data [0:BURST_LEN-1],   // Burst read data

    // Handshake
    output logic                  mem_ready,   // 1 = controller idle, can accept
    output logic                  mem_valid,   // 1 = read data valid this cycle

    // Alignment fault
    output logic                  align_fault, // 1 if addr[1:0] != 00

    // Performance counters
    output logic [31:0]           total_mem_accesses,  // Total requests served
    output logic [31:0]           total_mem_cycles,     // CPU cycles spent busy
    output logic [31:0]           burst_count           // Number of burst transfers
);

    // =========================================================================
    // Memory Array — 64 KB (16384 words × 32 bits)
    // =========================================================================
    logic [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    initial begin
        for (int i = 0; i < MEM_WORDS; i++)
            mem[i] = 32'h0;
        $readmemh("mem/mem_init.mem", mem);
    end

    // =========================================================================
    // Burst data buffer — internal register array
    // (Icarus Verilog has limited support for unpacked array ports)
    // =========================================================================


    // =========================================================================
    // Memory Clock Generation — 50 MHz (CPU ÷ 2)
    // =========================================================================
    logic mem_clk;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mem_clk <= 1'b0;
        else
            mem_clk <= ~mem_clk;
    end

    // Detect mem_clk rising edge in CPU domain
    logic mem_clk_prev;
    logic mem_clk_rise;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mem_clk_prev <= 1'b0;
        else
            mem_clk_prev <= mem_clk;
    end
    assign mem_clk_rise = mem_clk && !mem_clk_prev;

    // =========================================================================
    // Address Decoding
    // =========================================================================
    logic [13:0] word_index;
    assign word_index = addr[15:2];

    // Alignment fault: addr[1:0] must be 00 for any access
    assign align_fault = mem_req & (addr[1:0] != 2'b00);

    // =========================================================================
    // Accepted request detection (no combinational loop — uses state directly)
    // =========================================================================
    logic req_accepted;
    assign req_accepted = mem_req && !align_fault && (state == S_IDLE);

    // =========================================================================
    // FSM — Main Memory Controller
    // =========================================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_LATENCY,
        S_BURST_XFER,
        S_DONE
    } state_t;

    state_t state;

    // Latched request parameters
    logic [13:0] latched_word_index;
    logic [DATA_WIDTH-1:0] latched_write_data;
    logic        latched_wr_en;
    logic        latched_burst;

    // Counters
    logic [5:0]  latency_counter;
    logic [3:0]  burst_word_counter;

    // =========================================================================
    // Main FSM — single always_ff block for clarity
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            latched_word_index <= '0;
            latched_write_data <= '0;
            latched_wr_en      <= 1'b0;
            latched_burst      <= 1'b0;
            latency_counter    <= '0;
            burst_word_counter <= '0;
            read_data          <= '0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (req_accepted) begin
                        // Latch request parameters
                        latched_word_index <= word_index;
                        latched_write_data <= write_data;
                        latched_wr_en      <= mem_wr_en;
                        latched_burst      <= burst_en;
                        // Start counting: we need SINGLE_LATENCY CPU cycles
                        // Counter will decrement from SINGLE_LATENCY-1 down to 0
                        latency_counter    <= SINGLE_LATENCY[5:0] - 1;
                        burst_word_counter <= '0;
                        state              <= S_WAIT_LATENCY;
                    end
                end

                // ---------------------------------------------------------
                S_WAIT_LATENCY: begin
                    if (latency_counter > 0) begin
                        latency_counter <= latency_counter - 1;
                    end else begin
                        // Latency expired — perform the operation
                        if (latched_wr_en) begin
                            // WRITE: commit to memory and go to DONE
                            mem[latched_word_index] <= latched_write_data;
                            state <= S_DONE;
                        end else if (latched_burst) begin
                            // BURST READ: start transferring words
                            burst_word_counter <= '0;
                            state <= S_BURST_XFER;
                        end else begin
                            // SINGLE READ: capture data and go to DONE
                            read_data <= mem[latched_word_index];
                            state <= S_DONE;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_BURST_XFER: begin
                    // Transfer one word per mem_clk rising edge
                    if (mem_clk_rise) begin
                        if (burst_word_counter == BURST_LEN[3:0] - 1) begin
                            state <= S_DONE;
                        end else begin
                            burst_word_counter <= burst_word_counter + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Burst Data Capture — separate always_ff for Icarus Verilog compatibility
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BURST_LEN; i++)
                burst_data[i] <= '0;
        end else if (state == S_BURST_XFER && mem_clk_rise) begin
            burst_data[burst_word_counter] <= mem[latched_word_index + burst_word_counter];
        end
    end

    // =========================================================================
    // Output Signals
    // =========================================================================

    // mem_ready: controller can accept a new request
    // HIGH only when idle AND no request being accepted this cycle
    assign mem_ready = (state == S_IDLE);

    // mem_valid: transaction completed this cycle (read data valid or write done)
    assign mem_valid = (state == S_DONE);

    // =========================================================================
    // Performance Counters
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_mem_accesses <= '0;
            total_mem_cycles   <= '0;
            burst_count        <= '0;
        end else begin
            // Count each accepted request
            if (req_accepted)
                total_mem_accesses <= total_mem_accesses + 1;

            // Count every CPU cycle spent busy (not idle, or transitioning out)
            if (state != S_IDLE || req_accepted)
                total_mem_cycles <= total_mem_cycles + 1;

            // Count completed burst transfers
            if (state == S_DONE && latched_burst)
                burst_count <= burst_count + 1;
        end
    end

endmodule
