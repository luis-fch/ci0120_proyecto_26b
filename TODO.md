# Parte 2 · Core RV32I con pipeline

La Parte 1 sirve como referencia de estado arquitectónico. El pipeline debe ejecutar el mismo subconjunto de [CONVENTIONS.md](CONVENTIONS.md), cargar los mismos programas y producir el mismo estado final. Los ciclos pueden variar por el llenado del pipeline, las esperas y los saltos. Los resultados del core de un ciclo están en [PRUEBAS.md](PRUEBAS.md).

## Antes de editar

- [ ] Confirmar cómo se cuentan las etapas. El enunciado pide cuatro y la diapositiva 3 de [Presentacion-rv32i.pdf](Presentacion-rv32i.pdf) menciona cinco. Usar como punto de partida cuatro etapas: **extracción → decodificación y lectura → ejecución → escritura**.
- [ ] Trabajar en [modules/rv32-pipeline/](modules/rv32-pipeline/) y usar [rv32-pipeline.simics](targets/rv32i/rv32-pipeline.simics) para ejecutarlo. Usar el módulo atómico y sus programas para comparar resultados.

## Qué se puede reutilizar

| Pieza de la Parte 1 | Cómo usarla en el pipeline |
| --- | --- |
| [`txt_loader.py`](modules/rv32-atomic/txt_loader.py) | Copiarlo a [`modules/rv32-pipeline/txt_loader.py`](modules/rv32-pipeline/txt_loader.py). El formato del ensamblador, las codificaciones y la carga en RAM son los mismos. |
| `fetch()` de [`rv32-atomic.c`](modules/rv32-atomic/rv32-atomic.c) | Reutilizar la lectura de cuatro bytes y la reconstrucción de la palabra. Invocarla con el PC de la etapa de extracción. |
| `instruction_t`, `bits()`, `signed_value()` y `decode()` | Reutilizarlos para decodificar la palabra que llegó de extracción. Guardar el PC original junto con la instrucción decodificada. |
| `alu()`, `arithmetic_right()` y `branch_taken()` | Reutilizar los cálculos en ejecución. Entregarles los operandos de esa instrucción cuando estén disponibles. |
| El `switch` de `execute()` | Reutilizar las fórmulas para resultado, destino y enlace. La etapa de ejecución prepara estos valores y la etapa de escritura aplica los efectos que correspondan. |
| `rv32_disassemble()` | Reutilizarlo junto con `decode()`. Sirve también para leer las trazas del pipeline. |
| [Helpers del pipeline](modules/rv32-pipeline/rv32-helpers.h) | Usar las funciones que ya trae el módulo para memoria, registros, paradas y contadores. Escribir mediante `reg_write_x()` para conservar `x0=0`. |
| [Programas y resultados del core atómico](PRUEBAS.md#atomic) | Usarlos como referencia de registros, PC y motivo de parada. Comparar también los steps de los programas que terminan normalmente. |

## Implementación pendiente

- [ ] **Definir el estado del pipeline.** En [`rv32-core.h`](modules/rv32-pipeline/rv32-core.h), agregar los registros entre etapas con una bandera `valid`, el PC de la instrucción y los datos que consume la etapa siguiente. Separar el próximo PC de extracción del PC arquitectónico que muestra Simics. Inicializar el estado vacío y arrancar desde el PC que establece el target, incluido un `load_address` distinto de cero.
- [ ] **Avanzar un ciclo.** En [`rv32-pipeline.c`](modules/rv32-pipeline/rv32-pipeline.c), hacer que `execute()` avance todas las etapas una vez por llamada. Para que una instrucción no atraviese dos etapas en el mismo ciclo, calcular el próximo estado a partir del estado al comienzo del ciclo y aplicarlo al final. Contar un cycle por llamada, incluso al llenar el pipeline o insertar esperas.
- [ ] **Implementar extracción y decodificación.** Leer la palabra de memoria, transportar su PC, llamar a `decode()` e identificar qué registros lee y escribe cada instrucción. Por ejemplo, LUI no lee operandos y JALR lee `rs1`.
- [ ] **Implementar ejecución y escritura.** Calcular los resultados de ALU y el control de flujo con los operandos y el PC de esa instrucción. Pasar a escritura el destino, el resultado y la señal de escritura. Contar un step al confirmar una instrucción válida, incluido `ebreak`.
- [ ] **Resolver dependencias de datos.** Como primera implementación, esperar en decodificación mientras una instrucción anterior vaya a escribir un registro fuente que se necesita. Mantener esa instrucción y la extracción en espera, insertar un hueco en ejecución y dejar que las instrucciones anteriores avancen. Ignorar escrituras a `x0` al detectar dependencias. Si se añade forwarding más adelante, verificar primero la versión con esperas.
- [ ] **Resolver saltos y branches.** Usar el PC de la instrucción que provoca el salto. Si cambia el flujo, redirigir la extracción e invalidar las instrucciones más jóvenes del camino anterior. Probar los destinos alineados y comprobar la alineación de un branch únicamente cuando se toma.
- [ ] **Manejar paradas en orden.** Distinguir `ebreak`, palabra ilegal, destino desalineado y fallo de extracción. Dejar que las instrucciones anteriores se completen y descartar las posteriores. Confirmar la parada solo cuando le corresponda a esa instrucción, para que un `ebreak` o fallo del camino descartado no detenga el programa. Conservar en el PC arquitectónico la dirección de la instrucción que causó la parada. Los fallos no cuentan como step.

## Verificación y reporte

- [ ] Compilar y arrancar el target del pipeline desde PowerShell. Usar un límite de ciclos durante la depuración.

  ```powershell
  .\bin\make.bat rv32-pipeline
  .\simics.bat targets\rv32i\rv32-pipeline.simics program=targets/rv32i/programs/atomic/01-arranque.txt
  ```

- [ ] Verificar cada etapa con casos dirigidos. Observar palabra y PC en extracción, campos y operandos en decodificación, resultado o destino en ejecución y registro, PC y steps en escritura.
- [ ] Verificar el sistema con los programas del core atómico. Cubrir las 30 instrucciones, el estado de registros y la memoria de instrucciones. Recoger `pregs`, `ptime` y, según el caso, `x` o `disassemble`.
- [ ] Crear programas específicos del pipeline para dependencias entre instrucciones consecutivas, dependencias en branches o JALR, uso de `x0`, saltos tomados y no tomados, descarte de una escritura o de un `ebreak` del camino anterior, y llenado y vaciado del pipeline.
- [ ] Completar la [sección Pipeline de PRUEBAS.md](PRUEBAS.md#pipeline) con los programas, el estado esperado, los resultados observados y los ciclos. Comparar con el core atómico usando el mismo programa y estado inicial.
- [ ] Completar el reporte final con ambos diseños, sus planes de verificación y los resultados. Incluir diagramas y evidencia de Simics. Para el core atómico, organizar la verificación por módulo. Para el pipeline, incluir verificación por etapa y del sistema completo, con una traza de una espera por dependencia y otra de un salto que descarta instrucciones.
