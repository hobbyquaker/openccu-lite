# openccu-lite

*Deutsch — die englische Fassung ist [README.en.md](README.en.md).*

> **Alpha-Software — bitte zuerst lesen.**
>
> openccu-lite ist im **Alpha-Stadium**. Vieles ist ungetestet, manches genau auf einem System
> getestet, und es gibt Fehler — die bekannten in [BUGS.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/BUGS.md), andere hat noch niemand
> gesehen. **Bitte nur auf Testsystemen einsetzen.** Wer es trotzdem auf der CCU wagt, die das
> eigene Haus steuert, sorgt vorher für einen schmerzfreien Weg zurück: eine **zweite SD-Karte**
> mit der laufenden Firmware (Karte tauschen, fertig) oder auf x86 ein **Klon der VM**. Zurück zu
> OpenCCU mit den eigenen Daten geht nur über ein Backup, das *vor* dem Wechsel gezogen wurde —
> siehe [docs/switching.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/switching.md).
>
> **Es richtet sich an erfahrene Anwender**, die wissen, was sie tun: Leute, denen Homematic-
> Paramsets vertraut sind und die eine CCU von innen kennen (`rfd`, `hs485d`, der
> HmIP-Server, die Addon-Mechanik, lighttpd, das Userfs) und sich in einer Shell zurechtfinden.
> Es gibt keine ReGaHSS, keinen Programm-Editor und keine Handführung; was es gibt, ist ein
> Funk-Gateway mit Namensspeicher und einer Verwaltungsoberfläche — jede Automatisierung lebt
> woanders.

Eine Homematic-CCU-Firmware ohne ReGaHSS: die Funk-Schnittstellen (`rfd`, `hs485d`,
`hmipserver`), die Addon-Mechanik und lighttpd genau so, wie OpenCCU sie baut — und an der
Stelle von WebUI und ReGa-Logik ein kleiner Go-Dienst, **`occulited`**, der das System verwaltet und
das eine behält, das jede Integration von einer CCU noch braucht: Gerätenamen und Räume.

