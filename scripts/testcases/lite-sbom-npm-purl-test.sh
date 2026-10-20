#!/bin/sh
# openccu-lite: scripts/lite-sbom.py writes npm purls by the purl spec (B-325). A scoped name's
# scope is the namespace with its '@' percent-encoded: pkg:npm/%40primer/octicons@19.15.0, not
# pkg:npm/@primer/octicons@19.15.0, which SBOM consumers may read as a version separator.
#
# 1. npm_purl() on a plain name, a scoped name, a pre-release version and a build-metadata version.
# 2. occulited()'s UI bundle components (from a made-up bundle-licenses.json) carry the encoded
#    purl and bom-ref, and the name stays as npm spells it.
#
# Usage: sh scripts/testcases/lite-sbom-npm-purl-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SBOM="$HERE/scripts/lite-sbom.py"
[ -f "$SBOM" ] || { echo "$SBOM not found"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

cat > "$T/t.py" <<'PY'
import importlib.util, json, os, sys
s = importlib.util.spec_from_file_location("s", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
for name, ver in (("svelte", "5.1.0"), ("@primer/octicons", "19.15.0"), ("@scope/pkg", "1.0.0-beta.1"),
                  ("x", "1.0.0+build.5"), ("@a/b", "")):
    print(m.npm_purl(name, ver))
# occulited()'s UI bundle, on a made-up package dir
d = os.path.join(sys.argv[2], "occulited")
os.makedirs(os.path.join(d, "internal", "ui"))
with open(os.path.join(d, "internal", "ui", "bundle-licenses.json"), "w") as f:
    json.dump({"packages": [{"name": "@primer/octicons", "version": "19.15.0", "license": "MIT", "text": "MIT License"}]}, f)
class B:
    root = sys.argv[2]
    def pkgdir(self, name): return d
m.package = lambda texts, b, name: {"name": name, "version": "0123456789abcdef"}
m.licences = lambda texts, expr, text=None: []
errors = []
c = m.occulited(None, B(), errors)
n = [x for x in c["components"] if x["name"] == "@primer/octicons"][0]
print(n["purl"], n["bom-ref"], n["name"], errors)
PY
out=$(python3 "$T/t.py" "$SBOM" "$T" 2>&1)
exp='pkg:npm/svelte@5.1.0
pkg:npm/%40primer/octicons@19.15.0
pkg:npm/%40scope/pkg@1.0.0-beta.1
pkg:npm/x@1.0.0%2Bbuild.5
pkg:npm/%40a/b
pkg:npm/%40primer/octicons@19.15.0 pkg:npm/%40primer/octicons@19.15.0 @primer/octicons []'
if [ "$out" = "$exp" ]; then ok "npm purls by the spec"; else fail "npm purls"; echo "$out"; fi

echo "--- $fails failure(s)"
[ "$fails" = 0 ]
