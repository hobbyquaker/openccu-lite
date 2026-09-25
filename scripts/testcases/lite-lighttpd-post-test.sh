#!/bin/sh
# openccu-lite: a POST without a body reaches the API and the addons (B-211). lighttpd 1.4.84 answers
# 411 Length Required to a POST that carries neither Content-Length nor Transfer-Encoding, before any
# configuration or module sees it - there is no setting for it - so `curl -X POST`, simple scripts
# and other clients that send such a POST (a logout, an inject, a copy now) never reached occulited or
# the addon. The lite products carry board/lite/patches/lighttpd, which takes such a POST as an empty
# body (RFC 9112 section 6.3: a request without either has a body of length zero).
#
# The static part (always): every lite product (BR2_PACKAGE_OCCULITED=y) names board/lite/patches in
# BR2_GLOBAL_PATCH_DIR, upstream's products do not, and the patch directory holds only patches.
# The build part (docker and the network; SKIP_BUILD=1 leaves it out): lighttpd of the version the
# buildroot release pins (LIGHTTPD_VERSION, LIGHTTPD_SHA256), built in an Alpine container with
# mod_proxy in front of a small backend - first as released (the bodiless POST is 411, so the check
# still sees the code it is about), then with the lite patches: the bodiless POST reaches the backend
# with Content-Length: 0 over HTTP/1.1 and HTTP/1.0 and twice on one connection, a POST with a body
# is unchanged, a GET gets no Content-Length, and server.max-request-size still refuses a body that
# is too large (the body limits stay as they are).
#
# Usage: sh scripts/testcases/lite-lighttpd-post-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
PDIR="$EXT/board/lite/patches"
LIGHTTPD_VERSION=${LIGHTTPD_VERSION:-1.4.84}
LIGHTTPD_SHA256=${LIGHTTPD_SHA256:-076dd43bec8f2ba9ce6db7e7ca7e8ad72271cd529805ead2400b56efaa026f70}

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# ---- the static part
ls "$PDIR"/lighttpd/*.patch >/dev/null 2>&1 && ok "board/lite/patches/lighttpd holds the patch" || bad "no patch in board/lite/patches/lighttpd"
other=$(find "$PDIR" -type f ! -name '*.patch' | sed "s|$HERE/||")
[ -z "$other" ] && ok "the patch directory holds only patches" || bad "not a patch in the patch directory: $other"
lite=0
for cfg in "$EXT"/configs/*.config; do
  name=${cfg##*/}
  dirs=$(sed -n 's/^BR2_GLOBAL_PATCH_DIR="\(.*\)"$/\1/p' "$cfg")
  has=""
  for d in $dirs; do [ "$d" = '$(BR2_EXTERNAL_EQ3_PATH)/board/lite/patches' ] && has=1; done
  if grep -q '^BR2_PACKAGE_OCCULITED=y' "$cfg"; then
    lite=$((lite + 1))
    [ -n "$has" ] && ok "$name: the lite patches" || bad "$name is a lite product without board/lite/patches in BR2_GLOBAL_PATCH_DIR"
    # the VM and the containers never took upstream's patches/: they must not start now
    case "$name" in
      aarch64-*) ;;
      *) for d in $dirs; do [ "$d" = '$(BR2_EXTERNAL_EQ3_PATH)/patches' ] && bad "$name now takes upstream's patches/ too"; done ;;
    esac
  else
    [ -z "$has" ] && ok "$name: upstream's product, no lite patches" || bad "$name is not a lite product but takes board/lite/patches"
  fi
done
[ "$lite" -ge 6 ] && ok "$lite lite products checked" || bad "only $lite lite products found"

if [ -n "${SKIP_BUILD:-}" ]; then
  echo "skip the build part (SKIP_BUILD)"
elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skip the build part: no docker"
else
  out=$(docker run --rm -i -e "V=$LIGHTTPD_VERSION" -e "SHA=$LIGHTTPD_SHA256" -v "$PDIR:/patches:ro" \
    "${ALPINE_IMAGE:-alpine:3.22}" sh -s <<'INNER' 2>&1
set -u
apk add --no-cache build-base meson pkgconf curl python3 >/tmp/apk.log 2>&1 || { echo "FAIL apk"; cat /tmp/apk.log; exit 1; }
cd /tmp
curl -sfLO "https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-$V.tar.xz" || { echo "FAIL download lighttpd-$V"; exit 1; }
echo "$SHA  lighttpd-$V.tar.xz" | sha256sum -c - >/dev/null 2>&1 || { echo "FAIL lighttpd-$V.tar.xz: sha256 mismatch"; exit 1; }
tar xJf "lighttpd-$V.tar.xz"
cd "lighttpd-$V"
meson setup b -Dbuildtype=release -Dwith_pcre=disabled -Dwith_pcre2=false -Dwith_zlib=disabled -Dwith_xxhash=disabled >/tmp/meson.log 2>&1 || { echo "FAIL meson"; tail -20 /tmp/meson.log; exit 1; }
ninja -C b src/lighttpd src/mod_proxy.so >/tmp/ninja.log 2>&1 || { echo "FAIL ninja"; tail -20 /tmp/ninja.log; exit 1; }

# the backend: what reached it
cat > /tmp/backend.py <<'PY'
import http.server
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def answer(self):
        cl = self.headers.get("Content-Length")
        n = int(cl) if cl is not None else 0
        body = self.rfile.read(n) if n else b""
        out = ("%s cl=%s body=%d" % (self.command, cl if cl is not None else "none", len(body))).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
    do_GET = do_POST = answer
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 9000), H).serve_forever()
PY
python3 /tmp/backend.py & BPID=$!
mkdir -p /srv
cat > /tmp/l.conf <<CONF
server.document-root = "/srv"
server.bind = "127.0.0.1"
server.port = 8080
server.modules = ( "mod_proxy" )
server.max-request-size = 1
proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 9000 ) ) )
CONF
run() {  # start the built lighttpd
  ./b/src/lighttpd -D -f /tmp/l.conf -m "$PWD/b/src" & LPID=$!
  i=0; until curl -s -o /dev/null http://127.0.0.1:8080/ || [ $i -ge 50 ]; do sleep 0.1; i=$((i+1)); done
}
stop() { kill $LPID; wait $LPID 2>/dev/null; }
U=http://127.0.0.1:8080/x
q() { curl -s -w ' %{http_code}' "$@"; }

run
r=$(q -o /dev/null -X POST $U); case "$r" in " 411") echo "ok   as released: a bodiless POST is 411" ;; *) echo "FAIL as released: a bodiless POST answered '$r', not 411 - is the patch still needed?" ;; esac
stop

for p in /patches/lighttpd/*.patch; do patch -p1 --quiet < "$p" || { echo "FAIL $p does not apply to lighttpd-$V"; exit 1; }; done
echo "ok   the lite patches apply to lighttpd-$V"
ninja -C b src/lighttpd >>/tmp/ninja.log 2>&1 || { echo "FAIL ninja after the patches"; tail -20 /tmp/ninja.log; exit 1; }
run
r=$(q -X POST $U); [ "$r" = "POST cl=0 body=0 200" ] && echo "ok   a bodiless POST reaches the backend with Content-Length: 0" || echo "FAIL bodiless POST: '$r'"
r=$(q -0 -X POST $U); [ "$r" = "POST cl=0 body=0 200" ] && echo "ok   the same over HTTP/1.0" || echo "FAIL bodiless POST over HTTP/1.0: '$r'"
r=$(curl -s -o /dev/null -o /dev/null -w '%{http_code} ' -X POST $U $U); [ "$r" = "200 200 " ] && echo "ok   two bodiless POSTs on one connection" || echo "FAIL two bodiless POSTs: '$r'"
r=$(q -X POST -d abc $U); [ "$r" = "POST cl=3 body=3 200" ] && echo "ok   a POST with a body is unchanged" || echo "FAIL POST with a body: '$r'"
r=$(q -X POST -d '' $U); [ "$r" = "POST cl=0 body=0 200" ] && echo "ok   an empty body with Content-Length: 0 is unchanged" || echo "FAIL POST -d '': '$r'"
r=$(q $U); [ "$r" = "GET cl=none body=0 200" ] && echo "ok   a GET gets no Content-Length" || echo "FAIL GET: '$r'"
r=$(head -c 2048 /dev/zero | tr '\0' a | q -o /dev/null -X POST --data-binary @- $U); [ "$r" = " 413" ] && echo "ok   server.max-request-size still refuses a body that is too large" || echo "FAIL a body over the limit: '$r'"
stop
kill $BPID
INNER
  )
  rc=$?
  echo "$out"
  n=$(echo "$out" | grep -c '^FAIL ')
  fails=$((fails + n))
  if [ "$rc" -ne 0 ] && [ "$n" -eq 0 ]; then
    bad "the build part exited $rc: $(echo "$out" | tail -5)"
  fi
  echo "$out" | grep -q '^ok   a bodiless POST reaches the backend' || [ "$n" -gt 0 ] || bad "the build part did not reach its checks: $(echo "$out" | tail -5)"
fi

[ "$fails" -eq 0 ] && echo "lite-lighttpd-post-test: all passed" || echo "lite-lighttpd-post-test: $fails failed"
[ "$fails" -eq 0 ]
