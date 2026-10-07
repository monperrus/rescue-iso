#!/bin/sh
# Build out/tiramisu-rescue.iso (~400 MB, fits a 1 GB stick): the official Alpine standard
# ISO, plus the rescue packages and their dependencies taken from the extended ISO's signed
# repository (same release, same kernel), plus an apkovl overlay (sshd with key + password,
# DHCP on every NIC, on-screen banner, phone home). No root needed.
set -eu
cd "$(dirname "$0")"

VERSION=3.24.2
ISO="alpine-standard-$VERSION-x86_64.iso"
EXTENDED="alpine-extended-$VERSION-x86_64.iso"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${VERSION%.*}/releases/x86_64"
PUBKEY="${RESCUE_PUBKEY:-$HOME/.ssh/assert-server.private.pub}"
# on the standard ISO
BASE_PACKAGES="alpine-base openssh e2fsprogs"
# grafted from the extended ISO
EXTRA_PACKAGES="curl bash util-linux lvm2 cryptsetup mdadm btrfs-progs xfsprogs dosfstools
parted efibootmgr pciutils tmux"
ALPINE_KEY=0482D84022F52DF1C4E7CD43293ACD0907D9495A  # Natanael Copa

mkdir -p cache out
[ -f cache/ncopa.asc ] || curl -fsSL -o cache/ncopa.asc https://alpinelinux.org/keys/ncopa.asc
gpg -q --no-default-keyring --keyring ./cache/alpine.kbx --import cache/ncopa.asc 2>/dev/null
for iso in "$ISO" "$EXTENDED"; do
	if [ ! -f "cache/$iso" ]; then
		curl -fsSL -o "cache/$iso" "$MIRROR/$iso"
		curl -fsSL -o "cache/$iso.asc" "$MIRROR/$iso.asc"
	fi
	gpg --no-default-keyring --keyring ./cache/alpine.kbx --status-fd 1 \
		--verify "cache/$iso.asc" "cache/$iso" 2>/dev/null | grep -q "VALIDSIG $ALPINE_KEY" \
		|| { echo "bad signature on $iso" >&2; exit 1; }
done

# every world package must ship on the media, or apk refuses the whole set at boot
apks="$(xorriso -osirrox on -indev "cache/$ISO" -ls /apks/x86_64 2>/dev/null)"
for p in $BASE_PACKAGES; do
	echo "$apks" | grep -q "^'$p-[0-9]" || { echo "package $p not on the ISO" >&2; exit 1; }
done

# password: three short words, simple to type from the screen
[ -f out/password ] || shuf -n 3 --random-source=/dev/urandom words.txt | paste -sd- > out/password

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# extra repository /extra: the extended ISO's signed index + the closure of EXTRA_PACKAGES;
# the .boot_repository marker makes Alpine's init add it to /etc/apk/repositories
mkdir -p "$work/extra/x86_64"
touch "$work/extra/.boot_repository"
xorriso -osirrox on -indev "cache/$EXTENDED" \
	-extract /apks/x86_64/APKINDEX.tar.gz "$work/extra/x86_64/APKINDEX.tar.gz" 2>/dev/null
chmod u+w "$work/extra/x86_64/APKINDEX.tar.gz"
# shellcheck disable=SC2086
for f in $(python3 -I closure.py "$work/extra/x86_64/APKINDEX.tar.gz" $EXTRA_PACKAGES); do
	xorriso -osirrox on -indev "cache/$EXTENDED" \
		-extract "/apks/x86_64/$f" "$work/extra/x86_64/$f" 2>/dev/null
done
PACKAGES="$BASE_PACKAGES $EXTRA_PACKAGES"
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
initrd	/boot/initramfs-lts
}
menuentry "Tiramisu rescue (ssh, nomodeset)" {
linux	/boot/vmlinuz-lts $cmdline nomodeset
initrd	/boot/initramfs-lts
}
EOF
cat > "$work/syslinux.cfg" <<EOF
TIMEOUT 50
PROMPT 1
DEFAULT rescue

LABEL rescue
MENU LABEL Tiramisu rescue (ssh)
KERNEL /boot/vmlinuz-lts
INITRD /boot/initramfs-lts
APPEND $cmdline

LABEL nomodeset
MENU LABEL Tiramisu rescue (ssh, nomodeset)
KERNEL /boot/vmlinuz-lts
INITRD /boot/initramfs-lts
APPEND $cmdline nomodeset
EOF

rm -f out/tiramisu-rescue.iso
xorriso -indev "cache/$ISO" -outdev out/tiramisu-rescue.iso \
	-map "$work/tiramisu-rescue.apkovl.tar.gz" /tiramisu-rescue.apkovl.tar.gz \
	-map "$work/extra" /extra \
	-map "$work/grub.cfg" /boot/grub/grub.cfg \
	-map "$work/syslinux.cfg" /boot/syslinux/syslinux.cfg \
	-boot_image any replay 2>/dev/null
echo "out/tiramisu-rescue.iso  password: $(cat out/password)"
