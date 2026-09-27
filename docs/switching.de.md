# Wechsel zwischen OpenCCU (oder einer CCU3) und openccu-lite

*Deutsch — die englische Fassung ist [switching.md](switching.md).*

Der Wechsel **zu** openccu-lite ist ein unterstützter Vorgang. **Zurück** geht es, indem man das
Backup einspielt, das man vor dem Wechsel angelegt hat — nicht, indem man OpenCCU über lite flasht
und erwartet, dass die Konfiguration noch da ist.

**Vor der Migration ein Backup anlegen und aufbewahren.** Diese `.sbk` ist der Weg zurück. Alles
andere auf dieser Seite ist Mechanik. **Seit dem 2026-09-25 gibt es überhaupt keinen anderen Weg
zurück mehr:** nach seinem ersten Start entfernt openccu-lite die Altlasten der CCU vom userfs —
die ReGa-Datenbank (`homematic.regadom` und ihre `.bak`), die `measurement` und `userprofiles`
der WebUI, die Arbeitsdateien der ReGa und den NEO Server von mediola —, sobald die Namen daraus
importiert sind. Die Funk-Identität, die Schlüssel, die Interface-Konfiguration und die Addons
bleiben.

Die Mechanik ist die einfache Hälfte: gleiches Partitionslayout, gleiches Format von Image und
Update-Paket, und `/usr/local` — Anlernungen, Funkschlüssel, Interface-Konfiguration, Addons —
überlebt in beide Richtungen. Was nicht überlebt, ist die Datenbank der ReGa. openccu-lite betreibt
keine ReGaHss, also wird die `homematic.regadom` auf dem System vom Moment des Wechsels an nicht
mehr gepflegt: jeder Name, jeder Raum, jedes Gewerk, jedes Programm und jede Systemvariable, die
man danach ändert, existiert im Metadaten-Speicher von openccu-lite und sonst nirgends. Wer OpenCCU
zurückflasht, bekommt ein OpenCCU mit einer ReGa-Datenbank, die am Tag des Wechsels eingefroren
wurde, und daran ändert auch kein Hin- und Herkopieren einzelner Teile etwas. **Diese Seite hat
früher das Gegenteil behauptet und einen HM-Script-Export angeboten, der die Lücke überdecken
sollte. Beides ist weg (2026-09-08).**

## OpenCCU / CCU3 → openccu-lite

**Die Kurzfassung für eine OpenCCU-VM (`ova`) oder ein SD-Karten-Produkt**: in der OpenCCU-WebUI
unter Einstellungen → Systemsteuerung → Zentralen-Wartung → Software-Update durchführen die
`openccu-lite-<produkt>-<version>.zip` hochladen (**eine CCU3 nimmt stattdessen die `-ccu3.tgz`**,
siehe *Welches Paket für welches System* unten), bestätigen, neu starten lassen. Das eigene
Recovery-System von OpenCCU flasht das Image und behält `/usr/local`; das lite-System kommt mit den
Anlernungen, Schlüsseln und Addons hoch, liest beim ersten Start die Namen, Räume und Gewerke aus
der ReGa-Datenbank und fragt nach einem Administrator-Passwort. Die `.zip` wird angenommen, weil
die `/VERSION` des lite-Images die `PLATFORM` von upstream trägt — genau die vergleicht das
Recovery. **Der Weg zurück**: OpenCCU über den Abschnitt *Systemaktualisierung* der lite-Status-Seite
mit der `OpenCCU-<version>-ova.zip` von upstream flashen, dann **das vor der Migration angelegte
Backup einspielen**. Das Flashen allein ergibt ein funktionierendes OpenCCU mit den Anlernungen,
Schlüsseln und Addons — `/usr/local` überlebt —, aber seine ReGa-Datenbank ist die vom Tag des
Wechsels. Das Backup ist es, was das System wieder zu dem System macht, das es war.

### Welches Paket für welches System

Ein Release enthält pro Board mehr als eine Datei. Welche Ihr System nimmt, hängt davon ab, wie es
eingerichtet wurde, nicht von der Hardware allein — `cat /VERSION` über SSH (`PRODUCT=…`) sagt
Ihnen, welches Sie haben:

