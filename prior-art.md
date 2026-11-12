# Prior art

Projects close to this one, as found by a GitHub search on 2026-11-12 (keyword search sorted
by stars: "rescue iso", "rescue usb", "ssh rescue", topics `rescue-system`, `rescue-disk`).
A project described in other words may be missing.

This project: a generic ~380 MB Alpine stick that turns any computer into an SSH endpoint
for a coding agent running elsewhere. Nobody needs to stay at the broken machine.

## An agent repairs a broken machine

- [crmne/omarchy-rescue](https://github.com/crmne/omarchy-rescue): Arch/Omarchy live ISO
  with SystemRescue-style tools and Claude Code, Codex and OpenCode in the live console.
  The agent runs *on* the broken machine, so someone sits at its keyboard; here the agent
  runs on the operator's machine and the stick only serves SSH.
- [techbysakh963/Lifeline](https://github.com/techbysakh963/Lifeline): an Android app; the
  phone, connected by USB cable, talks to the PC over SSH, types as a USB keyboard or boots
  it as a USB drive, with an approval card before every change. Needs a rooted phone.
- [jmagly/kintsugi-usb](https://github.com/jmagly/kintsugi-usb): Ventoy multi-boot stick
  on Xubuntu with rescue ISOs and an offline LLM (Ollama, llama.cpp). Hands-on, desktop,
  many GB; this project is headless and needs the network.
- [MilkyWay008/Hermes-OTG](https://github.com/MilkyWay008/Hermes-OTG): a portable agent
  run from a USB drive on a working Windows PC; does not boot the machine.

## A stick that boots into remote access

- [Amperstrand/kali-live-headless](https://github.com/Amperstrand/kali-live-headless): Kali
  live USB that joins Wi-Fi and accepts your SSH key, no keyboard or monitor; also a KVM and
  CI-runner host. Closest mechanism. Wi-Fi is something this project lacks (wired DHCP only).
- [ShoeBoom/tailboot](https://github.com/ShoeBoom/tailboot): Debian 13 live image that
  joins your tailnet and starts Tailscale SSH: works behind NAT, which this project does not
  (the agent needs a reachable address).
- [midzelis/zquickinit](https://github.com/midzelis/zquickinit): ZFSBootMenu-based
  bootloader and rescue environment with Tailscale SSH, for remote unlock of encrypted ZFS.
- [SystemRescue](https://www.system-rescue.org/) and
  [nchevsky/systemrescue-zfs](https://github.com/nchevsky/systemrescue-zfs) (adds ZFS and a
  serial console): the reference rescue toolbox, with sshd and a root password set from the
  boot options; ~1 GB, made for a person at the console.
- [Grml](https://grml.org/): Debian live rescue system; the `ssh=` boot option sets a root
  password and starts sshd.
- Alpine's own `ssh_key=` boot option: starts sshd with that key, but only on a diskless
  boot without an apkovl, so not combinable with an overlay like ours.

## Where this project differs

- One generic release for everyone: no credentials baked in, a random password shown on
  screen, and `inject-key.sh` adds a key to a downloaded ISO without root.
- Fits a 1 GB stick: the standard Alpine ISO plus only the dependency closure of the repair
  tools, grafted from the extended ISO's signed repository.
- Field fixes, each covered by `test.sh`: the clock on a dead CMOS battery
  (`rescue-online`), the online repositories once networked, and a retried boot-media
  search for sticks that enumerate late (`initramfs-init.patch`).
