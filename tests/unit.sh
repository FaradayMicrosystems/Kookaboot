#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034,SC2209  # stubs and env overrides used by sourced libs
# KookaBoot unit tests. No root, no real drive needed.
# Usage: tests/unit.sh
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for f in common drive health verify space ventoy rookery commands; do
    # shellcheck source=/dev/null
    . "$ROOT/lib/$f.sh"
done
FIX=$ROOT/tests/fixtures
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  pass  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
eq()   { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
rc()   { local name=$1 want=$2; shift 2; local got=0; "$@" >/dev/null 2>&1 || got=$?; eq "$name" "$got" "$want"; }
dies() { local name=$1; shift; if ( "$@" ) >/dev/null 2>&1; then bad "$name (did not fail)"; else ok "$name"; fi; }

echo "drive"
eq "part sdb"      "$(kb_drive_part /dev/sdb 1)"      /dev/sdb1
eq "part nvme"     "$(kb_drive_part /dev/nvme0n1 1)"  /dev/nvme0n1p1
eq "part mmc"      "$(kb_drive_part /dev/mmcblk0 2)"  /dev/mmcblk0p2

# Stub findmnt/lsblk: / on LUKS-on-LVM on nvme0n1, /boot on sda1.
findmnt() {
    case ${*: -1} in
        /)     echo /dev/mapper/root ;;
        /boot) echo /dev/sda1 ;;
        *)     return 1 ;;
    esac
}
lsblk() {
    case ${*: -1} in
        /dev/mapper/root) printf '/dev/mapper/root crypt\n/dev/mapper/vg-root lvm\n/dev/nvme0n1p2 part\n/dev/nvme0n1 disk\n' ;;
        /dev/sda1)        printf '/dev/sda1 part\n/dev/sda disk\n' ;;
        *)                command lsblk "$@" ;;
    esac
}
eq "system disks through LUKS/LVM" "$(kb_drive_system_disks | grep -v '^/dev/zram' | grep -E 'nvme0n1|sda' | tr '\n' ' ')" "/dev/nvme0n1 /dev/sda "
unset -f findmnt lsblk

echo "versions and sizes"
rc "1.1.18 >= 1.1.17" 0 kb_version_ge 1.1.18 1.1.17
rc "1.1.9 < 1.1.18"   1 kb_version_ge 1.1.9 1.1.18
rc "equal versions"   0 kb_version_ge 1.1.18 1.1.18
eq "size 4G"   "$(kb_parse_size 4G)"   4294967296
eq "size 700m" "$(kb_parse_size 700m)" 734003200
printf 'abc' > "$TMP/f"; eq "size of file" "$(kb_parse_size "$TMP/f")" 3
dies "size garbage" kb_parse_size lots

echo "space"
G=$((1024*1024*1024))
KB_MIN_FREE_MB=1024
rc "fits with 1 GiB spare"     0 kb_space_fits $((5*G)) $((4*G))
rc "fails under 1 GiB spare"   1 kb_space_fits $((5*G)) $((4*G+1))
rc "fails when bigger than free" 1 kb_space_fits $G $((2*G))

echo "checksums"
printf 'hello\n' > "$TMP/a.iso"
H=$(sha256sum "$TMP/a.iso" | cut -d' ' -f1)
rc "verify match"           0 kb_verify_image "$TMP/a.iso" "$H"
rc "verify uppercase hash"  0 kb_verify_image "$TMP/a.iso" "${H^^}"
rc "verify mismatch"        1 kb_verify_image "$TMP/a.iso" "$(printf '0%.0s' {1..64})"
dies "verify invalid hash"  kb_verify_image "$TMP/a.iso" nothex
eq "sums GNU"        "$(kb_sums_lookup "$FIX/sums-gnu.txt" ubuntu-24.04.iso)" "$(printf 'a%.0s' {1..64})"
eq "sums GNU binary" "$(kb_sums_lookup "$FIX/sums-gnu.txt" kali.iso)"         "$(printf 'b%.0s' {1..64})"
eq "sums BSD clearsigned (Fedora)" "$(kb_sums_lookup "$FIX/sums-fedora.txt" Fedora-Workstation-Live-41.iso)" "$(printf 'c%.0s' {1..64})"
eq "sums missing name" "$(kb_sums_lookup "$FIX/sums-gnu.txt" nope.iso)" ""
dies "both --sha256 and --sums" kb_resolve_expected x.iso "$H" "$FIX/sums-gnu.txt" "" ""
dies "--sig without --keyring"  kb_resolve_expected x.iso "" "$FIX/sums-gnu.txt" sig ""
dies "no checksum at all"       kb_resolve_expected x.iso "" "" "" ""

