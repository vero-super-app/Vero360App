#!/usr/bin/env bash
# Codemagic / CI: create a local .env from environment variables before flutter build.
# Add as a pre-build script. Set these in Codemagic → Environment variables (secure).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GOOGLE_MAPS_API_KEY:=}"

if [[ -z "${GOOGLE_MAPS_API_KEY}" && -f .env.example ]]; then
  echo "GOOGLE_MAPS_API_KEY not set — copying .env.example → .env"
  cp .env.example .env
else
  cat > .env <<EOF
GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY}
EOF
  echo "Wrote .env from Codemagic environment variables"
fi
