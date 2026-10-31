# Hardware testing (v1.1)

Every release is tested on real drives and real machines before it is tagged.
Use drives with nothing you need on them: `install` erases them.

## Test rigs

| Rig | Needed for |
| --- | --- |
| A. USB 2.0 stick (no SMART) | Install, no-SMART warning path |
| B. USB 3.x SSD or NVMe enclosure (has SMART) | Health check, speed |
| C. Legacy BIOS machine | BIOS boot |
| D. UEFI machine, Secure Boot off | UEFI boot |
| E. UEFI machine, Secure Boot on | Ventoy MOK enrolment (full guidance arrives in v1.3) |

## Host setup (once)

```
sudo apt install smartmontools gnupg parted exfatprogs     # Debian/Ubuntu/Mint
sudo dnf install smartmontools gnupg2 parted exfatprogs    # Fedora
sudo pacman -S smartmontools gnupg parted exfatprogs       # Arch
git clone https://github.com/FaradayMicrosystems/kookaboot && cd kookaboot
make test            # lint + unit tests, no root
sudo make install    # optional: installs to /usr/local
```

## Test images

Use one small real ISO, e.g. Arch (about 1.2 GB), with its checksum file:

```
https://geo.mirror.pkgbuild.com/iso/latest/
  archlinux-x86_64.iso
  sha256sums.txt
```

If `sha256sums.txt` lists only the dated name (e.g. `archlinux-2026.10.01-x86_64.iso`), download that file instead.

Make a corrupt copy for the rejection test:

```
cp archlinux-x86_64.iso broken.iso
printf 'X' | dd of=broken.iso bs=1 seek=100000 conv=notrunc
```

## Procedure

Write results in the table at the end. `sdX` = the test drive (check with `lsblk`).

| # | Step | Command | Expected |
| --- | --- | --- | --- |
| 1 | Refuse system disk | `sudo kookaboot install /dev/<your system disk>` | Refused, nothing written |
| 2 | Refuse partition | `sudo kookaboot install /dev/sdX1` | Refused |
| 3 | Health on rig A | `sudo kookaboot health /dev/sdX` | WARN no SMART, exit 1 |
| 4 | Health on rig B | `sudo kookaboot health /dev/sdX` | OK, exit 0 |
| 5 | Cancel install | `sudo kookaboot install /dev/sdX`, type `no` | Cancelled, drive unchanged |
| 6 | Install (MBR) on A | `sudo kookaboot install /dev/sdX`, type `sdX` | OK installed |
| 7 | Install (GPT) on B | `sudo kookaboot install /dev/sdX --gpt` | OK installed |
| 8 | Add good image | `sudo kookaboot add /dev/sdX archlinux-x86_64.iso --sums sha256sums.txt` | OK added |
| 9 | Reject bad image | `cp sha256sums.txt s2 && sed -i 's/archlinux-x86_64.iso/broken.iso/' s2 && sudo kookaboot add /dev/sdX broken.iso --sums s2` | Refused, nothing written |
| 10 | Space check | `sudo kookaboot space /dev/sdX --need 500G` | Does not fit |
| 11 | Smoke test | `sudo tests/smoke.sh /dev/sdX` | 0 failed |
| 12 | Boot rig C | Boot from drive, pick Arch | Arch boots |
| 13 | Boot rig D | Same | Arch boots |
| 14 | Boot rig E | Same; enrol key when Ventoy asks | Arch boots after enrolment |
| 15 | Upgrade | Install an older Ventoy with `--reinstall` and `KB_VENTOY_VERSION`/`KB_VENTOY_DIR` set, add image, then `sudo kookaboot upgrade-ventoy /dev/sdX` | Upgraded, image intact, smoke test passes |

## Results

| Date | Tester | Rig | Drive model | Steps passed | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
