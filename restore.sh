#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restore personal data from USB backup to new machine
# =============================================================================
#
# Run this on the NEW machine AFTER install.sh has finished.
# Plug in your USB drive, then run:
#
#   ./restore.sh /run/media/<user>/<USB-name>/arch-backup/
#
# What gets restored:
#   Music/               → ~/Music/
#   wine-csp/            → ~/.wine-csp/
#   local-bin/           → ~/.local/bin/
#   config/vesktop/      → ~/.config/vesktop/
#   config/zen/          → ~/.config/zen/
#   Obsidian/            → ~/Obsidian/
#   config/VSCodium-User → ~/.config/VSCodium/User/
#   config/FreeTube/     → ~/.config/FreeTube/
#   config/appblocker/   → ~/.config/appblocker/
#   config/spicetify/    → ~/.config/spicetify/
#   config/yazi/         → ~/.config/yazi/
#   config/wal/          → ~/.config/wal/
#   config/wpg/          → ~/.config/wpg/
#   config/calcurse/     → ~/.config/calcurse/
#   local-share/calcurse → ~/.local/share/calcurse/
#   Downloads/           → ~/Downloads/  (if present in backup)
#
# After restoring:
#   - mpc update                 — rebuilds MPD music database
#   - appblocker quota state     — restored from ~/.config/appblocker/
#   - csp-wineserver.service     — paths auto-fixed if username changed
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

section() { echo ""; echo -e "${BOLD}${BLUE}==> $1${NC}"; }
ok()      { echo -e "  ${GREEN}[✓]${NC} $1"; }
info()    { echo -e "  ${CYAN}[-]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
err()     { echo -e "  ${RED}[✗]${NC} $1" >&2; }

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=false
SRC=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            sed -n '2,25p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) [[ -z "$SRC" ]] && SRC="$arg" ;;
    esac
done

if [[ -z "$SRC" ]]; then
    err "No backup source specified."
    echo ""
    echo "Usage: ./restore.sh /run/media/$USER/<USB>/arch-backup/"
    exit 1
fi

if [[ ! -d "$SRC" ]]; then
    err "Backup directory not found: $SRC"
    err "Is the USB drive mounted? Try: lsblk"
    exit 1
fi

run() { $DRY_RUN && echo -e "  ${CYAN}[dry]${NC} $*" || "$@"; }

# rsync wrapper: src_rel dst
restore_path() {
    local src_rel="$1" dst="$2"
    local src="$SRC/$src_rel"

    if [[ ! -e "$src" ]]; then
        warn "Not in backup (skipping): $src_rel"
        return
    fi

    local size
    size="$(du -sh "$src" 2>/dev/null | cut -f1)"
    info "Restoring $src_rel ($size) → $dst"

    if ! $DRY_RUN; then
        mkdir -p "$dst"
        rsync -avh --progress --ignore-existing "$src/" "$dst/" 2>&1 \
            | tail -1
    fi
    ok "Restored: $dst"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight"

ok "Backup source: $SRC"
$DRY_RUN && warn "DRY RUN — no files will be written"

if [[ -f "$SRC/manifest.txt" ]]; then
    ok "manifest.txt found"
    info "Backup was created: $(grep 'Created:' "$SRC/manifest.txt" | head -1 | sed 's/Created: //')"
    info "Source host: $(grep 'Source host:' "$SRC/manifest.txt" | head -1 | sed 's/Source host: //')"
else
    warn "manifest.txt not found — proceeding anyway"
fi

# ── Restore paths ─────────────────────────────────────────────────────────────
section "Music library (~7.9 GB)"
restore_path "Music"                     "$HOME/Music"

section "Wine prefix (Clip Studio Paint, ~4.9 GB)"
restore_path "wine-csp"                  "$HOME/.wine-csp"

section "~/.local/bin"
restore_path "local-bin"                 "$HOME/.local/bin"

section "Vesktop (Discord/Vencord)"
restore_path "config/vesktop"            "$HOME/.config/vesktop"

section "Zen browser profile"
restore_path "config/zen"               "$HOME/.config/zen"

section "Obsidian vault"
restore_path "Obsidian"                  "$HOME/Obsidian"

section "VSCodium user settings"
restore_path "config/VSCodium-User"      "$HOME/.config/VSCodium/User"

section "FreeTube"
restore_path "config/FreeTube"           "$HOME/.config/FreeTube"

section "App Blocker config + quotas"
restore_path "config/appblocker"         "$HOME/.config/appblocker"

section "Spicetify"
restore_path "config/spicetify"          "$HOME/.config/spicetify"

section "yazi"
restore_path "config/yazi"              "$HOME/.config/yazi"

section "pywal colorscheme"
restore_path "config/wal"               "$HOME/.config/wal"

section "wpgtk"
restore_path "config/wpg"              "$HOME/.config/wpg"

section "calcurse"
restore_path "config/calcurse"          "$HOME/.config/calcurse"
restore_path "local-share/calcurse"     "$HOME/.local/share/calcurse"

if [[ -d "$SRC/Downloads" ]]; then
    section "Downloads"
    restore_path "Downloads"             "$HOME/Downloads"
fi

# ── Post-restore fixups ───────────────────────────────────────────────────────
section "Post-restore fixups"

# Make binaries executable
for bin in clip-thumbnailer DigitalZen.AppImage; do
    if [[ -f "$HOME/.local/bin/$bin" ]]; then
        run chmod +x "$HOME/.local/bin/$bin"
        ok "$bin → chmod +x"
    fi
done

# Fix hardcoded /home/Frik paths in csp-wineserver.service if username changed
CSP_SVC="$HOME/.config/systemd/user/csp-wineserver.service"
if [[ -f "$CSP_SVC" ]] && [[ "$USER" != "Frik" ]]; then
    warn "Username changed (Frik → $USER) — fixing csp-wineserver.service paths..."
    if ! $DRY_RUN; then
        sed -i "s|/home/Frik/|/home/$USER/|g" "$CSP_SVC"
    fi
    ok "csp-wineserver.service paths updated"
    run systemctl --user daemon-reload
fi

# Rebuild MPD music library database
if [[ -d "$HOME/Music" ]] && command -v mpc &>/dev/null; then
    info "Updating MPD library database (scanning ~/Music/)..."
    run mpc update 2>/dev/null && ok "MPD database updated" \
        || warn "MPD update failed — run 'mpc update' manually after MPD starts"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Restore complete! Everything is back.               ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  1. Reboot (if you haven't already):"
echo -e "     ${YELLOW}sudo reboot${NC}"
echo ""
echo -e "  2. Auth GitHub CLI inside Hyprland:"
echo -e "     ${YELLOW}gh auth login${NC}"
echo ""
echo -e "  3. Open music player: ${YELLOW}SUPER+M${NC}"
echo -e "     (rmpc + cava overlay — music is back, cava visualizes it)"
echo ""
echo -e "  4. Pick theme preset: ${YELLOW}SUPER+W${NC}"
echo ""
echo -e "  5. Keybinds reference: ${YELLOW}~/frik-rice/docs/KEYBINDS.md${NC}"
echo ""
