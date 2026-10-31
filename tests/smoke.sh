#!/usr/bin/env bash
# KookaBoot smoke test for a real, already-installed drive. Read-only.
# Usage: sudo tests/smoke.sh /dev/sdX
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
LIB=$ROOT/lib
[[ -f $LIB/common.sh ]] || LIB=/usr/local/lib/kookaboot   # installed copy (live ISO)
for f in common drive health verify space ventoy rookery; do
    # shellcheck source=/dev/null
    . "$LIB/$f.sh"
done

DEV=${1:-}
[[ -n $DEV ]] || kb_die "Usage: sudo $0 /dev/sdX"
kb_need_root
DEV=$(kb_drive_resolve "$DEV")
[[ -b $DEV ]] || kb_die "$DEV is not a block device."

PASS=0; FAIL=0
check() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
    else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

P1=$(kb_drive_part "$DEV" 1); P2=$(kb_drive_part "$DEV" 2)
echo "Partitions on $DEV"
check "data partition $P1 exists"     test -b "$P1"
check "Ventoy EFI partition $P2 exists" test -b "$P2"
check "$P1 is exFAT"                  bash -c "[[ \$(blkid -s TYPE -o value '$P1') == exfat ]]"
check "$P2 is labelled VTOYEFI"       bash -c "[[ \$(blkid -s LABEL -o value '$P2') == VTOYEFI ]]"

kb_mount_data "$DEV"
M=$KB_MNT
echo "Rookery on $P1 (mounted at $M)"
check "rookery/rookery.conf present"  test -f "$M/rookery/rookery.conf"
check "rookery/images/ present"       test -d "$M/rookery/images"
check "ventoy/ventoy.json present"    test -f "$M/ventoy/ventoy.json"
if kb_have_cmd python3; then
    check "ventoy.json is valid JSON"  python3 -m json.tool "$M/ventoy/ventoy.json"
fi
check "at least ${KB_MIN_FREE_MB} MiB free" \
    bash -c "(( \$(df -B1M --output=avail '$M' | tail -n1) >= $KB_MIN_FREE_MB ))"

echo "Images"
n=0
while IFS=$'\t' read -r _size path; do
    n=$((n+1))
    want=$(kb_sums_lookup "$M/rookery/SHA256SUMS" "$path" 2>/dev/null)
    if [[ -z $want ]]; then
        FAIL=$((FAIL+1)); printf '  FAIL  %s (not in rookery/SHA256SUMS)\n' "$path"
    else
        check "$path checksum" kb_verify_image "$M/rookery/images/$path" "$want"
    fi
done < <(kb_rookery_images "$M")
(( n == 0 )) && echo "  (no images yet)"

kb_unmount_data
echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
