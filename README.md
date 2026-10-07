# rescue-iso

Tiny bootable USB image to debug a machine that no longer boots (first use: tiramisu stuck
at grub after a dist-upgrade). It boots, gets DHCP on every NIC, starts sshd, and shows on
screen everything needed to log in remotely:

- `ssh root@<ip>` with a simple three-word password (generated once, `out/password`), or
  with the key `~/.ssh/assert-server.private`;
- the IPv4 addresses and the sshd host-key fingerprints;
- the same banner is posted to the crabe endpoint as hostname `tiramisu-rescue`
  (`curl -s https://www.monperrus.net/martin/crabe.py`), so the IP can be found remotely.

It is the official Alpine standard ISO (GPG-verified), remastered with xorriso (no root
needed, BIOS and UEFI, ~380 MB so it fits a 1 GB stick), plus

- `/extra`: a second boot repository with the extended ISO's signed `APKINDEX` and only the
  53 packages (13 MB) that the rescue tools need (lvm2, cryptsetup, mdadm, btrfs-progs,
  xfsprogs, parted, efibootmgr, tmux…), computed by `closure.py`; both ISOs are the same
  release with the same kernel, and everything installs from the stick, no internet needed;
- an `apkovl` overlay and new boot menus (including a `nomodeset` entry).

## Usage

```sh
./build.sh          # -> out/tiramisu-rescue.iso, prints the password
./test.sh bios      # boots it in QEMU as a USB stick, checks ssh key/password, banner, tools
./test.sh uefi
sudo dd if=out/tiramisu-rescue.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

`RESCUE_PUBKEY=path.pub ./build.sh` authorizes another key. Delete `out/password` to get a
new password on the next build.

⚠️ The password is shown on screen and sshd listens on a public address: boot it only for
the debugging session.

## Story

How it was used to repair a server that a release upgrade left stuck at GRUB, with
Claude Code doing the remote work:
<https://gist.github.com/monperrus/24296cc2f096f8dd476ec8135e978c95>

## License

MIT
