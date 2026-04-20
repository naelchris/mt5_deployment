#!/bin/bash
# Seed /config from the pre-installed base baked into the image.
# Check for terminal64.exe specifically — a partial .wine dir (from a failed
# previous run) should still trigger a re-seed.
MT5_EXE="/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

if [ ! -f "$MT5_EXE" ] && [ -d "/config-base/.wine" ]; then
  echo "[entrypoint] MT5 not found in /config — seeding from pre-installed base..."
  cp -a /config-base/. /config/
  # Docker COPY resets ownership to root; restore to user 911 (abc) so Wine
  # and MT5 can write to their own files.
  chown -R 911:911 /config
  echo "[entrypoint] Seed complete ($(du -sh /config | cut -f1))"
fi

exec /init "$@"
