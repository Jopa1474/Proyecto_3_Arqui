import argparse # Para leer argumentos de la línea de comandos

# Uso: python3 tools/load_file.py --input archivo.bin --output mem/archivo.mem --address 0x1000

# Función para cargar un archivo a memoria
def load_file_to_mem(input_file, output_file, start_address):

    # Leemos el archivo de entrada 
    with open(input_file, 'rb') as infile:

        data = infile.read() 
    
    # Escribimos el archivo de salida con el formato deseado (.mem)
    with open(output_file, "w") as out:

        out.write(f"@{start_address:08x}\n")

        # Procesamos los datos en bloques de 4 bytes (32 bits)
        for i in range(0, len(data), 4):

            # Tomamos 4 bytes del archivo
            word = data[i:i+4]

            # padding si no es múltiplo de 4
            word = word.ljust(4, b'\x00')

            # Convertimos los 4 bytes a un entero (little-endian)
            value = int.from_bytes(word, byteorder='little')

            # Escribimos el valor en formato hexadecimal en el archivo de salida
            out.write(f"{value:08x}\n")


    print(f"Archivo convertido: {output_file}")
    print(f"Tamaño: {len(data)} bytes")

# Punto de entrada del script
if __name__ == "__main__":

    # Configuramos el parser de argumentos para recibir el archivo de entrada, el archivo de salida y la dirección inicial
    parser = argparse.ArgumentParser()

    # Agregamos los argumentos necesarios para el script
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--address", type=lambda x: int(x, 0), default=0)

    # Parseamos los argumentos de la línea de comandos
    args = parser.parse_args()

    # Llamamos a la función para cargar el archivo a memoria con los argumentos proporcionados
    load_file_to_mem(args.input, args.output, args.address)