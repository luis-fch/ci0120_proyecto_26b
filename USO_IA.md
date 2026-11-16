# Uso de inteligencia artificial en el proyecto

Usamos distintos modelos de agentes (GPT-6.1 Sol) como guía para aprender y resolver dudas durante la implementación de los cores RV32I en Simics. En la Parte 1, el trabajo se organizó en pasos pequeños con ejemplos de código y comprobaciones que podíamos ejecutar después de cada cambio. Consultamos cómo se codifican las instrucciones, cómo se extraen sus campos y cuándo se debe extender el signo de un inmediato. La guía y las explicaciones nos sirvieron para entender el código y aplicarlo al core monociclo.

## Aportes incorporados a la entrega

| Parte del proyecto | Uso de Codex | Resultado e incorporación |
| --- | --- | --- |
| Core monociclo | Elaborar una guía de implementación y explicar el cargador, la decodificación y el uso de Simics con ejemplos concretos. | Usamos las explicaciones durante la implementación. Por ejemplo, conservamos la conversión con signo de los inmediatos de 12 bits y usamos la cantidad de desplazamiento como un campo sin signo. |
| Programas de prueba | Proponer y escribir casos de entrada inválida, fallos de ejecución y casos de control. | Incorporamos programas que comprueban el rechazo de operandos inválidos, la alineación de saltos y los fallos de extracción. Un caso con un branch no tomado comprueba que el core continúa aunque el destino codificado esté desalineado. |
| Revisión del pipeline | Revisar la implementación de cuatro etapas escrita por un integrante del equipo y ayudar a corregir casos límite. | Incorporamos correcciones para un PC inicial desalineado, un `ebreak` al final de la RAM y un cambio de forwarding con instrucciones en curso. Añadimos pruebas para reproducir estos casos. |
| Script de regresión | Ampliar los scripts de regresión existentes para automatizar más comprobaciones en Simics. | La versión de la entrega ejecuta los casos en monociclo, pipeline con interlock y pipeline con forwarding. Compara registros, PC, motivo de parada, pasos y ciclos. En los casos seleccionados también compara la RAM de instrucciones antes y después de ejecutar. |
| Documentación | Ayudar a redactar y revisar el catálogo de pruebas, el reporte final y esta declaración. Escribir y ajustar los diagramas en formato SVG a partir del código. | Incorporamos los diagramas editables, las descripciones de los diseños, los planes de verificación y los resultados. |

## Verificación de los resultados

Contrastamos las propuestas con el enunciado, el código y el formato de ensamblador del proyecto. Para los casos de prueba definimos el estado esperado y lo comparamos con los resultados de Simics. Por ejemplo, en un JAL desalineado comprobamos que se conserve el registro de enlace y que la instrucción fallida no sume un paso. En `all-instructions.txt` verificamos los 32 registros frente al estado esperado y comparamos los 216 bytes cargados antes y después de ejecutar en los tres modos.

La evidencia de la entrega procede de ejecuciones reales de Simics 7. La regresión final completó 112 sesiones sin fallos de verificación. Codex ayudó a escribir el código de prueba y a documentar las salidas observadas. [Formato del ensamblador](CONVENTIONS.md) · [Resultados de Simics](docs/evidencia/regresion-simics7.md)

## Ejemplos de las conversaciones

**Consulta sobre un inmediato con signo**

> **Prompt:** Is it really necessary to use signed_value here?

**Respuesta de Codex, resumida en español.** La extracción devuelve un valor entre 0 y 4095. El patrón de 12 bits `0xfff` representa `-1` en una instrucción como `addi x1, x0, -1`. Pasar el valor extraído a un `int64` conservaría el valor positivo 4095. La conversión interpreta el bit de signo y obtiene el valor correcto.

**Uso en el proyecto.** La explicación sirvió para confirmar la conversión que ya hacía el decodificador. [Implementación](modules/rv32-atomic/rv32-atomic.c)

**Solicitud de pruebas de error**

> **Prompt (fragmento):** Solo me gustaría tener algunos programas de prueba que sirvan para probar intencionalmente cuando hay algún error y así estar seguros de que sí están siendo tomados en cuenta.

> **Respuesta de Codex (fragmento):** La prueba de JAL desalineado comprueba algo más que el mensaje de error. `x5` debe conservar su valor anterior, el PC debe quedarse en el JAL y `ptime` debe mostrar **1 step y 2 cycles**.

**Uso en el proyecto.** Incorporamos el programa y su estado esperado a las pruebas dirigidas. El caso también se ejecuta en ambos modos del pipeline y se compara con el monociclo. [Pruebas de error](targets/rv32i/programs/atomic/negativas/README.md)
