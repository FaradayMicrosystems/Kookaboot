#!/usr/bin/env bash
# Build the KookaBoot live installer ISO (Ubuntu 24.04 base, BIOS + UEFI + Secure Boot).
#
# Usage:  sudo iso/build.sh            (or: sudo make iso)
# Needs (Ubuntu/Debian host): debootstrap squashfs-tools xorriso mtools dosfstools
#        grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed shim-signed curl
# Output: iso/out/kookaboot-<version>-amd64.iso and .sha256
#
# Stages are cached in iso/work/. Delete iso/work/ to rebuild from scratch,
# or set KB_ISO_FRESH=1.
set -Eeuo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ISO_DIR=$REPO/iso
WORK=${KB_ISO_WORK:-$ISO_DIR/work}
OUT=${KB_ISO_OUT:-$ISO_DIR/out}
SUITE=${KB_ISO_SUITE:-noble}
MIRROR=${KB_ISO_MIRROR:-http://archive.ubuntu.com/ubuntu}
SECURITY_MIRROR=${KB_ISO_SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu}

# shellcheck source=lib/common.sh
. "$REPO/lib/common.sh"
# shellcheck source=lib/verify.sh
. "$REPO/lib/verify.sh"
# shellcheck source=lib/ventoy.sh
. "$REPO/lib/ventoy.sh"

VERSION=$KB_VERSION
ISO_NAME=kookaboot-$VERSION-amd64.iso
VOLID=KOOKABOOT
CHROOT=$WORK/chroot
IMAGE=$WORK/image

[[ $(id -u) -eq 0 ]] || kb_die "Run as root: sudo $0"
for c in debootstrap mksquashfs xorriso mformat mcopy mkfs.vfat grub-mkstandalone curl; do
    kb_need_cmd "$c"
done
for f in /usr/lib/grub/i386-pc/cdboot.img /usr/lib/grub/i386-pc/boot_hybrid.img \
         /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed /usr/lib/shim/shimx64.efi.signed \
         /usr/lib/shim/mmx64.efi; do
    [[ -f $f ]] || kb_die "Missing $f (install grub-pc-bin grub-efi-amd64-signed shim-signed)"
done

[[ ${KB_ISO_FRESH:-0} == 1 ]] && rm -rf -- "$WORK"
mkdir -p -- "$WORK" "$OUT"

# ------------------------------------------------------------------ chroot mounts
chroot_mount() {
    mountpoint -q "$CHROOT/proc"    || mount -t proc proc "$CHROOT/proc"
    mountpoint -q "$CHROOT/sys"     || mount -t sysfs sys "$CHROOT/sys"
    mountpoint -q "$CHROOT/dev"     || mount --bind /dev "$CHROOT/dev"
    mountpoint -q "$CHROOT/dev/pts" || mount --bind /dev/pts "$CHROOT/dev/pts"
    mountpoint -q "$CHROOT/run"     || mount -t tmpfs tmpfs "$CHROOT/run"
}
chroot_umount() {
    local m
    for m in run dev/pts dev sys proc; do
        mountpoint -q "$CHROOT/$m" && umount -l "$CHROOT/$m"
    done
    return 0
}
trap chroot_umount EXIT
in_chroot() { chroot "$CHROOT" /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive "$@"; }

# ------------------------------------------------------------------ 1. base system
if [[ ! -f $WORK/.stage-base ]]; then
    kb_info "[1/5] debootstrap $SUITE ..."
    rm -rf -- "$CHROOT"
    debootstrap --arch=amd64 --variant=minbase --components=main,restricted,universe,multiverse \
        "$SUITE" "$CHROOT" "$MIRROR"
    touch "$WORK/.stage-base"
fi

# ------------------------------------------------------------------ 2. packages
PACKAGES=(
    # live boot + kernel (linux-image-generic pulls modules-extra + firmware for Wi-Fi)
    linux-image-generic casper systemd-sysv initramfs-tools
    # networking
    network-manager wpasupplicant iw wireless-regdb ca-certificates curl wget iproute2 iputils-ping
    # drive tools KookaBoot + Ventoy use
    util-linux bsdextrautils parted exfatprogs dosfstools smartmontools gnupg gpgv kmod udev
    # convenience
    zstd less nano pciutils usbutils lsof xz-utils bash-completion console-setup keyboard-configuration locales
)
if [[ ! -f $WORK/.stage-packages ]]; then
    kb_info "[2/5] Installing packages ..."
    cat > "$CHROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main restricted universe multiverse
deb $MIRROR $SUITE-updates main restricted universe multiverse
deb $SECURITY_MIRROR $SUITE-security main restricted universe multiverse
EOF
    # Keep apt from starting services inside the chroot.
    printf '#!/bin/sh\nexit 101\n' > "$CHROOT/usr/sbin/policy-rc.d"
    chmod +x "$CHROOT/usr/sbin/policy-rc.d"
    chroot_mount
    in_chroot apt-get update
    in_chroot apt-get -y --no-install-recommends install "${PACKAGES[@]}"
    in_chroot apt-get -y --no-install-recommends install linux-firmware
    in_chroot apt-get -y full-upgrade
    chroot_umount
    touch "$WORK/.stage-packages"
fi

# ------------------------------------------------------------------ 3. KookaBoot + config (always re-run)
kb_info "[3/5] Installing KookaBoot $VERSION into the image ..."
chroot_mount

# KookaBoot itself
rm -rf -- "$CHROOT/usr/local/lib/kookaboot"
install -d "$CHROOT/usr/local/lib/kookaboot" "$CHROOT/usr/local/bin" "$CHROOT/usr/local/share/doc/kookaboot"
install -m 0644 "$REPO"/lib/*.sh "$CHROOT/usr/local/lib/kookaboot/"
install -m 0755 "$REPO/bin/kookaboot" "$REPO/bin/kookaboot-menu" "$CHROOT/usr/local/bin/"
install -m 0755 "$REPO/tests/smoke.sh" "$CHROOT/usr/local/bin/kookaboot-smoke"
cp -- "$REPO"/README.md "$REPO"/CHANGELOG.md "$REPO"/LICENSE "$REPO"/LICENSE-docs "$REPO"/docs/*.md \
    "$CHROOT/usr/local/share/doc/kookaboot/"

# Bundled, verified Ventoy (works offline)
VENTOY_SRC=$(KB_CACHE_DIR=$WORK/cache kb_ventoy_dir)
rm -rf -- "$CHROOT/opt/ventoy-$KB_VENTOY_VERSION"
mkdir -p -- "$CHROOT/opt"
cp -a -- "$VENTOY_SRC" "$CHROOT/opt/ventoy-$KB_VENTOY_VERSION"
cat > "$CHROOT/etc/kookaboot.conf" <<EOF
# KookaBoot live ISO settings
KB_VENTOY_DIR=/opt/ventoy-$KB_VENTOY_VERSION
KB_STATE_DIR=/run/kookaboot
EOF

# Identity
echo kookaboot > "$CHROOT/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 kookaboot\n' > "$CHROOT/etc/hosts"
cat > "$CHROOT/etc/issue" <<EOF
KookaBoot $VERSION live installer \\l

EOF

# Locale and keyboard (US defaults)
in_chroot sh -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; locale-gen >/dev/null; update-locale LANG=en_US.UTF-8'

# Root with no password, auto-login on tty1, menu starts on login
in_chroot passwd -d root >/dev/null
mkdir -p -- "$CHROOT/etc/systemd/system/getty@tty1.service.d"
cat > "$CHROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
cat > "$CHROOT/root/.bash_profile" <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ -z "${KB_IN_SHELL:-}" ]; then
    exec /usr/local/bin/kookaboot-menu
fi
EOF
cat > "$CHROOT/etc/motd" <<'EOF'

KookaBoot live shell. Commands: kookaboot help | kookaboot-menu | kookaboot-smoke /dev/sdX
Type 'exit' to return to the menu.

EOF

# Let NetworkManager manage every interface (wired comes up by itself)
mkdir -p -- "$CHROOT/etc/NetworkManager/conf.d"
: > "$CHROOT/etc/NetworkManager/conf.d/10-globally-managed-devices.conf"
in_chroot systemctl enable NetworkManager >/dev/null 2>&1 || true

# Quiet kernel messages on the console so they don't cover the menu
echo 'kernel.printk = 3 4 1 3' > "$CHROOT/etc/sysctl.d/20-quiet-printk.conf"

# Trim firmware nobody needs on an installer (GPU compute, datacenter NICs) to cut size.
for d in amdgpu nvidia radeon qcom mellanox netronome liquidio qed cxgb4 mrvl/prestera \
         intel/ipu mediatek/mt8* ti-connectivity/*.bin.zst dpaa2 bnx2x ice; do
    # shellcheck disable=SC2086  # globs intended
    rm -rf -- "$CHROOT"/lib/firmware/$d "$CHROOT"/usr/lib/firmware/$d 2>/dev/null || true
done

in_chroot update-initramfs -u -k all
in_chroot apt-get clean
rm -rf -- "$CHROOT"/var/lib/apt/lists/* "$CHROOT"/tmp/* "$CHROOT"/var/log/*.log "$CHROOT/usr/sbin/policy-rc.d"
: > "$CHROOT/etc/machine-id"
chroot_umount

# ------------------------------------------------------------------ 4. squashfs + boot files
kb_info "[4/5] Building squashfs ..."
rm -rf -- "$IMAGE"
mkdir -p -- "$IMAGE"/{casper,boot/grub,EFI/boot,.disk}
cp -- "$(readlink -f "$CHROOT/boot/vmlinuz")"    "$IMAGE/casper/vmlinuz"
cp -- "$(readlink -f "$CHROOT/boot/initrd.img")" "$IMAGE/casper/initrd"
mksquashfs "$CHROOT" "$IMAGE/casper/filesystem.squashfs" -noappend -comp xz -b 1M -e boot -quiet
du -sx --block-size=1 "$CHROOT" | cut -f1 > "$IMAGE/casper/filesystem.size"
echo "KookaBoot $VERSION \"Rookery\" - amd64 ($(date -u +%Y%m%d))" > "$IMAGE/.disk/info"
touch "$IMAGE/.disk/kookaboot"

cat > "$IMAGE/boot/grub/grub.cfg" <<EOF
search --no-floppy --set=root --file /.disk/kookaboot
set timeout=5
set default=0
insmod all_video 2>/dev/null
set gfxpayload=keep

menuentry "KookaBoot $VERSION" {
    linux /casper/vmlinuz boot=casper quiet ---
    initrd /casper/initrd
}
menuentry "KookaBoot $VERSION (safe graphics)" {
    linux /casper/vmlinuz boot=casper nomodeset quiet ---
    initrd /casper/initrd
}
menuentry "KookaBoot $VERSION (serial console)" {
    linux /casper/vmlinuz boot=casper console=tty0 console=ttyS0,115200 ---
    initrd /casper/initrd
}
if [ "\$grub_platform" = "efi" ]; then
    menuentry "UEFI firmware settings" { fwsetup }
fi
menuentry "Reboot" { reboot }
menuentry "Power off" { halt }
EOF

# BIOS: El Torito image (GRUB core + cdboot)
grub-mkstandalone --format=i386-pc --output="$WORK/core.img" \
    --install-modules="linux normal iso9660 biosdisk memdisk search tar ls part_msdos part_gpt configfile echo reboot halt all_video" \
    --modules="linux normal iso9660 biosdisk search part_msdos part_gpt" \
    --locales="" --fonts="" \
    "boot/grub/grub.cfg=$IMAGE/boot/grub/grub.cfg"
cat /usr/lib/grub/i386-pc/cdboot.img "$WORK/core.img" > "$IMAGE/boot/grub/bios.img"

# UEFI: Microsoft-signed shim -> Canonical-signed GRUB (Secure Boot works out of the box)
cp /usr/lib/shim/shimx64.efi.signed                 "$IMAGE/EFI/boot/bootx64.efi"
cp /usr/lib/shim/mmx64.efi                          "$IMAGE/EFI/boot/mmx64.efi"
cp /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed "$IMAGE/EFI/boot/grubx64.efi"
rm -f -- "$WORK/efiboot.img"
mkfs.vfat -C -n KBEFI "$WORK/efiboot.img" 8192 >/dev/null
mmd   -i "$WORK/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$WORK/efiboot.img" "$IMAGE/EFI/boot/bootx64.efi" "$IMAGE/EFI/boot/mmx64.efi" "$IMAGE/EFI/boot/grubx64.efi" ::/EFI/boot/

# ------------------------------------------------------------------ 5. ISO
kb_info "[5/5] Writing ISO ..."
rm -f -- "$OUT/$ISO_NAME"
xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid "$VOLID" \
    -output "$OUT/$ISO_NAME" \
    -eltorito-boot boot/grub/bios.img -no-emul-boot -boot-load-size 4 -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    -append_partition 2 0xef "$WORK/efiboot.img" \
    -partition_offset 16 \
    "$IMAGE"

( cd -- "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
kb_ok "Built $OUT/$ISO_NAME ($(kb_human "$(stat -c %s "$OUT/$ISO_NAME")"))"
cat "$OUT/$ISO_NAME.sha256"
