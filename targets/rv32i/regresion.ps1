# Regresion completa de los cores RV32I (monociclo y pipeline).
#
# Corre cada programa de regresion-esperado.csv en tres modos, cada uno en una
# sesion nueva de Simics (targets/rv32i/regresion.simics):
#   1. monociclo (rv32-atomic)
#   2. pipeline con interlock   (forwarding = 0)
#   3. pipeline con forwarding  (forwarding = 1)
# Para cada programa compara registros, PC, steps y motivo de parada del
# pipeline contra el monociclo, y los ciclos contra el CSV. Luego revisa las
# trazas de stall, forwarding y flush y los cuatro errores de carga.
#
# Uso, desde la raiz del proyecto Simics (despues de bin\make.bat para ambos
# modulos):
#   .\targets\rv32i\regresion.ps1
#   .\targets\rv32i\regresion.ps1 -Filtro "^h0[1-5]"     # solo algunos casos
#   .\targets\rv32i\regresion.ps1 -Simics "C:\ruta\simics.bat"
#
# Deja en regresion-salida\ la salida completa de cada corrida y el resumen
# en regresion-salida\resultados.md.

param(
    [string]$Simics = ".\simics.bat",
    [string]$Filtro = "",
    [string]$Salida = "regresion-salida"
)

$raiz = "targets/rv32i"
$esperado = Import-Csv "$raiz/regresion-esperado.csv"
New-Item -ItemType Directory -Force -Path $Salida | Out-Null

# Corre una sesion de Simics y devuelve toda su salida como texto. El "quit"
# por la entrada estandar evita que la prueba se quede esperando en el prompt
# si el script falla antes de llegar a su propio quit.
function Ejecutar([string]$modelo, [int]$fwd, [string]$ruta, [string]$extras, [int]$log, [string]$archivo) {
    $argumentos = @("$raiz/regresion.simics", "core_kind=$modelo", "forwarding=$fwd",
                    "log_level=$log", "program=$raiz/programs/$ruta")
    if ($extras) { $argumentos += $extras.Split(" ") }
    $texto = ("quit" | & $Simics @argumentos 2>&1 | Out-String)
    if ($archivo) { Set-Content -Path (Join-Path $Salida $archivo) -Value $texto -Encoding UTF8 }
    return $texto
}

# Extrae de la salida de Simics los registros, el PC, steps, cycles y el
# motivo de parada.
function Leer([string]$texto) {
    $regs = @{}
    foreach ($m in [regex]::Matches($texto, '\bx(\d+)\s*=\s*0x([0-9a-fA-F]{8})')) {
        $regs[[int]$m.Groups[1].Value] = $m.Groups[2].Value.ToLower()
    }
    $lista = @()
    foreach ($n in 0..31) {
        if ($regs.ContainsKey($n)) { $lista += $regs[$n] } else { $lista += "?" }
    }

    $pc = "?"
    $pcs = [regex]::Matches($texto, '\bpc\s*=\s*0x([0-9a-fA-F]{8})')
    if ($pcs.Count -gt 0) { $pc = "0x" + $pcs[$pcs.Count - 1].Groups[1].Value.ToLower() }

    # Fila de ptime: | cosim0 | steps | cycles | time |
    $steps = -1
    $ciclos = -1
    $t = [regex]::Match($texto, 'cosim0\s*[^\d\s]+\s*(\d+)\s*[^\d\s]+\s*(\d+)\s*[^\d\s]+\s*\d+\.\d+')
    if ($t.Success) {
        $steps = [int]$t.Groups[1].Value
        $ciclos = [int]$t.Groups[2].Value
    }

    $motivo = "?"
    $h = [regex]::Match($texto, 'halted at pc 0x[0-9a-fA-F]+: ([^\r\n]+)')
    if ($h.Success) {
        $motivo = $h.Groups[1].Value.Trim()
    } elseif ($texto -match 'illegal or unsupported instruction') {
        $motivo = "illegal instruction"
    }

    return [pscustomobject]@{
        Registros = ($lista -join " "); Pc = $pc; Steps = $steps; Ciclos = $ciclos; Motivo = $motivo
    }
}

$filas = @()
$fallos = 0

