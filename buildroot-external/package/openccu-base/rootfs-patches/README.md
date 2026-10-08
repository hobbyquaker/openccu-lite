# OpenCCU-Base rootfs patches

The numbered directories are the editable source of truth. Each file to be
changed is stored as a pristine `rootfs/path.orig` file and its corresponding
modified `rootfs/path` file. The adjacent numbered `.patch` files are generated
artifacts consumed by Buildroot after OpenCCU-Base has populated `build/rootfs`.

Regenerate after editing a modified file:

```sh
./create_patches.sh
./create_patches.sh --check
```

Patch generation requires Bash 4 or newer and GNU diffutils. Refreshing also
requires GNU coreutils. Validation requires GNU patch and a Tcl interpreter;
set `TCLSH` when it is not available as `tclsh` in `PATH`.

Refresh the complete stack for a newer OpenCCU-Base revision using an unpatched
rootfs generated with `OPENCCU_BASE_ENABLE_ROOTFS_PATCHING=NO`:

```sh
./update_patchfiles.sh \
  /absolute/path/to/pristine/build/rootfs \
  /absolute/path/to/extracted/OpenCCU-Base
```

The refresh deliberately fails at the first incompatible patch. Resolve that
patch's semantic change in its modified file, regenerate, and repeat. Do not
generate patches automatically during a normal Buildroot build; generated
patches are committed so they remain reproducible and reviewable.

Patches `0125`, `0155`, and `0207` are rebased semantically because their
generated inputs are unstable across OpenCCU-Base revisions. For these three
patches the transformations in `update_patchfiles.sh`, together with their
workspace files, define the desired result. Keep both representations in sync;
`validate_patches.sh` detects divergence after a refresh.

Non-rootfs maintenance inputs may be kept next to a patch workspace and are
preserved by `update_patchfiles.sh`. For example, patch `0002` retains its npm
and Sass metadata below `maintenance/webui`; these files are not emitted into
the firmware image.

Normal builds call `prepare_patch_input.sh` before applying the series and
`finalize_patch_input.sh` afterwards. The pair temporarily splits generated
template strings in `webui.js` for legacy patches and restores valid JavaScript
before the rootfs is installed. Always use both helpers when applying the stack
outside Buildroot.

The repository-level `check-openccu-base` target extracts the pinned
OpenCCU-Base revision and calls `stage_validation_rootfs.sh`. That helper uses
the OpenCCU-Base CMake definitions to generate only WebUI, device-type, and Tcl
assets with host tools; it does not compile target binaries or libraries. The
result is then passed to `validate_patches.sh` to verify the complete patch
series with zero fuzz.

openccu-lite builds from openccu-lite-base, OpenCCU-Base without the WebUI
sources and without HMServer's FreeMarker pages (task 329), so its build applies
only the series' sections outside `www/` and `opt/HMServer/pages/`, plus those on
the WebUI files openccu-lite ships for addons at the CCU's paths (task 331): the
device pictures under `www/config/img/devices/`, `www/config/devdescr/DEVDB.tcl`,
`www/config/stringtable_de.txt` and `www/webui/js/lang/<lang>/translate.lang*.js`.
`stage_lite_www.sh` stages those as the classic build does (DEVDB.tcl generated
by upstream's `create_devdb_tcl.tcl`, in a sorted order), `lite_series.py` writes
the sections per patch, 43 of the 162 have any, and the series itself stays as
OpenCCU keeps it. `check-openccu-base` validates exactly that part with
`validate_lite_patches.sh`; `stage_validation_rootfs.sh` stages the WebUI only
from a source that has it. Refreshing the complete series with
`update_patchfiles.sh` and `validate_patches.sh` still needs OpenCCU-Base itself.
