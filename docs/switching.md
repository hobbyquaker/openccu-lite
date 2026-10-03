# Switching between OpenCCU (or a CCU3) and openccu-lite

*English — the German version is [switching.de.md](switching.de.md).*

**Take a backup (`.sbk`) before you switch, and keep it. It is the only way back.** After its first start
openccu-lite removes the CCU's ReGa database and the WebUI's data from the system (see
[What changes on the first start](#what-changes-on-the-first-start)). Flashing OpenCCU back without the backup gives you
a working OpenCCU with your pairings and keys, but without your names, rooms, programs and system variables.

## OpenCCU / CCU3 → openccu-lite

In the OpenCCU or CCU3 WebUI: Settings → Control panel → CCU maintenance → Perform software update, upload the
package (below), confirm, let it reboot. Pairings, keys, the interface configuration and the addons stay in
`/usr/local`. On the first start the system takes over the names, rooms and functions from the ReGa database and asks
for an administrator password.

### Which package for which system

`cat /VERSION` over SSH (`PRODUCT=…`) tells you what your system is:

| Your system | Package | What happens |
| --- | --- | --- |
| OpenCCU on an SD card or USB disk (`PRODUCT=rpi3`, `rpi4`, `rpi5`, …) | `openccu-lite-<product>-<version>.zip` | one recovery pass, one reboot, about three minutes |
| The OpenCCU VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | the same |
| A CCU3, or a card set up from a CCU3 image or CCU3 backup image (`PRODUCT=ccu3`) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | two recovery passes and two reboots: the second grows the root partition to 2 GB. Plan for about 25 minutes after *Start update*, up to 30-40 minutes on a slower or larger card (see [below](#a-dark-update-on-a-raspberry-pi-3-or-charly)). |

The `.zip` is the wrong package for a CCU3-shaped system; take the `-ccu3.tgz`.

**A new installation** needs no update: write the `.img` from the release's `.zip` to an SD card (Raspberry Pi 3/4), or
import the `.ova` (Proxmox, VMware, VirtualBox). Then bring your old system's devices across with a
[restore or a device import](#bringing-the-devices-into-a-new-installation).

The VM (the `.ova`, and the package for the OpenCCU VM) is meant for testing, not for production; see the
[recommendations](recommendations.de.md#virtualisierung) (in German).

### The space the update needs

The recovery unpacks the update on the userfs (`/usr/local`) before it writes anything. **You need at least 2.8 GB
free.** The WebUI shows it under *Perform software update* (*Available user space*), SSH with `df -h /usr/local`.
Old backups under `/usr/local/tmp` and large addon data are the usual culprits; remove them first.

### Check before switching

- **A backup**, taken in Settings → Control panel → Security → Create backup and copied off the system.
- **2.8 GB free** on the userfs.
- **The right package** (the table above), its `.sha256` checked.
- **Access if something goes wrong:** the system's address written down (a failed update may come back on a new DHCP
  address), and the SD card or the VM's console within reach.
- **Reliable power** for the whole update: the CCU3's second pass writes partition tables.

### A dark update on a Raspberry Pi 3 or Charly

On a Raspberry Pi 3 (a Charly or a CCU3-shaped card) the recovery may run **without a network**: the board's
Ethernet chip sometimes does not come back after the reboot into the recovery. The update goes on regardless, but
`http://<system>/` shows nothing while it runs. **A fast magenta blink of the status LED means: the update is running -
wait, do not power off.** With the `-ccu3.tgz` it takes about 25 minutes after *Start update* on a Pi 3 with a 32 GB
card (the upload before it about 5 minutes; the longest step, moving the userfs to make room for the larger root
partition, about 10 minutes at 4 MB/s); a slower or larger card takes longer, **up to about 30-40 minutes**. Then the
system reboots into openccu-lite by itself, and its network is back. The recovery keeps its own log and what it saw of
the network and the USB devices; openccu-lite shows it in its log (tag `recovery`) after the first start.

### A recovery that stays at its menu

If the WebUI stays dark and `http://<system>/` shows the recovery's menu, **the update failed**. The CCU3's original
recovery stops there on any error. *Normal Reboot* starts the previous system with `/usr/local` untouched; *Check
storage* runs `e2fsck` over the partitions. Find out why it failed before you try again; it is usually the free
space, and that does not grow by itself. openccu-lite's own recovery reboots into the normal system after a failure,
and the journal shows the reason on the next start.

### Bringing the devices into a new installation

The Backup page offers two ways:

- **Restore the `.sbk`**: it replaces `/usr/local` completely, with pairings, keys, addons and the system's own
  state. The administrator you created before the restore is gone, and the system asks for a new one. The ReGa
  database in the backup is ignored; its names can be imported separately (below).
- **Import the paired devices** (only on a system with nothing paired yet): *Import the paired devices and reboot*
  takes over the pairings and identities of BidCos-RF, HmIP-RF and the LAN gateways, plus the names, rooms and
  functions from the backup, and reboots.

**A non-default BidCos security key** comes along as it is; the BidCos devices keep working. The Backup page asks for
its passphrase only to check it, and never stores it. A wrong or skipped passphrase (*Skip - I do not know it*) does
not stop the restore or the import. **Find the passphrase while the old CCU is still at hand:** you need it to change
the key later, to move the devices to another system, or to restore onto a system with another key. Without it, the
only way out is a factory reset and re-pairing of every BidCos device.

**Another radio module.** BidCos-RF needs nothing: it runs with the imported address on whatever module is there.
The HmIP identity, however, is bound to the radio module of the system that made the backup. On another module,
hmipserver moves it across when it starts (the *adapter exchange*):

- From a system in local key mode this works offline; see
  [lokaler-schluesselmodus.md](lokaler-schluesselmodus.md) (in German).
- Otherwise it goes through eQ-3's key server. That needs an internet connection, and **the key server may refuse the
  exchange**, even for a module it already knows. After a refusal HmIP-RF stays stopped. The Interfaces page shows the
  state (pending, done, rejected) and offers the ways out: *Try again*, back to the previous module, or *Start fresh
  with this module…* (every HmIP device paired again).
- After the exchange every HmIP device is re-keyed for the new module. A battery device only follows when it wakes up:
  press a button on it, and allow hours rather than minutes.
- The system that made the backup must not keep running the network: one HmIP network, one running system.
- The system records every adapter exchange - which module took which network over, when, whether the key server took
  part, and how it went - in `/etc/config/occulite/hmip-exchanges.jsonl`, which is part of every backup. Nothing is
  sent anywhere; the Interfaces page shows the record under a refused exchange.

Before a restore or an import the Backup page also judges the backup's HmIP security counter; see
[known-issues.md](known-issues.md#hmip-devices-unreachable-after-a-reboot-the-security-counter).

### What changes on the first start

- **Names, rooms and functions** are read from the ReGa database. The CCU's built-in rooms and functions get their
  German WebUI names (*Badezimmer*, *Heizung*); objects still carrying a default name such as `<type> <address>` are
  skipped. Later, *Import names from a ReGa database* on the Backup page imports them from a `.regadom` or `.sbk`
  file.
- **Not taken over:** programs, system variables, alarms, favourites, diagrams. Automation moves to Node-RED
  (RedMatic), Home Assistant, ioBroker or whatever you already use.
- **Addons:** those in the [catalogue](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md)
  work. Addons that need the ReGa (CUxD, the XML-API, …) are disabled and listed as *disabled, incompatible*. Addons
  with binaries for another architecture are listed as *disabled, needs update*; the catalogue's *Install* /
  *Update* fetches the right build ([addons.md](addons.md#architecture-and-addon-binaries)). Nothing is uninstalled.
- **mediola's NEO Server** cannot run without the ReGa and is switched off.
- **The leftovers are removed once the names are imported:** `homematic.regadom` and its `.bak`, the WebUI's
  `measurement` and `userprofiles`, `etc/config/rega` and the NEO Server. The journal line `ccu leftovers removed`
  lists them. The radio identity, the keys, the interface configuration and the addons stay.

## openccu-lite → OpenCCU / CCU3

1. **Install OpenCCU:** Status page → *System update* → upstream's `OpenCCU-<version>-<PRODUCT>.zip` → *Reboot and
   install*. Pairings, keys and addons survive in `/usr/local`. For a CCU3-shaped system it is upstream's
   `OpenCCU-<version>-ccu3.tgz`; that route is untested, so keep the backup and the
   [reflash fallback](#the-reflash-fallback) in mind.
2. **Restore the `.sbk` taken before the switch**, in OpenCCU's WebUI. Only this brings back the ReGa database,
   with names, rooms, programs and system variables as they were on the day you switched. Changes made on
   openccu-lite since then do not come back: there is no export for that.

openccu-lite's names stay in `/usr/local/etc/occulite/meta.json`, ready for a later switch back to openccu-lite.

**Encrypted backups:** OpenCCU cannot read a `.sbk.age`. Use *Download unencrypted (for OpenCCU or a CCU3)* on the
Backup page, or decrypt it on a PC: `age -d -i key.txt -o backup.sbk backup.sbk.age` (`key.txt` holds the
`AGE-SECRET-KEY-1…` line from the emergency kit).

**With HSTS on** (System → Certificate): switch HSTS off **and then open the system once by its name in every
browser you use**, before installing OpenCCU. Uploading OpenCCU's package switches HSTS off by itself, and the
Status page then lists the names to open. A browser that missed this refuses the recovery's plain HTTP page and
OpenCCU's own certificate under that name for up to seven days. `http://<IP address>/` always works.

## The reflash fallback

If an update package is refused, flash the image from scratch and restore the `.sbk`. Everything above still applies;
only the flashing step is different.
