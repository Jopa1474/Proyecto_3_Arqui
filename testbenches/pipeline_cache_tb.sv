`timescale 1ns/1ps

`ifndef PROGRAM_FILE
`define PROGRAM_FILE "mem/instructions_cache_test.mem"
`endif

`ifndef CACHE_CSV_FILE
`define CACHE_CSV_FILE "sim/cache_timeline.csv"
`endif

`ifndef BENCH_ID
`define BENCH_ID 0
`endif

`ifndef BENCH_MODE
`define BENCH_MODE 0
`endif

// =============================================================================
// pipeline_cache_tb.sv — Pipeline + Cache Hierarchy Integration Test 
// =============================================================================
// Este testbench verifica que el datapathv3 funcione correctamente con la 
// jerarquía de caché integrada.
//
// El objetivo es probar accesos a memoria desde el pipeline completo:
//
// Pipeline -> cache_hierarchy -> L1 -> L2 -> memoria principal
//
// 
// Se revisan tres escenarios principales: 
//
//   Fase 1: LOAD a dirección fría (0x0100) → RAM miss → LONG STALL  (~33+ ciclos)
//   Fase 2: LOAD a misma dirección (0x0100) → L1 HIT   → SHORT/NO STALL (~1 ciclo)
//   Setup:  LOADs adicionales para llenar y desalojar L1 sin afectar L2
//   Fase 5: LOAD a 0x0100 tras desalojo de L1 → L2 HIT  → MEDIUM STALL (~8 ciclos)
//
// El test programa corre en datapathv3 con INST_INIT_FILE = instructions_cache_test.mem
// La clasificación se basa en la duración de cache_stall:
//   0-2  ciclos  → L1 hit
//   3-20 ciclos  → L2 hit  (HIT_LATENCY = 8 en cache_l2)
//   21+  ciclos  → RAM miss (SINGLE_LATENCY = 25 en data_memoryv2)
// =============================================================================

module pipeline_cache_tb;

    function automatic string benchmark_title();
        case (`BENCH_ID)
            1: benchmark_title = "Benchmark 1 - Sequential";
            2: benchmark_title = "Benchmark 2 - Stride";
            3: benchmark_title = "Benchmark 3 - Random";
            4: benchmark_title = "Benchmark 4 - Thousands";
            default: benchmark_title = "Cache test program";
        endcase
    endfunction


// ========================================================================= 
// Señales principales del testbench 
// =========================================================================
    logic clk, rst;


