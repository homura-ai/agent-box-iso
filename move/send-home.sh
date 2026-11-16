#!/bin/bash
# Run on the old machine. Copies the whole of /home to the new machine as one btrfs snapshot.
#   send-home.sh [--dry-run] NEW_HOST
# Both machines need /home on btrfs and passwordless sudo, and SSH must already work to NEW_HOST.
# Nothing on the new machine is replaced: the copy lands at /home-from-<oldhost>, and the last
# line printed is the command that swaps it in. Subvolumes nested inside /home are not carried
# by btrfs send; they are listed so each can be sent the same way.
set -euo pipefail
dry=""; [ "${1:-}" = --dry-run ] && { dry=1; shift; }
new=${1:?usage: send-home.sh [--dry-run] NEW_HOST}
name="home-from-$(hostname)"; snap="/home/.send-$name"
run() { echo "+ $*"; [ -n "$dry" ] || "$@"; }
echo "nested subvolumes that will NOT be copied:"
sudo -n btrfs subvolume list -o /home | awk '{print "  " $NF}' | grep -v '\.snapshots' || echo "  (none besides snapshots)"
ssh -o BatchMode=yes "$new" 'sudo -n true && [ "$(stat -f -c %T /home)" = btrfs ] && ! sudo test -e "/'"$name"'"' \
  || { echo "new machine: need passwordless sudo, btrfs /home, and no existing /$name" >&2; exit 1; }
[ -e "$snap" ] && run sudo -n btrfs subvolume delete "$snap"
run sudo -n btrfs subvolume snapshot -r /home "$snap"
echo "+ btrfs send $snap | ssh $new btrfs receive /   (this is the long step)"
if [ -z "$dry" ]; then
  sudo -n btrfs send "$snap" | ssh "$new" 'sudo -n btrfs receive / && sudo -n mv "/'".send-$name"'" "/'"$name"'"'
fi
run sudo -n btrfs subvolume delete "$snap"
cat <<MSG
copied. To switch the new machine to it, log out of the desktop there and run on $new:
  sudo btrfs subvolume snapshot /$name /home.new && sudo mv /home /home.installer && sudo mv /home.new /home && sudo reboot
/home.installer and /$name can be deleted (btrfs subvolume delete) once the new home is confirmed.
MSG
