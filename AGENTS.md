# AGENTS.md

## Scope

This repository has three areas:

- `battery/` — the BatteryGuard Windows tray application. This is the active application.
- `portable/` — the dependency-free Rust core for Windows, Linux and macOS. It is read-only and is not linked into the C# tray yet.
- `windows/`, `linux/`, `.wslconfig`, `docs/production.md`, `docs/wsl/` — WSL2 provisioning notes. Do not rewrite these when the task is about the tray app.

## Build and verify

Run commands from the workspace root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-FloatLogic.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-ScheduleConflict.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-UiPolish.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Settings.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-BatteryInfo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-AppIdentity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-LogRotation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Icons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Layout.ps1
```

After editing C#, rebuild and rerun the affected checks. The build, launcher and every in-memory test enumerate `src/*.cs`, so a new module is picked up automatically and `add-type` compiles all modules together.

For the Rust core:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/check-targets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/test.ps1
```

`check-targets.ps1` only emits metadata and needs no linker. `build.ps1`/`test.ps1` need a platform linker; on this machine the MSVC linker is absent and Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers. Do not claim those runtime tests passed unless the binary actually ran.

`battery/tests/VisualCapture.ps1` renders the Settings, schedule and log windows in English/Arabic and light/dark. It backs up and restores `interface.ini` and `theme.ini`; it needs no hardware, WMI writes or elevation.

`battery/tests/Test-Layout.ps1` resizes the three dialogs through ten representative client sizes, from 780×601 down to 380×300. It checks pinned action bars, content scrolling, the 660 px Settings content width, the 360 px rule layout and the language/direction combo text. It shows the forms off-screen, so it needs no elevation and no hardware writes.

`battery/tests/Test-AppIdentity.ps1` verifies the Windows notification identity: it runs `AppIdentity.Install()`, then checks the current user's Start Menu shortcut for `System.AppUserModel.ID=BatteryGuard.Tray`, the PowerShell/exe target, arguments and description. It creates or replaces `%APPDATA%\Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk`; it needs no elevation and no hardware writes.

PowerShell scripts that contain non-ASCII text must be UTF-8 (BOM is accepted). The C# compiler uses `-codepage:65001`.

## Conventions

- .NET Framework 4.x only; no NuGet, no external runtime packages.
- The Rust core uses only the standard library: no crates, no build scripts and no network access.
- Keep the display name **BatteryGuard**. Keep the C# namespace `BatteryGuardTray` for compatibility with existing scripts and tests.
- Source, resources, scripts, tests and data files use neutral names; do not add product/version names to new paths.
- Settings are JSON; interface and theme files are `key=value` INI-style text.
- Never put credentials or secrets in this repository. The app uses only local Windows APIs.
- Do not run hardware tests that change charge mode unless the task requires it and elevation is available.
- Preserve the safety rule: only modes `0x00` (auto) and `0x05` (inhibit); never force discharge.

## Localization

- English is the source and fallback language.
- Every UI string is authored as `Loc.T("English source")` or `Loc.F("... {0} ...", args)`.
- Catalogs are `battery/locales/<code>.json`, flat objects keyed by the exact English source string.
- `language=auto` follows Windows; explicit codes are in `src/Localization.cs`.
- Preserve placeholders exactly: `{0}`, `{1:N0}`, etc. Run the validation described in `docs/LOCALIZATION.md` after catalog changes.
- Do not add a new UI string without adding it to all 30 catalogs or accepting the English fallback deliberately.
- Machine translation quality is a known limitation; use `tools/fix_glossary.py` for context-sensitive terms and prefer clear, unambiguous English source strings.

## Generated files

`application.exe`, `settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log`, `application.previous.log`, test screenshots and logs are local/generated. They are ignored by `.gitignore` and must not be committed. `portable/target/` is also generated and ignored.

## Documentation

Keep these in sync with behavior:

- `README.md`
- `battery/README.md`
- `portable/README.md`
- `portable/PLATFORMS.md`
- `docs/ARCHITECTURE.md`
- `docs/DEVICE_SUPPORT.md`
- `docs/PROJECT_STATUS.md`
- `docs/ROADMAP.md`
- `docs/DECISIONS.md`
- `docs/LOCALIZATION.md`
- `docs/SESSION_LOG.md`
- `CHANGELOG.md`

Write documentation in English. Do not claim a visual check, a native-speaker review or a hardware test that was not actually performed.