// ========================================================================= 
// Instancia del datapath bajo prueba 
// =========================================================================
// Se instancia datapathv3 como DUT. 
// DUT significa Design Under Test, es decir, el diseño que se está probando. 
// 
// INST_INIT_FILE carga el programa de prueba desde instructions_cache_test.mem. 
// Ese programa contiene las instrucciones LOAD necesarias para probar L1, L2 y RAM. 
// =========================================================================

    datapathv3 #(
        //.INST_INIT_FILE("mem/instructions_cache_test.mem")) dut (  // Archivo de instrucciones para esta prueba
        .INST_INIT_FILE(`PROGRAM_FILE)) dut (  // Archivo de instrucciones para la prueba de benchmarks dinamico
        .clk(clk),  // Conecta el reloj del testbench al datapath
        .rst(rst)   // Conecta el reset del testbench al datapath
    ); 



// ========================================================================= 
// Generador de reloj 
// =======================================================================
// Se genera un reloj de 100 MHz. 
// Período = 10 ns. 
// Medio período = 5 ns.
// // Cada 5 ns el reloj cambia de valor: 
// 0 -> 1 
// 1 -> 0 
// =======================================================================
    initial clk = 0;      // El reloj inicia en 0
    always #5 clk = ~clk; // Cambia el reloj cada 5 ns

// ========================================================================= 
// Variables para medir duración de stalls 
// =======================================================================
    int  cycle_count;     // Cuenta los ciclos ejecutados desde que termina el reset
    int  stall_event_num; // Cuenta cuántos eventos de stall han ocurrido
    int  stall_duration;  // Cuenta cuántos ciclos dura el stall actual
    logic in_stall;      // Indica si actualmente estamos dentro de un evento de stall

// =========================================================================
// Contadores de resultados del test
// =========================================================================
    int   pass_count;    // Cantidad de pruebas que pasaron
    int   fail_count;    // Cantidad de pruebas que fallaron
    logic halt_reported; // Evita que el bloque HALT se re-dispare cada ciclo
    integer csv_fd;      // Archivo CSV para timeline de cache y rendimiento

// ========================================================================= 
// Bloque inicial: configuración de simulación, reset e inicialización 
// =========================================================================
    initial begin
        // Genera archivo VCD para ver señales en GTKWave u otro visor de ondas.
        $dumpfile("sim/pipeline_cache_tb.vcd");

        // Guarda todas las señales del testbench y módulos internos. 
        // El 0 indica que se desea registrar toda la jerarquía desde pipeline_cache_tb.
        $dumpvars(0, pipeline_cache_tb);


        // Mensajes iniciales para identificar la simulación en consola.
        
        $display("====================================================================");
        $display("  pipeline_cache_tb — Cache Hierarchy Integration ");
        $display("  datapathv3: L1(4KB/2-way/1-cyc) -> L2(16KB/4-way/8-cyc) -> RAM(25-cyc)");
        $display("  Benchmark: %s", benchmark_title());
        $display("====================================================================");
        $display("");

        // Archivo CSV para graficas de comportamiento de cache por ciclo.
        csv_fd = $fopen(`CACHE_CSV_FILE, "w");
        if (csv_fd == 0) begin
            $display("[WARN] No se pudo abrir sim/cache_timeline.csv para escritura.");
        end else begin
            $fwrite(csv_fd,
                "cycle,cache_stall,stall_l1_miss,stall_l2_miss,l1_read_hits,l1_read_misses,l1_write_hits,l1_write_misses,l2_read_hits,l2_read_misses,l2_write_hits,l2_write_misses,mem_accesses,mem_cycles,perf_cycles,perf_instr,perf_stall_cache,perf_stall_l1,perf_stall_l2,perf_stall_branch,perf_stall_load_use,ipc_x1000,l1_hit_rate_x1000,l1_miss_rate_x1000,l2_hit_rate_x1000,l2_miss_rate_x1000,amat_x1000\n");
        end

       // Inicialización de contadores y banderas.
        cycle_count    = 0;  // Inicia contador de ciclos en 0
        stall_event_num = 0; // Todavía no hay eventos de stall
        stall_duration  = 0; // No hay duración de stall acumulada
        in_stall        = 0; // No estamos dentro de un stall al inicio
        pass_count      = 0; // Ninguna prueba ha pasado todavía
        fail_count      = 0; // Ninguna prueba ha fallado todavía
        halt_reported   = 0; // El reporte de HALT no se ha impreso aún

    // Activa reset.
        rst = 1;

    // Mantiene el reset activo durante 3 flancos positivos de reloj.    
        repeat(3) @(posedge clk);

    // Libera el reset.    
        rst = 0;


    // Mensaje informativo indicando que el reset terminó.
        $display("[INIT] Reset released at cycle 3");
        $display("");
    end

