# Diagramas de Microarquitectura — Procesador TEA-ISA

---

## 1. Sistema Extendido — Vista General

```mermaid
flowchart TB
    subgraph CPU["Procesador TEA-ISA"]
        direction TB

        subgraph PIPE["Pipeline de 5 Etapas"]
            direction LR
            IF["IF\nInstruction Fetch"]
            ID["ID\nInstruction Decode"]
            EX["EX\nExecute"]
            MEM["MEM\nMemory Access"]
            WB["WB\nWrite Back"]
            IF --> ID --> EX --> MEM --> WB
        end

        subgraph SEC["Subsistema de Seguridad / Criptografía"]
            direction LR
            AUTH["Unidad de Autenticación\n(auth_unit)\ngestión de sesión"]
            KV["Key Vault\n4 × 128-bit keys"]
            AUTH --- KV
        end

        IMEM["Memoria de Instrucciones\n(inst_mem · 64 KB · solo lectura)"]
        HD["Unidad de Detección de Riesgos\n(hazard_detection)"]
        PC_CNT["Contadores de Métricas\n(perf_counters)\nIPC · Hit Rates · AMAT"]
    end

    subgraph MEMSYS["Sistema de Memoria de Datos"]
        direction LR
        L1["Caché L1\n4 KB · 2-way · LRU\nWrite-Back"]
        L2["Caché L2\n16 KB · 4-way · pLRU\nWrite-Back + Write Buffer"]
        CTRL["Controlador de Memoria\nFSM · latencia 25 ciclos\nburst 8 palabras"]
        DRAM["Memoria Principal\n64 KB · 50 MHz"]
        L1 --> L2 --> CTRL --> DRAM
    end

    %% Instrucciones
    IMEM -->|"instrucción 23-bit"| IF

    %% Seguridad hacia ID
    AUTH -->|"auth_valid / auth_denied"| ID
    KV -->|"key_word 32-bit"| EX

    %% Write-back al banco de registros
    WB -->|"resultado → Banco de Registros"| ID

    %% Acceso a memoria de datos
    MEM <-->|"dirección / dato"| L1

    %% Detección de riesgos
    L1 -->|"stall L1 miss"| HD
    L2 -->|"stall L2 miss"| HD
    HD -->|"PCWrite=0 · NOP · flush"| PIPE

    %% Métricas
    PIPE -->|"instr_retired"| PC_CNT
    HD -->|"ciclos de stall"| PC_CNT
    L1 -->|"hits / misses L1"| PC_CNT
    L2 -->|"hits / misses L2"| PC_CNT
    CTRL -->|"accesos · ciclos usados"| PC_CNT
```

---

## 2. Pipeline de 5 Etapas

### 2a. Etapas y Componentes

```mermaid
flowchart LR
    IF["IF\n─────────────\nContador de Programa\nMem. Instrucciones\nAdder PC+4"]

    IFID(["IF/ID"])

    ID["ID\n─────────────\nUnidad de Control\nBanco de Registros\nGen. de Inmediato\nComparador Branch\nUnidad Autenticación"]

    IDEX(["ID/EX"])

    EX["EX\n─────────────\nLógica Forwarding\nALU Principal\nALU Criptográfica"]

    EXMEM(["EX/MEM"])

    MEM["MEM\n─────────────\nJerarquía de Caché\nL1 → L2 → Memoria"]

    MEMWB(["MEM/WB"])

    WB["WB\n─────────────\nMux Selección WB\nEscritura Registros"]

    IF --> IFID --> ID --> IDEX --> EX --> EXMEM --> MEM --> MEMWB --> WB
    WB -->|"reg write"| ID
```

### 2b. Caminos de Forwarding y Detección de Riesgos

```mermaid
flowchart TB
    subgraph FWD["Caminos de Forwarding"]
        direction LR
        EXMEM2["EX/MEM"]
        MEMWB2["MEM/WB"]
        ALU2["ALU\n(etapa EX)"]
        BC2["Branch Compare\n(etapa ID)"]

        EXMEM2 -->|"Forward EX→EX"| ALU2
        MEMWB2 -->|"Forward MEM→EX"| ALU2
        EXMEM2 -->|"Forward EX→ID"| BC2
        MEMWB2 -->|"Forward MEM→ID"| BC2
    end

    subgraph HAZ["Detección de Riesgos"]
        direction LR
        CAUSES["Causas de Stall\n──────────────\nLoad-use hazard\nBranch hazard\nCache miss\nAuth hazard"]
        ACTIONS["Acciones\n──────────────\nPCWrite = 0\nFlush IF/ID\nInsertar NOP\nCongelar registros"]
        CAUSES --> ACTIONS
    end
```

### Ciclos de Penalización por Tipo de Riesgo

| Tipo de Riesgo | Ciclos |
|---|---|
| Load-use hazard | 1 |
| Branch tomado | 1 |
| Auth hazard | 1 |
| Miss L1 → L2 hit | ~8 |
| Miss L2 → Memoria | ~25 + burst |

---

## 3. Jerarquía de Cachés

