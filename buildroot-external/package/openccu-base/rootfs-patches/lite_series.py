#!/usr/bin/env python3
"""Write the part of the rootfs patch series that applies to the OpenCCU-Base openccu-lite builds.

Usage: lite_series.py PATCH_DIR OUTPUT_DIR

openccu-lite builds from OpenCCU-Base pruned to openccu-base-paths.txt, without the WebUI sources
and without HMServer's FreeMarker pages (tasks 329, 335), so build/rootfs has no opt/HMServer/pages/ to patch and,
of the WebUI's www/ tree, only what openccu-lite ships at the CCU's paths for addons (task 331):
the device pictures (www/config/img/devices/), DEVDB.tcl, stringtable_de.txt and the
translate.lang*.js files (KEPT_WWW). Nothing else of www/ would reach the image (openccu-lite's
overlay brings its own four group pages). The series stays as OpenCCU keeps it; this script
copies every patch in `series` order to OUTPUT_DIR with only its file sections whose target is
outside those trees or one of the kept www/ files, drops patches left empty, and writes
OUTPUT_DIR/series. Hunks are parsed by their line counts, so a removed
line that itself starts with "-- " is never mistaken for a file header.
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
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    patch_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=False)
    names = [line.strip() for line in (patch_dir / "series").read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    kept = []
    for name in names:
        parts = [body for path, body in sections((patch_dir / name).read_bytes())
                 if applies(path)]
        if parts:
            (out_dir / name).write_bytes(b"".join(parts))
            kept.append(name)
    (out_dir / "series").write_text("".join(n + "\n" for n in kept))
    print("lite_series: %d of %d patches touch files openccu-lite builds from: %s"
          % (len(kept), len(names), " ".join(kept)))


if __name__ == "__main__":
    main()
