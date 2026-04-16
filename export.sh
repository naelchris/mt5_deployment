#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# export.sh — Save MT5 state back to GitHub, then optionally terminate the VM
# Run when done working:  bash export.sh
# ─────────────────────────────────────────────────────────────────────────────
set -eo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
ok()  { echo -e "${GREEN}✓ $*${RESET}"; }
err() { echo -e "${RED}✗ $*${RESET}"; exit 1; }
log() { echo "▶ $*"; }

REPO_DIR="/tmp/algoTrading"
MT5_DATA="${HOME}/.wine/drive_c/Program Files/MetaTrader 5"

# ── 1. Verify repo is present ─────────────────────────────────────────────────
[ -d "$REPO_DIR/.git" ] || err "Repo not found at $REPO_DIR — run start.sh first"

# ── 2. Pull latest to avoid conflicts ─────────────────────────────────────────
log "Pulling latest from GitHub..."
git -C "$REPO_DIR" pull --ff-only
ok "Up to date"

# ── 3. Sync MT5 data → repo ───────────────────────────────────────────────────
log "Syncing MT5 files to repo..."

for dir in Experts Indicators Scripts; do
    src="$MT5_DATA/MQL5/$dir"
    dst="$REPO_DIR/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -a --delete "$src/" "$dst/"
    fi
done

if [ -d "$MT5_DATA/Profiles" ]; then
    mkdir -p "$REPO_DIR/Profiles"
    rsync -a --delete "$MT5_DATA/Profiles/" "$REPO_DIR/Profiles/"
fi

ok "Sync complete"

# ── 4. Commit and push ────────────────────────────────────────────────────────
cd "$REPO_DIR"

if git diff --quiet && git diff --cached --quiet; then
    ok "Nothing changed — no commit needed"
else
    TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')
    log "Committing changes..."
    git add Experts Indicators Scripts Profiles 2>/dev/null || true
    git commit -m "chore: export MT5 state — ${TIMESTAMP}"
    git push
    ok "Changes pushed to GitHub"
fi

# ── 5. Kill MT5 + VNC + ngrok ─────────────────────────────────────────────────
log "Shutting down MT5, VNC, ngrok..."
pkill -f "terminal64.exe" 2>/dev/null || true
pkill x11vnc               2>/dev/null || true
pkill ngrok                2>/dev/null || true
pkill Xvfb                 2>/dev/null || true
ok "All processes terminated"

echo ""
echo "  State saved to GitHub. Safe to close / terminate the VM."
echo ""
