# KookaBoot commands (v1.1)

`DEV` is the whole drive, e.g. `/dev/sdb`. Use `lsblk` to find it. Stable names under `/dev/disk/by-id/` also work.
All commands except `version` and `help` need root.

## install

```
sudo kookaboot install DEV [--gpt] [--no-secure-boot] [--label NAME] [--reinstall]
```

Erases `DEV`, installs the pinned Ventoy release, and creates the Rookery.

1. Refuses partitions, the disk running your system, and drives with mounted partitions.
2. Shows model, size, serial and bus.
3. Runs the SMART health check. A failing drive is refused.
4. Asks you to type the device name (e.g. `sdb`) to confirm.
5. Downloads Ventoy if not cached, checks its SHA-256, installs it.
6. Creates `/rookery/` and `/ventoy/ventoy.json`.

| Option | Effect |
| --- | --- |
| `--gpt` | GPT partition table (default MBR). Needs `parted`. |
| `--no-secure-boot` | Leave out Ventoy's Secure Boot support. |
| `--label NAME` | Data partition label, max 11 characters. Default `KookaBoot`. |
| `--reinstall` | Wipe a drive that already has Ventoy. |

## add

```
sudo kookaboot add DEV IMAGE --sums SHA256SUMS [--sig SHA256SUMS.gpg --keyring KEY.gpg] [--name NAME] [--replace]
sudo kookaboot add DEV IMAGE --sha256 HASH
```

1. If `--keyring` is given, checks the checksum file's GPG signature (`gpgv`, only that key is trusted).
2. Checks the image on your computer. A mismatch stops here; nothing is written.
3. Checks free space, keeping 1 GiB spare.
4. Copies the image, flushes it to the drive, then checks the copy again from the drive.
5. A bad copy goes to `/rookery/.quarantine/`. A good copy goes to `/rookery/images/` and its checksum is recorded in `/rookery/SHA256SUMS`.

Clear-signed checksum files (Fedora `CHECKSUM`) need only `--sums` and `--keyring`.

## list

```
sudo kookaboot list DEV
```

Shows drive versions and every image with its size.

## space

```
sudo kookaboot space DEV [--need SIZE|FILE]
```

Shows total and free space. With `--need` (e.g. `4G`, or an ISO file), says whether it fits.

## health

```
sudo kookaboot health DEV
```

Exit code `0` healthy, `1` warning or no SMART data, `2` failing. Needs `smartmontools`. Most USB sticks have no SMART data.

## upgrade-ventoy

```
sudo kookaboot upgrade-ventoy DEV
```

Upgrades Ventoy to the pinned, tested version without touching images.

1. Refuses if the drive already has this or a newer version.
2. Backs up `/ventoy/` to `/var/lib/kookaboot/backups/<serial>/<time>/` and to `/rookery/.backup/<time>/`.
3. Records the image list, unmounts, asks for typed confirmation, runs Ventoy's update.
4. Checks the image list is unchanged and restores `/ventoy/` if it went missing.

## Settings

Put overrides in `/etc/kookaboot.conf` (Bash syntax):

| Setting | Default | Meaning |
| --- | --- | --- |
| `KB_MIN_FREE_MB` | `1024` | Space to keep free on the drive |
| `KB_CACHE_DIR` | `/var/cache/kookaboot` | Ventoy download cache |
| `KB_STATE_DIR` | `/var/lib/kookaboot` | Upgrade backups |
| `KB_VENTOY_DIR` | (unset) | Use an already-extracted Ventoy folder (offline) |
