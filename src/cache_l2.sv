// =============================================================================
// cache_l2.sv — Caché de Nivel 2 Unificada (Iteración 4)
// =============================================================================
//
// Descripción general:
//   Implementa la caché L2 unificada del procesador TEA-ISA. Actúa como
//   intermediario entre la caché L1-D y la memoria principal (data_memoryv2).
//   Cuando L1 tiene un miss, L2 busca la línea en su propio arreglo. Si la
//   encuentra (L2 hit), la devuelve en 8 ciclos. Si no (L2 miss), la solicita
//   a memoria principal vía burst y la devuelve a L1 una vez que llega.
//
// Parámetros arquitectónicos (según especificación del proyecto):
//   - Tamaño total : 16 KB  (4096 palabras de 32 bits)
//   - Asociatividad: 4-way set associative
//   - Tamaño de línea: 32 bytes (8 palabras de 32 bits)
//   - Número de sets : 128  (16KB / 4 ways / 32 bytes por línea)
//   - Política de escritura: write-back (obligatorio para L2)
//   - Política de reemplazo: Pseudo-LRU basado en árbol de bits (tree-based)
//   - Write buffer: 4 entradas para absorber evictions dirty hacia memoria
//   - Hit time: 8 ciclos de CPU
//
// Organización de la dirección de 32 bits:
//
//   [31      12][11    7][6       2][1  0]
//   |  TAG(20) | IDX(5) | OFFSET(5)| -- |
//
//   - OFFSET [6:2]  : 5 bits → selecciona 1 de 8 palabras dentro de la línea
//                     (bits [1:0] ignorados, acceso word-aligned)
//   - INDEX  [11:7] : 5 bits → selecciona 1 de 128 sets
//   - TAG    [31:12]: 20 bits → identifica la línea en el set
//
// Interfaces:
//   - Hacia L1  : recibe miss requests, devuelve líneas completas (8 palabras)
//   - Hacia MEM : genera burst requests a data_memoryv2 en caso de L2 miss
//
// Política de reemplazo — Pseudo-LRU con árbol de 3 bits por set:
//   Para 4 vías se usa un árbol binario con 3 bits (b2, b1, b0):
//
//           b2
//          /   \
//        b1     b0
//       /  \   /  \
//     vía0 vía1 vía2 vía3
//
//   - b2=0 → la próxima víctima apunta al subárbol izquierdo (vías 0,1)
//   - b2=1 → apunta al subárbol derecho (vías 2,3)
//   - b1 desempata entre vía0 y vía1
//   - b0 desempata entre vía2 y vía3
//   Al hacer un hit o fill en una vía, se actualizan los bits apuntando
//   en dirección contraria (LRU aproximado).
//
// Write buffer:
//   Cola FIFO de 4 entradas. Cuando L2 evicta una línea dirty para hacer
//   lugar a un fill, no espera a que memoria principal acepte la escritura;
//   la encola en el write buffer y continúa. El write buffer drena hacia
//   memoria en background cuando el bus está libre.
//
// FSM principal (state):
//   IDLE         → esperando requests de L1
//   HIT_WAIT     → línea encontrada en L2, contando 8 ciclos antes de responder
//   MEM_REQ      → enviando burst request a data_memoryv2
//   MEM_WAIT     → esperando que data_memoryv2 complete el burst (mem_valid)
//   FILL_L2      → escribiendo línea recibida de MEM en el arreglo L2
//   RESPOND_L1   → activando l2_valid y enviando línea a L1
//   WB_SEND      → drenando write buffer hacia memoria principal
//
// FSM write buffer (wb_state):
//   WB_IDLE      → sin entradas pendientes o bus ocupado por fill
//   WB_WAIT      → esperando mem_ready antes de enviar entrada del write buffer
//   WB_ACTIVE    → escritura en progreso hacia data_memoryv2
//
// Contadores de rendimiento (accesibles por perf_counters.sv):
//   l2_read_hits    : accesos de lectura que encontraron línea en L2
//   l2_read_misses  : accesos de lectura que requirieron ir a memoria
//   l2_write_hits   : accesos de escritura que encontraron línea en L2
//   l2_write_misses : accesos de escritura que requirieron ir a memoria
//
// Dependencias:
//   - data_memoryv2.sv : memoria principal (Iteración 2, ya implementada)
//   - cache_l1d.sv     : caché L1-D (define el lado del requestor)
// =============================================================================

