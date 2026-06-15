# Análisis de la Arquitectura de la Jerarquía de Memoria
## Proyecto II: Jerarquía de Caché de Dos Niveles para el Procesador TEA-ISA

El presente documento ofrece un análisis técnico detallado de las decisiones de diseño e implementación relativas a la jerarquía de memoria del procesador TEA-ISA segmentado de cinco etapas. En él se expone la justificación técnica de la selección de las políticas de escritura y de sustitución de líneas, así como de la parametrización de las cachés L1 de datos (L1-D) y L2 unificada, vinculando las especificaciones teóricas del proyecto con la microarquitectura final modelada en SystemVerilog.

---


## 1. Descripción general de la jerarquía

La microarquitectura implementa una jerarquía de memoria de datos estructurada en dos niveles de cachés síncronas antes de llegar a la memoria principal. El objetivo principal es reducir el **AMAT (tiempo medio de acceso a la memoria)** aprovechando la localidad espacial y temporal del procesador, minimizando así las penalizaciones por fallos de caché frente a la memoria principal, que es considerablemente más lenta.

El flujo de control y datos se establece de la siguiente manera:
$$\text{Procesador (Etapa MEM)} \longleftrightarrow \text{Caché L1-D} \longleftrightarrow \text{Caché L2} \longleftrightarrow \text{Controlador de Memoria} \longleftrightarrow \text{Memoria Principal (data\_memoryv2)}$$

```
                   +----------------------------------+
                   |     Procesador (Etapa MEM)       |
                   +-------+------------------+-------+
        Instruction Fetch  |                  | Acceso a Datos (LOAD/STORE)
        (ROM - Síncrona)   |                  | (1 ciclo en hit)
                           v                  v
                   +-------+-------+    +-----+-------+
                   |  Instruction  |    |   Caché L1  |
                   |  ROM (64 KB)  |    | Data (4 KB) |
                   +---------------+    +-----+-------+
                                              | Fallo L1 (l1_req = 1)
                                              v
                                        +-----+-------+
                                        |  Caché L2   |
                                        |   (16 KB)   |
                                        +-----+-------+
                                              | Fallo L2 (mem_req = 1)
                                              v
                                        +-----+-------+
                                        | Controlador |
                                        |  de Memoria |
                                        +-----+-------+
                                              | Cruce de Dominio (CDC)
                                              v (Reloj de Memoria: 20-50 MHz)
                                        +-----+-------+
                                        | Memoria     |
                                        | Principal   |
                                        +-------------+
```

---

## 2. Caché de datos L1 (L1-D)

La caché de datos L1 (`cache_l1.sv`) está integrada directamente en la etapa MEM de la canalización. Sus parámetros básicos son:
*   **Capacidad total:** 4 KB (1024 palabras de 32 bits).
*   **Asociatividad:** asociativa por conjuntos de 2 vías.
*   **Tamaño de línea (bloque):** 32 bytes (8 palabras de 32 bits).
*   **Latencia de acierto:** 1 ciclo de CPU.

### 2.1. Descomposición de direcciones (mapeo)
Con una dirección física orientada a bytes de 32 bits, el mapeo en L1-D se calcula matemáticamente para indexar el almacenamiento de la siguiente manera:
*   **Desplazamiento de byte [1:0]:** 2 bits. Se ignora internamente, ya que el procesador opera a nivel de palabra completa (32 bits).
*   **Desplazamiento de palabra [4:2]:** 3 bits. Permite seleccionar una de las 8 palabras ($2^3 = 8$) dentro de la línea de caché.
*   **Índice [10:5]:** 6 bits. Permite indexar uno de los 64 conjuntos ($2^6 = 64$ conjuntos).
*   **Etiqueta [31:11]:** 21 bits. Etiqueta almacenada para la verificación de coincidencia de direcciones en cada carril.

