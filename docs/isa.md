# TEA-ISA 23-bit Architecture

 - **Integrantes:** 
Ana Melissa Vásquez Rojas, 
Jose Pablo Fernandez Rojas,  
Dario Garro Moya, 
Isaac Somarribas Montero
- **Curso:** CE-4301 Arquitectura de Computadores I
- **Proyecto:** Arquitectura del Set de Instrucciones (ISA) Específica tipo RISC para Aplicaciones de Seguridad Informática
- **Profesor:** Dr. Ing. Jeferson González Gómez

---

| Parameter | Value |
|---|---|
| Instruction width | 23 bits |
| Data width | 32 bits |
| General-purpose registers | 16 (R0–R15, 4-bit index) |
| Program Counter (PC) | 32 bits |
| Status Register (SR) | 32 bits (flags, auth state) |
| Key Vault | 4 × 128-bit keys (indexed by 2 bits) |
| Immediate fields | 11 bits (I/S-type), 10-bit offset + 1 cond bit (B-type), 15 bits (J/JR-type) |
| Memory | 64 KB minimum |
| Endianness | little-endian |

---

## Register Conventions
 
| Register | Name | Role |
|----------|------|------|
| R0  | `zero` | Always 0 |
| R1  | `ra`   | Return address |
| R2  | `sp`   | Stack pointer |
| R3  | `fp`   | Frame pointer |
| R4–R7  | `a0–a3` | Function arguments / return values |
| R8–R11 | `t0–t3` | Temporaries |
| R12–R15 | `s0–s3` | Callee-saved |
 
> **V-type note:** `rd` and `rs1` are 4-bit fields, igual que el resto de instrucciones. En instrucciones AUTH, el UID efectivo se toma de los 2 bits bajos del registro usado como `rs2`, por lo que hay 4 usuarios posibles.
---
### R-Type (Register–Register)
```
[opcode(4) | rd(4) | rs1(4) | rs2(4) | funct(3) | res(4)]
           22..19  18..15  14..11  10..7   6..4      3..0
```
 
**Usage:** ALU operations (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA)

**Note:** `res(4)` is reserved and must be encoded as `0000`.

 
### I-Type (Immediate)
```
[opcode(4) | rd(4) | rs1(4) | imm(11) ]
           22..19  18..15  14..11  10..0
```
**Usage:** ADDI, LLI, LOAD
 
### S-Type (Store)
```
[opcode(4) | rs2(4) | rs1(4) | offset(11) ]
           22..19  18..15   14..11  10..0
```
**Usage:** STORE
 
### B-Type (Branch)
```
[opcode(4) | rs2(4) | rs1(4) | cond_bit(1) |offset(10)]
           22..19  18..15   14..11  10  9..0
```
**Usage:** BEQ, BNE, BGE, BGT (conditional jumps)
 
### J-Type (Jump)
```
[opcode(4) | rd(4) | offset(15) ]
           22..19  18..15  14..0
```
**Usage:** JAL (unconditional jump with link)
 
### JR-Type (Jump Register)
```
[opcode(4) | rs1(4) | res(15)]
           22..19  18..15  14..0
```
**Usage:** JR (jump register)
 
**Note:** `res(15)` is reserved and must be encoded as `0`.
 
### V-Type (Vault / TEA)
```
[opcode(4) | rd(4) | rs1(4) | ki(2) | funct(9)]
           22..19  18..15  14..11  10..9   8..0   
```

---
## Opcode Map (bits [22:19])
 
| Opcode | Instruction Class | Type |
|--------|-------------------|--------|
| `0000` | NOP | Special format instruction|
| `0001` | ADDI (imm sign-extended 11 bits) | I |
| `0010` | LLI (imm[10:9] = byte position, imm[7:0] = value, imm[8] reserved) | I |
| `0011` | LOAD | I |
| `0100` | STORE | S |
| `0101` | BEQ, BNE (`cond_bit` selects condition) | B |
| `0110` | BGE, BGT (`cond_bit` selects condition) | B |
| `0111` | JAL | J |
| `1000` | JR | JR |
| `1001` | HALT| Special format instruction|
| `1010` | TEA_ADD1 | V |
| `1011` | TEA_ADD2 | V |
| `1100` | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA (funct distinguishes) | R |
| `1101` | LOGIN, LOGOUT, SETPWD, AUTHORIZE, VKLOAD, VKINV  (funct distinguishes) | V |
| `1110` | AUTHCHK (funct distinguishes) | V |
| `1111` | Reservado |  |
---

