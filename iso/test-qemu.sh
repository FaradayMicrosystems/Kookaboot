#!/usr/bin/env bash
# Boot the KookaBoot ISO in QEMU with an empty 8 GB virtual USB drive attached.
# Usage: iso/test-qemu.sh [bios|uefi|secureboot] [ISO]
# Needs: qemu-system-x86 (and ovmf for uefi/secureboot). Uses KVM when available.
set -Eeuo pipefail

MODE=${1:-uefi}
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ISO=${2:-$(ls -t "$REPO"/iso/out/kookaboot-*-amd64.iso 2>/dev/null | head -n1)}
[[ -f ${ISO:-} ]] || { echo "No ISO found. Build one with: sudo make iso" >&2; exit 1; }

DISK=${KB_TEST_DISK:-$REPO/iso/work/test-usb.img}
mkdir -p -- "$(dirname -- "$DISK")"
[[ -f $DISK ]] || truncate -s 8G "$DISK"

args=(-m 2048 -smp 2
      -drive "file=$ISO,media=cdrom,readonly=on,if=none,id=cd" -device ide-cd,drive=cd,bootindex=0
      -device qemu-xhci -drive "file=$DISK,format=raw,if=none,id=usb" -device usb-storage,drive=usb
      -nic user,model=virtio-net-pci)
[[ -w /dev/kvm ]] && args+=(-enable-kvm -cpu host)

case $MODE in
    bios) ;;
    uefi|secureboot)
        code=/usr/share/OVMF/OVMF_CODE_4M.fd; vars=/usr/share/OVMF/OVMF_VARS_4M.fd
        if [[ $MODE == secureboot ]]; then
            code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd; vars=/usr/share/OVMF/OVMF_VARS_4M.ms.fd
            args+=(-machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on)
        fi
        [[ -f $code ]] || { echo "Missing $code (install ovmf)" >&2; exit 1; }
        cp -- "$vars" "$REPO/iso/work/ovmf-vars-$MODE.fd"
        args+=(-drive "if=pflash,format=raw,readonly=on,file=$code"
               -drive "if=pflash,format=raw,file=$REPO/iso/work/ovmf-vars-$MODE.fd")
        ;;
    *) echo "Mode must be bios, uefi or secureboot" >&2; exit 64 ;;
esac

exec qemu-system-x86_64 "${args[@]}" "${@:3}"
