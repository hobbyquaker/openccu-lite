# Switching between OpenCCU (or a CCU3) and openccu-lite

*English — the German version is [switching.de.md](switching.de.md).*

Going **to** openccu-lite is a supported operation. Coming **back** is done by restoring the
backup you took before you left — not by flashing OpenCCU over lite and expecting your
configuration to be there.

**Take a backup before you migrate, and keep it.** That `.sbk` is the way back. Everything else on
this page is mechanics. **Since 2026-09-25 there is no other way back at all:** after its
first start openccu-lite removes the CCU's leftovers from the userfs - the ReGa database
(`homematic.regadom` and its `.bak`), the WebUI's `measurement` and `userprofiles`, ReGa's working
files and mediola's NEO Server - once the names have been imported from them. The radio identity,
the keys, the interface configuration and the addons stay.

The mechanics are the easy half: same partition layout, same image and update package format, and
`/usr/local` — pairings, radio keys, interface configuration, addons — survives either way. What
does not survive is ReGa's database. openccu-lite does not run ReGaHss, so from the moment
you switch, the `homematic.regadom` on the system stops being maintained: every name, room, function,
program and system variable you change afterwards exists in openccu-lite's metadata store and
nowhere else. Flashing OpenCCU back gives you OpenCCU with a ReGa database frozen at the day you
left, and no amount of copying pieces across changes that. **This page used to claim otherwise, and
offered an HM-Script export to paper over the gap. Both are gone (2026-09-08).**

## OpenCCU / CCU3 → openccu-lite

**The short version for an OpenCCU VM (`ova`) or an SD-card product**: on the OpenCCU WebUI go to
Settings → Control panel → CCU maintenance → Perform software update, upload `openccu-lite-<product>-<version>.zip`
(**a CCU3 takes the `-ccu3.tgz` instead**, see *Which package for which system* below), confirm,
let it reboot. OpenCCU's own recovery system flashes the image and keeps `/usr/local`; the lite system
comes up with your pairings, keys and addons, reads the names, rooms and functions out of the ReGa
database on its first boot, and asks you for an administrator password. The `.zip` is accepted
because the lite image's `/VERSION` carries upstream's `PLATFORM` — the recovery compares
exactly that. **The way back**: flash OpenCCU through the *System update* section of the lite Status page with upstream's `OpenCCU-<version>-ova.zip`, then **restore the backup you took before migrating**. The flash alone gets you a working OpenCCU with your pairings, keys and addons — `/usr/local` survives — but its ReGa database is the one from the day you left. The backup is what makes the system the system it was.

### Which package for which system

A release carries more than one file per board. Which one your system takes depends on how it was
set up, not on the hardware alone — `cat /VERSION` over SSH (`PRODUCT=…`) tells you which one you have:

| Your system | Package | What happens on the way |
| --- | --- | --- |
| OpenCCU written to an SD card or USB disk from an OpenCCU image (`PRODUCT=rpi3`, `rpi4`, `rpi5`, …) | `openccu-lite-<product>-<version>.zip` | one pass of the recovery system: it unpacks the image on the userfs, writes the boot and root partitions, keeps `/usr/local`, reboots. About three minutes. |
| The OpenCCU VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | the same, one pass. |
| A CCU3, or any card set up from eQ-3's CCU3 image or a CCU3 backup image (`PRODUCT=ccu3`: bootfs 256 MB, rootfs 1 GB, userfs) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | the WebUI unpacks the archive and the recovery runs its `update_script`: it writes the new boot partition — with openccu-lite's recovery system — and, because the root partition is 1 GB and the image 2 GB, hands the rest over to that new recovery. **Two recovery passes, two reboots:** the second one grows the root partition to 2 GB, moving the user partition, and writes the root filesystem. Plan for the system to be dark for ten minutes or more. |