$$\text{Verificación de capacidad: } 64\text{ conjuntos} \times 2\text{ carriles/conjunto} \times 32\text{ bytes/línea} = 4096\text{ bytes} = 4\text{ KB}$$


### 2.2. Justificación de las políticas técnicas

#### Política de escritura: Write-Back
La implementación final de L1-D utiliza **Write-Back**.
*   **Justificación técnica:** En los algoritmos de cifrado y procesamiento de datos (como el algoritmo de cifrado Tiny Encryption Algorithm —TEA—, acelerado en este procesador), se realizan escrituras muy frecuentes en variables locales y marcos de pila temporales. Con una política de *Write-Through*, cada instrucción `STORE` propagaría inmediatamente la escritura a la caché L2, saturando el canal L1-L2 y aumentando los ciclos de bloqueo del procesador debido al cuello de botella del búfer. La política *Write-Back* almacena el estado modificado localmente utilizando un bit **dirty** y solo escribe la línea modificada en la L2 cuando la línea es expulsada. Esto reduce el tráfico del bus en un orden de magnitud y optimiza el IPC general.

#### Política de sustitución: LRU (Least Recently Used) de 1 bit
*   **Justificación técnica:** Para una caché asociativa de 2 vías ($N = 2$), la implementación del algoritmo LRU es exacta y extremadamente eficiente en cuanto a hardware. Solo requiere **1 bit por conjunto** (`lru[índice]`).
    *   Si `lru[s] == 0`, la línea 0 es la menos utilizada recientemente (víctima de la expulsión).
    *   Si `lru[s] == 1`, la línea 1 es la menos utilizada recientemente.
   
    *   **Actualización dinámica:** Cada vez que se accede a la ranura $k$ del conjunto $s$ (ya sea una lectura o una escritura), el bit de control se actualiza a `lru[s] <= ~k`. Este esquema garantiza que el bit siempre apunte en la dirección opuesta al acceso más reciente, lo que proporciona un comportamiento LRU perfecto sin ningún coste en términos de lógica combinacional compleja.

---

## 3. Caché L2 unificada

La caché L2 (`cache_l2.sv`) actúa como un puente intermedio entre L1-D y la memoria principal. Sus parámetros básicos son:
*   **Capacidad total:** 16 KB.
*   **Asociatividad:** asociativa por conjuntos de 4 vías.
*   **Tamaño de línea (bloque):** 32 bytes (8 palabras de 32 bits, idéntico a L1).
*   **Latencia de acierto:** 8 ciclos de CPU.

### 3.1. Descomposición de direcciones (mapeo)
*   **Desplazamiento de bytes [1:0]:** 2 bits (no se utiliza directamente para el direccionamiento de palabras).
*   **Desplazamiento de palabra [4:2]:** 3 bits (8 palabras por línea).
*   **Índice [11:5]:** 7 bits. Indexa uno de los 128 conjuntos ($2^7 = 128$ conjuntos).
*   **Etiqueta [31:12]:** 20 bits. Etiqueta para la comparación paralela entre los 4 canales.

$$\text{Verificación de la capacidad: } 128\text{ conjuntos} \times 4\text{ canales/conjunto} \times 32\text{ bytes/línea} = 16384\text{ bytes} = 16\text{ KB}$$


   ### 3.2. Justificación de las políticas técnicas

