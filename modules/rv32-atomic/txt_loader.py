# © 2026 Intel Corporation
#
# This software and the related documents are Intel copyrighted materials, and
# your use of them is governed by the express license under which they were
# provided to you ("License"). Unless the License provides otherwise, you may
# not use, modify, copy, publish, distribute, disclose or transmit this software
# or the related documents without Intel's prior written permission.
#
# This software and the related documents are provided as is, with no express or
# implied warranties, other than those that are expressly stated in the License.

import simics

I_FUNCT3 = {
    "addi": 0,
    "slti": 2,
    "sltiu": 3,
    "xori": 4,
    "ori": 6,
    "andi": 7,
}

SHIFT_FIELDS = {"slli": (1, 0), "srli": (5, 0), "srai": (5, 0x20)}

R_FIELDS = {
    "add": (0, 0),
    "sub": (0, 0x20),
    "sll": (1, 0),
    "slt": (2, 0),
    "sltu": (3, 0),
    "xor": (4, 0),
    "srl": (5, 0),
    "sra": (5, 0x20),
    "or": (6, 0),
    "and": (7, 0),
}


def mem_write8(core, addr, value):
    """Write the byte value (0..255) to address addr of the core's memory."""
    simics.SIM_write_phys_memory(core, addr, value, 1)


def number(text: str) -> int:
    """Convert a string to an integer, supporting decimal and hex formats."""
    unsigned = text.lstrip("+-")
    if unsigned.lower().startswith("0x"):
        return int(text, 16)
    else:
        return int(text)


def register(text: str) -> int:
    """Convert a string to a register number, supporting x0..x31"""
    digits = text[1:]
    if not text.startswith("x") or not digits.isdecimal():
        raise ValueError(f"Invalid register name: {text}")
    value = int(digits)
    if not 0 <= value <= 31:
        raise ValueError(f"Invalid register range: {text}")
    return value


def validate_range(value: int, low: int, high: int) -> None | ValueError:
    """Validate that a value is within a specified range."""
    if not (low <= value <= high):
        raise ValueError(f"Value {value} out of range [{low}, {high}]")


def encode_i(opcode: int, funct3: int, rd: int, rs1: int, immediate: int) -> int:
    """Encode an I-type instruction."""
    # RV32I I-type layout: imm[31:20], rs1[19:15], funct3[14:12],
    # rd[11:7], opcode[6:0]. Multiplying by 2**start places each
    # field at its starting bit. The opcode already starts at bit 0.
    return immediate * 2**20 + rs1 * 2**15 + funct3 * 2**12 + rd * 2**7 + opcode


def encode(line: str) -> int:
    """Encode a single instruction line into machine code."""
    parts = line.split(maxsplit=1)
    op = parts[0]
    operands = parts[1].split(",") if len(parts) == 2 else []
    operands = [operand.strip() for operand in operands]

    if op == "ebreak" and not operands:
        return 0x00100073

    # Handle I-type instructions
    if op in ("lui", "auipc") and len(operands) == 2:
        rd = register(operands[0])
        upper = number(operands[1])
        validate_range(upper, -524288, 1048575)
        opcode = 0x37 if op == "lui" else 0x17
        return (upper % 2**20) * 4096 + rd * 128 + opcode

    if len(operands) == 3:
        if op in I_FUNCT3:
            rd = register(operands[0])
            rs1 = register(operands[1])
            immediate = number(operands[2])
            validate_range(immediate, -2048, 2047)
            return encode_i(0x13, I_FUNCT3[op], rd, rs1, immediate % 4096)
        if op in SHIFT_FIELDS:
            rd = register(operands[0])
            rs1 = register(operands[1])
            amount = number(operands[2])
            validate_range(amount, 0, 31)
            funct3, funct7 = SHIFT_FIELDS[op]
            return encode_i(0x13, funct3, rd, rs1, funct7 * 32 + amount)
        if op in R_FIELDS:
            rd = register(operands[0])
            rs1 = register(operands[1])
            rs2 = register(operands[2])
            funct3, funct7 = R_FIELDS[op]
            return encode_i(0x33, funct3, rd, rs1, funct7 * 32 + rs2)

    raise ValueError(f"Unsupported instruction or operands: {line}")


def load_program(core, path, address) -> None:
    """Read the assembly program in the text file path and write the machine
    code of its instructions into memory, the first one at address."""
    words = []
    with open(path, encoding="utf-8") as source:
        for line_number, line_raw in enumerate(source, start=1):
            line = line_raw.partition("#")[0].strip()  # Remove comments and whitespace
            if not line:
                continue  # Skip empty lines
            try:
                words.append(encode(line))
            except ValueError as e:
                raise ValueError(f"Error in {path} at line {line_number}: {e}")

    for word in words:
        for byte in word.to_bytes(4, byteorder="little"):
            mem_write8(core, address, byte)
            address += 1
