#!/usr/bin/env python3
# openccu-lite: are the fork's buildroot, kernels and Raspberry Pi firmware current? Reads the
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
#                         Current: our series not at its end (below). A newer release of our series (e.g.
#                         6.18.x) is a note, never a finding - only the Raspberry Pi kernel's newer tag
#                         turns the badge yellow. A newer longterm series is a note.
#   the end of a series   (the VM kernel's, and the Raspberry Pi kernel's series from its Makefile) a
#                         series marked "iseol" in releases.json, or gone from it, is end of life: a
#                         finding ("move to the next longterm"), not a failed check. Early warning: the
#                         projected EOL of kernel.org's longterm table (category/releases.html) is shown,
#                         and from EOL_WARN_MONTHS before it the series is a finding ("plan the move");
#                         an unreadable table is a note ("EOL date unknown"), never a failed check.
#                         raspberrypi's default branch on a newer rpi-X.Y.y is a note.
#   Raspberry Pi firmware BR2_PACKAGE_RPI_FIRMWARE_VERSION of aarch64-rpi3 and -rpi4 (a commit of
#                         raspberrypi/firmware). raspberrypi releases firmware and kernel together: a
#                         firmware commit's extra/git_hash is the raspberrypi/linux commit it was built
#                         with, which is the commit of a stable_ tag. Current: both pin the same commit,
#                         it was built with our kernel's stable_ tag, and no newer firmware release (the
#                         newest FIRMWARE_TAGS of the 1.YYYYMMDD tags) was built with a newer stable_ tag.
#   rpi-eeprom            the pieeprom-YYYY-MM-DD.bin of package/rpi-eeprom's Pi 4 path (aarch64-rpi4);
#                         firmware-2711/versions.txt of raspberrypi/rpi-eeprom, the "default" channel
#                         only (never "latest"). Current: no default release newer than ours.
#   JVM                   JAVA_AZUL_VERSION of package/java-azul (the Azul Zulu runtime HMIPServer runs
#                         on) against the newest GA Zulu build of our Java major and package type (JRE)
#                         for each architecture we download (linux_aarch64, linux_x64), from Azul's
#                         metadata API (no key). Current: no newer build (Java version, then Zulu
#                         version) for either. The support column: endoflife.date's azul-zulu cycle of
#                         our Java major (Azul's published dates), a finding from EOL_WARN_MONTHS before
#                         it; unreadable is a note.
#   HMIPServer            opt/HMServer/HMIPServer.jar of the OpenCCU-Base our package/openccu-base pins
#                         (the fork's tag), shown with the OpenCCU/OpenCCU-Base version tag it comes from
#                         (the newest of the BASE_TAGS_SCAN newest version tags with the same jar), and
#                         against two others: eQ-3's own repository homematicip/OpenCCU-Base (its default
#                         branch head; information only, a newer one there - often a -SNAPSHOT - is a
#                         note, never a finding) and the newest version tag of OpenCCU/OpenCCU-Base
#                         (BASE_TAG_RE, e.g. 3.89.11, by version order; any other tag ignored): a finding
#                         when ours is older, or when its different jar has no readable version. The jar
#                         is identified by its git blob sha (GitHub's contents API lists it without the
#                         40 MB). The version is the
#                         one of eQ-3's server-core module, read from the jar's
#                         META-INF/maven/.../pom.properties with HTTP range requests (the zip's central
#                         directory and that one entry, about 3 MB) - ours always, another only when its
#                         sha differs from ours. A -SNAPSHOT is named as such (openccu-lite keeps eQ-3's
#                         release build).
#   OpenCCU-Base commits  the filtered OpenCCU-Base report (BASE_REPORT, report.json, kept by the fork's
#                         workflow every 6 hours): the commits on the paths openccu-lite uses above the
#                         line of the fork's lite. Current: none; each one is a finding, linked. A report
#                         older than BASE_REPORT_STALE_DAYS is a note. The count links to that report.
#                         The report measures the fork's lite head (report.json "lite"): a release column
#                         whose OpenCCU-Base pin (its tag in fork-base-tags.txt) is that commit is exact;
#                         an older one shows its pin, lite's commits above the line as a lower bound, a
#                         note, and "not measured exactly" instead of the check mark.
#   The report's "supported until" column: buildroot, the kernels and the JVM as above; the
#   Raspberry Pi firmware, rpi-eeprom, HMIPServer and the OpenCCU-Base commits have no published support
#   period: their cell stays empty.
#
# The columns: one per release of the fork (RELEASES_REPO's GitHub releases): the one marked Latest, and the
# newest pre-release only when it is newer than that (by version order; an older pre-release and drafts are
# ignored). Each column reads the pins from the files at that release's tag (TreeAt: git show <tag>:<path> in
# the --root checkout, a missing tag fetched shallow), never from the branch head. Each column's cell shows
# its own status - a green check disc when that release is current; the newest-upstream and status columns,
# the findings, the ::warning:: lines and the badge are the latest release's (what stable users run); a
# pre-release's findings that the latest release does not have are listed in its cell.
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
#     gh-release-latest.json, gh-releases.json (the fork's GitHub releases), buildroot-tags.txt, rpi-tags.txt, firmware-tags.txt (git ls-remote output),
#     releases.json, releases.html, buildroot-download.html, rpi-head.txt (git ls-remote --symref HEAD), rpi-Makefile-<tag>,
#     firmware-git_hash-<commit or tag>, eeprom-versions.txt, openccu-base-tags.txt (OpenCCU/OpenCCU-Base's
#     tags, git ls-remote output), eq3-repo.json (homematicip/OpenCCU-Base), azul-aarch64.json, azul-x64.json,
#     contents-<owner>_<repo>-<ref>.json (the opt/HMServer listing), jar-<blob sha> (the jar, read by
#     range), zulu-eol.json, base-report.json
#   --today YYYY-MM-DD the date the EOL warning counts from (the tests; default today, UTC)
import argparse
import datetime
import html
import json
import os
import re
import struct
import subprocess
import sys
import urllib.request
import zlib

