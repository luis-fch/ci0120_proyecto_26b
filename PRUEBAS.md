# Pruebas de los cores RV32I

## Atomic

Los valores de esta sección parten de una sesión nueva, con los registros en cero y el programa cargado en `0x0`. Los registros que no se enumeran conservan su valor inicial. Un **step** cuenta una instrucción completada, incluido `ebreak`. Un **cycle** cuenta una llamada a `execute()`, incluso cuando la instrucción falla. El PC queda en la instrucción que causó la parada.

### Cómo ejecutar

En PowerShell, desde la raíz del proyecto, compila y abre una sesión nueva por programa. Cambia la ruta de `program=` por la del archivo que quieras probar.

```powershell
.\bin\make.bat rv32-atomic
.\simics.bat targets\rv32i\rv32-atomic.simics program=targets/rv32i/programs/atomic/01-arranque.txt
```

Para los programas que cargan correctamente, usa estos comandos en Simics. Los casos 08 y 09 de las pruebas de ejecución requieren la preparación indicada más abajo.

```text
run 64 cycles
pregs
ptime
quit
```

Las pruebas de RAM comprueban la carga y extracción de instrucciones. El subconjunto de [CONVENTIONS.md](CONVENTIONS.md) cubre el uso de RAM como memoria de instrucciones.

### Programas que terminan en EBREAK

| Programa | Qué comprueba | Estado esperado al parar |
| --- | --- | --- |
| [01 · Arranque](targets/rv32i/programs/atomic/01-arranque.txt) | Carga, orden de bytes, extracción y decodificación de ADDI, escritura de `x1` y parada en EBREAK. | `x0=0`, `x1=5`, PC `0x04`. **2 steps, 2 cycles**. |
| [02 · Límites de la ALU](targets/rv32i/programs/atomic/02-alu-limites.txt) | La suma y resta conservan los 32 bits bajos. Comprueba las comparaciones con y sin signo, la extensión de signo en SLTIU, los desplazamientos de 0 y 31 posiciones y la protección de `x0`. | `x0=0`, `x1=0xffffffff`, `x2=0`, `x3=1`, `x4=0`, `x5=0`, `x6=0xffffffff`, `x7=1`, `x8=0x80000000`, `x9=0x7fffffff`, `x10=1`. PC `0x2c`. **12 steps, 12 cycles**. |
| [03 · Bucle](targets/rv32i/programs/atomic/03-bucle.txt) | BNE en `0x08` vuelve dos veces a `0x04` con offset `-4`. Cuando `x1` llega a cero, continúa en `0x0c`. | `x1=0`, `x2=7`, PC `0x10`. **9 steps, 9 cycles**. |
| [04 · Enlace](targets/rv32i/programs/atomic/04-enlace.txt) | JAL salta a `0x0c` y guarda el enlace en `x5`. JALR lee el valor anterior de `x6` (5), limpia su bit 0 para volver a `0x04` y escribe el nuevo enlace en ese mismo registro. | `x5=0x04`, `x6=0x14`, `x9=1`, PC `0x08`. **5 steps, 5 cycles**. |
| [Todas las instrucciones](targets/rv32i/programs/all-instructions.txt) | Integra las 30 instrucciones del ejercicio. Ejercita las seis condiciones de branch tanto tomadas como no tomadas, JAL y JALR, y un intento de escribir en `x0`. | PC `0xd4`. **46 steps, 46 cycles**. El estado completo aparece abajo. |

En **01 · Arranque**, antes de ejecutar, `x 0x0 8` debe mostrar `9300 5000 7300 1000`. Corresponde a las palabras `0x00500093` y `0x00100073`. `disassemble 0x0 2` debe mostrar `addi x1, x0, 5` y `ebreak`. Si ejecutas un solo ciclo desde el arranque, `pregs` ya debe mostrar `x1=5` y PC `0x04`.

En **02 · Límites de la ALU**, `x3=1` y `x4=0` distinguen la comparación de `0xffffffff` con cero interpretada con y sin signo. `x6=0xffffffff` y `x7=1` distinguen SRAI de SRLI con los mismos operandos.

En **Todas las instrucciones**, `x23=6` registra las seis caídas al siguiente PC y `x24=0` confirma que se saltaron las instrucciones señuelo. Los enlaces de JAL y JALR quedan en `x25=0xbc` y `x27=0xc8`. Este es el estado final de referencia para comparar los cores.

```text
x0  = 0x00000000   x1  = 0x12345000   x2  = 0x00000004   x3  = 0x00000064
x4  = 0xfffffff9   x5  = 0x00000001   x6  = 0x00000000   x7  = 0x0000009b
x8  = 0x00000764   x9  = 0x000000f0   x10 = 0x00000640   x11 = 0x0000000f
x12 = 0xfffffffc   x13 = 0x0000005d   x14 = 0xffffff95   x15 = 0x000000c8
x16 = 0x00000001   x17 = 0x00000000   x18 = 0xffffff9d   x19 = 0x7ffffffc
x20 = 0xfffffffc   x21 = 0x000000f4   x22 = 0x00000060   x23 = 0x00000006
x24 = 0x00000000   x25 = 0x000000bc   x26 = 0x000000c0   x27 = 0x000000c8
x28 = 0x00000064   x29 = 0x00000000   x30 = 0x00000000   x31 = 0x00000000
pc  = 0x000000d4
```

