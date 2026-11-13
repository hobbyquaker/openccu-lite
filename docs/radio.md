# Radio modules and multimacd: every option

This page lists every setting that decides which radio module the interface processes use, and
what each combination starts. It is the one complete list; the other documents link here.

The interface processes:

- **rfd** - BidCos-RF (classic Homematic radio), on a local module, an HM-CFG-USB-2 and/or BidCos
  LAN gateways.
- **hmipserver** - a Java process that runs one of two servers:
  - **HMIPServer.jar** - HmIP-RF (Homematic IP radio, HmIP-HAPs and DRAPs, HmIP wired) *and* the
    virtual devices (heating groups and the like, `VirtualDevices`, port 39292);
  - **HMServer.jar** - the virtual devices alone.
- **multimacd** - the multiplexer: it opens one radio module on its UART and offers it to rfd
  (`/dev/mmd_bidcos`) and hmipserver (`/dev/mmd_hmip`) at the same time.
- **hs485d** - BidCos-Wired (classic Homematic wired), through an HMW-LGW wired LAN gateway.
- **hmlangw** - only in LAN-gateway mode (below): the system itself acts as a BidCos LAN gateway
  for another central unit.

The system detects the modules at every boot and on every hotplug, then makes a plan from the
hardware and the settings below; *System → Interfaces → Connections* shows the plan (what runs,
on which module, and why) and changes the settings.

## The settings

| Setting | Where | Values | Default |
| --- | --- | --- | --- |
| **HmIP-RF module** | *Interfaces → Connections → HmIP-RF*; stored as `occulite.hmip.adapter=` in `/etc/config/crRFD/hmip_user.conf` | **Automatic** (no line): the module OpenCCU would pick (an RPI-RF-MOD before an HM-MOD-RPI-PCB), and from then on the module the HmIP network was last on; **a module** (its serial or SGTIN): exactly that one; **None** (`none`): no HmIP at all | Automatic |
| **HmIP path** | the same dropdown: one entry per module and path; stored as `occulite.hmip.path=` in the same file | **automatic** (no line); **direct** - hmipserver opens the module's UART itself; **multimacd** - through `/dev/mmd_hmip` | automatic |
| **BidCos-RF module** | *Interfaces → Connections → BidCos-RF*; stored as the first line `# occulite.bidcos.module=` in `/etc/config/rfd.conf` | **Automatic** (no line): an HM-CFG-USB-2 if one is plugged in, else the module OpenCCU would pick (an HM-MOD-RPI-PCB before an RPI-RF-MOD); **a module** (its serial); **None** (`none`): rfd without a local radio - *Off (HmIP only)* without a LAN gateway, *No local radio (LAN gateway only)* with one | Automatic |
| **BidCos LAN gateways** | *Interfaces → LAN devices*; sections in `/etc/config/rfd.conf` | any number of HM-LGW-O-TW-W-EU / HM-CFG-LAN | none |
| **HB-RF-ETH** | *Interfaces → LAN devices*; its address | one network radio board; its module then shows up like a module on the header | none |
| **BidCos-Wired** | *Interfaces → LAN devices*; a section in `/etc/config/hs485d.conf` | an HMW-LGW-O-DR-GS-EU | none |
| **LAN-gateway mode** | the file `/usr/local/HMLGW` (no page) | present: the system is a BidCos LAN gateway for another central unit | absent |

A setting is written into the daemons' own files, never flashes firmware, and stays when its module
is missing: no process is ever moved to another module without the user's choice.

## What runs

**HMServer.jar runs only when HmIP is set to None.** With Automatic or a chosen module hmipserver
always runs HMIPServer.jar - with its module, or, when none is found or the chosen one is missing,
without it. HMIPServer.jar cannot start without its module (it waits for it and opens neither
HmIP-RF nor the virtual devices), so the system then does not start hmipserver at all and says so:
*Status* (the warning "HmIP-RF and the virtual devices are down") and *Interfaces → Connections*
name the way out - connect the module, or set HmIP-RF to None. Nothing switches to HMServer.jar by
itself. (OpenCCU runs HMServer.jar whenever it finds no HmIP module.)

