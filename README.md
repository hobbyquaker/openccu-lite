# openccu-lite

*Deutsch — die englische Fassung ist [README.en.md](README.en.md).*

> openccu-lite ist in Entwicklung. Vieles ist noch ungetestet.
> **Bitte nur auf Testsystemen einsetzen.**
>
> **Es richtet sich an erfahrene Anwender**, die wissen, was sie tun: Leute, die eine CCU von innen
> kennen (`rfd`, `hs485d`, der `hmipserver`, Funkmodule, das RPC-Protokoll, die Paramsets, ...).
> Es gibt in openccu-lite keine ReGaHSS, keinen Programm-Editor und keine Homematic-Scripte.

## Installation

Die Releases liegen unter [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Wechsel von OpenCCU (Raspberry Pi oder VM):** erst ein Backup anlegen, dann in der OpenCCU-WebUI unter
  Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update durchführen die
  `openccu-lite-<produkt>-<version>.zip` hochladen. Anlernungen, Schlüssel und Addons bleiben; Namen, Räume und
  Gewerke übernimmt das System beim ersten Start. Details in [switching.de.md](docs/switching.de.md).
- **Wechsel von einer CCU3:** die `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` im Software-Update der CCU3 hochladen.
- **Neuinstallation auf einem Raspberry Pi 3/4:** die `.zip` des Releases entpacken und die `.img` darin auf die
  SD-Karte schreiben.
- **Neuinstallation als VM:** die `.ova` importieren (Proxmox, VMware, VirtualBox usw.); den LXC-Container beschreibt
  [install-lxc.md](docs/install-lxc.md).

## Dokumentation

Englisch, in [`docs/`](docs/) dieses Repositorys: der Wechsel von und zu OpenCCU
([switching.de.md](docs/switching.de.md), auf Deutsch), der Proxmox-Container ([install-lxc.md](docs/install-lxc.md)),
Addons ([addons.md](docs/addons.md)), Sicherheit ([security.md](docs/security.md),
[threat-model.md](docs/threat-model.md)), Datenschutz – was das System nach außen sendet
([privacy.md](docs/privacy.md)), Zertifikate ([tls-acme.md](docs/tls-acme.md)) und das
Portierungs-Kit für Addon-Maintainer ([porting-from-rega.md](docs/porting-from-rega.md)). Der
Systemdienst mit der Weboberfläche ist [occulited](https://github.com/hobbyquaker/occulited); seine
[`docs/`](https://github.com/hobbyquaker/occulited/tree/master/docs) beschreiben die Metadaten-,
System- und Auth-API, `occulited.json`, das Addon-Manifest und den Katalog.

## Fehler und Hilfe

Fehler und Wünsche, für die Firmware wie für occulited: der
[Issue-Tracker](https://github.com/hobbyquaker/openccu-lite/issues) dieses Repositorys
([SUPPORT.md](SUPPORT.md)); Sicherheitsprobleme wie in [SECURITY.md](SECURITY.md) beschrieben.
Tracker und Forumsbereich von OpenCCU sind für OpenCCU da — Probleme von openccu-lite bitte nicht
dort melden.

## Lizenz

Apache-2.0 für alles hier Geschriebene; die `occu`-Bestandteile behalten die Bedingungen von eQ-3.
