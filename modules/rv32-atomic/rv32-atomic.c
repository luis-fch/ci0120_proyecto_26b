/*
  © 2026 Intel Corporation

  This software and the related documents are Intel copyrighted materials, and
  your use of them is governed by the express license under which they were
  provided to you ("License"). Unless the License provides otherwise, you may
  not use, modify, copy, publish, distribute, disclose or transmit this software
  or the related documents without Intel's prior written permission.

  This software and the related documents are provided as is, with no express or
  implied warranties, other than those that are expressly stated in the License.
*/

#include <simics/util/strbuf.h>
#include "cosim.h"
#include "rv32-core.h"
#include "rv32-helpers.h"

/**
 * A single RV32I instruction.
 */
typedef struct
{
  uint32 opcode, rd, funct3, rs1, rs2, funct7;
  int64 immediate;
  const char *name;
} instruction_t;

/**
 * Extract a bit field from a word.
 * @param word The word to extract from.
 * @param start The starting position of the bit field.
 * @param width The width of the bit field.
 * @return The extracted bit field.
 */
static uint32 bits(uint32 word, unsigned start, unsigned width)
{
  // Create a mask with width 1s, e.g. width=3 -> mask=0b111=7. Then shift the word right by start bits and apply the mask to get the desired bits.
  uint32 mask = (1u << width) - 1u;
  return (word >> start) & mask;
}

/**
 * Convert a bit field to a signed integer.
 * @param value The bit field value.
 * @param width The width of the bit field.
 * @return The signed integer representation of the bit field.
 */
static int64 signed_value(uint32 value, unsigned width)
{
  int64 limit = (int64)1 << width;
  if (value >= limit / 2)
    return (int64)value - limit;
  return value;
}

/**
 * Fetch an instruction from the CPU's memory.
 * @param cpu The CPU to fetch from.
 * @param pc The program counter to fetch from.
 * @param word Pointer to store the fetched instruction word.
 * @return True if the fetch was successful, false otherwise.
 */
static bool fetch(rv32_t *cpu, uint32 pc, uint32 *word)
{
  uint8 bytes[4];
  if (!read_simics_memory(cpu, pc, bytes, 4))
    return false;

  // Little-endian: the first byte is the least significant byte. 256^1 = 256, 256^2 = 65536, 256^3 = 16777216
  *word = bytes[0] + 256u * bytes[1] + 65536u * bytes[2] + 16777216u * bytes[3];
  return true;
}

/**
 * Decode an instruction.
 * @param word The instruction word to decode.
 * @return The decoded instruction.
 */
