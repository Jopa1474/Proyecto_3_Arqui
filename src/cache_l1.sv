// cache_l1.sv
// Caché L1 para el procesador TEA-ISA.
//
// Especificación:
//   Total:  4 KB = 64 sets × 2 vías × 32 B/línea
//   Línea:  32 bytes = 8 palabras de 32 bits
//   Mapeo:  2-way set associative
//
// Organización de la dirección de 32 bits:
//   [31:11] tag (21 bits) | [10:5] index (6 bits) | [4:2] offset (3 bits) | [1:0] byte (ignorar)
//   Verificación: 64×2×32 = 4 096 bytes = 4 KB ✓
//
// Política de escritura: WRITE-BACK
//   Los stores solo modifican la línea en L1 (dirty=1). La línea se envía a L2
//   únicamente al ser desalojada. Justificación: elimina el tráfico L1→L2 en
//   cada store; la mayoría de stores accede a líneas ya calientes en L1.
//
// Política de reemplazo: LRU con 1 bit por set
//   Con 2 vías basta 1 bit exacto: lru[s]=0 ⟹ vía 0 es LRU (se desaloja).
//   lru[s]=1 ⟹ vía 1 es LRU. Al acceder la vía k → lru[s] = ~k.
//
// Máquina de estados:
//   HIT:  IDLE → LOOKUP → DECIDE → RESPOND          (2 ciclos de stall)
//   MISS: IDLE → LOOKUP → DECIDE → MISS → FILL → RESPOND
//     DECIDE detecta víctima dirty → en MISS se envía l1_dirty_writeback=1
//     junto con l1_req=1 cuando l2_ready. L2 gestiona el writeback en su
//     write-buffer y sirve la línea nueva; L1 la instala en S_FILL.
//
// Icarus Verilog — misma solución que cache_l2:
//   S_LOOKUP captura valid/tag/dirty/lru/data en registros escalares cur_*.
//   Writes a arreglos 3D usan case expandido sobre cada dimensión variable.
//
// Señales expuestas para integración:
//   cache_stall  → Persona 4 (pipeline freeze)
//   l1_read_hits, l1_read_misses, l1_write_hits, l1_write_misses → Persona 5
//
// Autores: [Nombres del grupo]
// CE-4301 Arquitectura de Computadores I, I Semestre 2026

