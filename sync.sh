#!/usr/bin/env bash
# =============================================================================
# sync.sh — Make this machine an exact mirror of Frik's source system
# =============================================================================
#
# Run this on the TARGET machine (not the source).
# It will:
#   1. Remove packages that are on this machine but NOT on the source
#      (NVIDIA packages are always kept)
#   2. Install packages from the source that are missing here
#   3. Apply all configs via frik-rice + dotfiles
#
# Usage:
#   ./sync.sh              — full sync
#   ./sync.sh --dry-run    — show what would change, make nothing
#   ./sync.sh --packages   — packages only, skip configs
#   ./sync.sh --configs    — configs only, skip packages
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

section() { echo ""; echo -e "${BOLD}${BLUE}╔══ $1 ══╗${NC}"; }
ok()      { echo -e "  ${GREEN}[✓]${NC} $1"; }
info()    { echo -e "  ${CYAN}[-]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
err()     { echo -e "  ${RED}[✗]${NC} $1" >&2; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
DO_PACKAGES=true
DO_CONFIGS=true

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --packages) DO_CONFIGS=false ;;
        --configs)  DO_PACKAGES=false ;;
    esac
done

run()  { $DRY_RUN && echo -e "  ${CYAN}[dry]${NC} $*" || "$@"; }
srun() { $DRY_RUN && echo -e "  ${CYAN}[dry]${NC} sudo $*" || sudo "$@"; }

[[ "$EUID" -eq 0 ]] && { err "Run as normal user, not root."; exit 1; }
$DRY_RUN && warn "DRY RUN — nothing will be changed"

# =============================================================================
# 1. Packages
# =============================================================================
if $DO_PACKAGES; then

    section "Package sync"

    SOURCE_PACMAN="$REPO/packages/pacman-explicit.txt"
    SOURCE_AUR="$REPO/packages/aur-explicit.txt"

    [[ -f "$SOURCE_PACMAN" ]] || { err "packages/pacman-explicit.txt not found"; exit 1; }
    [[ -f "$SOURCE_AUR"    ]] || { err "packages/aur-explicit.txt not found"; exit 1; }

    # Current explicitly installed packages on this machine
    CURRENT=$(pacman -Qqe | sort)

    # Source package list (pacman + AUR combined)
    SOURCE=$(sort "$SOURCE_PACMAN" "$SOURCE_AUR" | sort -u)

    # ── Remove packages on this machine NOT in source ─────────────────────────
    # Never remove: nvidia*, linux*, base, base-devel, sudo, grub, efibootmgr
    TO_REMOVE=$(comm -23 \
        <(echo "$CURRENT") \
        <(echo "$SOURCE") \
        | grep -vE "^(nvidia|linux|base|base-devel|sudo|grub|efibootmgr|intel-ucode|amd-ucode)" \
        || true)

    if [[ -z "$TO_REMOVE" ]]; then
        ok "No extra packages to remove"
    else
        echo ""
        warn "The following packages are on THIS machine but NOT on the source system:"
        echo "$TO_REMOVE" | while read -r pkg; do
            echo -e "    ${RED}−${NC} $pkg"
        done
        echo ""
        if ! $DRY_RUN; then
            read -rp "  Remove these packages? [y/N] " yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                # Remove one by one to skip any that are deps of kept packages
                while IFS= read -r pkg; do
                    if pacman -Qi "$pkg" &>/dev/null; then
                        sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null \
                            && ok "Removed: $pkg" \
                            || warn "Could not remove $pkg (likely needed as a dependency — skipping)"
                    fi
                done <<< "$TO_REMOVE"
            else
                info "Skipped removal"
            fi
        else
            echo "$TO_REMOVE" | while read -r pkg; do
                echo -e "  ${CYAN}[dry]${NC} would remove: $pkg"
            done
        fi
    fi

    # ── Install packages in source NOT on this machine ────────────────────────
    TO_INSTALL=$(comm -23 \
        <(echo "$SOURCE") \
        <(echo "$CURRENT") \
        || true)

    if [[ -z "$TO_INSTALL" ]]; then
        ok "No missing packages to install"
    else
        info "Installing missing packages..."
        # Split into official and AUR
        AUR_LIST=$(cat "$SOURCE_AUR")
        PACMAN_TO_INSTALL=()
        AUR_TO_INSTALL=()

        while IFS= read -r pkg; do
            if echo "$AUR_LIST" | grep -qx "$pkg"; then
                AUR_TO_INSTALL+=("$pkg")
            else
                PACMAN_TO_INSTALL+=("$pkg")
            fi
        done <<< "$TO_INSTALL"

        if [[ ${#PACMAN_TO_INSTALL[@]} -gt 0 ]]; then
            run sudo pacman -S --needed --noconfirm "${PACMAN_TO_INSTALL[@]}"
            ok "Installed pacman packages: ${PACMAN_TO_INSTALL[*]}"
        fi
        if [[ ${#AUR_TO_INSTALL[@]} -gt 0 ]]; then
            run yay -S --needed --noconfirm "${AUR_TO_INSTALL[@]}"
            ok "Installed AUR packages: ${AUR_TO_INSTALL[*]}"
        fi
    fi

fi

# =============================================================================
# 2. Configs
# =============================================================================
if $DO_CONFIGS; then

    section "Config sync"

    FRIK_RICE_DIR="$HOME/frik-rice"
    FRIK_RICE_URL="https://github.com/xXArachFrikXx/frik-rice.git"

    # Update or clone frik-rice
    if [[ -d "$FRIK_RICE_DIR/.git" ]]; then
        info "Updating frik-rice..."
        run git -C "$FRIK_RICE_DIR" pull --ff-only
    else
        run git clone "$FRIK_RICE_URL" "$FRIK_RICE_DIR"
    fi

    # Re-run frik-rice install for symlinks, wallpapers, SDDM
    run bash "$FRIK_RICE_DIR/install.sh" $( $DRY_RUN && echo "--dry-run" )

    # Extra dotfiles
    for src in "$REPO/dotfiles/home"/.[^.]*; do
        [[ -f "$src" ]] || continue
        dst="$HOME/$(basename "$src")"
        [[ -L "$dst" ]] && continue  # already a symlink
        run ln -sfn "$src" "$dst"
        ok "Linked: $dst"
    done

    for src in "$REPO/dotfiles/config"/*.list "$REPO/dotfiles/config"/*.ini "$REPO/dotfiles/config"/*.conf; do
        [[ -f "$src" ]] || continue
        dst="$HOME/.config/$(basename "$src")"
        [[ -L "$dst" ]] && continue
        run ln -sfn "$src" "$dst"
        ok "Linked: $dst"
    done

    ok "Configs synced"

fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Sync complete.                                      ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
$DRY_RUN && warn "This was a dry run — re-run without --dry-run to apply changes"
