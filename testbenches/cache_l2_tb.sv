`timescale 1ns/1ps
// cache_l2_tb.sv
// Testbench para cache_l2. Usa un stub de memoria que simula data_memoryv2
// con latencia de 25 ciclos y respuestas de burst, así el TB corre de forma
// independiente sin necesitar la memoria real.
//
// Tests:
//   T1: Cold miss — línea no está en L2, se busca en memoria y se instala
//   T2: Read hit  — misma línea, debe responder en exactamente 8 ciclos
//   T3: Write hit — palabra actualizada, línea marcada dirty
//   T4: Write miss con write-allocate — fetch + actualización de la palabra
//   T5: Eviction dirty — llenar el set para forzar reemplazo de línea dirty
//   T6: Writeback de L1 — L1 manda línea dirty junto con su miss request
//   T7: Pseudo-LRU — la vía más reciente no se evicta ante una nueva línea
//   T8: Contadores de rendimiento — verificar coherencia al final

// Stub de memoria principal. Responde bursts de lectura con datos generados
// (burst_data[i] = addr/4 + i) tras una latencia fija de 25 ciclos.
// Nota: mem_burst_data se conecta con genvar desde el TB.
module mem_stub (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_req,
    input  logic [31:0] mem_addr,
    input  logic        mem_wr_en,
    input  logic        mem_burst_en,
    input  logic [31:0] mem_write_data,
    output logic        mem_ready,
    output logic        mem_valid,
    output logic [31:0] mem_burst_data [0:7]
);
    localparam LATENCY = 25;
    logic [4:0]  counter;
    logic        busy;
    logic [31:0] latched_addr;

    assign mem_ready = !busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 0;
            counter   <= 0;
            mem_valid <= 0;
            for (int i = 0; i < 8; i++) mem_burst_data[i] <= 0;
        end else begin
            mem_valid <= 0;
            if (!busy && mem_req && !mem_wr_en) begin
                busy         <= 1;
                counter      <= LATENCY - 1;
                latched_addr <= mem_addr;
            end else if (busy) begin
                if (counter == 0) begin
                    busy      <= 0;
                    mem_valid <= 1;
                    for (int i = 0; i < 8; i++)
                        mem_burst_data[i] <= (latched_addr >> 2) + i;
                end else begin
                    counter <= counter - 1;
                end
            end
        end
    end
endmodule

module cache_l2_tb;

    logic        clk   = 0;
    logic        rst_n = 0;

    // Interfaz L1 → L2
    logic        l1_req             = 0;
    logic [31:0] l1_addr            = 0;
    logic        l1_wr_en           = 0;
    logic [31:0] l1_write_word      = 0;
    logic        l1_dirty_writeback = 0;
    logic [31:0] l1_dirty_line   [0:7];

    // Interfaz L2 → L1
    logic        l2_ready;
    logic        l2_valid;
    logic [31:0] l2_line [0:7];

    // Interfaz L2 → Memoria
    logic        mem_req_dut;
    logic [31:0] mem_addr_dut;
    logic        mem_wr_en_dut;
    logic        mem_burst_en_dut;
    logic [31:0] mem_write_data_dut;
    logic        mem_ready_stub;
    logic        mem_valid_stub;
    logic [31:0] mem_burst_data_stub [0:7];

    // Contadores de rendimiento
    logic [31:0] l2_read_hits, l2_read_misses;
    logic [31:0] l2_write_hits, l2_write_misses;

    always #5 clk = ~clk;

    // Instancia DUT. Arreglos desempacados se conectan con genvar abajo.
    cache_l2 #(
        .DATA_WIDTH(32), .NUM_SETS(128), .NUM_WAYS(4),
        .LINE_WORDS(8),  .HIT_LATENCY(8), .WB_DEPTH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .l1_req(l1_req), .l1_addr(l1_addr), .l1_wr_en(l1_wr_en),
        .l1_write_word(l1_write_word), .l1_dirty_writeback(l1_dirty_writeback),
        .l1_dirty_line(),
        .l2_ready(l2_ready), .l2_valid(l2_valid), .l2_line(),
        .mem_req(mem_req_dut), .mem_addr(mem_addr_dut),
        .mem_wr_en(mem_wr_en_dut), .mem_burst_en(mem_burst_en_dut),
        .mem_write_data(mem_write_data_dut),
        .mem_ready(mem_ready_stub), .mem_valid(mem_valid_stub),
        .mem_burst_data(),
        .l2_read_hits(l2_read_hits), .l2_read_misses(l2_read_misses),
        .l2_write_hits(l2_write_hits), .l2_write_misses(l2_write_misses)
    );
    for (genvar i = 0; i < 8; i++) begin : gen_dut
        assign dut.l1_dirty_line[i]  = l1_dirty_line[i];
        assign l2_line[i]            = dut.l2_line[i];
        assign dut.mem_burst_data[i] = mem_burst_data_stub[i];
    end

    // Instancia stub de memoria
    mem_stub stub (
        .clk(clk), .rst_n(rst_n),
        .mem_req(mem_req_dut), .mem_addr(mem_addr_dut),
        .mem_wr_en(mem_wr_en_dut), .mem_burst_en(mem_burst_en_dut),
        .mem_write_data(mem_write_data_dut),
        .mem_ready(mem_ready_stub), .mem_valid(mem_valid_stub),
        .mem_burst_data()
    );
    for (genvar i = 0; i < 8; i++) begin : gen_stub
        assign mem_burst_data_stub[i] = stub.mem_burst_data[i];
    end

    // Variables compartidas para los bloques de test
    integer pass_count = 0;
    integer fail_count = 0;
    logic [31:0] line_got [0:7];
    int          cyc;
    int          wb_before;

    task automatic check(input string name, input logic cond);
        if (cond) begin $display("  [PASS] %s", name); pass_count++; end
        else      begin $display("  [FAIL] %s", name); fail_count++; end
    endtask

    // Envía un read a L2 y espera respuesta. Resultado en line_got[], ciclos en cyc.
    task automatic l2_read(input logic [31:0] address);
        cyc = 0;
        while (!l2_ready) @(posedge clk);
        @(posedge clk); #1;
        l1_req = 1; l1_addr = address; l1_wr_en = 0;
        @(posedge clk); #1;
        while (!l2_valid) begin @(posedge clk); cyc++; #1; end
        for (int i = 0; i < 8; i++) line_got[i] = l2_line[i];
        l1_req = 0;
        @(posedge clk); #1;
    endtask

    // Envía un write a L2 y espera confirmación.
    task automatic l2_write(input logic [31:0] address, input logic [31:0] word_data);
        while (!l2_ready) @(posedge clk);
        @(posedge clk); #1;
        l1_req = 1; l1_addr = address; l1_wr_en = 1; l1_write_word = word_data;
        @(posedge clk); #1;
        while (!l2_valid) @(posedge clk);
        l1_req = 0; l1_wr_en = 0;
        @(posedge clk); #1;
    endtask

    initial begin
        $dumpfile("sim/cache_l2_tb.vcd");
        $dumpvars(0, cache_l2_tb);
        for (int i = 0; i < 8; i++) l1_dirty_line[i] = 32'h0;

        $display("=== cache_l2 Testbench ===");

        rst_n = 0; repeat(3) @(posedge clk); rst_n = 1; @(posedge clk); #1;

        check("INIT l2_ready HIGH", l2_ready == 1);
        check("INIT l2_valid LOW",  l2_valid == 0);

        // T1: Cold miss
        $display("--- T1: Cold miss ---");
        l2_read(32'h0000_0000);
        $display("  l2_valid en %0d ciclos", cyc);
        check("T1.1 latencia >= 25 ciclos", cyc >= 25);
        check("T1.2 latencia <= 45 ciclos", cyc <= 45);
        check("T1.3 line_got[0] == 0",      line_got[0] == 32'd0);
        check("T1.4 line_got[7] == 7",      line_got[7] == 32'd7);
        check("T1.5 read_misses == 1",       l2_read_misses == 1);

        // T2: Read hit — misma línea, debe responder en 8 ciclos
        $display("--- T2: Read hit ---");
        l2_read(32'h0000_0000);
        $display("  l2_valid en %0d ciclos", cyc);
        check("T2.1 latencia == 11 ciclos (8 + LOOKUP+DECIDE+RESPOND)", cyc == 11);
        check("T2.2 line_got[0] == 0",     line_got[0] == 32'd0);
        check("T2.3 read_hits == 1",        l2_read_hits == 1);

        // T3: Write hit
        $display("--- T3: Write hit ---");
        l2_write(32'h0000_0008, 32'hCAFE_BABE); // offset palabra 2
        l2_read(32'h0000_0000);
        check("T3.1 write_hits == 1",          l2_write_hits == 1);
        check("T3.2 palabra[2] == 0xCAFEBABE", line_got[2] == 32'hCAFE_BABE);
        check("T3.3 palabra[0] sin cambio",    line_got[0] == 32'd0);

        // T4: Write miss con write-allocate
        // El stub responde con burst_data[i] = 0x100/4 + i = 64 + i
        $display("--- T4: Write miss ---");
        l2_write(32'h0000_0104, 32'hDEAD_BEEF); // offset palabra 1
        check("T4.1 write_misses == 1", l2_write_misses == 1);
        l2_read(32'h0000_0100);
        check("T4.2 hit tras write-miss", cyc == 11);
        check("T4.3 palabra[1] == 0xDEADBEEF", line_got[1] == 32'hDEAD_BEEF);
        check("T4.4 palabra[0] == 64 (del fetch)", line_got[0] == 32'd64);

        // T5: Eviction dirty.
        // Llenar set 0 con tags 1-3, marcar TODAS las vías como dirty con write hits,
        // luego instalar tag4 que fuerza eviction de la LRU (cualquier vía es dirty).
        $display("--- T5: Eviction dirty ---");
        l2_read(32'h0000_1000); check("T5.1 miss tag1/set0", l2_read_misses == 2);
        l2_read(32'h0000_2000); check("T5.2 miss tag2/set0", l2_read_misses == 3);
        l2_read(32'h0000_3000); check("T5.3 miss tag3/set0", l2_read_misses == 4);
        // Marcar todas las vías como dirty para garantizar que la eviction llena WB
        l2_write(32'h0000_0000, 32'hDEAD_0001); // tag0 dirty
        l2_write(32'h0000_1000, 32'hDEAD_0002); // tag1 dirty
        l2_write(32'h0000_2000, 32'hDEAD_0003); // tag2 dirty
        l2_write(32'h0000_3000, 32'hDEAD_0004); // tag3 dirty
        // Esperar 2 ciclos en IDLE para que dirty bits estén estables en S_LOOKUP
        repeat(2) @(posedge clk); #1;
        // Instalar tag4 → evicta la LRU, que ahora sí es dirty
        l2_read(32'h0000_4000); check("T5.4 miss tag4/set0 (fuerza eviction dirty)", l2_read_misses == 5);
        repeat(5) @(posedge clk); #1;
        $display("  write buffer count = %0d", dut.wb_count);
        check("T5.5 wb_tail > 0 (linea dirty fue encolada en WB)", dut.wb_tail > 0);

        // T6: Writeback de L1 junto con el miss request
        $display("--- T6: Writeback de L1 ---");
        for (int i = 0; i < 8; i++) l1_dirty_line[i] = 32'hBEEF_0000 + i;
        wb_before = dut.wb_count;
        while (!l2_ready) @(posedge clk);
        @(posedge clk); #1;
        l1_req = 1; l1_addr = 32'h0000_5000; l1_wr_en = 0; l1_dirty_writeback = 1;
        @(posedge clk); #1;
        l1_dirty_writeback = 0;
        while (!l2_valid) @(posedge clk);
        l1_req = 0; repeat(2) @(posedge clk); #1;
        check("T6.1 wb_tail incrementó (writeback de L1 encolado)", dut.wb_tail > 0);
        check("T6.2 read_misses incrementó", l2_read_misses >= 6);
        for (int i = 0; i < 8; i++) l1_dirty_line[i] = 0;

        // T7: Pseudo-LRU — la vía accedida más recientemente no se evicta
        // Usar set 10 (index=10, base 0x00000050) para no pisar los tests anteriores
        $display("--- T7: Pseudo-LRU ---");
        l2_read(32'h0000_0140); // vía 0 set 10
        l2_read(32'h0001_0140); // vía 1 set 10
        l2_read(32'h0002_0140); // vía 2 set 10
        l2_read(32'h0003_0140); // vía 3 set 10 — set lleno
        l2_read(32'h0000_0140); // acceso a vía 0 → MRU
        check("T7.1 hit en vía 0", cyc == 11);
        l2_read(32'h0004_0140); // 5ª línea → evicta una de las vías 1-3
        l2_read(32'h0000_0140); // vía 0 debe seguir en L2
        check("T7.2 vía 0 (MRU) sobrevivió la eviction", cyc == 11);

        // T8: Contadores de rendimiento
        $display("--- T8: Contadores ---");
        $display("  read_hits=%0d  read_misses=%0d  write_hits=%0d  write_misses=%0d",
                 l2_read_hits, l2_read_misses, l2_write_hits, l2_write_misses);
        check("T8.1 read_hits >= 1",    l2_read_hits    >= 1);
        check("T8.2 read_misses >= 1",  l2_read_misses  >= 1);
        check("T8.3 write_hits >= 1",   l2_write_hits   >= 1);
        check("T8.4 write_misses >= 1", l2_write_misses >= 1);

        $display("");
        $display("=== %0d pasaron, %0d fallaron ===", pass_count, fail_count);
        if (fail_count == 0) $display("TODOS LOS TESTS PASARON");
        else                 $display("Revisar waveform en sim/cache_l2_tb.vcd");
        $finish;
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule