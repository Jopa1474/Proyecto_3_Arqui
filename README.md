# TEA-ISA — Procesador RISC Seguro con Jerarquía de Caché

Procesador RISC de 23 bits con pipeline de 5 etapas, jerarquía de caché de dos niveles (L1 + L2), controlador de memoria realista y contadores de métricas de rendimiento. Implementado en SystemVerilog y simulado con Icarus Verilog.

Proyecto Grupal II — CE4301 Arquitectura de Computadores I · I Semestre 2026

---

## Descripción General

**TEA-ISA** es una arquitectura tipo RISC diseñada para aplicaciones de seguridad en hardware. Este proyecto extiende el procesador del Proyecto Grupal I incorporando:

- **Pipeline de 5 etapas** (IF → ID → EX → MEM → WB) con forwarding completo y detección de hazards
- **Jerarquía de caché de datos de dos niveles**: L1 (4 KB, 2-way) y L2 (16 KB, 4-way)
- **Controlador de memoria realista** con latencia de 25 ciclos y soporte burst de 8 palabras
- **Contadores de métricas de rendimiento** integrados en hardware (IPC, hit rates, AMAT, stalls)
- **Instrucciones TEA** (`TEA_ADD1`, `TEA_ADD2`) para aceleración criptográfica
- **Bóveda de llaves** (Key Vault): 4 × 128 bits con control de acceso por sesión
- **Instrucción de 23 bits**, datos de 32 bits, 16 registros de propósito general (R0–R15)

---

## Especificaciones del Sistema

| Componente | Parámetro | Valor |
|---|---|---|
| **Pipeline** | Etapas | 5 (IF, ID, EX, MEM, WB) |
| **Caché L1** | Tamaño / Asociatividad | 4 KB / 2-way Set-Associative |
| | Política reemplazo / escritura | LRU / Write-Back |
| | Latencia hit | 2–3 ciclos |
| **Caché L2** | Tamaño / Asociatividad | 16 KB / 4-way Set-Associative |
| | Política reemplazo / escritura | Pseudo-LRU / Write-Back + Write Buffer |
| | Latencia hit | 8 ciclos |
| **Memoria Principal** | Tamaño / Latencia | 64 KB / 25 ciclos CPU |
| | Burst / Reloj | 8 palabras / 50 MHz (CPU ÷ 2) |
| **ROM Instrucciones** | Tamaño / Acceso | 64 KB / 1 ciclo (sin stalls) |

---

## Dependencias

