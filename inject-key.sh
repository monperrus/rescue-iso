#!/bin/sh
# Add a public key to a rescue ISO: inject-key.sh IN.iso PUBKEY OUT.iso
# Repacks the apkovl overlay with root's authorized_keys. No root needed.
set -eu
[ $# -eq 3 ] || { echo "usage: $0 IN.iso PUBKEY OUT.iso" >&2; exit 2; }
in="$1" key="$2" out="$3"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
xorriso -osirrox on -indev "$in" -extract /tiramisu-rescue.apkovl.tar.gz "$work/ovl.tgz" 2>/dev/null
chmod u+w "$work/ovl.tgz"
mkdir "$work/ovl"
tar -C "$work/ovl" -xzf "$work/ovl.tgz"
mkdir -p "$work/ovl/root/.ssh"
cat "$key" >> "$work/ovl/root/.ssh/authorized_keys"
chmod 700 "$work/ovl/root" "$work/ovl/root/.ssh"
chmod 600 "$work/ovl/root/.ssh/authorized_keys"
tar -C "$work/ovl" --owner=0 --group=0 -czf "$work/new.tgz" .
rm -f "$out"
xorriso -indev "$in" -outdev "$out" -map "$work/new.tgz" /tiramisu-rescue.apkovl.tar.gz \
	-boot_image any replay 2>/dev/null
