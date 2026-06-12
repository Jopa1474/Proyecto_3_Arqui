# Benchmark 1 
# Acceso secuencial a un arreglo

    # R2 <- base del arreglo (0x00000100)
    lli r2, 0x00, 0
    lli r2, 0x01, 1

    # R3 <- numero de elementos (64)
    lli r3, 0x40, 0

    # R4 <- indice i = 0
    addi r4, r0, 0

    # R7 <- acumulador = 0
    addi r7, r0, 0

loop_seq:
    # R5 <- mem[R2 + 0]
    load r5, 0(r2)

    # R7 <- R7 + R5
    add r7, r7, r5

    # R2 <- R2 + 4 (siguiente palabra)
    addi r2, r2, 4

    # i++
    addi r4, r4, 1

    # if i < 64 -> loop_seq
    bgt r3, r4, loop_seq

    halt
