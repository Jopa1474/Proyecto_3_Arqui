# Benchmark 3
# Accesso random a una ventana de memoria para evaluar hit rates y AMAT en el peor caso

    # R2 <- base ventana (0x00000400)
    lli r2, 0x00, 0
    lli r2, 0x04, 1

    # R3 <- seed inicial
    addi r3, r0, 7

    # R4 <- iteraciones
    addi r4, r0, 0
    lli  r6, 0x00, 0
    lli  r6, 0x01, 1     # 256

    # R7 <- acumulador
    addi r7, r0, 0

    # Constantes LCG
    addi r8,  r0, 17
    addi r9,  r0, 13

    # Mascara de 10 bits (0x000003FC, alineada a palabra)
    lli r10, 0xFC, 0
    lli r10, 0x03, 1

loop_rand:
    # x = x * 17 + 13
    # (sin multiplicacion nativa, se aproxima con sumas)
    add r11, r3, r3      # 2x
    add r12, r11, r11    # 4x
    add r12, r12, r12    # 8x
    add r12, r12, r12    # 16x
    add r3,  r12, r3     # 17x
    add r3,  r3,  r9     # +13

    # offset = x & 0x3FC
    and r13, r3, r10

    # addr = base + offset
    add r14, r2, r13

    # acceso pseudoaleatorio
    load r5, 0(r14)
    add  r7, r7, r5

    # loop control
    addi r4, r4, 1
    bgt  r6, r4, loop_rand

    halt