echo "signatures"
if command -v gpg >/dev/null && command -v gpgv >/dev/null; then
    export GNUPGHOME=$TMP/gnupg; mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key 'KB Test <t@example.invalid>' ed25519 sign never 2>/dev/null
    gpg --batch --export > "$TMP/key.gpg"
    printf '%s  a.iso\n' "$H" > "$TMP/SUMS"
    gpg --batch --quiet --detach-sign -o "$TMP/SUMS.gpg" "$TMP/SUMS"
    gpg --batch --quiet --clearsign -o "$TMP/SUMS.asc" "$TMP/SUMS"
    rc "detached signature valid" 0 kb_verify_signature "$TMP/SUMS" "$TMP/SUMS.gpg" "$TMP/key.gpg"
    rc "clear-signed valid"       0 kb_verify_signature "$TMP/SUMS.asc" "" "$TMP/key.gpg"
    eq "resolve via signed sums"  "$(kb_resolve_expected "$TMP/a.iso" "" "$TMP/SUMS" "$TMP/SUMS.gpg" "$TMP/key.gpg" 2>/dev/null)" "$H"
    printf 'x' >> "$TMP/SUMS"
    rc "tampered sums rejected"   1 kb_verify_signature "$TMP/SUMS" "$TMP/SUMS.gpg" "$TMP/key.gpg"
    dies "resolve dies on bad signature" kb_resolve_expected "$TMP/a.iso" "" "$TMP/SUMS" "$TMP/SUMS.gpg" "$TMP/key.gpg"
else
    echo "  skip  gpg not installed"
fi

echo "health"
rc "SMART passed, clean"        0 kb_health_parse < "$FIX/smart-ok.txt"
rc "SMART passed, reallocated"  1 kb_health_parse < "$FIX/smart-realloc.txt"
rc "SMART failed"               2 kb_health_parse < "$FIX/smart-failed.txt"
rc "USB stick, no SMART"        1 kb_health_parse < "$FIX/smart-none.txt"
rc "NVMe media errors"          1 kb_health_parse < "$FIX/smart-nvme-errors.txt"

echo "rookery"
mkdir -p "$TMP/mnt"
KB_VERSION=test kb_rookery_init "$TMP/mnt" 1.1.18
rc "rookery.conf written" 0 kb_rookery_is_drive "$TMP/mnt"
rc "ventoy.json search root" 0 grep -q '"/rookery/images"' "$TMP/mnt/ventoy/ventoy.json"
kb_rookery_conf_set "$TMP/mnt" VENTOY_VERSION 9.9
eq "conf update" "$(grep -c '^VENTOY_VERSION=9.9$' "$TMP/mnt/rookery/rookery.conf")" 1
kb_rookery_ledger_set "$TMP/mnt" a.iso "$(printf '1%.0s' {1..64})"
kb_rookery_ledger_set "$TMP/mnt" b.iso "$(printf '2%.0s' {1..64})"
kb_rookery_ledger_set "$TMP/mnt" a.iso "$(printf '3%.0s' {1..64})"
eq "ledger replaces old entry" "$(wc -l < "$TMP/mnt/rookery/SHA256SUMS" | tr -d ' ')" 2
eq "ledger keeps new hash" "$(kb_sums_lookup "$TMP/mnt/rookery/SHA256SUMS" a.iso)" "$(printf '3%.0s' {1..64})"
printf 'x' > "$TMP/mnt/rookery/images/one.iso"; printf 'x' > "$TMP/mnt/rookery/images/notes.txt"
eq "images lists only images" "$(kb_rookery_images "$TMP/mnt" | cut -f2)" one.iso

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