module cache_l2 #(
    // -------------------------------------------------------------------------
    // Parámetros configurables
    // -------------------------------------------------------------------------
    parameter DATA_WIDTH   = 32,   // Ancho de palabra en bits
    parameter NUM_SETS     = 128,  // Número de sets (2^7)
    parameter NUM_WAYS     = 4,    // Asociatividad
    parameter LINE_WORDS   = 8,    // Palabras por línea de caché
    parameter HIT_LATENCY  = 8,    // Ciclos de CPU para un L2 hit
    parameter WB_DEPTH     = 4,    // Entradas del write buffer
    // Bits derivados — no cambiar manualmente
    parameter INDEX_BITS   = 7,    // log2(NUM_SETS) = 7
    parameter OFFSET_BITS  = 3,    // log2(LINE_WORDS) = 3  (selecciona palabra)
    parameter TAG_BITS     = 22    // 32 - INDEX_BITS - OFFSET_BITS - 2 = 20
                                   // (los 2 bits bajos son byte offset, ignorados)
)(
    // -------------------------------------------------------------------------
    // Reloj y reset
    // -------------------------------------------------------------------------
    input  logic                            clk,
    input  logic                            rst_n,       // Reset activo en bajo

    // =========================================================================
    // Interfaz L1 → L2  (L1 notifica un miss y espera respuesta)
    // =========================================================================

    // L1 activa l1_req=1 cuando tiene un miss. Debe mantenerse en 1 hasta
    // que l2_valid=1. Solo un request activo a la vez.
    input  logic                            l1_req,

    // Dirección completa de 32 bits del acceso que causó el miss en L1.
    // Debe ser word-aligned (bits [1:0] = 00).
    input  logic [DATA_WIDTH-1:0]           l1_addr,

    // l1_wr_en=1 indica que el miss fue causado por un STORE (escritura).
    // l1_wr_en=0 indica miss por LOAD (lectura).
    input  logic                            l1_wr_en,

    // Palabra a escribir cuando l1_wr_en=1. Solo la palabra específica
    // dentro de la línea (no toda la línea). L2 hace fetch de la línea,
    // actualiza la palabra indicada por l1_addr[4:2], y responde con
    // la línea completa actualizada.
    input  logic [DATA_WIDTH-1:0]           l1_write_word,

    // L1 activa l1_dirty_writeback=1 junto con l1_req cuando está
    // evictando una línea dirty de su propio arreglo para hacer lugar
    // al fill. L2 debe recibir esta línea y encolarla en su write buffer
    // antes de proceder con el fill de la nueva línea.
    input  logic                            l1_dirty_writeback,

    // Línea dirty que L1 está evictando. Válida solo cuando
    // l1_dirty_writeback=1. Son 8 palabras de 32 bits.
    // Nota Icarus: conectar con genvar en el módulo superior.
    input  logic [DATA_WIDTH-1:0]           l1_dirty_line [0:LINE_WORDS-1],

    // =========================================================================
    // Interfaz L2 a L1  (L2 responde con la línea solicitada)
    // =========================================================================

    // l2_ready=1 indica que L2 está en IDLE y puede aceptar un nuevo request.
    // L1 debe esperar a que l2_ready=1 antes de activar l1_req.
    output logic                            l2_ready,

    // l2_valid=1 por exactamente 1 ciclo cuando la línea está lista para L1.
    // L1 debe capturar l2_line en este ciclo.
    output logic                            l2_valid,

    // Las 8 palabras de la línea de caché lista para que L1 haga el fill.
    // Válidas solo en el ciclo en que l2_valid=1.
    // Nota Icarus: conectar con genvar en el módulo superior.
    output logic [DATA_WIDTH-1:0]           l2_line [0:LINE_WORDS-1],

    // =========================================================================
    // Interfaz L2 a Memoria Principal  (reutiliza data_memoryv2)
    // =========================================================================
    // Estas señales se conectan directamente a los puertos de data_memoryv2.
    // L2 es el único master del bus de memoria; L1 nunca accede directamente.

    output logic                            mem_req,       // Strobe de request
    output logic [DATA_WIDTH-1:0]           mem_addr,      // Dirección byte-aligned
    output logic                            mem_wr_en,     // 1=write, 0=read
    output logic                            mem_burst_en,  // Siempre 1 (líneas completas)
    output logic [DATA_WIDTH-1:0]           mem_write_data,// Palabra para escrituras single
    input  logic                            mem_ready,     // Controlador de mem libre
    input  logic                            mem_valid,     // Transacción completada
    // Datos de burst leídos de memoria (8 palabras). Conectar con genvar.
    input  logic [DATA_WIDTH-1:0]           mem_burst_data [0:LINE_WORDS-1],

    // =========================================================================
    // Contadores de rendimiento  (para perf_counters.sv)
    // =========================================================================
    output logic [31:0]                     l2_read_hits,
    output logic [31:0]                     l2_read_misses,
    output logic [31:0]                     l2_write_hits,
    output logic [31:0]                     l2_write_misses
);

