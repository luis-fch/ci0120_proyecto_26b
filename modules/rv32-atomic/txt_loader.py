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

# Mapping of instruction mnemonics to their corresponding funct3 values for I-type instructions.
I_FUNCT3 = {
    "addi": 0,
    "slti": 2,
    "sltiu": 3,
    "xori": 4,
    "ori": 6,
    "andi": 7,
}

# Mapping of branch instruction mnemonics to their corresponding funct3 values.
BRANCH_FUNCT3 = {
    "beq": 0,
    "bne": 1,
    "blt": 4,
    "bge": 5,
    "bltu": 6,
    "bgeu": 7,
}

# Mapping of shift instruction mnemonics to their corresponding funct3 values and shift amounts.
SHIFT_FIELDS = {"slli": (1, 0), "srli": (5, 0), "srai": (5, 0x20)}

# Mapping of R-type instruction mnemonics to their corresponding funct3 and funct7 values.
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
    """Convert a string to an integer, supporting decimal and hex formats.

    :param str text: The string representation of the number.

    :return: The integer value of the string.
    :rtype: int
    """
    unsigned = text.lstrip("+-")
    if unsigned.lower().startswith("0x"):
        return int(text, 16)
    else:
        return int(text)


def field(value: int, start: int, width: int) -> int:
    """
    Extracts a field of given width starting at the specified bit position from the value.

    :param int value: The integer value from which to extract the field.
    :param int start: The starting bit position of the field (0-indexed).
    :param int width: The width of the field in bits.

    :return: The extracted field value.
    :rtype: int
    """
    return value // (2**start) % (2**width)


def register(text: str) -> int:
    """Convert a string to a register number, supporting x0..x31
    
    :param str text: The string representation of the register (e.g., 'x0', 'x1', ..., 'x31').

    :return: The integer register number corresponding to the string.
    :rtype: int

    :raises ValueError: If the register name is invalid or out of range.
    """
    digits = text[1:]
    if not text.startswith("x") or not digits.isdecimal():
        raise ValueError(f"Invalid register name: {text}")
    value = int(digits)
    validate_range(value, 0, 31)
    return value


def validate_range(value: int, low: int, high: int) -> None:
    """Validate that a value is within a specified range.
    
    :param int value: The value to validate.
    :param int low: The lower bound of the range (inclusive).
    :param int high: The upper bound of the range (inclusive).

    :raises ValueError: If the value is out of the specified range.
    """
    if not (low <= value <= high):
        raise ValueError(f"Value {value} out of range [{low}, {high}]")


def encode_i(opcode: int, funct3: int, rd: int, rs1: int, immediate: int) -> int:
    """Encode an I-type instruction.
    
    :param int opcode: The opcode of the instruction.
    :param int funct3: The funct3 field of the instruction.
    :param int rd: The destination register number.
    :param int rs1: The source register number.
    :param int immediate: The immediate value for the instruction.

    :return: The encoded instruction as an integer.
    :rtype: int
    """
    # RV32I I-type layout: imm[31:20], rs1[19:15], funct3[14:12],
    # rd[11:7], opcode[6:0]. Multiplying by 2**start places each
    # field at its starting bit. The opcode already starts at bit 0.
    return immediate * 2**20 + rs1 * 2**15 + funct3 * 2**12 + rd * 2**7 + opcode


def encode_control(op: str, operands: list[str]) -> int | None:
    """
    Encode control flow instructions like branches and jumps.

    :param str op: The operation code (e.g., 'beq', 'jal').
    :param list[str] operands: A list of operands for the instruction.

    :return: The encoded instruction as an integer, or None if the operation is unsupported.
    :rtype: int | None

    :raises ValueError: If the operands are invalid or out of range.
    """
    if op in BRANCH_FUNCT3 and len(operands) == 3:
        rs1 = register(operands[0])
        rs2 = register(operands[1])
        offset = number(operands[2])
        validate_range(offset, -4096, 4094)
        if offset % 2:
            raise ValueError(f"Branch offset must be even: {offset}")
        value = offset % 2**13
        return (
            field(value, 12, 1) * 2**31
            + field(value, 5, 6) * 2**25
            + rs2 * 2**20
            + rs1 * 2**15
            + BRANCH_FUNCT3[op] * 2**12
            + field(value, 1, 4) * 2**8
            + field(value, 11, 1) * 2**7
            + 0x63
        )

    if op == "jal" and len(operands) == 2:
        rd = register(operands[0])
        offset = number(operands[1])
        validate_range(offset, -1048576, 1048574)
        if offset % 2:
            raise ValueError(f"JAL offset must be even: {offset}")
        value = offset % 2**21
        return (
            field(value, 20, 1) * 2**31
            + field(value, 1, 10) * 2**21
            + field(value, 11, 1) * 2**20
            + field(value, 12, 8) * 2**12
            + rd * 2**7
            + 0x6F
        )

    if op == "jalr" and len(operands) == 2:
        rd = register(operands[0])
        offset_text, _, base = operands[1].partition("(")
        if not base.endswith(")"):
            raise ValueError(
                f"Invalid jalr operand format: {operands[1]}, expected like 'offset(base)'; for example '4(x1)'"
            )
        rs1 = register(base[:-1].strip())
        offset = number(offset_text.strip())
        validate_range(offset, -2048, 2047)
        return encode_i(0x67, 0, rd, rs1, offset % 4096)

    return None


def encode(line: str) -> int:
    """Encode a single instruction line into machine code.

    :param line: A string representing a single assembly instruction.

    :return: The machine code for the instruction.
    :rtype: int

    :raises ValueError: If the instruction is unsupported or operands are invalid.
    """
    parts = line.split(maxsplit=1)
    op = parts[0]
    operands = parts[1].split(",") if len(parts) == 2 else []
    operands = [operand.strip() for operand in operands]

    if op == "ebreak" and not operands:
        return 0x00100073

    # Handle control flow instructions
    control_word = encode_control(op, operands)
    if control_word is not None:
        return control_word

    # Handle LUI and AUIPC instructions
    if op in ("lui", "auipc") and len(operands) == 2:
        rd = register(operands[0])
        upper = number(operands[1])
        validate_range(upper, -524288, 1048575)
        opcode = 0x37 if op == "lui" else 0x17
        return (upper % 2**20) * 4096 + rd * 128 + opcode

    # Handle I-type, R-type, and shift instructions
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
    code of its instructions into memory, the first one at address.

    :param core: The core object to write the program into.
    :param path: The path to the text file containing the assembly program.
    :param address: The starting address in memory to write the program.

    :raises ValueError: If there is an error in the assembly program.
    """
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
