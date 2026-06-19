# Windows convenience runner -- equivalent to `make test`.
# Use this if you don't have GNU make on PATH. Requires iverilog at
# C:\iverilog\bin and python on PATH.
#
# Usage:
#   .\run.ps1                # build + run + validate
#   .\run.ps1 build          # build only
#   .\run.ps1 run            # run existing build
#   .\run.ps1 validate       # validate existing output
#   .\run.ps1 clean          # remove build artefacts
#   .\run.ps1 luts           # regenerate LUTs + golden vector
#   .\run.ps1 regress        # randomized regression vs bit-accurate model
#   .\run.ps1 synth          # sv2v + Yosys synthesis report

param([string]$target = "test")

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    $env:PATH = "C:\iverilog\bin;C:\iverilog\gtkwave\bin;" + $env:PATH
}

$src = Get-ChildItem src\*.v | ForEach-Object { $_.FullName }
$tb  = "tb\top_level_tb.v"
$out = "sim\top_sim"

function Build {
    if (-not (Test-Path sim)) { New-Item -ItemType Directory sim | Out-Null }
    Write-Host "[build] iverilog -g2012 -o $out src\*.v $tb"
    & iverilog -g2012 -o $out @src $tb
    if ($LASTEXITCODE -ne 0) { throw "iverilog build failed" }
}

function Run {
    Write-Host "[run] vvp $out"
    & vvp $out
    if ($LASTEXITCODE -ne 0) { throw "simulation failed" }
}

function Validate {
    Write-Host "[validate] python validate.py"
    & python validate.py
    if ($LASTEXITCODE -ne 0) { throw "validation failed" }
}

function Luts {
    & python scripts\gen_luts.py
    & python scripts\gen_golden.py
}

function Regress {
    & python scripts\regress.py --runs 20 --range 3
    if ($LASTEXITCODE -ne 0) { throw "regression failed" }
    & python scripts\regress.py --runs 20 --range 3 --parallel
    if ($LASTEXITCODE -ne 0) { throw "regression (parallel) failed" }
}

function Synth {
    # needs sv2v on PATH (or set $env:SV2V) and pip-installed yowasp-yosys
    $sv2v = if ($env:SV2V) { $env:SV2V } else { "sv2v" }
    $src = Get-ChildItem src\*.v | ForEach-Object { $_.FullName }
    & $sv2v @src | Out-File -Encoding ascii sim\design_flat.v
    if ($LASTEXITCODE -ne 0) { throw "sv2v failed" }
    python -c "import yowasp_yosys, sys; sys.exit(yowasp_yosys.run_yosys(['-p', 'read_verilog sim/design_flat.v; synth -top top_level -flatten; stat; ltp -noff']))"
    if ($LASTEXITCODE -ne 0) { throw "yosys failed" }
}

function Clean {
    Remove-Item -Force sim\*_sim, sim\top_sim, sim\attention.vcd, data\output.txt -ErrorAction SilentlyContinue
}

switch ($target) {
    "build"    { Build }
    "run"      { Run }
    "validate" { Validate }
    "luts"     { Luts }
    "regress"  { Regress }
    "synth"    { Synth }
    "clean"    { Clean }
    "test"     { Build; Run; Validate }
    default    { Write-Host "Unknown target: $target. Use build|run|validate|luts|regress|synth|clean|test." }
}