| Herramienta | Versión mínima | Instalación (Ubuntu/Debian) |
|---|---|---|
| [Icarus Verilog](https://steveicarus.github.io/iverilog/) | 11.0 | `sudo apt install iverilog` |
| [GTKWave](http://gtkwave.sourceforge.net/) | 3.3 | `sudo apt install gtkwave` |
| Python 3 | 3.8+ | `sudo apt install python3` |
| matplotlib / pandas | — | `pip install matplotlib pandas` |
| Make | cualquiera | `sudo apt install make` |

Verificar instalación:

```bash
iverilog -V
gtkwave --version
python3 --version
```

---

## Estructura del Proyecto

```
Proyecto_3_Arqui/
├── Makefile
├── README.md
│
├── src/                          # Módulos SystemVerilog
│   │
│   ├── — Datapaths (top-level) —
│   ├── datapath.sv               # v1: Pipeline base (Proyecto I, sin caché)
│   ├── datapathv2.sv             # v2: Pipeline + memoria realista + métricas
│   ├── datapathv3.sv             # v3: Pipeline + jerarquía de caché completa ← sistema extendido
│   │
│   ├── — Jerarquía de Memoria —
│   ├── cache_hierarchy.sv        # Integrador L1 + L2 + Memoria Principal
│   ├── cache_l1.sv               # Caché L1: 4 KB, 2-way, LRU, Write-Back
│   ├── cache_l2.sv               # Caché L2: 16 KB, 4-way, Pseudo-LRU, Write-Back
│   ├── data_memoryv2.sv          # Controlador de memoria: FSM, 25 ciclos, burst 8w
│   ├── data_memory.sv            # Memoria simple (baseline sin latencia)
│   ├── inst_mem.sv               # ROM de instrucciones (64 KB, 1 ciclo)
│   │
│   ├── — Métricas —
│   ├── perf_counters.sv          # IPC, hit/miss rates L1/L2, AMAT, stall cycles
│   ├── sic_counter.sv            # Session Instruction Counter (seguridad)
│   │
│   ├── — Pipeline —
│   ├── if_id_reg.sv              # Registro IF/ID
│   ├── id_ex_reg.sv              # Registro ID/EX
│   ├── ex_mem_reg.sv             # Registro EX/MEM
│   ├── mem_wb_reg.sv             # Registro MEM/WB
│   ├── hazard_detection.sv       # Stall / flush / forwarding control
│   ├── fwd_logic.sv              # Lógica de forwarding EX
│   ├── branch_compare.sv         # Evaluador de branch en ID
│   │
│   ├── — Unidades Funcionales —
│   ├── alu.sv                    # ALU: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/LLI
│   ├── alu_v.sv                  # ALU criptográfica: TEA_ADD1 / TEA_ADD2
│   ├── control_unit.sv           # Decodificador y generador de señales de control
│   ├── reg_file.sv               # Banco de registros 16 × 32-bit
│   ├── program_counter.sv        # PC de 32 bits
│   ├── imm_gen.sv                # Generador de inmediatos (sign-extension)
│   ├── adder.sv                  # Sumador paramétrico (PC+4, branch target)
│   ├── mux2.sv / mux4.sv        # Multiplexores 2:1 y 4:1
│   │
│   └── — Seguridad —
│       ├── auth_unit.sv          # Unidad de autenticación y gestión de sesión
│       └── key_vault.sv          # Bóveda de llaves: 4 × 128 bits
│
├── testbenches/                  # Testbenches de verificación
│   ├── — Sistema Completo —
│   ├── datapath_tb.sv            # Pipeline base (v1)
│   ├── datapathv2_perf_tb.sv     # Pipeline + memoria realista (v2)
│   ├── pipeline_cache_tb.sv      # Pipeline + jerarquía de caché (v3) ← principal
│   ├── datapath_benchmark_tb.sv  # Benchmark sin caché (baseline)
│   │
│   ├── — Caché y Memoria —
│   ├── cache_l1_tb.sv
│   ├── cache_l2_tb.sv
│   ├── data_memoryv2_tb.sv
│   ├── perf_counters_tb.sv
│   │
│   ├── — Módulos Individuales —
│   ├── alu_tb.sv / alu_v_tb.sv
│   ├── auth_unit_tb.sv / key_vault_tb.sv
│   ├── branch_compare_tb.sv / fwd_logic_tb.sv
│   ├── hazard_detection_tb.sv
│   ├── data_memory_tb.sv / data_memory_dump_tb.sv
│   └── [un testbench por cada módulo restante]
│
│   └── benchmarks/               # Programas de benchmark en ensamblador
│       ├── benchmark_1_sequential.asm   # Acceso secuencial a memoria
│       ├── benchmark_2_stride.asm       # Acceso con stride
│       ├── benchmark_3_random.asm       # Acceso aleatorio
│       └── benchmark_4_thousands.asm    # 2000+ accesos a memoria
│
├── mem/                          # Archivos de inicialización de memoria (.mem)
│   ├── instructions.mem          # Programa principal
│   ├── mem_init.mem              # Datos iniciales de memoria
│   ├── cifrado_test.mem          # Test de cifrado TEA
│   ├── descifrado_test.mem       # Test de descifrado TEA
│   └── benchmarks/               # Binarios compilados de benchmarks
│
├── tools/                        # Herramientas Python
│   ├── asm_to_mem.py                        # Ensamblador: .asm → .mem
│   ├── load_file.py                         # Carga archivo arbitrario en mem_init.mem
│   ├── extract_data.py                      # Extrae bytes desde un .mem
│   ├── plot_cache_behavior.py               # Gráficas de comportamiento de caché
│   ├── plot_benchmark_summary_table.py      # Tabla resumen de métricas (con caché)
│   ├── plot_baseline_benchmark_summary_table.py  # Tabla resumen (sin caché)
│   ├── plot_benchmark_comparison.py         # Comparativa entre benchmarks
│   └── plot_cache_vs_nocache_comparison.py  # Caché vs. sin caché
│
├── sim/                          # Salidas de simulación (generado)
│   ├── *.vvp / *.vcd            # Binarios y waveforms
│   ├── *.csv                    # Datos de métricas exportados
│   └── plots/                   # Gráficas generadas
│
└── docs/                         # Documentación
    ├── isa.md                    # Especificación completa del ISA
    ├── microarquitecture.md      # Descripción original de microarquitectura
    ├── diagramas_microarquitectura.md  # Diagramas de bloques del sistema extendido
    └── simulation.md             # Guía de simulación
```

---

## Compilación y Ejecución

### Usando Make (recomendado)

```bash
make setup    # Crea carpeta sim/
make all      # Ejecuta todas las simulaciones base (v1)
```

#### Iteración 1 — Pipeline Base (sin caché)

```bash
make datapath       # Sistema completo v1
make alu            # ALU estándar
make memory         # Memoria de datos simple
make branches       # Saltos condicionales
make tea            # Operaciones TEA
make vault          # Bóveda de llaves y autenticación
make file_crypto    # Cifrado/descifrado desde archivo
```

#### Iteración 2 — Memoria Principal Realista

```bash
make memoryv2       # Controlador de memoria (FSM, 25 ciclos, burst)
make datapathv2     # Pipeline + memoria realista + contadores de métricas
```

#### Iteración 3 — Caché L1

```bash
make cache_l1       # Caché L1 standalone
make perf_counters  # Módulo de contadores de métricas
```

#### Iteración 4 — Sistema Completo con Jerarquía de Caché

```bash
make pipeline_cache   # Pipeline + L1 + L2 + Memoria Principal
```

#### Benchmarks y Análisis de Rendimiento

```bash
# Compilar benchmarks (.asm → .mem)
make benchmarks-asm

# Ejecutar y graficar benchmark individual (con caché)
make pipeline_cache_program \
  PROGRAM_FILE=mem/benchmarks/benchmark_1_sequential.mem \
  CACHE_CSV_FILE=sim/cache_timeline_b1.csv \
  BENCH_ID=1

# Ejecutar y graficar todos los benchmarks con caché
make plots-benchmarks

# Ejecutar todos los benchmarks sin caché (baseline)
make plots-benchmarks-nocache

# Comparativa entre benchmarks con caché
make plots-benchmark-comparison

# Comparativa caché vs. sin caché
make plots-cache-vs-nocache-comparison
```

#### Ver Waveforms

```bash
make wave-datapath        # Pipeline base
make wave-datapathv2      # Pipeline + memoria realista
make wave-pipeline_cache  # Sistema completo con caché
make wave-memoryv2        # Controlador de memoria
make wave-cache_l1        # Caché L1
make wave-alu             # ALU
make wave-tea             # ALU criptográfica
make wave-vault           # Bóveda de llaves
```

#### Limpieza

```bash
make clean    # Elimina todos los archivos generados en sim/
```

---

### Compilación Manual con iverilog

```bash
# Sistema completo con caché (v3)
iverilog -g2012 -o sim/pipeline_cache_tb.vvp \
  src/adder.sv src/alu.sv src/alu_v.sv src/auth_unit.sv \
  src/branch_compare.sv src/control_unit.sv src/data_memoryv2.sv \
  src/ex_mem_reg.sv src/fwd_logic.sv src/hazard_detection.sv \
  src/id_ex_reg.sv src/if_id_reg.sv src/imm_gen.sv src/inst_mem.sv \
  src/key_vault.sv src/mem_wb_reg.sv src/mux2.sv src/mux4.sv \
  src/program_counter.sv src/reg_file.sv src/sic_counter.sv \
  src/perf_counters.sv src/cache_l1.sv src/cache_l2.sv \
  src/cache_hierarchy.sv src/datapathv3.sv \
  testbenches/pipeline_cache_tb.sv
vvp sim/pipeline_cache_tb.vvp

# Pipeline base (v1)
iverilog -g2012 -o sim/datapath_tb.vvp src/*.sv testbenches/datapath_tb.sv
vvp sim/datapath_tb.vvp
```

---

## Métricas de Rendimiento

El módulo `perf_counters` calcula en tiempo de simulación:

| Métrica | Descripción |
|---|---|
| `total_cycles` | Ciclos totales de ejecución |
| `instructions_completed` | Instrucciones completadas por el pipeline |
| `ipc_x1000` | IPC × 1000 (instrucciones por ciclo) |
| `l1_hit_rate_x1000` | Tasa de acierto L1 × 1000 |
| `l2_hit_rate_x1000` | Tasa de acierto L2 × 1000 |
| `amat_x1000` | Tiempo promedio de acceso a memoria × 1000 (ciclos) |
| `stall_cycles_l1miss` | Ciclos perdidos por miss en L1 |
| `stall_cycles_l2miss` | Ciclos perdidos por miss en L2 |
| `stall_cycles_control` | Ciclos perdidos por hazards de control |

> Los valores ×1000 permiten representar fracciones sin punto flotante en hardware.

**Fórmula AMAT:**
```
AMAT = 1 + MissRate_L1 × (8 + MissRate_L2 × 33)  [ciclos]
```

---

## Benchmarks Incluidos

| Benchmark | Patrón de Acceso | Propósito |
|---|---|---|
| `benchmark_1_sequential` | Secuencial | Alta localidad espacial, máxima tasa de acierto L1 |
| `benchmark_2_stride` | Stride fijo | Localidad media, evalúa eficiencia de líneas de caché |
| `benchmark_3_random` | Aleatorio | Baja localidad, máxima tasa de miss |
| `benchmark_4_thousands` | 2000+ accesos | Estrés de la jerarquía completa |

Los resultados se exportan a CSV en `sim/` y las gráficas se generan en `sim/plots/`.

---

## Herramientas Python

### `asm_to_mem.py` — Ensamblar programas

Convierte código ensamblador TEA-ISA a formato `.mem` para inicializar `inst_mem`.

```bash
python3 tools/asm_to_mem.py --input testbenches/benchmarks/benchmark_1_sequential.asm \
                             --output mem/benchmarks/benchmark_1_sequential.mem
```

### `load_file.py` — Cargar archivo en memoria de datos

Convierte cualquier archivo a formato `.mem` (hex, little-endian, word-aligned).

```bash
python3 tools/load_file.py --input archivo.bin --output mem/archivo.mem --address 0x1000
```

### `extract_data.py` — Extraer datos post-simulación

```bash
python3 tools/extract_data.py --memory mem/archivo.mem --address 0x1000 --size 64 --output resultado.bin
```

### `plot_cache_behavior.py` — Visualizar comportamiento de caché

Genera gráficas de hits/misses, stalls, e IPC a lo largo del tiempo de simulación.

```bash
python3 tools/plot_cache_behavior.py --input sim/cache_timeline.csv --outdir sim/plots
```

### `plot_cache_vs_nocache_comparison.py` — Comparativa caché vs. baseline

Compara métricas de rendimiento entre el sistema con caché y el sistema sin caché.

```bash
python3 tools/plot_cache_vs_nocache_comparison.py --input-dir sim --outdir sim/plots/comparison
```

---

## Documentación

La documentación completa se encuentra en `docs/`:

| Archivo | Contenido |
|---|---|
| `isa.md` | Especificación completa del ISA TEA-ISA (23-bit) |
| `diagramas_microarquitectura.md` | Diagramas de bloques del sistema extendido, pipeline, jerarquía de caché, FSM del controlador, contadores de métricas y flujo de datos |
| `performance-analysis.md` | Análisis de rendimiento y validación: metodología, resultados por benchmark, comparación caché vs. sin caché y conclusiones |
| `microarquitecture.md` | Descripción original de microarquitectura (Proyecto I) |
| `simulation.md` | Guía detallada de simulación con Icarus Verilog |

---

## Análisis de Rendimiento y Validación

### Metodología de Medición

Se compara el comportamiento del procesador en dos configuraciones:

1. **Con caché:** `datapathv3` con jerarquía L1/L2 y memoria principal realista.
2. **Sin caché:** `datapath` legacy original con acceso directo a memoria de datos simple.

Para cada configuración se ejecutaron los mismos 4 benchmarks ensamblados a `.mem` y se exportaron las métricas a CSV:

- Con caché: `sim/cache_timeline_benchmark_*.csv`
- Sin caché: `sim/nocache_timeline_benchmark_*.csv`

Las métricas analizadas fueron: ciclos totales, instrucciones completadas, IPC, accesos a memoria, stalls, hit/miss rates y AMAT (solo con caché).

---

### Benchmarks Utilizados

| # | Nombre | Patrón | Objetivo |
|---|---|---|---|
| 1 | Sequential | Accesos contiguos | Medir localidad espacial/temporal |
| 2 | Stride | Accesos con salto fijo | Forzar patrones menos amigables para caché |
| 3 | Random | Direcciones dispersas | Evaluar comportamiento ante baja localidad |
| 4 | Thousands | 2000+ accesos | Estresar la jerarquía completa en ejecución larga |

---

### Resultados por Benchmark

#### Benchmark 1 — Sequential

- **Con caché:** 1048 ciclos · IPC 0.309 · 64 accesos L1 · 8 accesos a RAM · L1 hit rate 87.5% · AMAT 6.125 ciclos
- **Sin caché:** 519 ciclos · IPC 0.624 · 64 accesos de memoria

El patrón secuencial logra un alto hit rate de 87.5% en L1. Sin embargo, la configuración con caché resulta más lenta en ciclos totales porque cada miss penaliza fuertemente dado el alto costo de la memoria principal realista (25 ciclos de latencia).

---

#### Benchmark 2 — Stride

- **Con caché:** 16514 ciclos · IPC 0.121 · 400 accesos L1 · 250 accesos a RAM · L1 hit rate 37.5% · AMAT 26.625 ciclos
- **Sin caché:** 3212 ciclos · IPC 0.625 · 400 accesos de memoria

El patrón stride genera gran cantidad de misses en L1. El AMAT sube de forma significativa y domina el costo total de ejecución. Es el caso donde la diferencia de ciclos entre ambas configuraciones es más marcada.

---

#### Benchmark 3 — Random

- **Con caché:** 15232 ciclos · IPC 0.630 · 800 accesos L1 · 32 accesos a RAM · L1 hit rate 96.0% · AMAT 2.640 ciclos
- **Sin caché:** 12014 ciclos · IPC 0.799 · 800 accesos de memoria

La caché muestra un 96% de hits en L1, reduciendo la diferencia respecto a la configuración sin caché. Aunque el patrón es "aleatorio", la reutilización de líneas cargadas explica el alto hit rate.

---

#### Benchmark 4 — Thousands

- **Con caché:** 32510 ciclos · IPC 0.307 · 2000 accesos L1 · 250 accesos a RAM · L1 hit rate 87.5% · AMAT 6.125 ciclos
- **Sin caché:** 16008 ciclos · IPC 0.625 · 2000 accesos de memoria

Confirma el comportamiento del benchmark secuencial bajo carga prolongada. La caché mantiene un buen hit rate con 2000 accesos, pero los misses acumulados siguen impactando por la latencia de la memoria principal.

---

### Comparación Global: Caché vs. Sin Caché

| Benchmark | Ciclos sin caché | Ciclos con caché | Relación (sin/con) | Observación |
|---|---:|---:|---:|---|
| B1 Sequential | 519 | 1048 | 0.495× | Sin caché más rápido |
| B2 Stride | 3212 | 16514 | 0.194× | Diferencia más marcada |
| B3 Random | 12014 | 15232 | 0.789× | Diferencia moderada |
| B4 Thousands | 16008 | 32510 | 0.492× | Sin caché más rápido |

> Una relación menor a 1 indica que la configuración sin caché termina en menos ciclos.

#### Interpretación Técnica

La comparación refleja dos configuraciones de memoria fundamentalmente distintas:

- **Con caché:** L1/L2 conectados a memoria principal realista con 25 ciclos de latencia. Cada miss tiene un costo elevado que puede dominar el tiempo total de ejecución.
- **Sin caché:** Memoria de datos simple del `datapath` legacy (Proyecto I) sin jerarquía. Menor costo efectivo por acceso en las simulaciones.

Los resultados validan:
1. El impacto de la latencia realista cuando ocurren misses.
2. La sensibilidad de cada benchmark al patrón de acceso a memoria.
3. Que una caché no mejora el tiempo total si el costo de miss y la microarquitectura no están balanceados para el workload.

---

### Validación Experimental

- Se ejecutó el mismo conjunto de 4 benchmarks en ambas configuraciones.
- Los resultados de tablas y gráficas son coherentes entre sí: benchmarks con peor localidad (stride) generan mayor cantidad de misses y peor AMAT; benchmarks con mejor localidad (random) mejoran el hit rate y reducen el costo.
- Los contadores de hardware (`perf_counters`) reportan valores consistentes con los tiempos de latencia definidos en el diseño (`SINGLE_LATENCY=25`, `HIT_LATENCY=8`).

---

### Conclusiones

1. El comportamiento con caché depende críticamente del patrón de acceso y del costo de los misses.
2. En esta implementación, la configuración sin caché es más rápida en ciclos para los 4 benchmarks medidos, debido a la alta penalización de la memoria principal realista.
3. La caché sí demuestra utilidad: alcanza hasta 96% de hit rate (B3) y reduce el AMAT cuando la localidad es alta.
4. Para futuras iteraciones se podría optimizar la ruta de misses (superposición de trabajo, menor latencia efectiva, política de prefetch) para capturar mejor los beneficios esperados de la jerarquía de caché.
