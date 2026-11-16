#!/bin/bash
# Run on the old machine. Records everything outside /home that the new machine needs re-created:
# packages, system units and the files they run, changed /etc files, flatpaks, firewall, cron.
#   capture-system.sh [OUT_DIR]   (default ~/.local/state/agent-box-iso/inventory)
# Read-only apart from OUT_DIR. The inventory can hold private names: keep it out of public repos.
set -uo pipefail
out=${1:-$HOME/.local/state/agent-box-iso/inventory}; mkdir -p "$out/units" "$out/etc"; chmod 700 "$out"
if command -v dnf >/dev/null; then dnf repoquery --userinstalled --qf '%{name}\n' 2>/dev/null | sort -u > "$out/packages.txt"
else apt-mark showmanual | sort -u > "$out/packages.txt"; fi
flatpak list --app --columns=installation,application,origin 2>/dev/null > "$out/flatpaks.txt" || true
# System units that are not owned by any package: someone put them there on purpose.
for u in /etc/systemd/system/*.service /etc/systemd/system/*.timer /etc/systemd/system/*.path /etc/systemd/system/*.socket; do
  [ -f "$u" ] && [ ! -L "$u" ] || continue
  cp -p "$u" "$out/units/"
  grep -hoE '^Exec(Start|StartPre|Stop)=[-+!@]*[^ ]+' "$u" | sed -E 's/^[^=]+=[-+!@]*//' >> "$out/unit-programs.txt"
done
sort -u -o "$out/unit-programs.txt" "$out/unit-programs.txt" 2>/dev/null || true
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' | sort > "$out/enabled-system-units.txt"
systemctl --user list-unit-files --state=enabled --no-legend | awk '{print $1}' | sort > "$out/enabled-user-units.txt"
sudo -n firewall-cmd --list-all-zones > "$out/firewall.txt" 2>/dev/null || sudo -n nft list ruleset > "$out/firewall.txt" 2>/dev/null || true
sudo -n sh -c 'for f in /etc/sudoers.d/* /etc/sysctl.d/*.conf /etc/systemd/zram-generator.conf /etc/systemd/oomd.conf.d/* /etc/systemd/system.conf.d/* /etc/systemd/logind.conf.d/* /etc/NetworkManager/conf.d/* /etc/fstab /etc/hosts /etc/crontab /etc/cron.d/*; do [ -f "$f" ] && echo "$f"; done' > "$out/etc-files.txt" 2>/dev/null || true
while read -r f; do sudo -n cp --parents -p "$f" "$out/etc/" 2>/dev/null; done < "$out/etc-files.txt"
sudo -n chown -R "$(id -u):$(id -g)" "$out"
crontab -l > "$out/crontab-user.txt" 2>/dev/null || true
{ echo "host: $(hostname)"; . /etc/os-release; echo "os: $PRETTY_NAME"; echo "kernel: $(uname -r)"; echo "user: $(id -un) uid=$(id -u)"; echo "python: $(python3 --version 2>&1)"; } > "$out/summary.txt"
echo "inventory in $out:"; wc -l "$out"/*.txt | sed 's/^/  /'