## Complete Instruction Set

### ALU Register–Register (R-Type)

| Mnemonic | Encoding | Operation | Notes |
|----------|----------|-----------|-------|
| `add rd, rs1, rs2` | opcode=`1100`, funct=`000` | rd = rs1 + rs2 | - |
| `sub rd, rs1, rs2` | opcode=`1100`, funct=`001` | rd = rs1 − rs2 | - |
| `and rd, rs1, rs2` | opcode=`1100`, funct=`010` | rd = rs1 & rs2 | - |
| `or  rd, rs1, rs2` | opcode=`1100`, funct=`011` | rd = rs1 \| rs2 | - |
| `xor rd, rs1, rs2` | opcode=`1100`, funct=`100` | rd = rs1 ^ rs2 | - |
| `sll rd, rs1, rs2` | opcode=`1100`, funct=`101` | rd = rs1 << rs2[4:0] | shift left logical  |
| `srl rd, rs1, rs2` | opcode=`1100`, funct=`110` | rd = rs1 >> rs2[4:0] | shift right logical (zero-fill) |
| `sra rd, rs1, rs2` | opcode=`1100`, funct=`111` | rd = rs1 >>> rs2[4:0] | (sign-fill) |

### Immediate Arithmetic (I-Type)

| Mnemonic | Encoding | Operation | Notes |
|----------|----------|-----------|-------|
| `addi rd, rs1, imm` | opcode=`0001` | rd = rs1 + sign_ext(imm[10:0]) | imm = 11 bits, signed |

### LLI - Load Lower Immediate (I-Type, opcode = `0010`)
 
`imm[10:9]` selecciona el byte objetivo; `imm[7:0]` contiene el valor inmediato de 8 bits. `imm[8]` queda reservado y se ignora.
 
| Mnemonic | imm[10:9] | Operation |
|----------|----------|-----------|
| `lli rd, imm8, 0` | `00` | rd[7:0] = imm[7:0]; rd[31:8] = 0 |
| `lli rd, imm8, 1` | `01` | rd[15:8] = imm[7:0]; los otros bytes permanecen sin cambios |
| `lli rd, imm8, 2` | `10` | rd[23:16] = imm[7:0]; los otros bytes permanecen sin cambios |
| `lli rd, imm8, 3` | `11` | rd[31:24] = imm[7:0]; los otros bytes permanecen sin cambios |
 
**Ejemplo loading DELTA = 0x9E3779B9:**
```asm
lli r5, 0xB9, 0   ; r5 = 0x000000B9
lli r5, 0x79, 1   ; r5 = 0x000079B9
lli r5, 0x37, 2   ; r5 = 0x003779B9
lli r5, 0x9E, 3   ; r5 = 0x9E3779B9
```
---

### Memory Access

| Mnemonic | Encoding | Operation | Notes |
|----------|----------|-----------|-------|
| `load rd, offset(rs1)` | opcode=`0011` | rd = mem[rs1 + sign_ext(offset)] | 32-bit word load; byte-addressed, word-aligned (addr[1:0]=00) |
| `store rs2, offset(rs1)` | opcode=`0100` | mem[rs1 + sign_ext(offset)] = rs2 | 32-bit word store; byte-addressed, word-aligned (addr[1:0]=00) |
---

### Control Flow - Conditional Branches (B-Type)

