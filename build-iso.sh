#!/bin/bash
# Build the agent box installer ISO from an official Debian netinst image.
#   build-iso.sh [--env FILE] [--user NAME] [--hostname NAME] [--timezone TZ] [--ssh-key FILE] [--out FILE]
# Settings: FILE (default ./agentbox.env next to this script; see agentbox.env.example),
# overridden by the flags. The login password comes from AGENTBOX_PASSWORD, or a random one is
# generated and printed once.
# Needs: xorriso, curl, sha256sum, openssl, python3; gpgv and the Debian keyring to check signatures.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
env_file="$here/agentbox.env"; args=("$@")
while [ $# -gt 0 ]; do [ "$1" = --env ] && env_file=$2; shift; done
set -- "${args[@]}"
# shellcheck source=/dev/null
[ -f "$env_file" ] && . "$env_file"
user=${AGENTBOX_USER:-}; host=${AGENTBOX_HOSTNAME:-agentbox}; tz=${AGENTBOX_TIMEZONE:-Etc/UTC}
key=${AGENTBOX_SSH_KEY:-}; out="$PWD/agentbox.iso"
while [ $# -gt 0 ]; do case "$1" in
  --env) shift 2;; --user) user=$2; shift 2;; --hostname) host=$2; shift 2;; --timezone) tz=$2; shift 2;;
  --ssh-key) key=$2; shift 2;; --out) out=$2; shift 2;;
  *) sed -n '2,7p' "$0"; exit 2;; esac; done
[ -n "$user" ] || { echo "set the login name with --user or AGENTBOX_USER" >&2; exit 2; }
[[ $user =~ ^[a-z][a-z0-9_-]*$ && $host =~ ^[a-z0-9][a-z0-9-]*$ && $tz =~ ^[A-Za-z0-9_+/-]+$ ]] || { echo "bad user, hostname or timezone" >&2; exit 2; }

base=${DEBIAN_ISO_BASE:-https://cdimage.debian.org/debian-cd/current/amd64/iso-cd}
cache=${AGENTBOX_CACHE:-$HOME/.cache/agent-box-iso}; mkdir -p "$cache"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl -fsSL "$base/SHA256SUMS" -o "$work/SHA256SUMS"
if command -v gpgv >/dev/null && [ -r /usr/share/keyrings/debian-role-keys.gpg ]; then
  curl -fsSL "$base/SHA256SUMS.sign" -o "$work/SHA256SUMS.sign"
  gpgv --keyring /usr/share/keyrings/debian-role-keys.gpg "$work/SHA256SUMS.sign" "$work/SHA256SUMS"
else
  echo "warning: checksum file signature not checked (no gpgv or Debian keyring here)" >&2
fi
iso=$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2; exit}' "$work/SHA256SUMS")
[ -n "$iso" ] || { echo "no netinst image listed at $base" >&2; exit 1; }
[ -f "$cache/$iso" ] || curl -fL "$base/$iso" -o "$cache/$iso.part" && [ -f "$cache/$iso" ] || mv "$cache/$iso.part" "$cache/$iso"
(cd "$cache" && grep " $iso\$" "$work/SHA256SUMS" | sha256sum -c -)

pw=${AGENTBOX_PASSWORD:-}
if [ -z "$pw" ]; then pw=$(openssl rand -base64 12); echo "login password for $user (shown once): $pw"; fi
hash=$(printf '%s' "$pw" | openssl passwd -6 -stdin)

cp -r "$here/payload" "$work/agentbox"
if [ -n "$key" ]; then cp "$key" "$work/agentbox/authorized_keys"; fi
python3 - "$here/preseed.cfg.in" "$work/preseed.cfg" "$user" "$host" "$tz" "$hash" <<'PY'
import sys
src, dst, user, host, tz, pwhash = sys.argv[1:]
text = open(src).read()
for k, v in {"@USER@": user, "@HOSTNAME@": host, "@TIMEZONE@": tz, "@PWHASH@": pwhash}.items():
    text = text.replace(k, v)
open(dst, "w").write(text)
PY

xorriso -osirrox on -indev "$cache/$iso" -extract /boot/grub/grub.cfg "$work/grub.orig" 2>/dev/null
chmod u+w "$work/grub.orig"
{
  awk '/^menuentry|^submenu/ {exit} {print}' "$work/grub.orig"
  cat <<'G'
set timeout=10
set default=0
menuentry "Agent box: automated install (asks before erasing a disk)" {
    set background_color=black
    linux    /install.amd/vmlinuz auto=true priority=high locale=en_US.UTF-8 keymap=us file=/cdrom/preseed.cfg --- quiet
    initrd   /install.amd/initrd.gz
}
G
  awk 'f || /^menuentry|^submenu/ {f=1; print}' "$work/grub.orig"
} > "$work/grub.cfg"

rm -f "$out"
xorriso -indev "$cache/$iso" -outdev "$out" -boot_image any replay \
  -map "$work/preseed.cfg" /preseed.cfg -map "$work/agentbox" /agentbox \
  -map "$work/grub.cfg" /boot/grub/grub.cfg -volid AGENTBOX
echo "built $out from $iso (UEFI boot only)"