| HmIP-RF | BidCos-RF | Hardware | multimacd | rfd | hmipserver | Interfaces offered |
| --- | --- | --- | --- | --- | --- | --- |
| Automatic / a module | Automatic / the same module | one module that carries both (RPI-RF-MOD, HmIP-RFUSB, HM-MOD-RPI-PCB) on the header, an HB-RF-USB(-2) or HB-RF-ETH, or a dual-firmware HmIP-RFUSB | on the module | through `/dev/mmd_bidcos` (+ LAN gateways) | HMIPServer.jar through `/dev/mmd_hmip` | BidCos-RF, HmIP-RF, VirtualDevices |
| Automatic / a module | **None** | the same | not for an RPI-RF-MOD or HmIP-RFUSB (hmipserver opens it directly); **yes** for an HM-MOD-RPI-PCB (rule 1) | not without a LAN gateway; on the LAN gateways alone with one | HMIPServer.jar on the module | HmIP-RF, VirtualDevices (+ BidCos-RF with a gateway) |
| **None** | Automatic / a module | a module that carries both | on the module (rfd reaches a module on a UART only through it) | through `/dev/mmd_bidcos` (+ LAN gateways) | **HMServer.jar** | BidCos-RF, VirtualDevices |
| **None** | Automatic | an HM-CFG-USB-2 | no | on the HM-CFG-USB-2 (+ LAN gateways) | **HMServer.jar** | BidCos-RF, VirtualDevices |
| **None** | **None** | any | no | on the LAN gateways alone, or off without one | **HMServer.jar** | VirtualDevices (+ BidCos-RF with a gateway) |
| Automatic / a module | Automatic | an HM-CFG-USB-2 beside a module (or an HmIP-RFUSB) | no | on the HM-CFG-USB-2 (+ LAN gateways) | HMIPServer.jar directly on the module (an HM-MOD-RPI-PCB: through multimacd, rule 1) | BidCos-RF, HmIP-RF, VirtualDevices |
| Automatic / a module | Automatic / a module | two modules (e.g. an RPI-RF-MOD on the header and an HB-RF-USB with an HM-MOD-RPI-PCB) | on the BidCos-RF module | through `/dev/mmd_bidcos` | HMIPServer.jar directly on the other module | BidCos-RF, HmIP-RF, VirtualDevices |
| Automatic / a module | any | an HmIP-only module (HmIP-RFUSB-TK, an HmIP-RFUSB on the HmIP-only firmware, a module without a BidCos address) | only where BidCos-RF has a module of its own on a UART | on that module, the HM-CFG-USB-2 or the gateways; off without | HMIPServer.jar directly on the HmIP-only module (rule 2) | HmIP-RF, VirtualDevices (+ BidCos-RF) |
| Automatic | any | **no HmIP module found** | only where BidCos-RF has a module on a UART | as above | **not started** (HMIPServer.jar needs its module; warning) | BidCos-RF where rfd runs |
| a module that is **missing** | any | - | as above | as above | **not started** (warning naming the module) | BidCos-RF where rfd runs |

**The HmIP path** changes only how hmipserver reaches its module: *automatic* takes
multimacd when BidCos-RF shares the module and the module directly otherwise; *direct* and
*multimacd* force one, where the hardware allows it (the dropdown offers only those). A choice that
cannot be served is refused before anything changes: *direct* while BidCos-RF uses the same module
through multimacd, *multimacd* while multimacd already serves another module for BidCos-RF. With HmIP
set to None there is no path to choose.

**hs485d** runs exactly when an HMW-LGW is configured, whatever the radio settings; BidCos-Wired is
then in the interface list.

**LAN-gateway mode** (`/usr/local/HMLGW`) ignores every setting above: multimacd on the BidCos module
and hmlangw run, rfd, hmipserver and hs485d do not, and no interface is offered on this system.

## The fixed rules

1. **An HM-MOD-RPI-PCB carries HmIP only through multimacd**: opened directly, hmipserver
   hangs after every reset of the module. multimacd serves one module, so HmIP on a PCB and BidCos-RF
   on another module that needs multimacd cannot run together; the page refuses that choice.
2. **An HmIP-only module is opened directly**: rfd cannot use it, and multimacd refuses its
   coprocessor. The radio firmware section flashes the dual firmware onto an HmIP-RFUSB.
3. **HMServer.jar only with HmIP set to None** - never as a fallback for a missing module.
4. **No module is replaced unasked:** a chosen module that is missing stays chosen, and on
   Automatic HmIP-RF stays on the module that holds the HmIP network; moving it to another module is
   an adapter exchange and needs the user's confirmation.
5. Only one local module per process; LAN gateways, HmIP-HAPs and DRAPs are not chosen here and can be
   several.

Switching HmIP to None takes HmIP-RF away: paired HmIP devices are out of reach until HmIP is set back,
but their pairings, keys and the HmIP network stay on the system (the page asks before the change).
Setting it back to Automatic or the module brings them back. None saves hmipserver about half its
memory: about 155 MB against about 300-330 MB for HMIPServer.jar, measured on a Pi 4.

The API behind the page is `GET`/`PUT /api/system/v1/radio/connections` in occulited's
`docs/system-api.md`.
