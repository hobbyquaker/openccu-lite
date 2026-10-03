#!/bin/bash
# openccu-lite: put a checked dev round on GitHub as a draft release (lite-only file).
#
#   scripts/lite-release-github.sh [--dry-run] <version> <commit>
#
# The release is not built here. A release is the dev round of the same version: the round script
# builds 1.0.0-dev.<N> in the build host's warm trees (as root, holding /ssd/build/.release.lock), the
# lab checks that round, and its files are what goes out - bit for bit what the lab saw. This script,
# run by lite-release.yml on the tag, checks that the round in $TREE is the tagged commit and version,
# and then:
#   - checks that GitHub's main contains the commit (the lite -> main push is the guard script's,
#     never this job's: the token cannot push);
#   - takes per product the update zip, the .ova (x86_64-ova) or the in-place -ccu3.tgz
#     (aarch64-rpi3), the image's SBOM, each with its .sha256; never the raw .img (over GitHub's
#     2 GiB per asset, and inside the zip);
#   - takes the pinned occulited's API documents (OpenAPI, AsyncAPI, lite-rpc's method catalogue)
#     from its source in the build tree, with their versions set, each with its .sha256;
#   - writes SHA256SUMS over all of them;
#   - creates the draft release v<version> on the commit (a prerelease while the version has one),
#     its body a short header plus GitHub's generated notes, and uploads every file: an asset of the
#     same name is deleted first, three tries, and the uploaded size and GitHub's sha256 digest must
#     match the local file.
# No sources archive: the sources are available on request (decision of 2026-09-25).
# Needs: GH_TOKEN (a fine-grained token for hobbyquaker/openccu-lite, Contents read and write),
# curl, python3, sha256sum. --dry-run does every local check and the read-only GitHub checks, and
# writes nothing to GitHub.
#
# Environment (defaults for the build host): TREE (/ssd/build/openccu-lite-3899), PRODUCTS
# ("aarch64-rpi3 aarch64-rpi4 x86_64-ova"), GH_REPO (hobbyquaker/openccu-lite), GH_API
# (https://api.github.com), GH_UPLOADS (https://uploads.github.com), STAGE (a new temporary directory).
set -euo pipefail

dry=0
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
[ $# -eq 2 ] || { echo "usage: $0 [--dry-run] <version> <commit>" >&2; exit 2; }
V="$1"
SHA="$2"
TREE="${TREE:-/ssd/build/openccu-lite-3899}"
PRODUCTS="${PRODUCTS:-aarch64-rpi3 aarch64-rpi4 x86_64-ova}"
GH_REPO="${GH_REPO:-hobbyquaker/openccu-lite}"
GH_API="${GH_API:-https://api.github.com}"
GH_UPLOADS="${GH_UPLOADS:-https://uploads.github.com}"
STAGE="${STAGE:-$(mktemp -d)}"
TAG="v$V"

fail() { echo "lite-release-github: ERROR: $*" >&2; exit 1; }
say() { echo "lite-release-github: $*"; }

# ---- the version and the commit -----------------------------------------------------------------
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || fail "commit '$SHA' is not a full sha"
L=$(git show "$SHA:LITE-VERSION" | sed -n 's/^VERSION=//p')
BASE=$(git show "$SHA:LITE-VERSION" | sed -n 's/^BASE=//p')
case "$V" in
  "$L") ;;
  "$L".[0-9]*) [[ "${V#"$L".}" =~ ^[0-9]+$ ]] || fail "version $V is not $L or $L.<N>" ;;
  *) fail "version $V does not match LITE-VERSION ($L) of $SHA" ;;
esac
PRE=false
[[ "$V" == *-* ]] && PRE=true
PIN=$(git show "$SHA:buildroot-external/package/occulited/occulited.mk" | sed -n 's/^OCCULITED_VERSION *= *//p')
[ -n "$PIN" ] || fail "no occulited pin in $SHA"
# occulited is versioned like the image (occulited task 9): the round tagged the pinned commit v$V and
# the pin carries the release; a pin from before that carries none, and occulited's version is its commit
OREL=$(git show "$SHA:buildroot-external/package/occulited/occulited.mk" | sed -n 's/^OCCULITED_RELEASE *= *//p')
[ -z "$OREL" ] || [ "$OREL" = "$V" ] || fail "occulited's pin in $SHA says release $OREL, not $V"
OVER="${OREL:-$PIN}"
say "release $TAG from $SHA (base $BASE, occulited ${OREL:+$OREL at }$PIN, prerelease $PRE), products: $PRODUCTS"