static instruction_t decode(uint32 word)
{
  instruction_t d = {0};
  d.opcode = bits(word, 0, 7);
  d.rd = bits(word, 7, 5);
  d.funct3 = bits(word, 12, 3);
  d.rs1 = bits(word, 15, 5);
  d.rs2 = bits(word, 20, 5);
  d.funct7 = bits(word, 25, 7);

  if (word == 0x00100073u)
  {
    d.name = "ebreak";
  }
  else if (d.opcode == 0x13u)
  {
    const char *names[] =
        {
            "addi", NULL, "slti", "sltiu", "xori", NULL, "ori", "andi"};
    d.name = names[d.funct3];
    d.immediate = signed_value(bits(word, 20, 12), 12);

    if (d.funct3 == 1 || d.funct3 == 5)
    {
      d.immediate = d.rs2; // For SLLI, SRLI, SRAI, the immediate is in rs2 field
      if (d.funct3 == 1 && d.funct7 == 0)
      {
        d.name = "slli";
      }
      if (d.funct3 == 5 && d.funct7 == 0)
      {
        d.name = "srli";
      }
      if (d.funct3 == 5 && d.funct7 == 0x20u)
      {
        d.name = "srai";
      }
    }
  }
  else if (d.opcode == 0x33u)
  {
    const char *names[] =
        {
            "add", "sll", "slt", "sltu", "xor", "srl", "or", "and"};
    if (d.funct7 == 0)
    {
      d.name = names[d.funct3];
    }
    if (d.funct7 == 0x20u && d.funct3 == 0)
    {
      d.name = "sub";
    }
    if (d.funct7 == 0x20u && d.funct3 == 5)
    {
      d.name = "sra";
    }
  }
  else if (d.opcode == 0x37u || d.opcode == 0x17u)
  {
    d.name = (d.opcode == 0x37u) ? "lui" : "auipc";
    d.immediate = bits(word, 12, 20);
  }

  if (d.opcode == 0x63u)
  {
    const char *names[] =
        {
            "beq", "bne", NULL, NULL, "blt", "bge", "bltu", "bgeu"};
    d.name = names[d.funct3];
    uint32 offset = bits(word, 31, 1) * 4096u + bits(word, 7, 1) * 2048u + bits(word, 25, 6) * 32u + bits(word, 8, 4) * 2u;
    d.immediate = signed_value(offset, 13);
  }
  else if (d.opcode == 0x6fu)
  {
    d.name = "jal";
    uint32 offset = bits(word, 31, 1) * 1048576u + bits(word, 12, 8) * 4096u + bits(word, 20, 1) * 2048u + bits(word, 21, 10) * 2u;
    d.immediate = signed_value(offset, 21);
  }
  else if (d.opcode == 0x67u && d.funct3 == 0)
  {
    d.name = "jalr";
    d.immediate = signed_value(bits(word, 20, 12), 12);
  }
  return d;
}

/**
 * Perform an arithmetic right shift on a 32-bit unsigned integer.
 * @param value The value to shift.
 * @param amount The number of bits to shift.
 * @return The shifted value.
 */
static uint32 arithmetic_right(uint32 value, unsigned amount)
{
  int64 original = signed_value(value, 32);
  int64 divisor = (int64)1 << amount;
  int64 result = original / divisor;
  if (original < 0 && original % divisor != 0)
    result -= 1;
  return (uint32)result;
}

/**
 * Perform an ALU operation based on the instruction's funct3 and funct7 fields.
 * @param d The decoded instruction.
 * @param a The value of the first register.
 * @param b The value of the second register or immediate.
 * @return The result of the ALU operation.
 */
static uint32 alu(instruction_t d, uint32 a, uint32 b)
{
  unsigned amount = b % 32u; // Only the lower 5 bits are used for shift amounts

  switch (d.funct3)
  {
  case 0:
    if (d.opcode == 0x33u && d.funct7 == 0x20u)
      return a - b; // SUB
    else
      return a + b; // ADD
  case 1:
    return a << amount; // SLL
  case 2:
    return signed_value(a, 32) < signed_value(b, 32); // SLT
  case 3:
    return a < b; // SLTU
  case 4:
    return a ^ b; // XOR
  case 5:
    if (d.funct7 == 0x20u)
      return arithmetic_right(a, amount); // SRA
    return a >> amount;                   // SRL
  case 6:
    return a | b; // OR
  case 7:
    return a & b; // AND
  default:
    return 0;
  }
}

/**
 * Determine if a branch should be taken based on the funct3 field and the values of two registers.
 * @param funct3 The funct3 field of the instruction.
 * @param a The value of the first register.
 * @param b The value of the second register.
 * @return True if the branch should be taken, false otherwise.
 */
static bool branch_taken(uint32 funct3, uint32 a, uint32 b)
{
  switch (funct3)
  {
  case 0:
    return a == b; // BEQ
  case 1:
    return a != b; // BNE
  case 4:
    return signed_value(a, 32) < signed_value(b, 32); // BLT
  case 5:
    return signed_value(a, 32) >= signed_value(b, 32); // BGE
  case 6:
    return a < b; // BLTU
  case 7:
    return a >= b; // BGEU
  default:
    return false;
  }
}

/**
 * Execute an instruction.
 * @param cpu The CPU to execute the instruction on.
 */
