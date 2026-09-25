#!/bin/sh
#
# openccu-lite: the CA bundle the image ships prebuilt (lite-ca-certificates copies it at boot
# when the user has added no certificate of their own).
#
# It is what update-ca-certificates --default writes on the box with an empty
# /etc/ca-certificates.conf and no /usr/local/share/ca-certificates: made by the image's own
# update-ca-certificates, run here against the target's certificates with the host's openssl, and
# its links then pointed at the paths they have on the box.
#
# Usage: ca-prebuilt.sh <target dir> [<host dir>]
#   writes <target dir>/usr/share/ca-certificates-prebuilt; stops the build when it cannot.

set -eu
TARGET=${1:?target dir}
HOST=${2:-${HOST_DIR:-}}
OUT="${TARGET}/usr/share/ca-certificates-prebuilt"
UPDATE="${TARGET}/usr/sbin/update-ca-certificates"
CERTS="${TARGET}/usr/share/ca-certificates"

fail() { echo "ca-prebuilt (lite): ERROR: $*" >&2; exit 1; }

[ -f "${UPDATE}" ] || fail "no ${UPDATE} (the ca-certificates package's script)"
[ -d "${CERTS}" ] || fail "no ${CERTS}"
if [ -s "${TARGET}/etc/ca-certificates.conf" ] && grep -qv '^[[:space:]]*\(#.*\)\?$' "${TARGET}/etc/ca-certificates.conf"; then
	fail "${TARGET}/etc/ca-certificates.conf is not empty; the prebuilt bundle assumes it is"
fi
if [ -n "${HOST}" ] && [ -x "${HOST}/bin/openssl" ]; then
	PATH="${HOST}/bin:${PATH}"
fi
command -v openssl >/dev/null || fail "no openssl on the host"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/certs" "${work}/hooks-none"
: >"${work}/empty.conf"

# the box's busybox sort orders bytewise; so does the C locale here
LC_ALL=C sh "${UPDATE}" --default \
	--certsdir "${CERTS}" \
	--localcertsdir "${work}/no-local" \
	--certsconf "${work}/empty.conf" \
	--etccertsdir "${work}/certs" \
	--hooksdir "${work}/no-hooks" >"${work}/log" 2>&1 || fail "update-ca-certificates: $(cat "${work}/log")"

# the certificate links point into the target tree here; on the box they point to /usr/share/...
count=0
for link in "${work}/certs"/*.pem; do
	[ -L "${link}" ] || continue
	dest=$(readlink "${link}")
	case "${dest}" in
		"${CERTS}"/*) ln -sfn "/usr/share/ca-certificates/${dest#"${CERTS}"/}" "${link}" ;;
		*) fail "${link##*/} points to ${dest}, outside the target's certificates" ;;
	esac
	count=$((count + 1))
done
[ "${count}" -gt 0 ] || fail "no certificate linked"
[ -s "${work}/certs/ca-certificates.crt" ] || fail "no bundle written"
bundled=$(grep -c 'BEGIN CERTIFICATE' "${work}/certs/ca-certificates.crt")
[ "${bundled}" = "${count}" ] || fail "${count} certificates linked but ${bundled} in the bundle"
hashes=$(find "${work}/certs" -name '*.[0-9]' -type l | wc -l)
[ "${hashes}" -ge "${count}" ] || fail "only ${hashes} hash links for ${count} certificates"

rm -rf "${OUT}"
mkdir -p "${OUT%/*}"
cp -a "${work}/certs" "${OUT}"
chmod 0755 "${OUT}"
echo "ca-prebuilt (lite): ${count} certificates, ${hashes} hash links in ${OUT#"${TARGET}"}"
