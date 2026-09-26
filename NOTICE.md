# Notices

## Licences

- Everything authored for openccu-lite in this repository is under the Apache License 2.0
  ([LICENSE](LICENSE)), as upstream OpenCCU's own work is.
- The system service [occulited](https://github.com/hobbyquaker/occulited), which the image builds from its own
  repository, is under the GPL-3.0-only.
- **eQ-3's software** — the OCCU payloads (`rfd`, `hs485d`, `multimacd`, `hmipserver` and their
  files), fetched at build time with OpenCCU-Base as upstream does — keeps eQ-3's terms, the
  **Homematic Software License (HMSL) 2.0**. This repository contains no eQ-3 binary. The images do,
  and every image carries the licence texts of what it ships in its SBOM
  (`/usr/share/openccu-lite/sbom.cdx.json.gz`, shown on the system's Licences page).

## Modified eQ-3 files (HMSL 2.0, section 3.2 b)

openccu-lite replaces or modifies these files of eQ-3's software. The modifications are published
here, under the HMSL like the originals. The FreeMarker pages and `log4j2.xml` say so in their first
lines; `rfd.conf` is left as it is, because the radio stack's tests compare it byte for byte with what
the system renders, and this file is its notice.

| File in this repository | Replaces in the image | What changed |
| --- | --- | --- |
| `buildroot-external/overlay/lite/opt/HMServer/pages/GroupListPage.ftl` | hmipserver's page of the same name | the heating group list as JSON for occulited, instead of the WebUI's page |
| `buildroot-external/overlay/lite/opt/HMServer/pages/GroupEditPage.ftl` | hmipserver's page of the same name | the group editor's model (the group, its members, the candidates, the types) as JSON |
| `buildroot-external/overlay/lite/opt/HMServer/pages/GroupChooseDialog.ftl` | hmipserver's page of the same name | the groups a device could join as JSON |
| `buildroot-external/overlay/lite/opt/HMServer/pages/GroupConfigureDialog.ftl` | hmipserver's page of the same name | the members whose configuration is pending as JSON |
| `buildroot-external/overlay/lite/etc/config_templates/rfd.conf` | the `rfd.conf` template | rfd listens on the loopback only, logs to syslog |
| `buildroot-external/overlay/lite/etc/config_templates/log4j2.xml` | hmipserver's logging configuration | one appender to the journal, the level set from the Log page |

The patches under `buildroot-external/package/openccu-base/rootfs-patches/` that change eQ-3 files of
OpenCCU-Base come from upstream OpenCCU.