| Ihr System | Paket | Was auf dem Weg passiert |
| --- | --- | --- |
| OpenCCU, von einem OpenCCU-Image auf SD-Karte oder USB-Datenträger geschrieben (`PRODUCT=rpi3`, `rpi4`, `rpi5`, …) | `openccu-lite-<produkt>-<version>.zip` | ein Durchlauf des Recovery-Systems: es entpackt das Image auf dem userfs, schreibt Boot- und Root-Partition, behält `/usr/local`, startet neu. Etwa drei Minuten. |
| Die OpenCCU-VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | dasselbe, ein Durchlauf. |
| Eine CCU3 oder eine Karte, die aus dem CCU3-Image von eQ-3 oder einem CCU3-Backup-Image eingerichtet wurde (`PRODUCT=ccu3`: bootfs 256 MB, rootfs 1 GB, userfs) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | die WebUI entpackt das Archiv, und das Recovery führt dessen `update_script` aus: es schreibt die neue Boot-Partition — mit dem Recovery-System von openccu-lite — und übergibt, weil die Root-Partition 1 GB groß ist und das Image 2 GB, den Rest an dieses neue Recovery. **Zwei Recovery-Durchläufe, zwei Neustarts:** der zweite vergrößert die Root-Partition auf 2 GB, verschiebt dafür die Benutzerpartition und schreibt das Root-Dateisystem. Rechnen Sie damit, dass das System zehn Minuten oder länger dunkel ist. |

Die `.zip` ist für ein System mit CCU3-Layout das falsche Paket: ihr Image ist für eine SD-Karte
aufgeteilt, und das Recovery bräuchte ohnehin die entpackten 2,4 GB auf dem userfs. Die `-ccu3.tgz`
ist der für dieses Layout gebaute Weg (der Pfad CCU3 → OpenCCU von upstream, den openccu-lite
weiterverwendet).

### Der Platz, den das Update braucht

Das Recovery entpackt das Update **auf dem userfs (`/usr/local`), bevor es irgendetwas schreibt**:
das Image der `.zip` hat entpackt etwa 2,4 GB, das Root-Dateisystem der `-ccu3.tgz` 2 GB, jeweils
zusätzlich zum Upload selbst. Prüfen Sie das vorher — die WebUI zeigt es auf der Seite
*Zentralen-Wartung* unter *Software-Update durchführen* als *Verfügbarer Speicherplatz: X GB (> 2,8 GB
erforderlich)*, und über SSH zeigt `df -h /usr/local` es in der Spalte *Avail*. **Unter 2,8 GB frei:
nicht starten.** Alte Backups unter `/usr/local/tmp` und große Addon-Daten sind der übliche Grund;
räumen Sie sie zuerst weg. Auf einer Karte mit CCU3-Layout, deren Benutzerpartition nicht bis zum
Ende der Karte reicht, vergrößert das Recovery von openccu-lite sie — das hilft aber erst im zweiten
Durchlauf, und nur, wenn der freie Platz hinter der Partition liegt, nicht, wenn die Partition voll
ist.

### Vor dem Wechsel prüfen

- **Ein Backup angelegt und aufbewahrt** — die `.sbk` aus Einstellungen → Systemsteuerung →
  Sicherheit → Backup erstellen (oder `createBackup.sh`), vom System heruntergeladen. Sie ist der
  Weg zurück.
- **Genug freier Platz** auf dem userfs (oben): mindestens 2,8 GB.
- **Das richtige Paket** für die Form Ihres Systems (die Tabelle oben), seine `.sha256` geprüft.
- **SSH oder physischer Zugang zur Hand.** Ein Wechsel, der auf halbem Weg stehen bleibt, lässt das
  System in seinem Recovery-System zurück, das nur einfaches HTTP auf Port 80 spricht; auf einer CCU3
  ist das Recovery-Blinkmuster der LED der Hinweis. Halten Sie die SD-Karte oder die Konsole der VM
  erreichbar und notieren Sie die Adresse des Systems: ein fehlgeschlagenes Update kann mit einer
  neuen DHCP-Adresse zurückkommen.
- **Eine Stromversorgung, der Sie vertrauen**, für die ganze Dauer: der zweite Durchlauf schreibt
  Partitionstabellen.

### Ein Recovery, das in seinem Menü stehen bleibt

