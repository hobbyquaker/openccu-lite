# Wechsel zwischen OpenCCU (oder einer CCU3) und openccu-lite

*Deutsch — die englische Fassung ist [switching.md](switching.md).*

**Vor dem Wechsel ein Backup (`.sbk`) anlegen und aufbewahren. Es ist der Weg zurück**, und eine
[Kopie des ganzen Systems](#zuerst-eine-kopie-des-ganzen-systems) ist der schnellere. Nach seinem ersten
Start entfernt openccu-lite die ReGa-Datenbank der CCU und die Daten der WebUI vom System (siehe
[Was sich beim ersten Start ändert](#was-sich-beim-ersten-start-ändert)). Wer ohne das Backup zu OpenCCU zurückflasht,
bekommt ein laufendes OpenCCU mit Anlernungen und Schlüsseln, aber ohne Namen, Räume, Programme und Systemvariablen.

## OpenCCU / CCU3 → openccu-lite

In der WebUI von OpenCCU oder der CCU3: Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update
durchführen, das Paket (unten) hochladen, bestätigen, neu starten lassen. Anlernungen, Schlüssel, die
Interface-Konfiguration und die Addons bleiben in `/usr/local`. Beim ersten Start übernimmt das System die Namen,
Räume und Gewerke aus der ReGa-Datenbank und fragt nach einem Administrator-Passwort.

**Dieses Update über das bestehende System ist der empfohlene Weg**, nach einer
[Kopie des ganzen Systems](#zuerst-eine-kopie-des-ganzen-systems): einem Snapshot oder Klon der VM, einer Kopie der
SD-Karte. Eine Neuinstallation mit dem Import der Sicherung des alten Systems ist für ein neues oder ersetztes System.

### Welches Paket für welches System

`cat /VERSION` über SSH (`PRODUCT=…`) zeigt, was für ein System es ist:

| Ihr System | Paket | Was passiert |
| --- | --- | --- |
| OpenCCU auf SD-Karte oder USB-Datenträger (`PRODUCT=rpi3`, `rpi4`) | `openccu-lite-<produkt>-<version>.zip` | ein Recovery-Durchlauf, ein Neustart, etwa drei Minuten |
| Die OpenCCU-VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | dasselbe |
| Eine CCU3 oder eine Karte aus einem CCU3-Image oder CCU3-Backup-Image (`PRODUCT=ccu3`) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | zwei Recovery-Durchläufe und zwei Neustarts: der zweite vergrößert die Root-Partition auf 2 GB. Mit etwa 25 Minuten ab dem Start des Updates rechnen, auf einer langsameren oder größeren Karte bis zu 30-40 Minuten (siehe [unten](#ein-dunkles-update-auf-einem-raspberry-pi-3-oder-charly)). |

Die `.zip` ist für ein System mit CCU3-Layout das falsche Paket; dort die `-ccu3.tgz` nehmen.

**Eine Neuinstallation** braucht kein Update: die `.img` aus der `.zip` des Releases auf eine SD-Karte schreiben
(Raspberry Pi 3/4) oder die `.ova` importieren (Proxmox, VMware, VirtualBox). Die Geräte des alten Systems kommen dann
per [Import seiner Sicherung](#geräte-in-eine-neuinstallation-übernehmen) dazu.

### Der Platz, den das Update braucht

Das Recovery entpackt das Update auf dem userfs (`/usr/local`), bevor es etwas schreibt. **Nötig sind mindestens
2,8 GB frei.** Die WebUI zeigt das unter *Software-Update durchführen* (*Verfügbarer Speicherplatz*), über SSH
`df -h /usr/local`. Alte Backups unter `/usr/local/tmp` und große Addon-Daten sind die üblichen Platzfresser; vorher
wegräumen.

### Vor dem Wechsel prüfen

- **Ein Backup**, angelegt unter Einstellungen → Systemsteuerung → Sicherheit → Backup erstellen und vom System
  heruntergeladen.
- **Eine Kopie des ganzen Systems:** ein Snapshot oder Klon der VM, eine Kopie der SD-Karte (unten).
- **2,8 GB frei** auf dem userfs.
- **Das richtige Paket** (Tabelle oben), seine `.sha256` geprüft.
- **Zugang, falls etwas schiefgeht:** die Adresse des Systems notiert (ein fehlgeschlagenes Update kann mit einer neuen
  DHCP-Adresse zurückkommen), SD-Karte oder Konsole der VM erreichbar.
- **Sichere Stromversorgung** für das ganze Update: der zweite Durchlauf auf der CCU3 schreibt Partitionstabellen.

### Zuerst eine Kopie des ganzen Systems

Das Backup bringt die ReGa-Datenbank und `/usr/local` zurück, aber nur auf ein laufendes OpenCCU. Eine Kopie des
ganzen Systems ist OpenCCU genau so, wie es war, bereit zum erneuten Start. Für die Kopie OpenCCU über seine WebUI
herunterfahren, damit währenddessen nichts geschrieben wird. Was sich später unter openccu-lite ändert (Geräte
angelernt oder entfernt, ein Schlüssel geändert), ist nicht in der Kopie.

**Eine VM: ein Snapshot oder ein Klon.** Proxmox VE, VMware, VirtualBox und Hyper-V (dort Prüfpunkt genannt) legen
einen Snapshot einer VM an; Proxmox VE und VirtualBox machen auch einen vollständigen Klon. Proxmox VE legt einen
Snapshot nur an, wenn die Platte der VM auf einem Speicher liegt, der das kann (eine `qcow2`-Platte auf Verzeichnis-
oder NFS-Speicher, ZFS, LVM-thin, Ceph und andere); sonst die VM klonen. Dann die VM starten und aktualisieren. Der
Weg zurück ist das Zurücksetzen auf den Snapshot oder der Klon. Einen Klon ausgeschaltet lassen, solange die andere VM
läuft: ein Funkmodul, ein laufendes System.

**Ein Raspberry Pi: eine Kopie der SD-Karte** (oder des USB-Datenträgers, von dem er startet). Die Karte aus dem
heruntergefahrenen System nehmen und auf einem PC in eine Image-Datei lesen oder auf eine zweite, mindestens gleich
große Karte kopieren; dann eine Karte wieder einsetzen und aktualisieren. Werkzeuge dafür:

- Windows: [Win32 Disk Imager](https://sourceforge.net/projects/win32diskimager/), *Read* in eine `.img`-Datei.
- Linux: die Karte mit `lsblk` finden, dann `sudo dd if=/dev/sdX of=openccu.img bs=4M status=progress`.
- macOS: die Karte mit `diskutil list` finden, `diskutil unmountDisk /dev/diskN`, dann
  `sudo dd if=/dev/rdiskN of=openccu.img bs=4m`.
- [balenaEtcher](https://etcher.balena.io/) (Windows, macOS, Linux): *Clone drive* kopiert die Karte auf eine zweite
  Karte; eine Image-Datei schreibt es nicht.

Der Raspberry Pi Imager schreibt nur Karten und kann keine lesen. Der Weg zurück ist die Kopie: die zweite Karte oder
das wieder auf eine Karte geschriebene Image (*Write* im Win32 Disk Imager, balenaEtcher, Raspberry Pi Imager oder
`dd`).

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

Auf der Seite Sicherung prüft *Sicherung einspielen oder importieren* die hochgeladene `.sbk`, sagt im Abschnitt
*Diese Datei*, was sie ist und was sie enthält, und bietet den einen Weg an, der zu ihr passt:

- **Eine Sicherung von OpenCCU, RaspberryMatic oder einer CCU3 wird importiert, nie eingespielt** (*In dieses System
  importieren*, dann *Importieren und neu starten*). Immer übernommen werden die angelernten Geräte aller drei
  Funkschnittstellen mit Funk-Identität und Schlüsseln, die LAN-Gateways und die Namen, Räume und Gewerke aus der
  ReGa-Datenbank der Sicherung. *Außerdem aus der Sicherung übernehmen:* bietet an, was die Sicherung vom Rest
  enthält, jedes mit einem Kästchen:
  - die Zusatzsoftware mit ihren Einstellungen (angehakt; ein Addon, das die ReGa braucht oder dessen Programme für
    einen anderen Prozessor sind, kommt deaktiviert, und ein hier schon installiertes bleibt, wie es ist);
  - die Adresse des HB-RF-ETH (angehakt; die Platine bedient ein System, das alte muss also aus sein);
  - den Hostnamen (nur angehakt, solange dieses System keinen eigenen Namen hat: zwei Systeme mit einem Namen
    verwirren den Router);
  - den Syslog-Server (`LOGHOST`, angehakt);
  - klassisches RPC wie auf dem alten System (nie angehakt; siehe
    [Was sich beim ersten Start ändert](#was-sich-beim-ersten-start-ändert)).

  *Was auf dem alten System zurückbleibt* nennt den Rest: Programme, Systemvariablen und Skripte der ReGa, die
  Benutzer der alten WebUI, die Netzwerkeinstellungen außer dem Hostnamen, die Firewall außer klassischem RPC, das
  Web-Zertifikat, SSH-Schlüssel und das root-Passwort, Zeitzone, Zeitserver und Standort, die Protokollstufen, crontab
  und monit, was ein Addon außerhalb seiner eigenen Verzeichnisse ablegt, den NEO Server von mediola und alles andere
  unter `/usr/local`.
- **Der Import braucht ein System ohne angelernte Geräte**: er übernimmt die Funk-Identität dieses Systems, und dort
  angelernte Geräte wären verwaist. Auf einem System mit Geräten lehnt die Seite ihn ab und zeigt den Weg dorthin,
  *Werkseinstellungen* am Ende derselben Seite, das alles auf dem System löscht (vorher eine Sicherung anlegen, wenn
  dort etwas erhaltenswert ist). Die Namen allein lassen sich auch so übernehmen, wenn die Sicherung eine
  ReGa-Datenbank enthält: *Namen aus dieser Sicherung importieren*.
- **Eine Sicherung von openccu-lite wird eingespielt** (*Auf dieses System einspielen*, dann *Einspielen und neu
  starten*): alles unter `/usr/local` wird ersetzt, die angelernten Geräte und Schlüssel, die Namen, die Addons mit
  ihren Einstellungen, das Netzwerk und jede andere Einstellung, die Benutzer und API-Tokens. Der vor dem Einspielen
  angelegte Administrator ist danach weg.

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
  `<Typ> <Adresse>` tragen, werden ausgelassen. Später bringt sie eine auf der Seite Sicherung hochgeladene
  `.sbk`: der Import übernimmt sie immer, und auf einem System mit angelernten Geräten übernimmt *Namen aus dieser
  Sicherung importieren* sie allein.
- **Nicht übernommen:** Programme, Systemvariablen, Alarme, Favoriten, Diagramme. Die Automatisierung wandert zu
  Node-RED (RedMatic), Home Assistant, ioBroker oder was man sonst schon einsetzt; siehe
  [Externe Clients nach dem Wechsel](#externe-clients-nach-dem-wechsel).
- **Addons:** die im [Katalog](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)
  funktionieren. Addons, die die ReGa brauchen (CUxD, die XML-API, …), werden deaktiviert und als *deaktiviert,
  inkompatibel* geführt. Addons mit Binaries für eine andere Architektur stehen als *deaktiviert, braucht ein Update*
  da; *Installieren* / *Aktualisieren* im Katalog holt den passenden Build
  ([addons.md](addons.md#architecture-and-addon-binaries)). Deinstalliert wird nichts.
- **Skripte in `/usr/local/etc/config/rc.d/`** kommen als Addons mit und werden gestartet, auch eigene. Die für die
  CCU3 geschriebenen schlagen hier meist fehl; die Seite Zusatzsoftware zeigt dann *Von der CCU übernommen* mit der
  letzten Log-Zeile des Skripts und bietet *rc.d-Eintrag entfernen* an.
- **Der NEO Server von mediola** läuft ohne die ReGa nicht und wird abgeschaltet.
- **Klassisches RPC wird eingeschaltet, wenn die Firewall von OpenCCU die XMLRPC-Ports freigab** (`full` oder
  `restricted` in `firewall.conf`), damit die Programme, die die CCU auf 2001, 2010, 9292 oder 2000 ansprechen,
  weiterlaufen: die Klartext- und die TLS-Ports, **ohne Anmeldung**. Die Firewall-Regeln behalten ihre Quellen: die
  lokalen Netze bei `full` (jede Adresse, wenn OpenCCU den Zugriff von außen erlaubte), je eine Regel für jede
  erlaubte Adresse oder jedes erlaubte Netz bei `restricted`. Der Hinweis der Seite Firewall zur Übernahme sagt das,
  und die Seite Status warnt, solange klassisches RPC ohne Anmeldung läuft. Ausschalten oder Benutzername und Passwort
  setzen unter System → Fernzugriff. Verlangte OpenCCU auf diesen Ports eine Anmeldung (`authEnabled`, ihre
  WebUI-Konten), bleibt klassisches RPC aus, weil diese Konten nicht mitkommen; der Hinweis der Seite Firewall sagt,
  warum.
- **Der Import einer Sicherung von OpenCCU oder einer CCU3** bietet klassisches RPC als eine seiner Optionen an, mit
  den Quellen, die die alte Firewall erlaubte; sie ist nie vorab angehakt und schaltet klassisches RPC, Klartext und
  TLS und ohne Anmeldung, nur ein, wenn sie angehakt wird. Wählbar ist sie nicht, wenn das alte System auf diesen
  Ports eine Anmeldung verlangte oder klassisches RPC hier schon an ist. Eine solche Sicherung wird importiert, nie
  eingespielt; eine eingespielte Sicherung von openccu-lite bringt ihre eigenen Firewall-Regeln mit.
- **Die Altlasten werden entfernt, sobald die Namen importiert sind:** `homematic.regadom` und ihre `.bak`, die
  `measurement` und `userprofiles` der WebUI, `etc/config/rega` und der NEO Server. Die Journal-Zeile
  `ccu leftovers removed` nennt sie. Funk-Identität, Schlüssel, Interface-Konfiguration und Addons bleiben.
- **Die Diagrammdaten werden einmalig beim ersten Start entfernt:** `measurement/` auf dem USB-Stick und
  `/usr/local/etc/config/measurement`. openccu-lite hat keine Diagramme (keine Seite, um sie einzurichten oder
  anzuzeigen). Die Journal-Zeile `diagram data: … removed` nennt jeden Pfad mit seiner Größe; andere Dateien auf dem
  Stick bleiben.
- **Weitere CCU-Altlasten werden einmalig beim ersten Start entfernt:** die Konfigurationsverzeichnisse nicht mehr
  installierter Addons (`/usr/local/etc/config/addons/<id>`, z. B. `mh` von CloudMatic), der Absturz-Dump der ReGa
  `homematic.regadom.err` und ein leeres `eQ-3-Backup`. Jedes wird mit Pfad und Größe protokolliert
  (`ccu remnants: removed`).

Alles, was beim ersten Start entfernt wird, steckt im vor dem Wechsel angelegten CCU-Backup: **dieses Backup ist der
Weg zurück.**

### Externe Clients nach dem Wechsel

Programme anderswo im Netz, die mit der CCU sprachen, behalten deren Geräte, verlieren aber alles, was die ReGa
lieferte.

- **Klassisches RPC** (die Ports 2001, 2010, 9292 und 2000 der CCU, Klartext und TLS) ist nach dem Wechsel ohne
  Anmeldung eingeschaltet, wenn die Firewall von OpenCCU die XMLRPC-Ports freigab
  ([oben](#was-sich-beim-ersten-start-ändert)); sonst ist es aus, und ein Client, der auf diese Ports eingestellt ist,
  bekommt keine Antwort, bis klassisches RPC unter System → Fernzugriff eingeschaltet ist. Die
  Schnittstellenprozesse rufen einen solchen Client unter der Adresse zurück, die er anmeldet; er muss also vom System
  aus erreichbar sein.
- **Node-RED mit [node-red-contrib-ccu](https://github.com/rdmtc/node-red-contrib-ccu#openccu-lite):** bis 4.6
  liefen klassisches RPC und ein API-Token mit `meta:read` für die Namen. Ab 4.7 spricht es die
  Schnittstellenprozesse über lite-rpc des Systems auf dem Web-Port an und zieht eine bestehende Verbindung bei ihrem
  ersten Start dorthin um. lite-rpc braucht mehr Scopes: `rpc:read` für Ereignisse und Abfragen, `rpc:operate` (das
  es einschließt) für `setValue`. **4.10.1 oder neuer** verwenden: ein Token ohne `rpc:read` behält dann die direkte
  Verbindung über klassisches RPC, das Log sagt, was lite-rpc bräuchte, und beim Verbindungstyp *openccu-lite*
  nennen die Knoten die fehlenden Scopes. In 4.7 bis 4.10.0 verlor ein solcher Token Ereignisse und Befehle
  kommentarlos. Am einfachsten ist *Pair with the system* im Verbindungsknoten: ein Administrator vergleicht den Code
  auf der Seite Status und gibt ihn frei, Token und Fingerabdruck des Zertifikats werden eingetragen. Von Hand
  angelegte API-Tokens stehen unter System → Fernzugriff. RedMatic auf dem System braucht keinen Token (ab 9.15.1).
  Die Knoten `ccu-sysvar`, `ccu-program`, `ccu-script` und `ccu-poll` beantworten jede Nachricht mit einem Fehler.
- **Home Assistant mit [Homematic(IP) Local](https://github.com/SukramJ/homematicip_local)** (`homematicip_local`):
  die Direktverbindung braucht für Anmeldung, Namen und Räume das JSON-RPC der CCU (die ReGa), das openccu-lite
  nicht hat. Die Integration verbindet sich über
  [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom), als Addon auf dem System (im Addon-Katalog) oder anderswo
  laufend, mit ihrem Backend *OpenCCU-Loom daemon*, in Version 2.12.4 als Beta gekennzeichnet.
  Wer einen bestehenden Eintrag der Integration (gesehen mit 2.12.3) auf dieses Backend umstellt, behält darin
  `username` und `password` der alten Direktverbindung; der Start bricht dann mit
  `box_token is the only credential behind the box` ab. Abhilfe: Home Assistant Core anhalten, eine Kopie von
  `.storage/core.config_entries` anlegen, im Eintrag der Integration die beiden Schlüssel `username` und `password`
  löschen und Home Assistant wieder starten. Das ist ein Verhalten der Integration; neuere Versionen können es
  anders handhaben.
- **ioBroker:** [ioBroker.hm-rpc](https://github.com/ioBroker/ioBroker.hm-rpc) verbindet sich mit den
  Schnittstellenprozessen wie mit einer CCU, über klassisches RPC (oben).
- **Was die ReGa braucht, geht nicht:** Systemvariablen, Programme, HM-Script, die JSON-RPC-API der WebUI
  (`/api/homematic.cgi`), die ReGa-Ports 1999 und 8181, und damit
  [ioBroker.hm-rega](https://github.com/ioBroker/ioBroker.hm-rega), CUxD und das XML-API-Addon. Namen, Räume und
  Gewerke liefert die Metadaten-API des Systems; [porting-from-rega.md](porting-from-rega.md) (englisch) ordnet den
  Aufrufen der ReGa ihren Ersatz zu.

## openccu-lite → OpenCCU / CCU3

1. **OpenCCU installieren:** Status-Seite → *Systemaktualisierung* → die `OpenCCU-<version>-<PRODUCT>.zip` von
   upstream → *Neu starten und installieren*. Anlernungen, Schlüssel und Addons bleiben in `/usr/local`. Für ein
   System mit CCU3-Layout ist es die `OpenCCU-<version>-ccu3.tgz` von upstream; dieser Weg ist ungetestet, also Backup
   und den [Ausweg über das Neuflashen](#der-ausweg-über-das-neuflashen) im Blick behalten.
2. **Die vor dem Wechsel angelegte `.sbk` einspielen**, in der WebUI von OpenCCU. Nur das bringt die ReGa-Datenbank
   zurück, mit Namen, Räumen, Programmen und Systemvariablen vom Tag des Wechsels. Was seitdem unter openccu-lite
   geändert wurde, kommt nicht mit: dafür gibt es keinen Export.

**Mit einer Kopie des ganzen Systems** (oben) sind beide Schritte einer: den Snapshot der VM zurücksetzen, ihren Klon
starten oder die kopierte Karte wieder einsetzen. Das ist OpenCCU vom Tag des Wechsels; was seitdem unter openccu-lite
geändert wurde, kommt auch so nicht mit.

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

Wird ein Update-Paket abgelehnt, das Image von Grund auf flashen: das von openccu-lite, dann [die Sicherung des alten
Systems importieren](#geräte-in-eine-neuinstallation-übernehmen); oder das von OpenCCU, dann die `.sbk` in dessen
WebUI einspielen. Alles oben gilt weiterhin; nur der Flash-Schritt ist anders.
