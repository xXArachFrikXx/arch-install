# System Setup Instructions

When the user asks you to set up or sync this system, run these steps
automatically without asking for confirmation unless something goes wrong.

## What this is

This is Frik's Arch Linux + Hyprland system replication repo. The goal is to
make the current machine an exact mirror of the source system (frik-arch).

The USB has two directories:
- `arch-install/` — scripts, dotfiles, configs (you are here)
- `arch-backup/` — personal data (Zen browser, Obsidian, VSCodium, etc.)

## Steps to run (in order)

### 1. Find and mount the USB

```bash
lsblk | grep -v loop
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb
```

### 2. Sync packages and configs

```bash
cd /mnt/usb/arch-install
./sync.sh
```

This will:
- Remove packages on this machine not on the source (never removes nvidia/kernel/base)
- Install missing packages from the source
- Pull latest frik-rice from GitHub and re-apply all configs/symlinks
- Clean up orphaned dependencies

### 3. Restore personal data

```bash
./restore.sh /mnt/usb/arch-backup/
```

### 4. Unmount USB and reboot

```bash
sudo umount /mnt/usb
sudo reboot
```

### 5. After reboot

```bash
gh auth login
```

## If something looks wrong with packages

Run the dry-run first to see what would change:

```bash
./sync.sh --dry-run
```

## Source system reference

- **Distro**: Arch Linux (frik-arch)
- **WM**: Hyprland (Wayland)
- **GPU on new machine**: NVIDIA (nvidia-open drivers — never remove these)
- **Package counts**: 96 pacman + 23 AUR = 119 explicit packages
- **frik-rice repo**: https://github.com/xXArachFrikXx/frik-rice
- **arch-install repo**: https://github.com/xXArachFrikXx/arch-install
