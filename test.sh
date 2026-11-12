#!/bin/sh
# Boot out/tiramisu-rescue.iso in QEMU as a USB stick and check it is remotely debuggable.
# usage: ./test.sh [bios|uefi|late]   (tests a generic ISO with a throwaway key injected)
# late: direct kernel boot with no stick, plugged in 15 s later, like a stick whose
# enumeration stalls on a descriptor-read timeout (error -110)
set -eu
cd "$(dirname "$0")"

FIRMWARE="${1:-bios}"
PORT=2222
work="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N "" -f "$work/key"
./inject-key.sh out/tiramisu-rescue.iso "$work/key.pub" "$work/test.iso"
ISO="$work/test.iso"
SSH="ssh -p $PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

firmware_args=""
stick_args="-drive if=none,id=stick,format=raw,file=$ISO -device usb-storage,drive=stick,bootindex=0"
if [ "$FIRMWARE" = late ]; then
	xorriso -osirrox on -indev "$ISO" -extract /boot/vmlinuz-lts "$work/vmlinuz" \
		-extract /boot/initramfs-lts "$work/initramfs" 2>/dev/null
	cmdline="$(xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg /dev/stdout 2>/dev/null \
		| sed -n 's|^linux\t/boot/vmlinuz-lts ||p' | head -1)"
	firmware_args="-kernel $work/vmlinuz -initrd $work/initramfs -monitor unix:$work/mon,server,nowait"
	stick_args=""
elif [ "$FIRMWARE" = uefi ]; then
	cp /usr/share/OVMF/OVMF_VARS_4M.fd "$work/vars.fd"
	firmware_args="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
		-drive if=pflash,format=raw,file=$work/vars.fd"
fi

# shellcheck disable=SC2086
qemu-system-x86_64 -enable-kvm -m 2048 -display none -snapshot $firmware_args \
	-device qemu-xhci $stick_args ${cmdline:+-append "$cmdline"} \
	-nic user,hostfwd=tcp:127.0.0.1:$PORT-:22 -rtc base=2016-01-18 \
	-pidfile "$work/qemu.pid" -daemonize
trap 'kill "$(cat "$work/qemu.pid")" 2>/dev/null; rm -rf "$work"' EXIT
if [ "$FIRMWARE" = late ]; then
	sleep 15
	printf 'drive_add 0 if=none,id=stick,format=raw,file=%s\ndevice_add usb-storage,drive=stick\n' "$ISO" \
		| socat - "UNIX-CONNECT:$work/mon" >/dev/null
fi

fail() { echo "FAIL ($FIRMWARE): $*" >&2; exit 1; }

i=0
KEY="-o BatchMode=yes -o IdentitiesOnly=yes -i $work/key"
until $SSH $KEY root@127.0.0.1 true 2>/dev/null; do
	i=$((i + 1))
	[ $i -gt 36 ] && fail "no key login after 180 s"
	sleep 5
done
echo "ok   key login"

PASSWORD="$($SSH $KEY root@127.0.0.1 "sleep 12; sed -n 's/.*password: //p' /etc/issue")"
[ -n "$PASSWORD" ] || fail "no password in banner"

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

# the RTC above simulates a dead CMOS battery; online fixes need the host's internet access
year="$(date -u +%Y)"
$SSH $KEY root@127.0.0.1 "i=0; until grep -q '^apk:' /var/log/rescue-online.log 2>/dev/null; do i=\$((i+1)); [ \$i -gt 30 ] && break; sleep 2; done; cat /var/log/rescue-online.log; [ \$(date -u +%Y) -ge $year ]" \
	|| fail "clock still in 2016"
echo "ok   clock set despite a 2016 RTC"
$SSH $KEY root@127.0.0.1 "date -u -s '2016-01-18 00:00:00' >/dev/null; RESCUE_NO_NTP=1 rescue-online | tee /dev/stderr | grep -q 'HTTP Date' && [ \$(date -u +%Y) -ge $year ]" \
	|| fail "HTTP Date fallback did not set the clock"
echo "ok   clock set from the HTTP Date header without NTP"
$SSH $KEY root@127.0.0.1 'apk add -q wipefs && command -v wipefs >/dev/null' \
	|| fail "apk cannot install from the online repositories"
echo "ok   apk installs from the online repositories"
echo "PASS ($FIRMWARE)"
