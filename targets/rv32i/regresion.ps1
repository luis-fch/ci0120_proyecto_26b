# Regression suite for the atomic and pipelined RV32I cores.
#
# Compare architectural state against the atomic core and cycle counts
# against the CSV. Run each case in a fresh Simics session for the atomic
# core and for the pipeline with and without forwarding.
#
# Run from the Simics project directory after building both modules:
#   .\targets\rv32i\regresion.ps1
#   .\targets\rv32i\regresion.ps1 -Filtro "^h0[1-5]"
#   .\targets\rv32i\regresion.ps1 -Simics "C:\path\simics.bat"

param(
    [string]$Simics = ".\simics.bat",
    [string]$Filtro = "",
    [string]$Salida = "regresion-salida"
)

$raiz = "targets/rv32i"
$esperado = Import-Csv "$raiz/regresion-esperado.csv"
New-Item -ItemType Directory -Force -Path $Salida | Out-Null

# Send "quit" on stdin in case the script fails before its own quit.
function Ejecutar([string]$modelo, [int]$fwd, [string]$ruta, [string]$extras, [int]$log, [string]$archivo) {
    $argumentos = @("$raiz/regresion.simics", "core_kind=$modelo", "forwarding=$fwd",
                    "log_level=$log", "program=$raiz/programs/$ruta")
    if ($extras) { $argumentos += $extras.Split(" ") }
    $texto = ("quit" | & $Simics @argumentos 2>&1 | Out-String)
    if ($archivo) { Set-Content -Path (Join-Path $Salida $archivo) -Value $texto -Encoding UTF8 }
    return $texto
}

# Parse the register dump, PC, counters and stop reason from Simics output.
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

    # ptime row: | cosim0 | steps | cycles | time |
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
        Registros = ($lista -join " "); RegistrosCompletos = ($regs.Count -eq 32)
        Pc = $pc; Steps = $steps; Ciclos = $ciclos; Motivo = $motivo
        X1 = $regs[1]; X2 = $regs[2]
        RamAntes = [regex]::Match($texto, '(?m)^RAM-BEFORE ([a-f0-9]+)\s*$').Groups[1].Value
        RamDespues = [regex]::Match($texto, '(?m)^RAM-AFTER ([a-f0-9]+)\s*$').Groups[1].Value
    }
}

$filas = @()
$filasRam = @()
$fallos = 0
$checks = 0

# 1. Architectural state and cycle counts
Write-Host ("{0,-26} {1,5} {2,6} {3,6} {4,6}  {5}" -f "programa", "steps", "mono", "ilock", "fwd", "estado")
$filas += "| Programa | Steps | Ciclos monociclo | Ciclos interlock | Ciclos forwarding | Estado |"
$filas += "| --- | ---: | ---: | ---: | ---: | --- |"

foreach ($c in $esperado) {
    if ($Filtro -and ($c.nombre -notmatch $Filtro)) { continue }
    $checks++
    $ramBytes = [int][regex]::Match($c.extras, '\bverify_ram_bytes=(\d+)').Groups[1].Value

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
        if (!$r.RegistrosCompletos)        { $problemas += "$($modo.Nombre): faltan registros de pregs" }
        if ($r.Registros -ne $a.Registros)  { $problemas += "$($modo.Nombre): registros distintos a los del monociclo" }
        if ($c.registros_esperados -and $r.Registros -ne $c.registros_esperados) {
            $problemas += "$($modo.Nombre): registros distintos a los esperados"
        }
    }

    if ($ramBytes -gt 0) {
        foreach ($modo in $modos) {
            $r = $modo.R
            $ramOk = $r.RamAntes.Length -eq (2 * $ramBytes) -and $r.RamDespues -eq $r.RamAntes -and
                     $r.RamAntes -eq $a.RamAntes -and (!$c.ram_esperada -or $r.RamAntes -eq $c.ram_esperada)
            if (!$ramOk) {
                $problemas += "$($modo.Nombre): RAM ausente o distinta de la esperada"
            }
            $byteCount = $r.RamDespues.Length / 2
            # The full image stays in the session log. Show short images in the report.
            $ram = if ($byteCount -le 16) { $r.RamDespues } else { "$byteCount bytes" }
            $filasRam += "| $($c.nombre) | $($modo.Nombre) | $ram | $(if ($ramOk) {'OK'} else {'FALLA'}) |"
        }
    }

    if ($problemas.Count -eq 0) { $estado = "OK" } else { $estado = "FALLA: " + ($problemas -join "; "); $fallos++ }
    Write-Host ("{0,-26} {1,5} {2,6} {3,6} {4,6}  {5}" -f $c.nombre, $a.Steps, $a.Ciclos, $i.Ciclos, $f.Ciclos, $estado)
    $filas += "| $($c.nombre) | $($a.Steps) | $($a.Ciclos) | $($i.Ciclos) | $($f.Ciclos) | $estado |"
}

