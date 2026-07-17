#!/usr/bin/env bash
set -euo pipefail

# Baut die Flutter-Web-App für Vercel.
# Vercel hat Flutter nicht vorinstalliert, deshalb wird es hier geholt.

FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Flutter wird heruntergeladen..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics
flutter pub get

# Optionale Fallback-Keys aus Vercel-Environment (wie .env.example).
DEFINES=()
if [ -n "${GROQ_API_KEY:-}" ]; then
  DEFINES+=(--dart-define=GROQ_API_KEY="$GROQ_API_KEY")
fi
if [ -n "${MISTRAL_API_KEY:-}" ]; then
  DEFINES+=(--dart-define=MISTRAL_API_KEY="$MISTRAL_API_KEY")
fi
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  DEFINES+=(--dart-define=OPENROUTER_API_KEY="$OPENROUTER_API_KEY")
fi

flutter build web --release --base-href "/" "${DEFINES[@]}"