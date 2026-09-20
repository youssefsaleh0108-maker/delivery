#!/bin/sh
# Regenerates both environments' ingress from the one template, so dev and qa cannot drift.
# Run from deploy/k3s: sh scripts/render-overlays.sh
#
# With an argument it renders into <dir>/<env>/ingress.yaml instead of overlays/<env>/ingress.yaml.
# scripts/verify.sh uses that to render into a temporary directory and diff, so the transform below
# lives in exactly one place: a rule added here can never be forgotten in the drift check.
#
# `# __DEV_ONLY__` marks a line that exists in dev and not in qa — the loopback CORS origins a
# developer's browser needs and a shared qa host must not carry. dev keeps the line and loses the
# marker; qa loses the line.
set -eu
cd "$(dirname "$0")/.."

OUT="${1:-overlays}"

for ENV in dev qa; do
  case "$ENV" in
    dev) DEV_ONLY='s/[[:space:]]*#[[:space:]]*__DEV_ONLY__[[:space:]]*$//' ;;
    *)   DEV_ONLY='/__DEV_ONLY__/d' ;;
  esac
  mkdir -p "$OUT/$ENV"
  sed -e "s/__API_HOST__/api-$ENV.youdrop.shop/g" \
      -e "s/__IAM_HOST__/iam-$ENV.youdrop.shop/g" \
      -e "s/__PORTAL_HOST__/portal-$ENV.youdrop.shop/g" \
      -e "s/__MON_HOST__/monitoring-$ENV.youdrop.shop/g" \
      -e "$DEV_ONLY" \
      overlays/ingress.template.yaml > "$OUT/$ENV/ingress.yaml"
  echo "rendered $OUT/$ENV/ingress.yaml"
done
