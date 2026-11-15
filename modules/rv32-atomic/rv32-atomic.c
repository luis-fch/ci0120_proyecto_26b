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

/* A single RV32I instruction. */
typedef struct
{
        uint32 opcode, rd, funct3, rs1, rs2, funct7;
        int64 immediate;
        const char *name;
} instruction_t;

/* Extract a bit field from a word. */
static uint32 bits(uint32 word, unsigned start, unsigned width)
{
        // Create a mask with width 1s, e.g. width=3 -> mask=0b111=7. Then shift the word right by start bits and apply the mask to get the desired bits.
        uint32 mask = (1u << width) - 1u;
        return (word >> start) & mask;
}

/* Convert a bit field to a signed integer. */
static int64 signed_value(uint32 value, unsigned width)
{
        int64 limit = (int64)1 << width;
        if (value >= limit / 2)
                return (int64)value - limit;
        return value;
}

/* Fetch an instruction from the CPU's memory. */
static bool fetch(rv32_t *cpu, uint32 pc, uint32 *word)
{
        uint8 bytes[4];
        if (!read_simics_memory(cpu, pc, bytes, 4))
                return false;

        // Little-endian: the first byte is the least significant byte. 256^1 = 256, 256^2 = 65536, 256^3 = 16777216
        *word = bytes[0] + 256u * bytes[1] + 65536u * bytes[2] + 16777216u * bytes[3];
        return true;
}

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
        else if (d.opcode == 0x13u && d.funct3 == 0)
        {
                d.name = "addi";
                d.immediate = signed_value(bits(word, 20, 12), 12);
        }
        return d;
}

void execute(rv32_t *cpu)
{
        uint32 pc = cpu->pc;
        uint32 word;
        increment_cycle(cpu);

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
        uint32 a = reg_read_x(cpu, d.rs1);
        uint32 result = a + (uint32)d.immediate;

        reg_write_x(cpu, d.rd, result);
        cpu->pc = next_pc;
        increment_step(cpu);
}

/* Text for Simics' disassemble CLI command (e.g. "disassemble 0x0 10")
   for the instruction word instr. Return a string allocated with Simics'
   allocators, e.g. MM_STRDUP() or a strbuf as below; Simics frees it. */
char *
rv32_disassemble(uint32 instr)
{
        strbuf_t b = SB_INIT;
        sb_addfmt(&b, ".word 0x%08x", instr);
        return sb_detach(&b);
}
