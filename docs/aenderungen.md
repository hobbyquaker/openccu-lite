# Änderungen gegenüber OpenCCU

Was openccu-lite gegenüber OpenCCU ändert, entfernt oder hinzufügt.

## Entfernt

- ReGaHSS, die CCU-WebUI, WebUI-Programme, Systemvariablen und HM-Script
- Die ReGa-Ports 1999, 8181 und 8183
- Node.js, monit, Avahi, logrotate, msmtp, Net-SNMP, NUT, OpenVPN, WireGuard-Tools, Tailscale, ser2net, socat, xinetd, nmap, tcpdump, strace, CloudMatic, mediola NEO Server
- ntpdate; chrony stellt die Uhr allein
- eq3configd, ssdpd und hss_led
- Bluetooth-Stack auf dem Raspberry Pi; Wi-Fi- und Bluetooth-Stack im VM-Image
- smartd (smartctl bleibt auf dem Raspberry Pi)
- USV-, Lüfter- und Display-Daemons der Pi-Boards
- Die Skripte, die ReGa brauchen (`updateDCVars.tcl`, `checkHmIPconsistency.tcl`, `checkHmIPdevices.sh`, `checkPortForwarding.sh`)
- `checkAddonUpdates.sh`, `checkFirmwareUpdate.sh`, `checkInternet`
- libfirewall und `setfirewall.tcl`
- Home-Assistant-WebUI-Proxy
- Das OCI-/Docker-Produkt
- Nach dem Wechsel von einer CCU: ReGa-Datenbank, `measurement`, `userprofiles` und NEO Server auf der Userfs, einmalig, nachdem die Namen übernommen sind

## Weboberfläche und Systemdienst

- Neue Weboberfläche (Svelte), ausgeliefert vom Systemdienst occulited, einer statischen Go-Binärdatei
- Deutsch und Englisch, helles und dunkles Design
- Seiten: Status, Bedienung, Zusatzsoftware und das System-Menü mit Schnittstellen, LAN-Geräte, Schlüssel, Netzwerk, Firewall, Fernzugriff, Vertrauensspeicher, Zertifikat, Benutzer, Dienste, Protokoll, Speicher, Sicherung, Updates, Statusleuchte
- Bedienung: Favoriten, Räume und Gewerke als Baum, Kanäle als Kacheln
- Der Menüpunkt Bedienung lässt sich ausblenden
- Namen, Räume und Gewerke in einem eigenen Metadatenspeicher mit REST-API und Änderungsstrom; Räume und Gewerke verschachtelbar
- Namen, Räume und Gewerke werden beim ersten Start aus der ReGa-Datenbank übernommen
- Keine eigene Geräteverwaltung: Anlernen, Parameter und Direktverknüpfungen über den Homematic Manager oder OpenCCU-Loom aus dem Katalog
- Status: Warnungen mit Link zur Lösung, Servicemeldungen, Duty Cycle und Carrier Sense mit Verlauf, Zustand der Speichermedien
- Statusleuchte des RPI-RF-MOD zeigt den Systemzustand, mit Nachtmodus und „Finden“
- Statusleuchte dimmbar, Farben frei wählbar, sanfte Übergänge; auf dem Raspberry Pi gelb ab dem Einschalten
- Statusleuchte zeigt auf Wunsch die Auslastung des Funks (Duty Cycle, Carrier Sense)
- Lizenzseite mit allen Bestandteilen und SBOM zum Herunterladen
- Neustart, Herunterfahren und Start ins Recovery-System aus der Oberfläche
- Beim ersten Start eine Begrüßung mit Übernahme aus einer Sicherung und der Wahl des Nur-HmIP-Betriebs

## Start und Dienste (systemd)

- systemd statt BusyBox-init auf allen Produkten
- Jeder Dienst eine eigene Unit; ausgefallene Dienste werden mit Backoff neu gestartet
- Startreihenfolge als Abhängigkeitsgraph statt fester Nummern
- Init-Skripte unter `/etc/init.d` nur noch als Kompatibilitätsschicht
- Hardware-Watchdog über systemd
- Dienste, Timer und Startablauf auf der Seite Dienste einsehbar und steuerbar
- Addon-Daemons werden überwacht wie die Systemdienste
- Ein Dienst, der immer wieder abstürzt, erscheint als Warnung auf der Statusseite

## Funk und Schnittstellen

