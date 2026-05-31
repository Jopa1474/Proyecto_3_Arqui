// Bóveda de llaves
// Almacena 4 llaves de 128 bits.
// Cada llave tiene 4 palabras de 32 bits.
// Escritura controlada por auth_unit mediante VKLOAD / VKINV.

module key_vault (
    input logic clk,
    input logic rst,

    // Escritura desde auth_unit
    input logic vault_we, // VKLOAD
    input logic vault_invalidate, // VKINV
    input logic [1:0] vault_key_sel, // llave destino 0..3
    input logic [1:0] vault_word_sel, // palabra dentro de la llave k0..k3
    input logic [31:0] vault_data_in,

    // Lectura hacia ALU_VAULT
    input logic [1:0] ki_activo, // llave activa
    input logic [1:0] ki, // palabra seleccionada por instrucción
    output logic [31:0] key_word_out
);

    logic [31:0] vault [0:3][0:3];

    assign key_word_out = vault[ki_activo][ki];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    vault[i][j] <= 32'd0;
                end
            end

        end else if (vault_invalidate) begin
            vault[vault_key_sel][0] <= 32'd0;
            vault[vault_key_sel][1] <= 32'd0;
            vault[vault_key_sel][2] <= 32'd0;
            vault[vault_key_sel][3] <= 32'd0;

        end else if (vault_we) begin
            vault[vault_key_sel][vault_word_sel] <= vault_data_in;
        end
    end

endmodule