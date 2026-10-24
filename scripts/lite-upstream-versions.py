#!/usr/bin/env python3
# openccu-lite: are the fork's buildroot, kernels, U-Boot and Raspberry Pi firmware current? Reads the
# pins from the tree and compares them with upstream; changes nothing. Run daily by
# .github/workflows/lite-upstream-versions.yml, which publishes the report page this writes.
# lite-only file, never part of an upstream PR.
#
# The components, our pin, upstream, and the rule for "current" (anything else is a finding: an
# update available, or pins that should be equal and are not):
#   buildroot             Makefile BUILDROOT_VERSION; the tags of github.com/buildroot/buildroot (the
#                         mirror the Makefile downloads from; -rc tags ignored). Current: no newer point
#                         release of our series and no newer release series. The series' end of support
#                         from buildroot.org's download table (Stable, Old stable, Long-term support - the
#                         LTS series are listed there as well, in the "Long-term support" row): a finding
#                         from BUILDROOT_EOL_WARN_DAYS (two weeks) before the end of the month named for a
#                         quarterly series, from BUILDROOT_LTS_EOL_WARN_MONTHS (six months) for an LTS; a
#                         series no longer listed is past it; an unreadable page is a note.
#   Raspberry Pi kernel   the raspberrypi/linux stable_YYYYMMDD tarball of aarch64-rpi3 and -rpi4; the
#                         repository's stable_ tags. Current: both configs pin the same tag, and no newer
#                         tag exists. The kernel version of a tag comes from its top-level Makefile.
#   VM kernel             BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE of x86_64-ova; kernel.org's releases.json.
#                         Current: no newer release of our series (e.g. 6.18.x), and our series not at its
#                         end (below). A newer longterm series is a note.
#   the end of a series   (the VM kernel's, and the Raspberry Pi kernel's series from its Makefile) a
#                         series marked "iseol" in releases.json, or gone from it, is end of life: a
#                         finding ("move to the next longterm"), not a failed check. Early warning: the
#                         projected EOL of kernel.org's longterm table (category/releases.html) is shown,
#                         and from EOL_WARN_MONTHS before it the series is a finding ("plan the move");
#                         an unreadable table is a note ("EOL date unknown"), never a failed check.
#                         raspberrypi's default branch on a newer rpi-X.Y.y is a note.
#   U-Boot                BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE of aarch64-rpi3 and -rpi4; the vYYYY.MM
#                         tags of github.com/u-boot/u-boot. Current: both pin the same version, and it is
#                         the newest release.
#   Raspberry Pi firmware BR2_PACKAGE_RPI_FIRMWARE_VERSION of aarch64-rpi3 and -rpi4 (a commit of
#                         raspberrypi/firmware). raspberrypi releases firmware and kernel together: a
#                         firmware commit's extra/git_hash is the raspberrypi/linux commit it was built
#                         with, which is the commit of a stable_ tag. Current: both pin the same commit,
#                         it was built with our kernel's stable_ tag, and no newer firmware release (the
#                         newest FIRMWARE_TAGS of the 1.YYYYMMDD tags) was built with a newer stable_ tag.
#   rpi-eeprom            the pieeprom-YYYY-MM-DD.bin of package/rpi-eeprom's Pi 4 path (aarch64-rpi4);
#                         firmware-2711/versions.txt of raspberrypi/rpi-eeprom, the "default" channel
#                         only (never "latest"). Current: no default release newer than ours.
#   GRUB (VM) and Go come with buildroot and are covered by its check.
#   The report's "supported until" column: buildroot and the kernels as above; U-Boot, the Raspberry Pi
#   firmware and rpi-eeprom publish no support period, and the report says so.
#
# Findings are not an error: they are ::warning:: lines, the report and a yellow badge, and the exit
# code stays 0. An error is: 2 a pin not found in the tree, 3 upstream unreachable or not parseable,
# 4 the script's own failure (::error::, the report says "check failed", the badge is grey) - never
# green on a network error.
# Prints a table; with GITHUB_STEP_SUMMARY set (or --summary FILE) it appends it as Markdown.
# --site DIR writes the report page (index.html German, en.html English) and badge.json, a shields.io
# endpoint: green "up to date", yellow "updates available", grey "check failed".
#
# Usage: python3 scripts/lite-upstream-versions.py [--root DIR] [--fixtures DIR] [--summary FILE]
#                                                   [--site DIR]
#   --fixtures DIR reads upstream from files instead of the network (the offline test):
#     buildroot-tags.txt, rpi-tags.txt, uboot-tags.txt, firmware-tags.txt (git ls-remote output),
#     releases.json, releases.html, buildroot-download.html, rpi-head.txt (git ls-remote --symref HEAD), rpi-Makefile-<tag>,
#     firmware-git_hash-<commit or tag>, eeprom-versions.txt
#   --today YYYY-MM-DD the date the EOL warning counts from (the tests; default today, UTC)
import argparse
import datetime
import html
import json
import os
import re
import subprocess
import sys
import urllib.request