# ---- the round in the warm tree is this commit and this version --------------------------------
[ -d "$TREE/.git" ] || fail "$TREE is not the build tree"
HEAD=$(git -C "$TREE" rev-parse HEAD)
[ "$HEAD" = "$SHA" ] || fail "the build tree is at $HEAD, not at $SHA: run the dev round for $V from this commit first"
mkdir -p "$STAGE"
: > "$STAGE/assets"
for P in $PRODUCTS; do
  T="$TREE/build-$P/target"
  lite=$(sed -n 's/^LITE=//p' "$T/VERSION")
  [ "$lite" = "$V" ] || fail "$P: the image says LITE=$lite, not $V"
  gunzip -c "$T/usr/share/openccu-lite/sbom.cdx.json.gz" > "$STAGE/openccu-lite-$P-$V.cdx.json"
  python3 - "$STAGE/openccu-lite-$P-$V.cdx.json" "$V" "$PIN" "$P" <<'PY' || fail "$P: the SBOM is not this round's"
import json, sys
d = json.load(open(sys.argv[1]))
v, pin, product = sys.argv[2], sys.argv[3], sys.argv[4]
comp = d["metadata"]["component"]
props = {p["name"]: p["value"] for p in comp.get("properties", [])}
assert comp["version"] == v, ("version", comp["version"])
assert props.get("openccu-lite:product") == product, ("product", props)
occ = [c for c in d["components"] if c.get("name") == "occulited"]
assert occ and occ[0]["bom-ref"] == "occulited@" + pin, ("occulited", occ[:1])
PY
  (cd "$STAGE" && sha256sum "openccu-lite-$P-$V.cdx.json" > "openccu-lite-$P-$V.cdx.json.sha256")
  files="openccu-lite-$P-$V.zip"
  case "$P" in
    x86_64-ova) files="$files openccu-lite-$P-$V.ova" ;;
    aarch64-rpi3) files="$files openccu-lite-$P-$V-ccu3.tgz" ;;
  esac
  for f in $files; do
    if [ ! -f "$TREE/release/$f" ] || [ ! -f "$TREE/release/$f.sha256" ]; then fail "$P: $f or its .sha256 is missing in $TREE/release"; fi
    (cd "$TREE/release" && sha256sum -c --quiet "$f.sha256") || fail "$P: $f does not match its .sha256"
    printf '%s\n%s\n' "$TREE/release/$f" "$TREE/release/$f.sha256" >> "$STAGE/assets"
  done
  printf '%s\n%s\n' "$STAGE/openccu-lite-$P-$V.cdx.json" "$STAGE/openccu-lite-$P-$V.cdx.json.sha256" >> "$STAGE/assets"
done

# ---- occulited's API documents (task 298): from the pinned occulited's source in the build tree ----
# docs/openapi.json, docs/asyncapi.json and docs/lite-rpc-methods.json are generated in occulited's
# repository and checked by its CI; the release carries the pinned commit's, with the version the
# system serves (occulited's version: the release, or the commit for a pin without one) and the release's.
set -- $PRODUCTS
OSRC="$TREE/build-$1/build/occulited-$PIN/docs"
DOCS="openapi asyncapi lite-rpc-methods"
if [ ! -f "$OSRC/openapi.json" ]; then
  # a pin from before occulited had them: the release goes out without
  [ -d "$OSRC" ] || fail "occulited $PIN's source is not in $TREE/build-$1/build"
  say "occulited $PIN has no API documents (older than task 298): none attached"
  DOCS=""
fi
for d in $DOCS; do
  [ -f "$OSRC/$d.json" ] || fail "occulited $PIN has no docs/$d.json in $OSRC"
  python3 - "$OSRC/$d.json" "$STAGE/occulited-$d-$V.json" "$OVER" "$V" <<'PY' || fail "occulited's docs/$d.json is not a document"
import json, sys
src, dst, pin, v = sys.argv[1:5]
d = json.load(open(src))
if "info" in d:  # OpenAPI, AsyncAPI
    assert d["info"]["version"] == "dev", d["info"]["version"]
    d["info"]["version"] = pin
    d["info"]["x-openccu-lite"] = v
