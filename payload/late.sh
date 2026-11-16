#!/bin/bash
# Runs once inside the freshly installed system, at the end of the Debian installer.
# Everything is logged to /var/log/agentbox-install.log; a failed step is logged and the rest still runs.
U="$1"; H="/home/$U"; P=/opt/agentbox; LOG=/var/log/agentbox-install.log
exec >>"$LOG" 2>&1
export DEBIAN_FRONTEND=noninteractive
step() { echo "== $*"; }
fail() { echo "FAILED: $*"; }

step "packages"
sed -i '/^deb cdrom:/s/^/# /' /etc/apt/sources.list
apt-get update || fail "apt-get update"
while read -r pkg; do
  case "$pkg" in ''|'#'*) continue;; esac
  apt-get install -y --no-install-recommends "$pkg" </dev/null || fail "package $pkg"
done < "$P/packages.txt"

step "/home as its own subvolume, so system snapshots leave it out"
if [ "$(stat -f -c %T /)" = btrfs ] && [ "$(stat -c %i /home)" != 256 ]; then
  mv /home /home.pre && btrfs subvolume create /home && cp -a /home.pre/. /home/ && rm -rf /home.pre || fail "home subvolume"
fi

step "system snapshots: hourly, and around every apt run (the snapper package ships the apt hook)"
snapper --no-dbus -c root create-config / || fail "snapper create-config"
snapper --no-dbus -c root set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
  TIMELINE_LIMIT_HOURLY=6 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 TIMELINE_LIMIT_MONTHLY=0 \
  TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 NUMBER_CLEANUP=yes NUMBER_LIMIT=20 \
  NUMBER_LIMIT_IMPORTANT=5 EMPTY_PRE_POST_CLEANUP=yes || fail "snapper set-config"
systemctl enable snapper-timeline.timer snapper-cleanup.timer || fail "snapper timers"

step "mount /home and /.snapshots by name, so they are also there when the fallback copy of the system boots"
src=$(awk '$2=="/" && $1!~/^#/ {print $1}' /etc/fstab)
sv=$(awk '$2=="/" && $1!~/^#/ {print $4}' /etc/fstab | tr , '\n' | sed -n 's/^subvol=//p'); sv=${sv#/}
for d in home .snapshots; do
  [ "$(stat -c %i /$d)" = 256 ] && echo "$src /$d btrfs defaults,subvol=${sv:+$sv/}$d 0 0" >> /etc/fstab || fail "$d in fstab"
done

step "memory: compressed swap in RAM, pressure killer, thrash protection"
cp -r "$P/etc/." /etc/ || fail "copy /etc files"
systemctl enable systemd-oomd.service || fail "enable oomd"

step "passwordless sudo and key-only SSH for $U"
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agentbox && chmod 440 /etc/sudoers.d/agentbox
if [ -s "$P/authorized_keys" ]; then
  install -d -m 700 -o "$U" -g "$U" "$H/.ssh"
  install -m 600 -o "$U" -g "$U" "$P/authorized_keys" "$H/.ssh/authorized_keys"
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/agentbox.conf
fi

step "desktop and agent tools for $U"
cp -r "$P/home/." "$H/" && chown -R "$U:$U" "$H" || fail "copy home files"
install -m 755 "$P/bin/"* /usr/local/bin/ || fail "install scripts"
systemctl enable agentbox-firstboot.service || fail "enable firstboot"

step "fallback to the last good system after three failed boots"
mkdir -p /boot/efi/agentbox && grub-editenv /boot/efi/agentbox/grubenv create || fail "boot counter file"
systemctl enable agentbox-boot-ok.timer || fail "enable boot-ok timer"
update-initramfs -u || fail "update-initramfs"
update-grub || fail "update-grub"
echo "== done"