// =============================================================================
// SECCIÓN 1 — Arreglos de almacenamiento L2
// =============================================================================
// Cuatro arreglos paralelos (uno por vía), cada uno con NUM_SETS entradas.
// Cada entrada almacena: valid, dirty, tag, y LINE_WORDS palabras de datos.

logic                           valid [0:NUM_SETS-1][0:NUM_WAYS-1]; // Línea válida
logic                           dirty [0:NUM_SETS-1][0:NUM_WAYS-1]; // Línea modificada (write-back)
logic [TAG_BITS-1:0]            tag   [0:NUM_SETS-1][0:NUM_WAYS-1]; // Tag de identificación
logic [DATA_WIDTH-1:0]          data  [0:NUM_SETS-1][0:NUM_WAYS-1][0:LINE_WORDS-1]; // Datos

// Árbol Pseudo-LRU: 3 bits por set para 4 vías.
// Bit layout: {b2, b1, b0} donde:
//   b2: 0 → víctima en subárbol izquierdo (vías 0-1), 1 → derecho (vías 2-3)
//   b1: 0 → víctima es vía 0, 1 → víctima es vía 1  (cuando b2=0)
//   b0: 0 → víctima es vía 2, 1 → víctima es vía 3  (cuando b2=1)
logic [2:0]                     plru  [0:NUM_SETS-1];

// =============================================================================
// SECCIÓN 2 — Write Buffer (FIFO de 4 entradas)
// =============================================================================
// Almacena líneas dirty evictadas de L2 (o recibidas de L1 via writeback)
// mientras espera que el bus de memoria esté libre para escribirlas.

typedef struct packed {
    logic [DATA_WIDTH-1:0]      addr;                           // Dirección de la línea
    logic [DATA_WIDTH-1:0]      words [0:LINE_WORDS-1];         // Datos de la línea
} wb_entry_t;

wb_entry_t  wb_buf  [0:WB_DEPTH-1]; // Entradas del write buffer
logic [1:0] wb_head;                // Índice de la próxima entrada a drenar
logic [1:0] wb_tail;                // Índice donde entra la siguiente línea dirty
logic [2:0] wb_count;               // Número de entradas ocupadas (0-4)

// Write buffer lleno — L2 debe stallarse si necesita enicolar y wb_count==WB_DEPTH
logic wb_full;
assign wb_full = (wb_count == WB_DEPTH[2:0]);