Ein Recovery-System, das nach einem unbeaufsichtigten Update oben bleibt — eine dunkle WebUI, und
`http://<system>/` zeigt das Menü des Recovery statt der Update-Ausgabe —, bedeutet: **das Update
ist fehlgeschlagen, und das Recovery hat das normale System nicht gestartet.** Das CCU3-Recovery von
eQ-3 aus dem Jahr 2018, das jede CCU3 vor ihrem ersten openccu-lite-Update ausführt, tut genau das:
sein unbeaufsichtigtes Update bleibt bei jedem Fehler im Menü stehen, und der Grund steht nur so
lange auf der Seite, wie die Ausgabe noch da ist (die Recovery-Seite zeigt die Ausgabe des laufenden
Updates; ist es vorbei, das Menü). Die Recovery-Systeme von OpenCCU und openccu-lite starten nach
einem fehlgeschlagenen unbeaufsichtigten Update stattdessen das normale System, und openccu-lite
behält den Grund: die letzten Zeilen von `/usr/local/var/recovery/<zeit>.log`, die das Journal beim
nächsten Start übernimmt.

**Der Weg zurück aus dem Menü:** *Normal Reboot* auf der Recovery-Seite startet das System, das vorher
da war (`/usr/local` und die Anlernungen unangetastet), und Sie können sich Platz, Paket und `.sbk`
ansehen und von vorn beginnen. *Check storage* auf derselben Seite lässt `e2fsck` über die
Partitionen laufen und zeigt, was es repariert hat — nützlich nach einem fehlgeschlagenen zweiten
Durchlauf. Was Sie nicht tun sollten: dasselbe Paket aus dem Menü heraus noch einmal hochladen, ohne
zu wissen, warum der erste Versuch fehlgeschlagen ist. Der Platz ist der übliche Grund, und er wächst
nicht von selbst.

1. **Backup** auf dem alten System (Einstellungen → Systemsteuerung → Sicherheit → Backup
   erstellen, oder `createBackup.sh`). Die `.sbk` aufbewahren.
2. **Flashen / aktualisieren** auf openccu-lite. Der Updater nimmt das Paket an; das
   Recovery-System ist das von upstream.
3. **Erster Start**: wer an Ort und Stelle aktualisiert hat, dessen System hat seine Anlernungen
   und Schlüssel schon — `/usr/local` wurde nicht angefasst —, und das Administrator-Passwort wird
   einmal gesetzt. Wer neu geflasht hat, **spielt zuerst die `.sbk` ein** (die Seite Sicherung ist
   erreichbar, sobald ein Wegwerf-Administrator angelegt ist): das Einspielen ersetzt `/usr/local`
   komplett — Anlernungen, Schlüssel, Addons und auch den eigenen Zustand von `occulited` —, der
   vor dem Einspielen angelegte Administrator ist also weg, und das System fragt beim nächsten
   Besuch wieder nach einem. Diese Reihenfolge ist Absicht: nichts vom alten System geht verloren,
   und nichts aus der Zeit vor dem Einspielen bleibt zurück. Die ReGa-Datenbank im Backup wird
   angenommen und einfach ignoriert.
3a. **Angelernte Geräte aus der Sicherung statt eines Restores** (eine Neuinstallation, noch nichts
   angelernt): Die Seite Sicherung liest die `.sbk` einmal, und *Angelernte Geräte importieren und neu
   starten* übernimmt die Anlernungen der drei Funkarten mit ihrer Identität - BidCos-Adresse und
   Schlüsselspeicher, die HmIP-Identität, die LAN-Gateways - und zuvor die Namen, Räume und Gewerke der
   ReGa-Datenbank der Sicherung; dann startet das System neu. Zwei Dinge sagt Ihnen das Panel, bevor Sie
   klicken:
   - **Ein anderes Funkmodul.** Die HmIP-Identität einer Sicherung ist an das Funkmodul des Systems
     gebunden, das sie angelegt hat. Betreibt dieses System HmIP-RF auf einem anderen Modul (eine andere
     SGTIN), übernimmt hmipserver die Identität beim Start nach dem Import auf dieses Modul - der
     *Adaptertausch*: offline, wenn die Sicherung von einem System im lokalen Schlüsselmodus stammt,
     sonst über den Schlüsselserver von eQ-3, der eine Internetverbindung braucht und dieses Modul kennen
     muss. Jedes HmIP-Gerät wird danach für das neue Modul umgeschlüsselt; ein Batteriegerät erst, wenn
     es aufwacht - drücken Sie eine Taste daran, wenn es stumm bleibt, und rechnen Sie in Stunden, nicht
     in Minuten. Die Seite Schnittstellen zeigt, wie die Übernahme ausging (offen, erledigt, abgelehnt),
     und bietet einen neuen Versuch an - einen Neustart von HmIP-RF, das den Tausch bei jedem Start
     versucht. Ein Modul, das der Schlüsselserver ablehnt, lässt HmIP-RF gestoppt; der Ausweg ist das
     vorherige Modul oder ein Neubeginn mit diesem (jedes HmIP-Gerät neu anlernen). BidCos-RF braucht
     keinen Tausch: rfd läuft mit der importierten Adresse und Seriennummer auf dem Modul, das es hat -
     RPI-RF-MOD, HM-MOD-RPI-PCB, HmIP-RFUSB, HM-CFG-USB-2 oder LAN-Gateway gleichermaßen -, und die Seite
     Schnittstellen sagt, ob es das tut.
   - **Ein eigener BidCos-Sicherheitsschlüssel.** Der Schlüsselspeicher der Sicherung kommt so mit, wie
     er ist - die damit angelernten BidCos-Geräte kennen diesen Schlüssel -, und Sie werden nicht nach
     der Passphrase des anderen Systems gefragt (nichts auf diesem System braucht sie). Bewahren Sie
     diese Passphrase trotzdem sicher auf: Sie brauchen sie, um den Schlüssel später zu ändern oder ein
     Gerät anzulernen, das ihn noch trägt. Ein System, das schon einen eigenen Schlüssel hat, bestätigt,
     dass der der Sicherung ihn ersetzt; ein System mit angelernten Geräten lehnt den Import ganz ab, so
     dass kein angelerntes Gerät dadurch je umgeschlüsselt wird.
