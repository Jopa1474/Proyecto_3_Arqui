# Modelado del Software / Simulación

## 1. Descripción general del modelo de simulación

El procesador diseñado fue modelado completamente en SystemVerilog y ejecutado mediante simulación utilizando Icarus Verilog (iverilog). El modelo implementa una arquitectura tipo RISC pipeline con soporte para operaciones de seguridad, como cifrado basado en el algoritmo TEA, manejo seguro de llaves mediante una bóveda de llaves (Key Vault). La simulación ejecuta directamente las instrucciones definidas en la ISA TEA-ISA, permitiendo validar su comportamiento funcional dentro del pipeline implementado. Esta permite evaluar el comportamiento funcional del procesador sin necesidad de síntesis en hardware. El sistema completo es instanciado en un módulo superior (datapath.sv), el cual integra todos los componentes del procesador y es utilizado con un testbench para simular el comportamiento global del CPU bajo diferentes escenarios de ejecución.

## 2. Componentes principales del modelo

El sistema está dividido en módulos los cuales representan los bloques funcionales del procesador:

### 2.1 Banco de registros (reg_file.sv)
- Contiene registros de propósito general de 32 bits.
- Permite dos lecturas simultáneas y una escritura.
- Implementa comportamiento especial para registros reservados (si aplica).
- Se accede durante la etapa ID.

### 2.2 Unidad ALU (alu.sv)
- Implementa operaciones aritméticas y lógicas:
  - suma, resta
  - AND, OR, XOR
  - desplazamientos
  - comparaciones
- Se utiliza en la etapa EX (Execute).
- Recibe operandos desde registros o inmediatos generados.

### 2.3 Unidad de control (control_unit.sv)
- Decodifica la instrucción actual.
- Genera señales de control para:
  - ALU
  - acceso a memoria
  - escritura en registros
  - control de flujo
  - hazards y forwarding
- Determina el tipo de instrucción (ALU, memoria, branch, cifrado, etc.).

### 2.4 Memoria RAM
- Implementada como memoria direccionable de 32 bits.
- Permite operaciones de:
  - lectura (load)
  - escritura (store)
- Se utiliza en la etapa MEM.
- Es inicializada mediante archivos `.mem` externos.

### 2.5 Bóveda de llaves (key_vault.sv)
- Implementa almacenamiento seguro de llaves criptográficas.
- Características:
  - Capacidad para al menos 4 llaves de 128 bits.
  - No accesible como memoria tradicional.
  - Solo accesible mediante instrucciones específicas.
- Incluye control de acceso basado en autenticación.
- Se integra con instrucciones de cifrado.

### 2.6 Unidad de autenticación (auth_unit.sv)
- Controla el acceso a la bóveda de llaves.
- Mantiene un estado de autorización del procesador.
- Bloquea operaciones criptográficas si no hay autorización válida.

### 2.7 Pipeline y registros intermedios

El procesador implementa un pipeline de 5 etapas:

1. IF – Instruction Fetch  
2. ID – Instruction Decode  
3. EX – Execute  
4. MEM – Memory  
5. WB – Write Back  

Se utilizan registros intermedios como:
- id_ex_reg.sv
- if_ex_reg.sv
- pipe_reg.sv
- ex_mem_reg.sv
- mem_wb_reg.sv

Estos almacenan los datos entre etapas.

### 2.8 Manejo de riesgos (hazards)

#### a) Forwarding (fwd_logic.sv)
- Evita stalls al reutilizar resultados de etapas posteriores.
- Reduce dependencias de datos.

#### b) Detección de hazards (hazard_detection.sv)
- Detecta conflictos de datos.
- Inserta stalls cuando es necesario.

### 2.9 Unidad de comparación (branch_compare.sv)
- Evalúa condiciones de salto.
- Determina si se toma un branch.

### 2.10 Generador de inmediatos (`imm_gen.sv`)
- Extrae valores inmediatos de la instrucción.
- Soporta diferentes formatos.

## 3. Manejo de instrucciones

Las instrucciones siguen el flujo normal del pipeline:

1. Fetch: 
   - Se obtiene la instrucción desde memoria usando el PC  
2. Decode: 
   - Se identifican operandos
   - Se generan señales de control  
3. Execute:  
   - Operaciones ALU  
   - Cálculo de direcciones  
4. Memory: 
   - Acceso a RAM (load/store)  
5. Write Back:  
   - Escritura de resultados en registros  

Para instrucciones especiales:
- Cifrado TEA: utilizan la bóveda de llaves como fuente
- Acceso a Key Vault: controlado por autenticación
- Branches: modifican el PC según condiciones

## 4. Ciclo de ejecución

El procesador opera en ciclos de reloj donde cada etapa del pipeline ejecuta simultáneamente diferentes instrucciones.

Características:
- Ejecución paralela por etapas
- Manejo de dependencias mediante forwarding y stalls

## 5. Interacción con la herramienta de carga de archivos

### 5.1 Carga de datos (load_file.py)

La herramienta permite cargar archivos reales en memoria del simulador. 

Esta herramienta:
- Lee un archivo binario
- Lo convierte en palabras de 32 bits (little-endian)
- Genera un archivo `.mem` compatible con SystemVerilog
- Permite especificar dirección de carga

Ejemplo:

- ```bash
- python3 load_file.py --input archivo.bin --output memoria.mem --address 0x1000

### 5.2 Extracción de datos (extract_data.py)

Permite recuperar datos desde la memoria simulada.

Esta herramienta:
- Lee archivo `.mem`
- Extrae palabras desde una dirección específica
- Convierte a formato binario
- Permite validar resultados de cifrado

Ejemplo:

- ```bash
- python3 extract_data.py --memory memoria.mem --address 0x1000 --size 64 --output salida.bin

## 6. Validación en simulación

Se valida tanto el funcionamiento individual de los módulos como la integración completa del procesador mediante simulaciones del datapath completo. El sistema fue validado mediante testbenches que verifican:


- Operaciones de ALU
- Acceso a memoria
- Control de flujo (branches y jumps)
- Funcionamiento del pipeline
- Manejo de hazards
- Acceso seguro a la bóveda de llaves
- Cifrado/descifrado de datos reales cargados en memoria

Además,todos los testbench generan archivos `.vcd` para análisis en GTKWave

Para utilizar el makefile se tienen las siguientes lineas en la terminal del proyecto:

make all	              - Ejecuta todas las simulaciones principales del proyecto.
make setup	              - Crea la carpeta sim/ para guardar salidas.
make alu	              - Compila y ejecuta el testbench de la ALU.
make memory	              - Compila y ejecuta el testbench de memoria de datos.
make branches	          - Prueba saltos condicionales y el program counter.
make tea	              - Prueba las operaciones de cifrado TEA en alu_v.
make vault	              - Prueba la bóveda de llaves y autenticación.
make file_crypto	      - Prueba carga/extracción de datos cifrados desde memoria.
make datapath	          - Compila y ejecuta la simulación del sistema completo.
make wave-alu             - Abre el .vcd de la ALU en GTKWave.
make wave-memory	      - Abre el .vcd de memoria en GTKWave.
make wave-branches	      - Abre el .vcd de branches en GTKWave.
make wave-tea	          - Abre el .vcd de TEA en GTKWave.
make wave-vault	          - Abre el .vcd de la bóveda en GTKWave.
make wave-file_crypto	  - Abre el .vcd del cifrado con memoria en GTKWave.
make wave-datapath	      - Abre el .vcd del datapath completo en GTKWave.
make clean	              - Borra archivos generados en sim/.