RPI = ["aarch64-rpi3", "aarch64-rpi4"]
VM = "x86_64-ova"
FIRMWARE_TAGS = 8

BUILDROOT_GIT = "https://github.com/buildroot/buildroot"
RPI_GIT = "https://github.com/raspberrypi/linux"
FIRMWARE_GIT = "https://github.com/raspberrypi/firmware"
RAW = "https://raw.githubusercontent.com/raspberrypi/{repo}/{ref}/{path}"
KERNEL_RELEASES = "https://www.kernel.org/releases.json"
KERNEL_EOL_PAGE = "https://www.kernel.org/category/releases.html"
EOL_WARN_MONTHS = 6
BUILDROOT_EOL_WARN_DAYS = 14         # a quarterly series: supported about four months, warn two weeks ahead
BUILDROOT_LTS_EOL_WARN_MONTHS = 6    # an LTS series: supported three years, warn six months ahead
BUILDROOT_DOWNLOAD = "https://buildroot.org/download.html"
NO_PERIOD = ("", "")   # no published support period: the cell stays empty
PAGE = "https://hobbyquaker.github.io/openccu-lite/"
BASE_UP = "OpenCCU/OpenCCU-Base"   # the OpenCCU-Base our fork follows
BASE_TAG_RE = re.compile(r"^\d+\.\d+\.\d+$")   # its version tags, e.g. 3.89.11
BASE_TAGS_SCAN = 10   # how many of its newest version tags are searched for the tag our jar comes from
GH_API = "https://api.github.com/"
GH_RAW = "https://raw.githubusercontent.com/{repo}/{ref}/{path}"
HMIP_DIR = "opt/HMServer"
HMIP_JAR = "HMIPServer.jar"
HMIP_POM = "META-INF/maven/de.eq3.cbcs.server/server-core/pom.properties"
ZULU_EOL = "https://endoflife.date/api/v1/products/azul-zulu/"
AZUL_API = "https://api.azul.com/metadata/v1/zulu/packages/"
AZUL_ARCHES = ["aarch64", "x64"]   # the architectures java-azul.mk downloads (linux_aarch64, linux_x64)
BASE_REPORT = "https://hobbyquaker.github.io/OpenCCU-Base/"
EQ3_BASE = "homematicip/OpenCCU-Base"   # eQ-3's own OpenCCU-Base repository
BASE_REPORT_STALE_DAYS = 2


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

    def api(self, path, fixture):
        """a GitHub API GET as JSON (GITHUB_TOKEN, when set, against the rate limit)"""
        try:
            return json.loads(self.http(GH_API + path, fixture))
        except ValueError as e:
            raise UpstreamError(f"{GH_API}{path}: {e}") from e

    def ranged(self, url, start, length, fixture):
        """bytes [start, start+length) of a file; start < 0 is that many bytes from its end (length ignored);
        returns (bytes, the file's size). Live with an HTTP Range request; a server that ignores it gives
        the whole file, which is kept."""
        key = "range:" + fixture
        whole = self.cache.get(key)
        if whole is None and self.fixtures:
            try:
                with open(os.path.join(self.fixtures, fixture), "rb") as f:
                    whole = self.cache[key] = f.read()
            except OSError as e:
                raise UpstreamError(f"fixture {fixture}: {e}") from e
        if whole is not None:
            size = len(whole)
            a = max(size + start, 0) if start < 0 else start
            return whole[a:size if start < 0 else a + length], size
        rng = f"bytes={start}" if start < 0 else f"bytes={start}-{start + length - 1}"
        req = urllib.request.Request(url, headers={"User-Agent": "openccu-lite-upstream-versions", "Range": rng})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
                if resp.status == 206:
                    m = re.search(r"/(\d+)$", resp.headers.get("Content-Range", ""))
                    if not m:
                        raise UpstreamError(f"{url}: a partial answer without its size")
                    return body, int(m.group(1))
        except (OSError, ValueError) as e:
            raise UpstreamError(f"{url}: {e}") from e
        self.cache[key] = body
        return self.ranged(url, start, length, fixture)

    def http(self, url, fixture):
        if fixture in self.cache:
            return self.cache[fixture]
        if self.fixtures:
            body = self._fixture(fixture)
        else:
            headers = {"User-Agent": "openccu-lite-upstream-versions"}
            token = os.environ.get("GITHUB_TOKEN")
            if token and url.startswith(GH_API):
                headers["Authorization"] = f"Bearer {token}"
            req = urllib.request.Request(url, headers=headers)
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
        self.ours = self.newest = "-"   # a string, or (en, de)
        self.newest_link = None         # the "newest" cell as a link
        self.until = NO_PERIOD
        self.findings = []   # [(en, de, link or None)]
        self.notes = []      # [(en, de)]
        self.exact = True    # False: the release's value is not measured exactly (its cell gets no check mark)

    def due(self, en, de, link=None):
        self.findings.append((en, de, link))

    def note(self, en, de):
        self.notes.append((en, de))


