#!/bin/bash
# Install the ISO into a throwaway UEFI virtual machine and check the result.
#   test-vm.sh agentbox.iso
# Needs qemu-system-x86_64, OVMF firmware and socat. The test answers the one disk confirmation itself.
set -euo pipefail
iso=$1; d=$(mktemp -d); echo "work dir: $d"
first() { for f in "$@"; do [ -e "$f" ] && { echo "$f"; return; }; done; echo "no OVMF firmware found" >&2; exit 1; }
fw=$(first /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd)
vars=$(first /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS.fd)
cp "$vars" "$d/vars.fd"; qemu-img create -q -f qcow2 "$d/disk.qcow2" 40G
accel=tcg; [ -w /dev/kvm ] && accel=kvm
vm() { qemu-system-x86_64 -accel $accel -cpu max -smp 4 -m 4096 -display none \
  -drive if=pflash,format=raw,readonly=on,file="$fw" -drive if=pflash,format=raw,file="$d/vars.fd" \
  -drive file="$d/disk.qcow2",if=virtio -nic user,model=virtio,hostfwd=tcp:127.0.0.1:2222-:22 \
  -monitor unix:"$d/mon",server,nowait -serial file:"$d/serial.log" "$@"; }
mon() { echo "$1" | socat - unix-connect:"$d/mon" >/dev/null; }
shot() { mon "screendump $d/$1.ppm"; }
echo "installing (accel=$accel)..."
vm -cdrom "$iso" -boot d -no-reboot &
pid=$!
# Answer "Write the changes to disks?" (Tab to Yes, Enter) every 30 s; harmless on other screens.
( i=0; while kill -0 $pid 2>/dev/null; do sleep 30; i=$((i+1)); shot "install-$i" 2>/dev/null || true
    mon "sendkey tab" 2>/dev/null || true; sleep 1; mon "sendkey ret" 2>/dev/null || true; done ) &
wait $pid || true
echo "install finished; booting the installed system..."
vm &
pid=$!; trap 'kill $pid 2>/dev/null' EXIT
sleep "${BOOT_WAIT:-240}"; shot boot
echo "screenshots and serial log in $d; ssh -p 2222 <user>@127.0.0.1 to inspect"
wait $pid
