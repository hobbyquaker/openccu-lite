# openccu-lite in a Proxmox LXC container

The products `lxc-lite_amd64` and `lxc-lite_arm64` are **CT templates** for Proxmox VE:
`openccu-lite-lxc-amd64-<version>.tar.xz` and `openccu-lite-lxc-arm64-<version>.tar.xz`, upstream's
`rootfs.tar` with the lite delta, compressed. Not a disk image, not an update package. This page is
the recipe for one, the checks that make it the release gate of the hardware checklist, and what a
container cannot do.

> **Status 2026-09-27: the first template of the 3.89.11 base is built** -
> `openccu-lite-lxc-amd64-1.0.0-dev.29.tar.xz` (143 MB, 437 MB unpacked). Built clean with the
> release checks (the hardening guard, the SBOM, the factory-reset marker in the tarball), and booted
> once in an unprivileged container on the build host: `running`, no failed unit, occulited answering
> through lighttpd. On Proxmox it is being tested now, with an HmIP-RFUSB (below). The checks of
> 2026-09-09 further down were run on an earlier template (3.89.8 base); the ones marked *to verify*
> have still not been run. The gate is **not passed** until the list below is done on this template.

## What is different from upstream's `install-proxmox.sh`

OpenCCU's own script creates a **privileged** container with `lxc.apparmor.profile: unconfined`,
an unrestricted seccomp profile, no capability dropped, `/dev` and `/lib/modules` of the host
bind-mounted and every character device allowed — so that the kernel modules of a GPIO radio
module and udev inside the container work. openccu-lite goes the other way, on purpose:

- **unprivileged** (`--unprivileged 1`): root inside is uid 100000 on the host; a broken addon
  cannot reach the hypervisor;
- **`--features nesting=1`**: systemd is PID 1 inside, and its sandboxing directives
  (`ProtectSystem=`, `PrivateTmp=`, the confined addons) need their own mount namespaces;
- **no kernel module, no raw device**: there is no built-in RF module in this product. Radio is a
  **LAN gateway** (HmIP-HAP, HM-LGW-O-TW-W-EU, HB-RF-ETH) or an **HmIP-RFUSB passed through** by
  Proxmox (`--dev0`, below); a Pi with a GPIO module is `aarch64-rpi4`'s job, not a container's;
- **no watchdog, no time daemon, no udev, no hardware clock**: the host has them
  (`board/lxc-lite/post-build.sh` takes the units out; `docs/systemd-scope.md` in the fork).

## Create the container

On the Proxmox host, as root. Put the template where Proxmox looks for templates — any storage
with content type `vztmpl`; on a default install that is `local`:

```sh
cp openccu-lite-lxc-amd64-<version>.tar.xz /var/lib/vz/template/cache/
pvesm list local --content vztmpl | grep openccu-lite
```

(The web UI does the same under *local → CT Templates → Upload*.) Then create the container.
Substitute the VMID, the storage names (`local-zfs` on a ZFS install, `local-lvm` on LVM) and the
bridge:

```sh
pct create <VMID> local:vztmpl/openccu-lite-lxc-amd64-<version>.tar.xz \
  --hostname openccu-lite \
  --ostype unmanaged \
  --arch amd64 \
  --unprivileged 1 \
  --features nesting=1 \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --rootfs local-zfs:2 \
  --mp0 local-zfs:4,mp=/usr/local,backup=1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --onboot 1
pct start <VMID>
```

Line by line:

- **`--ostype unmanaged`**: Proxmox has no setup script for this rootfs and must not try to write
  a Debian-style network configuration into it. The container brings its own network start
  (`occu-network.service` → `eQ3StartNetwork`, exactly as on every other product).
- **`--rootfs local-zfs:2`**: 2 GB is plenty; the template unpacks to well under 1 GB and the
  rootfs holds nothing that grows. **`--mp0 …,mp=/usr/local`**: *this* is the system — pairings,
  keys, the metadata store, addons, backups. It is a separate volume so that a template swap
  (below) leaves it alone; `backup=1` puts it into `vzdump` backups. 4 GB is a start; RedMatic
  and a few addons want more (`pct resize <VMID> mp0 +8G` later, online).
- **`--net0 … ip=dhcp`**: the container runs its own DHCP client (busybox `udhcpc`, as upstream's
  LXC product does). Give it a fixed address as a **DHCP reservation on the router**. A static
  `ip=…/24,gw=…` on the pct side is applied by LXC to the veth before init and shows up on the
  Network page, but the container's own DHCP client still runs in `MODE=DHCP` — *to verify* what
  `dhcp.script` then does to the address; until then, DHCP.