#### Política de escritura: Write-Back con un búfer de escritura aplanado
*   **Justificación técnica:** La memoria principal del sistema funciona a una frecuencia reducida (20-50 MHz en comparación con los 100 MHz de la CPU) y tiene una latencia de acceso base de **25 ciclos de procesador** por palabra, más el coste de la inicialización y la transferencia en ráfaga a través del bus. Escribir directamente en la memoria principal tras cada modificación (*Write-Through*) provocaría una caída drástica del rendimiento. Por lo tanto, L2 implementa **Write-Back** de forma predeterminada.
*   **Búfer de escritura (profundidad = 4 entradas):** Para almacenar en búfer la expulsión de líneas sucias a la memoria principal sin bloquear el bus L1-L2, se incluye un búfer de escritura FIFO (`wb_addr` y `wb_words`). Cuando una línea sucia debe ser expulsada de L2, se pone en cola en el búfer en un solo ciclo de reloj. L2 queda libre para atender inmediatamente nuevas lecturas críticas procedentes de L1, mientras que el búfer se vacía de forma asíncrona a la memoria principal utilizando los ciclos durante los cuales el bus está inactivo.
   #### Política de reemplazo: Pseudo-LRU (PLRU) basada en un árbol de decisión binario
*   **Justificación técnica:** La implementación de un LRU puro para una asociatividad de 4 vías requiere registrar el orden exacto de los accesos ($4! = 24$ estados posibles, lo que equivale a 5 bits por conjunto, o $4 \times 4$ matrices combinatorias de precedencia). Actualizar esta matriz en cada ciclo requiere un gran número de puertas lógicas y añade retraso a la ruta crítica.
*   En su lugar, L2 implementa un **pseudo-LRU basado en un árbol binario** que utiliza solo **3 bits de estado por conjunto** (`plru[2:0] = {b2, b1, b0}`):
    *   `b2`: Apunta al subconjunto superior de rutas (0 = rutas 0 y 1; 1 = rutas 2 y 3).
    *   `b1`: Apunta a la ruta dentro del subconjunto izquierdo (0 = ruta 0; 1 = ruta 1).
    *   `b0`: Apunta a la ruta dentro del subconjunto derecho (0 = ruta 2; 1 = ruta 3).

```
                      [ b2 ]  (PLRU Bit 2)
                     /      \
            0       /        \   1
                   v          v
                [ b1 ]      [ b0 ]  (PLRU Bits 1, 0)
                /   \       /    \
            0  /  1  \  0  /  1   \
              v       v   v        v
            Way0    Way1 Way2     Way3
```

*   **Algoritmo de Reemplazo (Víctima):** Cuando ocurre un fallo en L2, los bits del árbol deciden la vía víctima siguiendo el camino de los punteros inversos al uso reciente:
    *   Si `b2 == 0` $\rightarrow$ la víctima está en las vías 0 o 1. Se consulta `b1` para decidir cuál de las dos.
    *   Si `b2 == 1` $\rightarrow$ la víctima está en las vías 2 o 3. Se consulta `b0` para decidir cuál de las dos.
*   **Algoritmo de Actualización:** Al acceder a una vía $k$, se configuran los bits del árbol para que apunten al subárbol opuesto:
    *   Acceso a Vía 0: `b2 <= 1` (apunta a la derecha), `b1 <= 1` (apunta a la vía 1).
    *   Acceso a Vía 1: `b2 <= 1` (apunta a la derecha), `b1 <= 0` (apunta a la vía 0).
    *   Acceso a Vía 2: `b2 <= 0` (apunta a la izquierda), `b0 <= 1` (apunta a la vía 3).
    *   Acceso a Vía 3: `b2 <= 0` (apunta a la izquierda), `b0 <= 0` (apunta a la vía 2).

Este esquema reduce el área de memoria de control de 5 bits a 3 bits por conjunto (un **40% de ahorro de registros de control**) y simplifica la lógica de actualización a una asignación directa de compuertas simples, con un impacto en la tasa de fallos de caché prácticamente indistinguible del LRU puro.

---

## 4. Parámetros Configurables

La jerarquía está diseñada de forma paramétrica en SystemVerilog (`cache_hierarchy.sv`, `cache_l1.sv` y `cache_l2.sv`), permitiendo la exploración del espacio de diseño. Los principales parámetros configurables son:

