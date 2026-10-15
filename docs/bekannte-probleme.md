# Bekannte Probleme

*Deutsch — die englische Fassung ist [known-issues.md](known-issues.md).*

Bekannte Probleme der Homematic-Software, die openccu-lite betreibt, und was openccu-lite dagegen tut.

## HmIP-Geräte nach einem Neustart unerreichbar: der Sicherheitszähler

**Das Symptom:** nach einem Neustart oder einem Update antwortet kein HmIP-Gerät mehr - auch die
Bedienung vor Ort nicht -, während BidCos-RF-Geräte am selben Modul weiterlaufen, und ein weiterer
Neustart des Systems hilft nicht. **Die Ursache** (eq-3/occu#134, OpenCCU/OpenCCU#4274; Berichte im
Forum seit 2025-11): jeder HmIP-Frame trägt einen Sicherheitszähler, den die Geräte nur aufwärts
akzeptieren. Bei jedem Start liest hmipserver den Zähler des Funkmoduls (*"Current Security
Counter: N"* in seinem Journal), berechnet aus der Uhrzeit und zwei Zahlen aus der Datei des Access
Points (`crRFD/data/<SGTIN>.ap`: der Zeitpunkt der ersten Verbindung und ein Offset) einen Wert und
schreibt ihn ins Modul, wenn er höher ist (*"Update security counter to calculation: M"*). Das Modul
übernimmt die unteren 32 Bit dieses Werts, verglichen wird aber der ganze: hat der berechnete Wert
einmal 2³² überschritten, schützt die Prüfung nichts mehr, und ein Start mit einer zurückliegenden
Uhr - eine CCU ohne Echtzeituhr nach einem Stromausfall, NTP nicht erreichbar - gefolgt von einem
Start mit richtiger Uhr setzt den Zähler des Moduls unter das, was die Geräte schon gesehen haben.
Von da an verwerfen sie jeden Frame des Systems als Wiederholung.

**Was openccu-lite dagegen tut:**

- **Die Uhr startet nie im Jahr 1970.** Der Start stellt die Uhr mindestens auf den Bau des Images,
  dann auf die beim letzten Herunterfahren (stündlich) gesicherte Zeit, und der Funkstack wartet auf
  eine Echtzeituhr oder einen Zeitserver (`occu-clock-valid`, höchstens etwa 150 s). `chronyd` läuft
  immer.
- **Eine Uhr gilt nur zwischen dem Bau des Images und 15 Jahren danach als vertrauenswürdig** - aus
  einer Echtzeituhr, von einem Zeitserver und von Hand auf der Netzwerk-Seite gestellt gleichermaßen.
  Eine Echtzeituhr mit leerer Batterie oder einer unsinnigen Zeit, ein Zeitserver mit falschem Jahr
  wird nicht übernommen; die Status-Seite sagt es. Eine weit vorauslaufende Uhr würde den Zähler
  endgültig über 2³² schieben.
- **Der Zähler wird beobachtet.** `occulited radio ready hmipserver` liest die beiden Zeilen jedes
  Starts (der Logger, der sie schreibt, bleibt auf *info*, egal welcher HmIP-Loglevel gesetzt ist),
  und `occulited radio prep hmipserver` berechnet aus der Access-Point-Datei und der laufenden Uhr,
  was der nächste Start schreiben würde. Die Status-Seite warnt, wenn der Zähler 2³¹ überschritten hat
  (*near*: die Uhr synchron halten), 2³² (*wrapped*: der Schutz ist weg) oder unter das gesetzt wurde,
  was die Geräte gesehen haben (*backwards*: die Abhilfe unten).
- **Auf einem umgelaufenen oder gefährdeten Access Point wird hmipserver zurückgehalten, solange die
  Uhr nicht vertrauenswürdig ist** (das Gate lief in den Timeout oder hat Echtzeituhr oder Zeitserver
  abgelehnt). Die Status-Seite sagt es; eine von Hand auf der Netzwerk-Seite gestellte Zeit oder ein
  antwortender Zeitserver gibt ihn frei. Der Preis: ein solches System ohne Zeitserver startet
  HmIP-RF erst, wenn die Zeit gestellt ist. Ein System, dessen Access Point auf openccu-lite
  entstanden ist, ist nicht betroffen: sein Offset liegt bei ein paar Tausend, der Zähler erreicht
  2³² etwa 40 Jahre nach der ersten Verbindung.
- **Der Access Point einer Sicherung wird vor einem Import oder Restore beurteilt**: die Seite
  Sicherung zeigt den berechneten Wert und das Urteil, damit klar ist, in welchem Zustand das
  mitgebrachte System ist.

**Wenn es doch passiert ist** (die Status-Seite sagt *backwards*, oder jedes HmIP-Gerät schweigt,
während BidCos läuft): ein Neustart des Systems hilft nicht. **Die Geräte stromlos machen** -
Batterie raus und rein, bei Netzgeräten die Sicherung aus und ein - oder sie neu anlernen. **Oder das
System den Zähler anheben lassen:** `occulited radio repair-counter`, als root auf der Konsole des
Systems (SSH), zeigt die Zahlen jedes Access Points und beantragt nach einer Bestätigung, dass der
nächste Start von hmipserver den Zähler um einen Abstand (10 Millionen) über den höchsten Wert setzt,
den die Geräte bekanntermaßen gesehen haben - aus den Zählerständen früherer Starts, oder aus dem
Offset des Access Points, wenn keine aufgezeichnet sind. `systemctl restart hmipserver` (oder ein
Neustart) wendet das an, nur mit einer vertrauenswürdigen Uhr; die Geräte nehmen das System danach
wieder an, ohne angefasst zu werden. `--dry-run` zeigt nur die Zahlen, `--cancel` zieht einen Antrag
zurück, und die ursprüngliche Access-Point-Datei bleibt als `<SGTIN>.ap.bak` erhalten. Nicht helfen
kann es, wenn die Geräte einen Wert zu nahe an 2³² gesehen haben: dann die Geräte stromlos machen. Den
Offset in der Access-Point-Datei von Hand zu ändern (der Behelf aus dem Ticket) verschiebt nur den
nächsten Umlauf. Die Korrektur gehört in eQ-3s HmIP-Server; openccu-lite liefert dieses Binary unverändert aus
und verfolgt die Tickets.

## VirtualDevices / Heizungsgruppen bleiben nach einem ausgelasteten Start aus

**Das Symptom:** nach einem Start sind die Heizungsgruppen (die Schnittstelle VirtualDevices) nicht
verfügbar und bleiben es, während HmIP-RF, BidCos-RF und BidCos-Wired laufen. rfd und hs485d
protokollieren den ganzen Lauf über bei jedem Ereignis Transportfehler zum Port 39292:

```
rfd: XmlRpc transport error calling system.listMethods({"BidCos-RF_java"}) on http://127.0.0.1:39292/bidcos
rfd: Error in XmlRpcClient::writeRequest: write error (error 111).
```

und das Journal von hmipserver enthält für diesen Start `Could not add interface: HmIP-RF_java`.

**Die Ursache:** ein Wettlauf beim Start in eQ-3s hmipserver. Sein Teil, der VirtualDevices und die
BidCos-Seite bedient (Port 39292), verbindet sich beim Start mit hmipservers eigenem HmIP-RF-Port;
ist das System beim Booten ausgelastet (ein Raspberry Pi 3 mit vielen Geräten und startenden
Addons), lauscht dieser Port noch nicht. Die Verbindung scheitert, hmipserver versucht es nicht
erneut, und Port 39292 lauscht nie. hmipserver selbst läuft weiter, systemd sieht also nichts, was
neu zu starten wäre. Es ist selten: die meisten Starts, und jeder Start auf einem weniger
ausgelasteten System, gewinnen den Wettlauf.

**Der Behelf:** hmipserver neu starten - auf der Seite **Dienste** oder mit
`systemctl restart hmipserver`. Die Heizungsgruppen sind nach etwa zwei Minuten wieder da, und die
Transportfehler hören auf. Die Korrektur gehört in eQ-3s hmipserver; openccu-lite liefert dieses
Binary unverändert aus.

## Nicht ausgelieferte Gerätefirmware erscheint in anderen Apps als aktuell

**Was Sie sehen:** die Seite Updates führt eine Gerätefirmware als *Heruntergeladen, nicht
ausgeliefert*, während die WebUI, homematic-manager, Home Assistant und andere Apps dieselben Geräte
als aktuell anzeigen.

**Warum:** openccu-lite lädt Gerätefirmware herunter, gibt sie aber erst an die Geräte weiter, wenn
Sie es wollen: ist *Automatisch bereitstellen* aus - die Voreinstellung seit 1.0.0-beta.5, auch auf
Systemen, die von einer früheren Version aktualisiert wurden -, wartet ein Download auf dem System,
bis Sie für seinen Typ *An die Geräte ausliefern* drücken. hmipserver und rfd melden eine verfügbare
Firmware nur für ausgelieferte Firmware, also sieht jede App, die sie fragt, keine. Firmware, die
vor dem Update ausgeliefert war, bleibt ausgeliefert.

**Was zu tun ist:** nichts, wenn Sie selbst entscheiden wollen, wann eine Firmware Ihre Geräte
erreicht. Liefern Sie sie auf der Seite Updates aus, wenn Sie sie wollen; HmIP-Geräte erhalten sie
dann im Hintergrund (das kann Stunden dauern und nutzt die Funkzeit des Funkmoduls), BidCos-Geräte,
wenn Sie das Update im Frontend starten. Die Installation ist immer Ihr Schritt im Frontend.
Schalten Sie *Automatisch bereitstellen* ein, um jeden Download wie bisher sofort auszuliefern.