# ---------------------------------------------------------------------------
# 1. Regresion de estado y ciclos
# ---------------------------------------------------------------------------
Write-Host ("{0,-26} {1,5} {2,6} {3,6} {4,6}  {5}" -f "programa", "steps", "mono", "ilock", "fwd", "estado")
$filas += "| Programa | Steps | Ciclos monociclo | Ciclos interlock | Ciclos forwarding | Estado |"
$filas += "| --- | ---: | ---: | ---: | ---: | --- |"

foreach ($c in $esperado) {
    if ($Filtro -and ($c.nombre -notmatch $Filtro)) { continue }

    $a = Leer (Ejecutar "atomic" 0 $c.ruta $c.extras 1 "$($c.nombre)-monociclo.txt")
    $i = Leer (Ejecutar "pipeline" 0 $c.ruta $c.extras 1 "$($c.nombre)-interlock.txt")
    $f = Leer (Ejecutar "pipeline" 1 $c.ruta $c.extras 1 "$($c.nombre)-forwarding.txt")

    $problemas = @()
    $modos = @(
        @{ Nombre = "monociclo";  R = $a; Ciclos = [int]$c.ciclos_monociclo },
        @{ Nombre = "interlock";  R = $i; Ciclos = [int]$c.ciclos_interlock },
        @{ Nombre = "forwarding"; R = $f; Ciclos = [int]$c.ciclos_forwarding }
    )
    foreach ($modo in $modos) {
        $r = $modo.R
        if ($r.Pc -ne $c.pc)                { $problemas += "$($modo.Nombre): PC $($r.Pc) en vez de $($c.pc)" }
        if ($r.Steps -ne [int]$c.steps)     { $problemas += "$($modo.Nombre): $($r.Steps) steps en vez de $($c.steps)" }
        if ($r.Motivo -ne $c.motivo)        { $problemas += "$($modo.Nombre): parada '$($r.Motivo)' en vez de '$($c.motivo)'" }
        if ($r.Ciclos -ne $modo.Ciclos)     { $problemas += "$($modo.Nombre): $($r.Ciclos) cycles en vez de $($modo.Ciclos)" }
        if ($r.Registros -ne $a.Registros)  { $problemas += "$($modo.Nombre): registros distintos a los del monociclo" }
    }

    if ($problemas.Count -eq 0) { $estado = "OK" } else { $estado = "FALLA: " + ($problemas -join "; "); $fallos++ }
    Write-Host ("{0,-26} {1,5} {2,6} {3,6} {4,6}  {5}" -f $c.nombre, $a.Steps, $a.Ciclos, $i.Ciclos, $f.Ciclos, $estado)
    $filas += "| $($c.nombre) | $($a.Steps) | $($a.Ciclos) | $($i.Ciclos) | $($f.Ciclos) | $estado |"
}

# ---------------------------------------------------------------------------
# 2. Trazas de riesgos (log-level 3): cada caso exige y prohibe lineas.
# ---------------------------------------------------------------------------
$trazas = @(
    @{ Caso = "h01-raw-addi"; Fwd = 0; Debe = @('stall: 00000004 addi'); NoDebe = @('forward:') },
    @{ Caso = "h01-raw-addi"; Fwd = 1; Debe = @('forward: 00000004 x1 <- 0000000a \(EX/WB\)'); NoDebe = @('stall:') },
    @{ Caso = "h05-distancia-2"; Fwd = 0; Debe = @('halted at pc 0x0000000c: ebreak'); NoDebe = @('stall:') },
    @{ Caso = "h09-x0-sin-dependencia"; Fwd = 0; Debe = @('halted at pc 0x00000010: ebreak'); NoDebe = @('stall:') },
    @{ Caso = "h10-branch-tomado"; Fwd = 0; Debe = @('flush: salto de 00000008 a 00000014'); NoDebe = @('stall:') },
    @{ Caso = "h11-ebreak-descartado"; Fwd = 0; Debe = @('flush: salto de 00000008 a 00000014', 'halted at pc 0x00000018: ebreak'); NoDebe = @('halted at pc 0x0000000c') },
    @{ Caso = "h12-branch-no-tomado"; Fwd = 0; Debe = @('stall: 00000008 beq'); NoDebe = @('flush:') },
    @{ Caso = "01-arranque"; Fwd = 0; Debe = @('IF: 00000008 ID: 00000004 ebreak EX: 00000000 addi x1, x0, 5', 'WB: 00000004 ebreak'); NoDebe = @() },
    @{ Caso = "neg08-palabra-ilegal"; Fwd = 0; Debe = @('ID: 00000004 \.word 0x02101113', 'illegal or unsupported instruction 0x02101113 at 0x00000004'); NoDebe = @() },
    @{ Caso = "neg09-fuera-de-ram"; Fwd = 0; Debe = @('FETCH-FAIL', 'halted at pc 0x00000010: instruction fetch failed'); NoDebe = @() }
)

