# Makefile para TEA-ISA

PYTHON ?= C:/msys64/mingw64/bin/python.exe
BENCH_DIR ?= testbenches/benchmarks
BENCH_MEM_DIR ?= mem/benchmarks
BENCH_ID ?= 0

.PHONY: all setup alu memory branches tea vault file_crypto datapath wave-alu wave-memory wave-branches wave-tea wave-vault wave-file_crypto clean

all: setup alu memory branches tea vault file_crypto datapath

setup:
	mkdir -p sim

# Operaciones básicas de ALU
alu: setup
	iverilog -g2012 -o sim/alu_tb.vvp src/alu.sv testbenches/alu_tb.sv
	vvp sim/alu_tb.vvp

# Acceso a memoria
memory: setup
	iverilog -g2012 -o sim/data_memory_tb.vvp src/data_memory.sv testbenches/data_memory_tb.sv
	vvp sim/data_memory_tb.vvp

# Saltos condicionales e incondicionales
branches: setup
	iverilog -g2012 -o sim/branch_compare_tb.vvp src/branch_compare.sv testbenches/branch_compare_tb.sv
	vvp sim/branch_compare_tb.vvp

	iverilog -g2012 -o sim/program_counter_tb.vvp src/program_counter.sv testbenches/program_counter_tb.sv
	vvp sim/program_counter_tb.vvp

# Operaciones de cifrado TEA
tea: setup
	iverilog -g2012 -o sim/alu_v_tb.vvp src/alu_v.sv testbenches/alu_v_tb.sv
	vvp sim/alu_v_tb.vvp

# Manejo de bóveda de llaves
vault: setup
	iverilog -g2012 -o sim/key_vault_tb.vvp src/key_vault.sv testbenches/key_vault_tb.sv
	vvp sim/key_vault_tb.vvp

	iverilog -g2012 -o sim/auth_unit_tb.vvp src/auth_unit.sv src/sic_counter.sv testbenches/auth_unit_tb.sv
	vvp sim/auth_unit_tb.vvp

# Cifrado/descifrado de archivo cargado en memoria
file_crypto: setup
	iverilog -g2012 -o sim/data_memory_dump_tb.vvp src/data_memory.sv testbenches/data_memory_dump_tb.sv
	vvp sim/data_memory_dump_tb.vvp

# Sistema completo
LEGACY_DATAPATH_SRCS = src/adder.sv src/alu.sv src/alu_v.sv src/auth_unit.sv \
			 src/branch_compare.sv src/control_unit.sv src/data_memory.sv \
			 src/ex_mem_reg.sv src/fwd_logic.sv src/hazard_detection.sv \
			 src/id_ex_reg.sv src/if_id_reg.sv src/imm_gen.sv src/inst_mem.sv \
			 src/key_vault.sv src/mem_wb_reg.sv src/mux2.sv src/mux4.sv \
			 src/pipe_reg.sv src/program_counter.sv src/reg_file.sv \
			 src/sic_counter.sv src/datapath.sv

datapath: setup
	iverilog -g2012 -o sim/datapath_tb.vvp $(LEGACY_DATAPATH_SRCS) testbenches/datapath_tb.sv
	vvp sim/datapath_tb.vvp > /dev/null

datapath_benchmark_program: setup
	iverilog -g2012 -DPROGRAM_FILE='"$(PROGRAM_FILE)"' -DBASELINE_CSV_FILE='"$(BASELINE_CSV_FILE)"' -DBENCH_ID=$(BENCH_ID) -o sim/datapath_benchmark_tb.vvp \
		$(LEGACY_DATAPATH_SRCS) testbenches/datapath_benchmark_tb.sv
	vvp sim/datapath_benchmark_tb.vvp

# Abrir VCD en GTKWave
wave-alu:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/alu_tb.vcd

wave-memory:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/data_memory_tb.vcd

wave-branches:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/branch_compare_tb.vcd

wave-tea:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/alu_v_tb.vcd

wave-vault:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/key_vault_tb.vcd

wave-file_crypto:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/data_memory_dump_tb.vcd

wave-datapath:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/datapath_tb.vcd

# =============================================================================
# Iteration 2 — Realistic Main Memory
# =============================================================================

# Unit test for data_memoryv2 (standalone)
memoryv2: setup
	iverilog -g2012 -o sim/data_memoryv2_tb.vvp src/data_memoryv2.sv testbenches/data_memoryv2_tb.sv
	vvp sim/data_memoryv2_tb.vvp

