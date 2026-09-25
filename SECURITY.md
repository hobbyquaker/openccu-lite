# Security policy

This repository is **openccu-lite**, a Homematic CCU firmware built from a fork of OpenCCU. Security
problems in openccu-lite — in its image, its lite overlay, the system service `occulited`, the
addon confinement or the release files — are reported here, not to OpenCCU.

## Supported versions

Security fixes go into the newest release and the `main` branch. openccu-lite publishes
prereleases of 1.0.0 (`1.0.0-dev.<N>`) for now; there is no maintained older line.

## Reporting a vulnerability

Please report it privately, through GitHub's **[Report a vulnerability](https://github.com/hobbyquaker/openccu-lite/security/advisories/new)**
form (the repository's *Security* tab), not as a public issue. Say which release you run (the
Updates page shows it), what an attacker needs (network access, a user account, an addon) and how to
reproduce it. You get an answer as soon as possible; a fix is released and the advisory published
once it is out.

What is in scope, how the system is meant to hold together and the risks that are known and
accepted are in [docs/security.md](docs/security.md) and [docs/threat-model.md](docs/threat-model.md).

A problem that is in upstream OpenCCU as well (the parts openccu-lite takes unchanged) is best
reported to [OpenCCU](https://github.com/OpenCCU/OpenCCU/security) too; a problem in eQ-3's
programs (`rfd`, `hs485d`, `multimacd`, `hmipserver`) belongs to eQ-3.
