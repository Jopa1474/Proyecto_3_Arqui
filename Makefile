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


clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.txt sim/*.bin