```mermaid
flowchart TB
    CPU2["CPU\nEtapa MEM"]

    subgraph L1B["Caché L1"]
        L1I["4 KB\n2-way Set-Associative\n64 sets · línea 32 bytes\nReemplazo: LRU\nEscritura: Write-Back"]
    end

    subgraph L2B["Caché L2"]
        L2I["16 KB\n4-way Set-Associative\n128 sets · línea 32 bytes\nReemplazo: Pseudo-LRU\nEscritura: Write-Back\nWrite Buffer: 4 entradas"]
    end

    subgraph CTRLB["Controlador de Memoria"]
        FSMI["FSM\nS_IDLE → S_WAIT → S_BURST → S_DONE\nLatencia: 25 ciclos\nBurst: 8 palabras"]
    end

    subgraph DRAMB["Memoria Principal"]
        DRAMI["64 KB\n16 384 palabras × 32-bit\nReloj: 50 MHz (CPU ÷ 2)"]
    end

    CPU2 -->|"solicitud\ndirección"| L1B
    L1B -->|"HIT → dato"| CPU2
    L1B -->|"stall mientras\nse resuelve miss"| CPU2

    L1B -->|"MISS:\nsolicita línea"| L2B
    L1B -->|"EVICT dirty:\nescribe línea"| L2B
    L2B -->|"línea completa\n(8 words)"| L1B

    L2B -->|"MISS:\nburst request"| CTRLB
    L2B -->|"EVICT dirty:\nburst write"| CTRLB
    CTRLB -->|"8 palabras\nmem_valid"| L2B

    CTRLB <-->|"lectura /\nescritura"| DRAMB
```

---

## 4. Controlador de Memoria — FSM

```mermaid
stateDiagram-v2
    direction LR

    [*] --> IDLE : reset

    IDLE --> ESPERA : mem_req = 1\n(latch: addr, wr_en, dato)

    ESPERA --> ESPERA : contador > 0\n(25 ciclos de latencia)

    ESPERA --> HECHO : contador = 0\n+ escritura\n(dato escrito)

    ESPERA --> HECHO : contador = 0\n+ lectura simple\n(mem_valid = 1)

    ESPERA --> BURST : contador = 0\n+ burst_en = 1\n(inicia transferencia)

    BURST --> BURST : words < 8\n(transfiere 1 word/ciclo\nmem_valid = 1)

    BURST --> HECHO : words = 8\n(burst completo)

    HECHO --> IDLE : siguiente ciclo\n(mem_ready = 1)
```

---

## 5. Contadores de Métricas

```mermaid
flowchart LR
    subgraph ENT["Entradas"]
        direction TB
        E1["instr_retired\n(instrucción completada)"]
        E2["stall_l1miss\nstall_l2miss\nstall_control"]
        E3["Contadores L1\nhits / misses\nlectura y escritura"]
        E4["Contadores L2\nhits / misses\nlectura y escritura"]
        E5["Contadores Memoria\naccesos · ciclos usados"]
    end

    subgraph MOD["perf_counters"]
        direction TB
        B["Contadores Base\n─────────────\ntotal_cycles\ninstructions_completed\nstall_cycles_L1\nstall_cycles_L2\nstall_cycles_control"]
        C["Contadores de Acceso\n─────────────\nl1_total_accesses\nl2_total_accesses"]
        D["Métricas Derivadas\n─────────────\nIPC\nL1 Hit Rate / Miss Rate\nL2 Hit Rate / Miss Rate\nAMAT"]
        B --> D
        C --> D
    end

    subgraph SAL["Salidas"]
        direction TB
        S1["total_cycles\ninstructions_completed\nstall_cycles_*"]
        S2["l1/l2_total_accesses\nmem_accesses\nmem_cycles_used"]
        S3["ipc_x1000\nl1_hit_rate_x1000\nl2_hit_rate_x1000\namat_x1000"]
    end

    ENT --> MOD
    MOD --> SAL
```

### Fórmulas

| Métrica | Fórmula |
|---|---|
| IPC | `instrucciones_completadas / ciclos_totales` |
| L1 Hit Rate | `L1_hits / L1_accesos_totales` |
| L2 Hit Rate | `L2_hits / L2_accesos_totales` |
| AMAT | `1 + MR_L1 × (8 + MR_L2 × 33)` ciclos |

> Los resultados se almacenan ×1000 para evitar punto flotante en hardware.

---

## 6. Flujo de Datos e Instrucciones

### Instrucción Aritmética (ej. ADD rd, rs1, rs2)

```mermaid
sequenceDiagram
    participant IF
    participant ID
    participant EX
    participant MEM
    participant WB

    IF->>ID: instrucción + PC
    ID->>EX: operandos RD1, RD2 + señales de control
    EX->>MEM: resultado ALU (sin acceso a memoria)
    MEM->>WB: resultado pasa sin modificarse
    WB->>ID: escribe resultado en banco de registros
```

### Instrucción LOAD con Miss en Caché

