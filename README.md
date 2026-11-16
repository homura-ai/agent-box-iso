# agent-box-iso

Builds a Debian installer ISO that sets a laptop up as an agent box with almost no questions:
Debian stable on btrfs, snapshots with rollback, sway for the person at the screen, and virtual
X11 displays for the agents.

## Status

**Tested in a virtual machine only, on 2026-11-16** (QEMU with UEFI firmware, built from Debian
13.7). A clean install from the ISO finished with no failed steps and no failed units, and these
were checked on the installed system: snapshots around `apt` runs, `/home` as its own subvolume,
the kernel inside the root snapshots, grub-btrfs boot-menu entries for each snapshot, zram,
systemd-oomd, the thrash-protection setting, every tool in `payload/packages.txt`, an agent
display driven with xdotool, and the sway config loading without errors.

Not tested: a real laptop (Wi-Fi during install, graphics, firmware), sway on a real screen,
actually booting into a snapshot from the boot menu, and the `move/` scripts beyond
`capture-system.sh`.

## What the installed system has

- **Disk:** one EFI partition and one btrfs partition. `/boot` is inside the btrfs root, so a
  snapshot carries its own kernel. `/home` is a separate subvolume and is left out of system
  snapshots. No disk encryption.
- **Snapshots:** snapper snapshots `/` hourly and before and after every `apt` run.
- **Boot-menu rollback:** on first boot with a network, `agentbox-firstboot` installs grub-btrfs
  from its source, which adds every snapshot to the boot menu.
- **Memory:** compressed swap in RAM (zram), systemd-oomd, and thrash protection.
- **Desktop:** logging in on the first console starts sway (`~/.config/sway/config`).
- **Agent displays:** `agent-display start` gives an agent its own Xvfb screen with openbox;
  `agent-display run CMD` runs one command on a throwaway screen.
- **Access:** the user has passwordless sudo. SSH is key-only when a key is given at build time.

The package list covers what [machine-setup](https://github.com/homura-ai/machine-setup) installs
before it copies an agent stack over, so the installed machine is ready to be a destination for
that kind of move. machine-setup's own scripts still expect Fedora on the destination.

Not included: the agent stack itself (Claude Code, Codex, T3 Code, the proxies) and any
credentials. Automatic fallback to the last good snapshot after a failed boot is not built.

## Build

```bash
cp agentbox.env.example agentbox.env    # then edit it
./build-iso.sh --out agentbox.iso
```

Or pass the settings as flags: `--user NAME --hostname NAME --timezone TZ --ssh-key FILE`.

It downloads the current Debian netinst image, checks its checksum, and adds the answers file
(`preseed.cfg.in`) and `payload/`. The password hash is the only secret in the ISO; set
`AGENTBOX_PASSWORD` or let the script generate one.

## Install

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
- `move/capture-system.sh`: run on the old machine; records the packages, system units, flatpaks,
  firewall and changed `/etc` files that have to be re-created on the new one.
- `move/send-home.sh`: run on the old machine; copies all of `/home` to the new machine with
  `btrfs send` and prints the command that switches the new machine to it.