- rfd, hs485d, multimacd und hmipserver unverändert von OpenCCU
- Funkmodulerkennung, Konfiguration, Coprozessor- und LAN-Gateway-Firmware sowie USB-Hotplug in occulited
- Die Schnittstellendienste laufen unter eigenen Benutzern und in einer Sandbox
- rfd, hs485d und hmipserver lauschen nur auf dem Loopback
- Funk-Firmware: mitgelieferte und hochgeladene Versionen flashen, Upgrade und Downgrade
- HmIP: lokaler Schlüsselmodus, Geräteschlüssel per QR-Code, Schlüsselblatt zum Drucken
- Warnung, wenn ein HmIP-Gerät wegen eines falschen lokalen Schlüssels nicht angelernt wird
- Nur-HmIP-Betrieb ohne BidCos-Geräte: rfd aus, hmipserver direkt am Funkmodul ohne multimacd (außer beim HM-MOD-RPI-PCB)
- Die Identitätsdateien des HmIP-Access-Points ändern sich nur nach einer Warnung und Bestätigung; die automatische Wahl verschiebt HmIP-RF nie auf ein anderes Funkmodul
- Wechsel des HmIP-Funkmoduls: vorher ein Schnappschuss, ein Weg zurück zum vorherigen Modul, eine Diagnose, wenn der Schlüsseltausch abgelehnt wird
- Schutz vor dem zurückgesetzten HmIP-Sicherheitszähler: der Uhr wird nur zwischen dem Bau des Images und 15 Jahren danach vertraut, gefährdete Access Points werden erkannt, hmipserver wartet auf eine verlässliche Uhr; Details in [bekannte-probleme.md](bekannte-probleme.md)
- Warnung, wenn der Funk ausgelastet ist (Carrier Sense über 10 %, Duty Cycle über 50 %)
- Hinweis auf eine neuere Coprozessor-Firmware und auf Funkmodule, die die Dienste nicht nutzen können
- HmIP-Heizungsgruppen über die API von occulited
- Gerätebeschreibungen von Addons (`/firmware/rftypes`) in einer beschreibbaren Schicht, auf den Image-Stand zurücksetzbar
- Angemeldete RPC-Clients einsehbar und abmeldbar
- Eigene Protokollstufe für multimacd

## Fernzugriff

- Klassisches RPC (2001, 2010, 9292, 2000 und die TLS-Ports) standardmäßig aus; einschaltbar, optional mit Benutzername und Passwort
- lite-rpc: XML-RPC und JSON-RPC mit API-Tokens, Ereignisse über SSE oder WebSocket
- API-Tokens mit Scopes, Ablaufdatum und erlaubten Adressen
- RPC-Trace ins Protokoll
- SSH: ein-/ausschaltbar, Root-Schlüssel und -Passwort über die Oberfläche
- Netzwerksuche der eQ-3-Tools (UDP 43439) und SSDP beantwortet occulited; die Netzwerkkonfiguration über den Netfinder ist nicht mehr möglich
- API-Beschreibungen (OpenAPI, AsyncAPI) liefert das System selbst aus

## Netzwerk und Firewall

- Firewall als eine Liste von iptables-Regeln mit Policy `DROP`, jede Regel editierbar
- Regeln für Webserver, SSH, klassisches RPC, Access Points und Addon-Ports werden mit der Funktion angelegt und entfernt
- Firewall-Änderungen werden nach 60 s zurückgenommen, wenn sie nicht bestätigt werden
- Firewall wird beim Start vor dem Netzwerk geladen
- Bestehende OpenCCU-Firewall-Einstellungen werden einmalig übernommen
- Anzeige aller offenen Ports mit Prozess und zugehöriger Regel
- IPv6: aus, SLAAC, DHCPv6 oder statisch
- WLAN auf dem Raspberry Pi über die Oberfläche oder eine Datei auf der Boot-Partition
- LAN-Geräte: BidCoS-Gateways, HB-RF-ETH, HmIP-Access-Points und Gerätesuche auf einer Seite
- DHCP mit der Herstellerkennung `openccu-lite` statt `eQ3-CCU3`
- Hostname ändern ohne Neustart
- Eine Neuinstallation heißt `openccu-lite-` und die letzten vier Stellen der MAC-Adresse (z. B. `openccu-lite-3f2a`) statt `openccu`; ein umgestiegenes System behält seinen Namen
- Raspberry Pi 3/CCU3: der USB-Netzwerkchip wird zurückgesetzt, wenn er nach einem Warmstart oder im Recovery-System fehlt

## Sicherheit