RPI = ["aarch64-rpi3", "aarch64-rpi4"]
VM = "x86_64-ova"
FIRMWARE_TAGS = 8

BUILDROOT_GIT = "https://github.com/buildroot/buildroot"
RPI_GIT = "https://github.com/raspberrypi/linux"
UBOOT_GIT = "https://github.com/u-boot/u-boot"
FIRMWARE_GIT = "https://github.com/raspberrypi/firmware"
RAW = "https://raw.githubusercontent.com/raspberrypi/{repo}/{ref}/{path}"
KERNEL_RELEASES = "https://www.kernel.org/releases.json"
KERNEL_EOL_PAGE = "https://www.kernel.org/category/releases.html"
EOL_WARN_MONTHS = 6
BUILDROOT_EOL_WARN_DAYS = 14         # a quarterly series: supported about four months, warn two weeks ahead
BUILDROOT_LTS_EOL_WARN_MONTHS = 6    # an LTS series: supported three years, warn six months ahead
BUILDROOT_DOWNLOAD = "https://buildroot.org/download.html"
NO_PERIOD = ("no published support period", "kein veröffentlichter Supportzeitraum")
PAGE = "https://hobbyquaker.github.io/openccu-lite/"


class PinError(Exception):
    pass


class UpstreamError(Exception):
    pass