Write-Host ""
Write-Host "Trazas (log-level 3)"
$filas += ""
$filas += "| Traza | Forwarding | Estado |"
$filas += "| --- | ---: | --- |"

foreach ($t in $trazas) {
    if ($Filtro -and ($t.Caso -notmatch $Filtro)) { continue }
    $c = $esperado | Where-Object { $_.nombre -eq $t.Caso } | Select-Object -First 1
    $texto = Ejecutar "pipeline" $t.Fwd $c.ruta $c.extras 3 "traza-$($t.Caso)-fwd$($t.Fwd).txt"

    $problemas = @()
    foreach ($p in $t.Debe)   { if ($texto -notmatch $p) { $problemas += "falta '$p'" } }
    foreach ($p in $t.NoDebe) { if ($texto -match $p)    { $problemas += "sobra '$p'" } }

    if ($problemas.Count -eq 0) { $estado = "OK" } else { $estado = "FALLA: " + ($problemas -join "; "); $fallos++ }
    Write-Host ("{0,-26} fwd={1}  {2}" -f $t.Caso, $t.Fwd, $estado)
    $filas += "| $($t.Caso) | $($t.Fwd) | $estado |"
}

# ---------------------------------------------------------------------------
# 3. Errores de carga: los rechaza el cargador (el mismo en ambos cores).
# ---------------------------------------------------------------------------
$cargas = @(
    @{ Caso = "neg01-registro-fuera-de-rango"; Ruta = "atomic/negativas/01-registro-fuera-de-rango.txt"; Patron = 'at line 3: Value 32 out of range \[0, 31\]' },
    @{ Caso = "neg02-inmediato-fuera-de-rango"; Ruta = "atomic/negativas/02-inmediato-fuera-de-rango.txt"; Patron = 'at line 3: Value 2048 out of range \[-2048, 2047\]' },
    @{ Caso = "neg03-desplazamiento-fuera-de-rango"; Ruta = "atomic/negativas/03-desplazamiento-fuera-de-rango.txt"; Patron = 'at line 3: Value 32 out of range \[0, 31\]' },
    @{ Caso = "neg04-offset-impar"; Ruta = "atomic/negativas/04-offset-impar.txt"; Patron = 'at line 3: Branch offset must be even: 3' }
)

Write-Host ""
Write-Host "Errores de carga (pipeline)"
$filas += ""
$filas += "| Error de carga | Estado |"
$filas += "| --- | --- |"

foreach ($e in $cargas) {
    if ($Filtro -and ($e.Caso -notmatch $Filtro)) { continue }
    $texto = Ejecutar "pipeline" 0 $e.Ruta "" 1 "$($e.Caso).txt"
    if ($texto -match $e.Patron) { $estado = "OK" } else { $estado = "FALLA: no aparece '$($e.Patron)'"; $fallos++ }
    Write-Host ("{0,-36} {1}" -f $e.Caso, $estado)
    $filas += "| $($e.Caso) | $estado |"
}

Set-Content -Path (Join-Path $Salida "resultados.md") -Value $filas -Encoding UTF8
Write-Host ""
if ($fallos -eq 0) {
    Write-Host "Regresion completa: todo OK. Resumen en $Salida\resultados.md"
} else {
    Write-Host "Regresion con $fallos falla(s). Revisa $Salida\resultados.md y las salidas completas en $Salida\"
    exit 1
}
