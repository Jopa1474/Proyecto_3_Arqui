
// Instrucciones de 23 bits por slot.
// El archivo instructions.mem usa hex de 6 digitos.
module inst_mem #(
    parameter int ADDR_WIDTH  = 32,
    parameter int INSTR_WIDTH = 23,
    parameter int MEM_WORDS   = 16384
)(
    // 64 KB de instrucciones
    // 65536 bytes/4 bytes por slot = 16384 slots de 23 bits
    // Cada slot guarda una instruccion de 23 bits
    input  logic [ADDR_WIDTH-1:0]  addr,
    output logic [INSTR_WIDTH-1:0] inst
);

    logic [INSTR_WIDTH-1:0] memory [0:MEM_WORDS-1];

    assign inst = memory[addr[31:2]];

    initial begin
        $readmemh("mem/instructions.mem", memory);
    end

endmodule