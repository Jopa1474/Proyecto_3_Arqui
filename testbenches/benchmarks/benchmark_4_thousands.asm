# Benchmark 4
# Acceso secuencial de gran volumen para evaluar comportamiento en miles de accesos
# Total accesos: 2000

    # R2 <- base del arreglo (0x00000800)
    lli r2, 0x00, 0
    lli r2, 0x08, 1

    # R6 <- limite de iteraciones (2000 = 0x07D0)
    lli r6, 0xD0, 0
    lli r6, 0x07, 1

    # R4 <- contador i = 0
    addi r4, r0, 0

    # R7 <- acumulador = 0
    addi r7, r0, 0

loop_thousands:
    # Acceso secuencial
    load r5, 0(r2)
    add  r7, r7, r5

    # Siguiente palabra
    addi r2, r2, 4

    # i++
    addi r4, r4, 1

    # if i < 2000 -> loop_thousands
    bgt r6, r4, loop_thousands

    halt
