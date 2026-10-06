# Wechsel zwischen OpenCCU (oder einer CCU3) und openccu-lite

*Deutsch — die englische Fassung ist [switching.md](switching.md).*

**Vor dem Wechsel ein Backup (`.sbk`) anlegen und aufbewahren. Es ist der einzige Weg zurück.** Nach seinem ersten
Start entfernt openccu-lite die ReGa-Datenbank der CCU und die Daten der WebUI vom System (siehe
[Was sich beim ersten Start ändert](#was-sich-beim-ersten-start-ändert)). Wer ohne das Backup zu OpenCCU zurückflasht,
bekommt ein laufendes OpenCCU mit Anlernungen und Schlüsseln, aber ohne Namen, Räume, Programme und Systemvariablen.

## OpenCCU / CCU3 → openccu-lite

In der WebUI von OpenCCU oder der CCU3: Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update
durchführen, das Paket (unten) hochladen, bestätigen, neu starten lassen. Anlernungen, Schlüssel, die
Interface-Konfiguration und die Addons bleiben in `/usr/local`. Beim ersten Start übernimmt das System die Namen,
Räume und Gewerke aus der ReGa-Datenbank und fragt nach einem Administrator-Passwort.

### Welches Paket für welches System

`cat /VERSION` über SSH (`PRODUCT=…`) zeigt, was für ein System es ist:

| Ihr System | Paket | Was passiert |
| --- | --- | --- |
| OpenCCU auf SD-Karte oder USB-Datenträger (`PRODUCT=rpi3`, `rpi4`, `rpi5`, …) | `openccu-lite-<produkt>-<version>.zip` | ein Recovery-Durchlauf, ein Neustart, etwa drei Minuten |
| Die OpenCCU-VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | dasselbe |
| Eine CCU3 oder eine Karte aus einem CCU3-Image oder CCU3-Backup-Image (`PRODUCT=ccu3`) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | zwei Recovery-Durchläufe und zwei Neustarts: der zweite vergrößert die Root-Partition auf 2 GB. Mit etwa 25 Minuten ab dem Start des Updates rechnen, auf einer langsameren oder größeren Karte bis zu 30-40 Minuten (siehe [unten](#ein-dunkles-update-auf-einem-raspberry-pi-3-oder-charly)). |

Die `.zip` ist für ein System mit CCU3-Layout das falsche Paket; dort die `-ccu3.tgz` nehmen.

**Eine Neuinstallation** braucht kein Update: die `.img` aus der `.zip` des Releases auf eine SD-Karte schreiben
(Raspberry Pi 3/4) oder die `.ova` importieren (Proxmox, VMware, VirtualBox). Die Geräte des alten Systems kommen dann
per [Restore oder Geräte-Import](#geräte-in-eine-neuinstallation-übernehmen) dazu.

### Der Platz, den das Update braucht

Das Recovery entpackt das Update auf dem userfs (`/usr/local`), bevor es etwas schreibt. **Nötig sind mindestens
2,8 GB frei.** Die WebUI zeigt das unter *Software-Update durchführen* (*Verfügbarer Speicherplatz*), über SSH
`df -h /usr/local`. Alte Backups unter `/usr/local/tmp` und große Addon-Daten sind die üblichen Platzfresser; vorher
wegräumen.

### Vor dem Wechsel prüfen

- **Ein Backup**, angelegt unter Einstellungen → Systemsteuerung → Sicherheit → Backup erstellen und vom System
  heruntergeladen.
- **2,8 GB frei** auf dem userfs.
- **Das richtige Paket** (Tabelle oben), seine `.sha256` geprüft.
- **Zugang, falls etwas schiefgeht:** die Adresse des Systems notiert (ein fehlgeschlagenes Update kann mit einer neuen
  DHCP-Adresse zurückkommen), SD-Karte oder Konsole der VM erreichbar.
- **Sichere Stromversorgung** für das ganze Update: der zweite Durchlauf auf der CCU3 schreibt Partitionstabellen.

### Ein dunkles Update auf einem Raspberry Pi 3 oder Charly

Auf einem Raspberry Pi 3 (einem Charly oder einer Karte aus einem CCU3-Image) läuft das Recovery womöglich **ohne
Netzwerk**: Der Ethernet-Chip der Platine kommt nach dem Neustart ins Recovery manchmal nicht wieder. Das Update läuft
trotzdem weiter, aber `http://<system>/` zeigt währenddessen nichts. **Ein schnelles magentafarbenes Blinken der
Status-LED heißt: Das Update läuft - warten, nicht ausschalten.** Mit dem `-ccu3.tgz` dauert es auf einem Pi 3 mit einer
32-GB-Karte etwa 25 Minuten ab dem Start des Updates (das Hochladen davor etwa 5 Minuten; der längste Schritt, das
Verschieben des Userfs für die größere Root-Partition, etwa 10 Minuten bei 4 MB/s); eine langsamere oder größere Karte
braucht länger, **bis zu etwa 30-40 Minuten**. Danach startet das System von selbst openccu-lite, und sein Netzwerk ist
wieder da. Das Recovery bewahrt sein eigenes Protokoll auf, dazu, was es vom Netzwerk und von den USB-Geräten gesehen
hat; openccu-lite zeigt es nach dem ersten Start in seinem Log (Tag `recovery`).

### Ein Recovery, das in seinem Menü stehen bleibt

Bleibt die WebUI dunkel und zeigt `http://<system>/` das Menü des Recovery, **ist das Update fehlgeschlagen**. Das
ursprüngliche Recovery der CCU3 bleibt bei jedem Fehler dort stehen. *Normal Reboot* startet das vorherige System,
`/usr/local` unangetastet; *Check storage* prüft die Partitionen mit `e2fsck`. Vor einem neuen Versuch klären, warum
es fehlschlug; meist ist es der freie Platz, und der wächst nicht von selbst. Das Recovery von openccu-lite startet
nach einem Fehler das normale System, und das Journal zeigt den Grund beim nächsten Start.

### Geräte in eine Neuinstallation übernehmen

Die Seite Sicherung bietet zwei Wege:

- **Die `.sbk` einspielen**: ersetzt `/usr/local` komplett, mit Anlernungen, Schlüsseln, Addons und dem eigenen
  Zustand des Systems. Der vor dem Einspielen angelegte Administrator ist danach weg, das System fragt nach einem
  neuen. Die ReGa-Datenbank im Backup wird ignoriert; ihre Namen lassen sich getrennt importieren (unten).
- **Angelernte Geräte importieren** (nur auf einem System ohne angelernte Geräte): *Angelernte Geräte importieren und
  neu starten* übernimmt Anlernungen und Identität von BidCos-RF, HmIP-RF und den LAN-Gateways, dazu Namen, Räume und
  Gewerke aus der Sicherung, und startet neu.

**Ein eigener BidCos-Sicherheitsschlüssel** kommt so mit, wie er ist; die BidCos-Geräte arbeiten weiter. Die Seite
Sicherung fragt nach seiner Passphrase nur zur Prüfung und speichert sie nie. Eine falsche oder übersprungene
Passphrase (*Überspringen - ich kenne sie nicht*) hält Einspielen und Import nicht auf. **Die Passphrase suchen,
solange die alte CCU noch greifbar ist:** man braucht sie, um den Schlüssel später zu ändern, die Geräte auf ein
anderes System umzuziehen oder auf einem System mit anderem Schlüssel wiederherzustellen. Ohne sie bleibt nur, jedes
BidCos-Gerät zurückzusetzen und neu anzulernen.

**Ein anderes Funkmodul.** BidCos-RF braucht nichts: es läuft mit der importierten Adresse auf jedem Modul. Die
HmIP-Identität ist dagegen an das Funkmodul des Systems gebunden, das das Backup angelegt hat. Auf einem anderen Modul
übernimmt hmipserver sie beim Start (der *Adaptertausch*):

- Stammt die Sicherung von einem System im lokalen Schlüsselmodus, geht das offline; siehe
  [lokaler-schluesselmodus.md](lokaler-schluesselmodus.md).
- Sonst läuft es über den Schlüsselserver von eQ-3. Das braucht eine Internetverbindung, und **der Schlüsselserver
  kann den Tausch ablehnen**, auch für ein Modul, das er schon kennt. Nach einer Ablehnung bleibt HmIP-RF gestoppt.
  Die Seite Schnittstellen zeigt den Stand (offen, erledigt, abgelehnt) und die Auswege: *Erneut versuchen*, zurück
  zum vorherigen Modul oder *Mit diesem Modul neu beginnen…* (jedes HmIP-Gerät neu anlernen).
- Nach dem Tausch wird jedes HmIP-Gerät für das neue Modul umgeschlüsselt. Ein Batteriegerät erst, wenn es aufwacht:
  eine Taste daran drücken und in Stunden rechnen, nicht in Minuten.
- Das System, von dem die Sicherung stammt, darf das Netz nicht weiter betreiben: ein HmIP-Netz, ein laufendes System.
- Das System protokolliert jeden Adaptertausch - welches Modul welches Netz übernommen hat, wann, ob der Schlüsselserver
  beteiligt war und wie es ausging - in `/etc/config/occulite/hmip-exchanges.jsonl`, das in jeder Sicherung enthalten
  ist. Nichts wird irgendwohin gesendet; die Seite Schnittstellen zeigt das Protokoll unter einem abgelehnten Tausch.

Vor einem Einspielen oder Import beurteilt die Seite Sicherung außerdem den HmIP-Sicherheitszähler der Sicherung;
siehe [bekannte-probleme.md](bekannte-probleme.md#hmip-geräte-nach-einem-neustart-unerreichbar-der-sicherheitszähler).

### Was sich beim ersten Start ändert

- **Namen, Räume und Gewerke** werden aus der ReGa-Datenbank gelesen. Die vordefinierten Räume und Gewerke der CCU
  bekommen ihre deutschen WebUI-Namen (*Badezimmer*, *Heizung*); Objekte, die noch einen Standardnamen wie
  `<Typ> <Adresse>` tragen, werden ausgelassen. Später importiert *Namen aus einer ReGa-Datenbank importieren* auf der
  Seite Sicherung sie aus einer `.regadom`- oder `.sbk`-Datei.
- **Nicht übernommen:** Programme, Systemvariablen, Alarme, Favoriten, Diagramme. Die Automatisierung wandert zu
  Node-RED (RedMatic), Home Assistant, ioBroker oder was man sonst schon einsetzt.
- **Addons:** die im [Katalog](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)
  funktionieren. Addons, die die ReGa brauchen (CUxD, die XML-API, …), werden deaktiviert und als *deaktiviert,
  inkompatibel* geführt. Addons mit Binaries für eine andere Architektur stehen als *deaktiviert, braucht ein Update*
  da; *Installieren* / *Aktualisieren* im Katalog holt den passenden Build
  ([addons.md](addons.md#architecture-and-addon-binaries)). Deinstalliert wird nichts.
- **Der NEO Server von mediola** läuft ohne die ReGa nicht und wird abgeschaltet.
- **Die Altlasten werden entfernt, sobald die Namen importiert sind:** `homematic.regadom` und ihre `.bak`, die
  `measurement` und `userprofiles` der WebUI, `etc/config/rega` und der NEO Server. Die Journal-Zeile
  `ccu leftovers removed` nennt sie. Funk-Identität, Schlüssel, Interface-Konfiguration und Addons bleiben.

## openccu-lite → OpenCCU / CCU3

1. **OpenCCU installieren:** Status-Seite → *Systemaktualisierung* → die `OpenCCU-<version>-<PRODUCT>.zip` von
   upstream → *Neu starten und installieren*. Anlernungen, Schlüssel und Addons bleiben in `/usr/local`. Für ein
   System mit CCU3-Layout ist es die `OpenCCU-<version>-ccu3.tgz` von upstream; dieser Weg ist ungetestet, also Backup
   und den [Ausweg über das Neuflashen](#der-ausweg-über-das-neuflashen) im Blick behalten.
2. **Die vor dem Wechsel angelegte `.sbk` einspielen**, in der WebUI von OpenCCU. Nur das bringt die ReGa-Datenbank
   zurück, mit Namen, Räumen, Programmen und Systemvariablen vom Tag des Wechsels. Was seitdem unter openccu-lite
   geändert wurde, kommt nicht mit: dafür gibt es keinen Export.

Die Namen von openccu-lite bleiben in `/usr/local/etc/occulite/meta.json` liegen, für einen späteren Wechsel zurück
zu openccu-lite.

**Verschlüsselte Sicherungen:** OpenCCU kann eine `.sbk.age` nicht lesen. Auf der Seite Sicherung *Unverschlüsselt
herunterladen (für OpenCCU oder eine CCU3)* verwenden, oder sie auf einem PC entschlüsseln:
`age -d -i key.txt -o backup.sbk backup.sbk.age` (`key.txt` enthält die Zeile `AGE-SECRET-KEY-1…` aus dem Notfallkit).

**Mit eingeschaltetem HSTS** (System → Zertifikat): HSTS ausschalten **und danach das System in jedem verwendeten
Browser einmal unter seinem Namen öffnen**, bevor OpenCCU installiert wird. Das Hochladen des OpenCCU-Pakets schaltet
HSTS von selbst aus, und die Status-Seite nennt dann die zu öffnenden Namen. Ein Browser, der das verpasst hat,
verweigert unter diesem Namen bis zu sieben Tage lang die HTTP-Seite des Recovery und das Zertifikat von OpenCCU.
`http://<IP-Adresse>/` funktioniert immer.

## Der Ausweg über das Neuflashen

Wird ein Update-Paket abgelehnt, das Image von Grund auf flashen und die `.sbk` einspielen. Alles oben gilt weiterhin;
nur der Flash-Schritt ist anders.
