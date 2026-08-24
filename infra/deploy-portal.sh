#!/usr/bin/env bash
# Builds the portal for the web and copies it onto the box.
#
# The portal is static output with no server side, so it is served by a stock nginx over a mounted
# directory rather than baked into an image of its own. That means deploying it is a file copy, and
# this script is the whole of it — there is no registry round trip and nothing to rebuild in CI when
# only the copy on a screen changes.
#
# Run from a machine with Flutter, not from the box.
set -euo pipefail

HOST="${1:-delivery-vps}"
PUBLIC_HOST="${PUBLIC_HOST:-94.72.112.156}"

APP="$(cd "$(dirname "$0")/../clients/apps/delivery_portal" && pwd)"
REMOTE=/opt/delivery/infra/portal/web

echo "Building the portal against $PUBLIC_HOST..."
cd "$APP"

# The three of these have to agree with what Keycloak is told, or sign-in fails at the redirect
# rather than at the password — which looks like a broken login and is an addressing mistake.
#
# OIDC_REDIRECT_URL is set explicitly instead of being derived from window.location, because
# Keycloak matches redirect URIs exactly and a trailing slash is part of the match.
flutter build web --release \
  --dart-define=KEYCLOAK_ISSUER="http://${PUBLIC_HOST}:8180/realms/delivery-platform" \
  --dart-define=API_BASE_URL="http://${PUBLIC_HOST}:8100" \
  --dart-define=OIDC_REDIRECT_URL="http://${PUBLIC_HOST}:8200/"

echo "Copying to $HOST:$REMOTE..."
ssh "$HOST" "mkdir -p $REMOTE"

# --delete so a file removed from the build does not linger on the box and get served alongside
# the new ones. rsync where it exists, scp of a fresh directory where it does not.
if command -v rsync >/dev/null 2>&1; then
  rsync -az --delete "$APP/build/web/" "$HOST:$REMOTE/"
else
  ssh "$HOST" "rm -rf $REMOTE && mkdir -p $REMOTE"
  scp -q -r "$APP/build/web/." "$HOST:$REMOTE/"
fi

# nginx serves from the mount, so new files are live immediately. The reload is for the config,
# and costs nothing when it has not changed.
ssh "$HOST" "cd /opt/delivery/infra && docker compose -f docker-compose.dev.yml up -d portal >/dev/null 2>&1 && docker exec delivery-portal nginx -s reload >/dev/null 2>&1 || true"

echo "Portal deployed: http://${PUBLIC_HOST}:8200/"
