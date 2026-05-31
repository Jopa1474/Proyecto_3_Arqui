import argparse

# Uso: python3 tools/extract_data.py --memory mem/archivo.mem --address 0x1000 --size 64 --output datos.bin

# Función para extraer datos de un archivo .mem y guardarlos en un archivo binario
def extract_data_from_mem(mem_file, start_address, size, output_file):
    
    # Lista para almacenar las palabras leídas del archivo .mem
    words = []

    # Leer memoria
    with open(mem_file, "r") as f:

        # Procesar cada línea del archivo .mem, convertir de hexadecimal a entero y almacenarlo en la lista
        for line in f:
            line = line.strip()
            
            # Ignorar líneas vacías
            if not line or line.startswith("//"):
                continue

            # Ignorar lineas que no sean hexadecimales válidas
            if any(c not in "0123456789abcdefABCDEF" for c in line):
                continue

            words.append(int(line, 16))

    # Convertir dirección a indice
    start_index = start_address // 4

    # Calcular el número de palabras a extraer, redondeando hacia arriba si el tamaño no es múltiplo de 4
    num_words = (size + 3) // 4

    # Buffer para almacenar los bytes extraídos
    extracted_bytes = bytearray()

    # Iterar sobre el número de palabras a extraer, asegurándose de no exceder el tamaño del archivo .mem
    for i in range(num_words):
        if start_index + i < len(words):
            word = words[start_index + i]

            # Convertir a bytes little endian
            extracted_bytes.extend(word.to_bytes(4, byteorder='little'))

    # Cortar al tamaño exacto (despues de el redondeo, se reduce al original)
    extracted_bytes = extracted_bytes[:size]

    # Escribir archivo binario
    with open(output_file, "wb") as f:
        f.write(extracted_bytes)

    print(f"Datos extraídos a: {output_file}")
    print(f"Tamaño: {len(extracted_bytes)} bytes")


if __name__ == "__main__":

    # Configuramos el parser de argumentos para recibir el archivo .mem, la dirección inicial, el tamaño de los datos a extraer y el archivo de salida
    parser = argparse.ArgumentParser()

    parser.add_argument("--memory", required=True, help="Archivo .mem")
    parser.add_argument("--address", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    # Llamamos a la función para extraer los datos del archivo .mem con los argumentos proporcionados
    extract_data_from_mem(args.memory, args.address, args.size, args.output)