class TreeAt:
    """the files of the fork at a release tag (git show <tag>:<path> in the --root checkout), not its working
    tree: each report column is the release it names. A tag the checkout lacks (the workflow's shallow
    checkout) is fetched once, shallow."""

    def __init__(self, git_dir, tag):
        self.git_dir, self.tag, self.fetched = git_dir, tag, False

    def _git(self, *args):
        try:
            return subprocess.run(["git", "-C", self.git_dir, *args], capture_output=True, text=True, timeout=300,
                                  check=False, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        except (OSError, subprocess.TimeoutExpired) as e:
            raise PinError(f"git {args[0]} in {self.git_dir}: {e}") from e

    def read(self, rel):
        if not self.fetched and self._git("rev-parse", "-q", "--verify", f"refs/tags/{self.tag}").returncode != 0:
            self.fetched = True
            f = self._git("fetch", "-q", "--depth=1", "--no-tags", "origin", f"+refs/tags/{self.tag}:refs/tags/{self.tag}")
            if f.returncode != 0:
                raise PinError(f"release tag {self.tag} not in the checkout and not fetchable: {f.stderr.strip()}")
        self.fetched = True
        p = self._git("show", f"refs/tags/{self.tag}:{rel}")
        if p.returncode != 0:
            raise PinError(f"{rel} at {self.tag}: {p.stderr.strip()}")
        return p.stdout


def read(root, rel):
    if isinstance(root, TreeAt):
        return root.read(rel)
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        raise PinError(f"{rel}: {e}") from e


# ---- the releases the report has a column for

RELEASES_REPO = "hobbyquaker/openccu-lite"
SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


def semver_key(tag):
    """semantic version order: 1.1.0-dev.0 > 1.0.0 > 1.0.0-rc.4; None for a tag that is no version"""
    m = SEMVER_RE.match(tag)
    if not m:
        return None
    pre = m.group(4)
    ids = tuple((0, int(x), "") if x.isdigit() else (1, 0, x) for x in pre.split(".")) if pre else ()
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))), 0 if pre else 1, ids


def release_columns(up):
    """[(tag, "latest")] - the GitHub release marked Latest - plus (tag, "pre-release") for the newest
    pre-release when it is newer than that (by version order); older pre-releases and drafts are ignored"""
    latest = up.api(f"repos/{RELEASES_REPO}/releases/latest", "gh-release-latest.json")
    tag = latest.get("tag_name") if isinstance(latest, dict) else None
    if not tag or not semver_key(tag):
        raise UpstreamError(f"{RELEASES_REPO}: no latest release with a version tag")
    lst = up.api(f"repos/{RELEASES_REPO}/releases?per_page=50", "gh-releases.json")
    if not isinstance(lst, list):
        raise UpstreamError(f"{RELEASES_REPO}: the release list is not a list")
    pre = [x["tag_name"] for x in lst if isinstance(x, dict) and x.get("prerelease") and not x.get("draft")
           and isinstance(x.get("tag_name"), str) and semver_key(x["tag_name"])
           and semver_key(x["tag_name"]) > semver_key(tag)]
    cols = [(tag, "latest")]
    if pre:
        cols.append((max(pre, key=semver_key), "pre-release"))
    return cols


def version_of(tag):
    return tag[1:] if tag.startswith("v") else tag


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
            r.note(f"kernel {r.newest} is out (we pin {ours}) - update available, information only",
                   f"Kernel {r.newest} ist erschienen (wir: {ours}) - Update verfügbar, nur zur Information")
    series_eol(r, series, rels, kernel_eol_dates(up), up.today)
    newer_lt = sorted((x[1] for x in rels if x[0] == "longterm" and not x[2] and ver_key(x[1])[:2] > ver_key(series)),
                      key=ver_key)
    if newer_lt:
        r.note("newer longterm: " + ", ".join(newer_lt), "neuerer Longterm-Kernel: " + ", ".join(newer_lt))
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


# ---- the JVM (Azul Zulu) and HMIPServer (against the newest OpenCCU-Base version tag)

def base_tags(up):
    """OpenCCU/OpenCCU-Base's version tags, newest first"""
    t = [n for n in up.tags(f"https://github.com/{BASE_UP}", "refs/tags/*", "openccu-base-tags.txt")
         if BASE_TAG_RE.match(n)]
    if not t:
        raise UpstreamError(f"{BASE_UP}: no version tag")
    return sorted(t, key=ver_key, reverse=True)


ZULU_RE = re.compile(r"^(\d+(?:\.\d+)*)-ca-(jre|jdk)(\d+(?:\.\d+)*)$")
JAVA_MK = "buildroot-external/package/java-azul/java-azul.mk"
JAVA_VAR = r"^JAVA_AZUL_VERSION\s*=\s*(\S+)\s*$"


def zulu(v):
    """(java version, zulu version, jre|jdk) of a JAVA_AZUL_VERSION such as 21.52.203-ca-jre21.0.12.1"""
    m = ZULU_RE.match(v)
    if not m:
        return None
    return m.group(3), m.group(1), m.group(2)


def zulu_text(z):
    return f"{z[0]} (Zulu {z[1]}, {z[2].upper()})"


def zulu_eol(up, major):
    """((year, month), iseol) of endoflife.date's azul-zulu cycle `major`; None when not readable"""
    try:
        d = json.loads(up.http(ZULU_EOL, "zulu-eol.json"))
        for x in d["result"]["releases"]:
            if str(x.get("name")) == major:
                m = re.match(r"^(\d{4})-(\d{2})-\d{2}$", x.get("eolFrom") or "")
                return ((int(m.group(1)), int(m.group(2))), bool(x.get("isEol"))) if m else None
    except (UpstreamError, ValueError, KeyError, TypeError):
        return None
    return None


