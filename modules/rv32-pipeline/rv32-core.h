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

#ifndef RV32_CORE_H
#define RV32_CORE_H

#include "cosim-core.h"

#define RV32_NUM_REGS   32

/* Por que una instruccion no puede completarse normalmente. El fallo viaja
   con la instruccion y solo detiene la simulacion al llegar a WB. */
typedef enum {
        FAULT_NONE = 0,
        FAULT_FETCH,       /* no se pudo leer la instruccion */
        FAULT_ILLEGAL,     /* palabra no soportada */
        FAULT_MISALIGNED   /* destino de salto no multiplo de 4 */
} fault_t;

/* Registro IF/ID: instruccion que esta en ID durante este ciclo. */
typedef struct {
        bool    valid;     /* false = burbuja */
        uint32  pc;        /* direccion de la instruccion */
        uint32  word;
        fault_t fault;
} if_id_t;

/* Registro ID/EX: instruccion que esta en EX durante este ciclo. */
typedef struct {
        bool    valid;
        uint32  pc;
        uint32  word;
        fault_t fault;
        /* campos decodificados */
        uint32  opcode, rd, funct3, rs1, rs2, funct7;
        int64   imm;
        const char *name;
        bool    uses_rs1, uses_rs2, writes_rd;
        /* operandos leidos en ID (pueden corregirse con forwarding en EX) */
        uint32  val1, val2;
} id_ex_t;

/* Registro EX/WB: instruccion que esta en WB durante este ciclo. */
typedef struct {
        bool    valid;
        uint32  pc;
        uint32  word;
        fault_t fault;
        bool    writes_rd;
        bool    is_ebreak;
        uint32  rd;
        uint32  result;    /* resultado ALU o direccion de enlace */
        uint32  next_pc;   /* PC arquitectonico tras esta instruccion */
} ex_wb_t;

typedef struct rv32 {
        cosim_core_t *core;  /* pass to cosim_core_* functions */
        conf_object_t *obj;  /* the core object, for SIM_LOG_* */

        /* PC arquitectonico: el que ve Simics. Siguiente instruccion que
           debe completarse (o la que causo la parada). */
        uint32 pc;
        uint32 x[RV32_NUM_REGS];   /* use reg_read_x/reg_write_x: x0 is zero */

        /* Estado del pipeline */
        uint32 fetch_pc;           /* proxima direccion que IF debe leer */
        bool   fetch_stopped;      /* IF no busca mas (tras fallo de fetch) */
        if_id_t if_id;
        id_ex_t id_ex;
        ex_wb_t ex_wb;
        bool   forwarding_enabled; /* false = solo interlock (stalls) */

} rv32_t;

bool read_simics_memory(rv32_t *cpu, uint32 addr, uint8 *buf, unsigned len);

void rv32_halt(rv32_t *cpu, const char *reason);

void execute(rv32_t *cpu);

char *rv32_disassemble(uint32 instr);

void rv32_init_class(cosim_core_class_t *core_class);
struct rv32 *rv32_new_instance(cosim_core_t *core);
void rv32_delete_instance(rv32_t *cpu);
rv32_t *rv32_from_core(cosim_core_t *core);
logical_address_t rv32_get_pc(cosim_core_t *core);
void rv32_set_pc(cosim_core_t *core, logical_address_t pc);
void rv32_execute(cosim_core_t *core);

#endif