| Mnemonic | Encoding | Operation | Notes |
|----------|----------|-----------|-------|
| `beq rs2, rs1, offset` | opcode=`0101`, bit=`0` | if rs1 == rs2: PC <- PC + (sign_ext(offset) << 2) | branch equal |
| `bne rs2, rs1, offset` | opcode=`0101`, bit=`1` | if rs1 ≠ rs2: PC <- PC + (sign_ext(offset) << 2) | branch not equal |
| `bge rs2, rs1, offset` | opcode=`0110`, bit=`0` | if rs1 ≥ rs2: PC <- PC + (sign_ext(offset) << 2) | branch signed >= |
| `bgt rs2, rs1, offset` | opcode=`0110`, bit=`1` | if rs1 > rs2: PC <- PC + (sign_ext(offset) << 2) | branch signed > |

### Control Flow - Unconditional Jumps

| Mnemonic | Encoding | Operation | Notes |
|----------|----------|-----------|-------|
| `jal rd, offset` | opcode=`0111` | rd <- PC + 4; PC <- PC + (sign_ext(offset) << 2) | jump and link (to subroutine) |
| `jr rs1` | opcode=`1000` | PC <- rs1 | jump register (return / indirect jump) |

---
### Others (opcode = `1001`, Special format instruction)

| Mnemonic | Operation |
|----------|-----------|
| `halt` | Stop execution (end-of-program signal) |

```
Encoding: 1001 | 0000 | 0000 | 000 | 000000000
```
### Others (opcode = `0000`, Special format instruction)
| Mnemonic | Operation |
|----------|-----------|
| `nop` | No operation |
```
Encoding: 0000 | 0000 | 0000 | 000 | 000000000
```
---

## Cryptographic Instructions (TEA Acceleration)

- Las llaves de 128 bits residen en el módulo de bóveda.
- `TEA_ADD1`/`TEA_ADD2` reciben la palabra de llave por una ruta interna dentro de ALU_VAULT.

- **Requires AUTH=1**
- Si `AUTH=0`, la Security/Auth Unit activa `SR[SEC_EXC]=1`, carga `SR[SEC_CAUSE]=001` y la instrucción es anulada como `NOP`.

### TEA_ADD1 (V-Type, opcode = `1010`)
```
Encoding:  1010 | rd(4) | rs1(4) | ki(2) | 000000000
Operation: rd = (rs1 << 4) + K[ki]
```
- `ki` selecciona la palabra k0..k3 de la llave activa en la bóveda.


### TEA_ADD2 (V-Type, opcode = `1011`)
```
Encoding:  1011 | rd(4) | rs1(4) | ki(2) | 000000000
Operation: rd = (rs1 >> 5) + K[ki]
```
 
## Vault Instructions (V-Type)
 
### Security 
 
- Las llaves de 128 bits residen en el módulo de bóveda.
- `TEA_ADD1`/`TEA_ADD2` reciben la palabra de llave por una ruta interna dentro de ALU_VAULT.


#### Security Bits

| Bit(s) | Name | Description |
|--------|------|-------------|
| `SR[0]` | `AUTH` | Usuario autenticado |
| `SR[1]` | `VF` | Visible security query flag |
| `SR[2]` | `SEC_EXC` | Security exception flag |
| `SR[5:3]` | `SEC_CAUSE` | Código de causa de excepción |
| `SR[31:6]` | Reserved | - |

#### Security Exception Causes

| SEC_CAUSE | Trigger |
|-----------|---------|
| `001` | `AUTH=0` en operación que requiere `AUTH=1` |
| `010` | Contraseña incorrecta en `LOGIN` |
| `011` | Token incorrecto en `AUTHORIZE` |
| `100` | `SETPWD` first boot sin `prov_mode=1` |

Cuando ocurre una excepción de seguridad:

- `SR[SEC_EXC]` se activa,
- `SR[SEC_CAUSE]` refleja la causa durante la excepcion del ciclo
- la instrucción inválida es anulada,
- el Program Counter continúa secuencialmente.

```text
PC <- PC + 4
```
 
### AUTH Instructions (opcode = `1101`)
 
Enrutadas a la Security/Auth Unit en Decode. La arquitectura final resuelve autenticación, autorización, AUTHCHK, VKLOAD y VKINV desde ID usando los datos leídos del banco de registros y forwarding hacia Decode cuando es necesario.
 