def azul_newest(up, major, kind, arch):
    """(java version, zulu version) of the newest GA Zulu `major` build of package type `kind` for linux_<arch>
    (glibc, tar.gz) from Azul's metadata API"""
    url = (f"{AZUL_API}?java_version={major}&os=linux&arch={arch}&archive_type=tar.gz&java_package_type={kind}"
           "&javafx_bundled=false&crac_supported=false&latest=true&release_status=ga&availability_types=CA&page_size=20")
    try:
        lst = json.loads(up.http(url, f"azul-{arch}.json"))
    except ValueError as e:
        raise UpstreamError(f"Azul's metadata API ({arch}): {e}") from e
    found = []
    for x in lst if isinstance(lst, list) else []:
        m = re.match(rf"^zulu(\d+(?:\.\d+)*)-ca-{kind}(\d+(?:\.\d+)*)-linux_{re.escape(arch)}\.tar\.gz$",
                     str(x.get("name", "")) if isinstance(x, dict) else "")
        if m and m.group(2).split(".")[0] == major:
            found.append((m.group(2), m.group(1)))
    if not found:
        raise UpstreamError(f"Azul's metadata API: no Zulu {major} {kind.upper()} for linux_{arch}")
    return max(found, key=lambda z: (ver_key(z[0]), ver_key(z[1])))


def check_jvm(root, up):
    r = Row("jvm", "JVM (Azul Zulu)", "JVM (Azul Zulu)", "https://www.azul.com/downloads/?package=jre#zulu")
    v = pin(root, JAVA_MK, JAVA_VAR, "JAVA_AZUL_VERSION")
    ours = zulu(v)
    if not ours:
        raise PinError(f"{JAVA_MK}: JAVA_AZUL_VERSION {v!r} is not <zulu>-ca-<jre|jdk><java>")
    r.ours = zulu_text(ours)
    major = ours[0].split(".")[0]
    ko = (ver_key(ours[0]), ver_key(ours[1]))
    newest = {a: azul_newest(up, major, ours[2], a) for a in AZUL_ARCHES}
    shown = sorted(set(newest.values()), key=lambda z: (ver_key(z[0]), ver_key(z[1])))
    r.newest = " / ".join(f"{z[0]} (Zulu {z[1]}, {ours[2].upper()})"
                          + ("" if len(shown) == 1 else " " + ", ".join(a for a in AZUL_ARCHES if newest[a] == z))
                          for z in shown)
    for z in shown:
        if (ver_key(z[0]), ver_key(z[1])) > ko:
            who = ", ".join(a for a in AZUL_ARCHES if newest[a] == z)
            r.due(f"Zulu {z[1]} (Java {z[0]}) is out for {who}; we pin {ours[1]} (Java {ours[0]})",
                  f"Zulu {z[1]} (Java {z[0]}) ist erschienen für {who}; wir: {ours[1]} (Java {ours[0]})")
    if all((ver_key(z[0]), ver_key(z[1])) < ko for z in shown):
        r.note("ours is newer than Azul's newest GA build", "unsere ist neuer als Azuls neuester GA-Build")
    eol = zulu_eol(up, major)
    if eol is None:
        r.until = ("unknown", "unbekannt")
        r.note(f"end of support of Zulu {major} unknown (endoflife.date not readable)",
               f"Supportende von Zulu {major} unbekannt (endoflife.date nicht lesbar)")
    elif eol[1]:
        r.until = ("end of life", "end of life")
        r.due(f"Azul Zulu {major} is end of life", f"Azul Zulu {major} ist end of life")
    else:
        eol_within(r, f"Azul Zulu {major}", f"Azul Zulu {major}", eol[0], up.today, EOL_WARN_MONTHS)
    return r


BASE_MK = "buildroot-external/package/openccu-base/openccu-base.mk"


def base_source(text):
    """(owner/repo, ref) of an openccu-base.mk: OPENCCU_BASE_VERSION and the GitHub repository of its SITE"""
    v = re.search(r"^OPENCCU_BASE_VERSION\s*=\s*(\S+)\s*$", text, re.M)
    site = re.search(r"^OPENCCU_BASE_SITE\s*=\s*(.+?)\s*$", text, re.M)
    if not v or not site:
        return None
    m = (re.match(r"^\$\(call github,([\w.-]+),([\w.-]+),", site.group(1))
         or re.match(r"^https://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/?$", site.group(1)))
    return (f"{m.group(1)}/{m.group(2)}", v.group(1)) if m else None


def jar_blob(up, repo, ref, need=True):
    """the git blob sha of the ref's HMIPServer.jar; without it an error, or None when not `need`"""
    lst = up.api(f"repos/{repo}/contents/{HMIP_DIR}?ref={ref}", f"contents-{repo.replace('/', '_')}-{ref}.json")
    for x in lst if isinstance(lst, list) else []:
        if isinstance(x, dict) and x.get("name") == HMIP_JAR and re.match(r"^[0-9a-f]{40}$", x.get("sha") or ""):
            return x["sha"]
    if need:
        raise UpstreamError(f"{repo} {ref}: no {HMIP_DIR}/{HMIP_JAR}")
    return None


