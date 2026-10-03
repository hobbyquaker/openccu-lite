# Empfehlungen

Was sich im Betrieb von openccu-lite bewährt hat: die Hardware, die Virtualisierung, der Schlüssel des HmIP-Netzes und
die Sicherungen.

## Hardware

Am zuverlässigsten läuft openccu-lite auf einer **originalen CCU3** oder einem **ELV „Charly“** – also einem
**Raspberry Pi 3 B (nicht 3 B+) mit [RPI-RF-MOD](https://de.elv.com/search?q=rpi-rf-mod&ms=true)** auf der GPIO-Leiste.
Das Funkmodul hängt dort ohne USB- oder Netzwerkschicht direkt am System, und der Pi 3 B stört den 868-MHz-Funk am
wenigsten.

**Empfehlung: HmIP und BidCos trennen.** Das RPI-RF-MOD bedient nur HmIP (direkt, ohne multimacd), BidCos läuft über ein
zweites Funkmodul, via USB oder Netzwerk. So hat jeder Funkstandard sein eigenes Modul und seinen eigenen Duty Cycle. Wer kein
BidCos-Gerät hat, schaltet BidCos-RF ab: Schnittstellen → BidCos-RF → „Aus (nur HmIP)“ – das RPI-RF-MOD bedient dann
nur HmIP.

**Aus dem eigenen Betrieb** – keine getestete oder gesponserte Liste, nur was beim Entwickler von openccu-lite seit
Langem läuft: seit sechs Jahren gute Erfahrungen mit einem ähnlichen PoE-Splitter (z. B.
[dieser](https://de.aliexpress.com/item/1005008712707676.html)) – ein Kabel für Netzwerk und Strom. Als Gehäuse für Pi
und RPI-RF-MOD dient das gut durchdachte, druckbare
[„Raspberrymatic CCU3 Case Upgrade RPI-RF-MOD“](https://www.thingiverse.com/thing:4146052) von raabi91.

## Virtualisierung

openccu-lite ist ein auf buildroot basierendes System für Embedded-Hardware. Das VM-Image (`.ova`) ist zum Testen und für Laborsysteme gedacht und **für den Produktivbetrieb nicht empfohlen**. Für einen virtualisierten Betrieb wird
empfohlen auf piVCCU, Debmatic oder OpenCCU zu setzen.

## Lokaler Schlüsselmodus

**Empfehlung: auf einer Neuinstallation den lokalen Schlüsselmodus für HmIP einschalten** – im Willkommensassistenten
oder später auf der Seite Schlüssel. Der Netzwerkschlüssel des HmIP-Netzes gehört dann dem System statt dem Funkmodul:
HmIP funktioniert ohne Internet, und ein Tausch des Funkmoduls braucht den Schlüsselserver von eQ-3 nicht, der einen
solchen Tausch auch ablehnen kann.

Am besten gleich zu Beginn, solange noch kein HmIP-Gerät angelernt ist: dann kostet der Modus nichts. Eine bestehende
Installation muss beim Umstieg jedes HmIP-Gerät einmal neu anlernen. Die Geräteschlüssel (QR-Code bzw. KEY vom
Aufkleber) am besten gleich beim Anlernen auf der Seite Schlüssel erfassen; ohne Schlüsselserver nimmt das System ein
Gerät nur mit seinem Schlüssel an.

Das Risiko: der Schlüssel steht im Klartext in jeder Sicherung – Sicherungen deshalb verschlüsselt anlegen und sicher
aufbewahren. Außerdem ist der lokale Schlüsselmodus kein von eQ-3 offiziell unterstützter Betriebsmodus. Alles Weitere
in [lokaler-schluesselmodus.md](lokaler-schluesselmodus.md).

## Sicherungen

**Empfehlung: nächtlich, verschlüsselt und außerhalb des Systems sichern.** Die Seite Sicherung legt die nächtliche
Sicherung auf einem Sicherungsziel ab – einem USB-Stick oder einer Freigabe im Netz, nicht auf dem System selbst, mit dem
sie sonst zusammen verloren geht. Die *Verschlüsselung* auf derselben Seite schützt, was in einer Sicherung steht: die
Funkschlüssel, die Zugangsdaten und die Zertifikate. Den Wiederherstellungsschlüssel (Notfallkit) getrennt vom System
aufbewahren, etwa in einem Passwort-Manager: ohne ihn lässt sich eine verschlüsselte Sicherung auf keinem anderen
System einspielen, und auf diesem nicht mehr, sobald sein Speicher verloren ist.
