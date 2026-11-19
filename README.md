# agent-box-iso

Builds a Debian installer ISO that sets a laptop up as an agent box with almost no questions:
Debian stable on btrfs, snapshots with rollback, sway for the person at the screen, and virtual
X11 displays for the agents.

## What the installed system has

- **Disk:** one EFI partition and one btrfs partition. `/boot` is inside the btrfs root, so a
  snapshot carries its own kernel. `/home` is a separate subvolume and is left out of system
  snapshots. No disk encryption.
- **Snapshots:** snapper snapshots `/` hourly and before and after every `apt` run.
- **Boot-menu rollback:** on first boot with a network, `agentbox-firstboot` installs grub-btrfs
  from its source, which adds every snapshot to the boot menu.
- **Failed-boot fallback:** three minutes into a good boot, `agentbox-boot-ok` keeps a writable
  copy of the system in `/.agentbox-good` and clears a boot counter kept on the EFI partition.
  After two boots in a row that never get that far, GRUB boots the copy on the third. A kernel
  panic reboots after 20 seconds, a root filesystem with no init after 10, and a boot that hangs
  after 15 minutes, so failures count without anyone at the machine. The copy keeps booting until
  `sudo agentbox-restore` copies it over the main system; the broken state is kept as a read-only
  snapshot `/.agentbox-broken-<time>`. `/home` is never touched.
- **Memory:** compressed swap in RAM (zram), systemd-oomd, and thrash protection.
- **Desktop:** logging in on the first console starts sway (`~/.config/sway/config`).
- **Agent displays:** `agent-display start` gives an agent its own Xvfb screen with openbox;
  `agent-display run CMD` runs one command on a throwaway screen.
- **Access:** the user has passwordless sudo. SSH is key-only when a key is given at build time.

Not included: the agent stack itself (Claude Code, Codex, T3 Code, the proxies) and any
credentials.

## Build

Requires `xorriso`, `curl`, `sha256sum`, `openssl` and Python 3. Checksum-file
signature verification also requires `gpgv` and the Debian role keyring at
`/usr/share/keyrings/debian-role-keys.gpg`; without them the build warns and
checks only the downloaded checksum.

```bash
cp agentbox.env.example agentbox.env    # then edit it
./build-iso.sh --out agentbox.iso
```

Or pass the settings as flags: `--user NAME --hostname NAME --timezone TZ --ssh-key FILE`.

It downloads the current Debian netinst image, checks its checksum, and adds the answers file
(`preseed.cfg.in`) and `payload/`. The password hash is the only secret in the ISO; set
`AGENTBOX_PASSWORD` or let the script generate one.

## Install

The installer has been tested in a virtual machine. Hardware compatibility on
physical laptops is unverified.

Write the ISO to a USB stick and boot it in UEFI mode with a wired or known network. The first
menu entry runs the whole install. It stops once, at "Write the changes to disks?", and asks
which disk if there is more than one. **Answering yes erases that disk.** The log of the
post-install step is `/var/log/agentbox-install.log` on the installed system.

## Test

```bash
./test-vm.sh agentbox.iso
```

## Files

- `preseed.cfg.in`: the installer's answers.
- `payload/late.sh`: runs at the end of the install, inside the new system.
- `payload/packages.txt`: packages to install, one per line.
- `payload/etc/`, `payload/home/`, `payload/bin/`: files copied into the new system.