def zip_member(up, url, fixture, member):
    """one member of a remote zip, read by range: the end record, the central directory, the entry; None
    when the archive has no such member or cannot be read as a plain zip"""
    tail, size = up.ranged(url, -65557, 0, fixture)
    e = tail.rfind(b"PK\x05\x06")
    if e < 0 or len(tail) < e + 22:
        return None
    cd_size, cd_off = struct.unpack("<II", tail[e + 12:e + 20])
    if cd_off + cd_size > size:
        return None
    cd, _ = up.ranged(url, cd_off, cd_size, fixture)
    want, i = member.encode(), 0
    while i + 46 <= len(cd) and cd[i:i + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[i + 10:i + 12])
        csize, usize, nlen, xlen, clen = struct.unpack("<IIHHH", cd[i + 20:i + 34])
        off, = struct.unpack("<I", cd[i + 42:i + 46])
        if cd[i + 46:i + 46 + nlen] == want:
            head, _ = up.ranged(url, off, 30, fixture)
            if head[:4] != b"PK\x03\x04":
                return None
            ln, lx = struct.unpack("<HH", head[26:30])
            data, _ = up.ranged(url, off + 30 + ln + lx, csize, fixture)
            try:
                out = data if method == 0 else zlib.decompressobj(-15).decompress(data) if method == 8 else None
            except zlib.error:
                return None
            return out if out is not None and len(out) == usize else None
        i += 46 + nlen + xlen + clen
    return None


def jar_version(up, repo, ref, blob):
    """the server-core version of the jar, or None when it has none"""
    url = GH_RAW.format(repo=repo, ref=ref, path=f"{HMIP_DIR}/{HMIP_JAR}")
    pom = zip_member(up, url, f"jar-{blob}", HMIP_POM)
    m = re.search(r"^version=(\S+)\s*$", pom.decode("utf-8", "replace"), re.M) if pom else None
    return m.group(1) if m else None


def snap(v):
    return v is not None and "SNAPSHOT" in v.upper()


def check_hmipserver(root, up):
    r = Row("hmipserver", "HMIPServer", "HMIPServer", f"https://github.com/{EQ3_BASE}")
    ours = base_source(read(root, BASE_MK))
    if not ours:
        raise PinError(f"{BASE_MK}: no OPENCCU_BASE_VERSION or no GitHub OPENCCU_BASE_SITE")
    bo = jar_blob(up, *ours)
    vo = jar_version(up, *ours, bo)
    tags = base_tags(up)
    newest = tags[0]
    bt = jar_blob(up, BASE_UP, newest)
    origin = newest if bt == bo else next((t for t in tags[1:BASE_TAGS_SCAN] if jar_blob(up, BASE_UP, t, False) == bo),
                                         None)
    if origin:
        r.ours = f"{vo or '?'} (OpenCCU-Base {origin})"
    else:
        r.ours = (f"{vo or '?'} (in no OpenCCU-Base tag)", f"{vo or '?'} (in keinem OpenCCU-Base-Tag)")
        r.note(f"our jar is in none of the {BASE_TAGS_SCAN} newest version tags of {BASE_UP}",
               f"unser Jar ist in keinem der {BASE_TAGS_SCAN} neuesten Versions-Tags von {BASE_UP}")

    # eQ-3's own repository, its default branch: shown, never a finding
    info = up.api(f"repos/{EQ3_BASE}", "eq3-repo.json")
    branch = info.get("default_branch") if isinstance(info, dict) else None
    if not branch or not re.match(r"^[\w./-]+$", branch):
        raise UpstreamError(f"{EQ3_BASE}: no default branch")
    be = jar_blob(up, EQ3_BASE, branch)
    ve = vo if be == bo else jar_version(up, EQ3_BASE, branch, be)
    if be == bo:
        eq3 = (f"{EQ3_BASE} {branch}: {vo or '?'} (the same jar)", f"{EQ3_BASE} {branch}: {vo or '?'} (dasselbe Jar)")
    else:
        mark = (" (snapshot)", " (Snapshot)") if snap(ve) else ("", "")
        eq3 = (f"{EQ3_BASE} {branch}: {ve or '?'}{mark[0]}", f"{EQ3_BASE} {branch}: {ve or '?'}{mark[1]}")
        if not ve or not vo:
            r.note(f"{EQ3_BASE} {branch} has a different jar (its version is not readable)",
                   f"{EQ3_BASE} {branch} hat ein anderes Jar (seine Version ist nicht lesbar)")
        elif ver_key(ve) > ver_key(vo):
            r.note(f"{EQ3_BASE} {branch} has a newer one: {ve}{mark[0]} - information, not a finding (see the "
                   "OpenCCU-Base report)",
                   f"{EQ3_BASE} {branch} hat einen neueren: {ve}{mark[1]} - zur Information, kein Befund (siehe "
                   "den OpenCCU-Base-Bericht)")

    # the newest OpenCCU/OpenCCU-Base version tag: a finding when ours is older
    who = f"OpenCCU-Base {newest}"
    if bt == bo:
        occu = (f"{BASE_UP} {newest}: {vo or '?'} (the same jar)", f"{BASE_UP} {newest}: {vo or '?'} (dasselbe Jar)")
    else:
        vt = jar_version(up, BASE_UP, newest, bt)
        occu = (f"{BASE_UP} {newest}: {vt or '?'}" + (" (snapshot)" if snap(vt) else ""),
                f"{BASE_UP} {newest}: {vt or '?'}" + (" (Snapshot)" if snap(vt) else ""))
        r.note(f"git blob ours {bo[:12]}, {who}'s {bt[:12]}", f"Git-Blob unserer {bo[:12]}, der von {who} {bt[:12]}")
        if not vo or not vt:
            r.due(f"{who} has a different HMIPServer.jar (its version is not readable)",
                  f"{who} hat ein anderes HMIPServer.jar (seine Version ist nicht lesbar)")
        elif ver_key(vt) > ver_key(vo) and snap(vt):
            r.due(f"{who} has a newer HMIPServer, a snapshot: {vt} (ours: {vo}) - see the OpenCCU-Base report",
                  f"{who} hat einen neueren HMIPServer, einen Snapshot: {vt} (unserer: {vo}) - siehe den "
                  "OpenCCU-Base-Bericht", BASE_REPORT)
        elif ver_key(vt) > ver_key(vo):
            r.due(f"{who} has a newer HMIPServer: {vt} (ours: {vo})",
                  f"{who} hat einen neueren HMIPServer: {vt} (unserer: {vo})")
        elif ver_key(vt) == ver_key(vo):
            r.note(f"{who}: a different build of the same version", f"{who}: ein anderer Build derselben Version")
        else:
            r.note(f"{who} has an older one", f"{who} hat einen älteren")
    r.newest = (f"{eq3[0]} · {occu[0]}", f"{eq3[1]} · {occu[1]}")
    return r


