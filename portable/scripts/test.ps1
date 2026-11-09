[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'target'
New-Item -ItemType Directory -Force -Path $target | Out-Null
$rustc = (Get-Command rustc.exe -ErrorAction Stop).Source
$testExe = Join-Path $target 'batteryguard_core_tests.exe'

& $rustc '--edition=2021' '--test' (Join-Path $root 'src\lib.rs') '-o' $testExe
if ($LASTEXITCODE -ne 0) { throw "rustc test build failed with exit code $LASTEXITCODE" }

& $testExe
if ($LASTEXITCODE -ne 0) { throw "portable core tests failed with exit code $LASTEXITCODE" }
