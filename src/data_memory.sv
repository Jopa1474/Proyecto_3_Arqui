module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter MEM_WORDS  = 16384
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [DATA_WIDTH-1:0] addr, //Dirección byte
    input  logic [DATA_WIDTH-1:0] write_data,  //Dato a escribir STORE
    input  logic mem_read,  //1 = leer  LOAD
    input  logic mem_write,   //1 = escribir STORE

    output logic [DATA_WIDTH-1:0] read_data,   //Dato leído 
    output logic align_fault  //1 si la dirección no está alineada
);

    //16384 palabras × 4 bytes = 64 KB
    logic [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    //Inicialización: primero ceros, luego carga el archivo (hecho por la herramienta en py) si existe
    //Si no existe, la memoria arranca en cero
    initial begin
        for (int i = 0; i < MEM_WORDS; i++)
            mem[i] = 32'h0;
        //Cambiar "mem_init.mem" por el archivo
        $readmemh("mem/mem_init.mem", mem);
    end

    //Los bits [15:2] seleccionan la palabra dentro de los 64 KB
    //bits [1:0] son el offset de byte, siempre van en 00
    logic [13:0] word_index;
    assign word_index = addr[15:2];

    //Fallo de alineacion addr[1:0] debe ser 00 en cualquier acceso
    assign align_fault = (mem_read | mem_write) & (addr[1:0] != 2'b00);

    //Escritura sincronica
    always_ff @(posedge clk) begin
        if (mem_write && !align_fault)
            mem[word_index] <= write_data;
    end

    //Lectura asincronica
    always_comb begin
        if (mem_read && !align_fault)
            read_data = mem[word_index];
        else
            read_data = 32'h0;
    end

endmodule