class Upstream:
    def __init__(self, fixtures=None, today=None):
        self.fixtures = fixtures
        self.cache = {}
        self.today = today or datetime.datetime.now(datetime.timezone.utc).date()

    def symref(self, url, fixture):
        """the ref HEAD points to (git ls-remote --symref)"""
        if self.fixtures:
            out = self._fixture(fixture)
        else:
            try:
                p = subprocess.run(["git", "ls-remote", "--symref", url, "HEAD"], capture_output=True, text=True,
                                   timeout=120, check=False, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
            except (OSError, subprocess.TimeoutExpired) as e:
                raise UpstreamError(f"git ls-remote --symref {url}: {e}") from e
            if p.returncode != 0:
                raise UpstreamError(f"git ls-remote --symref {url}: exit {p.returncode}: {p.stderr.strip()}")
            out = p.stdout
        m = re.search(r"^ref: (\S+)\s+HEAD$", out, re.M)
        if not m:
            raise UpstreamError(f"{url}: no HEAD symref")
        return m.group(1)

    def _fixture(self, name):
        try:
            with open(os.path.join(self.fixtures, name), encoding="utf-8") as f:
                return f.read()
        except OSError as e:
            raise UpstreamError(f"fixture {name}: {e}") from e

    def tags(self, url, pattern, fixture):
        """{tag: commit} of git ls-remote --tags (an annotated tag's commit from its ^{} line)"""
        if fixture in self.cache:
            return self.cache[fixture]
        if self.fixtures:
            out = self._fixture(fixture)
        else:
            try:
                r = subprocess.run(["git", "ls-remote", "--tags", url, pattern], capture_output=True,
                                   text=True, timeout=120, check=False,
                                   env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
            except (OSError, subprocess.TimeoutExpired) as e:
                raise UpstreamError(f"git ls-remote {url}: {e}") from e
            if r.returncode != 0:
                raise UpstreamError(f"git ls-remote {url}: exit {r.returncode}: {r.stderr.strip()}")
            out = r.stdout
        tags = {}
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1].startswith("refs/tags/"):
                name = parts[1][len("refs/tags/"):]
                if name.endswith("^{}"):
                    tags[name[:-3]] = parts[0]
                else:
                    tags.setdefault(name, parts[0])
        self.cache[fixture] = tags
        return tags

    def http(self, url, fixture):
        if fixture in self.cache:
            return self.cache[fixture]
        if self.fixtures:
            body = self._fixture(fixture)
        else:
            req = urllib.request.Request(url, headers={"User-Agent": "openccu-lite-upstream-versions"})
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    body = resp.read().decode("utf-8")
            except (OSError, ValueError) as e:
                raise UpstreamError(f"{url}: {e}") from e
        self.cache[fixture] = body
        return body


class Row:
    def __init__(self, key, en, de, link):
        self.key, self.en, self.de, self.link = key, en, de, link
        self.ours = self.newest = "-"
        self.until = NO_PERIOD
        self.findings = []   # [(en, de)]
        self.notes = []      # [(en, de)]

    def due(self, en, de):
        self.findings.append((en, de))

    def note(self, en, de):
        self.notes.append((en, de))


def read(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        raise PinError(f"{rel}: {e}") from e


def pin(root, rel, regex, what):
    m = re.search(regex, read(root, rel), re.M)
    if not m:
        raise PinError(f"{rel}: no {what}")
    return m.group(1)


def cfg(product):
    return f"buildroot-external/configs/{product}.config"


def ver_key(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def short(product):
    return product.split("-", 1)[1]


# ---- buildroot

BR_RE = re.compile(r"^(\d{4})\.(\d{2})(?:\.(\d+))?$")


def br_key(v):
    m = BR_RE.match(v)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)) if m else None


def check_buildroot(root, up):
    r = Row("buildroot", "buildroot", "buildroot", "https://buildroot.org/download.html")
    ours = pin(root, "Makefile", r"^BUILDROOT_VERSION\s*:?=\s*(\S+)\s*$", "BUILDROOT_VERSION")
    k = br_key(ours)
    if not k:
        raise PinError(f"buildroot version {ours!r} is not YYYY.MM[.N]")
    rel = sorted((t for t in up.tags(BUILDROOT_GIT, "refs/tags/20*", "buildroot-tags.txt") if br_key(t)), key=br_key)
    if not rel:
        raise UpstreamError("buildroot: no release tags in the listing")
    r.ours, r.newest = ours, rel[-1]
    series = [t for t in rel if br_key(t)[:2] == k[:2]]
    if series and br_key(series[-1]) > k:
        r.due(f"buildroot {series[-1]} is out (we pin {ours})", f"buildroot {series[-1]} ist erschienen (wir: {ours})")
    for s in sorted({br_key(t)[:2] for t in rel if br_key(t)[:2] > k[:2]}):
        name = f"{s[0]}.{s[1]:02d}"
        newest = [t for t in rel if br_key(t)[:2] == s][-1]
        r.due(f"buildroot series {name} is out (newest {newest}); we pin {ours}",
              f"die buildroot-Reihe {name} ist erschienen (neueste {newest}); wir: {ours}")
    eol = buildroot_eol_dates(up)
    name = f"{k[0]}.{k[1]:02d}"
    if eol is None:
        r.until = ("unknown", "unbekannt")
        r.note("end of support unknown (buildroot.org's download page not readable)",
               "Supportende unbekannt (Download-Seite von buildroot.org nicht lesbar)")
    elif name in eol:
        ym, lts = eol[name]
        if lts:
            eol_within(r, f"buildroot {name} (LTS)", f"buildroot {name} (LTS)", ym, up.today, BUILDROOT_LTS_EOL_WARN_MONTHS)
        else:
            eol_within_days(r, f"buildroot {name}", f"buildroot {name}", ym, up.today, BUILDROOT_EOL_WARN_DAYS)
    else:
        r.until = ("not listed (end of support)", "nicht gelistet (Supportende)")
        r.due(f"buildroot {name} is no longer listed on buildroot.org's download page (end of support)",
              f"buildroot {name} steht nicht mehr auf der Download-Seite von buildroot.org (Supportende)")
    r.note("GRUB (VM) and Go come with buildroot", "GRUB (VM) und Go kommen mit buildroot")
    return r


def buildroot_eol_dates(up):
    """{series: ((year, month), lts)} of buildroot.org's download table (Stable, Old stable, Long-term support:
    "<th>Stable</th><th>2026.08.x</th><td>December 2026</td>"; the row labelled "Long-term support" is an LTS);
    None when it cannot be read - a note, never a failed check"""
    try:
        page = up.http(BUILDROOT_DOWNLOAD, "buildroot-download.html")
    except UpstreamError:
        return None
    page = re.sub(r"<!--.*?-->", "", page, flags=re.S)
    out = {}
    for label, ser, mon, year in re.findall(
            r"<th>\s*([^<]*?)\s*</th>\s*<th>\s*(\d{4}\.\d{2})(?:\.\d+)*\.x\s*</th>\s*<td>\s*([A-Za-z]+)\s+(\d{4})\s*</td>",
            page):
        if mon[:3].lower() in MONTHS:
            lts = bool(re.search(r"long[- ]term|\blts\b", label, re.I))
            out[ser] = ((int(year), MONTHS[mon[:3].lower()]), lts)
    return out or None


# ---- Raspberry Pi kernel

def rpi_kernel_version(tag, up):
    mk = up.http(RAW.format(repo="linux", ref=tag, path="Makefile"), f"rpi-Makefile-{tag}")
    f = dict(re.findall(r"^(VERSION|PATCHLEVEL|SUBLEVEL)\s*=\s*(\d+)\s*$", mk, re.M))
    if len(f) != 3:
        raise UpstreamError(f"raspberrypi/linux {tag}: no kernel version in its Makefile")
    return f"{f['VERSION']}.{f['PATCHLEVEL']}.{f['SUBLEVEL']}"


def rpi_stable_tags(up):
    t = {n: c for n, c in up.tags(RPI_GIT, "refs/tags/stable_*", "rpi-tags.txt").items()
         if re.match(r"^stable_\d{8}$", n)}
    if not t:
        raise UpstreamError("raspberrypi/linux: no stable_ tags in the listing")
    return t


def rpi_pins(root):
    return {p: pin(root, cfg(p), r'^BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="[^"]*raspberrypi/linux/archive/'
                   r'(stable_\d{8})\.tar\.gz"', "raspberrypi/linux stable_ tarball") for p in RPI}


def differ(r, pins, what_en, what_de):
    """a finding when the Pi products pin different values; returns the one value or None"""
    if len(set(pins.values())) > 1:
        lst = ", ".join(f"{short(p)} {v}" for p, v in pins.items())
        r.due(f"rpi3 and rpi4 pin different {what_en}: {lst}", f"rpi3 und rpi4 haben verschiedene {what_de}: {lst}")
        r.ours = lst
        return None
    return next(iter(pins.values()))


def check_rpi_kernel(root, up):
    r = Row("rpi-kernel", "Raspberry Pi kernel (rpi3, rpi4)", "Raspberry-Pi-Kernel (rpi3, rpi4)",
            "https://github.com/raspberrypi/linux/tags")
    pins = rpi_pins(root)
    tags = rpi_stable_tags(up)
    newest = max(tags)
    nv = rpi_kernel_version(newest, up)
    r.newest = f"{newest} ({nv})"
    one = differ(r, pins, "kernels", "Kernel")
    if one:
        ov = rpi_kernel_version(one, up)
        r.ours = f"{one} ({ov})"
        series = ".".join(ov.split(".")[:2])
        head = up.symref(RPI_GIT, "rpi-head.txt")
        hm = re.match(r"^refs/heads/rpi-(\d+\.\d+)\.y$", head)
        if hm and ver_key(hm.group(1)) > ver_key(series):
            r.note(f"raspberrypi's default branch moved to rpi-{hm.group(1)}.y (ours: {series})",
                   f"der Standard-Branch von raspberrypi ist jetzt rpi-{hm.group(1)}.y (unserer: {series})")
        series_eol(r, series, kernel_releases(up), kernel_eol_dates(up), up.today)
    for t in sorted(set(pins.values())):
        if newest > t:
            r.due(f"raspberrypi/linux {newest} (kernel {nv}) is out (we pin {t})",
                  f"raspberrypi/linux {newest} (Kernel {nv}) ist erschienen (wir: {t})")
    return r


# ---- VM kernel

def kernel_releases(up):
    try:
        return [(x["moniker"], x["version"], bool(x.get("iseol")))
                for x in json.loads(up.http(KERNEL_RELEASES, "releases.json"))["releases"]]
    except (ValueError, KeyError, TypeError) as e:
        raise UpstreamError(f"kernel.org releases.json: {e}") from e


MONTHS = {m: i + 1 for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun",
                                           "jul", "aug", "sep", "oct", "nov", "dec"])}