- `--arch arm64` and the `lxc-arm64` template on an aarch64 host (Proxmox on ARM, or a Pi running
  LXC with `pct`-less tooling — the template is a plain rootfs tar and works with `lxc-create -t
  local` too).

The console: `pct enter <VMID>` gives a root shell (no getty is needed). The web server waits for
the container's first address: the certificate it makes at the first start names that address, so
until DHCP has answered lighttpd restarts every few seconds and the page does not load. The address:
`pct exec <VMID> -- ip -4 -brief addr show eth0`. Then `http://<address>/` and the welcome page
asks for the administrator password.

### HmIP-RFUSB through to the container

The stick is **not a serial port**. Without eQ-3's driver the host lists it in `lsusb` as
`1b1f:c020 eQ-3 Entwicklung GmbH HmIP-RFUSB` and makes no `/dev/ttyUSB*` and no
`/dev/serial/by-id/` link for it. Its driver is piVCCU's `hb_rf_usb_2` on top of
`generic_raw_uart` (the same modules the VM and the Pi images carry), which turns it into
`/dev/raw-uart` with `/sys/class/raw-uart/raw-uart/device_type` =
`eQ-3 HmIP-RFUSB@usb-<port>`. A container runs the host's kernel and loads no modules, so **the
Proxmox host needs them**: the `pivccu-modules-dkms` package, as upstream's
`scripts/install-proxmox.sh` installs it. On the host, as root:

```sh
apt install -y proxmox-default-headers build-essential gpg   # headers for the running kernel (older PVE: pve-headers-$(uname -r))
wget -qO - https://apt.pivccu.de/piVCCU/public.key \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/pivccu-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/pivccu-archive-keyring.gpg] https://apt.pivccu.de/piVCCU stable main" \
  > /etc/apt/sources.list.d/pivccu.list
apt update && apt install -y pivccu-modules-dkms
```

Plug the stick in (or out and in again) and check:

```sh
lsusb | grep 1b1f:c020
lsmod | grep -E 'generic_raw_uart|hb_rf_usb_2'
ls -l /dev/raw-uart
cat /sys/class/raw-uart/raw-uart/device_type      # eQ-3 HmIP-RFUSB@usb-...
```

Then pass the node in (the `devN` option of current Proxmox VE; the ids are the container's, occulited's radio step gives the
node its group itself) and start the container again:

```sh
pct set <VMID> --dev0 /dev/raw-uart,mode=0660
pct reboot <VMID>          # a stopped container: pct start <VMID>
```

