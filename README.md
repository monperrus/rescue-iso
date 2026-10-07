# rescue-iso

A 380 MB bootable USB image whose only job is to make a machine that no longer boots
**remotely debuggable**, by a human or by an AI agent such as Claude Code. Plug it in, pick
it in the boot menu, and everything else happens over SSH.

It boots on BIOS and UEFI, gets DHCP on every NIC, starts sshd, and:

- accepts `ssh root@<ip>` with a pre-baked public key (`RESCUE_PUBKEY`, default
  `~/.ssh/assert-server.private.pub`) or a simple three-word password (generated once,
  `out/password`);
- prints on the console the IPv4 addresses, the password and the sshd host-key
  fingerprints;
- **phones home**: posts the same information, as hostname `tiramisu-rescue`, to the crabe
  endpoint (`curl -s https://www.monperrus.net/martin/crabe.py`) every time the address
  changes (and every 10 minutes), so the IP can be found without anyone reading the screen;
- ships the repair tools offline: lvm2, cryptsetup, mdadm, e2fsprogs, btrfs-progs,
  xfsprogs, parted, efibootmgr, pciutils, tmux, bash, curl.

## Usage

```sh
./build.sh          # -> out/tiramisu-rescue.iso, prints the password
./test.sh bios      # boots it in QEMU as a USB stick, checks ssh key/password, banner, tools
./test.sh uefi
sudo dd if=out/tiramisu-rescue.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

`RESCUE_PUBKEY=path.pub ./build.sh` authorizes another key. Delete `out/password` to get a
new password on the next build. If the screen stays black, pick the `nomodeset` entry. An
unsigned Alpine image needs Secure Boot disabled.

⚠️ The password is shown on screen, the wordlist is public (3 of 119 words, ~1.7 M
combinations) and sshd listens on a public address: boot it only for the debugging
session.

## How it is built

No root needed: the official Alpine *standard* ISO (GPG-verified) is remastered with
`xorriso`, keeping its BIOS and UEFI boot records.

- The standard ISO (370 MB) lacks most repair tools; the extended ISO (1.4 GB) has them.
  Both are the same release with the same kernel, so `build.sh` grafts a second boot
  repository `/extra` onto the standard ISO: the extended ISO's **signed** `APKINDEX` plus
  only the 53 `.apk` files (13 MB) in the dependency closure of the tools, computed by
  `closure.py`. Alpine's init adds any directory holding a `.boot_repository` marker to
  `/etc/apk/repositories`.
- The configuration is an `apkovl` overlay at the root of the media
  (`overlay/` + generated hostname, world, authorized key and password). An empty
  `etc/.default_boot_services` keeps Alpine's default boot services next to `sshd` and
  `local`.
- `overlay/etc/local.d/rescue.start` does DHCP, sets the password, and runs the banner and
  phone-home loop; `overlay/etc/ssh/sshd_config.d/rescue.conf` allows root and password
  login.
- New boot menus: no `quiet`, `consoleblank=0`, plus a `nomodeset` entry.

`test.sh` boots the image in QEMU as a USB stick and checks key login, password login,
wrong-password rejection, the banner, and that the tools are installed.

## First use: a server stuck at GRUB after a release upgrade

A GPU server (Ubuntu, LVM root, RAID1 `/home`, NVIDIA, docker) stopped booting after a
22.04 → 24.04 `do-release-upgrade` and sat on the GRUB screen. The only physical action was
plugging in the stick; Claude Code did the rest over SSH.

1. **Diagnosis**, read-only first: `vgchange -ay`, mount the root read-only, read
   `/var/log/dist-upgrade/`, `dpkg.log`, `/boot`, the ESP and `grub.cfg`.
   - The release upgrade had hung on a debconf prompt (*"configuration file
     /etc/ssh/sshd_config has been locally modified"*), then the machine was rebooted with
     678 packages unpacked but not configured.
   - GRUB's default entry was the new 6.8 kernel, which had **no initramfs**, so the LVM
     root could not be assembled.
2. **Repair** in a chroot (bind-mounted `/dev /proc /sys /run` and efivars), inside `tmux`
   on the rescue system so an SSH drop could not kill it:
   - back up `/var/lib/dpkg` and `/etc`;
   - `dpkg --configure -a` with `--force-confdef --force-confold` (keep local configs);
   - the only blocker was an obsolete out-of-tree `intel-sgx-dkms` that does not build on
     6.8 (SGX is in the kernel since 5.11), so it was purged;
   - `apt full-upgrade`, `update-initramfs`, `update-grub`, GRUB/shim refreshed on the ESP.
3. **Safe reboot**: `efibootmgr -n <ubuntu entry>` (BootNext) for a *one-time* boot into
   the repaired system; a failure would have fallen back to the stick, still first in the
   boot order.
4. **Cleanup** once the machine was back:
   - third-party apt sources moved from bionic/focal/jammy to noble, ~30 stale
     `.distUpgrade`/`.save` lists removed, a rotated signing key fixed;
   - an apt pin so the CUDA repository can never replace Ubuntu's NVIDIA driver or dkms;
   - system Python put back on Ubuntu's own build (it was a PPA build);
   - ~180 obsolete or unused packages and all residual configs purged, conffiles merged;
   - `fancontrol`, broken since the upgrade by hwmon renumbering, fixed, with a pre-start
     hook that renumbers by sensor name;
   - a final reboot to prove it.

Full log of the machine: <https://github.com/ASSERT-KTH/communal-work/issues/8>.

### Lessons

- **Release upgrades on headless servers**: run them inside `tmux`, with
  `DEBIAN_FRONTEND=noninteractive` and `-o Dpkg::Options::=--force-confold`, and never
  reboot until `dpkg --audit` is empty and every kernel in `/boot` has its `initrd.img`.
- On LVM, GRUB cannot record a failed boot; set `GRUB_RECORDFAIL_TIMEOUT` so it does not
  wait forever on the menu.
- Build the rescue stick **before** the incident, test it in QEMU, keep it next to the
  machine.
- What an agent needs to take over: SSH, a way to find the IP (phone home), offline tools,
  and `tmux`. Nothing more.
- Cleanup pitfalls: replacing a PPA `python3.12` with Ubuntu's deleted
  `/usr/bin/python3.12` (owned by the PPA package) until `python3.12-minimal` was
  reinstalled; purging the residual configs of an old NVIDIA driver deleted the
  `nvidia-persistenced` system user. After every purge, check `python3`, failed units and
  service users.

## License

MIT
