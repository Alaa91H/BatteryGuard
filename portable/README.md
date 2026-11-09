# BatteryGuard portable core

A dependency-free Rust core for reading battery state on Windows, Linux and
macOS. It is the first phase of the cross-platform BatteryGuard work. The
existing Windows tray application remains in `battery/` and is unchanged.

## Status

- **Source complete:** battery model, voltage/power formatting, charge/float
  policy, CLI, and read-only backends for Windows, Linux and macOS.
- **Cross-target type-check:** all 12 targets listed in
  [`PLATFORMS.md`](PLATFORMS.md) compile the library, test harness and CLI with
  `rustc --emit=metadata`.
- **Not yet executed here:** the MSVC linker is not installed on this machine,
  and Application Control blocks `cargo`, the GNU Rust compiler and the
  available `lld`/GNU linkers. As a result no linked `batteryguard.exe` and no
  test binary were produced on this host. The unit tests have therefore not
  run. Linux and macOS runtimes were not available either.
- **Read-only:** the portable backend does not write charge modes. Charge
  control remains limited to the native Windows HP controller.

This is intentionally honest about the boundary: the source and type-check
matrix are done, while linked binaries, installers and widgets are later work.

## What it provides

| Module | Responsibility |
| --- | --- |
| `src/model.rs` | Battery reading, derived power/health/minutes, error type and status text. |
| `src/format.rs` | `11.8 V · 6.5 W` and duration formatting. |
| `src/policy.rs` | Pure charge/float decision logic with the 13 Windows policy cases. |
| `src/platform/windows.rs` | Read-only PowerShell/WMI backend and parser. |
| `src/platform/linux.rs` | Read-only `/sys/class/power_supply` backend and parsers. |
| `src/platform/macos.rs` | Read-only `pmset -g batt` backend and parser. |
| `src/main.rs` | CLI with text, JSON and watch modes. |

## Build

The normal build is standard Cargo:

```sh
cd portable
cargo build --release
cargo test
```

On a host without Cargo, the scripts use `rustc` directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/test.ps1
```

```sh
portable/scripts/build.sh
portable/scripts/test.sh
```

`rustc` still needs the platform linker. Windows needs the MSVC C++ build
tools (or a working GNU target + MinGW); Linux needs `cc` and binutils; macOS
needs the Xcode command-line tools.

## Cross-target type-check

The reproducible check is in `portable/scripts/check-targets.ps1` (and the
commands below work on any host with the targets installed):

```sh
rustc --target x86_64-pc-windows-msvc --edition=2021 --test portable/src/lib.rs --emit=metadata -o /tmp/tests.rmeta
```

This validates every `#[cfg]` branch without linking. It is not a substitute
for running the tests or the CLI on each platform.

The 12 checked targets are:

- Windows: `x86_64-pc-windows-msvc`, `i686-pc-windows-msvc`,
  `aarch64-pc-windows-msvc`, `x86_64-pc-windows-gnu`,
  `i686-pc-windows-gnu`, `aarch64-pc-windows-gnullvm`
- Linux: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`,
  `i686-unknown-linux-gnu`, `armv7-unknown-linux-gnueabihf`
- macOS: `x86_64-apple-darwin`, `aarch64-apple-darwin`

See [`PLATFORMS.md`](PLATFORMS.md) for the runtime and packaging status.

## CLI

```text
batteryguard [--json] [--watch SECONDS]
```

Examples:

```sh
batteryguard
batteryguard --json
batteryguard --watch 30
```

Text output uses the same electrical format as the Windows tray:

```text
BatteryGuard portable core
platform: windows / x86_64
source: windows-wmi
battery: 61% · Plugged in
electrical: 11.8 V · 0.0 W
health: 80%
```

JSON is one object per reading:

```json
{"schema":"batteryguard.reading.v1","source":"windows-wmi","platform":"windows","arch":"x86_64","percent":61,"voltage_mv":11781,"power_mw":0,"ac_online":true,"charging":false,"discharging":false,"electrical":"11.8 V · 0.0 W","health_percent":80,"minutes_remaining":null}
```

Missing measurements are `null`; a real zero power is kept when voltage is
available.

## Platform notes

### Windows

- Uses `Get-CimInstance` through the built-in PowerShell. No WMI NuGet package
  or native DLL is required.
- Reads `BatteryStatus.Voltage`, `ChargeRate`, `DischargeRate`, `PowerOnline`,
  `Charging`, `Discharging`, `Win32_Battery.EstimatedChargeRemaining`,
  `BatteryFullChargedCapacity` and `BatteryCycleCount`.
- Works on x86, x64 and ARM64 Windows with Windows PowerShell 5.1.
- The read-only core is deliberately separate from the existing elevated C#
  HP controller.

### Linux

- Reads the kernel power-supply class at `/sys/class/power_supply`.
- Finds the first `type=Battery` (or `BAT*`) device and the `Mains`/`AC`
  supply.
- Handles `energy_now`/`energy_full` for health and `power_now` or
  voltage × current for power. Missing files simply produce missing fields.
- The interface is distribution-independent: Debian, Fedora, Arch, openSUSE,
  Alpine and others expose the same sysfs contract.

### macOS

- Uses the built-in `pmset -g batt`.
- Reads percentage, AC state and charging/discharging state.
- Voltage and wattage are not exposed by this small backend yet; a later IOKit
  adapter can add `AppleSmartBattery` details.
- No SMC or private charge-control write is attempted.

## Safety

The core never writes a charge mode. The only firmware control in the project
is the established Windows HP path, restricted to `0x00` (auto) and `0x05`
(inhibit), with no forced discharge. A future cross-platform controller must
probe the hardware interface and fail closed to monitoring when it cannot
confirm support.

## Not in this phase

- Linked Windows/macOS/Linux binaries and signed installers.
- Linux `.deb`, `.rpm`, Arch, AppImage or Flatpak packages.
- macOS `.pkg`, `.dmg` or a menu-bar widget.
- Linux desktop widgets or a system tray.
- Charge control outside the existing Windows HP controller.

These require the corresponding build hosts, signing identities, packaging
tools and runtime tests; they are tracked in the roadmap rather than claimed
as complete.
