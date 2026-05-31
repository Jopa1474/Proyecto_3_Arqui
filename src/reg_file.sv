module reg_file #(
    parameter DATA_WIDTH = 32,
    parameter REG_COUNT = 16
)(
    input logic clk,
    input logic rst,
    input logic write_en,

    input logic [3:0] rs1, // primer registro a leer
    input logic [3:0] rs2, // segundo registro a leer
    input logic [3:0] rd,  // registro destino
    input logic [DATA_WIDTH-1:0] WD3, // Lo que se va a escribir

    output logic [DATA_WIDTH-1:0] RD1,// Valor del registro rs1
    output logic [DATA_WIDTH-1:0] RD2 // Valor del registro rs2
);

    logic [DATA_WIDTH-1:0] regs [0:REG_COUNT-1];

    // Se asigna el valor de la salida a los registros
    assign RD1 = (rs1 == 4'd0) ? 32'd0 : regs[rs1];
    assign RD2 = (rs2 == 4'd0) ? 32'd0 : regs[rs2];

    always_ff @(negedge clk) begin
        if (rst) begin         // Si se hace rst todo a 0
            regs[0] <= 32'd0;
            regs[1] <= 32'd0;
            regs[2] <= 32'd0;
            regs[3] <= 32'd0;
            regs[4] <= 32'd0;
            regs[5] <= 32'd0;
            regs[6] <= 32'd0;
            regs[7] <= 32'd0;
            regs[8] <= 32'd0;
            regs[9] <= 32'd0;
            regs[10] <= 32'd0;
            regs[11] <= 32'd0;
            regs[12] <= 32'd0;
            regs[13] <= 32'd0;
            regs[14] <= 32'd0;
            regs[15] <= 32'd0; 
        end
        
        // Se asigna el valor de la entrada al registro correcto
        else if (write_en && rd != 4'd0) begin
            regs[rd] <= WD3;
        end
    end
endmodule