// ========================================================================= 
// Contador de ciclos 
// ========================================================================= 
// Este bloque cuenta ciclos después de liberar reset. 
// Se actualiza en cada flanco positivo de reloj. 
// =========================================================================
    always @(posedge clk) begin
        if (!rst)
            cycle_count <= cycle_count + 1; // Suma 1 ciclo si el reset no está activo

        // Escribe la traza CSV en cada ciclo activo para graficar el warm-up.
        if (!rst && csv_fd != 0) begin
            $fwrite(csv_fd,
                "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                cycle_count,
                dut.cache_stall,
                dut.stall_l1_miss,
                dut.stall_l2_miss,
                dut.l1_read_hits,
                dut.l1_read_misses,
                dut.l1_write_hits,
                dut.l1_write_misses,
                dut.l2_read_hits,
                dut.l2_read_misses,
                dut.l2_write_hits,
                dut.l2_write_misses,
                dut.perf_mem_accesses,
                dut.perf_mem_cycles_used,
                dut.perf_cycle_count,
                dut.perf_instr_count,
                dut.perf_cache_stall_cycles,
                dut.perf_stall_l1miss_cycles,
                dut.perf_stall_l2miss_cycles,
                dut.perf_branch_stalls,
                dut.perf_load_use_stalls,
                dut.perf_ipc_x1000,
                dut.perf_l1_hit_rate_x1000,
                dut.perf_l1_miss_rate_x1000,
                dut.perf_l2_hit_rate_x1000,
                dut.perf_l2_miss_rate_x1000,
                dut.perf_amat_x1000
            );
        end
    end

// ========================================================================= 
// Detección de cache_stall y medición de duración 
// ========================================================================= 
// Este bloque observa la señal dut.cache_stall. 
// // Detecta tres casos: 
// 
// 1. Inicio del stall: 
// cache_stall = 1 y antes no estábamos en stall. 
// 
// 2. Stall en progreso: 
// cache_stall = 1 y ya estábamos en stall. 
// 
// 3. Fin del stall:
 // cache_stall = 0 y antes estábamos en stall. 
 // 
 // Al finalizar el stall, clasifica el acceso como: 
 // L1 hit, L2 hit o RAM miss. 
// =========================================================================
    always @(posedge clk) begin
        if (!rst) begin


            // ----------------------------------------------------------------- 
            // Caso 1: inicio de un evento de stall 
            // -----------------------------------------------------------------
            if (dut.cache_stall && !in_stall) begin
                // Se marca que ahora estamos dentro de un stall.
                in_stall       <= 1;

                // El stall empieza contando desde 1 ciclo.
        
                stall_duration <= 1;
            end 
            
            
            // ----------------------------------------------------------------- 
            // Caso 2: stall continúa activo 
            // -----------------------------------------------------------------
            else if (dut.cache_stall && in_stall) begin
               // Mientras cache_stall siga activo, aumenta la duración.
                stall_duration <= stall_duration + 1;
            end 
            
        // ----------------------------------------------------------------- 
        // Caso 3: fin del evento de stall 
        // ---------------------------------------------------------------
            else if (!dut.cache_stall && in_stall) begin
                // Ya no estamos dentro de un stall.
                in_stall <= 0;

                // Se incrementa el número de evento de stall.
                stall_event_num <= stall_event_num + 1;



                // Imprime información del evento de stall recién finalizado.
                // Muestra:
                // - ciclo actual 
                // - número de evento 
                // - duración del stall 
                // - dirección usada en MEM 
                // - clasificación del acceso

                $display("[C%04d] STALL EVENT #%0d: %0d cycles | addr=0x%08h | %s",
                    cycle_count,         // Ciclo actual
                    stall_event_num + 1, // Número visible del evento
                    stall_duration,      // Duración del stall
                    dut.alu_result_mem,  // Dirección de memoria accedida en MEM
                    (stall_duration <= 2)  ? "-> L1 HIT" :
                    (stall_duration <= 20) ? "-> L2 HIT" :
                                             "-> RAM MISS");

