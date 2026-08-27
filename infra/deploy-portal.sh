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
# The public hostnames, since the TLS cutover. The old IP:port form still works for a curl on the
# box, but a build addressed that way breaks twice on a real client: Android denies cleartext to a
# public address, and Keycloak's issuer check refuses a token minted under a different hostname.
PORTAL_HOST="${PORTAL_HOST:-portal-dev.youdrop.shop}"
API_HOST="${API_HOST:-api-dev.youdrop.shop}"
IAM_HOST="${IAM_HOST:-iam-dev.youdrop.shop}"

APP="$(cd "$(dirname "$0")/../clients/apps/delivery_portal" && pwd)"
REMOTE=/opt/delivery/infra/portal/web

echo "Building the portal against $API_HOST / $IAM_HOST..."
cd "$APP"

# The three of these have to agree with what Keycloak is told, or sign-in fails at the redirect
# rather than at the password — which looks like a broken login and is an addressing mistake.
#
# OIDC_REDIRECT_URL is set explicitly instead of being derived from window.location, because
# Keycloak matches redirect URIs exactly and a trailing slash is part of the match.
flutter build web --release \
  --dart-define=KEYCLOAK_ISSUER="https://${IAM_HOST}/realms/delivery-platform" \
  --dart-define=API_BASE_URL="https://${API_HOST}" \
  --dart-define=OIDC_REDIRECT_URL="https://${PORTAL_HOST}/"

echo "Copying to $HOST:$REMOTE..."
ssh "$HOST" "mkdir -p $REMOTE"

# A tarball, always — and the contents are replaced, never the directory.
#
# Two hard-won constraints meet here. The directory itself must survive: nginx bind-mounts it, and
# a mount follows the inode, so `rm -rf $REMOTE && mkdir` leaves the running container serving a
# deleted directory — the site 403s while the files sit on disk looking perfectly deployed (this
# happened). And Windows scp refuses the `dir/.` idiom the old fallback used, failing after the
# build with exit 0 further up the pipe, so the failure read as success. tar over ssh has neither
# problem and needs no rsync on the box.
tar -C "$APP/build/web" -czf - . | ssh "$HOST" "mkdir -p $REMOTE && find $REMOTE -mindepth 1 -delete && tar -C $REMOTE -xzf -"

# nginx serves from the mount, so new files are live immediately. The reload is for the config,
# and costs nothing when it has not changed.
ssh "$HOST" "cd /opt/delivery/infra && docker compose -f docker-compose.dev.yml up -d portal >/dev/null 2>&1 && docker exec delivery-portal nginx -s reload >/dev/null 2>&1 || true"

echo "Portal deployed: https://${PORTAL_HOST}/"