```mermaid
sequenceDiagram
    participant EX
    participant MEM
    participant L1 as Caché L1
    participant L2 as Caché L2
    participant DRAM as Memoria Principal
    participant WB

    EX->>MEM: dirección = rs1 + imm
    MEM->>L1: solicita dato
    alt L1 HIT (2-3 ciclos)
        L1-->>MEM: dato listo
    else L1 MISS → L2
        L1->>L2: solicita línea (stall pipeline)
        alt L2 HIT (~8 ciclos)
            L2-->>L1: línea completa (8 words)
            L1-->>MEM: dato listo
        else L2 MISS → DRAM
            L2->>DRAM: burst request (stall pipeline)
            DRAM-->>L2: 8 words (~25 ciclos)
            L2-->>L1: línea completa
            L1-->>MEM: dato listo
        end
    end
    MEM->>WB: dato leído
    WB->>WB: escribe en registro destino
```

### Resumen de Penalizaciones

| Evento | Ciclos extra |
|---|---|
| Load-use hazard | 1 ciclo |
| Branch tomado | 1 ciclo (flush IF) |
| Miss L1 → L2 hit | ~8 ciclos |
| Miss L2 → Memoria | ~25 ciclos + burst |
| Instrucción criptográfica sin sesión | Excepción (halt) |

---

## 7. Explicación del Flujo de Datos e Instrucciones

El procesador TEA-ISA implementa un pipeline clásico de cinco etapas en el que cada instrucción avanza una etapa por ciclo de reloj, de modo que en condiciones ideales pueden coexistir hasta cinco instrucciones distintas ejecutándose simultáneamente. El recorrido comienza en la etapa de Fetch, donde el Contador de Programa apunta a la memoria de instrucciones y extrae la instrucción de 23 bits correspondiente. Al mismo tiempo, un sumador calcula el valor PC+4 para que el contador pueda avanzar en el siguiente ciclo. La instrucción y el valor actual del PC se almacenan en el registro de pipeline IF/ID para que estén disponibles en la siguiente etapa.

En la etapa de Decode, la Unidad de Control interpreta el opcode y los campos de la instrucción y genera todas las señales de control que gobernarán el comportamiento del resto del pipeline. El Banco de Registros entrega los valores de los operandos fuente, mientras que el Generador de Inmediato extiende en signo el campo inmediato cuando la instrucción lo requiere. Si la instrucción es un salto condicional, el Comparador de Branch evalúa la condición en esta misma etapa, lo que permite conocer el destino del salto un ciclo antes de llegar a la etapa de ejecución y reduce la penalización a un solo ciclo. Para instrucciones criptográficas, la Unidad de Autenticación verifica que exista una sesión activa y el Key Vault entrega la palabra de clave correspondiente.

La etapa de Execute recibe los operandos y las señales de control y los procesa a través de la ALU. Antes de que los valores lleguen a la ALU, la Lógica de Forwarding comprueba si alguna instrucción posterior en el pipeline ya calculó un resultado que todavía no ha sido escrito de vuelta al Banco de Registros. Si detecta esta situación, redirige el resultado más reciente directamente hacia la entrada de la ALU, evitando así un stall innecesario. Cuando la instrucción es de tipo criptográfico, la ALU Criptográfica ejecuta la operación TEA correspondiente utilizando la clave extraída del Key Vault, y un multiplexor selecciona su resultado en lugar del de la ALU principal.

Al llegar a la etapa de Memory Access, el procesador determina si la instrucción necesita leer o escribir datos en memoria. Si no lo necesita, el resultado de la ALU simplemente atraviesa la etapa sin modificarse. Cuando sí hay un acceso a memoria, la solicitud se dirige primero a la Caché L1. Si el dato se encuentra en L1, la respuesta llega en pocos ciclos. Si hay un miss, L1 consulta a L2, que tiene una latencia de ocho ciclos cuando el dato está presente. Si tampoco se encuentra en L2, el Controlador de Memoria emite una solicitud de burst hacia la Memoria Principal, que introduce una latencia de 25 ciclos más el tiempo necesario para transferir los ocho words que componen una línea de caché. Durante todo el tiempo que el dato no está disponible, la señal cache_stall congela todos los registros del pipeline y el Contador de Programa, impidiendo que nuevas instrucciones avancen hasta que la memoria responda.

Finalmente, en la etapa de Write Back, un multiplexor selecciona el valor que se escribirá en el Banco de Registros: puede ser el resultado de la ALU, el dato leído de memoria, o el valor PC+4 en el caso de instrucciones de salto con enlace que deben guardar la dirección de retorno. La escritura ocurre en el flanco negativo del reloj, de forma que no interfiere con la lectura que realiza la etapa de Decode en el flanco positivo del mismo ciclo, eliminando así el riesgo de escritura y lectura simultánea sin necesidad de un stall adicional.

El módulo de Contadores de Métricas observa de forma pasiva todas estas actividades. Cuenta cada ciclo que transcurre, cada instrucción que completa su recorrido por el pipeline, y cada ciclo en que el procesador estuvo detenido por un miss de caché o por un riesgo de control. Con esos datos calcula métricas como el IPC, las tasas de acierto de L1 y L2, y el Tiempo Promedio de Acceso a Memoria, que permiten evaluar el rendimiento real del sistema bajo distintas cargas de trabajo.
