# Bekannte Probleme

*Deutsch — die englische Fassung ist [known-issues.md](known-issues.md).*

Bekannte Probleme der Homematic-Software, die openccu-lite betreibt, und was openccu-lite dagegen tut.

## HmIP-Geräte nach einem Neustart unerreichbar: der Sicherheitszähler

**Das Symptom:** nach einem Neustart oder einem Update antwortet kein HmIP-Gerät mehr - auch die
Bedienung vor Ort nicht -, während BidCos-RF-Geräte am selben Modul weiterlaufen, und ein weiterer
Neustart des Systems hilft nicht. **Die Ursache** (eq-3/occu#134, OpenCCU/OpenCCU#4274; Berichte im
Forum seit 2025-11): jeder HmIP-Rahmen trägt einen Sicherheitszähler, den die Geräte nur aufwärts
akzeptieren. Bei jedem Start liest hmipserver den Zähler des Funkmoduls (*"Current Security
Counter: N"* in seinem Journal), berechnet aus der Uhrzeit und zwei Zahlen aus der Datei des Access
Points (`crRFD/data/<SGTIN>.ap`: der Zeitpunkt der ersten Verbindung und ein Offset) einen Wert und
schreibt ihn ins Modul, wenn er höher ist (*"Update security counter to calculation: M"*). Das Modul
übernimmt die unteren 32 Bit dieses Werts, verglichen wird aber der ganze: hat der berechnete Wert
einmal 2³² überschritten, schützt die Prüfung nichts mehr, und ein Start mit einer zurückliegenden
Uhr - eine CCU ohne Echtzeituhr nach einem Stromausfall, NTP nicht erreichbar - gefolgt von einem
Start mit richtiger Uhr setzt den Zähler des Moduls unter das, was die Geräte schon gesehen haben.
Von da an verwerfen sie jeden Rahmen des Systems als Wiederholung.

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
  Uhr nicht vertrauenswürdig ist** (das Tor lief in den Timeout oder hat Echtzeituhr oder Zeitserver
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
Batterie raus und rein, bei Netzgeräten die Sicherung aus und ein - oder sie neu anlernen. Den Offset
in der Access-Point-Datei von Hand zu ändern (der Behelf aus dem Ticket) verschiebt nur den nächsten
Umlauf. Die Korrektur gehört in eQ-3s HmIP-Server; openccu-lite liefert dieses Binary unverändert aus
und verfolgt die Tickets.
