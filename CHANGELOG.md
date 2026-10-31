# Changelog

## v1.1.0 (unreleased; awaiting hardware tests)

First release of the from-scratch rewrite.

- `install`: Ventoy 1.1.18 (pinned, SHA-256 checked) plus Rookery layout. Refuses partitions, system disks (including LUKS/LVM) and mounted drives. Typed confirmation.
- `add`: SHA-256 and GPG (gpgv) verification before copy; copy re-verified on the drive; bad copies quarantined; checksum ledger in `/rookery/SHA256SUMS`.
- `health`: SMART check (ATA, USB-SATA bridges, NVMe). Failing drives are refused by `install` and `upgrade-ventoy`.
- `space`: free-space planner keeping 1 GiB spare.
- `upgrade-ventoy`: in-place upgrade to the pinned version with config backups and image-list check; never downgrades.
- `list`, `version`, `help`.
- exFAT mounting falls back to `exfat-fuse` on kernels without exFAT.
- Live installer ISO (`sudo make iso`): Ubuntu 24.04 base, BIOS + UEFI + Secure Boot, auto-starting text menu (`kookaboot-menu`), wired + Wi-Fi (nmtui), Ventoy bundled for offline use. The boot drive is protected from being erased.
- `install` refuses drives under 1 GiB.
- Tests: `tests/unit.sh` (41 checks), `tests/smoke.sh` for real drives, `docs/hardware-testing.md`.