# ---- OpenCCU-Base: relevant commits above our line

def check_base_commits(root, up):
    r = Row("openccu-base-commits", "OpenCCU-Base commits above our line",
            "OpenCCU-Base-Commits über unserer Linie", BASE_REPORT)
    try:
        d = json.loads(up.http(BASE_REPORT + "report.json", "base-report.json"))
        above, line = d["above"], d["boundary"]
        if not isinstance(above, list) or not all(isinstance(c, dict) and c.get("subject") and c.get("url")
                                                  for c in above):
            raise ValueError("above is not a list of commits")
    except (ValueError, KeyError, TypeError) as e:
        raise UpstreamError(f"the OpenCCU-Base report's report.json: {e}") from e
    # the report measures the fork's lite head; a release that pins that very commit gets its line, an older
    # one (its OpenCCU-Base tag elsewhere) gets lite's commits above the line as a lower bound, said so
    src = base_source(read(root, BASE_MK))
    if not src:
        raise PinError(f"{BASE_MK}: no OPENCCU_BASE_VERSION or no GitHub OPENCCU_BASE_SITE")
    repo, ref = src
    pinned = ref if re.match(r"^[0-9a-f]{40}$", ref) else \
        up.tags(f"https://github.com/{repo}", "refs/tags/*", "fork-base-tags.txt").get(ref)
    if not pinned:
        raise UpstreamError(f"{repo}: no tag {ref}")
    lite = str(d.get("lite") or "")
    r.exact = pinned == lite
    if not r.exact:
        r.ours = (f"OpenCCU-Base {ref} ({pinned[:10]}), not lite's line ({lite[:10] or '?'})",
                  f"OpenCCU-Base {ref} ({pinned[:10]}), nicht die Linie von lite ({lite[:10] or '?'})")
        r.note(f"the OpenCCU-Base report measures the fork's lite ({lite[:10] or '?'}); this release pins {ref} "
               f"({pinned[:10]}): at least the commits above lite's line are missing in it, not counted exactly",
               f"der OpenCCU-Base-Bericht misst den lite des Forks ({lite[:10] or '?'}); dieses Release verwendet "
               f"{ref} ({pinned[:10]}): mindestens die Commits über der Linie von lite fehlen darin, nicht genau gezählt")
    elif line:
        r.ours = (f"lite at: {line.get('subject', '?')} ({str(line.get('date', ''))[:10]})",
                  f"lite bei: {line.get('subject', '?')} ({str(line.get('date', ''))[:10]})")
    else:
        r.ours = ("lite has no upstream commit of main", "lite hat keinen Upstream-Commit von main")
    r.newest = (f"{len(above)} commit(s) above the line", f"{len(above)} Commit(s) über der Linie")
    r.newest_link = BASE_REPORT
    for c in above:
        when = str(c.get("date", ""))[:10]
        r.due(f"not taken yet: {when} {c['subject']}", f"noch nicht übernommen: {when} {c['subject']}", c["url"])
    gen = re.match(r"^(\d{4}-\d{2}-\d{2})", str(d.get("generated", "")))
    if not gen:
        r.note("the report has no generation date", "der Bericht hat kein Erstellungsdatum")
    elif (up.today - datetime.date.fromisoformat(gen.group(1))).days > BASE_REPORT_STALE_DAYS:
        r.note(f"the OpenCCU-Base report is from {gen.group(1)}", f"der OpenCCU-Base-Bericht ist vom {gen.group(1)}")
    return r


CHECKS = [check_buildroot, check_rpi_kernel, check_vm_kernel, check_rpi_firmware, check_rpi_eeprom,
          check_jvm, check_hmipserver, check_base_commits]


# ---- output

