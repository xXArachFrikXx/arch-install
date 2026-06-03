#!/usr/bin/env bash
# =============================================================================
# backup.sh — Back up everything not in git to a USB drive
# =============================================================================
#
# Run this on the OLD machine BEFORE you leave.
# It copies your music, Wine prefix, browser profiles, app data, and all
# personal files to a USB drive (or any target directory you choose).
#
# Usage:
#   ./backup.sh /run/media/Frik/<USB-name>/arch-backup/
#   ./backup.sh --dry-run /run/media/Frik/<USB-name>/arch-backup/
#
# What gets backed up (~14 GB without Steam):
#   ~/Music/                       7.9 GB  — your full music library
#   ~/.wine-csp/                   4.9 GB  — Clip Studio Paint Wine prefix
#   ~/.local/bin/                  152 MB  — clip-thumbnailer, DigitalZen.AppImage
#   ~/.config/vesktop/             ~200 MB — Discord/Vencord (cache excluded)
#   ~/.config/zen/                 ~100 MB — Zen browser profile (cache excluded)
#   ~/Obsidian/                    29 MB   — your notes vault
#   ~/.config/VSCodium/User/       1.8 MB  — settings, keybindings, snippets
#   ~/.config/FreeTube/            2.4 MB  — YouTube subscriptions/library
#   ~/.config/appblocker/          small   — quota config + app list
#   ~/.config/spicetify/           small   — Spotify theme config
#   ~/.config/yazi/                small   — file manager config
#   ~/.config/wal/                 small   — last colorscheme
#   ~/.config/wpg/                 small   — color generation data
#   ~/.config/calcurse/            small   — calendar config
#   ~/.local/share/calcurse/       small   — calendar entries/todos
#   ~/Downloads/                   797 MB  — optional (prompted)
#
# Steam games (84 GB) are NOT backed up — re-download on new PC.
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
DEST=""
SKIP_DOWNLOADS=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)        DRY_RUN=true ;;
        --skip-downloads) SKIP_DOWNLOADS=true ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            [[ -z "$DEST" ]] && DEST="$arg"
            ;;
    esac
done

if [[ -z "$DEST" ]]; then
    err "No destination specified."
    echo ""
    echo "Usage: ./backup.sh /run/media/$USER/<USB>/arch-backup/"
    echo "       ./backup.sh --dry-run /run/media/$USER/<USB>/arch-backup/"
    exit 1
fi

run() { $DRY_RUN && echo -e "  ${CYAN}[dry]${NC} $*" || "$@"; }

