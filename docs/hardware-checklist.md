# The hardware checklist

The part CI cannot do, and a release gate: *"every radio interface
OpenCCU supports works here"* is a promise that is either tested or false, and **a release does not
go out with an untested interface class**. An interface class nobody could test is written
down as untested rather than claimed.

This is that checklist. It is run by a human, on hardware, on the image that is about to be
released — not on a rebuild of it. Record the image's full file name and the `/VERSION` of the system
next to each result; "it worked last time" is not a result.

Everything CI already covers is deliberately absent: the API suites, the addon install round trip,
the conformance corpus, the QEMU boot test of the x86 image (`scripts/lite-qemu-test.sh`). What is
here needs a radio, a board, or a person watching a light come on.

## 0. Before anything

- [ ] The image's `/VERSION` says upstream's `PRODUCT`/`PLATFORM` plus `VARIANT=lite` and `LITE=<n>`. Read it out of the image, not out of a system: `debugfs -R 'cat /VERSION' rootfs.ext4`.
- [ ] **The recovery system's own `/VERSION` says the same platform** —
      `build-<product>/build/recovery-system-*/output/target/VERSION`. Get it wrong
      and the system installs once and can never be updated again, the way back to OpenCCU included.
- [ ] A `.sbk` of the system you are about to flash, kept somewhere that is not the system (the
      default backup target is the system itself).

## 1. Per board, once per release

| board class | product | what to check |
| --- | --- | --- |
| CCU3 / CM3 / Raspberry Pi 3 | `aarch64-rpi3` | boots; `/VERSION` says `rpi3`; the in-place `-ccu3.tgz` installs from the previous release's WebUI |
| CM4 / Raspberry Pi 4 | `aarch64-rpi4` | boots; `/VERSION` says `rpi4`; the SD image comes up on a fresh card; the in-place update on top of itself (the staged zip) comes back with the userfs and the addons kept and the radio module detected again |
| CM5 / Raspberry Pi 5 | `aarch64-rpi5` | boots; `/VERSION` says `rpi5`; the SD image comes up on a fresh card; the Pi 5 specifics — RF module on the RP1 UART, watchdog, LEDs, `occu-interface-clock` |
| VM / appliance | `x86_64-ova` | covered by the QEMU test in CI, but boot the `.ova` once on the hypervisor people actually use |
| Proxmox LXC, unprivileged | `lxc-lite_amd64` (`lxc-lite_arm64` on an aarch64 host) | the [install-lxc.md](install-lxc.md) gate: `pct create` from the template with `--unprivileged 1 --features nesting=1` and `mp0` on `/usr/local` boots to occulited on its address; `systemctl --failed` empty; `/VERSION` says `lxc`; the Network page says *managed by the host*; an addon installs; a LAN gateway or a passed-through RFUSB is reachable; a template swap keeps `/usr/local` |

- [ ] The end-of-boot console hint is there and names a reachable address.
- [ ] The boot splash's progress messages appear.
- [ ] `systemctl is-system-running` says `running`, `systemctl --failed` is empty.
- [ ] The LEDs do what the Radio page says they do, and the LED switch turns them off.
- [ ] Pull the power while it is idle. It comes back, and the Status page says the shutdown was
      unclean. Then reboot it cleanly and confirm the notice is gone.

## 2. Per radio interface class — the actual list

One row per class, and a release names the ones that were run. Add the device you paired.

| class | hardware | tested? | check |
| --- | --- | --- | --- |
| built-in RF module | RPI-RF-MOD, HM-MOD-RPI-PCB | | detected on the Radio page with its serial and firmware; pair a BidCos device and a HmIP device; duty cycle is live and plausible |
| USB stick | HmIP-RFUSB | | the same, on a system with no built-in module |
| LAN gateway, RF | HM-LGW-O-TW-W-EU | | added on the Radio page with its key; `rfd.conf` stays `600 root:root` and the key never appears in an API answer; a device paired through it responds |
| LAN gateway, wired | HMIP-DRAP and the wired bus | | `hs485d` sees the bus; a wired actuator switches |
| HB-RF-USB / HB-RF-ETH | | | detected; the coprocessor firmware update path runs (the bootloader is handed over only before a firmware update) |
| coprocessor flash from the UI | HmIP-RFUSB, RPI-RF-MOD | | the Interfaces page's *Radio firmware* section: the running version, the shipped 4.4.18 and an uploaded file listed; a flash to another version stops hmipserver/rfd/multimacd, flashes, re-detects, starts them; the page shows the new version without a reboot and `GET /radio` agrees; a truncated `.eq3` fails with the daemons back up; occulited killed mid-flash leaves the daemons up and the attempt failed |
| dual-copro / HmIP-HAP | | | as far as the hardware at hand allows; otherwise **written down as untested** |

## 3. The things only a device can prove

- [ ] Pair a BidCos-RF device from the frontend, name it, put it in a room, and see the name and
      the room arrive in a consumer (MQTT or Node-RED). The chain is
      store → metadata API → consumer, and it is what this project exists for.
- [ ] Pair a HmIP device. Same.
- [ ] Create a **direct link** between two devices and confirm it survives a reboot.
- [ ] Create a **heating group** and confirm it survives a reboot.
- [ ] Disable `hs485d` on the Services page, reboot, confirm it stays down, re-enable it.
- [ ] Change the network settings and **let the revert timer fire** without confirming: the system
      comes back on the old address.
- [ ] Restore the `.sbk` from step 0 and confirm pairings, keys and addons are all back.

## 4. The switch, both ways

- [ ] OpenCCU → openccu-lite through the *OpenCCU* WebUI's firmware update, in place, on a system
      with real pairings. Names, rooms and functions arrive; umlauts are right.
- [ ] openccu-lite → OpenCCU through the lite Status page with upstream's own `.zip`. ReGa, the
      addons and the regadom come back where they were.
- [ ] Then update the lite system **again**, from itself. This is the half that proves the recovery system matters: the only
      way to prove the recovery on the installed image is the fixed one.

## 5. What to write down

For each release: the image file names and their checksums, which board classes were booted, which
interface classes were run and which were not, and every line above that was skipped and why. That
list is the release note's "tested on" section. An interface class with no hardware to test on is
listed as untested — **not** omitted.
