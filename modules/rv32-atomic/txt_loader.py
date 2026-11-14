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


def encode_i(opcode: int, funct3: int, rd: int, rs1: int, immediate: int) -> int:
    """Encode an I-type instruction."""
    return immediate * 2**20 + rs1 * 2**15 + funct3 * 2**12 + rd * 2**7 + opcode


def encode(line: str) -> int:
    """Encode a single instruction line into machine code."""
    parts = line.split(maxsplit=1)
    op = parts[0]
    operands = parts[1].split(",") if len(parts) == 2 else []
    operands = [operand.strip() for operand in operands]

    if op == "ebreak":
        return 0x00100073
    if op == "addi":
        rd = register(operands[0])
        rs1 = register(operands[1])
        imm = number(operands[2])
        if not -2048 <= imm <= 2047:
            raise ValueError(f"Immediate value out of range: {imm}")
        return encode_i(0x13, 0x0, rd, rs1, imm)
    else:
        raise ValueError(f"Unsupported instruction: {op}")


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
