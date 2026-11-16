# Regresión en Simics 7

Ejecutada el 16 de noviembre de 2026 con Intel Simics 7 (build 7214 win64).
La matriz compara los 32 registros de ambos modos del pipeline con los
del monociclo. Para cada modo también contrasta el PC, los steps, los
ciclos y el motivo de parada con el CSV. Los casos con un estado de
registros de referencia lo comprueban en los tres modos.

La tabla de RAM comprueba los bytes cargados antes y después de ejecutar,
y su igualdad entre modos. Para los dos casos de arranque también se
comprueba la codificación literal `9300500073001000`. Los volcados
completos quedan en las salidas individuales.

```powershell
.\bin\make.bat rv32-atomic rv32-pipeline
.\targets\rv32i\regresion.ps1 -Salida regresion-entrega-simics7
```

30 casos de la matriz × 3 modos, 13 trazas, 1 cambio de modo y 8
comprobaciones de carga. Las 112 sesiones de Simics pasaron.

| Programa | Steps | Ciclos monociclo | Ciclos interlock | Ciclos forwarding | Estado |
| --- | ---: | ---: | ---: | ---: | --- |
| 01-arranque | 2 | 2 | 5 | 5 | OK |
| 02-alu-limites | 12 | 12 | 18 | 15 | OK |
| 03-bucle | 9 | 9 | 20 | 16 | OK |
| 04-enlace | 5 | 5 | 13 | 12 | OK |
| all-instructions | 46 | 46 | 67 | 65 | OK |
| neg05-branch-desalineado | 1 | 2 | 6 | 5 | OK |
| neg06-jal-desalineado | 1 | 2 | 5 | 5 | OK |
| neg07-branch-no-tomado | 4 | 4 | 8 | 7 | OK |
| neg08-palabra-ilegal | 1 | 2 | 5 | 5 | OK |
| neg09-fuera-de-ram | 2 | 3 | 8 | 8 | OK |
| h01-raw-addi | 3 | 3 | 7 | 6 | OK |
| h02-raw-add-sub | 5 | 5 | 10 | 8 | OK |
| h03-raw-rs2 | 4 | 4 | 8 | 7 | OK |
| h04-mismo-registro | 5 | 5 | 11 | 8 | OK |
| h05-distancia-2 | 4 | 4 | 7 | 7 | OK |
| h06-branch-dependiente | 5 | 5 | 12 | 10 | OK |
| h07-jalr-dependiente | 4 | 4 | 10 | 9 | OK |
| h08-dos-operandos | 3 | 3 | 7 | 6 | OK |
| h09-x0-sin-dependencia | 5 | 5 | 8 | 8 | OK |
| h10-branch-tomado | 5 | 5 | 10 | 10 | OK |
| h11-ebreak-descartado | 5 | 5 | 10 | 10 | OK |
| h12-branch-no-tomado | 6 | 6 | 10 | 9 | OK |
| p01-independientes | 25 | 25 | 28 | 28 | OK |
| 01-arranque@0x100 | 2 | 2 | 5 | 5 | OK |
| 03-bucle@0x100 | 9 | 9 | 20 | 16 | OK |
| 04-enlace@0x100 | 5 | 5 | 13 | 12 | OK |
| h10-branch-tomado@0x100 | 5 | 5 | 10 | 10 | OK |
| 01-arranque@ram-end | 2 | 2 | 5 | 5 | OK |
| neg10-pc-inicial-desalineado | 0 | 1 | 4 | 4 | OK |
| h13-fetch-descartado | 3 | 3 | 10 | 10 | OK |

| Programa | Modo | RAM final | Carga y conservación |
| --- | --- | --- | --- |
| 01-arranque | monociclo | 9300500073001000 | OK |
| 01-arranque | interlock | 9300500073001000 | OK |
| 01-arranque | forwarding | 9300500073001000 | OK |
| all-instructions | monociclo | 216 bytes | OK |
| all-instructions | interlock | 216 bytes | OK |
| all-instructions | forwarding | 216 bytes | OK |
| 01-arranque@0x100 | monociclo | 9300500073001000 | OK |
| 01-arranque@0x100 | interlock | 9300500073001000 | OK |
| 01-arranque@0x100 | forwarding | 9300500073001000 | OK |
| h13-fetch-descartado | monociclo | 6f008000730010006ff0dfff | OK |
| h13-fetch-descartado | interlock | 6f008000730010006ff0dfff | OK |
| h13-fetch-descartado | forwarding | 6f008000730010006ff0dfff | OK |

| Traza | Forwarding | Estado |
| --- | ---: | --- |
| h01-raw-addi | 0 | OK |
| h01-raw-addi | 1 | OK |
| h05-distancia-2 | 0 | OK |
| h09-x0-sin-dependencia | 0 | OK |
| h10-branch-tomado | 0 | OK |
| h11-ebreak-descartado | 0 | OK |
| h12-branch-no-tomado | 0 | OK |
| 01-arranque | 0 | OK |
| neg08-palabra-ilegal | 0 | OK |
| neg09-fuera-de-ram | 0 | OK |
| 01-arranque@ram-end | 0 | OK |
| neg10-pc-inicial-desalineado | 0 | OK |
| h13-fetch-descartado | 0 | OK |

| Cambio de modo | Estado esperado | Estado observado | Resultado |
| --- | --- | --- | --- |
| h01-cambio-forwarding | x1=0000000a, x2=0000000f, PC=0x00000008, 3 steps, 10 cycles, ebreak | x1=0000000a, x2=0000000f, PC=0x00000008, 3 steps, 10 cycles, ebreak | OK |

| Error de carga | Core | Estado |
| --- | --- | --- |
| neg01-registro-fuera-de-rango | atomic | OK |
| neg01-registro-fuera-de-rango | pipeline | OK |
| neg02-inmediato-fuera-de-rango | atomic | OK |
| neg02-inmediato-fuera-de-rango | pipeline | OK |
| neg03-desplazamiento-fuera-de-rango | atomic | OK |
| neg03-desplazamiento-fuera-de-rango | pipeline | OK |
| neg04-offset-impar | atomic | OK |
| neg04-offset-impar | pipeline | OK |