CSS = """
:root{--bg:#fff;--fg:#1f2328;--muted:#59636e;--line:#d1d9e0;--ok:#1a7f37;--due:#9a6700;--err:#cf222e;--head:#f6f8fa}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#9198a1;--line:#3d444d;--ok:#3fb950;
--due:#d29922;--err:#f85149;--head:#151b23}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;margin:0;padding:24px 16px}
main{max-width:960px;margin:0 auto}h1{font-size:1.5em;margin:0 0 4px}p{color:var(--muted);margin:4px 0 16px}
a{color:inherit}.wrap{overflow-x:auto}table{border-collapse:collapse;width:100%}
th,td{border:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}th{background:var(--head)}
.ok{color:var(--ok);font-weight:600}.ck{display:inline-block;width:16px;height:16px;flex:none;vertical-align:-3px;margin-left:4px}
.ck circle{fill:var(--ok)}.ck path{fill:none;stroke:#fff;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}.due{color:var(--due);font-weight:600}.err{color:var(--err);font-weight:600}
ul{margin:4px 0 0;padding-left:18px}.note{color:var(--muted)}
"""

TEXT = {
    "en": {"title": "openccu-lite: upstream versions", "comp": "Component", "newest": "newest upstream",
           "until": "supported until", "status": "Status", "ok": "up to date", "due": "update available", "inexact": "not measured exactly", "checked": "Checked",
           "run": "workflow run", "lang": ("Deutsch", "index.html"), "failed": "Check failed",
           "intro": "Daily comparison of the versions openccu-lite pins with their upstream releases: one column for the "
                    "latest release, and one for the newest pre-release when there is one; the status is the latest "
                    "release's. "
                    "The rules are in scripts/lite-upstream-versions.py.",
           "base": ("What OpenCCU-Base changed in the components openccu-lite uses, and where our fork stands:",
                    "the OpenCCU-Base commit report")},
    "de": {"title": "openccu-lite: Upstream-Versionen", "comp": "Komponente", "newest": "neueste upstream",
           "until": "Support bis", "status": "Status", "ok": "aktuell", "due": "Update verfügbar", "inexact": "nicht genau gemessen", "checked": "Geprüft",
           "run": "Workflow-Lauf", "lang": ("English", "en.html"), "failed": "Prüfung fehlgeschlagen",
           "intro": "Täglicher Vergleich der Versionen, die openccu-lite verwendet, mit ihren Upstream-Releases: eine Spalte "
                    "für das neueste Release und eine für das neueste Pre-Release, wenn es eines gibt; der Status ist "
                    "der des neuesten Releases. "
                    "Die Regeln stehen in scripts/lite-upstream-versions.py.",
           "base": ("Was OpenCCU-Base an den Komponenten geändert hat, die openccu-lite verwendet, und wo unser Fork steht:",
                    "der OpenCCU-Base-Commit-Bericht")},
}


def loc(x, li):
    """a cell that is one string, or (en, de)"""
    return x[li] if isinstance(x, tuple) else x


def col_head(tag, kind):
    """the release column's header, the same in both languages (the maintainer's wording)"""
    return f"openccu-lite {version_of(tag)} ({kind})"


def ok_icon(label):
    """a white check mark on a green disc, inline: the same 16 px box in every current cell"""
    a = html.escape(label)
    return (f'<svg class="ck" role="img" aria-label="{a}" viewBox="0 0 16 16" width="16" height="16">'
            f'<title>{a}</title><circle cx="8" cy="8" r="8"/><path d="M4.4 8.3l2.4 2.4 4.8-5"/></svg>')


def components(cols):
    """per component the rows of every column, [(row of the latest release, row of the pre-release)...]"""
    return list(zip(*(rows for _, _, rows in cols)))


def until_text(cols, rs, li):
    """the support column: the latest release's; both when the pre-release's differs"""
    if len(rs) > 1 and rs[1].until != rs[0].until:
        return " · ".join(f"{version_of(c[0])}: {r.until[li] or '-'}" for c, r in zip(cols, rs))
    return rs[0].until[li]


def page(lang, cols, error, when, run_url):
    t, e = TEXT[lang], html.escape
    li = 0 if lang == "en" else 1
    out = [f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           f"<title>{e(t['title'])}</title><style>{CSS}</style></head><body><main>",
           f"<h1>{e(t['title'])}</h1>",
           f"<p>{e(t['intro'])}</p>",
           f'<p>{e(t["base"][0])} <a href="{e(BASE_REPORT)}">{e(t["base"][1])}</a>.</p>',
           f"<p>{e(t['checked'])}: {e(when)}"
           + (f' · <a href="{e(run_url)}">{e(t["run"])}</a>' if run_url else "")
           + f' · <a href="{t["lang"][1]}">{t["lang"][0]}</a></p>']
    if error:
        out.append(f'<p class="err">{e(t["failed"])}: {e(error)}</p>')
    else:
        status = t["status"] + (f" ({version_of(cols[0][0])})" if len(cols) > 1 else "")
        out.append(f'<div class="wrap"><table><tr><th>{e(t["comp"])}</th>'
                   + "".join(f"<th>{e(col_head(tag, kind))}</th>" for tag, kind, _ in cols)
                   + f'<th>{e(t["newest"])}</th><th>{e(t["until"])}</th><th>{e(status)}</th></tr>')
        for rs in components(cols):
            r = rs[0]
            st = f'<span class="due">{e(t["due"])}</span>' if r.findings else f'<span class="ok">{e(t["ok"])}</span>'
            items = [f'<li><a href="{e(f[2])}">{e(f[li])}</a></li>' if f[2] else f"<li>{e(f[li])}</li>"
                     for f in r.findings] + [f'<li class="note">{e(n[li])}</li>' for n in r.notes]
            name = r.en if lang == "en" else r.de
            newest = (f'<a href="{e(r.newest_link)}">{e(loc(r.newest, li))}</a>' if r.newest_link
                      else e(loc(r.newest, li)))
            cells = []
            for c in rs:
                if not c.findings and not c.exact:
                    mark = f' <span class="note">{e(t["inexact"])}</span>'
                elif not c.findings:
                    mark = " " + ok_icon(t["ok"])
                else:
                    mark = f' <span class="due">{e(t["due"])}</span>'
                    if c is not r:   # a pre-release's own findings, where they are not the latest's
                        own = [f for f in c.findings if f[0] not in {x[0] for x in r.findings}]
                        mark += ("<ul>" + "".join(f'<li><a href="{e(f[2])}">{e(f[li])}</a></li>' if f[2]
                                                  else f"<li>{e(f[li])}</li>" for f in own) + "</ul>") if own else ""
                cells.append(f"<td>{e(loc(c.ours, li))}{mark}</td>")
            out.append(f'<tr><td><a href="{e(r.link)}">{e(name)}</a></td>{"".join(cells)}<td>{newest}</td>'
                       f"<td>{e(until_text(cols, rs, li))}</td><td>{st}"
                       + (f"<ul>{''.join(items)}</ul>" if items else "") + "</td></tr>")
        out.append("</table></div>")
    out.append("</main></body></html>\n")
    return "\n".join(out)