else:  # the method catalogue
    assert "methods" in d and "tiers" in d
    d["occulited"] = pin
    d["openccu-lite"] = v
with open(dst, "w") as f:
    json.dump(d, f, indent=2, sort_keys=True, ensure_ascii=False)
    f.write("\n")
PY
  (cd "$STAGE" && sha256sum "occulited-$d-$V.json" > "occulited-$d-$V.json.sha256")
  printf '%s\n%s\n' "$STAGE/occulited-$d-$V.json" "$STAGE/occulited-$d-$V.json.sha256" >> "$STAGE/assets"
done
while read -r f; do (cd "$(dirname "$f")" && sha256sum "$(basename "$f")"); done < "$STAGE/assets" > "$STAGE/SHA256SUMS"
echo "$STAGE/SHA256SUMS" >> "$STAGE/assets"
say "$(wc -l < "$STAGE/assets") assets, $(tr '\n' '\0' < "$STAGE/assets" | du -chL --files0-from=- | tail -1 | cut -f1) in total:"
sed 's|.*/|  |' "$STAGE/assets"

# ---- GitHub ---------------------------------------------------------------------------------------
api() { # method path [curl args...] -> body on stdout, fails on HTTP >= 400
  # on an error GitHub's own message goes to stderr (never the token), so a 403 says why
  local m="$1" p="$2" out rc; shift 2
  out=$(curl -sS --fail-with-body -X "$m" -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@" "$GH_API$p") && rc=0 || rc=$?
  if [ "$rc" != 0 ]; then
    printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw); msg = d.get("message", ""); doc = d.get("documentation_url", ""); errs = d.get("errors", "")
except Exception:
    msg, doc, errs = raw[:300], "", ""
print("lite-release-github: GitHub " + sys.argv[1] + " " + sys.argv[2] + ": " + str(msg) + (" " + str(errs) if errs else "") + (" (" + doc + ")" if doc else ""), file=sys.stderr)
' "$m" "$p"
    return "$rc"
  fi
  printf '%s' "$out"
}
[ -n "${GH_TOKEN:-}" ] || { [ "$dry" = 1 ] && { say "dry run without GH_TOKEN: GitHub not asked"; exit 0; }; fail "GH_TOKEN is not set"; }

cmp=$(api GET "/repos/$GH_REPO/compare/$SHA...main") || fail "GitHub does not know $SHA: push lite to main with the guard script first"
python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["status"] in ("identical","ahead") and d["behind_by"]==0 else 1)' <<< "$cmp" \
  || fail "GitHub's main does not contain $SHA"
say "GitHub's main contains $SHA"