The `.zip` is the wrong package for a CCU3-shaped system: its image is laid out for an SD card,
and the recovery would need the unpacked 2.4 GB on the userfs anyway. The `-ccu3.tgz` is the route
built for that layout (upstream's CCU3 → OpenCCU path, which openccu-lite reuses).

### The space the update needs

The recovery unpacks the update **on the userfs (`/usr/local`) before it writes anything**: the
`.zip`'s image is about 2.4 GB unpacked, the `-ccu3.tgz`'s root filesystem 2 GB, each on top of the
upload itself. Check first — the stock WebUI shows it on the *CCU maintenance* page under *Perform
software update* as *Available user space: X GB (> 2.8 GB required)*, and over SSH `df -h /usr/local`
shows it in the *Avail* column. **Below 2.8 GB free, do not start.** Old backups under
`/usr/local/tmp` and large addon data are the usual reason; remove them first. On a CCU3-shaped card
whose user partition does not reach the end of the card, openccu-lite's recovery grows it — but that
only helps on the second pass, and only when the free space is behind the partition, not when the
partition is full.

### Check before switching

- **A backup taken and kept** — the `.sbk` from Settings → Control panel → Security → Create backup
  (or `createBackup.sh`), copied off the system. It is the way back.
- **Enough free space** on the userfs (above): at least 2.8 GB.
- **The right package** for your system's shape (the table above), its `.sha256` checked.
- **SSH or physical access at hand.** A switch that stops half-way leaves the system in its recovery
  system, which speaks plain HTTP on port 80 only; the recovery LED pattern on a CCU3 is the hint. Have
  the SD card or the VM's console reachable, and the address of the system written down: a failed
  update may come back on a new DHCP address.
- **A power supply you trust** for the duration: the second pass writes partition tables.

### A recovery that stays at its menu

A recovery system that stays up after an unattended update — a dark WebUI, and `http://<system>/`
shows the recovery's menu instead of the update output — means **the update failed and the recovery
did not boot the normal system**. eQ-3's 2018 CCU3 recovery, which every CCU3 runs before its first
openccu-lite update, does exactly that: its unattended update stops at the menu on any error, and
the reason is on the page only while the output is still there (the recovery page shows the running
update's output; once it is over, the menu). OpenCCU's and openccu-lite's recovery systems reboot
into the normal system after a failed unattended update instead, and openccu-lite keeps the reason:
the last lines of `/usr/local/var/recovery/<time>.log`, which the journal carries on the next boot.

**The way back from the menu:** *Normal Reboot* on the recovery page boots the system that was there
before (`/usr/local` and the pairings untouched), and you can look at the space, the package and the
`.sbk`, and start over. *Check storage* on the same page runs `e2fsck` over the partitions and shows
what it repaired — useful after a failed second pass. What you must not do is upload the same package
again from the menu without knowing why the first attempt failed: the space is the usual reason, and
it does not grow by itself.

1. **Back up** on the old system (Settings → Control panel → Security → Create backup, or `createBackup.sh`).
   Keep the `.sbk`.
2. **Flash / update** to openccu-lite. The updater accepts the package; the recovery system is
   upstream's.
3. **First boot**: if you updated in place, the system has its pairings and keys already —
   `/usr/local` was not touched — and you set the administrator password once. If you reflashed,
   **restore the `.sbk` first** (the Backup page is reachable after a throw-away administrator is
   created): the restore replaces `/usr/local` wholesale — pairings, keys, addons, and also
   `occulited`'s own state — so the administrator you created before the restore is gone and the
   system asks for one again on the next visit. That order is deliberate: nothing from the old system
   is lost, and nothing from before the restore lingers. The ReGa database inside the backup is
   accepted and simply ignored. **A backup with a non-default BidCos security key** (the old CCU's
   *System-Sicherheitsschlüssel*): the Backup page asks for its passphrase - only to check that the
   one you have is right; it is compared with the backup's signature and never stored. *Skip - I do
   not know it* is always there, and a wrong or skipped passphrase never stops the restore: after a
   clear warning and your confirmation it goes on. The restore itself re-keys no device - the key
   comes back as it is and the BidCos devices keep working - but the passphrase is what you need
   later to change the key, to re-key the devices (moving them to another system, setting the key
   again), to pair them with another central, or to restore onto a system with a different key.
   Without it, the only way back is a factory reset of every such device and pairing it again, so
   find it while the old CCU is still at hand.
3a. **Paired devices from the backup instead of a restore** (a new install, nothing paired yet): the
   Backup page reads the `.sbk` once and *Import the paired devices and reboot* takes the three radios'
   pairings with their identity - the BidCos address and key store, the HmIP identity, the LAN
   gateways - and, first, the names, rooms and functions of the backup's ReGa database; then the
   system reboots. Two things the panel tells you before you click:
   - **Another radio module.** The HmIP identity in a backup is bound to the module of the system
     that made it. When this system runs HmIP-RF on another module (a different SGTIN), hmipserver
     takes the identity over onto this module when it starts after the import - the *adapter
     exchange*: offline when the backup came from a system in local key mode, otherwise through
     eQ-3's key server, which needs an internet connection and has to know this module. Every HmIP
     device is then re-keyed for the new module; a battery device only when it wakes up, so press a
     button on it if it stays silent, and give it hours rather than minutes. The Interfaces page
     shows how the move went (pending, done, rejected) and offers a retry - a restart of HmIP-RF,
     which attempts the exchange at every start. A module the key server refuses keeps HmIP-RF
     stopped; the way out is the previous module, or a fresh start with this one (every HmIP device
     paired again). BidCos-RF needs no exchange: rfd runs with the imported address and serial on
     whatever module it has - an RPI-RF-MOD, an HM-MOD-RPI-PCB, an HmIP-RFUSB, an HM-CFG-USB-2 or a
     LAN gateway alike - and the Interfaces page says whether it does.
   - **A non-default BidCos security key.** The backup's key store comes along as it is - the BidCos
     devices paired with it know that key - and the import works without the other system's
     passphrase. The panel asks for it all the same, as a check that the one you have is right (the
     restore above does the same, with the same warning when it does not match or you skip it); the
     import goes on either way. Keep that passphrase safe: you need it to change the key later, to
     re-key or re-pair these devices, or to restore onto a system with another key. A system that already has a key
     of its own confirms that the backup's replaces it; a system with devices paired refuses the
     import altogether, so no paired device is ever re-keyed by it.
4. **Names, rooms and functions**: while the old CCU is still reachable, *Names → Import from a
   CCU* pulls them over its remote script port (8181). The old CCU's firewall must allow the new
   system (REGA: *full*, or the new address in the list). Rooms and functions become flat nodes;
   objects still carrying the CCU's default `<type> <address>` name are left out and counted.
   If the old CCU is gone, run the same import from any CCU that has the backup restored, or
   import a `meta.json` exported earlier.

   **Umlauts**: the ReGa database declares `iso-8859-1` and is not — it is mixed. eQ-3's own
   strings really are Latin-1 (a unit is the single byte for "°C"), while a name a user typed on a
   current firmware is UTF-8 in the same file. Both are read correctly; before 2026-09-07 every
   umlaut in a name came across as `Ã¼`. If you are looking at an import taken with an older image,
   that is what you are seeing, and a re-import on a current one fixes it. A system whose ReGa has the
   same room in both encodings — which happens on a CCU that has been through several firmware
   generations — ends up with one room here, not two.

   **The CCU's own rooms and functions**: the eleven rooms and ten functions a CCU creates by
   itself (Wohnzimmer … Terrasse, Licht … Energiemanagement) are stored in ReGa under a
   translation key — `roomBathroom`, or `${roomBathroom}` — and the WebUI swaps in the name from
   its language files on every page. Every import (from this system, from a backup, from a running
   CCU) now does the same, with the WebUI's German names: `roomBathroom` becomes *Badezimmer*,
   `funcHeating` *Heizung*. Only a name that is exactly one of these keys is translated; one you
   typed stays as it is, and an English system renames them by hand. A store imported before this
   (it lists `roomBathroom`, `funcCentral` … in the App's drawer) is corrected when `occulited`
   starts: those nodes are renamed in place, keep their ids (`room/roombathroom`) and so their
   members, and each rename is an ordinary revision on the change stream.
5. **What does not come across**: programs, system variables, alarms, favourites, diagrams —
   there is nothing here that could run or show them. Automation moves to Node-RED (RedMatic),
   Home Assistant, ioBroker or whatever you already use.
6. **Addons**: those in the [catalogue](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md) are known to work. Addons that need
   the ReGa (CUxD, the XML-API, anything that reads system variables or keeps its settings in the
   ReGa DOM) are **disabled on this first boot** and listed on the Addons page as "disabled,
   incompatible", each with the reason; they are not uninstalled, and a switch brings one back
   for the brave. The catalogue does not list such addons at all.
7. **Addons with binaries for another architecture** are disabled on the same first boot and
   listed as **"disabled, needs update"** with the offending file named. `/usr/local`
   survives a switch, so an addon installed on the old system comes along exactly as it was — and an
   addon compiled for a machine this one is not cannot run here. See
   [Architecture and addon binaries](addons.md#architecture-and-addon-binaries): the repair is the
   catalogue's *Install* / *Update* button, which fetches the release built for this system.
8. **mediola's NEO Server**, which OpenCCU's own package unpacks onto the userfs
   (`/usr/local/addons/mediola`, `rc.d/97NeoServer`), comes across too and cannot work here: it
   posts to `/tclrega.exe` and `/api/homematic.cgi`, the ReGa and the WebUI's CGI stack.
   openccu-lite switches it off **once**, with the addon's own switch (`Disabled` in its
   directory, which its rc.d script honours) and the executable bit of its rc.d entry, and lists
   it with the other ReGa-dependent addons on the Status and Addons pages. After the first start
   it goes with the other leftovers (what the addon's own uninstall does, `neoDisabled`
   marker included).
10. **The leftovers** (there is no way back except the backup taken before the migration):
   once the first-boot name import has read the ReGa database (or settled: given up, or not needed
   because the store holds names), occulited removes exactly this list, once - `homematic.regadom`,
   `homematic.regadom.bak`, `measurement`, `userprofiles`, `etc/config/rega`, the NEO Server - and
   writes `<state>/ccu-leftovers-removed.json` and one journal line (`ccu leftovers removed …`, the
   paths and the bytes freed). An import that has still to run keeps them, with a warning, until a
   later start. A system with nothing left over records an empty run, so a CCU backup restored
   later is not swept. The Backup page's *Leftovers from OpenCCU* panel is gone.
9. **An addon's state outside its own directory** — homematic-manager's profile in
   `/usr/local/hmm`, root-owned from its OpenCCU days — is taken over when the addon is confined: chowned to the addon's user and made writable in its unit, at the confinement and again
   at every start, so an addon that was confined and then could not write its own state
   is repaired by the next update.

### Acceptance test on a VM (first run 2026-09-06)

What "everything keeps working" means, as a checklist. Run it on a Proxmox snapshot of the
OpenCCU VM so the way back is one click even if the software way back fails.

1. Before: note on the OpenCCU WebUI the device count, one device name, one room, the security
   key state (Settings → Control panel → Security), the LAN gateways, the addons, the IP/hostname.
   Take a `.sbk` backup and the Proxmox snapshot.
2. Upload `openccu-lite-x86_64-ova-<version>.zip` in Settings → Control panel → CCU maintenance → Perform software update, confirm,
   let it reboot. The recovery shows its progress on the console; the whole thing is ~3 minutes.
3. First visit of `http://<system>/`: the welcome page asks for an administrator password and shows
   the regadom import result — devices, channels, rooms and functions counted. `curl
   http://<system>/api/system/v1/status` → `first_boot_import` has the same numbers.
4. Check, in this order: **Radio** (module detected, `hm_mode` as before, security key "set" if it
   was, LAN gateways listed), **Names** (the device you noted has its name, the room exists with
   its channels), **Addons** (the same list, running), **Network** (address and hostname unchanged),
   **Log** (rfd/hmipserver lines, no error loop), **Services** (rfd, hmipserver up). The files you
   know from OpenCCU (`/var/log/messages`, `hmserver.log`, `lighttpd-*.log`) are the journal here:
   the Log page, its download, or `journalctl` (`-t hmipserver`, `-t lighttpd`).
5. A device round trip: press a paired device, watch its channel event in the Names page or via
   `/api/system/v1/radio/health` (the duty cycle updates) — the pairing survived if it does.
6. The way back: on the Status page upload `OpenCCU-<version>-ova.zip` (upstream's), *Reboot and
   install*. OpenCCU comes back **without** its ReGa database (openccu-lite removed `homematic.regadom`
   after its first start): restore the backup taken before the switch. A `meta.json` under
   `/usr/local/etc/occulite/` stays for the next switch.
   That is the second half of the acceptance test: **both directions, no reflash**.

Anything on this list that fails is a bug, not a documentation gap.

### What the run of 2026-09-07 found

The forward half was run on a test VM in the night of 2026-09-06/07, on an `ova-lite-systemd`
image built that night. It found twenty-seven bugs, three of which the
checklist above cannot phrase because nobody had got that far before:

- the system booted with **no firewall at all** — nothing written in Tcl ran;
- **the update could be installed once and never again**: the recovery system's own `/VERSION`
  kept the lite product name while the image's is rewritten to upstream's, so the recovery
  a lite image installs refuses every lite image — and refuses upstream's `ova.zip`, i.e. step 6
  of this list, the way back;
- the Network page and the LAN gateway list were empty on a system that had both, and a save would
  have written that emptiness back.

With those fixed, the list passes: the system installs a release zip from its own Status page and is
back in two and a half minutes with its addons, its metadata store and its configuration intact;
*Names → Import names from a ReGa database* reads the system's own ReGa database and reports what it found; the Radio,
Names, Addons, Network, Log and Services pages all answer with the system's real state; and the five
verified catalogue addons install, start in their own units and survive the firmware update.

### Step 6, the round trip, run on 2026-09-07 06:26–06:46

Both directions, on the same test VM, with upstream's own
`OpenCCU-3.89.8.20260719-ova.zip` (403 218 494 B, checksum verified against the release's
`.sha256`) and the night's `…-lite.0-beta.1-ova-lite-systemd.zip`:

| | how | took |
| --- | --- | --- |
| lite → OpenCCU | the lite Status page: `POST /system-update/upload` (accepted, `board: ova` against the running `platform: ova`), then *Reboot and install* | 3 min |
| OpenCCU → lite | OpenCCU's **own** WebUI path: its `cp_maintenance.cgi` validated the zip (it looks for `EULA.de`/`EULA.en` inside — the lite zip carries both), staged it and rebooted | 2.5 min |

What came back on the OpenCCU side: `ReGaHss` running and answering `rega_script`
(`dom.GetObject(1555).Name()` → `HM-CC-TC JEQ0230153`, thirteen room objects), `rfd`, lighttpd,
`sshd`, mosquitto and RedMatic's Node-RED, the four addons still in `/usr/local/addons` and their
`rc.d` links, `homematic.regadom` untouched at its pre-switch timestamp, and `meta.json` waiting
under `/usr/local/etc/occulite/` for the next switch. The recovery's own log for the way in is
worth reading once: *"[2/5] Checking update_script… no 'update_script', OK … flashing bootfs…OK,
updating bootloader (GRUB)… OK, flashing rootfs……OK, DONE"* — upstream's recovery flashing an
openccu-lite image without a word about the platform, which is what the lite image's `/VERSION`
keeping upstream's `PRODUCT` is for.

And back on the lite side afterwards: no failed units, the four `addon-*.service` units active,
55 firewall rules, no unclean-shutdown marker, the administrator login working and the metadata
store still at revision 1 with the channel renamed on the lite side and its room enum
(`BidCos-RF.JEQ0230153:1` → *Wohnzimmer Thermostat*, `room/wohnzimmer`). **Nothing had to be
reflashed, and nothing was restored from a backup.**

The round trip found one bug: the `occulite` user's id was auto-allocated out of buildroot's
system pool (100…999), which is the pool upstream fills with *its* system users, so on the OpenCCU
side the metadata store — `users.json`, `local-token` — belonged to upstream's `sshd`
privilege-separation user. The id is pinned to 8100 now; both init paths already repair the
store's ownership at boot, so an older system updates into the change without noticing it.

## openccu-lite → OpenCCU / CCU3

**The one that matters: restore the backup you took before you migrated.** Everything below
assumes you have it. If you do not, you can still get back to a running OpenCCU — you will not get
back to *your* OpenCCU.

0. **What openccu-lite removed**: `homematic.regadom` and the WebUI's data are gone after its first
   start. Names, rooms and functions changed on the lite side live in the metadata store
   and nowhere else. Programs and system variables were never on the lite
   side at all. So OpenCCU wakes up as it was when you left it — which is exactly why the
   pre-migration backup is the answer and not an afterthought.
1. **Flash / update** to OpenCCU: lite Status page → *System update* → upstream's
   `OpenCCU-<version>-<PRODUCT>.zip` → *Reboot and install*. `/usr/local` survives, so pairings,
   radio keys and addons are already there. A CCU3-shaped system (`PRODUCT=ccu3`) has a 2 GB root
   partition after the switch, which is upstream's current layout too; its way back is upstream's
   `OpenCCU-<version>-ccu3.tgz` — a route that has not been run here yet, so keep the `.sbk` and the
   reflash fallback below in mind.
2. **Restore the pre-migration `.sbk`** through OpenCCU's own WebUI. This is the step that makes
   it your system again.
3. The metadata store's `meta.json` stays in `/usr/local/etc/occulite/` and is untouched by any of
   this, so switching to lite again later finds its names where it left them.

**With HSTS on** (System → Certificate): switch HSTS off, then **open the system once by its
name in every browser you use** before you install OpenCCU's zip — or open the system by its IP address
after the switch. Uploading a file that is not an openccu-lite release switches HSTS off by itself,
and the Status page then names the names to open. While HSTS is off, the system sends
`Strict-Transport-Security: max-age=0` for as long as the period was, at most 30 days, and a browser
that sees it forgets HSTS for that name. A browser that did not visit in that time still
remembers it: the recovery system that installs OpenCCU serves plain HTTP only, and OpenCCU serves a
self-signed certificate as soon as the one lite installed is within a day of expiring (upstream
renews nothing and replaces it). Such a browser refuses both under that name — the recovery page as
*connection refused*, OpenCCU's certificate with no way past — until the max-age has run out after
its last HTTPS visit (seven days by default). `max-age=0` has to reach the browser
before the switch: neither the recovery system nor OpenCCU can send it. `http://<IP address>/`
always works, since HSTS never applies to an address; the lite Status page's install notice links to
the recovery that way.

**There is no export to carry names back with.** There used to be an HM-Script export for exactly
that, and it was removed on 2026-09-08: it encouraged treating a half-migration as reversible when
the honest answer is a backup. Programs, system variables, and anything else that only ReGa
understands were never expressible that way either.

**Encrypted backups:** a `.sbk.age` from the lite Backup page is no `.sbk` for OpenCCU or a
CCU3. For the way back either use *Download unencrypted (for OpenCCU or a CCU3)* on the running lite
system — it asks for the password and is journaled — or decrypt the `.sbk.age` on a PC with
`age -d -i key.txt -o backup.sbk backup.sbk.age`, where `key.txt` holds the `AGE-SECRET-KEY-1…` line
from the emergency kit. The pre-migration `.sbk` of the way back was never encrypted.

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

## The reflash fallback

If one updater refuses the other's package (a version check, a changed partition table), flash
the image from scratch and restore the `.sbk`. Everything above still applies; only the flashing
step changes — and the backup is doing the same work either way.
