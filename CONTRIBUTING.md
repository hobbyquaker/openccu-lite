# Contributing to openccu-lite

openccu-lite is a fork of [OpenCCU](https://github.com/OpenCCU/OpenCCU) (see the [README](README.en.md)).
This repository builds the firmware images; the system service and its web interface are
[occulited](https://github.com/hobbyquaker/occulited), which the images build from its own repository.

## Issues

- **Bugs and feature requests go to this repository's
  [issue tracker](https://github.com/hobbyquaker/openccu-lite/issues)**, for the firmware and for occulited
  alike (occulited has no tracker of its own). The forms ask for the version (the Updates page shows it), the
  product and the journal (the Log page, or `journalctl -b` on the system).
- **Security problems** are reported privately, see [SECURITY.md](SECURITY.md).
- openccu-lite is not OpenCCU: please do not report its problems on OpenCCU's tracker or in its forum.

## Pull requests

Pull requests are welcome, here and in occulited.

- For anything larger than a fix, open an issue first, so the approach can be agreed before the work.
- One logical change per commit, with a message that says why.
- What you contribute here is under the Apache License 2.0 ([LICENSE](LICENSE), [NOTICE.md](NOTICE.md));
  occulited is under the GPL-3.0-only.
- Text a user reads (the web interface, the documents) calls it "the system". The README comes in
  German ([README.md](README.md)) and English ([README.en.md](README.en.md)); keep both in step.
- `lite-check` runs the guards and tests below on every pull request.

## Building a product

The build is buildroot, driven by the top `Makefile`, which downloads and patches buildroot itself. You need
a Linux host with [buildroot's requirements](https://buildroot.org/downloads/manual/manual.html#requirement),
a lot of disk space (a product's build tree runs to tens of gigabytes) and a few hours of CPU for the first
build.

The lite products are the ones listed in `LITE_PRODUCTS` in [lite-version.mk](lite-version.mk):

| Product | Image for |
| --- | --- |
| `aarch64-rpi3` | Raspberry Pi 3, and the eQ-3 CCU3 (its `-ccu3.tgz` update file) |
| `aarch64-rpi4` | Raspberry Pi 4 |
| `aarch64-rpi5` | Raspberry Pi 5 |
| `x86_64-ova` | virtual machines (`.ova`) |
| `lxc-lite_amd64`, `lxc-lite_arm64` | LXC containers |

```sh
make help                                                   # the targets
make PRODUCT=x86_64-ova build                               # the images, in build-x86_64-ova/images/
make PRODUCT=x86_64-ova release                             # plus the release files, in release/
make PRODUCT=x86_64-ova LITE_VERSION=1.0.0-dev.29 release   # with an explicit version
make x86_64-ova-check                                       # buildroot's package checks and the base patches
scripts/lite-qemu-test.sh build-x86_64-ova/images/sdcard.img 18090   # boot the VM image headless in QEMU
```

- **The version:** a lite product's version is `VERSION` from [LITE-VERSION](LITE-VERSION) unless `LITE_VERSION`
  overrides it; `BASE` there is the OpenCCU tag the branch is based on. A product that is missing from
  `LITE_PRODUCTS` silently gets upstream's date-based version.
- **The defconfig trap:** the Makefile merges `buildroot-external/Buildroot.config` and
  `buildroot-external/configs/<product>.config` into `build-<product>/.config` **only when that file does not exist
  yet**. After changing either, delete `build-<product>/.config`, and check the new one for your option before you
  start the long build.
- Upstream's other products (`rpi3`, `rpi4`, `rpi5`, `ova`, `lxc_*`, `generic-*`, `odroid-*`, `tinkerboard2`) are
  still in the tree, because the lite products build on their boards; they are not built or released here.

## Where the lite delta lives

[docs/upstream-delta.md](docs/upstream-delta.md) is the index of every difference to upstream. In short:

- `buildroot-external/configs/` — the lite products' configs (above);
- `buildroot-external/board/lite/` — the post-build steps every lite product runs (systemd, the init scripts,
  the SBOM, the prebuilt CA bundle, the boot screen), and `board/aarch64-rpi*`, `board/x86_64-ova`,
  `board/lxc-lite` for the products;
- `buildroot-external/overlay/lite/` — the files the lite images add or replace (units, drop-ins, scripts,
  lighttpd);
- `buildroot-external/package/occulited/`, `package/lite-bindlo/` — lite's packages;
- `scripts/lite-*` and `scripts/testcases/lite-*` — the guards and tests; `.github/workflows/lite-*.yml` — CI;
- `docs/` — the user documents (switching, LXC, addons, security, privacy, certificates) and the delta index.

An edit to an upstream file is made only in a form upstream could take as it is: honour an existing Kconfig
symbol, add a default-off guard, extend a generic mechanism. Anything else goes into lite's own files. Every
such edit gets its line in `docs/upstream-delta.md`.

## Guards and tests

These run without a build tree, and `lite-check` runs them on GitHub:

```sh
sh scripts/lite-id-guard.sh          # no internal task, decision or bug numbers in what the system shows a user
sh scripts/lite-shellcheck.sh        # upstream's shellcheck options over lite's scripts; warnings fail
sh scripts/testcases/lite-unit-order-test.sh    # and the other scripts/testcases/*-test.sh lite-check.yml lists
git ls-files | grep -v '^[A-Za-z0-9_./@-]*$'   # must print nothing: buildroot's repack chokes on odd file names
```

[lite-check.yml](.github/workflows/lite-check.yml) lists the full set. The image build and the QEMU boot test run
on the project's own build host (`lite-build.yml`).
