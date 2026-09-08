#!/usr/bin/env bash
# Pushes the public site (clients/website) onto the k3s node and refreshes its nginx config.
#
# The site is static, so deploying it is a file copy — there is no build step and nothing in CI to
# rebuild when a line of copy changes. The manifest that serves it is deploy/k3s/cluster/website.yaml.
#
#   infra/deploy-website.sh [ssh-host] [path-to-apk]
#
# The optional second argument drops an Android build at app/youdrop.apk, which is the single
# address the QR code on the landing page encodes and every "Download" button points at. Without
# it that address answers 404 by design rather than silently serving the landing page back.
set -euo pipefail

HOST="${1:-root@94.72.112.156}"
APK="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/clients/website"
REMOTE=/opt/delivery/sites/www

[ -f "$SITE/index.html" ] || { echo "No site at $SITE"; exit 1; }

# The nginx config comes from the repository, not from a copy pasted into the manifest, so the
# routing on the box cannot drift from the routing under review.
echo "Loading nginx config into the cluster..."
kubectl --kubeconfig <(ssh "$HOST" 'cat /etc/rancher/k3s/k3s.yaml' | sed "s/127.0.0.1/${HOST##*@}/") \
  -n youdrop-site create configmap website-nginx \
  --from-file=nginx.conf="$SITE/nginx.conf" \
  --dry-run=client -o yaml 2>/dev/null | \
  ssh "$HOST" 'kubectl apply -f -' || {
    # Falling back to doing it entirely on the box keeps this working from a laptop with no
    # kubeconfig, which is the common case.
    tar -C "$SITE" -czf - nginx.conf | ssh "$HOST" \
      'mkdir -p /tmp/site-conf && tar -C /tmp/site-conf -xzf - && kubectl -n youdrop-site create configmap website-nginx --from-file=nginx.conf=/tmp/site-conf/nginx.conf --dry-run=client -o yaml | kubectl apply -f -'
  }

# Contents are replaced, never the directory. nginx bind-mounts it and a mount follows the inode,
# so removing and recreating the directory leaves the running container serving a deleted one — the
# site 403s while the files sit on disk looking perfectly deployed. tar over ssh also avoids the
# Windows scp `dir/.` idiom, which fails after the copy with a zero exit further up the pipe.
echo "Copying the site to $HOST:$REMOTE..."
tar -C "$SITE" --exclude=nginx.conf -czf - . | ssh "$HOST" \
  "mkdir -p $REMOTE && find $REMOTE -mindepth 1 -maxdepth 1 ! -name app -exec rm -rf {} + && tar -C $REMOTE -xzf -"

if [ -n "$APK" ]; then
  [ -f "$APK" ] || { echo "No APK at $APK"; exit 1; }
  echo "Publishing $(basename "$APK") at /app ($(du -h "$APK" | cut -f1))..."
  ssh "$HOST" "mkdir -p $REMOTE/app"
  # Straight to its final name: nginx serves this exact path and a partial file would be handed
  # out as a truncated install.
  scp -q "$APK" "$HOST:$REMOTE/app/youdrop.apk.part"
  ssh "$HOST" "mv $REMOTE/app/youdrop.apk.part $REMOTE/app/youdrop.apk"
fi

# The files are a mount, so they are live immediately; the restart is only for the config.
ssh "$HOST" 'kubectl -n youdrop-site rollout restart deploy/website >/dev/null 2>&1 || true'
echo "Site deployed: https://www.youdrop.shop/"