What the container does with it: `occulited radio run` finds the node through
`/sys/class/raw-uart` (the host's sysfs, read-only inside), probes it with `detect_radio_module`,
and skips the module reset, which is a sysfs write. **HmIP works directly on the node; BidCos-RF on
the stick does not**: sharing the stick between BidCos-RF and HmIP needs multimacd, and multimacd
has the host's `eq3_char_loop` create `/dev/mmd_bidcos` and `/dev/mmd_hmip` while it runs - they
appear in the host's `/dev`, never in the container's, and an unprivileged container may not create
device nodes. So, once the administrator exists, on the **Interfaces** page set BidCos-RF to
*No local radio (LAN gateways only)* and HmIP to the stick *directly*; the radio stack restarts and
hmipserver opens `/dev/raw-uart` itself. BidCos-RF devices need a LAN gateway (HM-LGW-O-TW-W-EU,
an HB-RF-ETH with its own module) or the VM product.

The node is created in the container when it starts: the stick must be plugged in before
`pct start`, or the start fails on the missing `/dev/raw-uart`. There is no udev inside, so a stick
plugged in later is not seen - restart the container.

## What the system looks like from inside

`/VERSION` says `PRODUCT=lxc_amd64`, `PLATFORM=lxc`, `VARIANT=lite`, `LITE=<version>` (the
same `PLATFORM` upstream's template writes, which is what every `HM_HOST =~ oci|lxc` test in the
init scripts keys on). `systemd-detect-virt` says `lxc`, and occulited's `GET /api/system/v1/status`
carries `container: "lxc"`. From that:

- the **Network page is a display** ("managed by the host"): address, gateway, DNS and hostname
  are what the container was given; nothing writes `/etc/config/netconfig`
  (`GET /network` → `host_managed: true`, the writes answer `501 host-managed`);
- the **Time section sets the zone only**: the clock is the host's, `settimeofday` is EPERM in an
  unprivileged container, there is no chrony;
- the **System update section** says the template is swapped on the host and `/usr/local`
  survives; the daily release check still runs and names the newer template
  (`openccu-lite-lxc-amd64-<version>.tar.xz`), nothing is downloaded or installed from inside;
- the **journal is persistent** by default, as on the VM (the disk is the host's, not an SD card);
- the rootfs is **writable**. The lite design of a read-only root with `occu-etc-writable`'s bind
  mounts is kept in the units, but a Proxmox rootfs is a writable subvolume and the units that
  assume read-only skip themselves (`ConditionPathIsReadWrite=!/etc`). The recorded reason for not
  forcing it: Proxmox's own `ro=1` on the rootfs is a host-side option, and whether systemd's
  `/etc/machine-id` handling and the addon generator survive it in an unprivileged CT is
  *to verify* — the task's own text allows a writable root with a reason, and this is it.

## The template swap (that is the update)

There is no recovery system, no partition, no `.recoveryMode`: a new release is a new template.
`/usr/local` is the mount point, so the way is **a new container from the new template with the
old container's `mp0` moved over**:

```sh
pct stop <OLD>
pct create <NEW> local:vztmpl/openccu-lite-lxc-amd64-<newversion>.tar.xz \
  --hostname openccu-lite --ostype unmanaged --arch amd64 --unprivileged 1 --features nesting=1 \
  --cores 2 --memory 2048 --swap 512 --rootfs local-zfs:2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,hwaddr=<the old container's MAC> --onboot 1
pct move-volume <OLD> mp0 --target-vmid <NEW> --target-volume mp0
pct config <NEW> | grep ^mp0        # must say mp=/usr/local; if not: pct set <NEW> --mp0 <volid>,mp=/usr/local
pct start <NEW>
# check it (below), then
pct destroy <OLD>
```

The MAC keeps the DHCP reservation. `pct restore <OLD> <template> --force --mp0 <existing
volume>,mp=/usr/local` — restoring the same VMID in place and naming the existing volume so it is
kept — is the shorter form *to verify*; `pct restore` is written for backups and the keep-volume
behaviour on a plain rootfs archive has not been tried. What does **not** work for an unprivileged
container is upstream's in-place path (`pct mount`, wipe, `tar -x`, `pct unmount`): the rootfs is
id-shifted on the host and a plain `tar -x` leaves root-owned files the container sees as nobody's.

Same as every other product: a **`.sbk` backup before the swap** (Backup page), kept off the system.

## The checks — the gate

Run on the container that is to be released, and write the results into
[hardware-checklist.md](hardware-checklist.md):

- [x] `pct enter <VMID>`: `systemctl is-system-running` says `running`, `systemctl --failed` is
      empty (the masked udev units and the skipped conditions do not count as failed) — 2026-09-09, CT 900, after the boot-order fix;
- [x] `curl -s http://127.0.0.1/api/system/v1/health` answers `ok: true` with `release` =
      the template's version, and the same from a browser on the LAN — 2026-09-09 (curl over the LAN; the browser pass is next);
- [x] `cat /VERSION` says `PLATFORM=lxc`, `/var/hm_mode` says `HM_HOST='lxc'` — 2026-09-09;
- [ ] the Network page says *managed by the host*, shows the container's address, and has no
      Apply button; the Time section has no NTP field;
- [ ] the Status page's update section shows the container notice and no upload form;
- [x] the **firewall**: `iptables -S` inside the container works — **verified 2026-09-09**: 28 rules,
      `INPUT DROP` first, in an unprivileged CT with `nesting=1`; the Firewall page stays as it is;
- [x] an addon installs from the catalogue (mosquitto is the small one) and its page opens;
      a confined addon starts — that is the `nesting=1` test — **2026-09-09**: mosquitto
      installs, runs as `addon-mosquitto` with the system's certificate on 1883 and 8883, and
      the Firewall section opens each port on its own (8883 open, 1883 closed, kept across a
      reboot);
- [ ] a LAN gateway is added on the Radio page and a device paired through it, or the RFUSB
      is passed through and detected — **not yet run (2026-09-09)**;
- [x] the template swap above: the new container comes up with the old names, addons and
      the administrator password, i.e. `/usr/local` survived — **verified 2026-09-09**: CT 900 → 901
      with `pct move-volume`, the MAC kept, same DHCP address, the password logs in, mosquitto
      still installed, the metadata store where it was.

## Sizing and limits

- **Memory**: hmipserver (the JVM) is the big one; 2 GB is what upstream gives its CT and is
  fine for a LAN-gateway system with a few addons. RedMatic wants more.
- **CPU**: two cores. Nothing here is CPU-bound except a backup.
- **Nothing listens beyond the loopback except lighttpd** — the container's firewall is
  in addition to Proxmox's own (`firewall=1` on `net0` if it is wanted).
