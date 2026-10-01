# Known issues

*English — the German version is [bekannte-probleme.md](bekannte-probleme.md).*

Known problems of the Homematic software that openccu-lite runs, and what openccu-lite does about them.

## HmIP devices unreachable after a reboot: the security counter

**The symptom:** after a reboot or an update every HmIP device stops answering - local operation
included - while BidCos-RF devices on the same module keep working, and another reboot of the system
does not help. **The cause** (eq-3/occu#134, OpenCCU/OpenCCU#4274; reports in the forum since
2025-11): every HmIP frame carries a security counter the devices only accept going up. At each
start hmipserver reads the radio module's counter (*"Current Security Counter: N"* in its journal)
and computes a value from the wall clock and two numbers kept in the access point's file
(`crRFD/data/<SGTIN>.ap`: the time of the first connection and an offset), and writes it to the
module when it is higher (*"Update security counter to calculation: M"*). The module takes the lower
32 bits of that value while the comparison is done on the whole of it: once the computed value has
passed 2³² the check protects nothing, and a start with a clock behind real time - a CCU without a
real-time clock after a power cut, its NTP unreachable - followed by a start with the right clock
sets the module's counter below what the devices have seen. From then on they drop every frame of
the system as a replay.

**What openccu-lite does about it:**

- **The clock never starts at 1970.** The boot advances the clock to the image's build at least,
  then to the time saved at the last shutdown (hourly), and the radio stack waits for a real-time
  clock or a time server (`occu-clock-valid`, at most about 150 s). `chronyd` always runs.
- **A clock is trusted only between the image's build and 15 years after it** - from a real-time
  clock, from a time server, and set by hand on the Network page alike. A real-time clock with a
  dead battery or a bogus time, or a time server serving a wrong year, is not taken; the Status
  page says so. A clock far ahead would push the counter past 2³² for good.
- **The counter is watched.** `occulited radio ready hmipserver` reads the two lines of every start
  (the logger that writes them stays at *info* whatever the HmIP log level), and `occulited radio
  prep hmipserver` computes what the next start would write from the access point file and the
  running clock. The Status page warns when the counter has passed 2³¹ (*near*: keep the clock
  synchronised), 2³² (*wrapped*: the protection is gone), or was set below what the devices saw
  (*backwards*: the remedy below).
- **On a wrapped or at-risk access point hmipserver is held back while the clock is not trusted**
  (the gate timed out, or refused the real-time clock or the time server). The Status page says
  so; a time set by hand on the Network page, or a time server that answers, releases it. The
  cost: such a system without a time server does not start HmIP-RF until the time is set. A system
  whose access point was created on openccu-lite is not exposed: its offset is a few thousand, and
  the counter reaches 2³² about 40 years after the first connection.
- **A backup's access point is judged before an import or a restore**: the Backup page shows the
  computed value and the verdict, so you know the state of the system you bring.

**When it has happened anyway** (the Status page says *backwards*, or every HmIP device is silent
while BidCos works): rebooting the system does not help. **Power-cycle the devices** - battery out
and in, the fuse off and on for mains devices - or pair them again. Editing the offset in the access
point file by hand (the workaround in the issue) only postpones the next wrap. The fix belongs in
eQ-3's HmIP server; openccu-lite ships that binary unchanged and follows the tickets.
