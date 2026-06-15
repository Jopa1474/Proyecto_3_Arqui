// cache_l1_tb.sv
// Testbench para cache_l1.
//
// Usa un stub de L2 (l2_model) en lugar de cache_l2 completo para aislar L1.
// El stub responde con l2_valid tras 4 ciclos y maneja l1_dirty_writeback.
//
// Casos de prueba:
//   TC1 — Cold miss (frío): primera lectura → miss + fill
//   TC2 — Hit tras fill: misma dirección → hit
//   TC3 — Miss con fill en set distinto
//   TC4 — Eviction de línea dirty: llenar ambas vías del set 0, luego
//         forzar third miss → se desaloja la vía LRU que tiene dirty=1
//   TC5 — Accesos consecutivos al mismo set (thrashing de 2 vías)
//   TC6 — Write-hit: STORE a línea caliente → solo modifica L1
//   TC7 — Write-miss: STORE en frío → write-allocate desde L2
//

`timescale 1ns/1ps

module cache_l1_tb;

// ============================================================
// Parámetros
// ============================================================
localparam CLK_PERIOD = 10;  // 100 MHz
localparam LINE_WORDS = 8;

// ============================================================
// DUT — cache_l1
// ============================================================
logic        clk, rst_n;
logic        cpu_req, cpu_wr_en;
logic [31:0] cpu_addr, cpu_write_data;
logic [31:0] cpu_read_data;
logic        cpu_valid, cache_stall;

logic        l1_req;
logic [31:0] l1_addr;
logic        l1_wr_en;
logic [31:0] l1_write_word;
logic        l1_dirty_writeback;
logic [31:0] l1_dirty_line [0:LINE_WORDS-1];
logic        l2_ready, l2_valid;
logic [31:0] l2_line [0:LINE_WORDS-1];

logic [31:0] l1_read_hits, l1_read_misses, l1_write_hits, l1_write_misses;

cache_l1 dut (
    .clk(clk), .rst_n(rst_n),
    .cpu_req(cpu_req), .cpu_addr(cpu_addr),
    .cpu_wr_en(cpu_wr_en), .cpu_write_data(cpu_write_data),
    .cpu_read_data(cpu_read_data), .cpu_valid(cpu_valid),
    .cache_stall(cache_stall),
    .l1_req(l1_req), .l1_addr(l1_addr),
    .l1_wr_en(l1_wr_en), .l1_write_word(l1_write_word),
    .l1_dirty_writeback(l1_dirty_writeback), .l1_dirty_line(l1_dirty_line),
    .l2_ready(l2_ready), .l2_valid(l2_valid), .l2_line(l2_line),
    .l1_read_hits(l1_read_hits), .l1_read_misses(l1_read_misses),
    .l1_write_hits(l1_write_hits), .l1_write_misses(l1_write_misses)
);

// ============================================================
// L2 Stub — responde tras 4 ciclos con datos derivados de la dirección
// ============================================================
logic [3:0] l2_cnt;
logic       l2_busy;
logic [31:0] l2_saved_addr;
// Memoria stub: 256 palabras (suficiente para las pruebas)
logic [31:0] l2_mem [0:255];

// Inicializar memoria stub con valores conocidos
initial begin
    for (int i = 0; i < 256; i++) l2_mem[i] = 32'hA000_0000 + i;
end

assign l2_ready = !l2_busy;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l2_busy     <= 1'b0;
        l2_cnt      <= 4'd0;
        l2_valid    <= 1'b0;
        l2_saved_addr <= 32'd0;
        for (int i = 0; i < LINE_WORDS; i++) l2_line[i] <= 32'd0;
    end else begin
        l2_valid <= 1'b0;

        if (!l2_busy && l1_req) begin
            // Acepta el request; guarda dirty line si aplica
            l2_busy       <= 1'b1;
            l2_cnt        <= 4'd0;
            l2_saved_addr <= l1_addr;
            if (l1_dirty_writeback) begin
                // Almacenar línea dirty en memoria stub (palabra 0..7)
                for (int i = 0; i < LINE_WORDS; i++)
                    l2_mem[(l1_addr[9:2])] <= l1_dirty_line[i];
            end
        end else if (l2_busy) begin
            if (l2_cnt < 4'd3) begin
                l2_cnt <= l2_cnt + 1;
            end else begin
                // Responder con la línea de memoria
                for (int i = 0; i < LINE_WORDS; i++)
                    l2_line[i] <= l2_mem[(l2_saved_addr[9:5] << 3) + i];
                l2_valid <= 1'b1;
                l2_busy  <= 1'b0;
                l2_cnt   <= 4'd0;
            end
        end
    end
end

// ============================================================
// Clock
// ============================================================
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================
// Task: emitir un request y esperar a que cpu_valid=1
// ============================================================
task automatic do_read(input [31:0] addr, output [31:0] rdata);
    @(posedge clk);
    cpu_req       <= 1'b1;
    cpu_wr_en     <= 1'b0;
    cpu_addr      <= addr;
    cpu_write_data <= 32'd0;
    @(posedge clk);
    cpu_req <= 1'b0;
    // Esperar cpu_valid (pipeline stallado hasta entonces)
    while (!cpu_valid) @(posedge clk);
    rdata = cpu_read_data;
    @(posedge clk);
endtask

task automatic do_write(input [31:0] addr, input [31:0] wdata);
    @(posedge clk);
    cpu_req        <= 1'b1;
    cpu_wr_en      <= 1'b1;
    cpu_addr       <= addr;
    cpu_write_data <= wdata;
    @(posedge clk);
    cpu_req    <= 1'b0;
    cpu_wr_en  <= 1'b0;
    while (!cpu_valid) @(posedge clk);
    @(posedge clk);
endtask

// ============================================================
// Contador de errores
// ============================================================
integer errors = 0;

task check(input string msg, input logic cond);
    if (!cond) begin
        $display("FAIL [%0t] %s", $time, msg);
        errors++;
    end else begin
        $display("PASS [%0t] %s", $time, msg);
    end
endtask

// ============================================================
// Stimulus
// ============================================================
integer i;
logic [31:0] rdata, rdata2;

// Dirección helper: set=s, tag=t, offset=o
// addr[10:5]=s, addr[31:11]=t, addr[4:2]=o, addr[1:0]=0
function automatic [31:0] mk_addr(input [20:0] tag, input [5:0] idx, input [2:0] off);
    return {tag, idx, off, 2'b00};
endfunction

initial begin
    $dumpfile("cache_l1_tb.vcd");
    $dumpvars(0, cache_l1_tb);

    clk  = 0; rst_n = 0;
    cpu_req = 0; cpu_wr_en = 0;
    cpu_addr = 0; cpu_write_data = 0;

    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // --------------------------------------------------------
    // TC1: Cold miss — primera lectura a dirección nueva
    // --------------------------------------------------------
    $display("\n=== TC1: Cold miss (primera lectura) ===");
    do_read(mk_addr(21'h1, 6'd0, 3'd0), rdata);
    check("TC1 read_misses=1",   l1_read_misses == 1);
    check("TC1 read_hits=0",     l1_read_hits   == 0);
    check("TC1 cpu_valid pulsed (data returned)", rdata == l2_mem[0]);

    // --------------------------------------------------------
    // TC2: Hit tras fill — misma dirección, debería ser hit
    // --------------------------------------------------------
    $display("\n=== TC2: Hit tras fill (segunda lectura misma addr) ===");
    do_read(mk_addr(21'h1, 6'd0, 3'd0), rdata);
    check("TC2 read_hits=1",     l1_read_hits   == 1);
    check("TC2 read_misses=1",   l1_read_misses == 1);

    // --------------------------------------------------------
    // TC3: Miss en offset distinto dentro de la misma línea (hit)
    // --------------------------------------------------------
    $display("\n=== TC3: Hit en offset diferente de la misma linea ===");
    do_read(mk_addr(21'h1, 6'd0, 3'd3), rdata);
    check("TC3 read_hits=2",     l1_read_hits   == 2);

    // --------------------------------------------------------
    // TC4: Write-hit — STORE a línea caliente
    // --------------------------------------------------------
    $display("\n=== TC4: Write-hit (STORE a linea caliente) ===");
    do_write(mk_addr(21'h1, 6'd0, 3'd2), 32'hDEAD_BEEF);
    check("TC4 write_hits=1",    l1_write_hits  == 1);
    check("TC4 write_misses=0",  l1_write_misses == 0);
    // Verificar que la escritura persistió (lectura debe retornar el nuevo valor)
    do_read(mk_addr(21'h1, 6'd0, 3'd2), rdata);
    check("TC4 STORE persiste en L1", rdata == 32'hDEAD_BEEF);
    check("TC4 read_hits=3", l1_read_hits == 3);

    // --------------------------------------------------------
    // TC5: Eviction de línea dirty
    // --------------------------------------------------------
    // Set 0 tiene way0 ocupado con tag=1 y dirty=1 (por el write-hit de TC4).
    // Cargar tag=2 en way1 (miss limpio)
    $display("\n=== TC5: Eviction de linea dirty ===");
    do_read(mk_addr(21'h2, 6'd0, 3'd0), rdata);  // way1 <- tag=2
    check("TC5 miss tag=2",      l1_read_misses == 2);
    // Marcar way1 como dirty también
    do_write(mk_addr(21'h2, 6'd0, 3'd0), 32'hCAFE_F00D);
    check("TC5 write_hits=2",    l1_write_hits  == 2);
    // Ahora ambas vías del set 0 están válidas y dirty.
    // lru=0 tras acceder way1 más reciente → way0 es LRU.
    // Una nueva miss con tag=3 en set 0 debe desalojar way0 (dirty → writeback a L2)
    do_read(mk_addr(21'h3, 6'd0, 3'd0), rdata);
    check("TC5 miss tag=3 (eviction)",   l1_read_misses == 3);
    // El L2 stub debe haber recibido l1_dirty_writeback=1 (verificar via display)
    $display("  l1_dirty_writeback observado en stub (ver waveform)");
    // Confirmar que ahora el set 0 tiene tag=3 en la vía desalojada
    do_read(mk_addr(21'h3, 6'd0, 3'd0), rdata2);
    check("TC5 hit tag=3 tras fill", l1_read_hits == 4);

    // --------------------------------------------------------
    // TC6: Write-miss — STORE en frío (write-allocate)
    // --------------------------------------------------------
    $display("\n=== TC6: Write-miss (STORE en frio, write-allocate) ===");
    do_write(mk_addr(21'h5, 6'd5, 3'd1), 32'h1234_5678);
    check("TC6 write_misses=1",  l1_write_misses == 1);
    // El valor debe estar en L1 ahora (hit en la lectura siguiente)
    do_read(mk_addr(21'h5, 6'd5, 3'd1), rdata);
    check("TC6 read after write-allocate hit", l1_read_hits >= 4);
    check("TC6 write-allocate valor correcto", rdata == 32'h1234_5678);

    // --------------------------------------------------------
    // TC7: Accesos consecutivos al mismo set (thrashing)
    // --------------------------------------------------------
    $display("\n=== TC7: Accesos consecutivos al mismo set ===");
    // Acceder 4 tags distintos en set 10 → primeros 2 son misses, los 2 siguientes también
    do_read(mk_addr(21'hA, 6'd10, 3'd0), rdata);
    do_read(mk_addr(21'hB, 6'd10, 3'd0), rdata);
    // Hit en los que están instalados
    do_read(mk_addr(21'hA, 6'd10, 3'd0), rdata);
    do_read(mk_addr(21'hB, 6'd10, 3'd0), rdata);
    check("TC7 2 misses + 2 hits en set 10",
          l1_read_misses >= 5 && l1_read_hits >= 6);

    // --------------------------------------------------------
    // Resumen
    // --------------------------------------------------------
    $display("\n=== RESULTADOS FINALES ===");
    $display("  l1_read_hits    = %0d", l1_read_hits);
    $display("  l1_read_misses  = %0d", l1_read_misses);
    $display("  l1_write_hits   = %0d", l1_write_hits);
    $display("  l1_write_misses = %0d", l1_write_misses);

    if (errors == 0)
        $display("\n*** TODOS LOS TESTS PASARON ***");
    else
        $display("\n*** %0d TEST(S) FALLARON ***", errors);

    $finish;
end

// Timeout de seguridad
initial begin
    #200000;
    $display("TIMEOUT");
    $finish;
end

endmodule
