# KookaBoot 1.1.0 installer ISO (release candidate)

The ISO is split into 45 MB parts (GitHub file-size limits).
Status: boot-tested in QEMU (BIOS USB, UEFI USB, UEFI Secure Boot). Real-hardware tests pending.

## 1. Join the parts

```
cd release
cat kookaboot-1.1.0-amd64.iso.part* > kookaboot-1.1.0-amd64.iso
```

## 2. Check it

```
sha256sum -c kookaboot-1.1.0-amd64.iso.sha256
```

Must print `kookaboot-1.1.0-amd64.iso: OK`. If not, do not use it.

## 3. Write it to a USB stick (ERASES the stick)

```
lsblk                       # find the stick, e.g. /dev/sdX
sudo dd if=kookaboot-1.1.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot from the stick. The KookaBoot menu starts automatically.