| Parámetro | Caché L1-D | Caché L2 | Descripción | Impacto en Hardware |
| :--- | :---: | :---: | :--- | :--- |
| `DATA_WIDTH` | 32 | 32 | Ancho del bus de datos de la CPU. | Afecta el tamaño de los buses y puertos. |
| `NUM_SETS` | 64 | 128 | Cantidad de conjuntos independientes. | Modifica la capacidad de almacenamiento y simplifica/compleja el decodificador de índice. |
| `NUM_WAYS` | 2 | 4 | Nivel de asociatividad de la caché. | Mayor asociatividad reduce fallos de conflicto pero incrementa el tiempo de hit y el área de tags. |
| `LINE_WORDS` | 8 | 8 | Palabras de datos por línea de caché. | Modifica el ancho de los puertos burst y la latencia de transferencia con la memoria principal. |
| `WB_DEPTH` | - | 4 | Profundidad del Buffer de Escritura. | Más entradas permiten absorber ráfagas de escrituras sucias a costa de un mayor consumo de registros en L2. |
| `HIT_LATENCY` | 2 ciclos (stall) | 8 ciclos | Latencia fija en ciclos de reloj del procesador ante un hit. | Influye directamente en la cantidad de ciclos perdidos en stalls en el pipeline de la CPU. |

---

## 5. Detalles Críticos de la Implementación en SystemVerilog

### 5.1. Mecanismo de Stall de la Jerarquía con el Pipeline
El procesador debe detenerse ante fallos de caché para preservar la consistencia arquitectónica. Esto se resuelve mediante un protocolo de señales en `cache_hierarchy.sv`:
1.  **`cache_stall`:** Emitida por L1-D. Permanece en alto (`1`) mientras dure la transacción en curso (Lookup, Decide, Miss, Fill). La Unidad de Control del Procesador utiliza esta señal para congelar el Program Counter (PC) y deshabilitar la actualización de los registros interetapa del pipeline (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), deteniendo la progresión de todas las instrucciones.
2.  **`stall_l1_miss`:** Se activa únicamente en los estados de `S_MISS` y `S_FILL` de L1, indicando que L1 está esperando una respuesta de la caché L2.
3.  **`stall_l2_miss`:** Emitida por L2 e indica que está esperando la resolución de una ráfaga desde la memoria principal (latencia larga). Esta señal se propaga hacia atrás y mantiene el stall global.

### 5.2. Restricciones e Implementación de Compatibilidad para Icarus Verilog
Icarus Verilog no soporta el direccionamiento de arreglos de 3 dimensiones con señales variables dinámicas (por ejemplo, `data[latched_index][way][latched_offset]`) dentro de bloques síncronos de SystemVerilog. Para sortear esta limitación de síntesis de la herramienta de simulación, las cachés L1 y L2 implementan una **Máquina de Estados de Acceso Desacoplado**:

*   **Fase de Lectura y Captura (`S_LOOKUP`):**
    Dado el índice de la dirección (`latched_index`), la caché utiliza una sentencia `case` de SystemVerilog (completamente expandida para los 64/128 índices posibles) para leer los datos de todas las vías correspondientes del set y cargarlos en registros escalares intermedios (`cur_valid0`, `cur_tag0`, `cur_dirty0`, `cur_data0`, etc.).
*   **Fase de Decisión de Hit/Miss (`S_DECIDE`):**
    La lógica combinacional del hit y la selección de la vía víctima opera exclusivamente sobre estos registros planos en lugar del arreglo multidimensional principal. Esto elimina el direccionamiento dinámico variable y reduce el retardo de compuertas durante la toma de decisiones.
*   **Fase de Escritura y Actualización:**
    Al insertar datos o modificar una palabra (por ejemplo, en un hit de escritura o en la carga de una nueva línea en `S_FILL`), la caché realiza la escritura en el arreglo multidimensional usando de nuevo un bloque `case` estructurado sobre el índice de la dirección, asegurando que Icarus Verilog traduzca el circuito de forma estable sin generar errores de compilación ni colapsar la simulación.
