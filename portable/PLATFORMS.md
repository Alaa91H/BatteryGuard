# Platform and architecture support

## Supported by the portable core

| System | Architectures checked | Backend | Runtime status |
| --- | --- | --- | --- |
| Windows 10/11 | x86, x64, ARM64 | PowerShell + WMI | Source/type-check only on this host; no linked binary here |
| Linux | x86, x64, ARMv7, ARM64 | `/sys/class/power_supply` | Source/type-check only; no Linux runtime available |
| macOS | Intel, Apple silicon | `pmset -g batt` | Source/type-check only; no macOS runtime available |

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
`power_supply` class. No distribution package is produced yet.

Some vendor kernels expose only a subset of the fields. The parser treats a
missing file as an unavailable measurement and fails only when neither
percentage nor voltage exists.

## What remains

- **Build/link:** this machine has no MSVC linker; Application Control blocks
  Cargo, GNU rustc and the available linkers. The library, tests and CLI
  type-check for all targets, but no actual executable was linked here.
- **Runtime:** Windows WMI, Linux sysfs and macOS `pmset` parsers have fixture
  tests in source. Those tests require a linker and a host/target runtime and
  have not executed here.
- **Installers:** no `.msi`/Inno Setup, `.deb`, `.rpm`, Arch package, AppImage,
  Flatpak, `.pkg` or `.dmg` is included yet.
- **Widgets/UI:** the existing Windows tray is the only graphical interface.
  Linux and macOS have no widget, tray or menu-bar UI in this phase.
- **Charge control:** read-only. The Windows C# HP controller remains the only
  firmware writer.

Do not treat this matrix as a claim that Linux or macOS was run. It is a
compile-time support matrix plus parser tests awaiting a linked test run.