# rsync wrapper: src dst [extra rsync flags...]
backup_path() {
    local src="$1" dst_rel="$2"
    shift 2
    local dst="$DEST/$dst_rel"

    if [[ ! -e "$src" ]]; then
        warn "Skipping (not found): $src"
        return
    fi

    local size
    size="$(du -sh "$src" 2>/dev/null | cut -f1)"
    info "Backing up $src ($size) → $dst_rel/"

    if ! $DRY_RUN; then
        mkdir -p "$dst"
        rsync -avh --progress --ignore-existing "$@" "$src" "$dst/" 2>&1 \
            | tail -1
    fi
    ok "Done: $src"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight"

if ! $DRY_RUN; then
    # Check destination is writable
    mkdir -p "$DEST" 2>/dev/null || { err "Cannot create destination: $DEST"; exit 1; }

    # Check free space (rough estimate: 15 GB needed)
    AVAIL_KB="$(df -k "$DEST" | awk 'NR==2{print $4}')"
    NEEDED_KB=$((15 * 1024 * 1024))  # 15 GB in KB
    if [[ "$AVAIL_KB" -lt "$NEEDED_KB" ]]; then
        warn "Destination may not have enough space."
        warn "Available: $(( AVAIL_KB / 1024 / 1024 )) GB — recommended: 15+ GB"
        read -rp "  Continue anyway? [y/N] " yn
        [[ "$yn" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    else
        ok "Free space OK ($(( AVAIL_KB / 1024 / 1024 )) GB available)"
    fi
fi

ok "Destination: $DEST"
$DRY_RUN && warn "DRY RUN — no files will be copied"
echo ""

# ── Ask about Downloads ───────────────────────────────────────────────────────
if ! $SKIP_DOWNLOADS && ! $DRY_RUN; then
    DOWNLOADS_SIZE="$(du -sh "$HOME/Downloads" 2>/dev/null | cut -f1)"
    read -rp "  Include ~/Downloads/ ($DOWNLOADS_SIZE)? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || SKIP_DOWNLOADS=true
fi

# ── Backup each path ──────────────────────────────────────────────────────────
section "Music library"
backup_path "$HOME/Music"                      "Music"

section "Wine prefix (Clip Studio Paint)"
backup_path "$HOME/.wine-csp"                  "wine-csp"

section "~/.local/bin (clip-thumbnailer, DigitalZen.AppImage, etc.)"
backup_path "$HOME/.local/bin"                 "local-bin"

section "Vesktop (Discord/Vencord)"
backup_path "$HOME/.config/vesktop"            "config/vesktop" \
    --exclude="Cache/" \
    --exclude="GPUCache/" \
    --exclude="Code Cache/" \
    --exclude="DawnGraphiteCache/" \
    --exclude="DawnWebGPUCache/"

section "Zen browser profile"
backup_path "$HOME/.config/zen"                "config/zen" \
    --exclude="Cache/" \
    --exclude="GPUCache/" \
    --exclude="Code Cache/" \
    --exclude="DawnGraphiteCache/" \
    --exclude="DawnWebGPUCache/" \
    --exclude="Crashpad/"

section "Obsidian vault"
backup_path "$HOME/Obsidian"                   "Obsidian"

section "VSCodium user settings"
backup_path "$HOME/.config/VSCodium/User"      "config/VSCodium-User"

section "FreeTube (YouTube frontend)"
backup_path "$HOME/.config/FreeTube"           "config/FreeTube"

section "App Blocker config"
backup_path "$HOME/.config/appblocker"         "config/appblocker"

section "Spicetify (Spotify theme)"
backup_path "$HOME/.config/spicetify"          "config/spicetify"

section "yazi (file manager config)"
backup_path "$HOME/.config/yazi"               "config/yazi"

section "pywal colorscheme"
backup_path "$HOME/.config/wal"                "config/wal"

section "wpgtk color generation"
backup_path "$HOME/.config/wpg"                "config/wpg"

section "calcurse (calendar)"
backup_path "$HOME/.config/calcurse"           "config/calcurse"
backup_path "$HOME/.local/share/calcurse"      "local-share/calcurse"

if ! $SKIP_DOWNLOADS; then
    section "Downloads"
    backup_path "$HOME/Downloads"              "Downloads"
fi

# ── Write manifest ────────────────────────────────────────────────────────────
section "Manifest"

if ! $DRY_RUN; then
    MANIFEST="$DEST/manifest.txt"
    {
        echo "arch-backup manifest"
        echo "Created: $(date)"
        echo "Source host: $(hostname)"
        echo "Source user: $USER"
        echo ""
        echo "Contents:"
        find "$DEST" -maxdepth 2 -mindepth 1 -type d | sort | while read -r d; do
            rel="${d#$DEST/}"
            size="$(du -sh "$d" 2>/dev/null | cut -f1)"
            printf "  %-40s %s\n" "$rel" "$size"
        done
        echo ""
        TOTAL="$(du -sh "$DEST" 2>/dev/null | cut -f1)"
        echo "Total: $TOTAL"
    } > "$MANIFEST"
    ok "Manifest written: $MANIFEST"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  Backup complete! Safe to unplug USB.                ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Backup destination: ${CYAN}$DEST${NC}"
$DRY_RUN || echo -e "  Total size:         ${CYAN}$(du -sh "$DEST" 2>/dev/null | cut -f1)${NC}"
echo ""
echo -e "  On the new machine, run:"
echo -e "    ${YELLOW}./install.sh --nvidia${NC}"
echo -e "    ${YELLOW}./restore.sh $DEST${NC}"
echo ""
