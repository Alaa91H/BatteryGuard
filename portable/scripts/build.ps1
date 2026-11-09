[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'target'
New-Item -ItemType Directory -Force -Path $target | Out-Null

$rustc = (Get-Command rustc.exe -ErrorAction Stop).Source

& $rustc '--edition=2021' '--crate-name' 'batteryguard_core' '--crate-type=lib' `
    (Join-Path $root 'src\lib.rs') '--out-dir' $target
if ($LASTEXITCODE -ne 0) { throw "rustc library build failed with exit code $LASTEXITCODE" }

$libraryItem = Get-ChildItem -Path $target -Filter '*.rlib' |
    Sort-Object LastWriteTime |
    Select-Object -Last 1
if (-not $libraryItem) { throw 'rustc did not produce a .rlib' }

$output = Join-Path $target 'batteryguard.exe'
& $rustc '--edition=2021' '--crate-name' 'batteryguard' `
    '-L' ('dependency=' + $target) `
    '--extern' ('batteryguard_core=' + $libraryItem.FullName) `
    (Join-Path $root 'src\main.rs') '-o' $output
if ($LASTEXITCODE -ne 0) { throw "rustc CLI build failed with exit code $LASTEXITCODE" }

$file = Get-Item $output
'built {0} ({1:N0} bytes)' -f $file.FullName, $file.Length