# Full system with realistic memory + performance counters
datapathv2: setup
	iverilog -g2012 -o sim/datapathv2_perf_tb.vvp \
		src/adder.sv src/alu.sv src/alu_v.sv src/auth_unit.sv src/branch_compare.sv \
		src/control_unit.sv src/data_memoryv2.sv src/ex_mem_reg.sv src/fwd_logic.sv \
		src/hazard_detection.sv src/id_ex_reg.sv src/if_id_reg.sv src/imm_gen.sv \
		src/inst_mem.sv src/key_vault.sv src/mem_wb_reg.sv src/mux2.sv src/mux4.sv \
		src/pipe_reg.sv src/program_counter.sv src/reg_file.sv src/sic_counter.sv \
		src/datapathv2.sv testbenches/datapathv2_perf_tb.sv
	vvp sim/datapathv2_perf_tb.vvp

wave-memoryv2:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/data_memoryv2_tb.vcd

wave-datapathv2:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/datapathv2_perf_tb.vcd

# =============================================================================
# Iteration 3 — Cache L1
# =============================================================================

cache_l1: setup
	iverilog -g2012 -o sim/cache_l1_tb.vvp src/cache_l1.sv testbenches/cache_l1_tb.sv
	vvp sim/cache_l1_tb.vvp

perf_counters: setup
	iverilog -g2012 -o sim/perf_counters_tb.vvp src/perf_counters.sv testbenches/perf_counters_tb.sv
	vvp sim/perf_counters_tb.vvp

wave-cache_l1:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave cache_l1_tb.vcd

# =============================================================================
# Iteration 4 (P4) — Pipeline + Cache Hierarchy Integration
# =============================================================================

CACHE_SRCS = src/adder.sv src/alu.sv src/alu_v.sv src/auth_unit.sv \
             src/branch_compare.sv src/control_unit.sv src/data_memoryv2.sv \
             src/ex_mem_reg.sv src/fwd_logic.sv src/hazard_detection.sv \
             src/id_ex_reg.sv src/if_id_reg.sv src/imm_gen.sv src/inst_mem.sv \
             src/key_vault.sv src/mem_wb_reg.sv src/mux2.sv src/mux4.sv \
             src/program_counter.sv src/reg_file.sv src/sic_counter.sv \
			 src/perf_counters.sv \
             src/cache_l1.sv src/cache_l2.sv src/cache_hierarchy.sv \
             src/datapathv3.sv

# Pipeline + cache integration testbench (verifies L1 hit / L2 hit / RAM miss)
pipeline_cache: setup
	iverilog -g2012 -o sim/pipeline_cache_tb.vvp \
		$(CACHE_SRCS) testbenches/pipeline_cache_tb.sv
	vvp sim/pipeline_cache_tb.vvp

pipeline_cache_program: setup
	iverilog -g2012 -DBENCH_MODE=1 -DPROGRAM_FILE='"$(PROGRAM_FILE)"' -DCACHE_CSV_FILE='"$(CACHE_CSV_FILE)"' -DBENCH_ID=$(BENCH_ID) -o sim/pipeline_cache_tb.vvp \
		$(CACHE_SRCS) testbenches/pipeline_cache_tb.sv
	vvp sim/pipeline_cache_tb.vvp

wave-pipeline_cache:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave sim/pipeline_cache_tb.vcd

plots-cache: pipeline_cache
	$(PYTHON) tools/plot_cache_behavior.py --input sim/cache_timeline.csv --outdir sim/plots

benchmarks-asm:
	mkdir -p $(BENCH_MEM_DIR)
	$(PYTHON) tools/asm_to_mem.py --input $(BENCH_DIR)/benchmark_1_sequential.asm --output $(BENCH_MEM_DIR)/benchmark_1_sequential.mem
	$(PYTHON) tools/asm_to_mem.py --input $(BENCH_DIR)/benchmark_2_stride.asm --output $(BENCH_MEM_DIR)/benchmark_2_stride.mem
	$(PYTHON) tools/asm_to_mem.py --input $(BENCH_DIR)/benchmark_3_random.asm --output $(BENCH_MEM_DIR)/benchmark_3_random.mem
	$(PYTHON) tools/asm_to_mem.py --input $(BENCH_DIR)/benchmark_4_thousands.asm --output $(BENCH_MEM_DIR)/benchmark_4_thousands.mem