if ($filasRam.Count -gt 0) {
    $filas += "", "| Programa | Modo | RAM final | Carga y conservación |", "| --- | --- | --- | --- |"
    $filas += $filasRam
}

# 2. Required and forbidden messages in level 3 traces
$trazas = @(
    @{ Caso = "h01-raw-addi"; Fwd = 0; Debe = @('stall: 00000004 addi'); NoDebe = @('forward:') },
    @{ Caso = "h01-raw-addi"; Fwd = 1; Debe = @('forward: 00000004 x1 <- 0000000a \(EX/WB\)'); NoDebe = @('stall:') },
    @{ Caso = "h05-distancia-2"; Fwd = 0; Debe = @('halted at pc 0x0000000c: ebreak'); NoDebe = @('stall:') },
    @{ Caso = "h09-x0-sin-dependencia"; Fwd = 0; Debe = @('halted at pc 0x00000010: ebreak'); NoDebe = @('stall:') },
    @{ Caso = "h10-branch-tomado"; Fwd = 0; Debe = @('flush: redirect from 00000008 to 00000014'); NoDebe = @('stall:') },
    @{ Caso = "h11-ebreak-descartado"; Fwd = 0; Debe = @('flush: redirect from 00000008 to 00000014', 'halted at pc 0x00000018: ebreak'); NoDebe = @('halted at pc 0x0000000c') },
    @{ Caso = "h12-branch-no-tomado"; Fwd = 0; Debe = @('stall: 00000008 beq'); NoDebe = @('flush:') },
    @{ Caso = "01-arranque"; Fwd = 0; Debe = @('IF: 00000008 ID: 00000004 ebreak EX: 00000000 addi x1, x0, 5', 'WB: 00000004 ebreak'); NoDebe = @() },
    @{ Caso = "neg08-palabra-ilegal"; Fwd = 0; Debe = @('ID: 00000004 \.word 0x02101113', 'illegal or unsupported instruction 0x02101113 at 0x00000004'); NoDebe = @() },
    @{ Caso = "neg09-fuera-de-ram"; Fwd = 0; Debe = @('FETCH-FAIL', 'halted at pc 0x00000010: instruction fetch failed'); NoDebe = @() },
    @{ Caso = "01-arranque@ram-end"; Fwd = 0; Debe = @('WB: 00000004 ebreak'); NoDebe = @('FETCH-FAIL', 'fetch error') },
    @{ Caso = "neg10-pc-inicial-desalineado"; Fwd = 0; Debe = @('ID: 00000002 MISALIGNED', 'halted at pc 0x00000002: unaligned instruction fetch'); NoDebe = @('WB: 00000002 ebreak') },
    @{ Caso = "h13-fetch-descartado"; Fwd = 0; Debe = @('ID: 0000000c FETCH-FAIL EX: 00000008 jal x0, -4', 'halted at pc 0x00000004: ebreak'); NoDebe = @('halted at pc 0x0000000c', 'WB: 0000000c FETCH-FAIL') }
)

Write-Host ""
Write-Host "Trazas (log-level 3)"
$filas += ""
$filas += "| Traza | Forwarding | Estado |"
$filas += "| --- | ---: | --- |"

