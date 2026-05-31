// Estado de autenticación
// Ejecuta comandos ya decodificados por control_unit.
// Se comunica directamente con key_vault.

module auth_unit (
    input  logic clk,
    input  logic rst,

    // Comandos desde control_unit
    input  logic do_setpwd,
    input  logic do_login,
    input  logic do_logout,
    input  logic do_authorize,
    input  logic do_vkload,
    input  logic do_vkinv,
    input  logic do_authchk,
    input  logic auth_denied,

    // Datos del datapath
    input  logic [31:0] rs1_data,    // pwd / token / key word
    input  logic [1:0] uid_field,   // usuario
    input  logic [1:0] ki_field,    // palabra o llave seleccionada

    // SIC
    input  logic instr_retired,

    output logic auth_ok,
    output logic [1:0] ki_activo,
    output logic vf_flag,

    // Excepción de seguridad
    output logic exc_trigger,
    output logic [2:0] exc_cause,

    // Interfaz hacia key_vault
    output logic vault_we,
    output logic vault_invalidate,
    output logic [1:0] vault_key_sel,
    output logic [1:0] vault_word_sel,
    output logic [31:0] vault_data_in,
    output logic [31:0] sr
);

    localparam int NUM_USERS = 4;

    localparam logic [2:0] CAUSE_AUTH_DENIED = 3'b001;
    localparam logic [2:0] CAUSE_BAD_PWD = 3'b010;
    localparam logic [2:0] CAUSE_BAD_TOKEN = 3'b011;
    localparam logic [2:0] CAUSE_NO_PROV = 3'b100; // SETPWD sin prov_mode

    logic [31:0] TOKEN [0:3];

    initial begin
        TOKEN[0] = 32'hDDAABBCF ;
        TOKEN[1] = 32'hAABB3456;
        TOKEN[2] = 32'hABCD1234;
        TOKEN[3] = 32'h1234FBBE;
    end

    logic [31:0] pwd_table  [0:NUM_USERS-1];
    logic pwd_set [0:NUM_USERS-1];
    logic prov_mode[0:NUM_USERS-1]; // activado por AUTHORIZE, consumido por SETPWD

    logic auth_reg;
    logic [1:0] ki_activo_reg;
    logic vf_reg;

    logic sic_clear;
    logic sic_expired;

    assign auth_ok = auth_reg;
    assign ki_activo = ki_activo_reg;
    assign vf_flag = vf_reg;

    assign sr[0] = auth_reg;
    assign sr[1] = vf_reg;
    assign sr[2] = exc_trigger;
    assign sr[5:3] = exc_cause;
    assign sr[31:6] = 26'd0;

    // SIC se reinicia con login o logout; AUTHORIZE ya no inicia sesión
    assign sic_clear = do_login || do_logout;

    sic_counter sic (
        .clk (clk),
        .rst (rst),
        .enable (auth_reg && instr_retired),
        .clear (sic_clear),
        .expired (sic_expired)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            auth_reg <= 1'b0;
            ki_activo_reg <= 2'b00;
            vf_reg <= 1'b0;

            exc_trigger <= 1'b0;
            exc_cause <= 3'b000;;

            vault_we <= 1'b0;
            vault_invalidate <= 1'b0;
            vault_key_sel <= 2'b00;
            vault_word_sel <= 2'b00;
            vault_data_in <= 32'd0;

            for (int i = 0; i < NUM_USERS; i++) begin
                pwd_table[i] <= 32'd0;
                pwd_set[i] <= 1'b0;
                prov_mode[i] <= 1'b0;
            end

        end else begin
            // Defaults por ciclo
            exc_trigger <= 1'b0;
            exc_cause <= 3'b000;;
            vault_we <= 1'b0;
            vault_invalidate <= 1'b0;
            vault_key_sel <= 2'b00;
            vault_word_sel <= 2'b00;
            vault_data_in <= 32'd0;

            // Expiración automática de sesión
            if (sic_expired && auth_reg) begin
                auth_reg <= 1'b0;
                ki_activo_reg <= 2'b00;
                vf_reg <= 1'b0;
            end

            // Acceso denegado detectado por control_unit
            if (auth_denied) begin
                exc_trigger <= 1'b1;
                exc_cause <= CAUSE_AUTH_DENIED;
            end

            // AUTHCHK: copia AUTH a VF
            if (do_authchk) begin
                vf_reg <= auth_reg && !exc_trigger;
            end

            // AUTHORIZE: verifica token de fábrica  activa prov_mode, NO activa AUTH
            if (do_authorize) begin
                if (rs1_data == TOKEN[uid_field]) begin
                    prov_mode[uid_field] <= 1'b1;
                end else begin
                    exc_trigger <= 1'b1;
                    exc_cause   <= CAUSE_BAD_TOKEN;
                end
            end

            // SETPWD
            if (do_setpwd) begin
                if (!pwd_set[uid_field]) begin
                    // First boot: requiere prov_mode activado por AUTHORIZE
                    if (prov_mode[uid_field]) begin
                        pwd_table[uid_field]  <= rs1_data;
                        pwd_set[uid_field]   <= 1'b1;
                        prov_mode[uid_field] <= 1'b0;   // consume el prov_mode
                        auth_reg <= 1'b1;   // activa AUTH automáticamente
                        ki_activo_reg <= uid_field;
                        vf_reg <= 1'b0;
                    end else begin
                        exc_trigger <= 1'b1;
                        exc_cause <= CAUSE_NO_PROV;
                    end
                end else if (auth_reg && (ki_activo_reg == uid_field)) begin
                    // Cambio posterior: requiere AUTH y ser el usuario activo
                    pwd_table[uid_field] <= rs1_data;
                end else begin
                    exc_trigger <= 1'b1;
                    exc_cause   <= CAUSE_AUTH_DENIED;
                end
            end

            // LOGIN: solo funciona si pwd_set=1 (provisioning completado)
            if (do_login) begin
                if (pwd_set[uid_field] && (rs1_data == pwd_table[uid_field])) begin
                    auth_reg <= 1'b1;
                    ki_activo_reg <= uid_field;
                    vf_reg <= 1'b0;
                end else begin
                    exc_trigger <= 1'b1;
                    exc_cause <= CAUSE_BAD_PWD;
                end
            end

            // LOGOUT: siempre se ejecuta
            if (do_logout) begin
                auth_reg <= 1'b0;
                ki_activo_reg <= 2'b00;
                vf_reg <= 1'b0;
            end

            // VKLOAD: carga palabra en llave activa
            if (do_vkload && auth_reg) begin
                vault_we <= 1'b1;
                vault_key_sel <= ki_activo_reg;
                vault_word_sel <= ki_field;
                vault_data_in <= rs1_data;
            end

            // VKINV: invalida llave completa
            if (do_vkinv && auth_reg) begin
                vault_invalidate <= 1'b1;
                vault_key_sel <= ki_field;
            end

            // TEA_ADD1 / TEA_ADD2: no escriben en la bóveda.
            // Solo requieren AUTH y usan ki_activo para leer key_vault.

        end
    end

endmodule