`timescale 1ns/1ps

module cache_l1 #(
    parameter DATA_WIDTH  = 32,
    parameter NUM_SETS    = 64,
    parameter NUM_WAYS    = 2,
    parameter LINE_WORDS  = 8,
    parameter INDEX_BITS  = 6,
    parameter OFFSET_BITS = 3,
    parameter TAG_BITS    = 21
)(
    input  logic clk,
    input  logic rst_n,

    // ---- Interfaz con la etapa MEM del pipeline ----
    input  logic        cpu_req,          // 1 = LOAD/STORE presente en MEM
    input  logic [31:0] cpu_addr,         // Dirección byte
    input  logic        cpu_wr_en,        // 1 = STORE, 0 = LOAD
    input  logic [31:0] cpu_write_data,   // Dato para STORE
    output logic [31:0] cpu_read_data,    // Dato LOAD (válido cuando cpu_valid=1)
    output logic        cpu_valid,        // Pulso 1 ciclo: operación completada
    output logic        cache_stall,      // 1 mientras el request está en proceso

    // ---- Interfaz hacia cache_l2 ----
    // Conectar l1_dirty_line con genvar en el módulo superior si se usan
    // arreglos desempacados en puertos.
    output logic        l1_req,
    output logic [31:0] l1_addr,
    output logic        l1_wr_en,
    output logic [31:0] l1_write_word,
    output logic        l1_dirty_writeback,
    output logic [31:0] l1_dirty_line [0:LINE_WORDS-1],
    input  logic        l2_ready,
    input  logic        l2_valid,
    input  logic [31:0] l2_line [0:LINE_WORDS-1],

    // ---- Contadores de rendimiento ----
    output logic [31:0] l1_read_hits,
    output logic [31:0] l1_read_misses,
    output logic [31:0] l1_write_hits,
    output logic [31:0] l1_write_misses
);

// ============================================================
// Arreglos de almacenamiento
// ============================================================
logic              valid [0:NUM_SETS-1][0:NUM_WAYS-1];
logic              dirty [0:NUM_SETS-1][0:NUM_WAYS-1];
logic [TAG_BITS-1:0] tag [0:NUM_SETS-1][0:NUM_WAYS-1];
logic [31:0]        data [0:NUM_SETS-1][0:NUM_WAYS-1][0:LINE_WORDS-1];
logic              lru  [0:NUM_SETS-1];   // 0=way0 es LRU, 1=way1 es LRU

// ============================================================
// Decodificación de dirección entrante
// ============================================================
logic [TAG_BITS-1:0]    req_tag;
logic [INDEX_BITS-1:0]  req_index;
logic [OFFSET_BITS-1:0] req_offset;
logic [31:0]            req_line_base;

assign req_tag       = cpu_addr[31:11];
assign req_index     = cpu_addr[10:5];
assign req_offset    = cpu_addr[4:2];
assign req_line_base = {cpu_addr[31:5], 5'b00000};

// ============================================================
// Registros del request latched en S_IDLE
// ============================================================
logic [TAG_BITS-1:0]    latched_tag;
logic [INDEX_BITS-1:0]  latched_index;
logic [OFFSET_BITS-1:0] latched_offset;
logic [31:0]            latched_addr;
logic                   latched_wr_en;
logic [31:0]            latched_write_data;
logic [31:0]            latched_line_base;

// ============================================================
// Registros cur_* — cargados en S_LOOKUP (Icarus workaround)
// Icarus no soporta indexar arreglos multidim con señal variable
// en ningún bloque always; estos scalars resuelven el problema.
// ============================================================
logic              cur_valid0, cur_valid1;
logic              cur_dirty0, cur_dirty1;
logic [TAG_BITS-1:0] cur_tag0, cur_tag1;
logic              cur_lru;
logic [31:0]       cur_data0 [0:LINE_WORDS-1];
logic [31:0]       cur_data1 [0:LINE_WORDS-1];

// ============================================================
// Hit/miss y victim selection (combinacional sobre cur_*)
// Válido sólo en S_DECIDE y estados posteriores del mismo request.
// ============================================================
logic way0_hit, way1_hit, l1_hit;
logic hit_way;
logic victim_way;
logic victim_dirty;

always_comb begin
    way0_hit     = cur_valid0 && (cur_tag0 == latched_tag);
    way1_hit     = cur_valid1 && (cur_tag1 == latched_tag);
    l1_hit       = way0_hit || way1_hit;
    hit_way      = way1_hit ? 1'b1 : 1'b0;

    // Victim: prefer invalid way, then LRU
    if      (!cur_valid0) victim_way = 1'b0;
    else if (!cur_valid1) victim_way = 1'b1;
    else                  victim_way = cur_lru;

    victim_dirty = victim_way ? cur_dirty1 : cur_dirty0;
end

// Palabra de hit: mux combinacional sobre cur_data (arrays 1D — Icarus OK)
logic [31:0] hit_word;
assign hit_word = hit_way ? cur_data1[latched_offset] : cur_data0[latched_offset];

// ============================================================
// FSM
// ============================================================
localparam S_IDLE    = 3'd0;
localparam S_LOOKUP  = 3'd1;  // Captura cur_* del set activo
localparam S_DECIDE  = 3'd2;  // Decide hit/miss con cur_* estables
localparam S_MISS    = 3'd3;  // Espera l2_ready; envía dirty writeback si aplica
localparam S_FILL    = 3'd4;  // Espera l2_valid; instala línea
localparam S_RESPOND = 3'd5;  // Pulsa cpu_valid 1 ciclo, pipeline libre

logic [2:0] state;
logic [31:0] response_data;       // Palabra a retornar en S_RESPOND
logic        saved_victim_dirty;  // Latched de victim_dirty en S_DECIDE

// cache_stall: 1 mientras L1 procesa el request (pipeline congelado)
assign cache_stall = (state == S_LOOKUP) || (state == S_DECIDE) ||
                     (state == S_MISS)   || (state == S_FILL);

integer fi;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= S_IDLE;
        cpu_valid           <= 1'b0;
        cpu_read_data       <= 32'd0;
        l1_req              <= 1'b0;
        l1_wr_en            <= 1'b0;
        l1_addr             <= 32'd0;
        l1_write_word       <= 32'd0;
        l1_dirty_writeback  <= 1'b0;
        response_data       <= 32'd0;
        saved_victim_dirty  <= 1'b0;
        latched_addr        <= 32'd0;
        latched_wr_en       <= 1'b0;
        latched_write_data  <= 32'd0;
        latched_index       <= '0;
        latched_tag         <= '0;
        latched_offset      <= '0;
        latched_line_base   <= 32'd0;
        l1_read_hits        <= 32'd0;
        l1_read_misses      <= 32'd0;
        l1_write_hits       <= 32'd0;
        l1_write_misses     <= 32'd0;
        cur_valid0 <= 1'b0; cur_valid1 <= 1'b0;
        cur_dirty0 <= 1'b0; cur_dirty1 <= 1'b0;
        cur_tag0   <= '0;   cur_tag1   <= '0;
        cur_lru    <= 1'b0;
        for (fi = 0; fi < LINE_WORDS; fi++) begin
            cur_data0[fi]     <= 32'd0;
            cur_data1[fi]     <= 32'd0;
            l1_dirty_line[fi] <= 32'd0;
        end
        for (fi = 0; fi < NUM_SETS; fi++) begin
            lru[fi]      <= 1'b0;
            valid[fi][0] <= 1'b0; valid[fi][1] <= 1'b0;
            dirty[fi][0] <= 1'b0; dirty[fi][1] <= 1'b0;
            tag[fi][0]   <= '0;   tag[fi][1]   <= '0;
        end
    end else begin
        // ---- defaults ----
        cpu_valid          <= 1'b0;
        l1_req             <= 1'b0;
        l1_dirty_writeback <= 1'b0;

        case (state)

            // ----------------------------------------------------------
            S_IDLE: begin
                if (cpu_req) begin
                    latched_addr       <= cpu_addr;
                    latched_wr_en      <= cpu_wr_en;
                    latched_write_data <= cpu_write_data;
                    latched_index      <= req_index;
                    latched_tag        <= req_tag;
                    latched_offset     <= req_offset;
                    latched_line_base  <= req_line_base;
                    state              <= S_LOOKUP;
                end
            end

            // ----------------------------------------------------------
            // Captura valid/tag/dirty/lru y las 8 palabras de cada vía
            // del set latched_index en registros escalares.
            // Case expandido a 64 entradas para evitar indexar arreglos
            // multidimensionales con variable (limitación Icarus).
            S_LOOKUP: begin
                case (latched_index)
                    6'd0:  begin cur_valid0<=valid[0][0];  cur_valid1<=valid[0][1];  cur_dirty0<=dirty[0][0];  cur_dirty1<=dirty[0][1];  cur_tag0<=tag[0][0];  cur_tag1<=tag[0][1];  cur_lru<=lru[0];  cur_data0[0]<=data[0][0][0];  cur_data0[1]<=data[0][0][1];  cur_data0[2]<=data[0][0][2];  cur_data0[3]<=data[0][0][3];  cur_data0[4]<=data[0][0][4];  cur_data0[5]<=data[0][0][5];  cur_data0[6]<=data[0][0][6];  cur_data0[7]<=data[0][0][7];  cur_data1[0]<=data[0][1][0];  cur_data1[1]<=data[0][1][1];  cur_data1[2]<=data[0][1][2];  cur_data1[3]<=data[0][1][3];  cur_data1[4]<=data[0][1][4];  cur_data1[5]<=data[0][1][5];  cur_data1[6]<=data[0][1][6];  cur_data1[7]<=data[0][1][7];  end
                    6'd1:  begin cur_valid0<=valid[1][0];  cur_valid1<=valid[1][1];  cur_dirty0<=dirty[1][0];  cur_dirty1<=dirty[1][1];  cur_tag0<=tag[1][0];  cur_tag1<=tag[1][1];  cur_lru<=lru[1];  cur_data0[0]<=data[1][0][0];  cur_data0[1]<=data[1][0][1];  cur_data0[2]<=data[1][0][2];  cur_data0[3]<=data[1][0][3];  cur_data0[4]<=data[1][0][4];  cur_data0[5]<=data[1][0][5];  cur_data0[6]<=data[1][0][6];  cur_data0[7]<=data[1][0][7];  cur_data1[0]<=data[1][1][0];  cur_data1[1]<=data[1][1][1];  cur_data1[2]<=data[1][1][2];  cur_data1[3]<=data[1][1][3];  cur_data1[4]<=data[1][1][4];  cur_data1[5]<=data[1][1][5];  cur_data1[6]<=data[1][1][6];  cur_data1[7]<=data[1][1][7];  end
                    6'd2:  begin cur_valid0<=valid[2][0];  cur_valid1<=valid[2][1];  cur_dirty0<=dirty[2][0];  cur_dirty1<=dirty[2][1];  cur_tag0<=tag[2][0];  cur_tag1<=tag[2][1];  cur_lru<=lru[2];  cur_data0[0]<=data[2][0][0];  cur_data0[1]<=data[2][0][1];  cur_data0[2]<=data[2][0][2];  cur_data0[3]<=data[2][0][3];  cur_data0[4]<=data[2][0][4];  cur_data0[5]<=data[2][0][5];  cur_data0[6]<=data[2][0][6];  cur_data0[7]<=data[2][0][7];  cur_data1[0]<=data[2][1][0];  cur_data1[1]<=data[2][1][1];  cur_data1[2]<=data[2][1][2];  cur_data1[3]<=data[2][1][3];  cur_data1[4]<=data[2][1][4];  cur_data1[5]<=data[2][1][5];  cur_data1[6]<=data[2][1][6];  cur_data1[7]<=data[2][1][7];  end
                    6'd3:  begin cur_valid0<=valid[3][0];  cur_valid1<=valid[3][1];  cur_dirty0<=dirty[3][0];  cur_dirty1<=dirty[3][1];  cur_tag0<=tag[3][0];  cur_tag1<=tag[3][1];  cur_lru<=lru[3];  cur_data0[0]<=data[3][0][0];  cur_data0[1]<=data[3][0][1];  cur_data0[2]<=data[3][0][2];  cur_data0[3]<=data[3][0][3];  cur_data0[4]<=data[3][0][4];  cur_data0[5]<=data[3][0][5];  cur_data0[6]<=data[3][0][6];  cur_data0[7]<=data[3][0][7];  cur_data1[0]<=data[3][1][0];  cur_data1[1]<=data[3][1][1];  cur_data1[2]<=data[3][1][2];  cur_data1[3]<=data[3][1][3];  cur_data1[4]<=data[3][1][4];  cur_data1[5]<=data[3][1][5];  cur_data1[6]<=data[3][1][6];  cur_data1[7]<=data[3][1][7];  end
                    6'd4:  begin cur_valid0<=valid[4][0];  cur_valid1<=valid[4][1];  cur_dirty0<=dirty[4][0];  cur_dirty1<=dirty[4][1];  cur_tag0<=tag[4][0];  cur_tag1<=tag[4][1];  cur_lru<=lru[4];  cur_data0[0]<=data[4][0][0];  cur_data0[1]<=data[4][0][1];  cur_data0[2]<=data[4][0][2];  cur_data0[3]<=data[4][0][3];  cur_data0[4]<=data[4][0][4];  cur_data0[5]<=data[4][0][5];  cur_data0[6]<=data[4][0][6];  cur_data0[7]<=data[4][0][7];  cur_data1[0]<=data[4][1][0];  cur_data1[1]<=data[4][1][1];  cur_data1[2]<=data[4][1][2];  cur_data1[3]<=data[4][1][3];  cur_data1[4]<=data[4][1][4];  cur_data1[5]<=data[4][1][5];  cur_data1[6]<=data[4][1][6];  cur_data1[7]<=data[4][1][7];  end
                    6'd5:  begin cur_valid0<=valid[5][0];  cur_valid1<=valid[5][1];  cur_dirty0<=dirty[5][0];  cur_dirty1<=dirty[5][1];  cur_tag0<=tag[5][0];  cur_tag1<=tag[5][1];  cur_lru<=lru[5];  cur_data0[0]<=data[5][0][0];  cur_data0[1]<=data[5][0][1];  cur_data0[2]<=data[5][0][2];  cur_data0[3]<=data[5][0][3];  cur_data0[4]<=data[5][0][4];  cur_data0[5]<=data[5][0][5];  cur_data0[6]<=data[5][0][6];  cur_data0[7]<=data[5][0][7];  cur_data1[0]<=data[5][1][0];  cur_data1[1]<=data[5][1][1];  cur_data1[2]<=data[5][1][2];  cur_data1[3]<=data[5][1][3];  cur_data1[4]<=data[5][1][4];  cur_data1[5]<=data[5][1][5];  cur_data1[6]<=data[5][1][6];  cur_data1[7]<=data[5][1][7];  end
                    6'd6:  begin cur_valid0<=valid[6][0];  cur_valid1<=valid[6][1];  cur_dirty0<=dirty[6][0];  cur_dirty1<=dirty[6][1];  cur_tag0<=tag[6][0];  cur_tag1<=tag[6][1];  cur_lru<=lru[6];  cur_data0[0]<=data[6][0][0];  cur_data0[1]<=data[6][0][1];  cur_data0[2]<=data[6][0][2];  cur_data0[3]<=data[6][0][3];  cur_data0[4]<=data[6][0][4];  cur_data0[5]<=data[6][0][5];  cur_data0[6]<=data[6][0][6];  cur_data0[7]<=data[6][0][7];  cur_data1[0]<=data[6][1][0];  cur_data1[1]<=data[6][1][1];  cur_data1[2]<=data[6][1][2];  cur_data1[3]<=data[6][1][3];  cur_data1[4]<=data[6][1][4];  cur_data1[5]<=data[6][1][5];  cur_data1[6]<=data[6][1][6];  cur_data1[7]<=data[6][1][7];  end
                    6'd7:  begin cur_valid0<=valid[7][0];  cur_valid1<=valid[7][1];  cur_dirty0<=dirty[7][0];  cur_dirty1<=dirty[7][1];  cur_tag0<=tag[7][0];  cur_tag1<=tag[7][1];  cur_lru<=lru[7];  cur_data0[0]<=data[7][0][0];  cur_data0[1]<=data[7][0][1];  cur_data0[2]<=data[7][0][2];  cur_data0[3]<=data[7][0][3];  cur_data0[4]<=data[7][0][4];  cur_data0[5]<=data[7][0][5];  cur_data0[6]<=data[7][0][6];  cur_data0[7]<=data[7][0][7];  cur_data1[0]<=data[7][1][0];  cur_data1[1]<=data[7][1][1];  cur_data1[2]<=data[7][1][2];  cur_data1[3]<=data[7][1][3];  cur_data1[4]<=data[7][1][4];  cur_data1[5]<=data[7][1][5];  cur_data1[6]<=data[7][1][6];  cur_data1[7]<=data[7][1][7];  end
                    6'd8:  begin cur_valid0<=valid[8][0];  cur_valid1<=valid[8][1];  cur_dirty0<=dirty[8][0];  cur_dirty1<=dirty[8][1];  cur_tag0<=tag[8][0];  cur_tag1<=tag[8][1];  cur_lru<=lru[8];  cur_data0[0]<=data[8][0][0];  cur_data0[1]<=data[8][0][1];  cur_data0[2]<=data[8][0][2];  cur_data0[3]<=data[8][0][3];  cur_data0[4]<=data[8][0][4];  cur_data0[5]<=data[8][0][5];  cur_data0[6]<=data[8][0][6];  cur_data0[7]<=data[8][0][7];  cur_data1[0]<=data[8][1][0];  cur_data1[1]<=data[8][1][1];  cur_data1[2]<=data[8][1][2];  cur_data1[3]<=data[8][1][3];  cur_data1[4]<=data[8][1][4];  cur_data1[5]<=data[8][1][5];  cur_data1[6]<=data[8][1][6];  cur_data1[7]<=data[8][1][7];  end
                    6'd9:  begin cur_valid0<=valid[9][0];  cur_valid1<=valid[9][1];  cur_dirty0<=dirty[9][0];  cur_dirty1<=dirty[9][1];  cur_tag0<=tag[9][0];  cur_tag1<=tag[9][1];  cur_lru<=lru[9];  cur_data0[0]<=data[9][0][0];  cur_data0[1]<=data[9][0][1];  cur_data0[2]<=data[9][0][2];  cur_data0[3]<=data[9][0][3];  cur_data0[4]<=data[9][0][4];  cur_data0[5]<=data[9][0][5];  cur_data0[6]<=data[9][0][6];  cur_data0[7]<=data[9][0][7];  cur_data1[0]<=data[9][1][0];  cur_data1[1]<=data[9][1][1];  cur_data1[2]<=data[9][1][2];  cur_data1[3]<=data[9][1][3];  cur_data1[4]<=data[9][1][4];  cur_data1[5]<=data[9][1][5];  cur_data1[6]<=data[9][1][6];  cur_data1[7]<=data[9][1][7];  end
                    6'd10: begin cur_valid0<=valid[10][0]; cur_valid1<=valid[10][1]; cur_dirty0<=dirty[10][0]; cur_dirty1<=dirty[10][1]; cur_tag0<=tag[10][0]; cur_tag1<=tag[10][1]; cur_lru<=lru[10]; cur_data0[0]<=data[10][0][0]; cur_data0[1]<=data[10][0][1]; cur_data0[2]<=data[10][0][2]; cur_data0[3]<=data[10][0][3]; cur_data0[4]<=data[10][0][4]; cur_data0[5]<=data[10][0][5]; cur_data0[6]<=data[10][0][6]; cur_data0[7]<=data[10][0][7]; cur_data1[0]<=data[10][1][0]; cur_data1[1]<=data[10][1][1]; cur_data1[2]<=data[10][1][2]; cur_data1[3]<=data[10][1][3]; cur_data1[4]<=data[10][1][4]; cur_data1[5]<=data[10][1][5]; cur_data1[6]<=data[10][1][6]; cur_data1[7]<=data[10][1][7]; end
                    6'd11: begin cur_valid0<=valid[11][0]; cur_valid1<=valid[11][1]; cur_dirty0<=dirty[11][0]; cur_dirty1<=dirty[11][1]; cur_tag0<=tag[11][0]; cur_tag1<=tag[11][1]; cur_lru<=lru[11]; cur_data0[0]<=data[11][0][0]; cur_data0[1]<=data[11][0][1]; cur_data0[2]<=data[11][0][2]; cur_data0[3]<=data[11][0][3]; cur_data0[4]<=data[11][0][4]; cur_data0[5]<=data[11][0][5]; cur_data0[6]<=data[11][0][6]; cur_data0[7]<=data[11][0][7]; cur_data1[0]<=data[11][1][0]; cur_data1[1]<=data[11][1][1]; cur_data1[2]<=data[11][1][2]; cur_data1[3]<=data[11][1][3]; cur_data1[4]<=data[11][1][4]; cur_data1[5]<=data[11][1][5]; cur_data1[6]<=data[11][1][6]; cur_data1[7]<=data[11][1][7]; end
                    6'd12: begin cur_valid0<=valid[12][0]; cur_valid1<=valid[12][1]; cur_dirty0<=dirty[12][0]; cur_dirty1<=dirty[12][1]; cur_tag0<=tag[12][0]; cur_tag1<=tag[12][1]; cur_lru<=lru[12]; cur_data0[0]<=data[12][0][0]; cur_data0[1]<=data[12][0][1]; cur_data0[2]<=data[12][0][2]; cur_data0[3]<=data[12][0][3]; cur_data0[4]<=data[12][0][4]; cur_data0[5]<=data[12][0][5]; cur_data0[6]<=data[12][0][6]; cur_data0[7]<=data[12][0][7]; cur_data1[0]<=data[12][1][0]; cur_data1[1]<=data[12][1][1]; cur_data1[2]<=data[12][1][2]; cur_data1[3]<=data[12][1][3]; cur_data1[4]<=data[12][1][4]; cur_data1[5]<=data[12][1][5]; cur_data1[6]<=data[12][1][6]; cur_data1[7]<=data[12][1][7]; end
                    6'd13: begin cur_valid0<=valid[13][0]; cur_valid1<=valid[13][1]; cur_dirty0<=dirty[13][0]; cur_dirty1<=dirty[13][1]; cur_tag0<=tag[13][0]; cur_tag1<=tag[13][1]; cur_lru<=lru[13]; cur_data0[0]<=data[13][0][0]; cur_data0[1]<=data[13][0][1]; cur_data0[2]<=data[13][0][2]; cur_data0[3]<=data[13][0][3]; cur_data0[4]<=data[13][0][4]; cur_data0[5]<=data[13][0][5]; cur_data0[6]<=data[13][0][6]; cur_data0[7]<=data[13][0][7]; cur_data1[0]<=data[13][1][0]; cur_data1[1]<=data[13][1][1]; cur_data1[2]<=data[13][1][2]; cur_data1[3]<=data[13][1][3]; cur_data1[4]<=data[13][1][4]; cur_data1[5]<=data[13][1][5]; cur_data1[6]<=data[13][1][6]; cur_data1[7]<=data[13][1][7]; end
                    6'd14: begin cur_valid0<=valid[14][0]; cur_valid1<=valid[14][1]; cur_dirty0<=dirty[14][0]; cur_dirty1<=dirty[14][1]; cur_tag0<=tag[14][0]; cur_tag1<=tag[14][1]; cur_lru<=lru[14]; cur_data0[0]<=data[14][0][0]; cur_data0[1]<=data[14][0][1]; cur_data0[2]<=data[14][0][2]; cur_data0[3]<=data[14][0][3]; cur_data0[4]<=data[14][0][4]; cur_data0[5]<=data[14][0][5]; cur_data0[6]<=data[14][0][6]; cur_data0[7]<=data[14][0][7]; cur_data1[0]<=data[14][1][0]; cur_data1[1]<=data[14][1][1]; cur_data1[2]<=data[14][1][2]; cur_data1[3]<=data[14][1][3]; cur_data1[4]<=data[14][1][4]; cur_data1[5]<=data[14][1][5]; cur_data1[6]<=data[14][1][6]; cur_data1[7]<=data[14][1][7]; end
                    6'd15: begin cur_valid0<=valid[15][0]; cur_valid1<=valid[15][1]; cur_dirty0<=dirty[15][0]; cur_dirty1<=dirty[15][1]; cur_tag0<=tag[15][0]; cur_tag1<=tag[15][1]; cur_lru<=lru[15]; cur_data0[0]<=data[15][0][0]; cur_data0[1]<=data[15][0][1]; cur_data0[2]<=data[15][0][2]; cur_data0[3]<=data[15][0][3]; cur_data0[4]<=data[15][0][4]; cur_data0[5]<=data[15][0][5]; cur_data0[6]<=data[15][0][6]; cur_data0[7]<=data[15][0][7]; cur_data1[0]<=data[15][1][0]; cur_data1[1]<=data[15][1][1]; cur_data1[2]<=data[15][1][2]; cur_data1[3]<=data[15][1][3]; cur_data1[4]<=data[15][1][4]; cur_data1[5]<=data[15][1][5]; cur_data1[6]<=data[15][1][6]; cur_data1[7]<=data[15][1][7]; end
                    6'd16: begin cur_valid0<=valid[16][0]; cur_valid1<=valid[16][1]; cur_dirty0<=dirty[16][0]; cur_dirty1<=dirty[16][1]; cur_tag0<=tag[16][0]; cur_tag1<=tag[16][1]; cur_lru<=lru[16]; cur_data0[0]<=data[16][0][0]; cur_data0[1]<=data[16][0][1]; cur_data0[2]<=data[16][0][2]; cur_data0[3]<=data[16][0][3]; cur_data0[4]<=data[16][0][4]; cur_data0[5]<=data[16][0][5]; cur_data0[6]<=data[16][0][6]; cur_data0[7]<=data[16][0][7]; cur_data1[0]<=data[16][1][0]; cur_data1[1]<=data[16][1][1]; cur_data1[2]<=data[16][1][2]; cur_data1[3]<=data[16][1][3]; cur_data1[4]<=data[16][1][4]; cur_data1[5]<=data[16][1][5]; cur_data1[6]<=data[16][1][6]; cur_data1[7]<=data[16][1][7]; end
                    6'd17: begin cur_valid0<=valid[17][0]; cur_valid1<=valid[17][1]; cur_dirty0<=dirty[17][0]; cur_dirty1<=dirty[17][1]; cur_tag0<=tag[17][0]; cur_tag1<=tag[17][1]; cur_lru<=lru[17]; cur_data0[0]<=data[17][0][0]; cur_data0[1]<=data[17][0][1]; cur_data0[2]<=data[17][0][2]; cur_data0[3]<=data[17][0][3]; cur_data0[4]<=data[17][0][4]; cur_data0[5]<=data[17][0][5]; cur_data0[6]<=data[17][0][6]; cur_data0[7]<=data[17][0][7]; cur_data1[0]<=data[17][1][0]; cur_data1[1]<=data[17][1][1]; cur_data1[2]<=data[17][1][2]; cur_data1[3]<=data[17][1][3]; cur_data1[4]<=data[17][1][4]; cur_data1[5]<=data[17][1][5]; cur_data1[6]<=data[17][1][6]; cur_data1[7]<=data[17][1][7]; end
                    6'd18: begin cur_valid0<=valid[18][0]; cur_valid1<=valid[18][1]; cur_dirty0<=dirty[18][0]; cur_dirty1<=dirty[18][1]; cur_tag0<=tag[18][0]; cur_tag1<=tag[18][1]; cur_lru<=lru[18]; cur_data0[0]<=data[18][0][0]; cur_data0[1]<=data[18][0][1]; cur_data0[2]<=data[18][0][2]; cur_data0[3]<=data[18][0][3]; cur_data0[4]<=data[18][0][4]; cur_data0[5]<=data[18][0][5]; cur_data0[6]<=data[18][0][6]; cur_data0[7]<=data[18][0][7]; cur_data1[0]<=data[18][1][0]; cur_data1[1]<=data[18][1][1]; cur_data1[2]<=data[18][1][2]; cur_data1[3]<=data[18][1][3]; cur_data1[4]<=data[18][1][4]; cur_data1[5]<=data[18][1][5]; cur_data1[6]<=data[18][1][6]; cur_data1[7]<=data[18][1][7]; end
                    6'd19: begin cur_valid0<=valid[19][0]; cur_valid1<=valid[19][1]; cur_dirty0<=dirty[19][0]; cur_dirty1<=dirty[19][1]; cur_tag0<=tag[19][0]; cur_tag1<=tag[19][1]; cur_lru<=lru[19]; cur_data0[0]<=data[19][0][0]; cur_data0[1]<=data[19][0][1]; cur_data0[2]<=data[19][0][2]; cur_data0[3]<=data[19][0][3]; cur_data0[4]<=data[19][0][4]; cur_data0[5]<=data[19][0][5]; cur_data0[6]<=data[19][0][6]; cur_data0[7]<=data[19][0][7]; cur_data1[0]<=data[19][1][0]; cur_data1[1]<=data[19][1][1]; cur_data1[2]<=data[19][1][2]; cur_data1[3]<=data[19][1][3]; cur_data1[4]<=data[19][1][4]; cur_data1[5]<=data[19][1][5]; cur_data1[6]<=data[19][1][6]; cur_data1[7]<=data[19][1][7]; end
                    6'd20: begin cur_valid0<=valid[20][0]; cur_valid1<=valid[20][1]; cur_dirty0<=dirty[20][0]; cur_dirty1<=dirty[20][1]; cur_tag0<=tag[20][0]; cur_tag1<=tag[20][1]; cur_lru<=lru[20]; cur_data0[0]<=data[20][0][0]; cur_data0[1]<=data[20][0][1]; cur_data0[2]<=data[20][0][2]; cur_data0[3]<=data[20][0][3]; cur_data0[4]<=data[20][0][4]; cur_data0[5]<=data[20][0][5]; cur_data0[6]<=data[20][0][6]; cur_data0[7]<=data[20][0][7]; cur_data1[0]<=data[20][1][0]; cur_data1[1]<=data[20][1][1]; cur_data1[2]<=data[20][1][2]; cur_data1[3]<=data[20][1][3]; cur_data1[4]<=data[20][1][4]; cur_data1[5]<=data[20][1][5]; cur_data1[6]<=data[20][1][6]; cur_data1[7]<=data[20][1][7]; end
                    6'd21: begin cur_valid0<=valid[21][0]; cur_valid1<=valid[21][1]; cur_dirty0<=dirty[21][0]; cur_dirty1<=dirty[21][1]; cur_tag0<=tag[21][0]; cur_tag1<=tag[21][1]; cur_lru<=lru[21]; cur_data0[0]<=data[21][0][0]; cur_data0[1]<=data[21][0][1]; cur_data0[2]<=data[21][0][2]; cur_data0[3]<=data[21][0][3]; cur_data0[4]<=data[21][0][4]; cur_data0[5]<=data[21][0][5]; cur_data0[6]<=data[21][0][6]; cur_data0[7]<=data[21][0][7]; cur_data1[0]<=data[21][1][0]; cur_data1[1]<=data[21][1][1]; cur_data1[2]<=data[21][1][2]; cur_data1[3]<=data[21][1][3]; cur_data1[4]<=data[21][1][4]; cur_data1[5]<=data[21][1][5]; cur_data1[6]<=data[21][1][6]; cur_data1[7]<=data[21][1][7]; end
                    6'd22: begin cur_valid0<=valid[22][0]; cur_valid1<=valid[22][1]; cur_dirty0<=dirty[22][0]; cur_dirty1<=dirty[22][1]; cur_tag0<=tag[22][0]; cur_tag1<=tag[22][1]; cur_lru<=lru[22]; cur_data0[0]<=data[22][0][0]; cur_data0[1]<=data[22][0][1]; cur_data0[2]<=data[22][0][2]; cur_data0[3]<=data[22][0][3]; cur_data0[4]<=data[22][0][4]; cur_data0[5]<=data[22][0][5]; cur_data0[6]<=data[22][0][6]; cur_data0[7]<=data[22][0][7]; cur_data1[0]<=data[22][1][0]; cur_data1[1]<=data[22][1][1]; cur_data1[2]<=data[22][1][2]; cur_data1[3]<=data[22][1][3]; cur_data1[4]<=data[22][1][4]; cur_data1[5]<=data[22][1][5]; cur_data1[6]<=data[22][1][6]; cur_data1[7]<=data[22][1][7]; end
                    6'd23: begin cur_valid0<=valid[23][0]; cur_valid1<=valid[23][1]; cur_dirty0<=dirty[23][0]; cur_dirty1<=dirty[23][1]; cur_tag0<=tag[23][0]; cur_tag1<=tag[23][1]; cur_lru<=lru[23]; cur_data0[0]<=data[23][0][0]; cur_data0[1]<=data[23][0][1]; cur_data0[2]<=data[23][0][2]; cur_data0[3]<=data[23][0][3]; cur_data0[4]<=data[23][0][4]; cur_data0[5]<=data[23][0][5]; cur_data0[6]<=data[23][0][6]; cur_data0[7]<=data[23][0][7]; cur_data1[0]<=data[23][1][0]; cur_data1[1]<=data[23][1][1]; cur_data1[2]<=data[23][1][2]; cur_data1[3]<=data[23][1][3]; cur_data1[4]<=data[23][1][4]; cur_data1[5]<=data[23][1][5]; cur_data1[6]<=data[23][1][6]; cur_data1[7]<=data[23][1][7]; end
                    6'd24: begin cur_valid0<=valid[24][0]; cur_valid1<=valid[24][1]; cur_dirty0<=dirty[24][0]; cur_dirty1<=dirty[24][1]; cur_tag0<=tag[24][0]; cur_tag1<=tag[24][1]; cur_lru<=lru[24]; cur_data0[0]<=data[24][0][0]; cur_data0[1]<=data[24][0][1]; cur_data0[2]<=data[24][0][2]; cur_data0[3]<=data[24][0][3]; cur_data0[4]<=data[24][0][4]; cur_data0[5]<=data[24][0][5]; cur_data0[6]<=data[24][0][6]; cur_data0[7]<=data[24][0][7]; cur_data1[0]<=data[24][1][0]; cur_data1[1]<=data[24][1][1]; cur_data1[2]<=data[24][1][2]; cur_data1[3]<=data[24][1][3]; cur_data1[4]<=data[24][1][4]; cur_data1[5]<=data[24][1][5]; cur_data1[6]<=data[24][1][6]; cur_data1[7]<=data[24][1][7]; end
                    6'd25: begin cur_valid0<=valid[25][0]; cur_valid1<=valid[25][1]; cur_dirty0<=dirty[25][0]; cur_dirty1<=dirty[25][1]; cur_tag0<=tag[25][0]; cur_tag1<=tag[25][1]; cur_lru<=lru[25]; cur_data0[0]<=data[25][0][0]; cur_data0[1]<=data[25][0][1]; cur_data0[2]<=data[25][0][2]; cur_data0[3]<=data[25][0][3]; cur_data0[4]<=data[25][0][4]; cur_data0[5]<=data[25][0][5]; cur_data0[6]<=data[25][0][6]; cur_data0[7]<=data[25][0][7]; cur_data1[0]<=data[25][1][0]; cur_data1[1]<=data[25][1][1]; cur_data1[2]<=data[25][1][2]; cur_data1[3]<=data[25][1][3]; cur_data1[4]<=data[25][1][4]; cur_data1[5]<=data[25][1][5]; cur_data1[6]<=data[25][1][6]; cur_data1[7]<=data[25][1][7]; end
                    6'd26: begin cur_valid0<=valid[26][0]; cur_valid1<=valid[26][1]; cur_dirty0<=dirty[26][0]; cur_dirty1<=dirty[26][1]; cur_tag0<=tag[26][0]; cur_tag1<=tag[26][1]; cur_lru<=lru[26]; cur_data0[0]<=data[26][0][0]; cur_data0[1]<=data[26][0][1]; cur_data0[2]<=data[26][0][2]; cur_data0[3]<=data[26][0][3]; cur_data0[4]<=data[26][0][4]; cur_data0[5]<=data[26][0][5]; cur_data0[6]<=data[26][0][6]; cur_data0[7]<=data[26][0][7]; cur_data1[0]<=data[26][1][0]; cur_data1[1]<=data[26][1][1]; cur_data1[2]<=data[26][1][2]; cur_data1[3]<=data[26][1][3]; cur_data1[4]<=data[26][1][4]; cur_data1[5]<=data[26][1][5]; cur_data1[6]<=data[26][1][6]; cur_data1[7]<=data[26][1][7]; end
                    6'd27: begin cur_valid0<=valid[27][0]; cur_valid1<=valid[27][1]; cur_dirty0<=dirty[27][0]; cur_dirty1<=dirty[27][1]; cur_tag0<=tag[27][0]; cur_tag1<=tag[27][1]; cur_lru<=lru[27]; cur_data0[0]<=data[27][0][0]; cur_data0[1]<=data[27][0][1]; cur_data0[2]<=data[27][0][2]; cur_data0[3]<=data[27][0][3]; cur_data0[4]<=data[27][0][4]; cur_data0[5]<=data[27][0][5]; cur_data0[6]<=data[27][0][6]; cur_data0[7]<=data[27][0][7]; cur_data1[0]<=data[27][1][0]; cur_data1[1]<=data[27][1][1]; cur_data1[2]<=data[27][1][2]; cur_data1[3]<=data[27][1][3]; cur_data1[4]<=data[27][1][4]; cur_data1[5]<=data[27][1][5]; cur_data1[6]<=data[27][1][6]; cur_data1[7]<=data[27][1][7]; end
                    6'd28: begin cur_valid0<=valid[28][0]; cur_valid1<=valid[28][1]; cur_dirty0<=dirty[28][0]; cur_dirty1<=dirty[28][1]; cur_tag0<=tag[28][0]; cur_tag1<=tag[28][1]; cur_lru<=lru[28]; cur_data0[0]<=data[28][0][0]; cur_data0[1]<=data[28][0][1]; cur_data0[2]<=data[28][0][2]; cur_data0[3]<=data[28][0][3]; cur_data0[4]<=data[28][0][4]; cur_data0[5]<=data[28][0][5]; cur_data0[6]<=data[28][0][6]; cur_data0[7]<=data[28][0][7]; cur_data1[0]<=data[28][1][0]; cur_data1[1]<=data[28][1][1]; cur_data1[2]<=data[28][1][2]; cur_data1[3]<=data[28][1][3]; cur_data1[4]<=data[28][1][4]; cur_data1[5]<=data[28][1][5]; cur_data1[6]<=data[28][1][6]; cur_data1[7]<=data[28][1][7]; end
                    6'd29: begin cur_valid0<=valid[29][0]; cur_valid1<=valid[29][1]; cur_dirty0<=dirty[29][0]; cur_dirty1<=dirty[29][1]; cur_tag0<=tag[29][0]; cur_tag1<=tag[29][1]; cur_lru<=lru[29]; cur_data0[0]<=data[29][0][0]; cur_data0[1]<=data[29][0][1]; cur_data0[2]<=data[29][0][2]; cur_data0[3]<=data[29][0][3]; cur_data0[4]<=data[29][0][4]; cur_data0[5]<=data[29][0][5]; cur_data0[6]<=data[29][0][6]; cur_data0[7]<=data[29][0][7]; cur_data1[0]<=data[29][1][0]; cur_data1[1]<=data[29][1][1]; cur_data1[2]<=data[29][1][2]; cur_data1[3]<=data[29][1][3]; cur_data1[4]<=data[29][1][4]; cur_data1[5]<=data[29][1][5]; cur_data1[6]<=data[29][1][6]; cur_data1[7]<=data[29][1][7]; end
                    6'd30: begin cur_valid0<=valid[30][0]; cur_valid1<=valid[30][1]; cur_dirty0<=dirty[30][0]; cur_dirty1<=dirty[30][1]; cur_tag0<=tag[30][0]; cur_tag1<=tag[30][1]; cur_lru<=lru[30]; cur_data0[0]<=data[30][0][0]; cur_data0[1]<=data[30][0][1]; cur_data0[2]<=data[30][0][2]; cur_data0[3]<=data[30][0][3]; cur_data0[4]<=data[30][0][4]; cur_data0[5]<=data[30][0][5]; cur_data0[6]<=data[30][0][6]; cur_data0[7]<=data[30][0][7]; cur_data1[0]<=data[30][1][0]; cur_data1[1]<=data[30][1][1]; cur_data1[2]<=data[30][1][2]; cur_data1[3]<=data[30][1][3]; cur_data1[4]<=data[30][1][4]; cur_data1[5]<=data[30][1][5]; cur_data1[6]<=data[30][1][6]; cur_data1[7]<=data[30][1][7]; end
                    6'd31: begin cur_valid0<=valid[31][0]; cur_valid1<=valid[31][1]; cur_dirty0<=dirty[31][0]; cur_dirty1<=dirty[31][1]; cur_tag0<=tag[31][0]; cur_tag1<=tag[31][1]; cur_lru<=lru[31]; cur_data0[0]<=data[31][0][0]; cur_data0[1]<=data[31][0][1]; cur_data0[2]<=data[31][0][2]; cur_data0[3]<=data[31][0][3]; cur_data0[4]<=data[31][0][4]; cur_data0[5]<=data[31][0][5]; cur_data0[6]<=data[31][0][6]; cur_data0[7]<=data[31][0][7]; cur_data1[0]<=data[31][1][0]; cur_data1[1]<=data[31][1][1]; cur_data1[2]<=data[31][1][2]; cur_data1[3]<=data[31][1][3]; cur_data1[4]<=data[31][1][4]; cur_data1[5]<=data[31][1][5]; cur_data1[6]<=data[31][1][6]; cur_data1[7]<=data[31][1][7]; end
                    6'd32: begin cur_valid0<=valid[32][0]; cur_valid1<=valid[32][1]; cur_dirty0<=dirty[32][0]; cur_dirty1<=dirty[32][1]; cur_tag0<=tag[32][0]; cur_tag1<=tag[32][1]; cur_lru<=lru[32]; cur_data0[0]<=data[32][0][0]; cur_data0[1]<=data[32][0][1]; cur_data0[2]<=data[32][0][2]; cur_data0[3]<=data[32][0][3]; cur_data0[4]<=data[32][0][4]; cur_data0[5]<=data[32][0][5]; cur_data0[6]<=data[32][0][6]; cur_data0[7]<=data[32][0][7]; cur_data1[0]<=data[32][1][0]; cur_data1[1]<=data[32][1][1]; cur_data1[2]<=data[32][1][2]; cur_data1[3]<=data[32][1][3]; cur_data1[4]<=data[32][1][4]; cur_data1[5]<=data[32][1][5]; cur_data1[6]<=data[32][1][6]; cur_data1[7]<=data[32][1][7]; end
                    6'd33: begin cur_valid0<=valid[33][0]; cur_valid1<=valid[33][1]; cur_dirty0<=dirty[33][0]; cur_dirty1<=dirty[33][1]; cur_tag0<=tag[33][0]; cur_tag1<=tag[33][1]; cur_lru<=lru[33]; cur_data0[0]<=data[33][0][0]; cur_data0[1]<=data[33][0][1]; cur_data0[2]<=data[33][0][2]; cur_data0[3]<=data[33][0][3]; cur_data0[4]<=data[33][0][4]; cur_data0[5]<=data[33][0][5]; cur_data0[6]<=data[33][0][6]; cur_data0[7]<=data[33][0][7]; cur_data1[0]<=data[33][1][0]; cur_data1[1]<=data[33][1][1]; cur_data1[2]<=data[33][1][2]; cur_data1[3]<=data[33][1][3]; cur_data1[4]<=data[33][1][4]; cur_data1[5]<=data[33][1][5]; cur_data1[6]<=data[33][1][6]; cur_data1[7]<=data[33][1][7]; end
                    6'd34: begin cur_valid0<=valid[34][0]; cur_valid1<=valid[34][1]; cur_dirty0<=dirty[34][0]; cur_dirty1<=dirty[34][1]; cur_tag0<=tag[34][0]; cur_tag1<=tag[34][1]; cur_lru<=lru[34]; cur_data0[0]<=data[34][0][0]; cur_data0[1]<=data[34][0][1]; cur_data0[2]<=data[34][0][2]; cur_data0[3]<=data[34][0][3]; cur_data0[4]<=data[34][0][4]; cur_data0[5]<=data[34][0][5]; cur_data0[6]<=data[34][0][6]; cur_data0[7]<=data[34][0][7]; cur_data1[0]<=data[34][1][0]; cur_data1[1]<=data[34][1][1]; cur_data1[2]<=data[34][1][2]; cur_data1[3]<=data[34][1][3]; cur_data1[4]<=data[34][1][4]; cur_data1[5]<=data[34][1][5]; cur_data1[6]<=data[34][1][6]; cur_data1[7]<=data[34][1][7]; end
                    6'd35: begin cur_valid0<=valid[35][0]; cur_valid1<=valid[35][1]; cur_dirty0<=dirty[35][0]; cur_dirty1<=dirty[35][1]; cur_tag0<=tag[35][0]; cur_tag1<=tag[35][1]; cur_lru<=lru[35]; cur_data0[0]<=data[35][0][0]; cur_data0[1]<=data[35][0][1]; cur_data0[2]<=data[35][0][2]; cur_data0[3]<=data[35][0][3]; cur_data0[4]<=data[35][0][4]; cur_data0[5]<=data[35][0][5]; cur_data0[6]<=data[35][0][6]; cur_data0[7]<=data[35][0][7]; cur_data1[0]<=data[35][1][0]; cur_data1[1]<=data[35][1][1]; cur_data1[2]<=data[35][1][2]; cur_data1[3]<=data[35][1][3]; cur_data1[4]<=data[35][1][4]; cur_data1[5]<=data[35][1][5]; cur_data1[6]<=data[35][1][6]; cur_data1[7]<=data[35][1][7]; end
                    6'd36: begin cur_valid0<=valid[36][0]; cur_valid1<=valid[36][1]; cur_dirty0<=dirty[36][0]; cur_dirty1<=dirty[36][1]; cur_tag0<=tag[36][0]; cur_tag1<=tag[36][1]; cur_lru<=lru[36]; cur_data0[0]<=data[36][0][0]; cur_data0[1]<=data[36][0][1]; cur_data0[2]<=data[36][0][2]; cur_data0[3]<=data[36][0][3]; cur_data0[4]<=data[36][0][4]; cur_data0[5]<=data[36][0][5]; cur_data0[6]<=data[36][0][6]; cur_data0[7]<=data[36][0][7]; cur_data1[0]<=data[36][1][0]; cur_data1[1]<=data[36][1][1]; cur_data1[2]<=data[36][1][2]; cur_data1[3]<=data[36][1][3]; cur_data1[4]<=data[36][1][4]; cur_data1[5]<=data[36][1][5]; cur_data1[6]<=data[36][1][6]; cur_data1[7]<=data[36][1][7]; end
                    6'd37: begin cur_valid0<=valid[37][0]; cur_valid1<=valid[37][1]; cur_dirty0<=dirty[37][0]; cur_dirty1<=dirty[37][1]; cur_tag0<=tag[37][0]; cur_tag1<=tag[37][1]; cur_lru<=lru[37]; cur_data0[0]<=data[37][0][0]; cur_data0[1]<=data[37][0][1]; cur_data0[2]<=data[37][0][2]; cur_data0[3]<=data[37][0][3]; cur_data0[4]<=data[37][0][4]; cur_data0[5]<=data[37][0][5]; cur_data0[6]<=data[37][0][6]; cur_data0[7]<=data[37][0][7]; cur_data1[0]<=data[37][1][0]; cur_data1[1]<=data[37][1][1]; cur_data1[2]<=data[37][1][2]; cur_data1[3]<=data[37][1][3]; cur_data1[4]<=data[37][1][4]; cur_data1[5]<=data[37][1][5]; cur_data1[6]<=data[37][1][6]; cur_data1[7]<=data[37][1][7]; end
                    6'd38: begin cur_valid0<=valid[38][0]; cur_valid1<=valid[38][1]; cur_dirty0<=dirty[38][0]; cur_dirty1<=dirty[38][1]; cur_tag0<=tag[38][0]; cur_tag1<=tag[38][1]; cur_lru<=lru[38]; cur_data0[0]<=data[38][0][0]; cur_data0[1]<=data[38][0][1]; cur_data0[2]<=data[38][0][2]; cur_data0[3]<=data[38][0][3]; cur_data0[4]<=data[38][0][4]; cur_data0[5]<=data[38][0][5]; cur_data0[6]<=data[38][0][6]; cur_data0[7]<=data[38][0][7]; cur_data1[0]<=data[38][1][0]; cur_data1[1]<=data[38][1][1]; cur_data1[2]<=data[38][1][2]; cur_data1[3]<=data[38][1][3]; cur_data1[4]<=data[38][1][4]; cur_data1[5]<=data[38][1][5]; cur_data1[6]<=data[38][1][6]; cur_data1[7]<=data[38][1][7]; end
                    6'd39: begin cur_valid0<=valid[39][0]; cur_valid1<=valid[39][1]; cur_dirty0<=dirty[39][0]; cur_dirty1<=dirty[39][1]; cur_tag0<=tag[39][0]; cur_tag1<=tag[39][1]; cur_lru<=lru[39]; cur_data0[0]<=data[39][0][0]; cur_data0[1]<=data[39][0][1]; cur_data0[2]<=data[39][0][2]; cur_data0[3]<=data[39][0][3]; cur_data0[4]<=data[39][0][4]; cur_data0[5]<=data[39][0][5]; cur_data0[6]<=data[39][0][6]; cur_data0[7]<=data[39][0][7]; cur_data1[0]<=data[39][1][0]; cur_data1[1]<=data[39][1][1]; cur_data1[2]<=data[39][1][2]; cur_data1[3]<=data[39][1][3]; cur_data1[4]<=data[39][1][4]; cur_data1[5]<=data[39][1][5]; cur_data1[6]<=data[39][1][6]; cur_data1[7]<=data[39][1][7]; end
                    6'd40: begin cur_valid0<=valid[40][0]; cur_valid1<=valid[40][1]; cur_dirty0<=dirty[40][0]; cur_dirty1<=dirty[40][1]; cur_tag0<=tag[40][0]; cur_tag1<=tag[40][1]; cur_lru<=lru[40]; cur_data0[0]<=data[40][0][0]; cur_data0[1]<=data[40][0][1]; cur_data0[2]<=data[40][0][2]; cur_data0[3]<=data[40][0][3]; cur_data0[4]<=data[40][0][4]; cur_data0[5]<=data[40][0][5]; cur_data0[6]<=data[40][0][6]; cur_data0[7]<=data[40][0][7]; cur_data1[0]<=data[40][1][0]; cur_data1[1]<=data[40][1][1]; cur_data1[2]<=data[40][1][2]; cur_data1[3]<=data[40][1][3]; cur_data1[4]<=data[40][1][4]; cur_data1[5]<=data[40][1][5]; cur_data1[6]<=data[40][1][6]; cur_data1[7]<=data[40][1][7]; end
                    6'd41: begin cur_valid0<=valid[41][0]; cur_valid1<=valid[41][1]; cur_dirty0<=dirty[41][0]; cur_dirty1<=dirty[41][1]; cur_tag0<=tag[41][0]; cur_tag1<=tag[41][1]; cur_lru<=lru[41]; cur_data0[0]<=data[41][0][0]; cur_data0[1]<=data[41][0][1]; cur_data0[2]<=data[41][0][2]; cur_data0[3]<=data[41][0][3]; cur_data0[4]<=data[41][0][4]; cur_data0[5]<=data[41][0][5]; cur_data0[6]<=data[41][0][6]; cur_data0[7]<=data[41][0][7]; cur_data1[0]<=data[41][1][0]; cur_data1[1]<=data[41][1][1]; cur_data1[2]<=data[41][1][2]; cur_data1[3]<=data[41][1][3]; cur_data1[4]<=data[41][1][4]; cur_data1[5]<=data[41][1][5]; cur_data1[6]<=data[41][1][6]; cur_data1[7]<=data[41][1][7]; end
                    6'd42: begin cur_valid0<=valid[42][0]; cur_valid1<=valid[42][1]; cur_dirty0<=dirty[42][0]; cur_dirty1<=dirty[42][1]; cur_tag0<=tag[42][0]; cur_tag1<=tag[42][1]; cur_lru<=lru[42]; cur_data0[0]<=data[42][0][0]; cur_data0[1]<=data[42][0][1]; cur_data0[2]<=data[42][0][2]; cur_data0[3]<=data[42][0][3]; cur_data0[4]<=data[42][0][4]; cur_data0[5]<=data[42][0][5]; cur_data0[6]<=data[42][0][6]; cur_data0[7]<=data[42][0][7]; cur_data1[0]<=data[42][1][0]; cur_data1[1]<=data[42][1][1]; cur_data1[2]<=data[42][1][2]; cur_data1[3]<=data[42][1][3]; cur_data1[4]<=data[42][1][4]; cur_data1[5]<=data[42][1][5]; cur_data1[6]<=data[42][1][6]; cur_data1[7]<=data[42][1][7]; end
                    6'd43: begin cur_valid0<=valid[43][0]; cur_valid1<=valid[43][1]; cur_dirty0<=dirty[43][0]; cur_dirty1<=dirty[43][1]; cur_tag0<=tag[43][0]; cur_tag1<=tag[43][1]; cur_lru<=lru[43]; cur_data0[0]<=data[43][0][0]; cur_data0[1]<=data[43][0][1]; cur_data0[2]<=data[43][0][2]; cur_data0[3]<=data[43][0][3]; cur_data0[4]<=data[43][0][4]; cur_data0[5]<=data[43][0][5]; cur_data0[6]<=data[43][0][6]; cur_data0[7]<=data[43][0][7]; cur_data1[0]<=data[43][1][0]; cur_data1[1]<=data[43][1][1]; cur_data1[2]<=data[43][1][2]; cur_data1[3]<=data[43][1][3]; cur_data1[4]<=data[43][1][4]; cur_data1[5]<=data[43][1][5]; cur_data1[6]<=data[43][1][6]; cur_data1[7]<=data[43][1][7]; end
                    6'd44: begin cur_valid0<=valid[44][0]; cur_valid1<=valid[44][1]; cur_dirty0<=dirty[44][0]; cur_dirty1<=dirty[44][1]; cur_tag0<=tag[44][0]; cur_tag1<=tag[44][1]; cur_lru<=lru[44]; cur_data0[0]<=data[44][0][0]; cur_data0[1]<=data[44][0][1]; cur_data0[2]<=data[44][0][2]; cur_data0[3]<=data[44][0][3]; cur_data0[4]<=data[44][0][4]; cur_data0[5]<=data[44][0][5]; cur_data0[6]<=data[44][0][6]; cur_data0[7]<=data[44][0][7]; cur_data1[0]<=data[44][1][0]; cur_data1[1]<=data[44][1][1]; cur_data1[2]<=data[44][1][2]; cur_data1[3]<=data[44][1][3]; cur_data1[4]<=data[44][1][4]; cur_data1[5]<=data[44][1][5]; cur_data1[6]<=data[44][1][6]; cur_data1[7]<=data[44][1][7]; end
                    6'd45: begin cur_valid0<=valid[45][0]; cur_valid1<=valid[45][1]; cur_dirty0<=dirty[45][0]; cur_dirty1<=dirty[45][1]; cur_tag0<=tag[45][0]; cur_tag1<=tag[45][1]; cur_lru<=lru[45]; cur_data0[0]<=data[45][0][0]; cur_data0[1]<=data[45][0][1]; cur_data0[2]<=data[45][0][2]; cur_data0[3]<=data[45][0][3]; cur_data0[4]<=data[45][0][4]; cur_data0[5]<=data[45][0][5]; cur_data0[6]<=data[45][0][6]; cur_data0[7]<=data[45][0][7]; cur_data1[0]<=data[45][1][0]; cur_data1[1]<=data[45][1][1]; cur_data1[2]<=data[45][1][2]; cur_data1[3]<=data[45][1][3]; cur_data1[4]<=data[45][1][4]; cur_data1[5]<=data[45][1][5]; cur_data1[6]<=data[45][1][6]; cur_data1[7]<=data[45][1][7]; end
                    6'd46: begin cur_valid0<=valid[46][0]; cur_valid1<=valid[46][1]; cur_dirty0<=dirty[46][0]; cur_dirty1<=dirty[46][1]; cur_tag0<=tag[46][0]; cur_tag1<=tag[46][1]; cur_lru<=lru[46]; cur_data0[0]<=data[46][0][0]; cur_data0[1]<=data[46][0][1]; cur_data0[2]<=data[46][0][2]; cur_data0[3]<=data[46][0][3]; cur_data0[4]<=data[46][0][4]; cur_data0[5]<=data[46][0][5]; cur_data0[6]<=data[46][0][6]; cur_data0[7]<=data[46][0][7]; cur_data1[0]<=data[46][1][0]; cur_data1[1]<=data[46][1][1]; cur_data1[2]<=data[46][1][2]; cur_data1[3]<=data[46][1][3]; cur_data1[4]<=data[46][1][4]; cur_data1[5]<=data[46][1][5]; cur_data1[6]<=data[46][1][6]; cur_data1[7]<=data[46][1][7]; end
                    6'd47: begin cur_valid0<=valid[47][0]; cur_valid1<=valid[47][1]; cur_dirty0<=dirty[47][0]; cur_dirty1<=dirty[47][1]; cur_tag0<=tag[47][0]; cur_tag1<=tag[47][1]; cur_lru<=lru[47]; cur_data0[0]<=data[47][0][0]; cur_data0[1]<=data[47][0][1]; cur_data0[2]<=data[47][0][2]; cur_data0[3]<=data[47][0][3]; cur_data0[4]<=data[47][0][4]; cur_data0[5]<=data[47][0][5]; cur_data0[6]<=data[47][0][6]; cur_data0[7]<=data[47][0][7]; cur_data1[0]<=data[47][1][0]; cur_data1[1]<=data[47][1][1]; cur_data1[2]<=data[47][1][2]; cur_data1[3]<=data[47][1][3]; cur_data1[4]<=data[47][1][4]; cur_data1[5]<=data[47][1][5]; cur_data1[6]<=data[47][1][6]; cur_data1[7]<=data[47][1][7]; end
                    6'd48: begin cur_valid0<=valid[48][0]; cur_valid1<=valid[48][1]; cur_dirty0<=dirty[48][0]; cur_dirty1<=dirty[48][1]; cur_tag0<=tag[48][0]; cur_tag1<=tag[48][1]; cur_lru<=lru[48]; cur_data0[0]<=data[48][0][0]; cur_data0[1]<=data[48][0][1]; cur_data0[2]<=data[48][0][2]; cur_data0[3]<=data[48][0][3]; cur_data0[4]<=data[48][0][4]; cur_data0[5]<=data[48][0][5]; cur_data0[6]<=data[48][0][6]; cur_data0[7]<=data[48][0][7]; cur_data1[0]<=data[48][1][0]; cur_data1[1]<=data[48][1][1]; cur_data1[2]<=data[48][1][2]; cur_data1[3]<=data[48][1][3]; cur_data1[4]<=data[48][1][4]; cur_data1[5]<=data[48][1][5]; cur_data1[6]<=data[48][1][6]; cur_data1[7]<=data[48][1][7]; end
                    6'd49: begin cur_valid0<=valid[49][0]; cur_valid1<=valid[49][1]; cur_dirty0<=dirty[49][0]; cur_dirty1<=dirty[49][1]; cur_tag0<=tag[49][0]; cur_tag1<=tag[49][1]; cur_lru<=lru[49]; cur_data0[0]<=data[49][0][0]; cur_data0[1]<=data[49][0][1]; cur_data0[2]<=data[49][0][2]; cur_data0[3]<=data[49][0][3]; cur_data0[4]<=data[49][0][4]; cur_data0[5]<=data[49][0][5]; cur_data0[6]<=data[49][0][6]; cur_data0[7]<=data[49][0][7]; cur_data1[0]<=data[49][1][0]; cur_data1[1]<=data[49][1][1]; cur_data1[2]<=data[49][1][2]; cur_data1[3]<=data[49][1][3]; cur_data1[4]<=data[49][1][4]; cur_data1[5]<=data[49][1][5]; cur_data1[6]<=data[49][1][6]; cur_data1[7]<=data[49][1][7]; end
                    6'd50: begin cur_valid0<=valid[50][0]; cur_valid1<=valid[50][1]; cur_dirty0<=dirty[50][0]; cur_dirty1<=dirty[50][1]; cur_tag0<=tag[50][0]; cur_tag1<=tag[50][1]; cur_lru<=lru[50]; cur_data0[0]<=data[50][0][0]; cur_data0[1]<=data[50][0][1]; cur_data0[2]<=data[50][0][2]; cur_data0[3]<=data[50][0][3]; cur_data0[4]<=data[50][0][4]; cur_data0[5]<=data[50][0][5]; cur_data0[6]<=data[50][0][6]; cur_data0[7]<=data[50][0][7]; cur_data1[0]<=data[50][1][0]; cur_data1[1]<=data[50][1][1]; cur_data1[2]<=data[50][1][2]; cur_data1[3]<=data[50][1][3]; cur_data1[4]<=data[50][1][4]; cur_data1[5]<=data[50][1][5]; cur_data1[6]<=data[50][1][6]; cur_data1[7]<=data[50][1][7]; end
                    6'd51: begin cur_valid0<=valid[51][0]; cur_valid1<=valid[51][1]; cur_dirty0<=dirty[51][0]; cur_dirty1<=dirty[51][1]; cur_tag0<=tag[51][0]; cur_tag1<=tag[51][1]; cur_lru<=lru[51]; cur_data0[0]<=data[51][0][0]; cur_data0[1]<=data[51][0][1]; cur_data0[2]<=data[51][0][2]; cur_data0[3]<=data[51][0][3]; cur_data0[4]<=data[51][0][4]; cur_data0[5]<=data[51][0][5]; cur_data0[6]<=data[51][0][6]; cur_data0[7]<=data[51][0][7]; cur_data1[0]<=data[51][1][0]; cur_data1[1]<=data[51][1][1]; cur_data1[2]<=data[51][1][2]; cur_data1[3]<=data[51][1][3]; cur_data1[4]<=data[51][1][4]; cur_data1[5]<=data[51][1][5]; cur_data1[6]<=data[51][1][6]; cur_data1[7]<=data[51][1][7]; end
                    6'd52: begin cur_valid0<=valid[52][0]; cur_valid1<=valid[52][1]; cur_dirty0<=dirty[52][0]; cur_dirty1<=dirty[52][1]; cur_tag0<=tag[52][0]; cur_tag1<=tag[52][1]; cur_lru<=lru[52]; cur_data0[0]<=data[52][0][0]; cur_data0[1]<=data[52][0][1]; cur_data0[2]<=data[52][0][2]; cur_data0[3]<=data[52][0][3]; cur_data0[4]<=data[52][0][4]; cur_data0[5]<=data[52][0][5]; cur_data0[6]<=data[52][0][6]; cur_data0[7]<=data[52][0][7]; cur_data1[0]<=data[52][1][0]; cur_data1[1]<=data[52][1][1]; cur_data1[2]<=data[52][1][2]; cur_data1[3]<=data[52][1][3]; cur_data1[4]<=data[52][1][4]; cur_data1[5]<=data[52][1][5]; cur_data1[6]<=data[52][1][6]; cur_data1[7]<=data[52][1][7]; end
                    6'd53: begin cur_valid0<=valid[53][0]; cur_valid1<=valid[53][1]; cur_dirty0<=dirty[53][0]; cur_dirty1<=dirty[53][1]; cur_tag0<=tag[53][0]; cur_tag1<=tag[53][1]; cur_lru<=lru[53]; cur_data0[0]<=data[53][0][0]; cur_data0[1]<=data[53][0][1]; cur_data0[2]<=data[53][0][2]; cur_data0[3]<=data[53][0][3]; cur_data0[4]<=data[53][0][4]; cur_data0[5]<=data[53][0][5]; cur_data0[6]<=data[53][0][6]; cur_data0[7]<=data[53][0][7]; cur_data1[0]<=data[53][1][0]; cur_data1[1]<=data[53][1][1]; cur_data1[2]<=data[53][1][2]; cur_data1[3]<=data[53][1][3]; cur_data1[4]<=data[53][1][4]; cur_data1[5]<=data[53][1][5]; cur_data1[6]<=data[53][1][6]; cur_data1[7]<=data[53][1][7]; end
                    6'd54: begin cur_valid0<=valid[54][0]; cur_valid1<=valid[54][1]; cur_dirty0<=dirty[54][0]; cur_dirty1<=dirty[54][1]; cur_tag0<=tag[54][0]; cur_tag1<=tag[54][1]; cur_lru<=lru[54]; cur_data0[0]<=data[54][0][0]; cur_data0[1]<=data[54][0][1]; cur_data0[2]<=data[54][0][2]; cur_data0[3]<=data[54][0][3]; cur_data0[4]<=data[54][0][4]; cur_data0[5]<=data[54][0][5]; cur_data0[6]<=data[54][0][6]; cur_data0[7]<=data[54][0][7]; cur_data1[0]<=data[54][1][0]; cur_data1[1]<=data[54][1][1]; cur_data1[2]<=data[54][1][2]; cur_data1[3]<=data[54][1][3]; cur_data1[4]<=data[54][1][4]; cur_data1[5]<=data[54][1][5]; cur_data1[6]<=data[54][1][6]; cur_data1[7]<=data[54][1][7]; end
                    6'd55: begin cur_valid0<=valid[55][0]; cur_valid1<=valid[55][1]; cur_dirty0<=dirty[55][0]; cur_dirty1<=dirty[55][1]; cur_tag0<=tag[55][0]; cur_tag1<=tag[55][1]; cur_lru<=lru[55]; cur_data0[0]<=data[55][0][0]; cur_data0[1]<=data[55][0][1]; cur_data0[2]<=data[55][0][2]; cur_data0[3]<=data[55][0][3]; cur_data0[4]<=data[55][0][4]; cur_data0[5]<=data[55][0][5]; cur_data0[6]<=data[55][0][6]; cur_data0[7]<=data[55][0][7]; cur_data1[0]<=data[55][1][0]; cur_data1[1]<=data[55][1][1]; cur_data1[2]<=data[55][1][2]; cur_data1[3]<=data[55][1][3]; cur_data1[4]<=data[55][1][4]; cur_data1[5]<=data[55][1][5]; cur_data1[6]<=data[55][1][6]; cur_data1[7]<=data[55][1][7]; end
                    6'd56: begin cur_valid0<=valid[56][0]; cur_valid1<=valid[56][1]; cur_dirty0<=dirty[56][0]; cur_dirty1<=dirty[56][1]; cur_tag0<=tag[56][0]; cur_tag1<=tag[56][1]; cur_lru<=lru[56]; cur_data0[0]<=data[56][0][0]; cur_data0[1]<=data[56][0][1]; cur_data0[2]<=data[56][0][2]; cur_data0[3]<=data[56][0][3]; cur_data0[4]<=data[56][0][4]; cur_data0[5]<=data[56][0][5]; cur_data0[6]<=data[56][0][6]; cur_data0[7]<=data[56][0][7]; cur_data1[0]<=data[56][1][0]; cur_data1[1]<=data[56][1][1]; cur_data1[2]<=data[56][1][2]; cur_data1[3]<=data[56][1][3]; cur_data1[4]<=data[56][1][4]; cur_data1[5]<=data[56][1][5]; cur_data1[6]<=data[56][1][6]; cur_data1[7]<=data[56][1][7]; end
                    6'd57: begin cur_valid0<=valid[57][0]; cur_valid1<=valid[57][1]; cur_dirty0<=dirty[57][0]; cur_dirty1<=dirty[57][1]; cur_tag0<=tag[57][0]; cur_tag1<=tag[57][1]; cur_lru<=lru[57]; cur_data0[0]<=data[57][0][0]; cur_data0[1]<=data[57][0][1]; cur_data0[2]<=data[57][0][2]; cur_data0[3]<=data[57][0][3]; cur_data0[4]<=data[57][0][4]; cur_data0[5]<=data[57][0][5]; cur_data0[6]<=data[57][0][6]; cur_data0[7]<=data[57][0][7]; cur_data1[0]<=data[57][1][0]; cur_data1[1]<=data[57][1][1]; cur_data1[2]<=data[57][1][2]; cur_data1[3]<=data[57][1][3]; cur_data1[4]<=data[57][1][4]; cur_data1[5]<=data[57][1][5]; cur_data1[6]<=data[57][1][6]; cur_data1[7]<=data[57][1][7]; end
                    6'd58: begin cur_valid0<=valid[58][0]; cur_valid1<=valid[58][1]; cur_dirty0<=dirty[58][0]; cur_dirty1<=dirty[58][1]; cur_tag0<=tag[58][0]; cur_tag1<=tag[58][1]; cur_lru<=lru[58]; cur_data0[0]<=data[58][0][0]; cur_data0[1]<=data[58][0][1]; cur_data0[2]<=data[58][0][2]; cur_data0[3]<=data[58][0][3]; cur_data0[4]<=data[58][0][4]; cur_data0[5]<=data[58][0][5]; cur_data0[6]<=data[58][0][6]; cur_data0[7]<=data[58][0][7]; cur_data1[0]<=data[58][1][0]; cur_data1[1]<=data[58][1][1]; cur_data1[2]<=data[58][1][2]; cur_data1[3]<=data[58][1][3]; cur_data1[4]<=data[58][1][4]; cur_data1[5]<=data[58][1][5]; cur_data1[6]<=data[58][1][6]; cur_data1[7]<=data[58][1][7]; end
                    6'd59: begin cur_valid0<=valid[59][0]; cur_valid1<=valid[59][1]; cur_dirty0<=dirty[59][0]; cur_dirty1<=dirty[59][1]; cur_tag0<=tag[59][0]; cur_tag1<=tag[59][1]; cur_lru<=lru[59]; cur_data0[0]<=data[59][0][0]; cur_data0[1]<=data[59][0][1]; cur_data0[2]<=data[59][0][2]; cur_data0[3]<=data[59][0][3]; cur_data0[4]<=data[59][0][4]; cur_data0[5]<=data[59][0][5]; cur_data0[6]<=data[59][0][6]; cur_data0[7]<=data[59][0][7]; cur_data1[0]<=data[59][1][0]; cur_data1[1]<=data[59][1][1]; cur_data1[2]<=data[59][1][2]; cur_data1[3]<=data[59][1][3]; cur_data1[4]<=data[59][1][4]; cur_data1[5]<=data[59][1][5]; cur_data1[6]<=data[59][1][6]; cur_data1[7]<=data[59][1][7]; end
                    6'd60: begin cur_valid0<=valid[60][0]; cur_valid1<=valid[60][1]; cur_dirty0<=dirty[60][0]; cur_dirty1<=dirty[60][1]; cur_tag0<=tag[60][0]; cur_tag1<=tag[60][1]; cur_lru<=lru[60]; cur_data0[0]<=data[60][0][0]; cur_data0[1]<=data[60][0][1]; cur_data0[2]<=data[60][0][2]; cur_data0[3]<=data[60][0][3]; cur_data0[4]<=data[60][0][4]; cur_data0[5]<=data[60][0][5]; cur_data0[6]<=data[60][0][6]; cur_data0[7]<=data[60][0][7]; cur_data1[0]<=data[60][1][0]; cur_data1[1]<=data[60][1][1]; cur_data1[2]<=data[60][1][2]; cur_data1[3]<=data[60][1][3]; cur_data1[4]<=data[60][1][4]; cur_data1[5]<=data[60][1][5]; cur_data1[6]<=data[60][1][6]; cur_data1[7]<=data[60][1][7]; end
                    6'd61: begin cur_valid0<=valid[61][0]; cur_valid1<=valid[61][1]; cur_dirty0<=dirty[61][0]; cur_dirty1<=dirty[61][1]; cur_tag0<=tag[61][0]; cur_tag1<=tag[61][1]; cur_lru<=lru[61]; cur_data0[0]<=data[61][0][0]; cur_data0[1]<=data[61][0][1]; cur_data0[2]<=data[61][0][2]; cur_data0[3]<=data[61][0][3]; cur_data0[4]<=data[61][0][4]; cur_data0[5]<=data[61][0][5]; cur_data0[6]<=data[61][0][6]; cur_data0[7]<=data[61][0][7]; cur_data1[0]<=data[61][1][0]; cur_data1[1]<=data[61][1][1]; cur_data1[2]<=data[61][1][2]; cur_data1[3]<=data[61][1][3]; cur_data1[4]<=data[61][1][4]; cur_data1[5]<=data[61][1][5]; cur_data1[6]<=data[61][1][6]; cur_data1[7]<=data[61][1][7]; end
                    6'd62: begin cur_valid0<=valid[62][0]; cur_valid1<=valid[62][1]; cur_dirty0<=dirty[62][0]; cur_dirty1<=dirty[62][1]; cur_tag0<=tag[62][0]; cur_tag1<=tag[62][1]; cur_lru<=lru[62]; cur_data0[0]<=data[62][0][0]; cur_data0[1]<=data[62][0][1]; cur_data0[2]<=data[62][0][2]; cur_data0[3]<=data[62][0][3]; cur_data0[4]<=data[62][0][4]; cur_data0[5]<=data[62][0][5]; cur_data0[6]<=data[62][0][6]; cur_data0[7]<=data[62][0][7]; cur_data1[0]<=data[62][1][0]; cur_data1[1]<=data[62][1][1]; cur_data1[2]<=data[62][1][2]; cur_data1[3]<=data[62][1][3]; cur_data1[4]<=data[62][1][4]; cur_data1[5]<=data[62][1][5]; cur_data1[6]<=data[62][1][6]; cur_data1[7]<=data[62][1][7]; end
                    6'd63: begin cur_valid0<=valid[63][0]; cur_valid1<=valid[63][1]; cur_dirty0<=dirty[63][0]; cur_dirty1<=dirty[63][1]; cur_tag0<=tag[63][0]; cur_tag1<=tag[63][1]; cur_lru<=lru[63]; cur_data0[0]<=data[63][0][0]; cur_data0[1]<=data[63][0][1]; cur_data0[2]<=data[63][0][2]; cur_data0[3]<=data[63][0][3]; cur_data0[4]<=data[63][0][4]; cur_data0[5]<=data[63][0][5]; cur_data0[6]<=data[63][0][6]; cur_data0[7]<=data[63][0][7]; cur_data1[0]<=data[63][1][0]; cur_data1[1]<=data[63][1][1]; cur_data1[2]<=data[63][1][2]; cur_data1[3]<=data[63][1][3]; cur_data1[4]<=data[63][1][4]; cur_data1[5]<=data[63][1][5]; cur_data1[6]<=data[63][1][6]; cur_data1[7]<=data[63][1][7]; end
                    default: ;
                endcase
                state <= S_DECIDE;
            end

            // ----------------------------------------------------------
            // cur_* estables; computar hit/miss y actuar.
            S_DECIDE: begin
                if (l1_hit) begin
                    // HIT: actualizar LRU, actualizar dato si write-hit, ir a RESPOND
                    lru[latched_index] <= ~hit_way;
                    response_data      <= hit_word;

                    if (latched_wr_en) begin
                        // Write-hit: modificar palabra en el arreglo y marcar dirty
                        case (hit_way)
                            1'b0: case (latched_offset)
                                3'd0: data[latched_index][0][0] <= latched_write_data;
                                3'd1: data[latched_index][0][1] <= latched_write_data;
                                3'd2: data[latched_index][0][2] <= latched_write_data;
                                3'd3: data[latched_index][0][3] <= latched_write_data;
                                3'd4: data[latched_index][0][4] <= latched_write_data;
                                3'd5: data[latched_index][0][5] <= latched_write_data;
                                3'd6: data[latched_index][0][6] <= latched_write_data;
                                3'd7: data[latched_index][0][7] <= latched_write_data;
                            endcase
                            1'b1: case (latched_offset)
                                3'd0: data[latched_index][1][0] <= latched_write_data;
                                3'd1: data[latched_index][1][1] <= latched_write_data;
                                3'd2: data[latched_index][1][2] <= latched_write_data;
                                3'd3: data[latched_index][1][3] <= latched_write_data;
                                3'd4: data[latched_index][1][4] <= latched_write_data;
                                3'd5: data[latched_index][1][5] <= latched_write_data;
                                3'd6: data[latched_index][1][6] <= latched_write_data;
                                3'd7: data[latched_index][1][7] <= latched_write_data;
                            endcase
                        endcase
                        case (hit_way)
                            1'b0: dirty[latched_index][0] <= 1'b1;
                            1'b1: dirty[latched_index][1] <= 1'b1;
                        endcase
                        l1_write_hits <= l1_write_hits + 1;
                    end else begin
                        l1_read_hits <= l1_read_hits + 1;
                    end
                    state <= S_RESPOND;

                end else begin
                    // MISS: guardar línea dirty de la víctima para writeback
                    saved_victim_dirty <= victim_dirty;
                    if (victim_dirty) begin
                        for (fi = 0; fi < LINE_WORDS; fi++)
                            l1_dirty_line[fi] <= victim_way ? cur_data1[fi] : cur_data0[fi];
                    end
                    if (latched_wr_en) l1_write_misses <= l1_write_misses + 1;
                    else               l1_read_misses  <= l1_read_misses  + 1;
                    state <= S_MISS;
                end
            end

            // ----------------------------------------------------------
            // Espera que L2 esté disponible (l2_ready=1 ⟺ L2 en S_IDLE).
            // Cuando L2 acepta: envía l1_req=1 (y dirty_writeback si aplica).
            // El l1_req=1 queda latched hasta el próximo flanco (L2 lo ve en
            // el ciclo siguiente porque lo registramos via NBA).
            S_MISS: begin
                if (l2_ready) begin
                    l1_req             <= 1'b1;
                    l1_addr            <= latched_line_base;
                    l1_wr_en           <= 1'b0;        // siempre pide read de línea
                    l1_write_word      <= latched_write_data;
                    l1_dirty_writeback <= saved_victim_dirty;
                    state              <= S_FILL;
                end
            end

            // ----------------------------------------------------------
            // Espera l2_valid. Instala la línea nueva en la vía víctima.
            // Write-allocate: si era STORE, aplica la escritura a la línea.
            S_FILL: begin
                if (l2_valid) begin
                    case (victim_way)
                        1'b0: begin
                            valid[latched_index][0] <= 1'b1;
                            tag[latched_index][0]   <= latched_tag;
                            dirty[latched_index][0] <= latched_wr_en;
                            data[latched_index][0][0] <= l2_line[0];
                            data[latched_index][0][1] <= l2_line[1];
                            data[latched_index][0][2] <= l2_line[2];
                            data[latched_index][0][3] <= l2_line[3];
                            data[latched_index][0][4] <= l2_line[4];
                            data[latched_index][0][5] <= l2_line[5];
                            data[latched_index][0][6] <= l2_line[6];
                            data[latched_index][0][7] <= l2_line[7];
                            if (latched_wr_en) case (latched_offset)
                                3'd0: data[latched_index][0][0] <= latched_write_data;
                                3'd1: data[latched_index][0][1] <= latched_write_data;
                                3'd2: data[latched_index][0][2] <= latched_write_data;
                                3'd3: data[latched_index][0][3] <= latched_write_data;
                                3'd4: data[latched_index][0][4] <= latched_write_data;
                                3'd5: data[latched_index][0][5] <= latched_write_data;
                                3'd6: data[latched_index][0][6] <= latched_write_data;
                                3'd7: data[latched_index][0][7] <= latched_write_data;
                            endcase
                        end
                        1'b1: begin
                            valid[latched_index][1] <= 1'b1;
                            tag[latched_index][1]   <= latched_tag;
                            dirty[latched_index][1] <= latched_wr_en;
                            data[latched_index][1][0] <= l2_line[0];
                            data[latched_index][1][1] <= l2_line[1];
                            data[latched_index][1][2] <= l2_line[2];
                            data[latched_index][1][3] <= l2_line[3];
                            data[latched_index][1][4] <= l2_line[4];
                            data[latched_index][1][5] <= l2_line[5];
                            data[latched_index][1][6] <= l2_line[6];
                            data[latched_index][1][7] <= l2_line[7];
                            if (latched_wr_en) case (latched_offset)
                                3'd0: data[latched_index][1][0] <= latched_write_data;
                                3'd1: data[latched_index][1][1] <= latched_write_data;
                                3'd2: data[latched_index][1][2] <= latched_write_data;
                                3'd3: data[latched_index][1][3] <= latched_write_data;
                                3'd4: data[latched_index][1][4] <= latched_write_data;
                                3'd5: data[latched_index][1][5] <= latched_write_data;
                                3'd6: data[latched_index][1][6] <= latched_write_data;
                                3'd7: data[latched_index][1][7] <= latched_write_data;
                            endcase
                        end
                    endcase
                    // Victim way es ahora MRU
                    lru[latched_index] <= ~victim_way;
                    // Palabra de respuesta
                    response_data <= latched_wr_en ? latched_write_data : l2_line[latched_offset];
                    state         <= S_RESPOND;
                end
            end

            // ----------------------------------------------------------
            // Pulsa cpu_valid 1 ciclo. cache_stall ya es 0 en este estado.
            S_RESPOND: begin
                cpu_valid     <= 1'b1;
                cpu_read_data <= response_data;
                state         <= S_IDLE;
            end

            default: state <= S_IDLE;

        endcase
    end
end

endmodule
