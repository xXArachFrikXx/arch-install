# arch-install

Complete system replication for Frik's Arch Linux + Hyprland desktop.

## What this repo does

Installs and configures everything on a fresh Arch Linux system:

- All packages (pacman + AUR via yay)
- Hyprland WM + Waybar + Rofi + Kitty + Swaync + all configs
- GRUB with YoRHa theme
- SDDM login screen (YoRHa theme)
- Zsh + Oh My Zsh + Starship prompt
- Audio stack: MPD + PipeWire + rmpc + cava
- Theming: matugen + pywal + wpgtk
- Apps: Vesktop, Zen Browser, VSCodium, Obsidian, FreeTube, Steam, LibreOffice, Picard, spotdl...
- App Blocker daemon (daily playtime quotas)
- All systemd user services
- Extra dotfiles (.bashrc, .gitconfig, gh config, mimeapps, etc.)
- NVIDIA support (optional flag)

Configs come from [frik-rice](https://github.com/xXArachFrikXx/frik-rice) — cloned automatically.

---

## Full Workflow

### On the OLD machine — before you leave

```bash
git clone https://github.com/xXArachFrikXx/arch-install
cd arch-install

# Back up music, Wine prefix, browser profiles, app data → USB drive
./backup.sh /run/media/Frik/<USB-name>/arch-backup/
```

This copies ~14 GB (music, Clip Studio Paint Wine prefix, Zen browser, Vesktop,
Obsidian, VSCodium settings, FreeTube, app blocker config, and more).
Steam games are excluded — re-download them on the new PC.

---

### On the NEW machine — after base Arch install

Prerequisites: Arch installed, user account created with sudo, internet connected.

```bash
git clone https://github.com/xXArachFrikXx/arch-install
cd arch-install

# Install everything (add --nvidia if new PC has NVIDIA GPU)
./install.sh --nvidia

# Restore personal data from USB
./restore.sh /run/media/<user>/<USB-name>/arch-backup/

sudo reboot
```

---

## NVIDIA Support

Pass `--nvidia` to install.sh to:

1. Install `nvidia-open`, `nvidia-utils`, `lib32-nvidia-utils`
2. Add NVIDIA kernel modules to mkinitcpio and rebuild initramfs
3. Add `nvidia-drm.modeset=1` kernel parameter to GRUB
4. Link `nvidia/nvidia-env.conf` → `~/.config/hypr/Modules/nvidia-env.conf`

After install, add one line to `~/.config/hypr/hyprland.lua`:

```lua
require("Modules/nvidia-env")
```

---

## Scripts

| Script | Where to run | Purpose |
|--------|-------------|---------|
| `install.sh` | New machine | Installs all software + configs |
| `backup.sh` | Old machine | Backs up personal data to USB |
| `restore.sh` | New machine | Restores personal data from USB |

---

## Repo Structure

```
arch-install/
├── install.sh          Master setup script
├── backup.sh           Pre-departure backup to USB
├── restore.sh          Post-install restore from USB
├── dotfiles/           Extra dotfiles not in frik-rice
│   ├── home/           .bashrc, .bash_profile, .gitconfig
│   └── config/         gh/config.yml, mimeapps.list, pavucontrol.ini, QtProject.conf
├── grub/
│   ├── grub.default    /etc/default/grub template
│   └── yorha/          YoRHa GRUB boot theme (11 files)
├── local-bin/
│   └── appblocker      Daily playtime quota enforcer (Python)
├── systemd/user/       User systemd services (appblocker, awww-daemon, csp-wineserver)
└── nvidia/
    └── nvidia-env.conf Hyprland NVIDIA env vars (hl.env() Lua syntax)
```

---

## After First Boot

1. **Auth GitHub CLI**: `gh auth login`
2. **Monitor layout**: `hyprctl monitors` → edit `~/.config/hypr/Modules/Monitors.lua`
3. **Theme picker**: `SUPER+W`
4. **Music**: `SUPER+M` (rmpc + cava overlay)
5. **Keybinds**: `~/frik-rice/docs/KEYBINDS.md`
