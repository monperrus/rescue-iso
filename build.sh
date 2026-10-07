#!/bin/sh
# Build out/tiramisu-rescue.iso: the official Alpine extended ISO plus an apkovl overlay
# (sshd with key + password, DHCP on every NIC, on-screen banner, phone home). No root needed.
set -eu
cd "$(dirname "$0")"

VERSION=3.24.2
ISO="alpine-extended-$VERSION-x86_64.iso"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${VERSION%.*}/releases/x86_64"
PUBKEY="${RESCUE_PUBKEY:-$HOME/.ssh/assert-server.private.pub}"
PACKAGES="alpine-base openssh curl bash util-linux lvm2 cryptsetup mdadm e2fsprogs
btrfs-progs xfsprogs dosfstools parted efibootmgr pciutils tmux"
ALPINE_KEY=0482D84022F52DF1C4E7CD43293ACD0907D9495A  # Natanael Copa

mkdir -p cache out
if [ ! -f "cache/$ISO" ]; then
	curl -fsSL -o "cache/$ISO" "$MIRROR/$ISO"
	curl -fsSL -o "cache/$ISO.asc" "$MIRROR/$ISO.asc"
	curl -fsSL -o cache/ncopa.asc https://alpinelinux.org/keys/ncopa.asc
fi
gpg -q --no-default-keyring --keyring ./cache/alpine.kbx --import cache/ncopa.asc 2>/dev/null
gpg --no-default-keyring --keyring ./cache/alpine.kbx --status-fd 1 \
	--verify "cache/$ISO.asc" "cache/$ISO" 2>/dev/null | grep -q "VALIDSIG $ALPINE_KEY" \
	|| { echo "bad signature on $ISO" >&2; exit 1; }

# every world package must ship on the media, or apk refuses the whole set at boot
apks="$(xorriso -osirrox on -indev "cache/$ISO" -ls /apks/x86_64 2>/dev/null)"
for p in $PACKAGES; do
	echo "$apks" | grep -q "^'$p-[0-9]" || { echo "package $p not on the ISO" >&2; exit 1; }
done

# password: three short words, simple to type from the screen
[ -f out/password ] || shuf -n 3 --random-source=/dev/urandom words.txt | paste -sd- > out/password

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -a overlay "$work/ovl"
o="$work/ovl"
mkdir -p "$o/etc/apk" "$o/etc/rescue" "$o/root/.ssh" "$o/etc/runlevels/default"
echo tiramisu-rescue > "$o/etc/hostname"
printf '127.0.0.1\ttiramisu-rescue localhost\n' > "$o/etc/hosts"
echo "$PACKAGES" | tr ' ' '\n' | grep . > "$o/etc/apk/world"
cp out/password "$o/etc/rescue/password"
cp "$PUBKEY" "$o/root/.ssh/authorized_keys"
chmod 700 "$o/root" "$o/root/.ssh" "$o/etc/rescue"
chmod 600 "$o/root/.ssh/authorized_keys" "$o/etc/rescue/password"
chmod 755 "$o/etc/local.d/rescue.start"
# keep Alpine's default sysinit/boot/shutdown services alongside ours
touch "$o/etc/.default_boot_services"
ln -s /etc/init.d/sshd "$o/etc/runlevels/default/sshd"
ln -s /etc/init.d/local "$o/etc/runlevels/default/local"
tar -C "$o" --owner=0 --group=0 -czf "$work/tiramisu-rescue.apkovl.tar.gz" .

# boot menus: verbose, no console blanking, a nomodeset fallback entry
cmdline="modules=loop,squashfs,sd-mod,usb-storage consoleblank=0"
cat > "$work/grub.cfg" <<EOF
set timeout=5

menuentry "Tiramisu rescue (ssh)" {
linux	/boot/vmlinuz-lts $cmdline
initrd	/boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}
menuentry "Tiramisu rescue (ssh, nomodeset)" {
linux	/boot/vmlinuz-lts $cmdline nomodeset
initrd	/boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}
EOF
cat > "$work/syslinux.cfg" <<EOF
TIMEOUT 50
PROMPT 1
DEFAULT rescue

LABEL rescue
MENU LABEL Tiramisu rescue (ssh)
KERNEL /boot/vmlinuz-lts
INITRD /boot/intel-ucode.img,/boot/amd-ucode.img,/boot/initramfs-lts
APPEND $cmdline

LABEL nomodeset
MENU LABEL Tiramisu rescue (ssh, nomodeset)
KERNEL /boot/vmlinuz-lts
INITRD /boot/intel-ucode.img,/boot/amd-ucode.img,/boot/initramfs-lts
APPEND $cmdline nomodeset
EOF

rm -f out/tiramisu-rescue.iso
xorriso -indev "cache/$ISO" -outdev out/tiramisu-rescue.iso \
	-map "$work/tiramisu-rescue.apkovl.tar.gz" /tiramisu-rescue.apkovl.tar.gz \
	-map "$work/grub.cfg" /boot/grub/grub.cfg \
	-map "$work/syslinux.cfg" /boot/syslinux/syslinux.cfg \
	-boot_image any replay 2>/dev/null
echo "out/tiramisu-rescue.iso  password: $(cat out/password)"