### Errores de carga

Cada archivo contiene un ADDI válido antes de la instrucción defectuosa. Simics debe reportar un `ValueError` con el nombre del archivo y la línea 3 al intentar cargarlo. La prueba termina en ese diagnóstico, antes de ejecutar el programa.

| Programa | Qué comprueba | Diagnóstico esperado |
| --- | --- | --- |
| [01 · Registro fuera de rango](targets/rv32i/programs/atomic/negativas/01-registro-fuera-de-rango.txt) | Rechaza `x32`. El banco contiene `x0` a `x31`. | `Value 32 out of range [0, 31]` |
| [02 · Inmediato fuera de rango](targets/rv32i/programs/atomic/negativas/02-inmediato-fuera-de-rango.txt) | Rechaza `2048` en ADDI. El inmediato con signo usa 12 bits. | `Value 2048 out of range [-2048, 2047]` |
| [03 · Desplazamiento fuera de rango](targets/rv32i/programs/atomic/negativas/03-desplazamiento-fuera-de-rango.txt) | Rechaza un desplazamiento inmediato de 32 en SLLI. El campo admite 0 a 31. | `Value 32 out of range [0, 31]` |
| [04 · Offset impar](targets/rv32i/programs/atomic/negativas/04-offset-impar.txt) | Rechaza el offset `3` en BEQ. El formato B solo codifica offsets pares. | `Branch offset must be even: 3` |

### Errores de ejecución y caso de control

Los offsets pares del formato B o J pueden producir destinos que no son múltiplos de cuatro. Por eso los casos 05 a 07 pasan el cargador y ponen a prueba el core.

| Programa | Qué comprueba | Resultado esperado |
| --- | --- | --- |
| [05 · Branch desalineado](targets/rv32i/programs/atomic/negativas/05-branch-desalineado.txt) | BEQ se toma desde `0x04` hacia `0x06`. La instrucción siguiente queda sin ejecutar. | `unaligned instruction fetch`. PC `0x04`, `x1=5`, `x2=0`. **1 step, 2 cycles**. |
| [06 · JAL desalineado](targets/rv32i/programs/atomic/negativas/06-jal-desalineado.txt) | JAL intenta saltar a `0x06`. Comprueba que la detección ocurre antes de sobrescribir el enlace en `x5`. | `unaligned instruction fetch`. PC `0x04`, `x5=7`, `x2=0`. **1 step, 2 cycles**. |
| [07 · Branch no tomado](targets/rv32i/programs/atomic/negativas/07-branch-no-tomado.txt) | BNE compara un registro consigo mismo y continúa por `0x08`, aunque el destino codificado sea `0x06`. | Parada en `ebreak`. PC `0x0c`, `x1=5`, `x2=9`. **4 steps, 4 cycles**. |
| [08 · Palabra ilegal](targets/rv32i/programs/atomic/negativas/08-palabra-ilegal.txt) | Con la inyección indicada abajo, el decodificador encuentra una palabra con el opcode y funct3 de SLLI, pero con funct7 inválido. | `illegal or unsupported instruction 0x02101113 at 0x00000004`. PC `0x04`, `x1=5`, `x2=0`. **1 step, 2 cycles**. |
| [09 · Fuera de RAM](targets/rv32i/programs/atomic/negativas/09-fuera-de-ram.txt) | JAL fija el PC en `0x10`. Con 16 bytes de RAM, la lectura siguiente falla. | `instruction fetch failed`. PC `0x10`, `x1=5`, `x2=0`. **2 steps, 3 cycles**. |

Para el **caso 08**, sustituye la instrucción en `0x04` en la CLI de Simics tras cargar el archivo y antes de ejecutar. El segundo comando debe mostrar `.word 0x02101113`.

```text
@SIM_write_phys_memory(conf.core0, 0x4, 0x02101113, 4)
disassemble 0x4 1
```

Para el **caso 09**, agrega `ram_size=0x10` al comando de arranque en PowerShell. Las cuatro palabras del programa ocupan toda la RAM desde `0x00` hasta `0x0f`. El JAL se completa y el siguiente ciclo es el que falla.

### Resultados observados

En Simics 7, los cinco programas positivos terminaron en el PC esperado con los registros y contadores indicados. Los cuatro archivos inválidos fueron rechazados en la línea 3. Los cinco casos de ejecución coincidieron con el diagnóstico, los registros y los contadores de la tabla, incluido el caso 07 que terminó normalmente.

## Pipeline

Pendiente de rellenar cuando se implemente y verifique la Parte 2.
