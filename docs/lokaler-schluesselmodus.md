# Der lokale Schlüsselmodus für HmIP

*Nur auf Deutsch. In der Weboberfläche heißt er „Lokaler Schlüssel“ und steht auf der Seite
**Schlüssel** (Systemmenü → Schlüssel, Abschnitt *Lokaler Schlüssel*).*

Diese Seite erklärt, was der lokale Schlüsselmodus ist, was er bringt, was er kostet – vor allem
beim Umstieg einer bestehenden Installation – und wie man ihn in openccu-lite ein- und wieder
ausschaltet.

## Kurz

- **Was:** Der Netzwerkschlüssel des HmIP-Netzes liegt auf dem System selbst, statt dass er im
  Funkmodul verschlossen ist und nur über den Schlüsselserver von eQ-3 auf ein anderes Modul
  kommt.
- **Gewinn:** HmIP funktioniert ohne Internet und ohne Schlüsselserver. Ein Tausch des Funkmoduls
  braucht kein Umschlüsseln über eQ-3 und kann deshalb auch nicht von eQ-3 abgelehnt werden.
- **Preis:** Eine bestehende Installation muss beim Umstieg **jedes HmIP-Gerät einmal neu
  anlernen**. Eine Neuinstallation ohne angelernte Geräte kostet der Umstieg nichts.
- **Status bei eQ-3:** Kein offiziell unterstützter Betriebsmodus. eQ-3 nennt die Funktion eine
  Besonderheit für Entwickler und deren Testumgebung, nicht für Endkunden bestimmt (Zitat unten).
- **Pflicht:** Der Schlüssel liegt im Klartext auf dem System und in jeder Sicherung. Die
  Sicherungen müssen geschützt werden.

## Was der lokale Schlüsselmodus ist

Alle HmIP-Geräte eines Systems teilen sich einen **Netzwerkschlüssel**; dazu kommt ein
**Backbone-Schlüssel** für die Access Points (HAP, DRAP).

**Normalerweise** – auf einer CCU3, auf OpenCCU und auf openccu-lite, solange man nichts ändert –
erzeugt das Funkmodul diese Schlüssel beim ersten Start selbst und gibt sie nie im Klartext heraus.
Das System speichert nur eine verschlüsselte Fassung, die allein dieses Modul lesen kann. Das HmIP-Netz
ist damit an genau dieses Funkmodul gebunden. Soll es auf ein anderes Modul umziehen, übersetzt der
Schlüsselserver von eQ-3 (`secgtw.homematic.com`) den Schlüssel für das neue Modul – der
*Adaptertausch*. Das System selbst kennt den Netzwerkschlüssel nicht.

**Im lokalen Schlüsselmodus** gehören die beiden Schlüssel dem System. Sie stehen in
`/etc/config/crRFD/hmip_user.conf` (`Network.Key`, `Backbone.Key`), und der HmIP-Dienst (hmipserver)
schreibt sie bei jedem Start in das Funkmodul, das gerade steckt. Welches Modul das ist, spielt dann
keine Rolle mehr: der Schlüssel kommt vom System, nicht vom Modul. Der Schlüsselserver wird dafür nicht
gebraucht.

