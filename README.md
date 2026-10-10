# openccu-lite

[:uk: English README](README.en.md)

> [!CAUTION]
> openccu-lite ist in Entwicklung. Vieles ist noch ungetestet.
>
> **Die Beta-Versionen richten sich an erfahrene Homematic-Anwender**, die wissen, was sie tun, sich im
> Fall der Fälle selbst helfen können und keine Scheu vor Bugs haben.

Openccu-lite ist ein Fork des [OpenCCU-Projekts](https://github.com/OpenCCU/OpenCCU), der einige alte Softwareteile entfernt,
die für Anwender, die ihre Automation anderswo (z. B. in Home Assistant, ioBroker, Node-RED, ...) betreiben, nicht notwendig sind:
**Es gibt in openccu-lite keine ReGaHSS, keine WebUI-Programme und keine Homematic-Scripte.**
Die alte CCU-WebUI wurde durch eine [neu entwickelte Oberfläche](docs/walkthrough/README.md) ersetzt, der neue Daemon ["occulited"](https://github.com/hobbyquaker/occulited)
übernimmt die Aufgaben der Systemverwaltung. Systeminterna wie u.A. das Init-System, das Logging oder die Funkmodulerkennung wurden von Grund auf neu gestaltet, viele neue Security-Features wurden implementiert.

## Installation

Die Releases liegen unter [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Neuinstallation auf einem Raspberry Pi 3/4:** die `.zip` des Releases entpacken und die `.img` darin auf die SD-Karte schreiben.
- **Neuinstallation als VM:** die `.ova` importieren (Proxmox, VMware, VirtualBox usw.).
- **Proxmox-VM per Skript:** als root auf dem Proxmox-VE-Host legt ein Skript die VM in einem Schritt an (`--help`
  zeigt die Optionen):
  `bash -c "$(wget -qLO - https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh)"`

## Wechsel von (Open)CCU zu openccu-lite

In der OpenCCU-WebUI unter *Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update durchführen* die
`openccu-lite-<produkt>-<version>.zip` hochladen. Beim Update von einer original CCU3 Firmware die `-ccu3.tgz`
verwenden. Anlernungen, Schlüssel, Addons, Namen, Räume und Gewerke werden übernommen [switching.de.md](docs/switching.de.md). WebUI-Programme und Variablen entfallen ersatzlos. Für den Weg zurück unbedingt vorher ein
Backup anlegen!

## Update

Auf der Seite *Updates* der Weboberfläche: *Jetzt prüfen*, *Herunterladen und bereitstellen*, *Neu starten und
installieren*. Oder als root per SSH: `occulited update check` zeigt, ob es ein neueres Release gibt,
`occulited update install` installiert es – nach einer Sicherung auf die eingerichteten Sicherungsziele und mit
Prüfung der sha256-Summe; `occulited update install <version>` installiert eine bestimmte Version, auch eine ältere.
Die Befehle und ihre Optionen (`--yes` für Skripte, `--no-backup`, `--file`, …) beschreibt
[occulited's docs/config.md](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md).

## Geräte anlernen und konfigurieren, Direktverknüpfungen verwalten

Dafür den
  [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) oder 
  [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom) aus dem Addon-Katalog installieren.

## Dokumentation

Ein Rundgang mit Bildern durch jede Seite der Weboberfläche: [docs/walkthrough](docs/walkthrough/README.md).
Weiteres, meist auf Englisch, in [`docs/`](docs/) dieses Repositorys: der Wechsel von und zu OpenCCU
([switching.de.md](docs/switching.de.md), auf Deutsch), was sich gegenüber OpenCCU ändert
([aenderungen.md](docs/aenderungen.md), auf Deutsch), bekannte Probleme und was das System dagegen tut
([bekannte-probleme.md](docs/bekannte-probleme.md), auf Deutsch), der lokale Schlüsselmodus für HmIP – offline-fähig,
Funkmodultausch ohne Schlüsselserver von eQ-3 ([lokaler-schluesselmodus.md](docs/lokaler-schluesselmodus.md), auf
Deutsch), Addons ([addons.md](docs/addons.md)), Sicherheit ([security.md](docs/security.md),
[threat-model.md](docs/threat-model.md)), Datenschutz – was das System nach außen sendet
([privacy.md](docs/privacy.md)), Zertifikate ([tls-acme.md](docs/tls-acme.md)) und das
Portierungs-Kit für Addon-Maintainer ([porting-from-rega.md](docs/porting-from-rega.md)). Der
Systemdienst mit der Weboberfläche ist [occulited](https://github.com/hobbyquaker/occulited); seine
[`docs/`](https://github.com/hobbyquaker/occulited/tree/master/docs) beschreiben die Metadaten-,
System- und Auth-API, `occulited.json`, das Addon-Manifest und den Katalog.
Empfehlungen: [recommendations.de.md](docs/recommendations.de.md).

## Fehler und Hilfe

Fehler und Wünsche, für die Firmware wie für occulited: der
[Issue-Tracker](https://github.com/hobbyquaker/openccu-lite/issues) dieses Repositorys
([SUPPORT.md](SUPPORT.md)); Sicherheitsprobleme wie in [SECURITY.md](SECURITY.md) beschrieben.
Tracker und Forumsbereich von OpenCCU sind für OpenCCU da — Probleme von openccu-lite bitte nicht
dort melden.

## Lizenz

Apache-2.0 für alles hier Geschriebene; die `occu`-Bestandteile behalten die Bedingungen von eQ-3.

## Haftungsausschluss

openccu-lite wird OHNE JEDE AUSDRÜCKLICHE ODER IMPLIZIERTE GARANTIE bereitgestellt, einschließlich der Garantie zur Benutzung für den vorgesehenen oder einem bestimmten Zweck sowie jeglicher Rechtsverletzung, jedoch nicht darauf beschränkt. IN KEINEM FALL sind die Autoren oder Copyrightinhaber für jeglichen Schaden oder sonstige Ansprüche haftbar zu machen, ob infolge der Erfüllung eines Vertrages, eines Deliktes oder anders im Zusammenhang mit der Software oder sonstiger Verwendung der Software entstanden.
