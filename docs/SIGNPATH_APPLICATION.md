# SignPath Foundation application answers

**Status:** submitted through the public form on 2026-11-09; awaiting SignPath
review. The form did not display an application or receipt ID. This file is not
a claim that SignPath reviewed or approved the project.

## Submission record

- Submitted on 2026-11-09 from the maintainer's Chrome session.
- Confirmation shown by the form: `Thank you, we'll be in touch soon.`
- No application or receipt ID was displayed.
- Review outcome is unknown; no approval, project, policy or signing
  configuration exists yet.
- The form received `Category = Other`, `Maintainer Type = Individual
  maintainer(s)`, `Build System = GitHub Actions`, and `Primary Discovery
  Channel = AI / LLM tools`.

The field list below follows the public HubSpot form definition used at
`https://signpath.org/apply` (portal `145110231`, form
`bf62807d-bb72-4e45-9bde-1f3a53ba2472`), checked against public write-ups of
the form. Labels can change; fill the corresponding field if the wording
differs.

## Copy-paste fields

| Form field | Required | Value to enter |
| --- | --- | --- |
| Project Name | Yes | `BatteryGuard` |
| Repository URL | Yes | `https://github.com/Alaa91H/BatteryGuard` |
| Homepage URL | Yes | `https://github.com/Alaa91H/BatteryGuard` |
| Download URL | No | `https://github.com/Alaa91H/BatteryGuard#installers-and-releases` |
| Privacy Policy URL | No | `https://github.com/Alaa91H/BatteryGuard/blob/main/docs/CODE_SIGNING_POLICY.md#privacy` |
| Wikipedia URL | No | Leave blank. |
| Tagline | Yes | `A Windows battery tray for HP charge control and cross-brand monitoring, with a small cross-platform CLI.` |
| Description | Yes | See the description block below. |
| Reputation | Yes | See the reputation block below. |
| Maintainer Type | No | `Individual maintainer` |
| Build System | No | `GitHub Actions` |
| First Name | Yes | `[your given name]` |
| Last Name | Yes | `[your family name]` |
| Email | Yes | `[your email address]` |
| Company Name | No | Leave blank unless applying as an organization. |
| Primary Discovery Channel | Yes | Choose the truthful channel; do not guess. |
| Please specify the exact source | No | Fill only if it is accurate (for example, a specific GitHub link or search result). |
| Code of Conduct consent | Yes | Read the live terms and check this personally. |
| reCAPTCHA | Yes | Complete personally. |
| Other communications | No | Leave unchecked unless you want marketing email. |

The form has **no separate license or build-process field**. SignPath checks
those from the repository. The project is MIT licensed and the complete build
is in the public repository.

### Download URL note

The README page above contains the release links and the required
**Code signing policy** section, so it is ready to use now. If the release page
is preferred instead, first add this line to the `v0.2.0` release notes:

```text
Code signing policy: https://github.com/Alaa91H/BatteryGuard#code-signing-policy
```

The current release body does not contain that line. The form requires the
download page to mention SignPath Foundation.

## Description

Copy this block:

```text
BatteryGuard is a free, open-source Windows battery utility. Its .NET Framework
tray application applies a charge limit and resume point on supported HP
notebooks, supports scheduled charge windows and float mode, and monitors
health, capacity, cycles, temperature, voltage and power on other brands. A
dependency-free Rust CLI provides read-only battery data on Windows, Linux and
macOS. Windows releases ship as a per-machine MSI and a single-EXE WiX Burn
bootstrapper; Linux and macOS packages are CLI-only. It uses local Windows APIs
and has no telemetry, analytics, update checks or other network services.
```

## Reputation

Copy this block, but review every sentence before submitting:

```text
BatteryGuard is a new, actively maintained MIT project published on GitHub. Its
complete source, tests, build scripts and code-signing policy are public. The
v0.2.0 release (2026-11-09) contains 14 platform-native assets: 3 Windows EXE
bootstrappers, 3 Windows MSIs, 6 Linux packages and 2 macOS PKGs. Every tag runs
a seven-job, GitHub-hosted build, test and attestation matrix; the Windows x64
job ran eight hardware-independent C# tests in the v0.2.0 run; the current branch adds ninth and tenth checks, with quiet MSI/EXE install-uninstall
and v0.1.0 upgrade checks. The installers carry GitHub/Sigstore build-provenance
attestations, and the repository is continuously built and tested on GitHub
Actions.

The repository was created on 2026-11-09. The project does not claim independent
media coverage, third-party adoption or download statistics at this stage.
Verifiable links: repository https://github.com/Alaa91H/BatteryGuard, release
https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0, tag run
https://github.com/Alaa91H/BatteryGuard/actions/runs/42653411073, and code-signing
policy https://github.com/Alaa91H/BatteryGuard/blob/main/docs/CODE_SIGNING_POLICY.md.
```

This is deliberately honest. The new repository has 0 stars and no independent
adoption evidence, so a rejection or deferral is a material possibility.
SignPath requires verifiable reputation for downloadable executables; do not
replace this field with invented stars, downloads or media links.

## Signing scope (for review or follow-up email)

- `application.exe` — the C# .NET Framework tray application.
- `batteryguard.exe` — the Rust CLI.
- Per-architecture Windows MSI packages.
- Per-architecture final EXE bootstrappers.

The upstream WiX Burn engine is included unsigned inside the final EXE. The
project is not asking to sign the upstream engine with the Foundation
certificate. The workflow has three SignPath requests: binaries, MSI, then final
EXE.

Releases are built only by `.github/workflows/ci.yml` on GitHub-hosted runners
from a `v*` tag matching `portable/Cargo.toml`. Branch builds upload artifacts
but never publish a release. Signing requests require manual approval.

## Pre-submit checks

- [ ] Read the current [SignPath conditions](https://signpath.org/terms.html)
      and Code of Conduct personally.
- [ ] Enter your own name and email in the form; do not put personal data or
      tokens in this repository.
- [ ] Confirm GitHub MFA is active. According to the maintainer it is enabled;
      enable MFA for the SignPath account after it is created.
- [ ] Use the README download URL, or add the code-signing line to the release
      notes before using the release URL.
- [ ] Review the reputation text. If it is rejected, gather real public
      adoption evidence before reapplying; do not argue with the policy.
- [ ] Complete reCAPTCHA and check the consent box yourself.
- [ ] Do not describe the current `v0.2.0` binaries as signed. They are
      `NotSigned`; Smart App Control blocked the unsigned x64 EXE on
      2026-11-09.

## Known technical gap before the first signing request

The MSI and EXE bundle carry product version `0.2.0`, but the current
`application.exe` reports file/product version `0.0.0.0` and the Rust
`batteryguard.exe` has no PE version resource. SignPath's artifact
configuration rules require product metadata for signed PE files. Add and
verify PE product-name/version metadata before relying on a SignPath artifact
configuration; do not claim that the metadata is already compliant.

## After approval

The setup and GitHub variables are documented in
[`SIGNPATH.md`](SIGNPATH.md). Do not paste the API token into chat. After the
first signed release, verify the Authenticode signatures and repeat the Smart
App Control install test on this Windows 11 host.
