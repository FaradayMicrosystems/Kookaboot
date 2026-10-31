# KookaBoot

Turns a drive into a verified, bootable image library — the Virtual Rookery — built on Ventoy.

- Linux hosts only. Bash.
- Status: v1.1.0, awaiting hardware tests. See [CHANGELOG.md](CHANGELOG.md) and [docs/release-plan.md](docs/release-plan.md).

## Installer ISO

Write `kookaboot-<version>-amd64.iso` to a USB stick (e.g. `sudo dd if=kookaboot-1.1.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync`), boot it, and use the menu. Build it yourself with `sudo make iso` on an Ubuntu/Debian host; test it with `iso/test-qemu.sh uefi`.

## Quick start (on an existing Linux PC)

```
git clone https://github.com/FaradayMicrosystems/kookaboot && cd kookaboot
sudo make install                     # or run ./bin/kookaboot directly
lsblk                                 # find your USB drive, e.g. /dev/sdb
sudo kookaboot install /dev/sdb       # ERASES the drive
sudo kookaboot add /dev/sdb ubuntu-24.04.iso --sums SHA256SUMS
sudo kookaboot list /dev/sdb
```

Needs: `bash`, `util-linux`, `coreutils`, `curl`, `tar`. Recommended: `smartmontools`, `gnupg` (gpgv), `parted` (for `--gpt`), `exfatprogs`.

Docs: [commands](docs/commands.md) · [hardware testing](docs/hardware-testing.md)

## Licences

| Part | Licence |
| --- | --- |
| Code | PolyForm Noncommercial 1.0.0 (see `LICENSE`) |
| Docs, theme art, logo | CC BY-NC-SA 4.0 (see `LICENSE-docs`) |
| Ventoy (downloaded at install time, unmodified) | GPLv3, https://github.com/ventoy/Ventoy |
