# Estado del proyecto RV32I

Las dos partes están implementadas. El core monociclo sirve como referencia
del estado arquitectónico; el pipeline añade interlock y forwarding sin
ampliar el subconjunto de instrucciones.

| Área | Implementación y comprobación |
| --- | --- |
| Carga y decodificación | Cada módulo tiene su `txt_loader.py`. [CONVENTIONS.md](CONVENTIONS.md) define el formato de entrada común. |
| Estado y etapas | `modules/rv32-pipeline/rv32-core.h` define IF/ID, ID/EX y EX/WB. `execute()` en `rv32-pipeline.c` avanza un ciclo y confirma los efectos en WB. |
| Dependencias RAW | El interlock mantiene la instrucción consumidora en ID; el modo opcional toma el operando de EX/WB. Las pruebas H01–H09 cubren ambas rutas. |
| Saltos y paradas | EX redirige la extracción y descarta el camino anterior. WB confirma `ebreak` y los fallos en orden. H10–H12 y las pruebas negativas cubren estos casos. |
| Verificación | [PRUEBAS.md](PRUEBAS.md) contiene entradas, estados esperados y resultados observados. El [reporte final](docs/reporte_final_rv32i.md) documenta ambos diseños. |

Para cualquier cambio que afecte a la ejecución, compila los dos módulos y
ejecuta la regresión descrita en [README.md](README.md#regression).