// ------------------------------------------------------------- 
// Mapeo esperado de eventos de stall 
// ------------------------------------------------------------- 
// stall_event_num usa el valor ANTES del incremento porque se 
// actualiza con asignación no bloqueante <=. 
// 
// 0 = Primer LOAD a 0x0100 
// Debe ser RAM miss porque la dirección está fría. 
// // 1 = Segundo LOAD a 0x0100 
// Debe ser L1 hit porque ya se cargó en L1. 
// 
// 2 = LOAD a 0x0900 
// Parte del setup para llenar/desalojar L1. 
// 
// 3 = LOAD a 0x1100 
// Parte del setup; debería desalojar 0x0100 de L1. 
// 
// 4 = LOAD final a 0x0100 
// Debe ser L2 hit porque fue desalojado de L1, 
// pero todavía debería estar en L2. 
// -------------------------------------------------------------
                // ------------------------------------------------------------- 
                // Verificación de Fase 1 
                // ------------------------------------------------------------- 
                // Primer acceso a 0x0100. 
                // Se espera RAM miss, por lo tanto el stall debe durar más de 
                // 20 ciclos. 
                // -------------------------------------------------------------
                if (!`BENCH_MODE && stall_event_num == 0) begin
                    if (stall_duration > 20) begin
                        $display("         [PASS] Phase 1 (RAM miss): %0d cycles > 20", stall_duration);
                        pass_count <= pass_count + 1;
                    end else begin
                        $display("         [FAIL] Phase 1: Expected RAM miss (>20 cycles), got %0d",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end
                end

                // ------------------------------------------------------------- 
                // Verificación de Fase 2 
                // ------------------------------------------------------------- 
                // Segundo acceso a 0x0100. 
                // Se espera L1 hit, por lo tanto el stall debe ser de 0 a 2 ciclos. 
                // -------------------------------------------------------------
                if (!`BENCH_MODE && stall_event_num == 1) begin
                    if (stall_duration <= 2) begin
                        $display("         [PASS] Phase 2 (L1 hit): %0d cycles ≤ 2", stall_duration);
                        pass_count <= pass_count + 1;
                    end else begin
                        $display("         [FAIL] Phase 2: Expected L1 hit (≤2 cycles), got %0d",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end
                end

                // ------------------------------------------------------------- 
                // Verificación de Fase 5 
                // ------------------------------------------------------------- 
                // Acceso final a 0x0100 después del desalojo de L1. 
                // Se espera L2 hit. 
                // 
                // Aunque L2 tiene HIT_LATENCY = 8, el overhead de la FSM de L1 
                // puede hacer que el stall observado sea un poco mayor. 
                // 
                // Por eso se acepta un rango entre 3 y 25 ciclos. 
                // -------------------------------------------------------------
                if (!`BENCH_MODE && stall_event_num == 4) begin

                    // Caso esperado: L2 hit.
                    if (stall_duration > 2 && stall_duration <= 25) begin
                        $display("         [PASS] Phase 5 (L2 hit): %0d cycles in [3,25]", stall_duration);
                        pass_count <= pass_count + 1;

                    // Si dura más de 25 ciclos, probablemente llegó hasta RAM.
                    end else if (stall_duration > 25) begin
                        $display("         [FAIL] Phase 5: Expected L2 hit (3-25 cycles), got RAM-level %0d",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end

                    // Si dura 0-2 ciclos, parece que todavía estaba en L1.
                    else begin
                        $display("         [FAIL] Phase 5: Expected L2 hit, got L1-level %0d cycles",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end
                end

                // Probando con Instruccion STORE. 
                // -------------------------------------------------------------
                // Verificación de Fase S1
                // -------------------------------------------------------------
                // Primer STORE a 0x0200 — dirección fría, va hasta RAM.
                // Se espera un stall largo (>20 ciclos).
                // -------------------------------------------------------------
                if (!`BENCH_MODE && stall_event_num == 5) begin
                    if (stall_duration > 20) begin
                        $display("         [PASS] Phase S1 (STORE RAM miss): %0d cycles > 20", stall_duration);
                        pass_count <= pass_count + 1;
                    end else begin
                        $display("         [FAIL] Phase S1: Expected STORE RAM miss (>20 cycles), got %0d",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end
                end

                // -------------------------------------------------------------
                // Verificación de Fase S2
                // -------------------------------------------------------------
                // LOAD desde 0x0200 inmediatamente después del STORE.
                // El bloque ya debe estar en L1, se espera hit corto (0-2 ciclos).
                // La coherencia (R10 == 0xAB) se verifica al llegar a HALT.
                // -------------------------------------------------------------
                if (!`BENCH_MODE && stall_event_num == 6) begin
                    if (stall_duration <= 2) begin
                        $display("         [PASS] Phase S2 (LOAD after STORE, L1 hit): %0d cycles", stall_duration);
                        pass_count <= pass_count + 1;
                    end else begin
                        $display("         [FAIL] Phase S2: Expected L1 hit after STORE (<=2 cycles), got %0d",
                            stall_duration);
                        fail_count <= fail_count + 1;
                    end
                end
            end
        end
    end

// =========================================================================
// Traza por ciclo 
// ========================================================================= 
// Este bloque imprime información útil durante la simulación. 
// // Imprime cuando: 
// - el ciclo es menor a 15, 
// - hay cache_stall activo, 
// - el procesador ya hizo HALT. 
// 
// Esto evita imprimir todos los ciclos y mantiene la salida más manejable. 
// =========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            if (cycle_count < 15 || dut.cache_stall || dut.halted) begin
                $display("[C%04d] PC=%08h | cache_stall=%b | mem_r=%b mem_w=%b | addr=%08h | R1=%08h R3=%08h",
                    cycle_count,
                    dut.pc_out,
                    dut.cache_stall,
                    dut.mem_read_mem,
                    dut.mem_write_mem,
                    dut.alu_result_mem,
                    dut.rf.regs[1],
                    dut.rf.regs[3]);
            end
        end
    end

// ========================================================================= 
// Detección de HALT y reporte final 
// ========================================================================= 
// Cuando el programa ejecutado por datapathv3 llega a HALT, 
// este bloque imprime el resumen final de la prueba. 
// =========================================================================
    always @(posedge clk) begin
        if (!rst && dut.halted && !halt_reported) begin
            halt_reported <= 1; // Bloquea re-disparos: halted se mantiene alto cada ciclo

            // Encabezado del reporte final.
            $display("");
            $display("====================================================================");
            $display("  PROGRAM HALTED - Cycle %0d", cycle_count);
            $display("  Benchmark: %s", benchmark_title());
            $display("====================================================================");
            $display("");


            // ----------------------------------------------------------------- 
            // Reporte de contadores de caché 
            // ----------------------------------------------------------------- 
            // Estos contadores vienen desde cache_hierarchy dentro del datapath. 
            // Sirven para validar cuántos accesos fueron hits o misses. 
            // -----------------------------------------------------------------
            $display("--- Cache Performance Counters ---");
            $display("  L1 read  hits:    %0d", dut.l1_read_hits);
            $display("  L1 read  misses:  %0d", dut.l1_read_misses);
            $display("  L1 write hits:    %0d", dut.l1_write_hits);
            $display("  L1 write misses:  %0d", dut.l1_write_misses);
            $display("  L2 read  hits:    %0d", dut.l2_read_hits);
            $display("  L2 read  misses:  %0d", dut.l2_read_misses);
            $display("  L2 write hits:    %0d", dut.l2_write_hits);
            $display("  L2 write misses:  %0d", dut.l2_write_misses);
            $display("  RAM accesses:     %0d", dut.mem_accesses);
            $display("  RAM busy cycles:  %0d", dut.mem_cycles);
            $display("");

            // ----------------------------------------------------------------- 
            // Reporte de rendimiento del pipeline 
            // ----------------------------------------------------------------- 
            // Estos contadores permiten ver el impacto de la caché en el pipeline. 
            // -----------------------------------------------------------------
            $display("--- Pipeline Performance ---");
            $display("  Total cycles:         %0d", dut.perf_cycle_count);
            $display("  Instructions retired: %0d", dut.perf_instr_count);
            $display("  Cache stall cycles:   %0d", dut.perf_cache_stall_cycles);
            $display("    - L1 miss stalls:   %0d", dut.perf_stall_l1miss_cycles);
            $display("    - L2 miss stalls:   %0d", dut.perf_stall_l2miss_cycles);
            $display("  Branch stall cycles:  %0d", dut.perf_branch_stalls);
            $display("  Load-use stalls:      %0d", dut.perf_load_use_stalls);
            $display("");

            // -----------------------------------------------------------------
            // Metricas derivadas (calculadas dentro de perf_counters)
            // -----------------------------------------------------------------
            $display("--- Derived Metrics (x1000) ---");
            $display("  IPC x1000:            %0d", dut.perf_ipc_x1000);
            $display("  L1 hit rate x1000:    %0d", dut.perf_l1_hit_rate_x1000);
            $display("  L1 miss rate x1000:   %0d", dut.perf_l1_miss_rate_x1000);
            $display("  L2 hit rate x1000:    %0d", dut.perf_l2_hit_rate_x1000);
            $display("  L2 miss rate x1000:   %0d", dut.perf_l2_miss_rate_x1000);
            $display("  AMAT x1000:           %0d", dut.perf_amat_x1000);
            $display("");

            // Valor real con 3 decimales
            $display("--- Derived Metrics (real) ---");
            $display("  IPC:                  %0d.%03d", dut.perf_ipc_x1000/1000, dut.perf_ipc_x1000%1000);
            $display("  L1 hit rate:          %0d.%03d%%", dut.perf_l1_hit_rate_x1000/10, dut.perf_l1_hit_rate_x1000%10*100);
            $display("  L1 miss rate:         %0d.%03d%%", dut.perf_l1_miss_rate_x1000/10, dut.perf_l1_miss_rate_x1000%10*100);
            $display("  L2 hit rate:          %0d.%03d%%", dut.perf_l2_hit_rate_x1000/10, dut.perf_l2_hit_rate_x1000%10*100);
            $display("  L2 miss rate:         %0d.%03d%%", dut.perf_l2_miss_rate_x1000/10, dut.perf_l2_miss_rate_x1000%10*100);
            $display("  AMAT (cycles):        %0d.%03d", dut.perf_amat_x1000/1000, dut.perf_amat_x1000%1000);
            $display("");


            // ----------------------------------------------------------------- 
            // Resultado general del test 
            // -----------------------------------------------------------------
            
            $display("--- Test Result ---");
            $display("  PASS: %0d / FAIL: %0d", pass_count, fail_count);

            if (`BENCH_MODE)
                $display("  BENCH MODE: aserciones de fases fijas deshabilitadas");


            // Si no hubo fallos y al menos una aserción se ejecutó, 
            // se considera que todas las pruebas pasaron.
            if (fail_count == 0 && pass_count > 0)
                $display("  ALL TESTS PASSED");

            // Si hubo al menos un fallo, se reporta error.
            else if (fail_count > 0)
                $display("  SOME TESTS FAILED");


            // Si no se ejecutó ninguna verificación, puede que no hayan ocurrido 
            // los eventos de stall esperados.
            else
                $display("  WARNING: no assertions triggered - check stall events");

            $display("====================================================================");

           // ----------------------------------------------------------------- 
           // Estado final de registros 
           // ----------------------------------------------------------------- 
           // Se imprimen algunos registros para revisar si los LOAD escribieron 
           // correctamente sus resultados. 
           // -----------------------------------------------------------------
            $display("");
            $display("--- Final Register State ---");
            $display("  R0=%08h  R1=%08h  R2=%08h  R3=%08h",
                dut.rf.regs[0], dut.rf.regs[1],
                dut.rf.regs[2], dut.rf.regs[3]);
            $display("  R4=%08h  R5=%08h  R6=%08h  R7=%08h",
                dut.rf.regs[4], dut.rf.regs[5],
                dut.rf.regs[6], dut.rf.regs[7]);
            $display("  R8=%08h  R9=%08h  R10=%08h",
                dut.rf.regs[8], dut.rf.regs[9], dut.rf.regs[10]);
            $display("");

            // -----------------------------------------------------------------
            // Verificación de coherencia STORE → LOAD
            // -----------------------------------------------------------------
            // R9 = 0xAB fue guardado en mem[0x0200] (Fase S1).
            // R10 = LOAD de mem[0x0200] (Fase S2).
            // Si R10 == 0xAB la jerarquía de caché mantiene coherencia de escritura.
            // -----------------------------------------------------------------
            $display("--- Write-then-Read Coherence ---");
            if (`BENCH_MODE) begin
                $display("  [INFO] Coherencia STORE->LOAD omitida en modo benchmark.");
            end else if (dut.rf.regs[10] == 32'h000000AB)
                $display("  [PASS] R10 = 0x000000AB, coherencia OK (STORE->LOAD correcto)");
            else
                $display("  [FAIL] R10 = %08h — esperado 000000AB (fallo de coherencia)",
                    dut.rf.regs[10]);

            // Espera 20 ns para que se impriman los últimos mensajes.
            if (csv_fd != 0) begin
                $fclose(csv_fd);
                csv_fd = 0;
            end

            #20;
            $finish;
        end
    end

// =========================================================================
// Monitor de Writeback
// =========================================================================
// Este bloque imprime cada vez que el banco de registros escribe un valor.
//
// Se ejecuta en flanco negativo para observar el resultado después del
// flanco positivo donde pudo ocurrir la escritura.
//
// No imprime escrituras a R0 porque normalmente R0 se mantiene en cero.
// =========================================================================

    always @(negedge clk) begin
        if (!rst && dut.rf.write_en && dut.rf.rd != 4'd0) begin
            $display("[C%04d-WB] R%0d <= %08h", cycle_count, dut.rf.rd, dut.rf.WD3);
        end
    end

// =========================================================================
// Monitor de STORE
// =========================================================================
// Imprime cada vez que un STORE completa su escritura en la etapa MEM.
// Detecta ambos casos:
//   - STORE hit  (cache_stall=0 en el ciclo de escritura)
//   - STORE miss (cache_stall cae a 0 tras resolver el miss)
//
// Verifica que el dato y la dirección sean los esperados para la Fase S1/S3:
//   addr esperada = 0x00000200
//   dato esperado = 0x000000AB  (R9 = ADDI R9, R0, 0xAB)
// =========================================================================
    always @(posedge clk) begin
        if (!rst && dut.mem_write_mem && !dut.cache_stall) begin
            if (dut.alu_result_mem == 32'h00000200 && dut.write_data_mem == 32'h000000AB)
                $display("[C%04d-ST] STORE: addr=0x%08h | dato=0x%08h | [PASS] escritura correcta",
                    cycle_count, dut.alu_result_mem, dut.write_data_mem);
            else
                $display("[C%04d-ST] STORE: addr=0x%08h | dato=0x%08h | [FAIL] dato o direccion inesperados",
                    cycle_count, dut.alu_result_mem, dut.write_data_mem);
        end
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    // Este bloque evita que la simulación quede corriendo para siempre. 
    // 
    // Si el programa no llega a HALT antes del tiempo límite, se imprime TIMEOUT 
    // y se finaliza la simulación. 
    // 
    // 5_000_000 ns equivalen a 5 ms. 
    // Con reloj de 100 MHz, eso representa aproximadamente 500,000 ciclos. 
    // =========================================================================
    
    initial begin
        // Tiempo máximo permitido para la simulación.
        #5_000_000; // 500,000 CPU cycles at 100 MHz = 5 ms
        // Si se llega aquí, el programa no terminó a tiempo.
        $display("TIMEOUT at cycle %0d", cycle_count);
        // Imprime señales útiles para diagnosticar el problema.
        $display("  cache_stall=%b  halted=%b", dut.cache_stall, dut.halted);
        // Finaliza la simulación por timeout.
        $finish;
    end

endmodule