#### SETPWD - Set or Change Password
```
Encoding:  1101 | rs2(uid)(4) | rs1(pwd)(4) | 00 | 000000000 
```
- `rs2` contiene el user ID (0..3); `rs1` contiene la contraseña a registrar para ese usuario.

First boot (pwd_set[uid]=0):
- Requiere `prov_mode[uid]=1` (activado previamente por AUTHORIZE).
- Si `prov_mode[uid]=0`: `SR[SEC_EXC]=1`, `SR[SEC_CAUSE]=100`, instrucción anulada.
- Si exitoso:
  - almacena contraseña en `pwd_table[uid]`
  - activa `pwd_set[uid]=1`
  - limpia `prov_mode[uid]=0`
  - activa `SR[AUTH]=1`, establece `ki_activo <- uid`
Cambio posterior (pwd_set[uid]=1):
- Requiere `AUTH=1` y que `ki_activo == uid` (un usuario solo cambia su propia contraseña).
- Si no cumple: `SR[SEC_EXC]=1`, `SR[SEC_CAUSE]=001`.


#### LOGIN - Authenticate
```
Encoding:  1101 | rs2(uid)(4) | rs1(pwd)(4) | 00 | 000000001
```
- `rs2` contiene el user ID (0..3); `rs1` contiene la contraseña del usuario.
- La Security/Auth Unit valida el par (uid, pwd) contra su tabla interna de usuarios.
- Coincidencia:
  - activa `SR[AUTH]=1`,
  - limpia `SR[SEC_EXC]=0`,
  - limpia `SR[SEC_CAUSE]=000`,
  - establece `ki_activo <- uid`,
  - reinicia el Session Instruction Counter (SIC) a 0.

#### LOGOUT - Lock Vault
```
Encoding:  1101 | 0000 | 0000 | 00 | 000000010 
```
- Limpia `SR[AUTH]=0`, `SR[VF]=0`, `SR[SEC_EXC]=0` y `SR[SEC_CAUSE]=000`.
- No borra el contenido de la bóveda.
- Siempre se ejecuta independientemente del estado de AUTH.

### AUTHORIZE — Provisioning Token Verification
```
Encoding:  1101 | rs2(uid)(4) | rs1(token)(4) | 00 | 000000011
```
- `rs2` contiene el user ID (0..3); `rs1` contiene el token para ese usuario.
- La Security/Auth Unit compara `rs1_data` contra `TOKEN[uid]`.
- Coincidencia:
  - activa `prov_mode[uid] = 1` internamente
  - NO activa `SR[AUTH]`
  - limpia `SR[SEC_EXC]=0`, `SR[SEC_CAUSE]=000`
- No coincidencia:
  - `SR[SEC_EXC]=1`; `SR[SEC_CAUSE]=011`
- No requiere AUTH=1.
- `prov_mode` es un flag interno.
Solo habilita la ejecución de SETPWD en modo first boot para el uid correspondiente.
---


#### VKLOAD - Load Key Word into Vault
```
Encoding:  1101 | 0000 | rs1(4) | ki(2) | 000000100
```
- `ki` selecciona la palabra destino dentro de la llave activa (k0..k3).
- `rs1` contiene la palabra de 32 bits a escribir. El dato fluye directamente por la ruta interna ALU_VAULT y se almacena en el Key Vault; **no** queda expuesto en registros generales ni memoria.
- Una llave de 128 bits se carga en 4 llamadas consecutivas (ki=0..3). El software puede limpiar el registro temporal después de cada llamada (e.g., `add r_temp, r0, r0`).
- Requires AUTH=1


#### VKINV - Invalidate/Zeroize Key in Vault
```
Encoding:  1101 | 0000 | 0000 | ki(2) | 000000101
```
- `ki` selecciona cuál de las 4 llaves (k0..k3) se invalida.
- La Security/Auth Unit escribe ceros en las 128 bits de la llave seleccionada dentro del Key Vault.
- No escribe en ningún registro general ni memoria.
- Requires AUTH=1
---


### Session Expiration (Session Instruction Counter)
 
La Security/Auth Unit mantiene un contador interno de instrucciones (SIC).

