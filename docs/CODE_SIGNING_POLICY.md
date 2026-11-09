# Code signing policy

BatteryGuard uses free code signing provided by [SignPath.io](https://about.signpath.io/), certificate by [SignPath Foundation](https://signpath.org/). When signing is enabled, SignPath Foundation is the publisher shown on the signed Windows files.

## Scope

The GitHub Actions workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) is the only signer. It signs only these artifacts, built from this repository:

- `application.exe` — the C# tray application.
- `batteryguard.exe` — the Rust CLI.
- The per-architecture MSI packages.
- The per-architecture Burn EXE bootstrappers.

The upstream WiX Burn engine is included unsigned. It is not submitted for signing under the SignPath Foundation certificate. The optional maintainer-owned PFX path is separate from this policy.

No developer workstation signs release artifacts.

## Roles and approval

- **Authors and committers:** Alaa ([@Alaa91H](https://github.com/Alaa91H)), repository owner.
- **Reviewers:** Alaa. Changes from outside contributors require owner review before merge.
- **Approvers:** Alaa. Every SignPath signing request requires manual approval. The CI submitter is not an approver.

If the team grows, this section must name the additional committers, reviewers and approvers before signing continues.

All signing participants must use multi-factor authentication for both GitHub and SignPath.

## Release control

- `portable/Cargo.toml` is the version source of truth.
- A published release tag must be `v` plus that version.
- Only a matching `v*` tag may publish a GitHub Release. Branch builds do not publish a release.
- The workflow verifies returned Authenticode signatures with `signtool verify /pa /all` before packaging or publishing.
- SignPath is not configured yet. No artifact is currently signed under this policy.

## Privacy

BatteryGuard uses local Windows APIs. It has no telemetry, analytics, update checks, remote logging or other transfer to a networked system. Settings, activity logs and cached capacity remain on the local computer. The installer and the .NET Framework are platform components; no third-party service receives application data.

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

## Links

- Repository: https://github.com/Alaa91H/BatteryGuard
- Releases: https://github.com/Alaa91H/BatteryGuard/releases
- Issues: https://github.com/Alaa91H/BatteryGuard/issues
- License: [MIT](../LICENSE)
