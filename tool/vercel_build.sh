#!/usr/bin/env bash
set -euo pipefail

# Baut die Flutter-Web-App für Vercel.
# Vercel hat Flutter nicht vorinstalliert, deshalb wird es hier geholt.
# Zusätzlich: Build-ID für PWA-Cache-Versionierung + Update-Hinweis.

FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Flutter wird heruntergeladen..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics
flutter pub get

# Kurze, stabile Build-ID (Commit oder Zeitstempel).
RAW_ID="${VERCEL_GIT_COMMIT_SHA:-${GITHUB_SHA:-}}"
if [ -z "$RAW_ID" ]; then
  RAW_ID="$(date -u +%Y%m%d%H%M%S)"
fi
APP_BUILD_ID="$(printf '%s' "$RAW_ID" | cut -c1-12)"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "PWA Build-ID: $APP_BUILD_ID"

flutter build web --release --base-href "/" \
  --dart-define="APP_BUILD_ID=$APP_BUILD_ID"

# version.json — wird von der App mit Cache-Busting geladen.
cat > build/web/version.json <<EOF
{
  "buildId": "$APP_BUILD_ID",
  "builtAt": "$BUILT_AT"
}
EOF

# Eigenen Service Worker mit Build-ID einsetzen (ersetzt Flutter-Default).
if [ -f web/flutter_service_worker_template.js ]; then
  sed "s/__APP_BUILD_ID__/${APP_BUILD_ID}/g" \
    web/flutter_service_worker_template.js \
    > build/web/flutter_service_worker.js
fi

# pwa_boot.js kommt aus web/ — sicherheitshalber nochmal kopieren.
cp -f web/pwa_boot.js build/web/pwa_boot.js

echo "PWA-Assets geschrieben: version.json + flutter_service_worker.js"
