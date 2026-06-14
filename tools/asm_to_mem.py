import argparse
import os
import re
from typing import Dict, List, Tuple


OPCODES = {
    "nop": 0b0000,
    "addi": 0b0001,
    "lli": 0b0010,
    "load": 0b0011,
    "store": 0b0100,
    "beq": 0b0101,
    "bne": 0b0101,
    "bge": 0b0110,
    "bgt": 0b0110,
    "jal": 0b0111,
    "jr": 0b1000,
    "halt": 0b1001,
    "add": 0b1100,
    "sub": 0b1100,
    "and": 0b1100,
    "or": 0b1100,
    "xor": 0b1100,
    "sll": 0b1100,
    "srl": 0b1100,
    "sra": 0b1100,
}

FUNCT_R = {
    "add": 0b000,
    "sub": 0b001,
    "and": 0b010,
    "or": 0b011,
    "xor": 0b100,
    "sll": 0b101,
    "srl": 0b110,
    "sra": 0b111,
}


def parse_imm(token: str) -> int:
    token = token.strip()
    if token.lower().startswith("0x"):
        return int(token, 16)
    return int(token, 10)


def parse_reg(token: str) -> int:
    token = token.strip().lower()
    if not token.startswith("r"):
        raise ValueError(f"Registro invalido: {token}")
    idx = int(token[1:])
    if idx < 0 or idx > 15:
        raise ValueError(f"Registro fuera de rango: {token}")
    return idx


def clean_line(line: str) -> str:
    if "#" in line:
        line = line.split("#", 1)[0]
    if "//" in line:
        line = line.split("//", 1)[0]
    return line.strip()


def tokenize(op_line: str) -> List[str]:
    op_line = op_line.replace("(", ",").replace(")", "")
    toks = [t.strip() for t in op_line.split(",") if t.strip()]
    if not toks:
        return []
    first = toks[0].split()
    mnemonic = first[0]
    args = first[1:]
    toks_out = [mnemonic]
    toks_out.extend(args)
    toks_out.extend(toks[1:])
    return toks_out


def encode_signed(value: int, bits: int) -> int:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi:
        raise ValueError(f"Inmediato {value} fuera de rango para {bits} bits signed")
    return value & ((1 << bits) - 1)


def first_pass(lines: List[str]) -> Tuple[List[str], Dict[str, int]]:
    instructions: List[str] = []
    labels: Dict[str, int] = {}
    pc = 0
    for raw in lines:
        line = clean_line(raw)
        if not line:
            continue

        while ":" in line:
            label, rest = line.split(":", 1)
            label = label.strip()
            if not label:
                break
            if label in labels:
                raise ValueError(f"Etiqueta duplicada: {label}")
            labels[label] = pc
            line = rest.strip()
            if not line:
                break

        if line:
            instructions.append(line)
            pc += 1

    return instructions, labels


def encode_instruction(inst: str, pc: int, labels: Dict[str, int]) -> int:
    toks = tokenize(inst)
    if not toks:
        return 0

    m = toks[0].lower()
    if m not in OPCODES:
        raise ValueError(f"Instruccion no soportada: {m}")

    op = OPCODES[m]

    if m == "nop":
        return 0

    if m == "halt":
        return op << 19

    if m in FUNCT_R:
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para {m}: {inst}")
        rd = parse_reg(toks[1])
        rs1 = parse_reg(toks[2])
        rs2 = parse_reg(toks[3])
        funct = FUNCT_R[m]
        return (op << 19) | (rd << 15) | (rs1 << 11) | (rs2 << 7) | (funct << 4)

    if m == "addi":
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para addi: {inst}")
        rd = parse_reg(toks[1])
        rs1 = parse_reg(toks[2])
        imm = encode_signed(parse_imm(toks[3]), 11)
        return (op << 19) | (rd << 15) | (rs1 << 11) | imm

    if m == "lli":
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para lli: {inst}")
        rd = parse_reg(toks[1])
        imm8 = parse_imm(toks[2])
        if imm8 < 0 or imm8 > 0xFF:
            raise ValueError(f"imm8 invalido en lli: {imm8}")
        byte_sel = parse_imm(toks[3])
        if byte_sel < 0 or byte_sel > 3:
            raise ValueError(f"byte_sel invalido en lli: {byte_sel}")
        imm11 = (byte_sel << 9) | (imm8 & 0xFF)
        rs1 = rd  # Convencion usada en el proyecto
        return (op << 19) | (rd << 15) | (rs1 << 11) | imm11

    if m == "load":
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para load: {inst}")
        rd = parse_reg(toks[1])
        offset = encode_signed(parse_imm(toks[2]), 11)
        rs1 = parse_reg(toks[3])
        return (op << 19) | (rd << 15) | (rs1 << 11) | offset

    if m == "store":
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para store: {inst}")
        rs2 = parse_reg(toks[1])
        offset = encode_signed(parse_imm(toks[2]), 11)
        rs1 = parse_reg(toks[3])
        return (op << 19) | (rs2 << 15) | (rs1 << 11) | offset

    if m in ("beq", "bne", "bge", "bgt"):
        if len(toks) != 4:
            raise ValueError(f"Formato invalido para {m}: {inst}")

        # Sintaxis esperada en benchmarks: bgt lhs, rhs, label
        lhs = parse_reg(toks[1])
        rhs = parse_reg(toks[2])
        target_label = toks[3]
        if target_label not in labels:
            raise ValueError(f"Etiqueta no encontrada: {target_label}")

        # En datapathv3: target = PC + (imm << 2), por lo que el offset es relativo al PC actual.
        rel_words = labels[target_label] - pc
        imm10 = encode_signed(rel_words, 10)

        cond_bit = 0
        if m in ("bne", "bgt"):
            cond_bit = 1

        # Campos B-type: [opcode|rs2|rs1|cond_bit|offset(10)]
        rs1 = lhs
        rs2 = rhs
        return (op << 19) | (rs2 << 15) | (rs1 << 11) | (cond_bit << 10) | imm10

    if m == "jal":
        if len(toks) != 3:
            raise ValueError(f"Formato invalido para jal: {inst}")
        rd = parse_reg(toks[1])
        target = toks[2]
        if target in labels:
            rel_words = labels[target] - pc
        else:
            rel_words = parse_imm(target)
        imm15 = encode_signed(rel_words, 15)
        return (op << 19) | (rd << 15) | imm15

    if m == "jr":
        if len(toks) != 2:
            raise ValueError(f"Formato invalido para jr: {inst}")
        rs1 = parse_reg(toks[1])
        return (op << 19) | (rs1 << 15)

    raise ValueError(f"Instruccion no implementada: {m}")


def assemble_file(input_path: str, output_path: str) -> int:
    with open(input_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    instructions, labels = first_pass(lines)

    words: List[int] = []
    for pc, inst in enumerate(instructions):
        words.append(encode_instruction(inst, pc, labels))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(f"// Auto-generated from {os.path.basename(input_path)}\n")
        for w in words:
            f.write(f"{w:06x}\n")

    return len(words)


def main() -> None:
    parser = argparse.ArgumentParser(description="Assembla TEA-ISA ASM a .mem (23-bit)")
    parser.add_argument("--input", required=True, help="Archivo ASM de entrada")
    parser.add_argument("--output", required=True, help="Archivo .mem de salida")
    args = parser.parse_args()

    n = assemble_file(args.input, args.output)
    print(f"Assembled {n} instrucciones -> {args.output}")


if __name__ == "__main__":
    main()