foreach ($t in $trazas) {
    if ($Filtro -and ($t.Caso -notmatch $Filtro)) { continue }
    $checks++
    $c = $esperado | Where-Object { $_.nombre -eq $t.Caso } | Select-Object -First 1
    $texto = Ejecutar "pipeline" $t.Fwd $c.ruta $c.extras 3 "traza-$($t.Caso)-fwd$($t.Fwd).txt"

    $problemas = @()
    foreach ($p in $t.Debe)   { if ($texto -notmatch $p) { $problemas += "falta '$p'" } }
    foreach ($p in $t.NoDebe) { if ($texto -match $p)    { $problemas += "sobra '$p'" } }

    if ($problemas.Count -eq 0) { $estado = "OK" } else { $estado = "FALLA: " + ($problemas -join "; "); $fallos++ }
    Write-Host ("{0,-26} fwd={1}  {2}" -f $t.Caso, $t.Fwd, $estado)
    $filas += "| $($t.Caso) | $($t.Fwd) | $estado |"
}

# 3. Change mode with a dependent instruction in flight.
$switchCase = "h01-cambio-forwarding"
if (!$Filtro -or $switchCase -match $Filtro) {
    $checks++
    $result = Leer (Ejecutar "pipeline" 1 "pipeline/h01-raw-addi.txt" "switch_at_cycle=3" 3 "$switchCase.txt")
    $observed = "x1=$($result.X1), x2=$($result.X2), PC=$($result.Pc), $($result.Steps) steps, $($result.Ciclos) cycles, $($result.Motivo)"
    if ($result.RegistrosCompletos -and $result.X1 -eq "0000000a" -and $result.X2 -eq "0000000f" -and
        $result.Pc -eq "0x00000008" -and $result.Steps -eq 3 -and $result.Ciclos -eq 10 -and $result.Motivo -eq "ebreak") {
        $estado = "OK"
    } else {
        $estado = "FALLA"
        $fallos++
    }
    Write-Host "`n${switchCase}: $estado ($observed)"
    $filas += "", "| Cambio de modo | Estado esperado | Estado observado | Resultado |",
              "| --- | --- | --- | --- |",
              "| $switchCase | x1=0000000a, x2=0000000f, PC=0x00000008, 3 steps, 10 cycles, ebreak | $observed | $estado |"
}

# 4. Check that both loaders reject invalid programs.
$cargas = @(
    @{ Caso = "neg01-registro-fuera-de-rango"; Ruta = "atomic/negativas/01-registro-fuera-de-rango.txt"; Patron = 'at line 3: Value 32 out of range \[0, 31\]' },
    @{ Caso = "neg02-inmediato-fuera-de-rango"; Ruta = "atomic/negativas/02-inmediato-fuera-de-rango.txt"; Patron = 'at line 3: Value 2048 out of range \[-2048, 2047\]' },
    @{ Caso = "neg03-desplazamiento-fuera-de-rango"; Ruta = "atomic/negativas/03-desplazamiento-fuera-de-rango.txt"; Patron = 'at line 3: Value 32 out of range \[0, 31\]' },
    @{ Caso = "neg04-offset-impar"; Ruta = "atomic/negativas/04-offset-impar.txt"; Patron = 'at line 3: Branch offset must be even: 3' }
)

Write-Host ""
Write-Host "Errores de carga"
$filas += ""
$filas += "| Error de carga | Core | Estado |"
$filas += "| --- | --- | --- |"

foreach ($e in $cargas) {
    if ($Filtro -and ($e.Caso -notmatch $Filtro)) { continue }
    foreach ($core in @("atomic", "pipeline")) {
        $checks++
        $texto = Ejecutar $core 0 $e.Ruta "" 1 "$($e.Caso)-$core.txt"
        if ($texto -match $e.Patron -and $texto -notmatch 'REGRESION core=') {
            $estado = "OK"
        } else {
            $estado = "FALLA: el cargador no detuvo el script con el diagnostico esperado"
            $fallos++
        }
        Write-Host ("{0,-36} {1,-8} {2}" -f $e.Caso, $core, $estado)
        $filas += "| $($e.Caso) | $core | $estado |"
    }
}

if ($checks -eq 0) {
    Write-Error "Ningun caso coincide con -Filtro '$Filtro'."
    exit 1
}

Set-Content -Path (Join-Path $Salida "resultados.md") -Value $filas -Encoding UTF8
Write-Host ""
if ($fallos -eq 0) {
    Write-Host "Regresion completa: todo OK. Resumen en $Salida\resultados.md"
} else {
    Write-Host "Regresion con $fallos falla(s). Revisa $Salida\resultados.md y las salidas completas en $Salida\"
    exit 1
}
