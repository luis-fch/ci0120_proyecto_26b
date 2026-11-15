# Pruebas de error del core de un ciclo

Cada archivo provoca una condición concreta. El caso 07 sirve de control para comprobar que la detección de desalineación depende de si se toma el branch.

Desde la raíz del proyecto, compila el módulo y abre una sesión nueva por archivo. Cambia el nombre del programa en este ejemplo.

```powershell
.\bin\make.bat rv32-atomic
.\simics.bat targets\rv32i\rv32-atomic.simics program=targets/rv32i/programs/atomic/negativas/05-branch-desalineado.txt
```

En los casos 01 a 04, el cargador debe rechazar el archivo al iniciarse e indicar la línea 3. En los casos 05 a 09, usa los siguientes comandos en Simics después de la preparación indicada para cada caso.

```text
run 8 cycles
pregs
ptime
quit
```

| Programa | Diagnóstico esperado | Estado esperado |
| --- | --- | --- |
| [01 · Registro](01-registro-fuera-de-rango.txt) | `Value 32 out of range [0, 31]` | Error de carga |
| [02 · Inmediato](02-inmediato-fuera-de-rango.txt) | `Value 2048 out of range [-2048, 2047]` | Error de carga |
| [03 · Desplazamiento](03-desplazamiento-fuera-de-rango.txt) | `Value 32 out of range [0, 31]` | Error de carga |
| [04 · Offset impar](04-offset-impar.txt) | `Branch offset must be even: 3` | Error de carga |
| [05 · Branch desalineado](05-branch-desalineado.txt) | `unaligned instruction fetch` | PC `0x04`, `x1=5`, `x2=0`, 1 step y 2 cycles |
| [06 · JAL desalineado](06-jal-desalineado.txt) | `unaligned instruction fetch` | PC `0x04`, `x5=7`, `x2=0`, 1 step y 2 cycles |
| [07 · Branch no tomado](07-branch-no-tomado.txt) | Parada normal en `ebreak` | PC `0x0c`, `x1=5`, `x2=9`, 4 steps y 4 cycles |
| [08 · Palabra ilegal](08-palabra-ilegal.txt) | `illegal or unsupported instruction 0x02101113 at 0x00000004` | PC `0x04`, `x1=5`, `x2=0`, 1 step y 2 cycles |
| [09 · Fuera de RAM](09-fuera-de-ram.txt) | `instruction fetch failed` | PC `0x10`, `x1=5`, `x2=0`, 2 steps y 3 cycles |

Para el **caso 08**, carga el programa y escribe la palabra de máquina desde la CLI de Simics antes de ejecutar `run`. Así puedes provocar un error del decodificador con una codificación de SLLI que el cargador no generaría. Conserva el opcode y el funct3 de SLLI, pero usa un funct7 inválido para RV32I.

```text
@SIM_write_phys_memory(conf.core0, 0x4, 0x02101113, 4)
disassemble 0x4 1
```

El desensamblado debe mostrar `.word 0x02101113`. Después ejecuta los comandos de arriba.

Para el **caso 09**, añade `ram_size=0x10` al comando de arranque. Las cuatro palabras ocupan exactamente los 16 bytes de RAM y el JAL se completa al fijar el PC en `0x10`. La extracción siguiente intenta leer desde una dirección que queda fuera de la RAM.

Los nueve resultados se comprobaron en Simics 7 con el módulo `rv32-atomic` del proyecto.
