#!/usr/bin/env bash
# =============================================================================
# arch-install — Frik's complete system setup script
# =============================================================================
#
# Replicates a full Arch Linux + Hyprland desktop on a fresh install.
# Run as a normal user (not root) after initial Arch setup.
#
# Usage:
#   ./install.sh              — standard install (AMD/auto GPU)
#   ./install.sh --nvidia     — install nvidia-open + configure Hyprland for NVIDIA
#   ./install.sh --dry-run    — show what would happen, make no changes
#
# Prerequisites: fresh Arch install, user account with sudo, internet connection
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRIK_RICE_DIR="$HOME/frik-rice"
FRIK_RICE_URL="https://github.com/xXArachFrikXx/frik-rice.git"

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
NVIDIA=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --nvidia)  NVIDIA=true  ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

section() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${BLUE}║  %-52s║${NC}\n" "$1"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
}

ok()   { echo -e "  ${GREEN}[✓]${NC} $1"; }
skip() { echo -e "  ${YELLOW}[~]${NC} (skip) $1"; }
info() { echo -e "  ${CYAN}[-]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
err()  { echo -e "  ${RED}[✗]${NC} $1" >&2; }

run()  { $DRY_RUN && echo -e "  ${MAGENTA}[dry]${NC} $*" || "$@"; }
srun() { $DRY_RUN && echo -e "  ${MAGENTA}[dry]${NC} sudo $*" || sudo "$@"; }

is_installed() { pacman -Qi "$1" &>/dev/null; }

pacman_install() {
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" && { skip "$pkg"; continue; }
        info "queued: $pkg"; to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return
    info "Installing ${#to_install[@]} package(s) via pacman..."
    srun pacman -S --needed --noconfirm "${to_install[@]}"
    ok "Installed: ${to_install[*]}"
}

yay_install() {
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" && { skip "$pkg"; continue; }
        info "queued: $pkg"; to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return
    info "Installing ${#to_install[@]} AUR package(s) via yay..."
    run yay -S --needed --noconfirm "${to_install[@]}"
    ok "Installed: ${to_install[*]}"
}

safe_link() {
    local src="$1" dst="$2"
    run mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" ]]; then
        run ln -sfn "$src" "$dst"; ok "Updated symlink: $dst"
    elif [[ -e "$dst" ]]; then
        local bak="${dst}.bak.$(date +%s)"
        run mv "$dst" "$bak"; warn "Backed up existing → $bak"
        run ln -sfn "$src" "$dst"; ok "Linked: $dst"
    else
        run ln -sfn "$src" "$dst"; ok "Linked: $dst"
    fi
}

# =============================================================================
# 0. Preflight
# =============================================================================
section "0. Preflight checks"

[[ "$EUID" -eq 0 ]] && { err "Do not run as root — use a regular user with sudo."; exit 1; }
ok "Not root (user: $USER)"

[[ -f /etc/arch-release ]] || { err "This script is for Arch Linux only."; exit 1; }
ok "Arch Linux confirmed"

ping -c 1 -W 5 archlinux.org &>/dev/null || { err "No internet. Connect and retry."; exit 1; }
ok "Internet OK"

$DRY_RUN && warn "DRY RUN — no changes will be made"
$NVIDIA  && info "NVIDIA mode — will install nvidia-open + configure Hyprland"

# =============================================================================
# 1. pacman.conf — enable multilib + parallel downloads
# =============================================================================
section "1. pacman.conf"

PACMAN_CONF="/etc/pacman.conf"
if grep -q "^\[multilib\]" "$PACMAN_CONF"; then
    skip "multilib already enabled"
else
    info "Enabling [multilib]..."
    srun sed -i '/^#\[multilib\]/{N;s/#\[multilib\]\n#Include/\[multilib\]\nInclude/}' "$PACMAN_CONF"
    ok "multilib enabled"
fi

if grep -qE "^ParallelDownloads" "$PACMAN_CONF"; then
    skip "ParallelDownloads already set"
else
    srun sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' "$PACMAN_CONF"
    ok "ParallelDownloads = 5"
fi

info "Syncing package databases..."
srun pacman -Sy --noconfirm
ok "Databases synced"

# =============================================================================
# 2. yay (AUR helper)
# =============================================================================
section "2. AUR helper (yay)"

if command -v yay &>/dev/null; then
    skip "yay already installed ($(yay --version 2>/dev/null | head -1))"
else
    info "Building yay from AUR..."
    srun pacman -S --needed --noconfirm git base-devel
    YAY_TMP="$(mktemp -d /tmp/yay-build.XXXXXX)"
    run git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    run bash -c "cd '$YAY_TMP' && makepkg -si --noconfirm"
    run rm -rf "$YAY_TMP"
    ok "yay installed"
fi

# =============================================================================
# 3. Clone frik-rice + run its install.sh
# =============================================================================
section "3. frik-rice (configs, packages, wallpapers, SDDM, Zsh, MPD)"

if [[ -d "$FRIK_RICE_DIR/.git" ]]; then
    skip "frik-rice already cloned — pulling latest..."
    run git -C "$FRIK_RICE_DIR" pull --ff-only
else
    run git clone "$FRIK_RICE_URL" "$FRIK_RICE_DIR"
    ok "frik-rice cloned"
fi

info "Running frik-rice/install.sh..."
FRIK_FLAGS=""
$DRY_RUN && FRIK_FLAGS="--dry-run"
run bash "$FRIK_RICE_DIR/install.sh" $FRIK_FLAGS
ok "frik-rice install complete"

# =============================================================================
# 4. GPU drivers
# =============================================================================
section "4. GPU drivers"

if $NVIDIA; then
    info "NVIDIA — installing nvidia-open, nvidia-utils, lib32-nvidia-utils"
    pacman_install nvidia-open nvidia-utils lib32-nvidia-utils

    MKINITCPIO="/etc/mkinitcpio.conf"
    if grep -qP "^MODULES=\(.*nvidia" "$MKINITCPIO"; then
        skip "NVIDIA modules already in mkinitcpio MODULES"
    else
        info "Adding NVIDIA modules to mkinitcpio MODULES..."
        srun sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINITCPIO"
        ok "NVIDIA modules added"
        info "Rebuilding initramfs (this takes ~30s)..."
        srun mkinitcpio -P
        ok "initramfs rebuilt"
    fi

    NVIDIA_ENV_SRC="$REPO/nvidia/nvidia-env.conf"
    NVIDIA_ENV_DST="$HOME/.config/hypr/Modules/nvidia-env.conf"
    if [[ -f "$NVIDIA_ENV_SRC" ]]; then
        safe_link "$NVIDIA_ENV_SRC" "$NVIDIA_ENV_DST"
        warn "ACTION NEEDED: add  require(\"Modules/nvidia-env\")  to ~/.config/hypr/hyprland.lua"
    fi
else
    info "Detecting GPU for mesa/vulkan drivers..."
    if ! command -v lspci &>/dev/null; then
        pacman_install pciutils
    fi
    GPU_INFO="$(lspci 2>/dev/null | grep -iE '(vga|3d|display controller)')"
    if echo "$GPU_INFO" | grep -qi "amd\|ati\|radeon"; then
        info "AMD GPU detected"
        pacman_install mesa vulkan-radeon libva-mesa-driver rocm-smi-lib
    elif echo "$GPU_INFO" | grep -qi "intel"; then
        info "Intel GPU detected"
        pacman_install mesa vulkan-intel intel-media-driver
    else
        warn "GPU not auto-detected. Install drivers manually if Hyprland fails to start."
        warn "AMD:   sudo pacman -S mesa vulkan-radeon"
        warn "NVIDIA: re-run with --nvidia flag"
    fi
fi

# =============================================================================
# 5. CPU microcode
# =============================================================================
section "5. CPU microcode"

CPU_VENDOR="$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')"
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    info "Intel CPU — installing intel-ucode"
    pacman_install intel-ucode
else
    info "AMD CPU ($CPU_VENDOR) — installing amd-ucode"
    pacman_install amd-ucode
fi

# =============================================================================
# 6. GRUB: yorha theme + /etc/default/grub
# =============================================================================
section "6. GRUB bootloader (YoRHa theme)"

GRUB_THEME_SRC="$REPO/grub/yorha"
GRUB_THEME_DST="/boot/grub/themes/yorha"

if [[ -d "$GRUB_THEME_DST" ]] && diff -rq "$GRUB_THEME_SRC" "$GRUB_THEME_DST" &>/dev/null; then
    skip "YoRHa GRUB theme already installed (unchanged)"
else
    info "Installing YoRHa GRUB theme to $GRUB_THEME_DST..."
    srun mkdir -p "$GRUB_THEME_DST"
    srun cp -r "$GRUB_THEME_SRC/." "$GRUB_THEME_DST/"
    ok "GRUB theme installed"
fi

GRUB_TEMPLATE="$REPO/grub/grub.default"
GRUB_CONF="/etc/default/grub"
if [[ -f "$GRUB_TEMPLATE" ]]; then
    EXTRA_CMDLINE=""
    $NVIDIA && EXTRA_CMDLINE="nvidia-drm.modeset=1"
    info "Writing $GRUB_CONF (NVIDIA kernel param: ${EXTRA_CMDLINE:-none})..."
    if ! $DRY_RUN; then
        sed "s|__NVIDIA_CMDLINE__|${EXTRA_CMDLINE}|g" "$GRUB_TEMPLATE" \
            | sudo tee "$GRUB_CONF" > /dev/null
    fi
    ok "GRUB config written"
    info "Regenerating GRUB config..."
    srun grub-mkconfig -o /boot/grub/grub.cfg
    ok "GRUB config regenerated"
else
    warn "grub/grub.default not found in repo — skipping"
fi

# =============================================================================
# 7. Extra dotfiles (not in frik-rice)
# =============================================================================
section "7. Extra dotfiles"

DOTFILES_HOME="$REPO/dotfiles/home"
for src in "$DOTFILES_HOME"/.[^.]*; do
    [[ -f "$src" ]] || continue
    safe_link "$src" "$HOME/$(basename "$src")"
done

DOTFILES_CFG="$REPO/dotfiles/config"
run mkdir -p "$HOME/.config"

# gh config
if [[ -f "$DOTFILES_CFG/gh/config.yml" ]]; then
    run mkdir -p "$HOME/.config/gh"
    safe_link "$DOTFILES_CFG/gh/config.yml" "$HOME/.config/gh/config.yml"
fi

# Single config files (mimeapps.list, pavucontrol.ini, QtProject.conf)
for src in "$DOTFILES_CFG"/*.list "$DOTFILES_CFG"/*.ini "$DOTFILES_CFG"/*.conf; do
    [[ -f "$src" ]] || continue
    safe_link "$src" "$HOME/.config/$(basename "$src")"
done

# =============================================================================
# 8. ~/.local/bin — appblocker + notices for binaries
# =============================================================================
section "8. ~/.local/bin"

run mkdir -p "$HOME/.local/bin"

LOCAL_BIN_SRC="$REPO/local-bin"
if [[ -f "$LOCAL_BIN_SRC/appblocker" ]]; then
    if [[ -f "$HOME/.local/bin/appblocker" ]] && \
       diff -q "$LOCAL_BIN_SRC/appblocker" "$HOME/.local/bin/appblocker" &>/dev/null; then
        skip "appblocker unchanged"
    else
        run cp "$LOCAL_BIN_SRC/appblocker" "$HOME/.local/bin/appblocker"
        run chmod +x "$HOME/.local/bin/appblocker"
        ok "appblocker installed"
    fi
fi

[[ -f "$HOME/.local/bin/clip-thumbnailer" ]] \
    && skip "clip-thumbnailer already present" \
    || warn "clip-thumbnailer missing — run restore.sh after plugging in USB"

[[ -f "$HOME/.local/bin/DigitalZen.AppImage" ]] \
    && skip "DigitalZen.AppImage already present" \
    || warn "DigitalZen.AppImage missing — run restore.sh after plugging in USB"

# =============================================================================
# 9. Systemd user services
# =============================================================================
section "9. Systemd user services"

SYSTEMD_SRC="$REPO/systemd/user"
SYSTEMD_DST="$HOME/.config/systemd/user"
run mkdir -p "$SYSTEMD_DST"

for svc in "$SYSTEMD_SRC"/*.service; do
    [[ -f "$svc" ]] || continue
    name="$(basename "$svc")"
    dst="$SYSTEMD_DST/$name"
    if [[ -f "$dst" ]] && diff -q "$svc" "$dst" &>/dev/null; then
        skip "$name (unchanged)"
    else
        run cp "$svc" "$dst"
        ok "Installed: $name"
    fi
done

if ! $DRY_RUN; then systemctl --user daemon-reload; fi

USER_SERVICES=(
    appblocker.service
    awww-daemon.service
    mpd.service
    wireplumber.service
    xdg-user-dirs.service
    pipewire.socket
    pipewire-pulse.socket
    p11-kit-server.socket
)
for svc in "${USER_SERVICES[@]}"; do
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        skip "enabled: $svc"
    else
        run systemctl --user enable "$svc"
        ok "Enabled: $svc"
    fi
done

# csp-wineserver has hardcoded paths — give 5s to abort
if systemctl --user is-enabled csp-wineserver.service &>/dev/null; then
    skip "enabled: csp-wineserver.service"
else
    warn "Enabling csp-wineserver.service (CSP Wine pre-warm)."
    warn "It uses hardcoded paths — restore.sh will fix them."
    warn "Press Ctrl+C in 5s to skip, or wait..."
    sleep 5
    run systemctl --user enable csp-wineserver.service
    ok "Enabled: csp-wineserver.service"
fi

# =============================================================================
# 10. System services
# =============================================================================
section "10. System services"

for svc in NetworkManager sddm; do
    if systemctl is-enabled "$svc" &>/dev/null; then
        skip "enabled: $svc"
    else
        srun systemctl enable "$svc"
        ok "Enabled: $svc"
    fi
done

# =============================================================================
# 11. NPM global packages
# =============================================================================
section "11. NPM global packages"

if ! command -v npm &>/dev/null; then
    warn "npm not found — skipping (nodejs is a dep of AUR packages; retry if missing)"
else
    NPM_GLOBALS=(
        "gulp@5.0.1"
        "node-gyp"
        "nopt"
        "pnpm@11.3.0"
        "semver"
        "yarn@1.22.22"
    )
    for pkg in "${NPM_GLOBALS[@]}"; do
        name="${pkg%@*}"
        if npm list -g --depth=0 2>/dev/null | grep -q " $name@"; then
            skip "npm: $name"
        else
            run npm install -g "$pkg"
            ok "npm: $pkg"
        fi
    done
fi

# =============================================================================
# 12. pipx apps
# =============================================================================
section "12. pipx apps"

if ! command -v pipx &>/dev/null; then
    warn "pipx not found — skipping"
else
    run pipx ensurepath
    if pipx list 2>/dev/null | grep -q "spotdl"; then
        skip "spotdl already in pipx"
    else
        run pipx install spotdl
        ok "spotdl installed via pipx"
    fi
fi

# =============================================================================
# 13. Music library notice
# =============================================================================
section "13. Music library"

echo ""
echo -e "  ${BOLD}Your music library (7.9 GB) lives on the USB drive.${NC}"
echo -e "  Run restore.sh after plugging in your USB to get it back:"
echo ""
echo -e "    ${YELLOW}./restore.sh /run/media/$USER/<USB>/arch-backup/${NC}"
echo ""
echo -e "  After restore: ${CYAN}mpc update${NC}  (rebuilds MPD library database)"
echo -e "  Then open rmpc with ${CYAN}SUPER+M${NC} — cava visualizer appears alongside it."
echo ""

# =============================================================================
# Done — post-install checklist
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Install complete! Required actions below.           ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}1. Restore personal data (music, apps, Wine, browser):${NC}"
echo -e "     ${YELLOW}./restore.sh /run/media/$USER/<USB>/arch-backup/${NC}"
echo ""
echo -e "  ${BOLD}2. Reboot:${NC}"
echo -e "     ${YELLOW}sudo reboot${NC}"
echo ""
echo -e "  ${BOLD}3. Re-auth GitHub CLI (after reboot, inside Hyprland):${NC}"
echo -e "     ${YELLOW}gh auth login${NC}"
echo ""
if $NVIDIA; then
    echo -e "  ${BOLD}4. NVIDIA — add env vars to Hyprland:${NC}"
    echo -e "     In ${YELLOW}~/.config/hypr/hyprland.lua${NC} add:"
    echo -e "     ${YELLOW}require(\"Modules/nvidia-env\")${NC}"
    echo ""
fi
echo -e "  ${BOLD}5. Fix monitor layout if needed:${NC}"
echo -e "     Inside Hyprland: ${YELLOW}hyprctl monitors${NC}"
echo -e "     Then edit: ${YELLOW}~/.config/hypr/Modules/Monitors.lua${NC}"
echo ""
echo -e "  ${BOLD}6. Theme picker:${NC}  ${YELLOW}SUPER+W${NC}"
echo -e "  ${BOLD}   Keybinds ref:${NC}  ${YELLOW}~/frik-rice/docs/KEYBINDS.md${NC}"
echo ""
