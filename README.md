# openccu-lite

[:uk: English README](README.en.md)

> [!CAUTION]
> openccu-lite ist in Entwicklung. Vieles ist noch ungetestet.
> **Bitte nur auf Testsystemen einsetzen.**
>
> **Die -dev Releases richten sich an erfahrene Homematic Anwender**, die wissen, was sie tun und sich im Fall der Fälle 
> selbst helfen können: Leute, die eine CCU von innen kennen (`rfd`, `hs485d`, der `hmipserver`,
> Funkmodule und Key-Handling, das RPC-Protokoll, die Paramsets, ...).

openccu-lite ist ein Fork des [OpenCCU-Projekts](https://github.com/OpenCCU/OpenCCU), der einige alte Softwareteile entfernt,
die für Anwender, die ihre Automation anderswo (z. B. in Home Assistant, ioBroker, Node-RED, ...) betreiben, nicht notwendig sind:
**Es gibt in openccu-lite keine ReGaHSS, keine WebUI-Programme und keine Homematic-Scripte.**
Die alte CCU-WebUI wurde durch eine [neu entwickelte Oberfläche](docs/walkthrough/README.md) ersetzt, der neue Daemon ["occulited"](https://github.com/hobbyquaker/occulited)
übernimmt die Aufgaben der Systemverwaltung. Systeminterna wie u.A. das Init-System, das Logging oder die Funkmodulerkennung wurden von Grund auf neu gestaltet, viele neue Security-Features wurden implementiert.

## Installation

Die Releases liegen unter [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Wechsel von OpenCCU (Raspberry Pi oder VM):** erst ein Backup anlegen, dann in der OpenCCU-WebUI unter
  Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update durchführen die
  `openccu-lite-<produkt>-<version>.zip` hochladen. Anlernungen, Schlüssel und Addons bleiben; Namen, Räume und
  Gewerke übernimmt das System beim ersten Start. Details in [switching.de.md](docs/switching.de.md).
- **Wechsel von einer CCU3:** die `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` im Software-Update der CCU3 hochladen.
- **Neuinstallation auf einem Raspberry Pi 3/4:** die `.zip` des Releases entpacken und die `.img` darin auf die SD-Karte schreiben.
- **Neuinstallation als VM:** die `.ova` importieren (Proxmox, VMware, VirtualBox usw.).
- eine Neuinstallation kann (solange noch keine Geräte angelernt sind) angelernte Geräte, Schlüssel, Namen und Räume aus einem
  (Open)CCU-Backup in einem Schritt importieren. Der BidCos-Sicherheitsschlüssel der Sicherung kommt so mit, wie er ist (seine
  Passphrase wird nur als Prüfung abgefragt, nie als Hürde; sie wird für spätere Schlüsseländerungen gebraucht); eine
  HmIP-Identität, die an ein anderes Funkmodul gebunden ist, übernimmt hmipserver auf das Modul dieses Systems, und die
  Seite Schnittstellen zeigt, wie das ausging ([switching.de.md](docs/switching.de.md)).
- **Geräte anlernen und konfigurieren, Direktverknüpfungen verwalten:** dafür den
  [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) oder 
  [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom) aus dem Addon-Katalog installieren.

## Dokumentation

Ein Rundgang mit Bildern durch jede Seite der Weboberfläche: [docs/walkthrough](docs/walkthrough/README.md).
Weiteres, meist auf Englisch, in [`docs/`](docs/) dieses Repositorys: der Wechsel von und zu OpenCCU
([switching.de.md](docs/switching.de.md), auf Deutsch), der lokale Schlüsselmodus für HmIP – offline-fähig,
Funkmodultausch ohne Schlüsselserver von eQ-3 ([lokaler-schluesselmodus.md](docs/lokaler-schluesselmodus.md), auf
Deutsch), Addons ([addons.md](docs/addons.md)), Sicherheit ([security.md](docs/security.md),
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
