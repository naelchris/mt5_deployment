#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — Google Colab bootstrap for MetaTrader 5 (Wine + VNC, no Docker)
# Paste into Colab terminal and run:  bash start.sh
# ─────────────────────────────────────────────────────────────────────────────
set -eo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
ok()  { echo -e "${GREEN}✓ $*${RESET}"; }
err() { echo -e "${RED}✗ $*${RESET}"; exit 1; }
log() { echo "▶ $*"; }

VNC_PORT="${VNC_PORT:-5900}"
VNC_PASS="${VNC_PASS:-mt5vnc}"
DISP="${DISP:-:99}"
NGROK_TOKEN="1eqDDFA2XmhchLGZovN83Z27YrD_4YyD4xK98Jec8uj6Ag5o8"
MT5_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
MT5_SETUP="/tmp/mt5setup.exe"
REPO_DIR="/tmp/algoTrading"
MT5_DATA="${HOME}/.wine/drive_c/Program Files/MetaTrader 5"

# ── 1. System dependencies ────────────────────────────────────────────────────
log "Installing Wine, Xvfb, x11vnc..."
dpkg --add-architecture i386
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    wine wine32 wine64 libwine \
    xvfb x11vnc \
    wget curl python3-pip
ok "Dependencies ready"

# ── 2. Virtual display ────────────────────────────────────────────────────────
log "Starting virtual display ${DISP}..."
pkill Xvfb 2>/dev/null || true
Xvfb "$DISP" -screen 0 1280x800x24 -ac &
export DISPLAY="$DISP"
sleep 2
ok "Virtual display ${DISP} ready"

# ── 3. Init Wine prefix (64-bit) ─────────────────────────────────────────────
# Wipe prefix if it's 32-bit (MT5 requires 64-bit)
if [ -f ~/.wine/system.reg ] && ! grep -q '#arch=win64' ~/.wine/system.reg 2>/dev/null; then
    log "Detected 32-bit Wine prefix — recreating as 64-bit..."
    rm -rf ~/.wine
fi
if [ ! -f ~/.wine/system.reg ]; then
    log "Initialising Wine prefix (64-bit)..."
    WINEARCH=win64 WINEPREFIX=~/.wine WINEDEBUG=-all DISPLAY="$DISP" wineboot --init 2>/dev/null || true
    ok "Wine prefix ready (win64)"
else
    ok "Wine prefix already initialised (win64)"
fi

# ── 4. Download MT5 installer ─────────────────────────────────────────────────
if [ ! -f "$MT5_SETUP" ]; then
    log "Downloading MT5 installer..."
    wget -q --show-progress -O "$MT5_SETUP" "$MT5_URL"
    ok "MT5 installer downloaded"
else
    ok "MT5 installer already present ($(du -sh $MT5_SETUP | cut -f1))"
fi

# ── 5. Install + launch MT5 via Wine ─────────────────────────────────────────
MT5_EXE=~/.wine/drive_c/Program\ Files/MetaTrader\ 5/terminal64.exe
if [ ! -f "$MT5_EXE" ]; then
    log "Installing MT5 via Wine (silent, ~60 s)..."
    WINEARCH=win64 WINEPREFIX=~/.wine WINEDEBUG=-all DISPLAY="$DISP" wine "$MT5_SETUP" /auto &
    WINE_PID=$!
    for _i in $(seq 1 18); do
        sleep 5
        [ -f "$MT5_EXE" ] && break
        kill -0 $WINE_PID 2>/dev/null || break
    done
    ok "MT5 installed"
else
    ok "MT5 already installed — launching..."
fi
# Launch terminal (installer auto-starts it, but launch explicitly on re-runs)
WINEARCH=win64 WINEPREFIX=~/.wine WINEDEBUG=-all DISPLAY="$DISP" wine "$MT5_EXE" &
sleep 5
ok "MT5 launched"

# ── 6. VNC server ─────────────────────────────────────────────────────────────
log "Starting x11vnc on port ${VNC_PORT}..."
pkill x11vnc 2>/dev/null || true
x11vnc \
    -display "$DISP" \
    -rfbport "$VNC_PORT" \
    -passwd  "$VNC_PASS" \
    -forever -shared -noxdamage \
    -bg -o /tmp/x11vnc.log
ok "VNC running on port ${VNC_PORT}  (password: ${VNC_PASS})"

# ── 7. Ngrok tunnel ───────────────────────────────────────────────────────────
if [ -n "$NGROK_TOKEN" ]; then
    log "Installing ngrok CLI..."
    if ! command -v ngrok &>/dev/null; then
        curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
            -o /etc/apt/trusted.gpg.d/ngrok.asc
        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
            > /etc/apt/sources.list.d/ngrok.list
        apt-get update -qq && apt-get install -y -qq ngrok
    fi
    ngrok config add-authtoken "$NGROK_TOKEN"

    log "Starting ngrok tunnel (persistent background daemon)..."
    pkill ngrok 2>/dev/null || true
    nohup ngrok tcp "$VNC_PORT" > /tmp/ngrok.log 2>&1 &
    sleep 4

    VNC_ADDR=$(curl -s localhost:4040/api/tunnels \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'].replace('tcp://',''))")
    echo ""
    echo "  VNC address : ${VNC_ADDR}"
    echo "  VNC password: ${VNC_PASS}"
    echo ""
else
    echo ""
    echo "  VNC port $VNC_PORT is open locally."
    echo "  Set NGROK_TOKEN=<your-token> to expose publicly."
fi

# ── 8. Restore MT5 state from GitHub ─────────────────────────────────────────
log "Restoring MT5 state from GitHub..."
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only
else
    git clone --depth 1 https://github.com/naelchris/algoTrading.git "$REPO_DIR"
fi

# Sync data directories into MT5 install dir
for dir in Experts Indicators Scripts; do
    src="$REPO_DIR/$dir"
    dst="$MT5_DATA/MQL5/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -a --delete "$src/" "$dst/"
    fi
done

# Profiles sits one level up from MQL5
if [ -d "$REPO_DIR/Profiles" ]; then
    mkdir -p "$MT5_DATA/Profiles"
    rsync -a --delete "$REPO_DIR/Profiles/" "$MT5_DATA/Profiles/"
fi

ok "MT5 state restored from GitHub"

ok "Done! Connect any VNC client to the address above."
