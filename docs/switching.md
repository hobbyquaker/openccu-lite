# Switching between OpenCCU (or a CCU3) and openccu-lite

*English — the German version is [switching.de.md](switching.de.md).*

**Take a backup (`.sbk`) before you switch, and keep it. It is the way back**, and a
[copy of the whole system](#a-copy-of-the-whole-system-first) is the quicker one. After its first start
openccu-lite removes the CCU's ReGa database and the WebUI's data from the system (see
[What changes on the first start](#what-changes-on-the-first-start)). Flashing OpenCCU back without the backup gives you
a working OpenCCU with your pairings and keys, but without your names, rooms, programs and system variables.

## OpenCCU / CCU3 → openccu-lite

In the OpenCCU or CCU3 WebUI: Settings → Control panel → CCU maintenance → Perform software update, upload the
package (below), confirm, let it reboot. Pairings, keys, the interface configuration and the addons stay in
`/usr/local`. On the first start the system takes over the names, rooms and functions from the ReGa database and asks
for an administrator password.

**This update over the existing system is the recommended way**, after a
[copy of the whole system](#a-copy-of-the-whole-system-first): a snapshot or clone of the VM, a copy of the SD card. A
new installation with an import of the old system's backup is for a new or replaced system.

### Which package for which system

`cat /VERSION` over SSH (`PRODUCT=…`) tells you what your system is:

| Your system | Package | What happens |
| --- | --- | --- |
| OpenCCU on an SD card or USB disk (`PRODUCT=rpi3`, `rpi4`) | `openccu-lite-<product>-<version>.zip` | one recovery pass, one reboot, about three minutes |
| The OpenCCU VM (`PRODUCT=ova`) | `openccu-lite-x86_64-ova-<version>.zip` | the same |
| A CCU3, or a card set up from a CCU3 image or CCU3 backup image (`PRODUCT=ccu3`) | `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` | two recovery passes and two reboots: the second grows the root partition to 2 GB. Plan for about 25 minutes after *Start update*, up to 30-40 minutes on a slower or larger card (see [below](#a-dark-update-on-a-raspberry-pi-3-or-charly)). |

The `.zip` is the wrong package for a CCU3-shaped system; take the `-ccu3.tgz`.

**A new installation** needs no update: write the `.img` from the release's `.zip` to an SD card (Raspberry Pi 3/4), or
import the `.ova` (Proxmox, VMware, VirtualBox). Then bring your old system's devices across with an
[import of its backup](#bringing-the-devices-into-a-new-installation).

### The space the update needs

The recovery unpacks the update on the userfs (`/usr/local`) before it writes anything. **You need at least 2.8 GB
free.** The WebUI shows it under *Perform software update* (*Available user space*), SSH with `df -h /usr/local`.
Old backups under `/usr/local/tmp` and large addon data are the usual culprits; remove them first.

### Check before switching

- **A backup**, taken in Settings → Control panel → Security → Create backup and copied off the system.
- **A copy of the whole system:** a snapshot or clone of the VM, a copy of the SD card (below).
- **2.8 GB free** on the userfs.
- **The right package** (the table above), its `.sha256` checked.
- **Access if something goes wrong:** the system's address written down (a failed update may come back on a new DHCP
  address), and the SD card or the VM's console within reach.
- **Reliable power** for the whole update: the CCU3's second pass writes partition tables.

### A copy of the whole system first

The backup brings back the ReGa database and `/usr/local`, but only onto a working OpenCCU. A copy of the whole system
is OpenCCU exactly as it was, ready to start again. Shut OpenCCU down from its WebUI for the copy, so that nothing is
written while it is taken. What changes on openccu-lite later (devices paired or removed, a key changed) is not in the
copy.

**A VM: a snapshot or a clone.** Proxmox VE, VMware, VirtualBox and Hyper-V (where it is called a checkpoint) take a
snapshot of a VM; Proxmox VE and VirtualBox also make a full clone. Proxmox VE takes a snapshot only where the VM's
disk is on a storage that supports it (a `qcow2` disk on directory or NFS storage, ZFS, LVM-thin, Ceph and others);
otherwise clone the VM. Then start the VM and update it. The way back is the rollback to the snapshot, or the clone.
Keep a clone switched off while the other VM runs: one radio module, one running system.

**A Raspberry Pi: a copy of the SD card** (or of the USB disk it boots from). Take the card out of the shut-down
system and read it into an image file on a PC, or copy it onto a second card of at least the same size; then put a
card back and update it. Tools that do it:

- Windows: [Win32 Disk Imager](https://sourceforge.net/projects/win32diskimager/), *Read* into an `.img` file.
- Linux: find the card with `lsblk`, then `sudo dd if=/dev/sdX of=openccu.img bs=4M status=progress`.
- macOS: find the card with `diskutil list`, `diskutil unmountDisk /dev/diskN`, then
  `sudo dd if=/dev/rdiskN of=openccu.img bs=4m`.
- [balenaEtcher](https://etcher.balena.io/) (Windows, macOS, Linux): *Clone drive* copies the card onto a second card;
  it writes no image file.

Raspberry Pi Imager only writes cards and cannot read one. The way back is the copy: the second card, or the image
written onto a card again (Win32 Disk Imager's *Write*, balenaEtcher, Raspberry Pi Imager or `dd`).

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

On the Backup page, *Restore or import a backup* checks the uploaded `.sbk`, says in the panel *This file* what it is
and what it holds, and offers the one way that fits it:

- **A backup of OpenCCU, RaspberryMatic or a CCU3 is imported, never restored** (*Import into this system*, then
  *Import and reboot*). Always taken: the paired devices of all three radios with the radio identity and the keys, the
  LAN gateways, and the names, rooms and functions from the backup's ReGa database. *Also take from the backup:* offers
  what the backup holds of the rest, each with a checkbox:
  - the addons with their settings (ticked; an addon that needs the ReGa, or whose programs are for another processor,
    comes disabled, and one installed here already stays as it is);
  - the HB-RF-ETH's address (ticked; the board serves one system, so the old one must be off);
  - the host name (ticked only while this system has no name of its own: two systems with one name confuse the
    router);
  - the syslog server (`LOGHOST`, ticked);
  - classic RPC as on the old system (never ticked; see
    [What changes on the first start](#what-changes-on-the-first-start)).

  *What stays behind on the old system* lists the rest: the ReGa's programs, system variables and scripts, the old
  WebUI's users, the network settings other than the host name, the firewall other than classic RPC, the web
  certificate, SSH keys and the root password, time zone, time servers and location, the log levels, crontab and
  monit, what an addon keeps outside its own directories, mediola's NEO Server, and everything else under
  `/usr/local`.
- **The import needs a system without paired devices**: it takes over that system's radio identity, and devices paired
  there would be orphaned. On a system with devices the page refuses it and points to the way there, *Factory reset*
  at the end of the same page, which deletes everything on the system (take a backup first if anything on it is worth
  keeping). The names alone can be taken without it, when the backup holds a ReGa database: *Import the names from
  this backup*.
- **A backup of openccu-lite is restored** (*Restore onto this system*, then *Restore and reboot*): everything under
  `/usr/local` is replaced, the paired devices and keys, the names, the addons with their settings, the network and
  every other setting, and the users and API tokens. The administrator created before the restore is gone.

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
  skipped. Later, a `.sbk` uploaded on the Backup page brings them: the import always takes them, and on a system with
  paired devices *Import the names from this backup* takes them alone.
- **Not taken over:** programs, system variables, alarms, favourites, diagrams. Automation moves to Node-RED
  (RedMatic), Home Assistant, ioBroker or whatever you already use; see
  [External clients after the switch](#external-clients-after-the-switch).
- **Addons:** those in the [catalogue](https://github.com/openccu-lite/occulited/blob/master/docs/catalog-format.md)
  work. Addons that need the ReGa (CUxD, the XML-API, …) are disabled and listed as *disabled, incompatible*. Addons
  with binaries for another architecture are listed as *disabled, needs update*; the catalogue's *Install* /
  *Update* fetches the right build ([addons.md](addons.md#architecture-and-addon-binaries)). Nothing is uninstalled.
- **Scripts in `/usr/local/etc/config/rc.d/`** come along as addons and are started, your own scripts too. Ones
  written for the CCU3 mostly fail here; the Addons page then shows *Came from the CCU* with the script's last log
  line and offers *Remove the rc.d entry*.
- **mediola's NEO Server** cannot run without the ReGa and is switched off.
- **Classic RPC is switched on when OpenCCU's firewall let clients reach the XMLRPC ports** (`full` or `restricted`
  in `firewall.conf`), so that the programs that talk to the CCU on 2001, 2010, 9292 or 2000 keep working: the plain
  and the TLS ports, **without a login**. Its firewall rules keep their sources: the local networks for `full` (every
  address when OpenCCU allowed external access), one rule for each allowed address or network for `restricted`. The
  Firewall page's notice on the conversion says so, and the Status page warns as long as classic RPC runs without a
  login. Switch it off, or set a user name and password, on System → Remote access. If OpenCCU asked for a login on
  these ports (`authEnabled`, its WebUI accounts), classic RPC stays off, as those accounts cannot come along; the
  Firewall page's notice says why.
- **An import of an OpenCCU or CCU3 backup** offers classic RPC as one of its options, with the sources the old
  firewall allowed; it is never ticked in advance and switches classic RPC on, plain and TLS and without a login, only
  when ticked. It cannot be chosen when the old system asked for a login on these ports, or when classic RPC is on here
  already. Such a backup is imported, never restored; a restored backup of openccu-lite brings its own firewall rules.
- **The leftovers are removed once the names are imported:** `homematic.regadom` and its `.bak`, the WebUI's
  `measurement` and `userprofiles`, `etc/config/rega` and the NEO Server. The journal line `ccu leftovers removed`
  lists them. The radio identity, the keys, the interface configuration and the addons stay.
- **The diagram data is removed once, at the first start:** the USB stick's `measurement/` and
  `/usr/local/etc/config/measurement`. openccu-lite has no diagrams (no page to set them up or show them). The journal
  line `diagram data: … removed` names each path with its size; other files on the stick stay.
- **Other CCU remnants are removed once, at the first start:** the configuration directories of addons that are no
  longer installed (`/usr/local/etc/config/addons/<id>`, e.g. CloudMatic's `mh`), the ReGa's crash dump
  `homematic.regadom.err` and an empty `eQ-3-Backup`. Each is logged with its path and size (`ccu remnants: removed`).
- **The first start's log is kept:** the journal of the first boot after the switch - the import, the addon checks,
  the first starts of the radios - is copied once to `/usr/local/var/log/first-boot-journal.txt.gz` (text, gzipped, at
  most its first 8 MiB), 30 minutes into that boot or when the system is shut down before then. It is in no backup and
  stays until you delete it. Where the journal is kept in RAM (the default on a Raspberry Pi or a CCU3), everything
  else is lost at a reboot; the Status page says so, and the Log page's journal settings keep it on the userfs, a USB
  stick or a network share.

Everything removed on the first start is in the CCU backup taken before the switch: **that backup is the way back.**

### External clients after the switch

Programs elsewhere on the network that talked to the CCU keep its devices, but lose everything of the ReGa.

- **Classic RPC** (the CCU's ports 2001, 2010, 9292 and 2000, plain and TLS) is on after the switch, without a login,
  when OpenCCU's firewall opened the XMLRPC ports ([above](#what-changes-on-the-first-start)); otherwise it is off,
  and a client set up for those ports gets no answer until classic RPC is switched on on System → Remote access. The
  interface processes call such a client back at the address it registers, so it must be reachable from the system.
- **Node-RED with [node-red-contrib-ccu](https://github.com/rdmtc/node-red-contrib-ccu#openccu-lite):** up to 4.6 it
  used classic RPC and an API token with `meta:read` for the names. From 4.7 it talks to the interface processes
  through the system's lite-rpc on the web port and moves an existing connection there at its first start. lite-rpc
  needs more scopes: `rpc:read` for events and reads, `rpc:operate` (which includes it) for `setValue`. Use **4.10.1
  or later**: a token without `rpc:read` then keeps the direct connection over classic RPC and the log says what
  lite-rpc would need, and with the connection type *openccu-lite* the nodes name the missing scopes. In 4.7 to 4.10.0
  such a token lost the events and commands without a word. The simplest way is *Pair with the system* in the
  connection node: an administrator compares its code on the Status page and approves it, and the token and the
  certificate's fingerprint are filled in. API tokens made by hand are on System → Remote access. RedMatic on the
  system needs no token (9.15.1 or later). The nodes `ccu-sysvar`, `ccu-program`, `ccu-script` and `ccu-poll` answer
  every message with an error.
- **Home Assistant with [Homematic(IP) Local](https://github.com/SukramJ/homematicip_local)** (`homematicip_local`):
  its direct connection needs the CCU's JSON-RPC (the ReGa) for its login, the names and the rooms, which openccu-lite
  does not have. It connects through [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom), as an addon on
  the system (in the addon catalogue) or running elsewhere, with the integration's backend *OpenCCU-Loom daemon*,
  marked Beta in version 2.12.4.
  An existing entry of the integration (seen with 2.12.3) that is switched to this backend keeps the old direct
  connection's `username` and `password`, and its start then aborts with
  `box_token is the only credential behind the box`. The way out: stop Home Assistant Core, make a copy of
  `.storage/core.config_entries`, delete the two keys `username` and `password` from the integration's entry, and
  start Home Assistant again. This is the integration's behaviour; newer versions may handle it differently.
- **ioBroker:** [ioBroker.hm-rpc](https://github.com/ioBroker/ioBroker.hm-rpc) connects to the interface processes
  as to a CCU, through classic RPC (above).
- **Whatever needs the ReGa does not work:** system variables, programs, HM-Script, the WebUI's JSON-RPC API
  (`/api/homematic.cgi`), the ReGa's ports 1999 and 8181, and with them
  [ioBroker.hm-rega](https://github.com/ioBroker/ioBroker.hm-rega), CUxD and the XML-API addon. Names, rooms and
  functions are in the system's metadata API; [porting-from-rega.md](porting-from-rega.md) maps the ReGa's calls to
  what replaces them.

## openccu-lite → OpenCCU / CCU3

1. **Install OpenCCU:** Status page → *System update* → upstream's `OpenCCU-<version>-<PRODUCT>.zip` → *Reboot and
   install*. Pairings, keys and addons survive in `/usr/local`. For a CCU3-shaped system it is upstream's
   `OpenCCU-<version>-ccu3.tgz`; that route is untested, so keep the backup and the
   [reflash fallback](#the-reflash-fallback) in mind.
2. **Restore the `.sbk` taken before the switch**, in OpenCCU's WebUI. Only this brings back the ReGa database,
   with names, rooms, programs and system variables as they were on the day you switched. Changes made on
   openccu-lite since then do not come back: there is no export for that.

**With a copy of the whole system** (above) both steps are one: roll back the VM's snapshot, start its clone, or put
the copied card back in. That is OpenCCU as it was on the day of the switch; changes made on openccu-lite since then do
not come back either.

openccu-lite's names stay in `/usr/local/etc/occulite/meta.json`, ready for a later switch back to openccu-lite.

**Encrypted backups:** OpenCCU cannot read a `.sbk.age`. Use *Download unencrypted (for OpenCCU or a CCU3)* on the
Backup page, or decrypt it on a PC: `age -d -i key.txt -o backup.sbk backup.sbk.age` (`key.txt` holds the
`AGE-SECRET-KEY-1…` line from the emergency kit).

**With HSTS on** (System → Certificate): switch HSTS off **and then open the system once by its name in every
browser you use**, before installing OpenCCU. Uploading OpenCCU's package switches HSTS off by itself, and the
Status page then lists the names to open. A browser that missed this refuses the recovery's plain HTTP page and
OpenCCU's own certificate under that name for up to seven days. `http://<IP address>/` always works.

## The reflash fallback

If an update package is refused, flash the image from scratch: openccu-lite's, then
[import the old system's backup](#bringing-the-devices-into-a-new-installation); or OpenCCU's, then restore the `.sbk`
in its WebUI. Everything above still applies; only the flashing step is different.
