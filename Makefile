# Makefile para TEA-ISA

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
datapath: setup
	iverilog -g2012 -o sim/datapath_tb.vvp src/*.sv testbenches/datapath_tb.sv
	vvp sim/datapath_tb.vvp > /dev/null

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

wave-cache_l1:
	env -u GTK_EXE_PREFIX -u GTK_PATH -u GSETTINGS_SCHEMA_DIR -u XDG_DATA_HOME -u XDG_DATA_DIRS -u LOCPATH -u GTK_IM_MODULE_FILE -u GIO_MODULE_DIR gtkwave cache_l1_tb.vcd

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.txt sim/*.bin