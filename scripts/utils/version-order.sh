#!/bin/bash
# openccu-lite: the order of our version tags, where a script has to choose one. sort -V is alphabetical on
# the pre-release word, so v1.1.0-dev.6 would pass v1.1.0-beta.0. The order here is
# dev < alpha < beta < rc < release, any other word below dev, and numbers compared as numbers
# (scripts/lite-upstream-versions.py's semver_key, internal/prerelease in occulited; a test compares this
# with semver_key).

# newest_version_tag: the newest of the tags read from stdin, one per line ([v]X.Y.Z[-pre]); a line that is
# no version is ignored; prints nothing when none is left.
function newest_version_tag() {
  python3 -c '
import re, sys
RANK = {"dev": 1, "alpha": 2, "beta": 3, "rc": 4}
def key(tag):
    m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$", tag)
    if not m:
        return None
    pre = m.group(4)
    ids = tuple((0, int(x), "") if x.isdigit() else (1, RANK.get(x, 0), x) for x in pre.split(".")) if pre else ()
    return tuple(int(x) for x in m.groups()[:3]), 0 if pre else 1, ids
tags = [t for t in sys.stdin.read().split() if key(t)]
if tags:
    print(max(tags, key=key))
'
}