- Anmeldung für jede Seite, auch für die Seiten der Addons
- Benutzerkonten mit Stufen (lesen, bedienen, konfigurieren, verwalten); Passwörter mit argon2id
- Sperre nach fehlgeschlagenen Anmeldungen
- Anmeldung über OpenID Connect möglich
- Sicherheitsschlüssel und Passkeys (WebAuthn); Sitzungsdauer einstellbar
- Zertifikat-Pinning für OpenID Connect und ACME, zusätzlich zur CA-Prüfung oder an ihrer Stelle
- Sitzungen überstehen einen Neustart; Sitzungs-IDs werden nur als Hash gespeichert
- occulited läuft als eigener Benutzer auf `127.0.0.1`; Root-Aktionen nur über einen Helper mit fester Freigabeliste
- Nur lighttpd lauscht im LAN
- Zertifikat selbstsigniert, per ACME (Let's Encrypt, ZeroSSL, eigene CA; HTTP-01 oder DNS-01) oder manuell
- HSTS und Umleitung vom kurzen auf den vollständigen Hostnamen, einschaltbar
- Vertrauensspeicher für eigene Zertifizierungsstellen
- Content-Security-Policy für die Oberfläche; das Sitzungs-Cookie der API erreicht die Seiten der Addons nicht
- Weltbeschreibbare Dateien unter `addons/mh` von der CCU werden beim ersten Start gehärtet
- systemd mit seccomp; Programme mit PIE, Stack-Protector, FORTIFY und RELRO, beim Build geprüft

## Zusatzsoftware

- Unveränderte CCU-Addons werden weiter unterstützt; Installation über `install_addon`
- Addon-Katalog mit Installation per Klick
- Katalog und Seite Zusatzsoftware zeigen, ob ein Addon eingesperrt läuft, früh startet oder ungetestet ist
- Addons laufen standardmäßig eingesperrt unter eigenem Benutzer; Root nur auf ausdrücklichen Wunsch
- Bereits installierte Addons behalten beim Update Root
- Auch Root-Addons können die Systempartition nicht mehr beschreibbar einhängen; was sie ablegen, landet in beschreibbaren Verzeichnissen
- Addons, die ReGa brauchen, und Addons mit Binärdateien für eine andere Architektur werden beim Wechsel deaktiviert und angezeigt
- Addons beschreiben sich über ein Manifest (`openccu-lite.json`)
- Addons können laut Manifest vor den Funkdiensten starten
- Icons und Logos aus dem Manifest, im hellen und dunklen Design
- Addon-Ports werden einzeln per Schalter in der Firewall geöffnet
- Addons erhalten auf Wunsch einen eigenen API-Token mit begrenzten Scopes
- Addons mit eigener Oberfläche öffnen innerhalb der Weboberfläche und lassen sich anheften
- Die Seiten eines Addons sind auch mit einem API-Token erreichbar (für Apps und Skripte)
- `tclrega.so` ist ein Shim, der nur die Sitzungsprüfung beantwortet
- Nach einer Wiederherstellung zeigt die Seite Zusatzsoftware, welche Addons neu installiert werden müssen

## Datenschutz

- Keine Telemetrie, kein Herstellerkonto, kein eigener Cloud-Dienst
- Ein neues System verbindet sich von sich aus nicht mit dem Internet; tägliche Prüfungen (GitHub, eQ-3) sind aus und werden beim ersten Start abgefragt
- Keine Internet-Prüfung beim Netzwerkstart
- Gerätefirmware-Abfrage bei eQ-3 ohne Seriennummern
- Alle ausgehenden Verbindungen sind in [privacy.md](privacy.md) aufgeführt

## Protokoll und Speicher

- journald als einziges Protokoll; keine Logdateien daneben
- Journal standardmäßig im RAM (VM und Container: persistent), wahlweise persistent oder als Kopie auf einem USB-Stick
- Weiterleitung an einen entfernten Syslog-Server bleibt möglich
- hmipserver und lighttpd schreiben ins Journal
- Protokoll mit Filtern, Live-Ansicht und Download; Protokollstufen der Funkdienste einstellbar
- Das ganze Protokoll seit dem Start, beim Scrollen nachgeladen
- USB-Sticks formatieren und sicher entfernen; SMB- und NFS-Freigaben einhängen
- Die Datenbank von occulited wahlweise auf einem USB-Stick

## Sicherung und Updates

- Sicherungen optional verschlüsselt (age) mit Wiederherstellungsschlüssel
- Nächtliche Sicherung auf USB, Netzwerkfreigabe oder SFTP-Server
- Übernahme nur der angelernten Geräte mit Schlüsseln und Namen aus einer CCU- oder OpenCCU-Sicherung
- Die Übernahme geht auch auf ein anderes Funkmodul, mit geführtem Schlüsseltausch
- Ein eigener BidCos-Sicherheitsschlüssel der Sicherung wird zur Prüfung abgefragt, nie als Sperre
- Wechsel von OpenCCU oder CCU3 per Software-Update; Anlernungen, Schlüssel und Addons bleiben
- Systemupdate-Prüfung gegen die openccu-lite-Releases, Update-Paket hochladen
- Gerätefirmware von eQ-3 prüfen und herunterladen, eigene Firmware hochladen
- Installationsprotokoll des Recovery-Systems landet im Journal
- Recovery-System: eine abgebrochene Vergrößerung der Userfs wird fortgesetzt; nach einem fehlgeschlagenen Update startet das System normal

## Build und Releases

- Produkte: x86_64-VM (OVA), Raspberry Pi 3/CCU3, Raspberry Pi 4, Raspberry Pi 5, Proxmox-LXC-Container (amd64, arm64)
- Keine 32-Bit-ARM-Produkte
- Update-Pakete bleiben mit OpenCCU austauschbar
- Update-Pakete zeigen vor der EULA von OpenCCU einen eigenen Vorspann: wo es Unterstützung gibt, keine Spenden
- SBOM (CycloneDX 1.6) mit allen Bestandteilen und Lizenzen
- Die Workflows, Home-Assistant-Add-ons und Helm-Charts von OpenCCU sind aus dem Repository entfernt