- El SIC se reinicia con `LOGIN` exitoso y con `LOGOUT`.
- Por cada instrucción retirada con `AUTH=1`, el SIC se incrementa en 1.
- Cuando el SIC alcanza el límite de sesión definido por hardware (`SESSION_LIMIT`), la Security/Auth Unit ejecuta automáticamente `logout`, invalidando la sesión autenticada.


### Vault Query Instructions (opcode = `1110`)
 
`funct[8:0]` selecciona la sub-operación.
 

#### AUTHCHK - Read Auth State
```
Encoding:  1110 | 0000 | 0000 | 00 | 000000011  
```
where `funct9 = 000000011`.

Copia SR[AUTH] en SR[VF]. El software lee el estado de autenticación mediante una rama sobre VF.
No requiere AUTH. No escribe en ningún registro.

- si `AUTH=1` y no hay excepción de seguridad activa en ese ciclo, entonces `SR[VF]=1`
- si `AUTH=0` o hay excepción de seguridad activa en ese ciclo, entonces `SR[VF]=0`

No requiere AUTH.
No escribe en registros generales.

## Access Control 
 
| Instruction | Decode: passes without AUTH | Requires AUTH=1 | Requires prov_mode=1 |
|-------------|:--------:|:---------------:|:--------------------:|
| `authorize` | Sí | No | No |
| `setpwd` (first boot) | Solo con prov_mode=1 | No | Sí |
| `setpwd` (change) | No | Sí | No |
| `login` | Sí | No | No |
| `logout` | Sí | No | No |
| `authchk` | Sí | No | No |
| `vkload` | No | Sí | No |
| `vkinv` | No | Sí | No |
| `tea_add1` | No | Sí | No |
| `tea_add2` | No | Sí | No |
 
---



## Justificación de Características del ISA TEA-ISA 23-bit
 
 
### 1. Ancho de instrucción: 23 bits
 
El ancho de 23 bits surge de la necesidad de un campo de offset suficientemente amplio para las instrucciones de salto y acceso a memoria, dado el espacio de direcciones de 64 KB. Con un offset de 11 bits con signo (rango −1024..+1023) se cubren accesos locales al stack y variables, y con 15 bits para JAL se alcanza el espacio completo de memoria.
 
Cada campo de instrucción tiene una razón concreta:
 
- Opcode (4 bits): permite codificar 16 tipos de instrucciones distintas, suficientes para cubrir ALU, acceso a memoria, control de flujo, instrucciones TEA y operaciones de bóveda de llaves. 

- Registros rd, rs1, rs2 (4 bits cada uno):indexan 16 registros de propósito general (R0–R15). El análisis de las operaciones TEA mostró que se requieren simultáneamente al menos 8 registros activos: cuatro variables de datos (`v0`, `v1`, `sum`, `delta`), registros temporales para las operaciones intermedias del cifrado y registros de control de flujo (ra, sp). Con solo 8 registros habría no es suficiente. Con 32 registros el costo de área del banco de registros se duplicaría sin beneficio para este conjunto de aplicaciones. 16 registros es el punto de equilibrio.

- funct (3 bits): distingue 8 variantes dentro de un mismo opcode. Esto es exactamente lo necesario para las 8 operaciones ALU del formato R-type (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA). Para los formatos V-type que requieren más variantes se dispone de un campo `funct[8:0]` de 9 bits.

- Inmediato (11 bits en I/S/B-type): un campo inmediato con signo de 11 bits permite offsets en el rango −1024 a +1023 bytes, suficiente para los accesos a memoria y saltos relativos dentro de programas que operan en los 64 KB de memoria mínima. Para saltos incondicionales (JAL) el campo crece a 15 bits aprovechando el espacio que liberan los campos de rs2/funct.

- Un ancho de 16 bits no alcanzaría para codificar tres campos de registro de 4 bits junto con opcode y funct en el mismo formato. Un ancho de 32 bits introduce al menos 9 bits en todos los formatos, aumentando el tamaño de la memoria de instrucciones y el ancho del bus de fetch sin ningún beneficio funcional dado el conjunto de instrucciones definido.
 
---
 
## 2. Número de registros: 16 (R0–R15)
 
