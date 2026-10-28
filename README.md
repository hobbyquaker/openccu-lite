<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/openccu-lite-dark@2x.png">
    <img src="docs/images/openccu-lite-light@2x.png" alt="openccu-lite" width="428">
  </picture>
</h1>

[![upstream versions](https://img.shields.io/endpoint?url=https://hobbyquaker.github.io/openccu-lite/badge.json)](https://hobbyquaker.github.io/openccu-lite/)

[:uk: English README](README.en.md)

openccu-lite ist eine Firmware für Homematic-Zentralen, ein Fork des [OpenCCU-Projekts](https://github.com/OpenCCU/OpenCCU).
Sie richtet sich an alle, die ihre Automation anderswo betreiben, etwa in Home Assistant, ioBroker oder Node-RED, und
von der Zentrale vor allem eines wollen: dass sie die Homematic-Geräte zuverlässig anbindet.

Deshalb fehlt einiges, was eine CCU sonst mitbringt: **Es gibt in openccu-lite keine ReGaHSS, keine WebUI-Programme und 
keine Homematic-Scripte.** Die alte CCU-WebUI wurde durch eine
[neu entwickelte Oberfläche](docs/walkthrough/README.md) ersetzt, und der neue Systemdienst
[occulited](https://github.com/hobbyquaker/occulited) übernimmt die Systemverwaltung. Systeminterna wie unter anderem das
Init-System, das Logging oder die Funkmodulerkennung wurden von Grund auf neu gestaltet.

## Schwerpunkte

- **Stabil.** Weniger Bestandteile heißt weniger, was ausfallen kann, und eine hohe Testabdeckung schützt vor
  Regressionsfehlern.
- **Sicher.** Addons und Systemdienste laufen unter eigenen Benutzern mit eingeschränkten Rechten, Ports sind
  standardmäßig geschlossen, Authentifizierung mit Passkeys, OAuth und Tokens, Zertifikate per ACME, verschlüsselte
  Sicherungen. Programme und Addons sprechen die Schnittstellenprozesse über lite-rpc an, mit API-Tokens, deren Scopes
  festlegen, was sie dürfen: lesen, bedienen, konfigurieren oder verwalten.
- **Privat.** Keine Telemetrie. Im [lokalen Schlüsselmodus](docs/lokaler-schluesselmodus.md) lässt sich eine Zentrale
  auch ohne Internetverbindung und ohne Abhängigkeit vom Schlüsselserver von eQ-3 betreiben, sonstige ausgehende
  Verbindungen (Update-Checks) gibt es nur mit Zustimmung des Benutzers. Details: [Datenschutz](docs/privacy.md).
- **Freie Funkkonfiguration.** Welches Funkmodul welche Schnittstelle bedient, ist frei wählbar. Das ermöglicht
  besondere Konfigurationen, etwa getrennte Funkmodule für BidCos-RF und HmIP-RF oder einen reinen HmIP-Betrieb ohne
  BidCos. [Beispiele](docs/walkthrough/README.md#beispiele-für-funk-konfigurationen) zeigt der Rundgang.
- **Minimal.** openccu-lite bringt nur mit, was eine Zentrale wirklich braucht. Alles andere kommt als Addon dazu, und
  zwar nur das, was tatsächlich genutzt wird.

## Addons: nur das, was gebraucht wird

Die Firmware selbst bleibt bewusst klein. Was darüber hinaus gebraucht wird, lässt sich als Addon aus dem
eingebauten Addon-Katalog mit einem Klick installieren.

### Geräte anlernen und verwalten: freie Wahl

Womit die Geräte angelernt und konfiguriert und die Direktverknüpfungen verwaltet werden, ist frei wählbar:

- [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) **muss gar nicht auf der Zentrale laufen**: Es
  gibt ihn auch als Anwendung für Windows, macOS und Linux. Auf Wunsch lässt er sich trotzdem als Addon installieren und ist
  dann in die Weboberfläche von openccu-lite integriert.
- [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom) (Geräte und Direktverknüpfungen verwalten, MQTT, Home Assistant, Matter und mehr)
- [ccu-addon-mui](https://github.com/firsttris/ccu-addon-mui) (Geräte und Direktverknüpfungen verwalten, schöne Bedienoberfläche)

### Weitere Addons

- [RedMatic](https://github.com/rdmtc/RedMatic) (Automation mit Node-RED, MQTT, Home Assistant, HomeKit, Matter und mehr)
- [ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto) (MQTT-Broker)
- [ccu-addon-battery](https://github.com/hobbyquaker/ccu-addon-battery) (Batteriewechsel erkennen, Statistiken zu Batterien)
- [ccu-addon-longpressdim](https://github.com/hobbyquaker/ccu-addon-longpressdim) (Dimmen mit langem Tastendruck über
  Schnittstellengrenzen hinweg)

Weitere Addons stehen im Katalog. Wie Addons auf openccu-lite funktionieren und wie sich ein bestehendes Addon anpassen lässt, steht unter [Addons](docs/addons.md).

## Installation

Die Releases liegen unter [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Raspberry Pi 3/4:** die `.zip` des Releases entpacken und die `.img` darin auf die SD-Karte schreiben.
- **Virtuelle Maschine:** die `.ova` importieren (Proxmox, VMware, VirtualBox usw.).
- **Proxmox per Skript:** als root auf dem Proxmox-VE-Host legt ein Skript die VM in einem Schritt an (`--help` zeigt
  die Optionen):
  `bash -c "$(wget -qLO - https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh)"`

## Wechsel von (Open)CCU zu openccu-lite

In der OpenCCU-WebUI unter *Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update durchführen* die
`openccu-lite-<produkt>-<version>.zip` hochladen, von einer originalen CCU3-Firmware die `-ccu3.tgz`. Anlernungen,
Schlüssel, Addons, Namen, Räume und Gewerke werden übernommen, WebUI-Programme und Systemvariablen entfallen ersatzlos.
Für den Weg zurück unbedingt vorher ein Backup anlegen! Alles Weitere: [Wechsel von und zu OpenCCU](docs/switching.de.md).

## Updates

### So wird aktualisiert

Auf der Seite *Updates* der Weboberfläche: *Jetzt prüfen*, *Herunterladen und bereitstellen*, *Neu starten und
installieren*. Vor der Installation wird eine Sicherung auf die eingerichteten Sicherungsziele geschrieben und die
Prüfsumme kontrolliert. Per SSH geht dasselbe mit `occulited update check` und `occulited update install`
([Befehle und Optionen](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md)).

Welche Versionen angeboten werden, ist einstellbar: **stable** (nur fertige Releases, die Voreinstellung), **beta** (dazu
Beta- und Release-Candidate-Versionen) oder **dev** (alles, auch Entwicklungsstände).

### Was geplant ist

- **Mit jedem neuen HMIPServer von eQ-3 erscheint ein neues Release** von openccu-lite, damit neue HmIP-Geräte und
  Fehlerbehebungen von eQ-3 schnell ankommen.
- **Die Schnittstellenprozesse rfd, hs485d und multimacd** kommen aus einem
  [eigenen Fork von OpenCCU-Base](https://github.com/hobbyquaker/OpenCCU-Base). Er soll möglichst nah an OpenCCU bleiben;
  welche Änderungen von OpenCCU schon übernommen sind, zeigt ein [Abgleich](https://hobbyquaker.github.io/OpenCCU-Base/).
- **Ab Buildroot 2027.02 basiert openccu-lite auf den LTS-Versionen von Buildroot.** Sie werden länger mit
  Sicherheitsupdates versorgt; dazwischen bleibt das System auf einer gepflegten Basis, und deren Point-Releases
  lassen sich mit wenig Aufwand übernehmen.
- Ob die Bestandteile aktuell sind (Buildroot, Kernel, Firmware, Java, HMIPServer, OpenCCU-Base), zeigt eine täglich
  erneuerte [Übersicht](https://hobbyquaker.github.io/openccu-lite/).

## Dokumentation

**Erste Schritte**
- [Rundgang durch die Weboberfläche](docs/walkthrough/README.md): jede Seite mit Bild
- [Wechsel von und zu OpenCCU](docs/switching.de.md)
- [Empfehlungen](docs/recommendations.de.md)
- [Was sich gegenüber OpenCCU ändert](docs/aenderungen.md)

**Betrieb**
- [Lokaler Schlüsselmodus für HmIP](docs/lokaler-schluesselmodus.md): offlinefähig, Funkmodultausch ohne den
  Schlüsselserver von eQ-3
- [Zertifikate](docs/tls-acme.md) (eigene oder automatisch per ACME)
- [occulite-backup](https://github.com/hobbyquaker/occulite-backup): Sicherungen eines oder mehrerer Systeme per Cron
  oder Timer herunterladen

**Sicherheit und Datenschutz**
- [Sicherheit](docs/security.md) und [Bedrohungsmodell](docs/threat-model.md) (englisch)
- [Datenschutz](docs/privacy.md): was das System nach außen sendet (englisch)

**Für Addon-Entwickler und eigene Programme**
- [Addons auf openccu-lite](docs/addons.md) (englisch)
- [Portierungs-Kit: von ReGa zu openccu-lite](docs/porting-from-rega.md) (englisch)
- [ccu-addon-kit](https://github.com/hobbyquaker/ccu-addon-kit): Einstellungsseite, Dienststeuerung und Go-Bausteine
  für Addons
- [occulite-client](https://github.com/hobbyquaker/occulite-client): der Client für die APIs von openccu-lite (npm)
- [occulited](https://github.com/hobbyquaker/occulited): der Systemdienst; seine
  [Dokumentation](https://github.com/hobbyquaker/occulited/tree/master/docs) beschreibt die Metadaten-, System- und
  Auth-API, `occulited.json`, das Addon-Manifest und den Katalog

## Fehler und Hilfe

Fehler und Wünsche, für die Firmware wie für occulited: der
[Issue-Tracker](https://github.com/hobbyquaker/openccu-lite/issues) dieses Repositorys ([SUPPORT.md](SUPPORT.md));
Sicherheitsprobleme wie in [SECURITY.md](SECURITY.md) beschrieben. Tracker und Forumsbereich von OpenCCU sind für
OpenCCU da, Probleme mit openccu-lite bitte nicht dort melden.

## Lizenz

Apache-2.0 für alles hier Geschriebene; die `occu`-Bestandteile behalten die Bedingungen von eQ-3.

## Haftungsausschluss

openccu-lite wird OHNE JEDE AUSDRÜCKLICHE ODER IMPLIZIERTE GARANTIE bereitgestellt, einschließlich der Garantie zur
Benutzung für den vorgesehenen oder einem bestimmten Zweck sowie jeglicher Rechtsverletzung, jedoch nicht darauf
beschränkt. IN KEINEM FALL sind die Autoren oder Copyrightinhaber für jeglichen Schaden oder sonstige Ansprüche haftbar
zu machen, ob infolge der Erfüllung eines Vertrages, eines Deliktes oder anders im Zusammenhang mit der Software oder
sonstiger Verwendung der Software entstanden.
