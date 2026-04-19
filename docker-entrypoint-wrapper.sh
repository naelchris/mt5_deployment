#!/bin/bash
# Seed /config from the pre-installed base baked into the image.
# Only runs on the very first start when the bind-mount is empty.
if [ ! -d "/config/.wine" ] && [ -d "/config-base/.wine" ]; then
  echo "[entrypoint] First run — seeding Wine+MT5 from pre-installed image layer..."
  cp -a /config-base/. /config/
  echo "[entrypoint] Seed complete ($(du -sh /config | cut -f1))"
fi

exec /init "$@"
