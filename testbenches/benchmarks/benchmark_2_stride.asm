
# Benchmark 2
# Acceso a un arreglo con diferentes strides para comparar hit rates y AMAT
#   - stride corto: 4 palabras (16 bytes)
#   - stride largo: 16 palabras (64 bytes)

    # R2 <- base arreglo (0x00000200)
    lli r2, 0x00, 0
    lli r2, 0x02, 1

    # R7 <- acumulador
    addi r7, r0, 0

    # Fase A: stride = 16 bytes
    addi r4, r0, 0      # contador
    addi r6, r0, 128    # limite
    addi r8, r0, 16     # stride bytes

loop_stride_short:
    load r5, 0(r2)
    add  r7, r7, r5
    add  r2, r2, r8
    addi r4, r4, 1
    bgt  r6, r4, loop_stride_short

    # Reiniciar base para fase B
    lli r2, 0x00, 0
    lli r2, 0x02, 1

    # Fase B: stride = 64 bytes
    addi r4, r0, 0
    addi r6, r0, 128

    # R9 <- 64
    addi r9, r0, 64

loop_stride_long:
    load r5, 0(r2)
    add  r7, r7, r5
    add  r2, r2, r9
    addi r4, r4, 1
    bgt  r6, r4, loop_stride_long

    halt
