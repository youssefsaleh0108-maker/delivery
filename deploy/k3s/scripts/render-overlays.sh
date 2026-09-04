#!/bin/sh
# Regenerates both environments' ingress from the one template, so dev and qa cannot drift.
# Run from deploy/k3s: sh scripts/render-overlays.sh
set -eu
cd "$(dirname "$0")/.."

for ENV in dev qa; do
  sed -e "s/__API_HOST__/api-$ENV.youdrop.shop/g" \
      -e "s/__IAM_HOST__/iam-$ENV.youdrop.shop/g" \
      -e "s/__PORTAL_HOST__/portal-$ENV.youdrop.shop/g" \
      -e "s/__MON_HOST__/monitoring-$ENV.youdrop.shop/g" \
      overlays/ingress.template.yaml > "overlays/$ENV/ingress.yaml"
  echo "rendered overlays/$ENV/ingress.yaml"
done