4. **Namen, Räume und Gewerke**: solange die alte CCU noch erreichbar ist, holt *Namen → Von einer
   CCU importieren* sie über deren Remote-Script-Port (8181). Die Firewall der alten CCU muss das
   neue System zulassen (REGA: *Vollzugriff*, oder die neue Adresse in der Liste). Räume und Gewerke
   werden zu flachen Knoten; Objekte, die noch den Standardnamen `<Typ> <Adresse>` der CCU tragen,
   werden ausgelassen und gezählt. Ist die alte CCU weg, denselben Import von irgendeiner CCU
   ausführen, auf der das Backup eingespielt ist, oder eine früher exportierte `meta.json`
   importieren.

   **Umlaute**: die ReGa-Datenbank deklariert `iso-8859-1` und ist es nicht — sie ist gemischt.
   Die Strings von eQ-3 selbst sind wirklich Latin-1 (eine Einheit ist das einzelne Byte für
   „°C“), während ein Name, den ein Benutzer auf einer aktuellen Firmware eingetippt hat, in
   derselben Datei UTF-8 ist. Beides wird richtig gelesen; vor dem 2026-09-07 kam jeder Umlaut in
   einem Namen als `Ã¼` an. Wer einen Import sieht, der mit einem älteren Image gemacht wurde,
   sieht genau das, und ein erneuter Import auf einem aktuellen Image behebt es. Ein System, dessen
   ReGa denselben Raum in beiden Kodierungen hat — was auf einer CCU vorkommt, die mehrere
   Firmware-Generationen durchlaufen hat —, endet hier mit einem Raum, nicht mit zwei.

   **Die eigenen Räume und Gewerke der CCU**: die elf Räume und zehn Gewerke, die eine CCU von
   selbst anlegt (Wohnzimmer … Terrasse, Licht … Energiemanagement), stehen in der ReGa unter einem
   Übersetzungsschlüssel — `roomBathroom` oder `${roomBathroom}` —, und die WebUI setzt auf jeder
   Seite den Namen aus ihren Sprachdateien ein. Jeder Import (von diesem System, aus einem Backup,
   von einer laufenden CCU) macht jetzt dasselbe, mit den deutschen Namen der WebUI: aus
   `roomBathroom` wird *Badezimmer*, aus `funcHeating` *Heizung*. Übersetzt wird nur ein Name, der
   genau einer dieser Schlüssel ist; ein selbst eingetippter bleibt, wie er ist, und ein englisches
   System benennt sie von Hand um. Ein Speicher, der vor dieser Änderung importiert wurde (er
   zeigt `roomBathroom`, `funcCentral` … in der Seitenleiste der App), wird beim Start von
   `occulited` korrigiert: diese Knoten werden an Ort und Stelle umbenannt, behalten ihre Ids
   (`room/roombathroom`) und damit ihre Mitglieder, und jede Umbenennung ist eine gewöhnliche
   Revision im Änderungsstrom.
