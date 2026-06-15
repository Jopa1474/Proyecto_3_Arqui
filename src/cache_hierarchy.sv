// cache_hierarchy.sv
// Modulo que instancia cache_l1, cache_l2 y data_memoryv2 y expone
// una interfaz simple hacia la etapa MEM del pipeline.
//
// Flujo de señales:
//   Pipeline (MEM) → cache_l1 → cache_l2 → data_memoryv2
//
// Señal clave:
//   cache_stall → viene de cache_l1.cache_stall (L1 lo propaga mientras
//   espera a L2, que a su vez espera a memoria). El pipeline usa esta señal
//   para congelar PC y registros durante un miss.


`timescale 1ns/1ps

module cache_hierarchy #(
    parameter LINE_WORDS = 8 // indica que cada línea de caché tiene 8 palabras de 32 bits.
            // Este parámetro se reutiliza para conectar los arreglos de datos entre L1, L2 y memoria.

)(
    input  logic        clk,   // reloj del procesador.
    input  logic        rst_n, // reset activo en bajo. Es decir, cuando rst_n = 0, el sistema se reinicia.

    // ---- Interfaz con la etapa MEM del pipeline (datapathv2) ----
    input  logic        cpu_req,          // Indica que la etapa MEM del pipeline está haciendo una solicitud de memoria.
    input  logic [31:0] cpu_addr,         // Dirección de memoria enviada por el procesador.
    input  logic        cpu_wr_en,        // Indica si la operación es escritura o lectura , 1 = STORE, 0 = LOAD. 
    input  logic [31:0] cpu_write_data,   // Dato que el procesador quiere escribir en memoria cuando la instrucción es un STORE.
    output logic [31:0] cpu_read_data,    // Dato que se devuelve al procesador cuando la instrucción es un LOAD.
                                          // Este dato viene desde L1 si hay hit, o desde niveles inferiores si hubo miss.
    output logic        cache_stall,      // Señal que indica que el pipeline debe detenerse.
                                          // Cuando hay un miss en caché, cache_stall = 1, entonces el procesador debe congelar el PC y los registros del pipeline hasta que el dato esté listo
    output logic        stall_l1_miss,    // Stall por miss de L1 (espera a L2)
    output logic        stall_l2_miss,    // Stall por miss de L2 (espera a memoria principal)


// -------Contadores de rendimiento---------------------------------------------------------
    // Contadores que vienen de cache L1
    // Sirven para medir cuántos accesos fueron exitosos o fallidos en L1, separados por lectura y escritura.
    
    output logic [31:0] l1_read_hits,   // Lecturas encontradas en L1
    output logic [31:0] l1_read_misses, // Lecturas no encontradas en L1
    output logic [31:0] l1_write_hits,  // Escrituras encontradas en L1
    output logic [31:0] l1_write_misses,  // Escrituras no encontradas en L1


    // Contadores que vienen de cache L2
    // Funcionan igual que los de L1, pero miden el comportamiento de la segunda caché.
  
    output logic [31:0] l2_read_hits,   // Lecturas encontradas en L2
    output logic [31:0] l2_read_misses, // Lecturas no encontradas en L2
    output logic [31:0] l2_write_hits,  // Escrituras encontradas en L2
    output logic [31:0] l2_write_misses, // Escrituras no encontradas en L2

 // Contadores de memoria principal:
    output logic [31:0] mem_accesses, // cantidad de accesos realizados a memoria principal.
    output logic [31:0] mem_cycles    // cantidad de ciclos consumidos por la memoria.
);

// ============================================================
// Wires internos L1 ↔ L2
// ============================================================
logic        l1_req;   // Señal que L1 envía a L2 para pedir una línea cuando ocurre un miss en L1.
logic [31:0] l1_addr;  // Dirección que L1 envía a L2. Normalmente corresponde a la dirección que causó el miss.
logic        l1_wr_en; // Indica si la solicitud de L1 hacia L2 es una escritura.
logic [31:0] l1_write_word; // Palabra que L1 quiere escribir hacia L2. Se usa cuando hay una operación de escritura o writeback.
logic        l1_dirty_writeback; // Indica que L1 está devolviendo una línea sucia a L2.
                                 // Una línea sucia significa que fue modificada en L1 y todavía no se ha actualizado en niveles inferiores.
logic [31:0] l1_dirty_line  [0:LINE_WORDS-1];  // línea dirty de L1 hacia L2, es un arreglo que contiene una línea completa de L1 que debe escribirse hacia L2.
logic        l2_ready;  // Señal de L2 hacia L1 que indica que L2 está lista para recibir o procesar una solicitud. 
logic        l2_valid;  // Señal de L2 hacia L1 que indica que la línea solicitada ya está disponible.
logic [31:0] l2_line        [0:LINE_WORDS-1];  // Línea completa que L2 entrega a L1 cuando L1 tuvo un miss.

// ============================================================
// Wires internos L2 ↔ data_memoryv2
// ============================================================
logic        mem_req_w;  // Señal que L2 envía a memoria principal para solicitar acceso.
logic [31:0] mem_addr_w; // Dirección que L2 envía a memoria principal. 
logic        mem_wr_en_w; // Indica si la operación hacia memoria es escritura o lectura.
logic        mem_burst_en_w; // Indica que la memoria debe hacer una transferencia tipo burst.
                             // Eso significa que en lugar de devolver una sola palabra, devuelve una línea completa de varias palabras.
logic [31:0] mem_write_data_w; // Dato que L2 puede escribir en memoria principal.
logic        mem_ready_w;    // Indica que la memoria está lista para recibir una solicitud. 
logic        mem_valid_w;    // Indica que la memoria ya tiene datos válidos para entregar a L2. 
logic [31:0] mem_burst_data_w [0:LINE_WORDS-1];  // Línea completa que memoria principal entrega a L2.

// ============================================================
// Instancia cache_l1
// ============================================================
cache_l1 u_l1 (
    .clk                (clk),
    .rst_n              (rst_n),
    // CPU interface
    .cpu_req            (cpu_req),
    .cpu_addr           (cpu_addr),
    .cpu_wr_en          (cpu_wr_en),
    .cpu_write_data     (cpu_write_data),
    .cpu_read_data      (cpu_read_data),
    .cpu_valid          (),
    .cache_stall        (cache_stall),
    .stall_l1_miss      (stall_l1_miss),
    // Conexion L1 - L2
    .l1_req             (l1_req),
    .l1_addr            (l1_addr),
    .l1_wr_en           (l1_wr_en),
    .l1_write_word      (l1_write_word),
    .l1_dirty_writeback (l1_dirty_writeback),
    .l1_dirty_line      (l1_dirty_line),
    .l2_ready           (l2_ready),
    .l2_valid           (l2_valid),
    .l2_line            (l2_line),
    // Contadores
    .l1_read_hits       (l1_read_hits),
    .l1_read_misses     (l1_read_misses),
    .l1_write_hits      (l1_write_hits),
    .l1_write_misses    (l1_write_misses)
);

// ============================================================
// Instancia cache_l2
// ============================================================
cache_l2 u_l2 (
    .clk                (clk),
    .rst_n              (rst_n),
    // Conexion L1 - L2
    .l1_req             (l1_req),
    .l1_addr            (l1_addr),
    .l1_wr_en           (l1_wr_en),
    .l1_write_word      (l1_write_word),
    .l1_dirty_writeback (l1_dirty_writeback),
    .l1_dirty_line      (l1_dirty_line),
    .l2_ready           (l2_ready),
    .l2_valid           (l2_valid),
    .l2_line            (l2_line),

    // Conexion L2 - memoria principal
    .mem_req            (mem_req_w),
    .mem_addr           (mem_addr_w),
    .mem_wr_en          (mem_wr_en_w),
    .mem_burst_en       (mem_burst_en_w),
    .mem_write_data     (mem_write_data_w),
    .mem_ready          (mem_ready_w),
    .mem_valid          (mem_valid_w),
    .mem_burst_data     (mem_burst_data_w),
    // Contadores
    .l2_read_hits       (l2_read_hits),
    .l2_read_misses     (l2_read_misses),
    .l2_write_hits      (l2_write_hits),
    .l2_write_misses    (l2_write_misses),
    .stall_l2_miss      (stall_l2_miss)
);

// ============================================================
// Instancia data_memoryv2
// ============================================================
data_memoryv2 u_mem (
    .clk                (clk),
    .rst_n              (rst_n),
   
   // Estas son las señales de control y datos que vienen desde L2.
    .addr               (mem_addr_w),
    .write_data         (mem_write_data_w),
    .mem_req            (mem_req_w),
    .mem_wr_en          (mem_wr_en_w),
    .burst_en           (mem_burst_en_w),
   
   
    .read_data          (),              // no usado; L2 siempre pide burst, la razón es que L2 siempre trabaja con burst_data, es decir, con líneas completas, no con una sola palabra.
    .burst_data         (mem_burst_data_w), // Memoria devuelve una línea completa hacia L2.
    
    // Señales de sincronización entre memoria y L2:
    .mem_ready          (mem_ready_w),
    .mem_valid          (mem_valid_w),
    .align_fault        (),
    .total_mem_accesses (mem_accesses),
    .total_mem_cycles   (mem_cycles),
    .burst_count        ()
);

endmodule