void execute(rv32_t *cpu)
{
  uint32 pc = cpu->pc;
  uint32 word;
  increment_cycle(cpu);

  if (pc % 4u != 0)
  {
    rv32_halt(cpu, "unaligned instruction fetch");
    return;
  }

  if (!fetch(cpu, pc, &word))
  {
    rv32_halt(cpu, "instruction fetch failed");
    return;
  }

  instruction_t d = decode(word);
  if (d.name == NULL)
  {
    illegal_instruction(cpu, pc, word);
    return;
  }

  if (d.opcode == 0x73u) // ECALL/EBREAK
  {
    increment_step(cpu);
    ebreak(cpu);
    return;
  }

  uint32 next_pc = pc + 4u;
  uint32 result = 0;
  bool write_rd = true;

  switch (d.opcode)
  {
  case 0x37u: // LUI
    result = (uint32)d.immediate * 4096u;
    break;
  case 0x17u: // AUIPC
    result = pc + (uint32)d.immediate * 4096u;
    break;
  case 0x13u: // ALU immediate
    result = alu(d, reg_read_x(cpu, d.rs1), (uint32)d.immediate);
    break;
  case 0x33u: // ALU registers
    result = alu(d, reg_read_x(cpu, d.rs1), reg_read_x(cpu, d.rs2));
    break;
  case 0x63u: // Branch
    write_rd = false;
    if (branch_taken(d.funct3, reg_read_x(cpu, d.rs1), reg_read_x(cpu, d.rs2)))
    {
      next_pc = pc + (uint32)d.immediate;
    }
    break;
  case 0x6fu: // JAL
    result = pc + 4u;
    next_pc = pc + (uint32)d.immediate;
    break;
  case 0x67u: // JALR
    result = pc + 4u;
    next_pc = (reg_read_x(cpu, d.rs1) + (uint32)d.immediate);
    next_pc -= next_pc % 2u; // Clear the least significant bit
    break;
  }

  if (next_pc % 4u != 0)
  {
    rv32_halt(cpu, "unaligned instruction fetch");
    return;
  }

  if (write_rd)
  {
    reg_write_x(cpu, d.rd, result);
  }
  cpu->pc = next_pc;
  increment_step(cpu);
}

/* Text for Simics' disassemble CLI command (e.g. "disassemble 0x0 10")
   for the instruction word. Return a string allocated with Simics'
   allocators, e.g. MM_STRDUP() or a strbuf as below; Simics frees it. */
char *
rv32_disassemble(uint32 word)
{
  strbuf_t b = SB_INIT;
  instruction_t d = decode(word);
  long long immediate = (long long)d.immediate; // Cast to long long for printing

  if (d.name == NULL)
  {
    sb_addfmt(&b, ".word 0x%08x", word);
    return sb_detach(&b);
  }

  switch (d.opcode)
  {
  case 0x73u: // ECALL/EBREAK
    sb_addfmt(&b, "%s", d.name);
    break;
  case 0x37u: // LUI
  case 0x17u: // AUIPC
    sb_addfmt(&b, "%s x%u, 0x%x", d.name, d.rd, (unsigned)d.immediate);
    break;
  case 0x13u: // ALU immediate
    sb_addfmt(&b, "%s x%u, x%u, %lld", d.name, d.rd, d.rs1, immediate);
    break;
  case 0x33u: // ALU registers
    sb_addfmt(&b, "%s x%u, x%u, x%u", d.name, d.rd, d.rs1, d.rs2);
    break;
  case 0x63u: // Branch
    sb_addfmt(&b, "%s x%u, x%u, %lld", d.name, d.rs1, d.rs2, immediate);
    break;
  case 0x6fu: // JAL
    sb_addfmt(&b, "%s x%u, %lld", d.name, d.rd, immediate);
    break;
  case 0x67u: // JALR
    sb_addfmt(&b, "%s x%u, %lld(x%u)", d.name, d.rd, immediate, d.rs1);
    break;
  }
  return sb_detach(&b);
}