5. **Was nicht mitkommt**: Programme, Systemvariablen, Alarme, Favoriten, Diagramme — hier gibt es
   nichts, das sie ausführen oder anzeigen könnte. Die Automatisierung wandert zu Node-RED
   (RedMatic), Home Assistant, ioBroker oder was man sonst schon einsetzt.
6. **Addons**: die im [Katalog](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)
   funktionieren bekanntermaßen. Addons, die die ReGa brauchen (CUxD, die XML-API, alles, was
   Systemvariablen liest oder seine Einstellungen im ReGa-DOM hält), werden **bei diesem ersten
   Start deaktiviert** und auf der Seite Zusatzsoftware als „deaktiviert, inkompatibel“ aufgeführt,
   jedes mit dem Grund; deinstalliert werden sie nicht, und ein Schalter holt eines für die Mutigen
   zurück. Der Katalog führt solche Addons gar nicht.
7. **Addons mit Binaries für eine andere Architektur** werden beim selben ersten Start deaktiviert
   und als **„deaktiviert, braucht ein Update“** aufgeführt, mit der betreffenden Datei beim Namen.
   `/usr/local` überlebt einen Wechsel, also kommt ein auf dem alten System installiertes Addon
   genau so mit, wie es war — und ein Addon, das für eine Maschine kompiliert ist, die diese nicht
   ist, kann hier nicht laufen. Siehe
   [Architecture and addon binaries](addons.md#architecture-and-addon-binaries): die Reparatur ist
   die Schaltfläche *Installieren* / *Aktualisieren* des Katalogs, die das für dieses System gebaute
   Release holt.
8. **Der NEO Server von mediola**, den das eigene Paket von OpenCCU auf das userfs entpackt
   (`/usr/local/addons/mediola`, `rc.d/97NeoServer`), kommt auch mit und kann hier nicht
   funktionieren: er postet an `/tclrega.exe` und `/api/homematic.cgi`, die ReGa und den CGI-Stack
   der WebUI. openccu-lite schaltet ihn **einmal** ab, mit dem eigenen Schalter des Addons
   (`Disabled` in seinem Verzeichnis, das sein rc.d-Script beachtet) und dem Ausführbar-Bit seines
   rc.d-Eintrags, und führt ihn mit den anderen ReGa-abhängigen Addons auf den Seiten Status und
   Zusatzsoftware auf. Nach dem ersten Start geht er mit den anderen Altlasten (was die eigene
   Deinstallation des Addons tut, `neoDisabled`-Marker eingeschlossen).
10. **Die Altlasten** (es gibt keinen Weg zurück außer dem vor der Migration angelegten Backup):
   sobald der Namensimport des ersten Starts die ReGa-Datenbank gelesen hat (oder zur Ruhe gekommen
   ist: aufgegeben hat, oder nicht nötig war, weil der Speicher Namen hält), entfernt occulited
   genau diese Liste, einmal — `homematic.regadom`, `homematic.regadom.bak`, `measurement`,
   `userprofiles`, `etc/config/rega`, den NEO Server — und schreibt `<state>/ccu-leftovers-removed.json`
   und eine Journal-Zeile (`ccu leftovers removed …`, die Pfade und die freigewordenen Bytes). Ein
   Import, der noch laufen muss, behält sie mit einer Warnung bis zu einem späteren Start. Ein
   System ohne Altlasten hält einen leeren Lauf fest, damit ein später eingespieltes CCU-Backup
   nicht ausgekehrt wird. Das Panel *Altlasten von OpenCCU* der Seite Sicherung ist weg.
9. **Der Zustand eines Addons außerhalb seines eigenen Verzeichnisses** — das Profil von
   homematic-manager in `/usr/local/hmm`, aus seinen OpenCCU-Tagen root-eigen — wird beim
   Einsperren des Addons übernommen: dem Benutzer des Addons übereignet und in seiner Unit
   beschreibbar gemacht, beim Einsperren und wieder bei jedem Start, sodass ein Addon, das
   eingesperrt wurde und dann seinen eigenen Zustand nicht schreiben konnte, vom nächsten Update
   repariert wird.

### Abnahmetest auf einer VM (erster Lauf 2026-09-06)

Was „alles funktioniert weiter“ heißt, als Checkliste. Auf einem Proxmox-Snapshot der OpenCCU-VM
ausführen, damit der Weg zurück ein Klick ist, selbst wenn der Software-Weg zurück scheitert.

1. Vorher: in der OpenCCU-WebUI die Geräteanzahl, einen Gerätenamen, einen Raum, den Zustand des
   Sicherheitsschlüssels (Einstellungen → Systemsteuerung → Sicherheit), die LAN-Gateways, die
   Addons, die IP/den Hostnamen notieren. Ein `.sbk`-Backup und den Proxmox-Snapshot anlegen.
2. Die `openccu-lite-x86_64-ova-<version>.zip` unter Einstellungen → Systemsteuerung →
   Zentralen-Wartung → Software-Update durchführen hochladen, bestätigen, neu starten lassen. Das
   Recovery zeigt seinen Fortschritt auf der Konsole; das Ganze dauert ~3 Minuten.
3. Erster Besuch von `http://<system>/`: die Willkommensseite fragt nach einem
   Administrator-Passwort und zeigt das Ergebnis des regadom-Imports — Geräte, Kanäle, Räume und
   Gewerke gezählt. `curl http://<system>/api/system/v1/status` → `first_boot_import` hat dieselben
   Zahlen.
4. Prüfen, in dieser Reihenfolge: **Funk** (Modul erkannt, `hm_mode` wie vorher,
   Sicherheitsschlüssel „gesetzt“, wenn er es war, LAN-Gateways aufgeführt), **Namen** (das
   notierte Gerät hat seinen Namen, der Raum existiert mit seinen Kanälen), **Zusatzsoftware**
   (dieselbe Liste, läuft), **Netzwerk** (Adresse und Hostname unverändert), **Protokoll**
   (rfd-/hmipserver-Zeilen, keine Fehlerschleife), **Dienste** (rfd, hmipserver laufen). Die
   Dateien, die man von OpenCCU kennt (`/var/log/messages`, `hmserver.log`, `lighttpd-*.log`),
   sind hier das Journal: die Seite Protokoll, ihr Download, oder `journalctl` (`-t hmipserver`,
   `-t lighttpd`).
5. Ein Geräte-Rundlauf: ein angelerntes Gerät drücken, sein Kanal-Ereignis auf der Seite Namen oder
   über `/api/system/v1/radio/health` beobachten (der Duty Cycle aktualisiert sich) — wenn ja, hat
   die Anlernung überlebt.
6. Der Weg zurück: auf der Status-Seite die `OpenCCU-<version>-ova.zip` (die von upstream)
   hochladen, *Neu starten und installieren*. OpenCCU kommt **ohne** seine ReGa-Datenbank zurück
   (openccu-lite hat `homematic.regadom` nach seinem ersten Start entfernt): das vor dem Wechsel
   angelegte Backup einspielen. Eine `meta.json` unter `/usr/local/etc/occulite/` bleibt für den
   nächsten Wechsel liegen.
   Das ist die zweite Hälfte des Abnahmetests: **beide Richtungen, kein Neuflashen**.

Was auf dieser Liste scheitert, ist ein Bug, keine Dokumentationslücke.

### Was der Lauf vom 2026-09-07 gefunden hat

Der Hinweg wurde in der Nacht vom 2026-09-06 auf den 07. auf einer Test-VM gefahren, mit einem
`ova-lite-systemd`-Image, das in dieser Nacht gebaut wurde. Er fand siebenundzwanzig Bugs, drei
davon kann die Checkliste oben nicht formulieren, weil vorher niemand so weit gekommen war:

- das System startete **ganz ohne Firewall** — nichts, was in Tcl geschrieben war, lief;
- **das Update ließ sich einmal installieren und nie wieder**: die eigene `/VERSION` des
  Recovery-Systems behielt den lite-Produktnamen, während die des Images auf den von upstream
  umgeschrieben wird, sodass das Recovery, das ein lite-Image installiert, jedes lite-Image
  ablehnt — und auch die `ova.zip` von upstream, also Schritt 6 dieser Liste, den Weg zurück;
- die Seite Netzwerk und die LAN-Gateway-Liste waren auf einem System leer, das beides hatte, und
  ein Speichern hätte diese Leere zurückgeschrieben.

Mit diesen Korrekturen besteht die Liste: das System installiert eine Release-Zip von seiner
eigenen Status-Seite und ist nach zweieinhalb Minuten mit seinen Addons, seinem Metadaten-Speicher
und seiner Konfiguration intakt zurück; *Namen → Namen aus einer ReGa-Datenbank importieren* liest die
eigene ReGa-Datenbank des Systems und meldet, was es gefunden hat; die Seiten Funk, Namen, Zusatzsoftware, Netzwerk,
Protokoll und Dienste antworten alle mit dem wirklichen Zustand des Systems; und die fünf
geprüften Katalog-Addons installieren sich, starten in ihren eigenen Units und überleben das
Firmware-Update.

### Schritt 6, der Rundlauf, gefahren am 2026-09-07 06:26–06:46

Beide Richtungen, auf derselben Test-VM, mit der eigenen
`OpenCCU-3.89.8.20260719-ova.zip` von upstream (403 218 494 B, Prüfsumme gegen die `.sha256` des
Releases geprüft) und der `…-lite.0-beta.1-ova-lite-systemd.zip` der Nacht:

| | wie | dauerte |
| --- | --- | --- |
| lite → OpenCCU | die lite-Status-Seite: `POST /system-update/upload` (angenommen, `board: ova` gegen die laufende `platform: ova`), dann *Neu starten und installieren* | 3 min |
| OpenCCU → lite | der **eigene** WebUI-Weg von OpenCCU: seine `cp_maintenance.cgi` prüfte die Zip (sie sucht darin nach `EULA.de`/`EULA.en` — die lite-Zip trägt beide), legte sie bereit und startete neu | 2,5 min |

Was auf der OpenCCU-Seite zurückkam: `ReGaHss` läuft und antwortet auf `rega_script`
(`dom.GetObject(1555).Name()` → `HM-CC-TC JEQ0230153`, dreizehn Raumobjekte), `rfd`, lighttpd,
`sshd`, mosquitto und das Node-RED von RedMatic, die vier Addons weiterhin in `/usr/local/addons`
mit ihren `rc.d`-Links, `homematic.regadom` unberührt mit seinem Zeitstempel von vor dem Wechsel,
und `meta.json` wartend unter `/usr/local/etc/occulite/` auf den nächsten Wechsel. Das eigene
Protokoll des Recovery für den Hinweg lohnt einmal das Lesen: *„[2/5] Checking update_script… no
'update_script', OK … flashing bootfs…OK, updating bootloader (GRUB)… OK, flashing rootfs……OK,
DONE“* — das Recovery von upstream flasht ein openccu-lite-Image ohne ein Wort über die Plattform,
und genau dafür behält die `/VERSION` des lite-Images das `PRODUCT` von upstream.

Und danach wieder auf der lite-Seite: keine fehlgeschlagenen Units, die vier `addon-*.service`-Units
aktiv, 55 Firewall-Regeln, kein Marker für ein unsauberes Herunterfahren, die Administrator-Anmeldung
funktioniert und der Metadaten-Speicher steht weiterhin auf Revision 1, mit dem auf der lite-Seite
umbenannten Kanal und seinem Raum-Enum (`BidCos-RF.JEQ0230153:1` → *Wohnzimmer Thermostat*,
`room/wohnzimmer`). **Nichts musste neu geflasht werden, und nichts wurde aus einem Backup
eingespielt.**

Der Rundlauf fand einen Bug: die Id des Benutzers `occulite` wurde automatisch aus dem System-Pool
von buildroot (100…999) vergeben, demselben Pool, den upstream mit *seinen* Systembenutzern füllt,
sodass auf der OpenCCU-Seite der Metadaten-Speicher — `users.json`, `local-token` — dem
Privilege-Separation-Benutzer des `sshd` von upstream gehörte. Die Id ist jetzt auf 8100 festgelegt;
beide Init-Pfade reparieren die Eigentümerschaft des Speichers ohnehin beim Start, sodass ein
älteres System in die Änderung hinein aktualisiert, ohne es zu merken.

## openccu-lite → OpenCCU / CCU3

**Das Einzige, was zählt: das Backup einspielen, das vor der Migration angelegt wurde.** Alles
Folgende setzt voraus, dass es da ist. Wer es nicht hat, kommt trotzdem zu einem laufenden OpenCCU
zurück — nur nicht zu *seinem* OpenCCU.

0. **Was openccu-lite entfernt hat**: `homematic.regadom` und die Daten der WebUI sind nach seinem
   ersten Start weg. Auf der lite-Seite geänderte Namen, Räume und Gewerke leben im
   Metadaten-Speicher und sonst nirgends. Programme und Systemvariablen waren auf der lite-Seite
   nie vorhanden. OpenCCU wacht also so auf, wie man es verlassen hat — und genau deshalb ist das
   Backup von vor der Migration die Antwort und kein Nachgedanke.
1. **Flashen / aktualisieren** auf OpenCCU: lite-Status-Seite → *Systemaktualisierung* → die
   `OpenCCU-<version>-<PRODUCT>.zip` von upstream → *Neu starten und installieren*. `/usr/local`
   überlebt, also sind Anlernungen, Funkschlüssel und Addons schon da. Ein System mit CCU3-Layout
   (`PRODUCT=ccu3`) hat nach dem Wechsel eine 2-GB-Root-Partition, was auch das aktuelle Layout von
   upstream ist; sein Weg zurück ist die `OpenCCU-<version>-ccu3.tgz` von upstream — ein Weg, der
   hier noch nicht gelaufen ist, behalten Sie also die `.sbk` und den Reflash-Ausweg unten im Blick.
2. **Die `.sbk` von vor der Migration einspielen**, über die eigene WebUI von OpenCCU. Das ist der
   Schritt, der das System wieder zum eigenen macht.
3. Die `meta.json` des Metadaten-Speichers bleibt in `/usr/local/etc/occulite/` und wird von all dem
   nicht berührt, sodass ein späterer Wechsel zu lite seine Namen dort findet, wo er sie gelassen
   hat.

**Mit eingeschaltetem HSTS** (System → Zertifikat): HSTS ausschalten, dann **das System in jedem
verwendeten Browser einmal unter seinem Namen öffnen**, bevor die Zip von OpenCCU installiert
wird — oder das System nach dem Wechsel über seine IP-Adresse öffnen. Das Hochladen einer Datei, die
kein openccu-lite-Release ist, schaltet HSTS von selbst aus, und die Status-Seite nennt dann die
Namen, die zu öffnen sind. Solange HSTS aus ist, sendet das System `Strict-Transport-Security:
max-age=0`, und zwar so lange, wie die Frist war, höchstens 30 Tage, und ein Browser, der das
sieht, vergisst HSTS für diesen Namen. Ein Browser, der in dieser Zeit nicht vorbeikam, erinnert
sich weiterhin: das Recovery-System, das OpenCCU installiert, liefert nur reines HTTP, und OpenCCU
liefert ein selbstsigniertes Zertifikat, sobald das von lite installierte weniger als einen Tag vor
dem Ablauf steht (upstream erneuert nichts und ersetzt es). Ein solcher Browser verweigert beides
unter diesem Namen — die Recovery-Seite als *Verbindung abgelehnt*, das Zertifikat von OpenCCU ohne
einen Weg daran vorbei —, bis das max-age nach seinem letzten HTTPS-Besuch abgelaufen ist
(standardmäßig sieben Tage). `max-age=0` muss den Browser **vor** dem Wechsel erreichen: weder das
Recovery-System noch OpenCCU können es senden. `http://<IP-Adresse>/` funktioniert immer, denn
HSTS gilt nie für eine Adresse; der Installationshinweis der lite-Status-Seite verlinkt das
Recovery auf diesem Weg.

**Es gibt keinen Export, mit dem sich Namen zurücktragen ließen.** Genau dafür gab es früher einen
HM-Script-Export, und er wurde am 2026-09-08 entfernt: er verleitete dazu, eine halbe Migration als
umkehrbar zu behandeln, wo die ehrliche Antwort ein Backup ist. Programme, Systemvariablen und
alles andere, das nur die ReGa versteht, waren auf diesem Weg ohnehin nie ausdrückbar.

**Verschlüsselte Sicherungen:** eine `.sbk.age` von der lite-Seite Sicherung ist keine `.sbk` für
OpenCCU oder eine CCU3. Für den Weg zurück entweder *Unverschlüsselt herunterladen (für OpenCCU oder
eine CCU3)* auf dem laufenden lite-System verwenden — es fragt nach dem Passwort und wird im Journal
festgehalten — oder die `.sbk.age` auf einem PC entschlüsseln, mit
`age -d -i key.txt -o backup.sbk backup.sbk.age`, wobei `key.txt` die Zeile `AGE-SECRET-KEY-1…` aus
dem Notfallkit enthält. Die `.sbk` von vor der Migration, der Weg zurück, war nie verschlüsselt.

## Der Ausweg über das Neuflashen

Lehnt der eine Updater das Paket des anderen ab (eine Versionsprüfung, eine geänderte
Partitionstabelle), das Image von Grund auf flashen und die `.sbk` einspielen. Alles oben gilt
weiterhin; nur der Flash-Schritt ändert sich — und das Backup leistet so oder so dieselbe Arbeit.
