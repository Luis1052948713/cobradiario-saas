#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
APP_ENV_VALUE="${APP_ENV:-production}"

if ! command -v flutter >/dev/null 2>&1; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter config --enable-web
flutter pub get

flutter build web --release \
  --dart-define=APP_ENV="$APP_ENV_VALUE" \
  --dart-define=APP_NAME="${APP_NAME:-Cobra Diario}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=STRIPE_PUBLISHABLE_KEY="${STRIPE_PUBLISHABLE_KEY:-}" \
  --dart-define=WEB_BASE_URL="${WEB_BASE_URL:-}" \
  --dart-define=SUPPORT_EMAIL="${SUPPORT_EMAIL:-}" \
  --dart-define=MIN_SUPPORTED_VERSION="${MIN_SUPPORTED_VERSION:-1.0.0}" \
  --dart-define=RECOMMENDED_VERSION="${RECOMMENDED_VERSION:-1.0.0}"