Se eligieron 16 registros porque la ISA está diseñada para aplicaciones generales de seguridad, no únicamente para TEA. Un programa típico necesita simultáneamente registros para argumentos de función (a0–a3), temporales (t0–t3), callee-saved (s0–s3), más el stack pointer, frame pointer y dirección de retorno. Con solo 8 registros no es suficiente.
 
Además, 4 bits de índice de registro encajan perfectamente en el ancho de instrucción de 23 bits junto con los demás campos, mientras que 5 bits (para 32 registros estilo RISC-V) harían imposible codificar tres campos de registro dentro de los 23 bits disponibles.
 
---
 
## 3. Instrucción LLI (Load Lower Immediate por byte)
 
Las operaciones criptográficas requieren cargar constantes de 32 bits en registros, la más importante siendo la constante DELTA del algoritmo TEA: `0x9E3779B9`. Con instrucciones de 23 bits el campo inmediato máximo disponible es 15 bits (formato J-type), insuficiente para una constante de 32 bits en una sola instrucción.
 
La alternativa es la combinación `LUI` + `ADDI`, donde `LUI` carga los 20 bits superiores y `ADDI` agrega los 12 bits inferiores. Esto requiere un campo inmediato de 20 bits para `LUI`, que no cabe en una instrucción de 23 bits cuando también se necesita un campo de registro de 4 bits y un opcode de 4 bits (20 + 4 + 4 = 28 > 23).
 
La solución adoptada con `LLI` divide la carga de la constante en cuatro instrucciones, cada una escribiendo 8 bits en la posición de byte elegida del registro destino:
 
```asm
lli r5, 0xB9, 0   ; r5[7:0]   = 0xB9  →  r5 = 0x000000B9
lli r5, 0x79, 1   ; r5[15:8]  = 0x79  →  r5 = 0x000079B9
lli r5, 0x37, 2   ; r5[23:16] = 0x37  →  r5 = 0x003779B9
lli r5, 0x9E, 3   ; r5[31:24] = 0x9E  →  r5 = 0x9E3779B9
```
 
El campo de inmediato de 11 bits se aprovecha completamente y de forma eficiente: `imm[10:9]` selecciona cuál de los 4 bytes se escribe, e `imm[7:0]` transporta el valor de 8 bits a escribir. El bit `imm[8]` queda reservado para uso futuro.
 
---
 
## 4. Instrucciones TEA_ADD1 y TEA_ADD2 (aceleración criptográfica)
 
El algoritmo TEA realiza en cada ronda de cifrado las siguientes operaciones sobre las variables `v0` y `v1`:
 
```c
v0 += ((v1 << 4) + k0) ^ (v1 + sum) ^ ((v1 >> 5) + k1);
v1 += ((v0 << 4) + k2) ^ (v0 + sum) ^ ((v0 >> 5) + k3);
```
 
Los términos `(x << 4) + K[i]` y `(x >> 5) + K[i]` aparecen repetidamente en cada ronda y en ambas variables. Estos dos patrones pueden usarse para aceleración, porque combinan una operación de desplazamiento con una suma de una palabra de llave proveniente de la bóveda, operación que de otra manera requeriría instrucciones separadas de desplazamiento, lectura de llave y suma.
 
`TEA_ADD1` y `TEA_ADD2` reducen el número de instrucciones por ronda TEA a la mitad de lo que requeriría la implementación solo en instrucciones ALU, sin impactar la ruta crítica del datapath más allá de la adición de la unidad ALU_VAULT, que opera en paralelo con la ALU principal.
 
El parámetro `ki` de 2 bits en el formato V-type permite seleccionar directamente cualquiera de las 4 palabras de 32 bits de la llave activa (`k0`..`k3`) sin instrucciones adicionales de indexación, ya que las llaves residen en la bóveda y son accesibles únicamente por esta ruta interna.
 
---
 
## 5. Modos de direccionamiento
 
Registro a registro: los operandos se leen directamente del banco de registros. Es el modo usado por todas las instrucciones ALU R-type. No requiere unidad de cálculo de direcciones y es el modo de menor latencia.
 