Dieselbe Einstellung lässt sich auf einer CCU3 oder unter OpenCCU von Hand in dieser Datei setzen;
im Homematic-Forum wird das seit 2023 als „Schlüssel in Software“ oder „lokale Keys“ beschrieben
([„Funkmodul-Tausch ohne Online-Rekeying“, t=78091](https://homematic-forum.de/forum/viewtopic.php?t=78091),
[Erfahrungsbericht von hce, t=80011](https://homematic-forum.de/forum/viewtopic.php?t=80011)).
openccu-lite bietet sie in der Weboberfläche an, mit einer Sicherung des vorherigen Zustands und
einem Weg zurück.

## Was eQ-3 dazu sagt

Der Forumsnutzer hce hat eQ-3 im Oktober 2023 gefragt, ob die Möglichkeit, die Schlüssel „in
Software“ zu setzen, ausgebaut werden soll. Die Antwort, die er am 10.10.2023
[im Forum zitiert](https://homematic-forum.de/forum/viewtopic.php?p=780106#p780106):

> Leider können wir zu dieser Funktion keine Auskunft geben, da es sich hier um eine Besonderheit
> für den Entwickler und in dessen Testumgebung handelt und nicht für Endkunden bestimmt und damit
> dokumentiert ist.

Das heißt:

- **Der lokale Schlüsselmodus ist kein offiziell unterstützter Modus von eQ-3.** eQ-3 dokumentiert
  ihn nicht, sagt nichts zu seiner Zukunft und kann sein Verhalten mit einer neuen Version der
  HmIP-Software ändern oder ihn entfernen.
- openccu-lite prüft den Modus mit jedem Update der HmIP-Software von eQ-3 erneut. Eine Garantie,
  dass er bleibt, gibt es nicht. Das bedeutet man wird - im Falle, dass eQ-3 den lokalen Schlüsselmodus 
  entfernt - einen alten Softwarestand weiternutzen müssen, dem dann eventuell die Unterstützung für neue 
  Gerätetypen, Bugfixes und Sicherheitsupdates fehlen.

## Was er bringt

- **Offline-fähig.** Für den Funk braucht das System weder Internet noch den Schlüsselserver von
  eQ-3. openccu-lite setzt dazu den Schlüsselserver-Modus auf `LOCAL`: für Modultausch und
  Anlernen fragt hmipserver eQ-3 nicht mehr (siehe [privacy.md, *HmIP key server*](privacy.md#hmip-key-server)).
- **Funkmodultausch ohne Umschlüsseln.** Ein neues oder anderes Funkmodul (RPI-RF-MOD, HmIP-RFUSB,
  ein Modul an einem Funk-Adapter) bekommt den Schlüssel beim Start vom System. Kein Adaptertausch
  über eQ-3, kein stundenlanges Umschlüsseln der Batteriegeräte, keine Internetverbindung.
- **Kein Tausch, den der Schlüsselserver ablehnen kann.** Ohne lokalen Schlüssel entscheidet eQ-3s
  Server, ob ein Modultausch gelingt; lehnt er ab, bleibt HmIP-RF gestoppt (siehe
  [unten](#verhältnis-zum-funkmodultausch-über-den-schlüsselserver)). Im lokalen Schlüsselmodus wird
  er nicht gefragt.
- **Sicherungen sind portabel.** Eine Sicherung aus dem lokalen Schlüsselmodus lässt sich auf einem
  anderen System mit einem anderen Funkmodul einspielen, ohne dass eQ-3 beteiligt ist.

## Was er kostet

### Neuinstallation: nichts

Ist noch kein HmIP-Gerät angelernt, kostet der lokale Schlüssel nichts. Der Willkommensassistent
bietet ihn dann im Schritt *Der HmIP-Netzwerkschlüssel* an: **Jetzt einen lokalen Schlüssel erzeugen**
oder **Beim Schlüsselserver von eQ-3 bleiben**. Nichts ist vorausgewählt; beides lässt sich später
auf der Seite Schlüssel ändern. Wer sich hier für den lokalen Schlüssel entscheidet, lernt alle Geräte
gleich unter ihm an.

### Bestehende Installation: jedes HmIP-Gerät neu anlernen

Ein HmIP-Netz, das über den Schlüsselserver von eQ-3 entstanden ist – also praktisch jede bestehende
CCU3-, OpenCCU- oder openccu-lite-Installation –, hat einen Netzwerkschlüssel, den nur das Funkmodul
kennt. Das System kann ihn nicht auslesen, und er steht auch auf keinem Aufkleber (den Schlüssel vom
Aufkleber des Funkmoduls als Netzwerkschlüssel einzutragen, hilft nicht; im Forum ausprobiert,
[t=79986](https://homematic-forum.de/forum/viewtopic.php?t=79986)).

Beim Umstieg erzeugt das System deshalb einen **neuen** Netzwerkschlüssel. Alle bisher angelernten
HmIP-Geräte kennen nur den alten und **antworten nicht mehr, bis sie neu angelernt sind**:

- **Jedes HmIP-Gerät wird einmal neu angelernt**, eines nach dem anderen, am Gerät selbst (Anlernmodus
  über seine Taste), mit dem [Homematic Manager](https://github.com/hobbyquaker/homematic-manager)
  oder einer anderen Oberfläche, die HmIP-Geräte anlernt. Ein Gerät, das sich so nicht anlernen
  lässt, wird auf Werkseinstellungen zurückgesetzt und dann angelernt.
- **Das gilt auch für HmIP-Access-Points** (HAP, DRAP) und HmIP-Wired: beim Erzeugen bekommt auch der
  Backbone-Schlüssel einen neuen Wert.
- **Direktverknüpfungen und Geräteeinstellungen** danach wiederherstellen. Ein Gerät, das zurückgesetzt wurde,
  hat sie verloren und braucht sie neu.
- **BidCos-Geräte** (Homematic „classic“) sind nicht betroffen; ihr Schlüssel ist ein anderer.

**Vorher planen:**

1. **Eine Sicherung anlegen** (Seite Sicherung) und außerhalb des Systems aufbewahren.
2. **Die Geräteschlüssel bereitlegen.** Jedes HmIP-Gerät hat einen Aufkleber mit QR-Code und KEY.
   Im lokalen Schlüsselmodus wird ein Gerät mit diesem Schlüssel angelernt: entweder vorher auf der
   Seite Schlüssel unter *HmIP-Geräteschlüssel* erfassen (scannen oder eintippen), oder beim Anlernen
   im Homematic Manager per QR-Code. Ein Gerät, dessen Aufkleber fehlt, lässt sich ohne
   Schlüsselserver nicht anlernen (siehe [Anlernen](#anlernen-im-lokalen-schlüsselmodus)).
3. **Schwer erreichbare Geräte zuerst ansehen:** Unterputz-Aktoren hinter Abdeckungen, Rauchmelder
   an der Decke, Geräte in der Verteilung, im Garten, in anderen Gebäuden. Jedes muss einmal in den
   Anlernmodus.
4. **Batteriegeräte** brauchen ebenfalls einen Tastendruck am Gerät. Wer viele hat, plant Zeit ein.
5. **Geräte mit gesperrtem Werksreset** (eine Einstellung mancher HmIP-Geräte) lassen sich nicht
   ohne Weiteres zurücksetzen; vorher klären, ob sie sich ohne Reset neu anlernen lassen.
6. **Einen Zeitpunkt wählen**, an dem HmIP eine Weile ausfallen darf: vom Umschalten bis zum letzten
   neu angelernten Gerät arbeiten die übrigen nicht.

## Risiken und Pflichten

- **Die Schlüssel liegen im Klartext** in `/etc/config/crRFD/hmip_user.conf` und **in jeder
  Sicherung**. Wer eine Sicherung hat, hat den Netzwerkschlüssel und kann dem HmIP-Netz beitreten.
  Sicherungen deshalb verschlüsselt anlegen (Seite Sicherung, *Verschlüsselung*), sicher aufbewahren
  und nicht weitergeben.
- **Die Sicherung ist der Schlüssel.** Geht das System verloren (defekte SD-Karte, defekte Platte)
  und gibt es keine Sicherung, ist der Netzwerkschlüssel weg, und jedes HmIP-Gerät muss neu angelernt
  werden. Ohne lokalen Schlüssel gilt das übrigens genauso – nur hängt dort zusätzlich alles am
  Funkmodul und am Schlüsselserver.
- **Anlernen und erneutes Anmelden brauchen den Geräteschlüssel.** Ohne Schlüsselserver nimmt das
  System ein Gerät nur mit dessen Schlüssel (QR-Code/KEY vom Aufkleber) an. Das betrifft auch ein
  Gerät, das sich nach einem Firmware-Update neu an der Zentrale anmeldet: dafür braucht das System
  den Geräteschlüssel unter *HmIP-Geräteschlüssel* oder, ausnahmsweise, den Schlüsselserver. Am
  einfachsten erfasst man die Schlüssel aller Geräte einmal auf der Seite Schlüssel. Das geht komfortabel
  mit dem eingebauten QR-Code Scanner.
- **eQ-3 kann das Verhalten ändern** (siehe [oben](#was-eq-3-dazu-sagt)). Ein Update der
  HmIP-Software könnte den lokalen Schlüsselmodus einschränken oder entfernen.

## Einschalten

**Systemmenü → Schlüssel → Lokaler Schlüssel**, nur für Administratoren:

1. **Auf lokalen Schlüssel umschalten** öffnen.
2. Unter *Woher der Schlüssel kommt* wählen:
   - **Einen neuen Schlüssel erzeugen** – der Normalfall. Das System erzeugt Netz- und
     Backbone-Schlüssel aus Zufallszahlen. Jedes bereits angelernte HmIP-Gerät muss danach einmal neu
     angelernt werden (siehe oben).
   - **Den Schlüssel des Netzes eingeben** – nur, wer den echten Netzwerkschlüssel kennt
     (*Netzwerkschlüssel*, 32 Hex-Ziffern; *Backbone-Schlüssel (optional)*). Dann wird nichts neu
     angelernt.
3. **Auf lokalen Schlüssel umschalten** bestätigen. HmIP-RF startet sofort neu; der Funk ist etwa
   eine Minute nicht verfügbar.

Was dabei geschieht:

- **Vorher** legt das System eine Kopie der bisherigen HmIP-Identität des Funkmoduls beiseite. Sie
  erscheint unter *Aufbewahrte Identitäten* und bleibt, bis man sie verwirft. Sie ist der Weg zurück.
- Die Schlüssel werden in `hmip_user.conf` geschrieben, der Schlüsselserver-Modus auf `LOCAL`
  gesetzt, HmIP-RF neu gestartet. Die Schlüssel selbst zeigt die Seite nie an.
- **Nach einem eingegebenen Schlüssel** beobachtet das System zehn Minuten lang die Geräte, die vorher
  geantwortet haben. Bleiben sie stumm, war der Schlüssel vermutlich nicht der des Netzes; die Seite
  Schlüssel und die Statusseite sagen das, mit dem Weg zurück daneben.

### Anlernen im lokalen Schlüsselmodus

- **Mit Geräteschlüssel, offline:** den Schlüssel vorher unter *HmIP-Geräteschlüssel* erfassen oder
  beim Anlernen im Homematic Manager den QR-Code scannen. eQ-3 wird nicht gefragt.
- **Ohne Geräteschlüssel** (Aufkleber verloren): *Den Schlüsselserver für das nächste Anlernen
  erlauben* auf der Seite Schlüssel. Dann darf hmipserver eQ-3 für genau dieses Anlernen fragen; die
  Erlaubnis endet nach dem nächsten Anlernmodus, spätestens nach 30 Minuten. Das braucht Internet und
  einen Neustart von HmIP-RF.

## Zurück zum Schlüsselserver von eQ-3

**Systemmenü → Schlüssel → Lokaler Schlüssel → Zurück zum Schlüsselserver von eQ-3.**

- Das System legt die beim Einschalten aufbewahrte Identität des Funkmoduls zurück, nimmt die
  Schlüsselzeilen aus `hmip_user.conf` und startet HmIP-RF neu. Danach gehört das HmIP-Netz wieder dem
  Funkmodul, und die Geräte, die **vor** dem Umschalten angelernt waren, arbeiten wieder wie zuvor.
- **Geräte, die seit dem Umschalten unter dem lokalen Schlüssel neu angelernt wurden, müssen erneut
  angelernt werden** – auch die, die man beim Umstieg schon neu angelernt hatte.
- Das geht **nur mit dem Funkmodul, von dem die aufbewahrte Identität stammt**. Steckt ein anderes,
  ist die Schaltfläche gesperrt und sagt warum. Wurde die aufbewahrte Identität verworfen, gibt es
  keinen Weg zurück; dann bleibt nur ein Neubeginn unter dem Schlüsselserver mit erneutem Anlernen
  aller Geräte.

## Funkmodul tauschen

**Im lokalen Schlüsselmodus:** das neue Modul einbauen oder anstecken und es auf der Seite
Schnittstellen unter *Verbindungen* für HmIP wählen (oder die automatische Wahl lassen). Beim Start
schreibt hmipserver den Schlüssel des Systems in das neue Modul; die Geräte bleiben angelernt. Kein
Internet, kein Schlüsselserver. Der Dialog auf der Seite Schnittstellen sagt in diesem Fall, dass
kein Schlüsselserver beteiligt ist.

## Verhältnis zum Funkmodultausch über den Schlüsselserver

**Ohne lokalen Schlüssel** ist ein Modultausch ein *Adaptertausch* über den Schlüsselserver von eQ-3:
beim Wechsel der Verbindung, nach dem Import angelernter Geräte aus einer Sicherung eines anderen
Systems oder nach dem Einspielen einer Sicherung. Wie das in openccu-lite abläuft, beschreibt
[Geräte in eine Neuinstallation übernehmen](switching.de.md#geräte-in-eine-neuinstallation-übernehmen) in switching.de.md. Dabei gilt:

- Der Tausch braucht eine Internetverbindung, und **der Schlüsselserver kann ihn ablehnen**, auch für
  ein Funkmodul, das er schon kennt. Einen Grund nennt die Meldung nicht.
- Nach einer Ablehnung bleibt HmIP-RF gestoppt. Die Seite Schnittstellen zeigt das und bietet die
  Auswege an: das vorherige Modul (*Zurück zum vorherigen Modul*, wenn das System vor dem Wechsel eine
  Kopie aufbewahrt hat) oder *Mit diesem Modul neu beginnen…* – ein leeres HmIP-Netz, in dem jedes
  Gerät neu angelernt wird. Dieser Neubeginn bietet an, **im selben Schritt auf den lokalen Schlüssel
  umzustellen**; das ist der günstigste Zeitpunkt, weil ohnehin jedes Gerät neu angelernt wird.
- Der lokale Schlüsselmodus rettet **kein bestehendes Netz**, dessen Tausch abgelehnt wurde: auch
  dann wird jedes Gerät neu angelernt. Er sorgt dafür, dass es **beim nächsten Tausch** nicht wieder
  auf eQ-3 ankommt.