def kernel_eol_dates(up):
    """{series: (year, month)} of kernel.org's longterm table (projected EOL); None when it cannot be read -
    the dates are an early warning, their absence is a note, never a failed check"""
    try:
        page = up.http(KERNEL_EOL_PAGE, "releases.html")
    except UpstreamError:
        return None
    out = {}
    for row in re.findall(r"<tr>(.*?)</tr>", page, re.S):
        cells = [re.sub(r"<[^>]+>", "", c).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
        if len(cells) >= 4 and re.match(r"^\d+\.\d+$", cells[0]):
            m = re.match(r"^([A-Za-z]{3})[a-z]*\.?,?\s*(\d{4})$", cells[-1])
            if m and m.group(1).lower() in MONTHS:
                out[cells[0]] = (int(m.group(2)), MONTHS[m.group(1).lower()])
    return out or None


def newest_longterm(rels):
    lt = [x[1] for x in rels if x[0] == "longterm" and not x[2]]
    return max(lt, key=ver_key) if lt else None


def eol_within(r, what_en, what_de, ym, today, warn, plan_en="", plan_de=""):
    """the support column from a projected (year, month), and a finding from `warn` months before it"""
    y, m = ym
    when = f"{y}-{m:02d}"
    months = (y * 12 + m) - (today.year * 12 + today.month)
    r.until = (when, when)
    if months < 0:
        r.due(f"{what_en} is past its end of support ({when}){plan_en}",
              f"{what_de} hat sein Supportende überschritten ({when}){plan_de}")
    elif months <= warn:
        r.due(f"{what_en} reaches its end of support in {months} month(s) ({when}){plan_en}",
              f"{what_de} erreicht sein Supportende in {months} Monat(en) ({when}){plan_de}")


def eol_within_days(r, what_en, what_de, ym, today, warn_days):
    """like eol_within, with the warning `warn_days` before the end of the month named (a month named as the
    end of support is taken as supported through its last day)"""
    y, m = ym
    when = f"{y}-{m:02d}"
    last = (datetime.date(y + m // 12, m % 12 + 1, 1) - datetime.timedelta(days=1))
    days = (last - today).days
    r.until = (when, when)
    if days < 0:
        r.due(f"{what_en} is past its end of support ({when})", f"{what_de} hat sein Supportende überschritten ({when})")
    elif days <= warn_days:
        r.due(f"{what_en} reaches its end of support in {days} day(s) ({when})",
              f"{what_de} erreicht sein Supportende in {days} Tag(en) ({when})")


def series_eol(r, series, rels, eol_dates, today):
    """the end-of-life findings of a kernel.org series: marked EOL or gone from releases.json, or its projected
    EOL within EOL_WARN_MONTHS; sets the support column"""
    nxt = newest_longterm(rels)
    later = nxt and ver_key(nxt)[:2] > ver_key(series)
    move_en = f", move to the next longterm ({nxt})" if later else ""
    move_de = f", Wechsel auf den nächsten Longterm-Kernel ({nxt})" if later else ""
    mine = [x for x in rels if re.match(rf"^{re.escape(series)}(\.|$)", x[1])]
    if not mine or any(x[2] for x in mine):
        r.until = ("end of life", "end of life")
        how_en, how_de = ("no longer listed on kernel.org", "nicht mehr auf kernel.org") if not mine \
            else ("marked EOL on kernel.org", "auf kernel.org als EOL markiert")
        r.due(f"kernel {series} is end of life ({how_en}){move_en}",
              f"Kernel {series} ist end of life ({how_de}){move_de}")
    elif eol_dates is None:
        r.until = ("unknown", "unbekannt")
        r.note("projected end of life unknown (kernel.org's releases page not readable)",
               "voraussichtliches Supportende unbekannt (kernel.org-Release-Seite nicht lesbar)")
    elif series in eol_dates:
        eol_within(r, f"kernel {series}", f"Kernel {series}", eol_dates[series], today, EOL_WARN_MONTHS,
                   f", plan the move to {nxt}" if later else "", f", Wechsel auf {nxt} planen" if later else "")
    else:
        r.until = ("no projected end (not longterm)", "kein voraussichtliches Ende (kein Longterm)")


def check_vm_kernel(root, up):
    r = Row("vm-kernel", "VM kernel (ova)", "VM-Kernel (ova)", "https://www.kernel.org/category/releases.html")
    ours = pin(root, cfg(VM), r'^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="([^"]+)"', "kernel.org kernel version")
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", ours)
    if not m:
        raise PinError(f"kernel version {ours!r} is not N.N[.N]")
    rels = kernel_releases(up)
    series = f"{m.group(1)}.{m.group(2)}"
    r.ours = ours
    mine = [x for x in rels if re.match(rf"^{re.escape(series)}(\.|$)", x[1])]
    if mine:
        r.newest = max((x[1] for x in mine), key=ver_key)
        if ver_key(r.newest) > ver_key(ours):
            r.due(f"kernel {r.newest} is out (we pin {ours})", f"Kernel {r.newest} ist erschienen (wir: {ours})")
    series_eol(r, series, rels, kernel_eol_dates(up), up.today)
    newer_lt = sorted((x[1] for x in rels if x[0] == "longterm" and not x[2] and ver_key(x[1])[:2] > ver_key(series)),
                      key=ver_key)
    if newer_lt:
        r.note("newer longterm: " + ", ".join(newer_lt), "neuerer Longterm-Kernel: " + ", ".join(newer_lt))
    return r


# ---- U-Boot

def check_uboot(root, up):
    r = Row("u-boot", "U-Boot (rpi3, rpi4)", "U-Boot (rpi3, rpi4)", "https://github.com/u-boot/u-boot/tags")
    pins = {p: pin(root, cfg(p), r'^BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="([^"]+)"', "U-Boot version") for p in RPI}
    rel = sorted((t[1:] for t in up.tags(UBOOT_GIT, "refs/tags/v20*", "uboot-tags.txt")
                  if re.match(r"^v\d{4}\.\d{2}$", t)), key=ver_key)
    if not rel:
        raise UpstreamError("u-boot: no release tags in the listing")
    r.newest = rel[-1]
    one = differ(r, pins, "U-Boot versions", "U-Boot-Versionen")
    if one:
        r.ours = one
    for v in sorted(set(pins.values()), key=ver_key):
        if ver_key(r.newest) > ver_key(v):
            who = ", ".join(short(p) for p in RPI if pins[p] == v)
            r.due(f"U-Boot {r.newest} is out ({who} pins {v})", f"U-Boot {r.newest} ist erschienen ({who}: {v})")
    return r


# ---- Raspberry Pi firmware

def firmware_kernel(ref, up):
    h = up.http(RAW.format(repo="firmware", ref=ref, path="extra/git_hash"), f"firmware-git_hash-{ref}").strip()
    if not re.match(r"^[0-9a-f]{40}$", h):
        raise UpstreamError(f"raspberrypi/firmware {ref}: extra/git_hash is not a commit")
    return h


def check_rpi_firmware(root, up):
    r = Row("rpi-firmware", "Raspberry Pi firmware (rpi3, rpi4)", "Raspberry-Pi-Firmware (rpi3, rpi4)",
            "https://github.com/raspberrypi/firmware/tags")
    pins = {p: pin(root, cfg(p), r'^BR2_PACKAGE_RPI_FIRMWARE_VERSION="([0-9a-f]{40})"', "rpi-firmware commit")
            for p in RPI}
    by_commit = {c: n for n, c in rpi_stable_tags(up).items()}
    fw = up.tags(FIRMWARE_GIT, "refs/tags/1.*", "firmware-tags.txt")
    fw = sorted((t for t in fw if re.match(r"^1\.\d{8}$", t)), reverse=True)[:FIRMWARE_TAGS]
    if not fw:
        raise UpstreamError("raspberrypi/firmware: no 1.YYYYMMDD tags in the listing")
    newest_fw = newest_for = None
    for t in fw:  # newest first: the newest firmware release built with a stable_ tag
        k = by_commit.get(firmware_kernel(t, up))
        if k:
            newest_fw, newest_for = t, k
            break
    r.newest = f"{newest_fw} ({newest_for})" if newest_fw else "-"
    one = differ(r, {p: v[:12] for p, v in pins.items()}, "firmware commits", "Firmware-Commits")
    kernel = rpi_pins(root)
    for commit in sorted(set(pins.values())):
        built = by_commit.get(firmware_kernel(commit, up))
        if one:
            r.ours = f"{commit[:12]} ({built or 'no stable_ tag'})"
        if not built:
            r.due(f"firmware {commit[:12]} was not built with a raspberrypi/linux stable_ tag",
                  f"Firmware {commit[:12]} wurde mit keinem stable_-Tag von raspberrypi/linux gebaut")
            continue
        for p in RPI:
            if pins[p] == commit and kernel[p] != built:
                r.due(f"{short(p)}: firmware {commit[:12]} belongs to {built}, the kernel is {kernel[p]}",
                      f"{short(p)}: Firmware {commit[:12]} gehört zu {built}, der Kernel ist {kernel[p]}")
        if newest_for and newest_for > built:
            r.due(f"firmware {newest_fw} (built with {newest_for}) is out; ours was built with {built}",
                  f"Firmware {newest_fw} (gebaut mit {newest_for}) ist erschienen; unsere mit {built}")
    if not newest_fw:
        r.note(f"none of the newest {FIRMWARE_TAGS} firmware releases was built with a stable_ tag",
               f"keines der neuesten {FIRMWARE_TAGS} Firmware-Releases wurde mit einem stable_-Tag gebaut")
    return r


# ---- rpi-eeprom

def check_rpi_eeprom(root, up):
    r = Row("rpi-eeprom", "rpi-eeprom (rpi4, channel default)", "rpi-eeprom (rpi4, Kanal default)",
            "https://github.com/raspberrypi/rpi-eeprom/blob/master/firmware-2711/release-notes.md")
    if not re.search(r"^BR2_PACKAGE_RPI_EEPROM=y", read(root, cfg("aarch64-rpi4")), re.M):
        r.note("not in aarch64-rpi4", "nicht in aarch64-rpi4")
        return r
    mk = read(root, "buildroot-external/package/rpi-eeprom/rpi-eeprom.mk")
    m = re.search(r"^\s*RPI_EEPROM_FIRMWARE_PATH\s*=\s*firmware-2711/\S*pieeprom-(\d{4}-\d{2}-\d{2})\.bin", mk, re.M)
    if not m:
        raise PinError("rpi-eeprom.mk: no firmware-2711 pieeprom-YYYY-MM-DD.bin")
    ours = r.ours = m.group(1)
    txt = up.http(RAW.format(repo="rpi-eeprom", ref="master", path="firmware-2711/versions.txt"), "eeprom-versions.txt")
    rows = [x for x in (ln.split() for ln in txt.splitlines() if not ln.startswith("#"))
            if len(x) >= 4 and re.match(r"^\d{4}-\d{2}-\d{2}$", x[0])]
    default = sorted(x[0] for x in rows if x[3] == "default")
    if not default:
        raise UpstreamError("rpi-eeprom: no default release in firmware-2711/versions.txt")
    r.newest = default[-1]
    if r.newest > ours:
        r.due(f"rpi-eeprom {r.newest} is the default release (we pin {ours})",
              f"rpi-eeprom {r.newest} ist das default-Release (wir: {ours})")
    elif ours > r.newest:
        chan = next((x[3] for x in rows if x[0] == ours), "?")
        r.note(f"ours is newer than default (channel {chan})", f"unseres ist neuer als default (Kanal {chan})")
    return r


CHECKS = [check_buildroot, check_rpi_kernel, check_vm_kernel, check_uboot, check_rpi_firmware, check_rpi_eeprom]


# ---- output

CSS = """
:root{--bg:#fff;--fg:#1f2328;--muted:#59636e;--line:#d1d9e0;--ok:#1a7f37;--due:#9a6700;--err:#cf222e;--head:#f6f8fa}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#9198a1;--line:#3d444d;--ok:#3fb950;
--due:#d29922;--err:#f85149;--head:#151b23}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;margin:0;padding:24px 16px}
main{max-width:960px;margin:0 auto}h1{font-size:1.5em;margin:0 0 4px}p{color:var(--muted);margin:4px 0 16px}
a{color:inherit}.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%}
th,td{border:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}th{background:var(--head)}
.ok{color:var(--ok);font-weight:600}.due{color:var(--due);font-weight:600}.err{color:var(--err);font-weight:600}
ul{margin:4px 0 0;padding-left:18px}.note{color:var(--muted)}
"""

TEXT = {
    "en": {"title": "openccu-lite: upstream versions", "comp": "Component", "ours": "ours", "newest": "newest upstream",
           "until": "supported until", "status": "Status", "ok": "up to date", "due": "update available", "checked": "Checked",
           "run": "workflow run", "lang": ("Deutsch", "index.html"), "failed": "Check failed",
           "intro": "Daily comparison of the versions openccu-lite pins with their upstream releases. "
                    "The rules are in scripts/lite-upstream-versions.py."},
    "de": {"title": "openccu-lite: Upstream-Versionen", "comp": "Komponente", "ours": "unsere", "newest": "neueste upstream",
           "until": "Support bis", "status": "Status", "ok": "aktuell", "due": "Update verfügbar", "checked": "Geprüft",
           "run": "Workflow-Lauf", "lang": ("English", "en.html"), "failed": "Prüfung fehlgeschlagen",
           "intro": "Täglicher Vergleich der Versionen, die openccu-lite verwendet, mit ihren Upstream-Releases. "
                    "Die Regeln stehen in scripts/lite-upstream-versions.py."},
}


def page(lang, rows, error, when, run_url):
    t, e = TEXT[lang], html.escape
    li = 0 if lang == "en" else 1
    out = [f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           f"<title>{e(t['title'])}</title><style>{CSS}</style></head><body><main>",
           f"<h1>{e(t['title'])}</h1>",
           f"<p>{e(t['intro'])}</p>",
           f"<p>{e(t['checked'])}: {e(when)}"
           + (f' · <a href="{e(run_url)}">{e(t["run"])}</a>' if run_url else "")
           + f' · <a href="{t["lang"][1]}">{t["lang"][0]}</a></p>']
    if error:
        out.append(f'<p class="err">{e(t["failed"])}: {e(error)}</p>')
    else:
        out.append(f'<div class="wrap"><table><tr><th>{e(t["comp"])}</th><th>{e(t["ours"])}</th>'
                   f'<th>{e(t["newest"])}</th><th>{e(t["until"])}</th><th>{e(t["status"])}</th></tr>')
        for r in rows:
            st = f'<span class="due">{e(t["due"])}</span>' if r.findings else f'<span class="ok">{e(t["ok"])}</span>'
            items = [f"<li>{e(f[li])}</li>" for f in r.findings] + [f'<li class="note">{e(n[li])}</li>' for n in r.notes]
            name = r.en if lang == "en" else r.de
            out.append(f'<tr><td><a href="{e(r.link)}">{e(name)}</a></td><td>{e(r.ours)}</td><td>{e(r.newest)}</td>'
                       f"<td>{e(r.until[li])}</td><td>{st}" + (f"<ul>{''.join(items)}</ul>" if items else "") + "</td></tr>")
        out.append("</table></div>")
    out.append("</main></body></html>\n")
    return "\n".join(out)


def write_site(d, rows, error):
    os.makedirs(d, exist_ok=True)
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    run_url = None
    if os.environ.get("GITHUB_RUN_ID") and os.environ.get("GITHUB_REPOSITORY"):
        run_url = (f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}"
                   f"/actions/runs/{os.environ['GITHUB_RUN_ID']}")
    for lang, name in (("de", "index.html"), ("en", "en.html")):
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(page(lang, rows, error, when, run_url))
    if error:
        badge = ("check failed", "lightgrey")
    elif any(r.findings for r in rows):
        badge = ("updates available", "yellow")
    else:
        badge = ("up to date", "brightgreen")
    with open(os.path.join(d, "badge.json"), "w", encoding="utf-8") as f:
        json.dump({"schemaVersion": 1, "label": "upstream versions", "message": badge[0], "color": badge[1]}, f)
        f.write("\n")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ap.add_argument("--fixtures")
    ap.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"))
    ap.add_argument("--site")
    ap.add_argument("--today", type=datetime.date.fromisoformat, help="the date the EOL warning counts from (tests)")
    a = ap.parse_args(argv)
    up = Upstream(a.fixtures, a.today)
    rows, error, code = [], None, 0
    try:
        for check in CHECKS:
            rows.append(check(a.root, up))
    except UpstreamError as e:
        error, code = f"upstream unreachable or not parseable - nothing was checked: {e}", 3
    except PinError as e:
        error, code = f"pin not found: {e}", 2
    except Exception as e:  # noqa: BLE001 - a bug here still gives a grey badge, not a stale one
        error, code = f"the check itself failed: {e!r}", 4
    if a.site:
        write_site(a.site, rows, error)
    if error:
        print(f"::error::{error}")
        if a.summary:
            with open(a.summary, "a", encoding="utf-8") as f:
                f.write(f"## Upstream versions\n\n**Check failed:** {error}\n")
        return code

    head = ("component", "ours", "newest", "supported until", "status")
    tab = [(r.en, r.ours, r.newest, r.until[0], "update available" if r.findings else "up to date") for r in rows]
    w = [max(len(x[i]) for x in tab + [head]) for i in range(5)]
    for x in [head] + tab:
        print("  ".join(c.ljust(w[i]) for i, c in enumerate(x)).rstrip())
    due = [f"{r.en}: {f[0]}" for r in rows for f in r.findings]
    for r in rows:
        for n in r.notes:
            print(f"note - {r.en}: {n[0]}")
    for d in due:
        print(f"::warning::update available - {d}")
    if a.summary:
        with open(a.summary, "a", encoding="utf-8") as f:
            f.write("## Upstream versions\n\n| component | ours | newest upstream | supported until | status |\n| --- | --- | --- | --- | --- |\n")
            for x in tab:
                f.write("| " + " | ".join(x) + " |\n")
            f.write("\n" + (f"**{len(due)} finding(s).**\n" if due else "**All current.**\n"))
            for d in due:
                f.write(f"- {d}\n")
            f.write(f"\nReport: {PAGE}\n")
    print(f"\n{len(due)} finding(s)" if due else "\nall current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