Inmediato con extensión de signo: el segundo operando es un valor constante codificado en la instrucción, extendido en signo a 32 bits. Lo utilizan ADDI para sumas con constantes pequeñas y LOAD/STORE para el cálculo de direcciones de memoria. El hardware requerido es un extensor de signo combinacional, sin costo adicional en la ruta crítica del pipeline.
 
Base más desplazamiento (para memoria): la dirección efectiva de acceso a memoria se calcula como `rs1 + sign_ext(offset)`, donde `rs1` es un registro base y `offset` es el inmediato de 11 bits. Simplifica el hardware del acceso a memoria a una sola ALU de suma y elimina la necesidad de modos de direccionamiento complejos (indirecto, indexado, etc.).
 
PC-relativo (para saltos): las instrucciones de salto condicional (B-type) e incondicional (JAL) calculan la dirección destino como `PC + sign_ext(offset) << 2`. El desplazamiento en palabras (shift de 2 bits) amplía el rango de salto efectivo a ±4 × 1023 = ±4092 bytes para los branches y ±4 × 16383 = ±65532 bytes para JAL, cubriendo el espacio de memoria completo de 64 KB con un inmediato de tamaño reducido.
 
---
 
## 6. Tipos y tamaños de datos
 
El único tipo de dato que opera la ISA es la palabra de 32 bits con signo(complemento a dos). Esta decisión simplifica la ALU, el banco de registros y los caminos de datos.
 
Los accesos a memoria son de palabra completa de 32 bits (word-aligned), con la restricción `addr[1:0] = 00`. La arquitectura es little-endian. No se implementan accesos de byte o media palabra porque no son necesarios y agregarían complejidad al módulo de memoria y al manejo de datos en el pipeline.
 
Las llaves de bóveda son palabras de 128 bits organizadas como cuatro palabras de 32 bits (`k0`..`k3`), con el formato de llave del algoritmo TEA. El índice `ki` de 2 bits en las instrucciones V-type selecciona directamente cuál de las cuatro palabras de llave se usa, sin necesidad de instrucciones de desplazamiento adicionales.
 
Los inmediatos tienen tres tamaños según el formato de instrucción: 8 bits para LLI (valor de byte a cargar), 11 bits con signo para ADDI, LOAD, STORE y branches (rango −1024..+1023), y 15 bits con signo para JAL (rango −16384..+16383 en palabras). Estos tamaños resultan directamente del espacio disponible en cada formato de instrucción de 23 bits después de ubicar los campos de opcode y registros.
 
---
 
## 7. Conjunto de instrucciones: justificación por categoría
 
### 7.1 Instrucciones ALU (R-type e I-type)
 
Se incluyen ocho operaciones aritméticas y lógicas (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA) más la suma con inmediato (ADDI). Esta selección cubre el conjunto mínimo necesario para implementar el bucle TEA en software, que requiere sumas, XOR, desplazamientos y aritmética de control de flujo (comparaciones mediante resta y branch).
 
No se incluyen multiplicación ni división porque el algoritmo TEA no las usa y agregarían más complejidad.

### 7.2 Instrucciones de memoria (LOAD, STORE)
 
La arquitectura es de tipo carga-almacenamiento(load-store), lo que significa que las operaciones ALU solo operan sobre registros. Solo LOAD y STORE acceden a memoria. Esta elección simplifica el pipeline: la etapa de memoria (MEM) solo necesita existir para estas dos instrucciones, y no hay que manejar operandos de memoria directamente en la ALU.
 
### 7.3 Control de flujo (BEQ, BNE, BGE, BGT, JAL, JR)
 
Se incluyen cuatro condiciones de branch (igual, diferente, mayor o igual, estrictamente mayor) para cubrir los patrones típicos de bucles e if-then-else. Los pares BEQ/BNE y BGE/BGT comparten opcode y se distinguen por el bit de condición `cond_bit`, reduciendo el número de opcodes utilizados.
 
JAL permite llamadas a subrutinas guardando la dirección de retorno en un registro. JR permite el retorno desde subrutinas leyendo esa dirección del registro. 
 
### 7.4 Instrucciones de seguridad (V-type)
 
