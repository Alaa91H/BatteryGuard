# Platform and architecture support

## Supported by the portable core

| System | Architectures checked | Backend | Runtime status |
| --- | --- | --- | --- |
| Windows 10/11 | x86, x64, ARM64 | PowerShell + WMI | Hosted CI tests and CLI smoke test; local host cannot link |
| Linux | x86, x64, ARMv7, ARM64 | `/sys/class/power_supply` | Hosted CI tests and CLI smoke test; no hardware battery |
| macOS | Intel, Apple silicon | `pmset -g batt` | Hosted CI tests and CLI smoke test; no hardware battery |

The 12 exact Rust targets that passed `rustc --emit=metadata` are:

| Target | Family |
| --- | --- |
| `x86_64-pc-windows-msvc` | Windows x64 |
| `i686-pc-windows-msvc` | Windows x86 |
| `aarch64-pc-windows-msvc` | Windows ARM64 |
| `x86_64-pc-windows-gnu` | Windows x64, GNU ABI |
| `i686-pc-windows-gnu` | Windows x86, GNU ABI |
| `aarch64-pc-windows-gnullvm` | Windows ARM64, LLVM/MinGW ABI |
| `x86_64-unknown-linux-gnu` | Linux x64 |
| `aarch64-unknown-linux-gnu` | Linux ARM64 |
| `i686-unknown-linux-gnu` | Linux x86 |
| `armv7-unknown-linux-gnueabihf` | Linux ARMv7 |
| `x86_64-apple-darwin` | macOS Intel |
| `aarch64-apple-darwin` | macOS Apple silicon |

This covers Intel, AMD, Apple silicon and Snapdragon X class CPUs through the
standard Rust targets. The backend code has no CPU-specific path.

## Linux distributions

The sysfs backend is distribution-independent. The same source is expected to
work on current Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, Linux
Mint, Pop!_OS, Manjaro, Kali and other distributions using the mainline
`power_supply` class. CI produces Debian and RPM packages and an AppImage for x64 and ARM64; the packages use a static musl binary and carry a GNU build-id.

Some vendor kernels expose only a subset of the fields. The parser treats a
missing file as an unavailable measurement and fails only when neither
percentage nor voltage exists.

## What remains

- **Local build/link:** this machine has no MSVC linker; Application Control
  blocks Cargo, GNU rustc and the available linkers. The library, tests and CLI
  type-check for all targets here, but no executable was linked locally. The
  hosted CI links and tests every runnable target.
- **Runtime hardware:** Windows WMI, Linux sysfs and macOS `pmset` parsers have
  fixture tests in source and ran on hosted CI, but no real battery reading was
  taken on Linux or macOS. Do not treat a hosted runner as hardware coverage.
- **Installers:** the current CI produces `.msi` (x86/x64/ARM64), `.deb`,
  `.rpm`, `.AppImage` (Linux x64/ARM64) and `.pkg` (macOS Intel/Apple silicon).
  Arch, Flatpak and `.dmg` are not produced.
- **Signing:** installers carry GitHub/Sigstore build provenance; Windows
  Authenticode and Apple notarization are not configured.
- **Widgets/UI:** the existing Windows tray is the only graphical interface.
  Linux and macOS have no widget, tray or menu-bar UI in this phase.
- **Charge control:** read-only. The Windows C# HP controller remains the only
  firmware writer.

Do not treat this matrix as a claim that a real Linux or macOS battery was
read. It is a support matrix backed by hosted builds and smoke tests, not
hardware validation.