// Write buffer vacío — no hay nada que drenar
logic wb_empty;
assign wb_empty = (wb_count == 3'd0);

// =============================================================================
// SECCIÓN 3 — Decodificación de la dirección de L1
// =============================================================================

logic [TAG_BITS-1:0]    req_tag;    // TAG  [31:10] de la dirección solicitada
logic [INDEX_BITS-1:0]  req_index;  // INDEX[9:3]   selecciona el set
logic [OFFSET_BITS-1:0] req_offset; // OFFSET[2:0]  selecciona la palabra en línea
                                    // Nota: bit 0 y 1 son byte-offset, ignorados

// Dirección alineada a línea (para acceder a memoria en burst):
// se zerean los bits de offset y byte para obtener la dirección base de la línea.
logic [DATA_WIDTH-1:0]  line_base_addr;

assign req_tag       = l1_addr[31:10];
assign req_index     = l1_addr[9:3];
assign req_offset    = l1_addr[4:2];   // bits [4:2] seleccionan palabra (0-7)
assign line_base_addr = {l1_addr[31:5], 5'b00000}; // alinear a 32 bytes

// =============================================================================
// SECCIÓN 4 — Lógica de hit/miss combinacional
// =============================================================================

logic [NUM_WAYS-1:0] way_hit;    // Bit i=1 si la vía i tiene la línea buscada
logic                l2_hit;     // Alguna vía tiene hit
logic [1:0]          hit_way;    // Número de vía con hit (válido si l2_hit=1)

genvar w;
generate
    for (w = 0; w < NUM_WAYS; w++) begin : gen_hit
        assign way_hit[w] = valid[req_index][w] &&
                            (tag[req_index][w] == req_tag);
    end
endgenerate

// Codificar qué vía tuvo hit (priority encoder, solo una puede ser 1 a la vez)
always_comb begin
    l2_hit   = |way_hit;
    hit_way  = 2'd0;
    if      (way_hit[0]) hit_way = 2'd0;
    else if (way_hit[1]) hit_way = 2'd1;
    else if (way_hit[2]) hit_way = 2'd2;
    else if (way_hit[3]) hit_way = 2'd3;
end

// =============================================================================
// SECCIÓN 5 — Política de reemplazo Pseudo-LRU
// =============================================================================
// Devuelve la vía víctima para el set actual según los bits PLRU.
// Primero se busca una vía inválida (cold miss); si todas son válidas,
// se usa el árbol PLRU para encontrar la LRU aproximada.

logic [1:0] victim_way;   // Vía a reemplazar en caso de miss

always_comb begin
    // Prioridad 1: vía inválida (cold miss, no hay que evicar nada)
    if      (!valid[req_index][0]) victim_way = 2'd0;
    else if (!valid[req_index][1]) victim_way = 2'd1;
    else if (!valid[req_index][2]) victim_way = 2'd2;
    else if (!valid[req_index][3]) victim_way = 2'd3;
    else begin
        // Todas las vías válidas — usar árbol PLRU
        // plru[set] = {b2, b1, b0}
        if (!plru[req_index][2]) begin
            // Subárbol izquierdo (vías 0 y 1)
            victim_way = plru[req_index][1] ? 2'd0 : 2'd1;
        end else begin
            // Subárbol derecho (vías 2 y 3)
            victim_way = plru[req_index][0] ? 2'd2 : 2'd3;
        end
    end
end

// Tarea de actualización del árbol PLRU tras un acceso (hit o fill).
// Recibe el índice del set y la vía accedida, y actualiza los 3 bits
// para que esa vía sea la menos probable de ser reemplazada.
// Se llama desde la FSM al completar un hit o un fill.
task automatic update_plru(
    input logic [INDEX_BITS-1:0] set_idx,
    input logic [1:0]            accessed_way
);
    case (accessed_way)
        2'd0: plru[set_idx] <= {1'b1, 1'b1, plru[set_idx][0]}; // b2=1, b1=1
        2'd1: plru[set_idx] <= {1'b1, 1'b0, plru[set_idx][0]}; // b2=1, b1=0
        2'd2: plru[set_idx] <= {1'b0, plru[set_idx][1], 1'b1}; // b2=0, b0=1
        2'd3: plru[set_idx] <= {1'b0, plru[set_idx][1], 1'b0}; // b2=0, b0=0
    endcase
endtask

// =============================================================================
// SECCIÓN 6 — FSM principal
// =============================================================================

typedef enum logic [2:0] {
    S_IDLE,        // Sin actividad, listo para aceptar request de L1
    S_HIT_WAIT,    // Hit en L2: contando los 8 ciclos de latencia
    S_MEM_REQ,     // Miss en L2: enviando burst request a data_memoryv2
    S_MEM_WAIT,    // Esperando mem_valid de data_memoryv2
    S_FILL_L2,     // Escribiendo línea recibida de MEM en el arreglo L2
    S_RESPOND_L1,  // Pulso l2_valid=1 hacia L1
    S_WB_DRAIN     // Drenando write buffer (después de completar fill principal)
} state_t;

state_t state;

// Contador de ciclos para el hit latency (8 ciclos)
logic [3:0] hit_counter;

// Latch de la vía hit/fill activa (para saber dónde escribir durante FILL_L2)
logic [1:0] active_way;

// Latch de la línea recibida de memoria antes de escribirla en L2
logic [DATA_WIDTH-1:0] fill_buffer [0:LINE_WORDS-1];

// Latch de la dirección y control del request activo
logic [DATA_WIDTH-1:0]  latched_addr;
logic                   latched_wr_en;
logic [DATA_WIDTH-1:0]  latched_write_word;
logic [INDEX_BITS-1:0]  latched_index;
logic [TAG_BITS-1:0]    latched_tag;
logic [OFFSET_BITS-1:0] latched_offset;
logic [DATA_WIDTH-1:0]  latched_line_base;

// =============================================================================
// SECCIÓN 7 — FSM secuencial principal
// =============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // -----------------------------------------------------------------
        // Reset: limpiar todo el estado de L2
        // -----------------------------------------------------------------
        state <= S_IDLE;
        hit_counter  <= '0;
        active_way   <= '0;
        l2_valid     <= 1'b0;
        mem_req      <= 1'b0;
        mem_wr_en    <= 1'b0;
        mem_burst_en <= 1'b1;   // L2 siempre pide bursts completos
        mem_addr     <= '0;
        mem_write_data <= '0;
        latched_addr      <= '0;
        latched_wr_en     <= 1'b0;
        latched_write_word<= '0;
        latched_index     <= '0;
        latched_tag       <= '0;
        latched_offset    <= '0;
        latched_line_base <= '0;
        wb_head  <= '0;
        wb_tail  <= '0;
        wb_count <= '0;

        // Limpiar arreglos de caché
        for (int s = 0; s < NUM_SETS; s++) begin
            plru[s] <= 3'b000;
            for (int ww = 0; ww < NUM_WAYS; ww++) begin
                valid[s][ww] <= 1'b0;
                dirty[s][ww] <= 1'b0;
                tag[s][ww]   <= '0;
            end
        end

        // Limpiar fill buffer
        for (int i = 0; i < LINE_WORDS; i++)
            fill_buffer[i] <= '0;

        // Inicializar contadores de rendimiento
        l2_read_hits    <= '0;
        l2_read_misses  <= '0;
        l2_write_hits   <= '0;
        l2_write_misses <= '0;

    end else begin

        // Bajar l2_valid por defecto (se sube solo 1 ciclo en S_RESPOND_L1)
        l2_valid <= 1'b0;
        // Bajar mem_req por defecto (se sube 1 ciclo en S_MEM_REQ)
        mem_req  <= 1'b0;

        case (state)

            // =================================================================
            // S_IDLE: esperar request de L1
            // =================================================================
            S_IDLE: begin
                if (l1_req) begin
                    // Latchear parámetros del request para usarlos en estados siguientes
                    latched_addr       <= l1_addr;
                    latched_wr_en      <= l1_wr_en;
                    latched_write_word <= l1_write_word;
                    latched_index      <= req_index;
                    latched_tag        <= req_tag;
                    latched_offset     <= req_offset;
                    latched_line_base  <= line_base_addr;

                    // Si L1 viene con una línea dirty a evicar, encolarla en WB
                    if (l1_dirty_writeback && !wb_full) begin
                        wb_buf[wb_tail].addr <= {l1_addr[31:5], 5'b00000};
                        for (int i = 0; i < LINE_WORDS; i++)
                            wb_buf[wb_tail].words[i] <= l1_dirty_line[i];
                        wb_tail  <= wb_tail + 1;
                        wb_count <= wb_count + 1;
                    end

                    // Decidir entre hit y miss
                    if (l2_hit) begin
                        // ── L2 HIT ──────────────────────────────────────────
                        // Actualizar PLRU con la vía que tuvo hit
                        update_plru(req_index, hit_way);
                        active_way  <= hit_way;
                        hit_counter <= HIT_LATENCY[3:0] - 1; // Contar 8-1=7 ciclos más

                        // Si es un write hit, actualizar la palabra en L2
                        if (l1_wr_en) begin
                            data[req_index][hit_way][req_offset] <= l1_write_word;
                            dirty[req_index][hit_way] <= 1'b1; // Marcar dirty
                            l2_write_hits <= l2_write_hits + 1;
                        end else begin
                            l2_read_hits <= l2_read_hits + 1;
                        end

                        state <= S_HIT_WAIT;

                    end else begin
                        // ── L2 MISS ─────────────────────────────────────────
                        if (l1_wr_en)
                            l2_write_misses <= l2_write_misses + 1;
                        else
                            l2_read_misses <= l2_read_misses + 1;

                        // Si la vía víctima tiene dirty data, evicarla al WB
                        if (valid[req_index][victim_way] &&
                            dirty[req_index][victim_way] &&
                            !wb_full) begin
                            // Calcular dirección de la línea dirty evictada
                            wb_buf[wb_tail].addr <=
                                {tag[req_index][victim_way],
                                 req_index, {OFFSET_BITS{1'b0}}, 2'b00};
                            for (int i = 0; i < LINE_WORDS; i++)
                                wb_buf[wb_tail].words[i] <=
                                    data[req_index][victim_way][i];
                            wb_tail  <= wb_tail + 1;
                            wb_count <= wb_count + 1;
                        end

                        active_way <= victim_way;
                        state <= S_MEM_REQ;
                    end
                end
                // Si no hay request de L1 pero hay entradas en WB, drenar
                else if (!wb_empty && mem_ready) begin
                    state <= S_WB_DRAIN;
                end
            end

            // =================================================================
            // S_HIT_WAIT: contar los 8 ciclos de latencia del hit
            // =================================================================
            S_HIT_WAIT: begin
                if (hit_counter > 0) begin
                    hit_counter <= hit_counter - 1;
                end else begin
                    // Latencia cumplida — preparar la línea de respuesta para L1
                    for (int i = 0; i < LINE_WORDS; i++)
                        l2_line[i] <= data[latched_index][active_way][i];
                    state <= S_RESPOND_L1;
                end
            end

            // =================================================================
            // S_MEM_REQ: emitir burst request a data_memoryv2
            // =================================================================
            S_MEM_REQ: begin
                if (mem_ready) begin
                    mem_req      <= 1'b1;           // Pulso de 1 ciclo
                    mem_addr     <= latched_line_base;
                    mem_wr_en    <= 1'b0;           // Siempre lectura (fetch de línea)
                    mem_burst_en <= 1'b1;
                    state        <= S_MEM_WAIT;
                end
                // Si mem no está listo, esperar (el stall del pipeline
                // ya fue generado por cache_stall desde L1)
            end

            // =================================================================
            // S_MEM_WAIT: esperar que data_memoryv2 complete el burst
            // =================================================================
            S_MEM_WAIT: begin
                mem_req <= 1'b0; // Bajar strobe tras el primer ciclo
                if (mem_valid) begin
                    // Capturar los datos del burst en fill_buffer
                    for (int i = 0; i < LINE_WORDS; i++)
                        fill_buffer[i] <= mem_burst_data[i];
                    state <= S_FILL_L2;
                end
            end

            // =================================================================
            // S_FILL_L2: escribir línea recibida de MEM en el arreglo L2
            // =================================================================
            S_FILL_L2: begin
                // Instalar línea en la vía víctima
                valid[latched_index][active_way] <= 1'b1;
                dirty[latched_index][active_way] <= 1'b0; // Recién llegada, no dirty
                tag  [latched_index][active_way] <= latched_tag;

                for (int i = 0; i < LINE_WORDS; i++)
                    data[latched_index][active_way][i] <= fill_buffer[i];

                // Si era un write miss, actualizar la palabra específica y marcar dirty
                if (latched_wr_en) begin
                    data[latched_index][active_way][latched_offset] <= latched_write_word;
                    dirty[latched_index][active_way] <= 1'b1;
                end

                // Actualizar PLRU para la vía recién instalada
                update_plru(latched_index, active_way);

                // Preparar línea de respuesta para L1
                for (int i = 0; i < LINE_WORDS; i++)
                    l2_line[i] <= fill_buffer[i];
                // Si fue write miss, la línea que ve L1 tiene la palabra actualizada
                if (latched_wr_en)
                    l2_line[latched_offset] <= latched_write_word;

                state <= S_RESPOND_L1;
            end

            // =================================================================
            // S_RESPOND_L1: pulso l2_valid=1 por 1 ciclo
            // =================================================================
            S_RESPOND_L1: begin
                l2_valid <= 1'b1;   // L1 captura l2_line en este ciclo
                // Si hay entradas en WB y memoria está libre, drenar
                if (!wb_empty && mem_ready)
                    state <= S_WB_DRAIN;
                else
                    state <= S_IDLE;
            end

            // =================================================================
            // S_WB_DRAIN: drenar una entrada del write buffer a memoria
            // Solo cuando mem_ready=1 y no hay request de L1 pendiente
            // =================================================================
            S_WB_DRAIN: begin
                if (mem_ready && !l1_req) begin
                    // Enviar la entrada head del write buffer a memoria
                    mem_req        <= 1'b1;
                    mem_addr       <= wb_buf[wb_head].addr;
                    mem_wr_en      <= 1'b1;
                    mem_burst_en   <= 1'b0; // Escrituras single-word por ahora
                    mem_write_data <= wb_buf[wb_head].words[0]; // Simplificado
                    // Actualizar punteros del WB
                    wb_head  <= wb_head + 1;
                    wb_count <= wb_count - 1;
                    state    <= S_IDLE;
                end else if (l1_req) begin
                    // Priorizar request de L1 sobre drenado de WB
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;

        endcase
    end
end

// =============================================================================
// SECCIÓN 8 — Salidas combinacionales
// =============================================================================

// l2_ready: L2 acepta requests cuando está en IDLE
assign l2_ready = (state == S_IDLE);

endmodule