# occulited's tag goes to GitHub with the release, before it: the notes link it
if [ -n "$OREL" ]; then
  OREPO="${OCCULITED_REPO:-hobbyquaker/occulited}"
  oref=$(api GET "/repos/$OREPO/git/ref/tags/v$OREL") || fail "$OREPO has no tag v$OREL on GitHub: push occulited's tag first"
  otarget=$(python3 -c '
import json, sys
o = json.load(sys.stdin)["object"]
print(o["type"], o["sha"])' <<< "$oref")
  if [ "${otarget%% *}" = tag ]; then
    otag=$(api GET "/repos/$OREPO/git/tags/${otarget#* }") || fail "$OREPO's tag object v$OREL cannot be read"
    otarget=$(python3 -c 'import json,sys; o=json.load(sys.stdin)["object"]; print(o["type"], o["sha"])' <<< "$otag")
  fi
  [ "$otarget" = "commit $PIN" ] || fail "$OREPO's tag v$OREL is ${otarget:-nothing}, not the pinned commit $PIN"
  say "$OREPO's tag v$OREL is the pinned commit"
fi

# a draft of this tag from an earlier, broken run is reused; a published release is never touched
rel=$(api GET "/repos/$GH_REPO/releases?per_page=100" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    if r["tag_name"] == sys.argv[1]:
        print(r["id"], "draft" if r["draft"] else "published"); break
' "$TAG")
if [ -n "$rel" ] && [ "${rel#* }" = published ]; then fail "$TAG is published already"; fi
ID="${rel%% *}"

if [ "$dry" = 1 ]; then
  if [ -n "$ID" ]; then say "dry run: would reuse draft $ID and upload $(wc -l < "$STAGE/assets") assets"
  else say "dry run: would create the draft $TAG and upload $(wc -l < "$STAGE/assets") assets"; fi
  exit 0
fi

if [ -z "$ID" ]; then
  if [ -n "$OREL" ]; then
    OCC_NOTE="occulited [$OREL](https://github.com/hobbyquaker/occulited/tree/v$OREL) (\`${PIN:0:7}\`)"
  else
    OCC_NOTE="occulited [\`${PIN:0:7}\`](https://github.com/hobbyquaker/occulited/commit/$PIN)"
  fi
  body=$(cat <<EOF
openccu-lite $V: a Homematic CCU firmware without ReGaHSS, built on OpenCCU $BASE, with $OCC_NOTE. **Alpha software** — read the [README](https://github.com/$GH_REPO/blob/$SHA/README.en.md) first.

*The maintainer edits this header before publishing.*

**Download — which file for whom:** the \`.zip\` per board is the image and the update package for a system set up from an OpenCCU image (SD card, USB disk) and for the VM (\`x86_64-ova\`, also as \`.ova\` for a fresh import); a **CCU3** — or any card with the CCU3 layout, \`PRODUCT=ccu3\` in its \`/VERSION\` — takes \`openccu-lite-aarch64-rpi3-$V-ccu3.tgz\` through its own WebUI, not the zip (two recovery passes; see [switching.md](https://github.com/$GH_REPO/blob/$SHA/docs/switching.md)). The update needs 2.8 GB free on the userfs. Every file has its \`.sha256\`; \`SHA256SUMS\` covers all of them and is signed with minisign (\`SHA256SUMS.minisig\`). The SBOM of each image is its \`.cdx.json\`.

**API:** occulited's OpenAPI 3.1 document (\`occulited-openapi-$V.json\`, also served by the system as \`GET /api/openapi.json\` with \`system:read\`), the AsyncAPI 3.0 document of its event streams and lite-rpc's method catalogue are attached.

**Sources:** the sources of the GPL/LGPL components of these images are available on request — open an issue.

**Known issues:** occulited does not verify the minisign signature of a system update yet; it checks the published sha256.
EOF
)
  req=$(python3 -c 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"target_commitish":sys.argv[2],"name":sys.argv[1],"body":sys.argv[4],"draft":True,"prerelease":sys.argv[5]=="true","generate_release_notes":True}))' "$TAG" "$SHA" "$V" "$body" "$PRE")
  resp=$(api POST "/repos/$GH_REPO/releases" -H 'Content-Type: application/json' -d "$req") || fail "GitHub refused to create the draft $TAG (see its message above)"
  ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$resp")
  say "draft $TAG created: release $ID"
fi

upload() { # file
  local f="$1" n size sum try out
  n=$(basename "$f"); size=$(stat -c %s "$f"); sum=$(sha256sum "$f" | cut -d' ' -f1)
  for try in 1 2 3; do
    for old in $(api GET "/repos/$GH_REPO/releases/$ID/assets?per_page=100" | python3 -c '
import json, sys
print(" ".join(str(a["id"]) for a in json.load(sys.stdin) if a["name"] == sys.argv[1]))' "$n"); do
      api DELETE "/repos/$GH_REPO/releases/assets/$old" > /dev/null
    done
    if out=$(curl -sS --fail-with-body -X POST -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" -H "Content-Type: application/octet-stream" \
        --upload-file "$f" "$GH_UPLOADS/repos/$GH_REPO/releases/$ID/assets?name=$n"); then
      if python3 -c '
import json, sys
a = json.load(sys.stdin)
ok = a["size"] == int(sys.argv[1]) and a.get("state") == "uploaded" and a.get("digest") in (None, "sha256:" + sys.argv[2])
sys.exit(0 if ok else 1)' "$size" "$sum" <<< "$out"; then
        say "uploaded $n ($size bytes)"; return 0
      fi
      echo "lite-release-github: $n: size or digest differs after try $try" >&2
    else
      echo "lite-release-github: $n: upload try $try failed" >&2
    fi
    sleep $((try * 30))
  done
  fail "$n was not uploaded"
}
while read -r f; do upload "$f"; done < "$STAGE/assets"
say "draft $TAG complete: https://github.com/$GH_REPO/releases (sign SHA256SUMS, edit the notes, publish)"