La bóveda de llaves y el sistema de autenticación requieren instrucciones específicas que no pueden implementarse con instrucciones generales de memoria por diseño, los datos de las llaves no deben quedar expuestos en registros ni en memoria accesible.
 
Las instrucciones `VKLOAD` y `VKINV` operan directamente sobre la bóveda a través de una ruta interna, sin pasar por el bus de datos principal. `TEA_ADD1` y `TEA_ADD2` leen la llave desde la bóveda también por ruta interna. Este aislamiento es un requisito de seguridad, no una limitación de diseño.
 
`LOGIN`, `LOGOUT`, `SETPWD` y `AUTHORIZE` implementan el modelo de control de acceso con cuatro niveles de privilegio (uno por usuario/llave), sesiones limitadas por contador de instrucciones (SIC) y provisión segura de contraseñas mediante tokens de fábrica. `AUTHCHK` permite al software consultar el estado de autenticación de forma no privilegiada, necesario para implementar lógica de control que se adapte al estado de autenticación actual sin requerir acceso a la bóveda.
 
La instrucción `NOP` es necesaria para el pipeline (relleno de ciclos de stall en implementaciones simples) y para alineación de código. `HALT` señala el fin de la ejecución al simulador y al hardware de verificación.

## Instruction Reference Sheet

| Instrucción            | Formato  | Semántica                    |
| ---------------------- | -------- | ---------------------------- |
| `add rd, rs1, rs2`     | R        | `rd = rs1 + rs2`             |
| `sub rd, rs1, rs2`     | R        | `rd = rs1 - rs2`             |
| `and rd, rs1, rs2`     | R        | `rd = rs1 & rs2`             |
| `or rd, rs1, rs2`      | R        | `rd = rs1 \| rs2`            |
| `xor rd, rs1, rs2`     | R        | `rd = rs1 ^ rs2`             |
| `sll rd, rs1, rs2`     | R        | `rd = rs1 << rs2[4:0]`       |
| `srl rd, rs1, rs2`     | R        | `rd = rs1 >> rs2[4:0]`       |
| `sra rd, rs1, rs2`     | R        | `rd = rs1 >>> rs2[4:0]`      |
| `addi rd, rs1, imm`    | I        | `rd = rs1 + imm`             |
| `lli rd, imm8, pos`    | I        | Carga inmediata por byte     |
| `load rd, off(rs1)`    | I        | `rd = MEM[rs1 + off]`        |
| `store rs2, off(rs1)`  | S        | `MEM[rs1 + off] = rs2`       |
| `beq rs2, rs1, off`    | B        | Branch si `rs1 == rs2`       |
| `bne rs2, rs1, off`    | B        | Branch si `rs1 != rs2`       |
| `bge rs2, rs1, off`    | B        | Branch si `rs1 >= rs2`       |
| `bgt rs2, rs1, off`    | B        | Branch si `rs1 > rs2`        |
| `jal rd, off`          | J        | Salto con link               |
| `jr rs1`               | JR       | Salto indirecto              |
| `tea_add1 rd, rs1, ki` | V        | `(rs1 << 4) + K[ki]`         |
| `tea_add2 rd, rs1, ki` | V        | `(rs1 >> 5) + K[ki]`         |
| `setpwd uid, pwd`      | V        | Registrar/cambiar contraseña |
| `login uid, pwd`       | V        | Iniciar sesión autenticada   |
| `logout`               | V        | Cerrar sesión                |
| `authorize uid, token` | V        | Validar token de provisión   |
| `vkload rs1, ki`       | V        | Cargar palabra en bóveda     |
| `vkinv ki`             | V        | Invalidar llave              |
| `authchk`              | V        | Copiar AUTH hacia VF         |
| `nop`                  | Especial | No operación                 |
| `halt`                 | Especial | Detener ejecución            |


> En la implementación actual, `SEC_EXC` y `SEC_CAUSE` son señales visibles durante el ciclo de la instrucción que provoca la excepción. Dichas señales son reflejadas temporalmente en `SR`, pero no permanecen latcheadas de manera persistente en instrucciones posteriores.


