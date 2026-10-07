#!/bin/sh
# Boot out/tiramisu-rescue.iso in QEMU as a USB stick and check it is remotely debuggable.
# usage: ./test.sh [bios|uefi]
set -eu
cd "$(dirname "$0")"

FIRMWARE="${1:-bios}"
PORT=2222
ISO=out/tiramisu-rescue.iso
PASSWORD="$(cat out/password)"
work="$(mktemp -d)"
SSH="ssh -p $PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

firmware_args=""
if [ "$FIRMWARE" = uefi ]; then
	cp /usr/share/OVMF/OVMF_VARS_4M.fd "$work/vars.fd"
	firmware_args="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
		-drive if=pflash,format=raw,file=$work/vars.fd"
fi

# shellcheck disable=SC2086
qemu-system-x86_64 -enable-kvm -m 2048 -display none -snapshot $firmware_args \
	-device qemu-xhci -drive if=none,id=stick,format=raw,file="$ISO" \
	-device usb-storage,drive=stick,bootindex=0 \
	-nic user,hostfwd=tcp:127.0.0.1:$PORT-:22 \
	-pidfile "$work/qemu.pid" -daemonize
trap 'kill "$(cat "$work/qemu.pid")" 2>/dev/null; rm -rf "$work"' EXIT

fail() { echo "FAIL ($FIRMWARE): $*" >&2; exit 1; }

i=0
KEY="-o BatchMode=yes -o IdentitiesOnly=yes -i $HOME/.ssh/assert-server.private.pub"
until $SSH $KEY root@127.0.0.1 true 2>/dev/null; do
	i=$((i + 1))
	[ $i -gt 36 ] && fail "no key login after 180 s"
	sleep 5
done
echo "ok   key login (assert-server)"

sshpass -p "$PASSWORD" $SSH -o PubkeyAuthentication=no root@127.0.0.1 true \
	|| fail "password login refused"
echo "ok   password login"

if sshpass -p wrong-password $SSH -o PubkeyAuthentication=no root@127.0.0.1 true 2>/dev/null; then
	fail "wrong password accepted"
fi
echo "ok   wrong password refused"

$SSH $KEY root@127.0.0.1 "sleep 12; grep -q '$PASSWORD' /etc/issue && grep -qE '^    eth0 [0-9.]+/' /etc/issue" \
	|| fail "banner lacks password or address"
echo "ok   banner shows password and address"

$SSH $KEY root@127.0.0.1 'for t in lsblk vgchange cryptsetup mdadm e2fsck btrfs xfs_repair efibootmgr parted lspci tmux chroot; do command -v $t >/dev/null || { echo missing $t; exit 1; }; done' \
	|| fail "rescue tools missing"
echo "ok   rescue tools present"
echo "PASS ($FIRMWARE)"