def write_site(d, cols, error):
    os.makedirs(d, exist_ok=True)
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    run_url = None
    if os.environ.get("GITHUB_RUN_ID") and os.environ.get("GITHUB_REPOSITORY"):
        run_url = (f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}"
                   f"/actions/runs/{os.environ['GITHUB_RUN_ID']}")
    for lang, name in (("de", "index.html"), ("en", "en.html")):
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(page(lang, cols, error, when, run_url))
    # the badge follows the latest release (what stable users run), never the pre-release
    if error:
        badge = ("check failed", "lightgrey")
    elif any(r.findings for r in cols[0][2]):
        badge = ("updates available", "yellow")
    else:
        badge = ("up to date", "brightgreen")
    with open(os.path.join(d, "badge.json"), "w", encoding="utf-8") as f:
        json.dump({"schemaVersion": 1, "label": "upstream versions", "message": badge[0], "color": badge[1]}, f)
        f.write("\n")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."),
                    help="the fork's git checkout; each release column reads the files at its tag")
    ap.add_argument("--fixtures")
    ap.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"))
    ap.add_argument("--site")
    ap.add_argument("--today", type=datetime.date.fromisoformat, help="the date the EOL warning counts from (tests)")
    a = ap.parse_args(argv)
    up = Upstream(a.fixtures, a.today)
    cols, error, code = [], None, 0
    try:
        for tag, kind in release_columns(up):
            tree = TreeAt(a.root, tag)
            cols.append((tag, kind, [check(tree, up) for check in CHECKS]))
    except UpstreamError as e:
        error, code = f"upstream unreachable or not parseable - nothing was checked: {e}", 3
    except PinError as e:
        error, code = f"pin not found: {e}", 2
    except Exception as e:  # noqa: BLE001 - a bug here still gives a grey badge, not a stale one
        error, code = f"the check itself failed: {e!r}", 4
    if a.site:
        write_site(a.site, cols, error)
    if error:
        print(f"::error::{error}")
        if a.summary:
            with open(a.summary, "a", encoding="utf-8") as f:
                f.write(f"## Upstream versions\n\n**Check failed:** {error}\n")
        return code

    heads = [col_head(tag, kind) for tag, kind, _ in cols]
    status = "status" + (f" ({version_of(cols[0][0])})" if len(cols) > 1 else "")
    head = ("component", *heads, "newest", "supported until", status)
    tab = [(rs[0].en, *(loc(r.ours, 0) for r in rs), loc(rs[0].newest, 0), until_text(cols, rs, 0),
            "update available" if rs[0].findings else "up to date") for rs in components(cols)]
    n = len(head)
    w = [max(len(x[i]) for x in tab + [head]) for i in range(n)]
    for x in [head] + tab:
        print("  ".join(c.ljust(w[i]) for i, c in enumerate(x)).rstrip())
    due = [f"{r.en}: {f[0]}" + (f" {f[2]}" if f[2] else "") for r in cols[0][2] for f in r.findings]
    for r in cols[0][2]:
        for nt in r.notes:
            print(f"note - {r.en}: {nt[0]}")
    for d in due:
        print(f"::warning::update available - {d}")
    pre_due = []
    if len(cols) > 1:
        v = version_of(cols[1][0])
        for r0, r1 in zip(cols[0][2], cols[1][2]):
            pre_due += [f"{r1.en}: {f[0]}" for f in r1.findings if f[0] not in {x[0] for x in r0.findings}]
        for d in pre_due:
            print(f"note - pre-release {v}: {d}")
    if a.summary:
        with open(a.summary, "a", encoding="utf-8") as f:
            f.write("## Upstream versions\n\n| " + " | ".join(("component", *heads, "newest upstream", "supported until",
                                                              status)) + " |\n|" + " --- |" * n + "\n")
            for x in tab:
                f.write("| " + " | ".join(x) + " |\n")
            f.write("\n" + (f"**{len(due)} finding(s).**\n" if due else "**All current.**\n"))
            for d in due:
                f.write(f"- {d}\n")
            if pre_due:
                f.write(f"\nOnly in the pre-release {version_of(cols[1][0])}:\n")
                for d in pre_due:
                    f.write(f"- {d}\n")
            f.write(f"\nReport: {PAGE}\nOpenCCU-Base commit report: {BASE_REPORT}\n")
    print(f"\n{len(due)} finding(s)" if due else "\nall current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
