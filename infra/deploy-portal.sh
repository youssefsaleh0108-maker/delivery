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
# Which environment's portal this is. There are two directories on the box now and one Deployment
# per namespace, so the environment cannot be implicit: writing dev's build into qa's directory
# would be silent and wrong. Defaults to dev because that is the one deployed constantly.
ENV="${2:-${ENV:-dev}}"
case "$ENV" in
  dev|qa) ;;
  *) echo "Unknown environment '$ENV' (expected dev or qa)" >&2; exit 1 ;;
esac
# The public hostnames, since the TLS cutover. The old IP:port form still works for a curl on the
# box, but a build addressed that way breaks twice on a real client: Android denies cleartext to a
# public address, and Keycloak's issuer check refuses a token minted under a different hostname.
PORTAL_HOST="${PORTAL_HOST:-portal-$ENV.youdrop.shop}"
API_HOST="${API_HOST:-api-$ENV.youdrop.shop}"
IAM_HOST="${IAM_HOST:-iam-$ENV.youdrop.shop}"

APP="$(cd "$(dirname "$0")/../clients/apps/delivery_portal" && pwd)"
# Where the portal Deployment's hostPath volume actually points, per environment — see
# deploy/k3s/overlays/<env>/kustomization.yaml, which patches it.
#
# This said /opt/delivery/infra/portal/web until 2026-09-22, left behind when the box moved from
# docker compose to k3s. That directory does not exist, so `find ... -delete` created nothing to
# delete, tar wrote a fresh tree nothing serves, and the script printed "Portal deployed" — the
# exact shape of failure the comments below were written to prevent, in the step they do not cover.
REMOTE="/opt/delivery/sites/$ENV/portal"

echo "Building the portal against $API_HOST / $IAM_HOST..."
cd "$APP"

# The three of these have to agree with what Keycloak is told, or sign-in fails at the redirect
# rather than at the password — which looks like a broken login and is an addressing mistake.
#
# OIDC_REDIRECT_URL is set explicitly instead of being derived from window.location, because
# Keycloak matches redirect URIs exactly and a trailing slash is part of the match.
#
# --no-web-resources-cdn keeps CanvasKit on our own origin. web/flutter_bootstrap.js already
# points the loader at the local copy, and this makes the build itself stop offering the gstatic
# one — belt and braces, because the portal's CSP says script-src 'self' and the page renders
# NOTHING at all if the renderer is fetched from an origin the policy does not allow. Rubik is
# bundled as an asset (delivery_design_system/pubspec.yaml), so no font comes from a CDN either.
flutter build web --release \
  --no-web-resources-cdn \
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
[ -f "$APP/build/web/index.html" ] || { echo "The build produced no index.html; refusing to deploy nothing." >&2; exit 1; }
ssh "$HOST" "test -d $REMOTE" || { echo "No portal directory at $HOST:$REMOTE — check which environment's Deployment mounts what before creating it." >&2; exit 1; }
tar -C "$APP/build/web" -czf - . | ssh "$HOST" "find $REMOTE -mindepth 1 -delete && tar -C $REMOTE -xzf -"

# Proof rather than a hopeful message: ask the box for the file we just sent. A deploy that copied
# into the wrong directory used to end with "Portal deployed" all the same.
LOCAL_SUM=$(sha256sum "$APP/build/web/index.html" | cut -d' ' -f1)
REMOTE_SUM=$(ssh "$HOST" "sha256sum $REMOTE/index.html | cut -d' ' -f1")
[ "$LOCAL_SUM" = "$REMOTE_SUM" ] || { echo "index.html on the box does not match the one just built." >&2; exit 1; }

# No restart: nginx serves the hostPath mount, so the new files are already being served. Its
# config comes from a ConfigMap and is not touched here.
echo "Portal deployed to $ENV ($REMOTE, index.html verified): https://${PORTAL_HOST}/"