plots-benchmarks: benchmarks-asm
	mkdir -p sim/plots/benchmark_1_sequential sim/plots/benchmark_2_stride sim/plots/benchmark_3_random sim/plots/benchmark_4_thousands
	$(MAKE) pipeline_cache_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_1_sequential.mem CACHE_CSV_FILE=sim/cache_timeline_benchmark_1_sequential.csv BENCH_ID=1
	$(PYTHON) tools/plot_cache_behavior.py --input sim/cache_timeline_benchmark_1_sequential.csv --outdir sim/plots/benchmark_1_sequential
	$(PYTHON) tools/plot_benchmark_summary_table.py --input sim/cache_timeline_benchmark_1_sequential.csv --outdir sim/plots/benchmark_1_sequential --benchmark-name "Benchmark 1 - Sequential"
	$(MAKE) pipeline_cache_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_2_stride.mem CACHE_CSV_FILE=sim/cache_timeline_benchmark_2_stride.csv BENCH_ID=2
	$(PYTHON) tools/plot_cache_behavior.py --input sim/cache_timeline_benchmark_2_stride.csv --outdir sim/plots/benchmark_2_stride
	$(PYTHON) tools/plot_benchmark_summary_table.py --input sim/cache_timeline_benchmark_2_stride.csv --outdir sim/plots/benchmark_2_stride --benchmark-name "Benchmark 2 - Stride"
	$(MAKE) pipeline_cache_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_3_random.mem CACHE_CSV_FILE=sim/cache_timeline_benchmark_3_random.csv BENCH_ID=3
	$(PYTHON) tools/plot_cache_behavior.py --input sim/cache_timeline_benchmark_3_random.csv --outdir sim/plots/benchmark_3_random
	$(PYTHON) tools/plot_benchmark_summary_table.py --input sim/cache_timeline_benchmark_3_random.csv --outdir sim/plots/benchmark_3_random --benchmark-name "Benchmark 3 - Random"
	$(MAKE) pipeline_cache_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_4_thousands.mem CACHE_CSV_FILE=sim/cache_timeline_benchmark_4_thousands.csv BENCH_ID=4
	$(PYTHON) tools/plot_cache_behavior.py --input sim/cache_timeline_benchmark_4_thousands.csv --outdir sim/plots/benchmark_4_thousands
	$(PYTHON) tools/plot_benchmark_summary_table.py --input sim/cache_timeline_benchmark_4_thousands.csv --outdir sim/plots/benchmark_4_thousands --benchmark-name "Benchmark 4 - Thousands"

plots-benchmarks-nocache: benchmarks-asm
	mkdir -p sim/plots/nocache/benchmark_1_sequential sim/plots/nocache/benchmark_2_stride sim/plots/nocache/benchmark_3_random sim/plots/nocache/benchmark_4_thousands
	$(MAKE) datapath_benchmark_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_1_sequential.mem BASELINE_CSV_FILE=sim/nocache_timeline_benchmark_1_sequential.csv BENCH_ID=1
	$(PYTHON) tools/plot_baseline_benchmark_summary_table.py --input sim/nocache_timeline_benchmark_1_sequential.csv --outdir sim/plots/nocache/benchmark_1_sequential --benchmark-name "Benchmark 1 - Sequential"
	$(MAKE) datapath_benchmark_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_2_stride.mem BASELINE_CSV_FILE=sim/nocache_timeline_benchmark_2_stride.csv BENCH_ID=2
	$(PYTHON) tools/plot_baseline_benchmark_summary_table.py --input sim/nocache_timeline_benchmark_2_stride.csv --outdir sim/plots/nocache/benchmark_2_stride --benchmark-name "Benchmark 2 - Stride"
	$(MAKE) datapath_benchmark_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_3_random.mem BASELINE_CSV_FILE=sim/nocache_timeline_benchmark_3_random.csv BENCH_ID=3
	$(PYTHON) tools/plot_baseline_benchmark_summary_table.py --input sim/nocache_timeline_benchmark_3_random.csv --outdir sim/plots/nocache/benchmark_3_random --benchmark-name "Benchmark 3 - Random"
	$(MAKE) datapath_benchmark_program PROGRAM_FILE=$(BENCH_MEM_DIR)/benchmark_4_thousands.mem BASELINE_CSV_FILE=sim/nocache_timeline_benchmark_4_thousands.csv BENCH_ID=4
	$(PYTHON) tools/plot_baseline_benchmark_summary_table.py --input sim/nocache_timeline_benchmark_4_thousands.csv --outdir sim/plots/nocache/benchmark_4_thousands --benchmark-name "Benchmark 4 - Thousands"

plots-benchmark-comparison: plots-benchmarks
	mkdir -p sim/plots/comparison
	$(PYTHON) tools/plot_benchmark_comparison.py --input-dir sim --outdir sim/plots/comparison

plots-cache-vs-nocache-comparison: plots-benchmarks plots-benchmarks-nocache
	mkdir -p sim/plots/comparison
	$(PYTHON) tools/plot_cache_vs_nocache_comparison.py --input-dir sim --outdir sim/plots/comparison

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.txt sim/*.bin