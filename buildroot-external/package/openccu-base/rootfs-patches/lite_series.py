#!/usr/bin/env python3
"""Check that the rootfs patch series changes only what openccu-lite builds and ships.

Usage: lite_series.py PATCH_DIR

openccu-lite builds from OpenCCU-Base pruned to openccu-base-paths.txt, without the WebUI sources
and without HMServer's FreeMarker pages (tasks 329, 335), so build/rootfs has no opt/HMServer/pages/
to patch and, of the WebUI's www/ tree, only what openccu-lite ships at the CCU's paths for addons
(task 331): the device pictures (www/config/img/devices/), DEVDB.tcl, stringtable_de.txt and the
translate.lang*.js files (KEPT_WWW). Until task 389 this script cut OpenCCU's complete series down
to those sections at build time; since then the series in PATCH_DIR holds exactly those sections
(tasks 388, 389) and the build applies it as it is. This script is the guard that keeps it so: it
fails when a patch has a section on any other file (an upstream merge that brings a WebUI change
is named instead of failing later in the build, or being dropped without a word) or no section
at all. Hunks are parsed by their line counts, so a removed line that itself starts with "-- " is
never mistaken for a file header.
"""
import re
import sys
from pathlib import Path

SKIPPED = ("www/", "opt/HMServer/pages/")
# what openccu-base.mk stages and installs of www/ (task 331); the post-build guard allows exactly this
KEPT_WWW = re.compile(r"^www/(config/img/devices/(50|250)/|config/devdescr/DEVDB\.tcl$"
                      r"|config/stringtable_de\.txt$|webui/js/lang/[^/]+/translate\.lang[^/]*\.js$)")


def applies(path):
    return path is not None and (not path.startswith(SKIPPED) or bool(KEPT_WWW.match(path)))
HUNK = re.compile(rb"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


def target_path(header):
    path = header[4:].split(b"\t")[0].strip()
    if path == b"/dev/null":
        return None
    return re.sub(rb"^[ab]/", b"", path).decode("utf-8", "replace")


def sections(data):
    """Yield (target path, section bytes) per file of a unified diff."""
    # split on LF only: some patched files carry CRs inside their lines
    lines = re.findall(rb"[^\n]*\n|[^\n]+$", data)
    i = 0
    while i < len(lines):
        if not (lines[i].startswith(b"--- ") and i + 1 < len(lines)
                and lines[i + 1].startswith(b"+++ ")):
            i += 1  # text between sections (none in this stack) is dropped
            continue
        start = i
        old, new = lines[i], lines[i + 1]
        i += 2
        while i < len(lines):
            m = HUNK.match(lines[i])
            if not m:
                break
            old_left = int(m.group(1) or b"1")
            new_left = int(m.group(2) or b"1")
            i += 1
            while (old_left > 0 or new_left > 0) and i < len(lines):
                tag = lines[i][:1]
                if tag == b" ":
                    old_left -= 1
                    new_left -= 1
                elif tag == b"-":
                    old_left -= 1
                elif tag == b"+":
                    new_left -= 1
                elif tag != b"\\":
                    raise SystemExit("malformed hunk at line %d" % (i + 1))
                i += 1
            while i < len(lines) and lines[i].startswith(b"\\"):
                i += 1  # "\ No newline at end of file"
        path = target_path(new) or target_path(old)
        yield path, b"".join(lines[start:i])


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    patch_dir = Path(sys.argv[1])
    names = [line.strip() for line in (patch_dir / "series").read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    errors = []
    for name in names:
        paths = [path for path, _ in sections((patch_dir / name).read_bytes())]
        if not paths:
            errors.append("%s: no file section" % name)
        errors += ["%s: changes %s, which openccu-lite does not build or ship" % (name, path)
                   for path in paths if not applies(path)]
    if errors:
        raise SystemExit("lite_series: ERROR:\n  " + "\n  ".join(errors))
    print("lite_series: all %d patches change only files openccu-lite builds and ships" % len(names))

if __name__ == "__main__":
    main()
