# Instructions for Claude Code — New Machine Sync

This document tells you exactly what to do on the new machine to make it
an exact mirror of Frik's source Arch Linux system.

## Context

- **Source machine**: frik-arch (Arch Linux, AMD Ryzen 5 5600, AMD RX 9060 XT)
- **Target machine**: new PC with NVIDIA GPU
- **Goal**: make the target machine's packages and configs exactly match the source

The USB drive has two directories:
- `arch-install/` — install/sync scripts and dotfiles
- `arch-backup/` — personal data (Zen browser, Obsidian, VSCodium settings, etc.)

## Step 1 — Check for package mismatches

Run a dry-run first to see what differs:

```bash
cd /mnt/usb/arch-install   # or wherever arch-install is
./sync.sh --dry-run
```

This will show you:
- Packages on the new machine NOT on the source → these get removed (except nvidia*)
- Packages on the source NOT on the new machine → these get installed

## Step 2 — Apply the sync

```bash
./sync.sh
```

It will ask for confirmation before removing anything. NVIDIA packages are
always protected and will never be removed.

## Step 3 — Restore personal data

```bash
./restore.sh /mnt/usb/arch-backup/
```

## Step 4 — Reboot

```bash
sudo reboot
```

## After reboot

```bash
gh auth login      # re-authenticate GitHub CLI
```

Then inside Hyprland:
- `SUPER+W` — wallpaper/theme picker
- `SUPER+M` — music player (rmpc + cava)

---

## What sync.sh does exactly

1. Reads `packages/pacman-explicit.txt` and `packages/aur-explicit.txt`
   (generated from the source machine — 96 pacman + 23 AUR packages)
2. Compares against `pacman -Qqe` on the current machine
3. Removes packages present here but not on source — **except**:
   - `nvidia*` — GPU drivers
   - `linux*` — kernel
   - `base`, `base-devel`, `sudo`, `grub`, `efibootmgr` — system essentials
   - `intel-ucode`, `amd-ucode` — CPU microcode
4. Installs packages on source missing from here
5. Updates frik-rice and re-runs its install.sh for configs/symlinks

---

## If something looks wrong

Check what packages are on the new machine that weren't on the source:

```bash
comm -23 <(pacman -Qqe | sort) <(sort packages/pacman-explicit.txt packages/aur-explicit.txt | sort -u)
```

Check what's missing from the new machine:

```bash
comm -23 <(sort packages/pacman-explicit.txt packages/aur-explicit.txt | sort -u) <(pacman -Qqe | sort)
```

---

## Source package counts (as of snapshot)

- Official (pacman): 96 packages
- AUR (yay): 23 packages
- Total explicit: 119 packages
