[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$targets = @(
    'x86_64-pc-windows-msvc',
    'i686-pc-windows-msvc',
    'aarch64-pc-windows-msvc',
    'x86_64-pc-windows-gnu',
    'i686-pc-windows-gnu',
    'aarch64-pc-windows-gnullvm',
    'x86_64-unknown-linux-gnu',
    'aarch64-unknown-linux-gnu',
    'i686-unknown-linux-gnu',
    'armv7-unknown-linux-gnueabihf',
    'x86_64-apple-darwin',
    'aarch64-apple-darwin'
)
$rustc = (Get-Command rustc.exe -ErrorAction Stop).Source
$failures = 0

foreach ($target in $targets) {
    $out = Join-Path $root "target/check-$target"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Write-Host "== $target =="

    & $rustc '--target' $target '--edition=2021' '--crate-name' 'batteryguard_core' `
        '--crate-type=lib' '--emit=metadata' (Join-Path $root 'src/lib.rs') '--out-dir' $out
    if ($LASTEXITCODE -ne 0) { $failures++; continue }

    & $rustc '--target' $target '--edition=2021' '--test' (Join-Path $root 'src/lib.rs') `
        '--emit=metadata' '-o' (Join-Path $out 'tests.rmeta')
    if ($LASTEXITCODE -ne 0) { $failures++; continue }

    & $rustc '--target' $target '--edition=2021' '--crate-name' 'batteryguard' `
        '--emit=metadata' '--extern' ('batteryguard_core=' + (Join-Path $out 'libbatteryguard_core.rmeta')) `
        (Join-Path $root 'src/main.rs') '-o' (Join-Path $out 'batteryguard.rmeta')
    if ($LASTEXITCODE -ne 0) { $failures++; continue }

    Write-Host 'ok'
}

if ($failures -ne 0) {
    throw "$failures of $($targets.Count) target checks failed"
}
Write-Host "checked $($targets.Count) targets (metadata only; no linker or runtime tests)"