Das System ist ein Funk-Gateway mit Namensspeicher. Die Automatisierung läuft dort, wo Anwender sie
ohnehin betreiben (Home Assistant, Smart Home Engine ("she"), Node-RED, ioBroker, ...); die
Geräteverwaltung macht [homematic-manager](https://github.com/hobbyquaker/homematic-manager),
als Addon mit einem Klick installiert.

## Versionen und Images

openccu-lite hat eine eigene semantische Version, beginnend mit **1.0.0-alpha.0**; die Kopfzeile
der Oberfläche zeigt sie. Die Images tragen in `/VERSION` zusätzlich die OpenCCU-Basis, auf der
sie gebaut sind — für das Recovery-System. Release-Artefakte heißen
`openccu-lite-<Produkt>-<Version>.<Endung>`:

| Produkt | Hardware | Artefakte |
| --- | --- | --- |
| `x86_64-ova` | eine VM (VMware, Proxmox, VirtualBox) | `….ova`, `….zip` (das Update-Paket), `….img` |
| `aarch64-rpi3` | CCU3, Charly, Raspberry Pi 3, CM3 | `….zip`, `…-ccu3.tgz` (das Update von einer CCU3 aus) |
| `aarch64-rpi4` | Raspberry Pi 4, CM4 | `….zip` |
| `aarch64-rpi5` | Raspberry Pi 5, CM5 (noch nie gebootet, Aufgabe 32) | `….zip` |
| `lxc-lite_amd64`, `lxc-lite_arm64` | ein unprivilegierter Proxmox-LXC-Container (Aufgabe 34; Funk nur über LAN-Gateways oder einen durchgereichten HmIP-RFUSB) | `openccu-lite-lxc-amd64-….tar.xz`, `openccu-lite-lxc-arm64-….tar.xz` (die CT-Vorlage) |

Ein Docker-/OCI-Image gibt es nicht: der Container ist die LXC-Vorlage. Wer eine CCU in Docker
betreiben will, nimmt das OCI-Image von OpenCCU.

openccu-lite läuft im Labor auf einer x86_64-VM, einem Raspberry Pi 4 mit HmIP-RFUSB und einer
Charly (Raspberry Pi 3 B mit RPI-RF-MOD); vor einem Release steht
[docs/hardware-checklist.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/hardware-checklist.md).

## Funktionen im Überblick

Neben Namen, Räumen, Addons, Netzwerk und Geräte-Firmware (siehe *occulited in einem Absatz*):

- **Log-Seite:** das Journal mit Filtern nach Unit, Tag, Schweregrad und Text, live mitlaufend und
  als Text oder JSON herunterladbar. Die Quelle *Alle / System / Kernel* zeigt das Kernel-Log mit
  Zeitstempeln seit dem Boot wie `dmesg`; ein Boot-Menü springt in frühere Boots, soweit das Journal
  sie hält.
- **Boot-Zeitleiste** auf der Dienste-Seite: jede Unit des Boots als Balken, die kritische Kette,
  der Vergleich mit dem vorigen Boot, Export als SVG und JSON. Die letzten zehn Boots bleiben auf
  jedem System gespeichert.
- **Wo das Journal liegt**, wählbar: nur im RAM (Standard auf den SD-Karten-Produkten); im RAM mit
  Kopien auf das Userfs alle 6 Stunden und bei jedem Herunterfahren, sodass die Karte einen
  Schreibvorgang pro Intervall sieht und ein Neustart nichts verliert; oder direkt auf das Userfs
  (Standard auf VM und Container).
- **Status-LED** (RPI-RF-MOD): occulited ist ihr einziger Schreiber, `hss_led` ist nicht mehr im
  Image. Dauerhaft blau, wenn alles in Ordnung ist, wie auf der CCU3; gelb schnell ohne Netzwerk,
  rot bei ausgefallenem Funk oder Dienst, cyan bei einem System-Update. Reihenfolge, Farben und
  Muster sind einstellbar, dazu ein Nachtmodus und *Locate*; Home Assistant oder Node-RED setzen die
  LED über die API mit einem Token, das nur das darf.
- **Backups auf Netzwerkfreigaben:** Die nächtliche Sicherung wird einmal erstellt und auf jedes
  aktivierte Ziel kopiert — ein USB-Verzeichnis, NFS, CIFS/SMB oder SSH (ein SFTP-Upload von
  occulited, mit einem auf dem System erzeugten Schlüssel und festgehaltenem Host-Key). Jedes Ziel
  zeigt seinen Zustand, hat einen Schreibtest und wird nach Fehlern neu eingehängt; alte Sicherungen
  werden erst nach einer bestätigten Lieferung gelöscht.
- **Warnungen der Statusseite** kommen aus occulited. Ein Administrator schaltet eine Warnung für 1,
  7 oder 90 Tage stumm, und die Stummschaltung endet früher, sobald die Warnung verschwindet und
  wiederkommt.

## Sicherheit

Eine CCU gibt die Gerätesteuerung über 2001, 2010 und 2000 ohne Anmeldung ins LAN, lässt Addons,
ihre CGIs und die Funk-Daemons als root laufen und schützt eine Addon-Seite nur so gut, wie das
Addon sich selbst prüft. openccu-lite dreht jede dieser Voreinstellungen um.

### Was im Netz erreichbar ist

Die Funk-Daemons und occulited lauschen nur auf dem Loopback; nach außen spricht lighttpd. Die
Firewall ist eine Liste von INPUT-Regeln in der Reihenfolge, in der sie geprüft werden, mit der Policy
`DROP` für IPv4 und IPv6: Eingehend wird verworfen, was keine Regel annimmt. Was eine eingeschaltete
Funktion braucht, trägt das System selbst als Regel mit ihrem Besitzer ein — mit einem Kommentar,
warum sie da ist — und nimmt sie beim Ausschalten wieder heraus; jede Regel lässt sich bearbeiten,
verschieben oder löschen. Eine Änderung muss innerhalb von 60 Sekunden bestätigt werden, sonst stellt
das System die vorigen Regeln selbst wieder her. Ein System, das von OpenCCU kommt, übernimmt dessen
`firewall.conf` einmal in diese Liste, mit denselben Freigaben wie vorher.

| Dienst | Port | gebunden an | von außen |
| --- | --- | --- | --- |
| lighttpd | 80, 443 | LAN | Weboberfläche und API mit Anmeldung, Addon-Seiten hinter dem Login-Gate; Regel aus den local networks |
| occulited | 8183 | `127.0.0.1`, erzwungen | nur über lighttpd |
| rfd (BidCos-RF) | 32001 | `127.0.0.1` | nur über lighttpd mit klassischem RPC |
| hmipserver (HmIP-RF) | 32010 | `127.0.0.1` | nur über lighttpd mit klassischem RPC |
| hs485d (BidCos-Wired) | 32000 | `127.0.0.1` | nur über lighttpd mit klassischem RPC |
| hmipserver (VirtualDevices) | 39292 | alle Adressen | von der Firewall geschlossen; über lighttpd mit klassischem RPC |
| klassisches RPC über lighttpd | 2001, 2010, 9292, TLS 42001, 42010, 49292; 2000/42000 nur mit hs485d | LAN | standardmäßig aus; auf System → Fernzugriff, Klartext und TLS getrennt, mit oder ohne Benutzername und Passwort |
| hmipserver (Update von HmIP-Access-Points) | 9293, 9294, UDP 43438 | alle Adressen | offen, solange HmIP-RF läuft |
| Netzwerkerkennung | Multicast, SSDP 1900, eQ-3-Discovery | – | offen, als eigene Regeln bearbeitbar |
| multimacd | – | kein Socket, kein Netzwerk | – |
| sshd | 22 | LAN | nur mit eingeschaltetem SSH, nur aus lokalen Netzen |
| ReGaHSS 1999, 8181 | – | – | gibt es nicht (8183 gehört seit Aufgabe 182 occulited) |
| Addons | ihre Ports | wie das Addon bindet | jeder deklarierte Port ein eigener Schalter auf der Seite Zusatzsoftware, standardmäßig zu |

Ein Schalter pro Port heißt: Der TLS-Listener eines MQTT-Brokers kann offen sein und sein
Klartext-Port zu.

### Wer als wer läuft

- **occulited** läuft als eigener Nutzer `occulite` ohne Rechte; die HTTP-Seite, also die
  Angriffsfläche, kann nichts, was ein Nutzer ohne Rechte nicht kann. Was root braucht —
  `/etc/config` schreiben, die Skripte der Firmware, `systemctl`, Addon-Konten — geht über einen
  Unix-Socket (`root:occulite 0660`) an einen Helper mit einer geschlossenen Liste: Programme per
  Name, Schreibpfade per Präfix und typisierte Einzeloperationen, die ihre Eingaben an der Grenze
  prüfen (das Root-Passwort nur als fertiger Hash, das Zertifikat nur als Kette mit dem passenden
  Schlüssel, eine Datei für `X-Sendfile` nur als übergebener Deskriptor). Befehle sind
  Argumentlisten, nie Shell-Strings, und jede Ablehnung steht im Journal.
- **Addons** laufen standardmäßig eingesperrt als eigener Nutzer `addon-<id>`: `ProtectSystem=strict`,
  `NoNewPrivileges`, keine Capabilities, eigener Mount- und PID-Namespace mit privatem `/tmp` und
  `/var/run`, schreibbar nur die eigenen Verzeichnisse. Was ein Addon darüber hinaus braucht —
  Capabilities, Gruppen, Pfade, Datenverzeichnisse, Ports — deklariert sein Katalogeintrag, und die
  Dienste-Seite zeigt es. Ein Addon ohne Deklaration läuft ebenso eingesperrt und ist als
  *undeclared* markiert. Root ist ein bewusster, als unsicher beschrifteter Opt-out; Addons, die vor
  dem Wechsel schon installiert waren, bleiben einmalig root, bis man sie einsperrt. Die CGIs eines
  Addons laufen als dessen Nutzer, nicht als root unter lighttpd.
- **Dateibesitz:** Nach jedem Update über die Oberfläche bekommt ein eingesperrtes Addon seine
  Dateien zurück; was ein direktes `install_addon` als root hinterlässt, meldet die Statusseite mit
  *Besitz reparieren*. Datenverzeichnisse außerhalb des Addon-Baums (`/usr/local/<id>` oder
  deklarierte) übernimmt occulited mit Leitplanken: nie ein geteiltes Verzeichnis, nie das eines
  anderen Addons, nie über einen Symlink.
- **Root-Addons** verlieren `CAP_SYS_ADMIN`: `mount -o remount,rw /` schlägt fehl, die
  Systempartition bleibt schreibgeschützt. Damit Addons wie jp-hb-devices trotzdem unverändert
  laufen, ist `/firmware/rftypes` beim Boot beschreibbar (ein Overlay auf dem Userfs). Ein Addon, das
  wirklich einhängen muss, deklariert `sys_admin`, und die Dienste-Seite sagt es.
- **AppArmor:** Profile für occulited, seinen Helper, lighttpd und homematic-manager; ein Addon kann
  ein eigenes Profil mitbringen. Für fremde Software werden keine Profile generiert — ein falsches
  Profil ist schlimmer als keins.
- **Das Zertifikat des Systems** (Kette und Schlüssel) ist `root:certs 0640`. Eingesperrte Addons sind
  in der Gruppe `certs`, damit ein Broker oder Webserver TLS mit dem Zertifikat des Systems anbietet.
- **Die Funk-Daemons** haben eigene Nutzer: `rfd`, `hmipserver`, `multimacd`, `hs485d`, dazu
  `hmlangw`. udev gibt den Gerätedateien Ressourcengruppen
  (`raw-uart`, `eq3loop`, `mmd-bidcos`, `mmd-hmip`), und jede Unit darf nur ihre eigenen öffnen
  (`DevicePolicy=closed`). Keine Capabilities, `ProtectSystem=strict`; die Vorbereitung als root
  läuft vor dem Start, samt einer Reparatur der Besitzrechte bei jedem Start, denn ein
  `.sbk`-Restore ist immer root-eigen. multimacd bekommt seine Echtzeitpriorität über
  `LimitRTPRIO=99` statt `CAP_SYS_NICE`. Ein Fehler in der JVM des hmipservers erreicht so weder den
  BidCos-Schlüssel von rfd noch den UART von multimacd, und `rfd.conf` mit den
  LAN-Gateway-Schlüsseln ist `root:rfd 0640`, für Addons unlesbar. Das gilt auch in den
  LXC-Containern, und es gibt keinen Rückfall auf root. Die Firmware des Funkmoduls wird als
  multimacd-Nutzer in einer transienten Unit geflasht, die nur das Gerät des Moduls öffnen darf. Im
  Labor nicht getestet: HB-RF-USB/ETH, ein BidCos-LAN-Gateway, ein HM-CFG-USB-2, BidCos-Wired und
  der LAN-Gateway-Modus.

### Anmeldung, Sitzungen und Addon-Seiten

- **Lokale Konten** mit argon2id, Rollen `admin` und `user`, Sperre nach Fehlversuchen pro Name und
  Adresse, ein erzwungenes Passwort beim ersten Start, eine Sitzungsliste mit *überall abmelden*.
  Einen Passwort-Reset per Mail gibt es nicht; `occulited passwd <user>` auf der Konsole ist der Weg
  zurück. Ganz ohne Anmeldung läuft das System nur in einem bewusst gewählten Modus für ein
  vertrauenswürdiges Netz.
- **Das Sitzungs-Cookie** heißt über HTTPS `__Secure-occulite_session` (`Secure`, `HttpOnly`,
  `SameSite=Lax`) und über HTTP `occulite_session`, damit eine Anmeldung über das eine Schema das
  andere nicht aussperrt.
- **Das Login-Gate:** lighttpd prüft vor jeder Anfrage unter `/addons/` — statische Dateien, CGIs,
  Backends hinter einem Proxy, WebSockets —, ob eine gültige Sitzung dahintersteht; ohne Sitzung
  kommt die Anmeldung. Auf einer CCU ist ein CGI, dessen Autor die Sitzungsprüfung vergessen hat,
  offen.
- **`X-Occulite-Session`:** Das Gate reicht die geprüfte Sitzungs-ID in diesem Header an das Addon
  weiter. Einen gleichnamigen Header vom Client entfernt lighttpd auf jeder Anfrage und jedem
  Socket, in jeder Schreibweise (auch `X_Occulite_Session`); gelingt das nicht, antwortet das Gate
  mit `500`. Der Header stammt also nie vom Client, und ein Addon muss kein Cookie parsen. Wer der
  Nutzer ist und welche Rolle er hat, beantwortet `GET /api/auth/v1/state`.
- **Addons übernehmen die Sitzung des Systems**, statt eine eigene Anmeldung zu verlangen: RedMatics
  Node-RED-Editor und homematic-manager öffnen sich ohne zweiten Login.
- **Keine Sitzungs-ID in URLs:** Eingebettete Addon-Ansichten und neue Tabs tragen kein `?sid=` mehr,
  das sonst in Verlauf, Lesezeichen und `Referer` landet. Nur ein Addon, das es ausdrücklich
  deklariert, bekommt es noch; die Sitzungsprüfung klassischer Einstellungsseiten beantwortet das
  `tclrega.so`-Shim.
- **OpenID Connect** (Authentik, Keycloak, Authelia, Zitadel, Pocket ID, …): Authorization Code mit
  PKCE, eingerichtet über Discovery mit Issuer, Client-ID und Secret. Für jede Anmeldung über den
  Provider muss ein Konto gleichen Namens auf dem System existieren; abgeglichen wird nur über den
  Nutzernamen, die Rolle kommt vom Konto. Die Anmeldeseite zeigt unter dem Passwortformular
  *Anmelden mit …*; der Passwort-Login daneben ist abschaltbar, und dann führt
  `occulited auth password-login on` auf der Konsole zurück. Zwei-Faktor-Anmeldung ist Sache des
  Providers.

### API-Tokens

Programme melden sich mit `Authorization: Bearer olt_…` an. Ein Token hat 128 Bit Zufall, wird genau
einmal angezeigt, nur als SHA-256 gespeichert und einzeln widerrufen; `occulited token` legt einen
auf der Konsole an. Tokens tragen **Scopes** statt einer pauschalen Rolle: Jede Route nennt den
Scope, den sie braucht, und ein Token darf nur, was ihm gegeben wurde. Der gemeinsame Token der
Addons auf dem System liest nur. Zwei Scopes sind für eine Aufgabe gemacht:

| Scope | darf | für |
| --- | --- | --- |
| `led` | den Zustand der Status-LED lesen, eine eigene Überschreibung setzen, *Locate* — sonst nichts | Home Assistant, Node-RED |
| `backup` | Sicherungen erstellen und herunterladen, synchron oder als asynchroner Job — sonst nichts | Backup-Integrationen, Skripte auf einem NAS |

Für die Maintainer von Backup-Integrationen gibt es einen wiederverwendbaren Prompt,
`docs/INTEGRATOR-PROMPT.md`.

### Klassisches RPC (System → Fernzugriff)

Clients, die für eine CCU3 oder OpenCCU eingerichtet sind — Home Assistant, ioBroker, homematic-manager
als Desktop-App, node-red-contrib-ccu auf einem anderen Rechner, FHEM, openHAB —, arbeiten unverändert
gegen openccu-lite: auf denselben Ports, mit derselben Anmeldung und mit Rückrufen.

- **Zwei Schalter, standardmäßig aus:** Klartext (2001 BidCos-RF, 2010 HmIP-RF, 9292 VirtualDevices,
  2000 BidCos-Wired, wo hs485d läuft) und TLS (42001, 42010, 49292, 42000) mit dem Zertifikat des
  Systems. lighttpd bedient die Ports; die Schnittstellenprozesse bleiben auf dem Loopback.
- **Anmeldung:** keine, oder Benutzername und Passwort nur für klassisches RPC — nicht die Konten des
  Systems, keine API-Tokens. Basic-Auth wie auf einer CCU mit eingeschalteter Authentifizierung, von
  lighttpd geprüft. Das Passwort wird getippt (mindestens 12 Zeichen) oder erzeugt (32 Zeichen, einmal
  angezeigt) und nur als SHA-512-crypt gespeichert.
- **Firewall:** Jeder offene Port bekommt eine Regel *Classic RPC* aus den local networks, wie OpenCCU
  sie erlaubt hat; weiter oder enger stellt man sie auf der Firewall-Seite.
- **Von OpenCCU:** Waren die XMLRPC-Ports offen, ist klassisches RPC danach eingeschaltet, mit den
  bisherigen Freigaben. Hatte OpenCCU eine Anmeldung verlangt (`authEnabled`, mit den ReGa-Konten, die
  es hier nicht gibt), bleibt es aus, bis Benutzername und Passwort gesetzt sind.
- **Wie auf einer CCU:** keine Rechte pro Methode, kein Trace, keine Sperre nach Fehlversuchen. Die
  Schnittstellenprozesse rufen den Client unter der Adresse zurück, die er anmeldet; er muss vom
  System aus erreichbar sein. BIN-RPC über lighttpd geht nicht, wie bei OpenCCU.
- **Geplant: lite-rpc** — Anfragen und Ereignisse über den Web-Port mit API-Tokens, SSE/WebSocket statt
  Rückrufen, mit Rechten pro Token und einem Trace.

### Zertifikate und HTTPS

- **Drei Wege zum Zertifikat** (System → Zertifikat):
  - **selbstsigniert**, der Standard (zehn Jahre, Hostname und Adresse im SAN);
  - **ACME**, eingebaut ohne zweiten Prozess: Let's Encrypt, ZeroSSL (mit External Account Binding)
    oder eine eigene CA wie step-ca, per HTTP-01 oder DNS-01 (Cloudflare, Hetzner, netcup, DuckDNS
    oder ein eigenes Skript); *Test* läuft gegen die Staging-Umgebung, geprüft wird zweimal täglich,
    erneuert unter 30 Tagen oder der halben Laufzeit;
  - **manuell**: Zertifikat, Kette und Schlüssel als PEM oder DER hochladen, oder Schlüssel und
    Zertifikatsanforderung auf dem System erzeugen — dann verlässt der Schlüssel das System nie.

  Nach jeder Installation lädt lighttpd neu, und die Addons der Gruppe `certs` starten neu. Die
  Statusseite warnt 14 Tage vor dem Ablauf und nach einer fehlgeschlagenen Erneuerung.
- **HTTPS-Umleitung und HSTS** (System → Zertifikat): Die Umleitung von HTTP auf HTTPS ist ein
  Schalter. HSTS lässt sich nur mit einem nicht selbstsignierten Zertifikat einschalten, mit
  `max-age` 7 Tage als Standard und höchstens 730. Vorher sagt eine Rückfrage, was es kostet: Das
  Recovery-System und die Installationsphase eines System-Updates sprechen nur HTTP und sind dann
  nur noch über die IP-Adresse erreichbar, und ein Weg zurück zu OpenCCU oder ein Reset mit
  selbstsigniertem Zertifikat ist unter dem Namen bis zum Ablauf gesperrt. **Ausschalten** sendet
  deshalb `Strict-Transport-Security: max-age=0`, so lange wie das bisherige `max-age`, höchstens
  30 Tage, und die Seite nennt die Namen, die man in jedem Browser einmal öffnen sollte. Dasselbe
  geschieht vor dem Wechsel zurück auf selbstsigniert und wenn ein Weg zurück zu OpenCCU bereitgelegt
  wird.
- **Recovery per IP-Adresse:** Das Recovery-System hat kein TLS. Jeder Weg hinein — der Neustart ins
  Recovery im Power-Menü, der Hinweis bei der Installation eines Updates — verlinkt `http://<IP>/`,
  denn HSTS gilt nie für eine IP-Adresse.
- **Vom kurzen auf den vollständigen Namen:** Ein Schalter, standardmäßig aus, leitet
  `https://<host>/` mit `302` auf `https://<host>.<domain>/` um, Pfad und Query bleiben; zusammen mit
  der HTTPS-Umleitung auch `http://<host>/` in einem Schritt. Ein Browser hat so einen Namen für das
  System: ein Cookie, einen HSTS-Eintrag, ein gespeichertes Passwort. Umgeleitet werden nur `GET` und
  `HEAD`, nie `/api`, der ACME-Pfad, der Loopback, IP-Adressen oder andere Namen; `302` statt `301`,
  weil ein Browser eine `301` behält. Die Umleitung gilt nur, solange das Zertifikat den
  vollständigen Namen abdeckt, und ruht nach einer Umbenennung oder einem Domainwechsel, bis ein
  passendes Zertifikat da ist.

### Außerdem

- **Keine ReGaHSS:** kein HM-Script-Interpreter, kein Port 8181 oder 8183, nichts, das Skripte aus
  dem LAN ausführt.
- **Ein Log:** Das System und die Addons schreiben ins Journal und in keine Log-Datei; der Build
  bricht ab, wenn eine mitgelieferte Konfiguration eine `.log`-Datei nennt. Ausnahmen sind nur das
  Recovery-System und die Installationsphase eines System-Updates, die kein Journal haben; ihr Log
  wird beim nächsten Boot ins Journal übernommen. lighttpds Access-Log ist standardmäßig aus.
  **Remote-Syslog** schickt jeden Journal-Eintrag — Syslog, die Ausgaben der Units, den Kernel — als
  RFC 5424 über UDP an den eingestellten `LOGHOST`.
- **Verschlüsselte Backups:** Eine `.sbk` enthält das ganze Userfs — den BidCos-Schlüssel, das
  HmIP-Schlüsselmaterial, die Passwort-Hashes, die Tokens der DNS-Provider, den TLS-Schlüssel.
  Sobald ein Wiederherstellungscode eingerichtet ist, wird jede Sicherung auf Freigaben, auf USB und
  als Download mit age verschlüsselt (`.sbk.age` um die unveränderte `.sbk`), und zwar für zwei
  Schlüssel: den des Systems, der in keiner Sicherung liegt und ihre eigenen Sicherungen ohne Eingabe
  öffnet, und den **Wiederherstellungscode** — kurz, gruppiert, mit Prüfsumme, im Browser erzeugt und
  nie auf dem System gespeichert —, der sie auf jedem anderen System öffnet. Ein unverschlüsselter
  Download verlangt das Passwort erneut und steht im Journal. Ältere Sicherungen behalten ihren
  Schlüssel, und die Seite zeigt, welchen jede braucht. Das Recovery-System stellt nur
  unverschlüsselte `.sbk` wieder her; das Notfallkit erklärt das Entschlüsseln am PC.
- **Bluetooth** ist nur in den Raspberry-Pi-Images und standardmäßig aus (`disable-bt`, der Chip ganz
  abgeschaltet); Einschalten ändert `config.txt` und braucht einen Neustart.
- **Standard-Sicherheitsschlüssel:** Solange BidCos-RF mit dem öffentlich bekannten
  Standardschlüssel läuft, warnt die Statusseite und führt direkt zum Schlüsselfeld der
  Schnittstellen-Seite.

## Startzeit

Die systemd-Umstellung hatte OpenCCUs SysV-Reihenfolge in eine streng serielle Kette übersetzt:
Jeder Schritt wartete auf alle vorigen, auch auf fremde. multimacd wartete auf hs485d, die Erkennung
des Funkmoduls auf eine blockierende NTP-Synchronisation, occulited auf das Funkmodul, hmipserver auf
rfd und alle Addons auf hmipserver. openccu-lite startet nach einem Abhängigkeitsgraphen, in dem jede
Unit nur auf das wartet, was sie braucht; ein Test in der CI schlägt fehl, wenn ein serielles Glied
zurückkommt.

| Sekunden nach dem Neustart | x86_64-VM | Raspberry Pi 4 | Charly (Raspberry Pi 3 B, CCU3-Klasse) |
| --- | --- | --- | --- |
| Weboberfläche antwortet | 48,8 → **36,5** | 81,1 → **48,9** | 60,8 → **45,8** |
| hmipserver bereit | 67,4 → **55,8** | 108,2 → **95,1** | 111,1 → **97,3** |
| alle Addons laufen | 98,7 → **86,9** | 142,2 → **128,1** | 148,1 → **133,3** |

Gemessen mit je drei normalen Neustarts (`systemctl reboot`) pro System, Median, gezählt ab dem
Neustart-Befehl, also mit Herunterfahren und Firmware; ein Client fragte alle 0,25 s
`/api/system/v1/health` ab, die Zeiten der Units stammen von systemd.

- **chrony blockiert nicht mehr.** Bisher hielt ein `ntpdate -b` den Boot rund 10 s auf (9,8 / 10,5 /
  10,9 s), und ohne Internet beim Boot startete chronyd gar nicht. Jetzt startet chronyd sofort und
  korrigiert einen großen ersten Versatz selbst: 0,1–0,2 s. Wer eine richtige Uhr braucht, wartet auf
  ein Uhr-Gate, das durchlässt, sobald die RTC eine plausible Zeit gesetzt hat, chrony synchron ist
  oder 60 s vergangen sind (dann mit einem Hinweis auf der Statusseite). Das sind die Funk-Daemons,
  denn hmipserver, rfd und multimacd geben die Systemzeit an Geräte weiter. Auf Systemen mit RTC kostet
  das nichts; der Pi 4 ohne RTC wartete 6 s auf NTP, während die Funkmodul-Erkennung ohnehin lief.
- **Der Funkstack startet parallel.** multimacd wartet nicht mehr auf hs485d, rfd und hmipserver
  starten nebeneinander nach multimacd, und Firmware-Update und Schlüssel der LAN-Gateways kommen vor
  rfd und hs485d statt nach der Addon-Initialisierung. multimacd ist 9,5–10,8 s früher bereit.
- **lighttpd startet direkt nach dem Netzwerk**, neben occulited statt danach: aktiv 19–24 s nach dem
  Kernelstart statt 32–53 s. Solange occulited nicht antwortet — beim Boot, nach einem Neustart oder
  Absturz —, liefert lighttpd eine statische Warteseite mit Hostname und Version, hell und dunkel,
  deutsch und englisch. Sie fragt alle 2 s nach und lädt die aufgerufene Adresse neu, sobald
  occulited da ist; API-Clients bekommen `503` mit `Retry-After` und JSON.
- **Ein Countdown-Balken** erscheint, wenn man das System über die Oberfläche neu startet. Er beginnt
  voll und leert sich von links nach rechts bis zu dem Moment, in dem die Weboberfläche wieder
  antwortet. An den Punkten, die der Browser sieht — das System antwortet nicht mehr, lighttpd antwortet,
  occulited antwortet —, schätzt er neu, ohne je zurückzuspringen, und die Warteseite von lighttpd
  führt denselben Balken weiter. Die erwarteten Zeiten kommen zuerst aus den Messungen pro Produkt;
  danach nimmt jedes System den Median ihrer letzten drei Neustarts pro Phase. Ein zweiter, schmaler
  Balken zählt anschließend, bis die Funkschnittstellen bereit sind, und Status-, Schnittstellen- und
  Dienste-Seite zeigen eine startende Schnittstelle als *startet* mit der verstrichenen Zeit statt als
  ausgefallen.
- **Addons starten nach Bedarf.** Ein Addon, das mit den Schnittstellen spricht, startet erst, wenn
  hmipserver und rfd bereit sind — hmipservers Unit ist erst aktiv, wenn sein RPC antwortet —, und
  beim Boot steht kein RPC-Fehler in den Addon-Logs. Ein Addon, das im Katalog `runtime.needs: []`
  deklariert, etwa Mosquitto, startet direkt nach dem Netzwerk: Auf dem Pi 4 lief der Broker 25 s vor
  hmipserver und rund 40 s früher als vorher. Ein Addon ohne Deklaration behält die sichere
  Reihenfolge. Ein Addon, das im Katalog `runtime.start: "early"` deklariert, kommt mit noch nicht bereiten
  Schnittstellen zurecht und startet vor ihnen; die Addons-Seite schaltet das ab, für alle Addons oder einzeln, ab dem
  nächsten Neustart. Feste Wartezeiten gibt es in keiner Unit.
- **Das Herunterfahren endet absichtlich später.** lighttpd stoppt jetzt nach dem Funkstack, das System
  antwortet also 2,6–3,0 s länger; dafür erscheint der Hinweis, dass das System vom Strom getrennt
  werden kann, erst, wenn hmipserver wirklich gestoppt ist.
- **Was noch dominiert:** auf dem Pi 4 die Erkennung des Funkmoduls (rund 21 s), und seine Firmware
  braucht vor dem Kernel am längsten; auf der Pi-3-Klasse der Java-Start des hmipservers (42 s,
  gegenüber 24 s auf dem Pi 4 und 14 s auf der VM). Die Boot-Zeitleiste auf der Dienste-Seite zeigt
  das für jedes System selbst.

## Was wo liegt

openccu-lite besteht aus drei Repositories:

| | |
| --- | --- |
| **dieses Repository** | Der Buildroot-Baum (Fork von OpenCCU): die Produkte `x86_64-ova`, `aarch64-rpi3`, `aarch64-rpi4`, `aarch64-rpi5`, `lxc-lite_amd64`, `lxc-lite_arm64`, das lite-Overlay mit den systemd-Units, das Paket, das occulited einbaut, der Release-Workflow, `BUILD.md`. |
| [occulited](https://git.lan.raff.rocks/hobbyquaker/occulited) | Der Systemdienst mit eingebetteter Weboberfläche: `cmd/occulited`, `internal/`, `ui/`, `deploy/` (lighttpd-Verdrahtung, Login-Gate, das `tclrega.so`-Shim), `fixtures/` (der Konformitätskorpus der Metadaten-API). |
| [openccu-lite-addons](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-addons) | Der Addon-Katalog (`index.json`), aus dem das System installiert. |

Die Dokumentation liegt bis auf weiteres im Arbeitsrepository des Maintainers:
[docs/meta-format.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/meta-format.md) und [docs/meta-api.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/meta-api.md) (der Metadatenspeicher, normativ),
[docs/system-api.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/system-api.md) und [docs/config.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/config.md) (System- und Auth-API, `occulited.json`),
[docs/porting-from-rega.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/porting-from-rega.md) und [docs/PORTING-PROMPT.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/PORTING-PROMPT.md) (das Portierungs-Kit für Addon-Maintainer),
[docs/catalog-format.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/catalog-format.md) (das Katalogformat),
[docs/addons.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/addons.md), [docs/security.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/security.md), [docs/switching.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/switching.md) (der Wechsel von und zu OpenCCU),
[docs/hardware-checklist.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/hardware-checklist.md) (die Release-Hürde, D-26), [docs/study-without-rega.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/study-without-rega.md) (der Laborbefund).
Roadmap, Entscheidungen, offene Fehler und der Arbeitsstand liegen dort unter `openccu-lite/`.

## occulited in einem Absatz

Ein HTTP-Dienst nur auf Loopback, hinter lighttpd. `/api/meta/v1`: Objekte mit Schlüssel
`<Schnittstelle>.<Adresse>`, Enum-Bäume (Räume, Gewerke, Etagen), Bulk und Import/Export, ein
SSE-Änderungsstrom, eine JSON-Datei auf der Platte. `/api/system/v1`: Status, Schnittstellen und
ihre Abonnenten, Dienste und ihre Units, Addons (Installation, Deinstallation, Update-Prüfung,
der Katalog mit Fortschrittsbalken), Geräte-Firmware automatisch für die angelernten Typen,
Netzwerk mit Bestätigen-oder-Zurückrollen, Firewall in den Worten von iptables, Zeit, Log-Level
und Journal, Protokoll. `/api/auth/v1`: lokale Benutzer mit argon2id, Sitzungen, die lighttpds
Gate für die Addon-Seiten mitbenutzt, API-Tokens für Programme, OpenID Connect — oder gar keine
Anmeldung für ein System allein in einem vertrauenswürdigen Netz. Die Weboberfläche ist eingebettet;
sie ist die Shell des Systems und zeigt die eigene Oberfläche jedes Addons in ihrem Menü.

## occulited bauen

Im [occulited](https://git.lan.raff.rocks/hobbyquaker/occulited)-Repository:

```sh
cd ui && npm ci && npm run build && cd ..   # bettet die Oberfläche ein
go build ./cmd/occulited                     # oder scripts/build.sh für alle drei Ziele
go test ./...
```

Go 1.26 oder neuer, Node 24. `occulited --root <Verzeichnis>` läuft für die Entwicklung gegen ein
nachgebildetes Dateisystem; Systemkommandos werden in diesem Modus nur protokolliert.

## Lizenz

Apache-2.0 für alles hier Geschriebene; die `occu`-Bestandteile behalten die Bedingungen von eQ-3.
