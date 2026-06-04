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

function Clean {
    Remove-Item -Force sim\*_sim, sim\top_sim, sim\attention.vcd, data\output.txt -ErrorAction SilentlyContinue
}

switch ($target) {
    "build"    { Build }
    "run"      { Run }
    "validate" { Validate }
    "luts"     { Luts }
    "clean"    { Clean }
    "test"     { Build; Run; Validate }
    default    { Write-Host "Unknown target: $target. Use build|run|validate|luts|clean|test." }
}
