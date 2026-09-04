#!/bin/sh
# Installs the monitoring stack. Idempotent. Run on the box from /opt/delivery/k3s.
set -eu
cd "$(dirname "$0")/.."

kubectl apply -f cluster/monitoring.yaml >/dev/null 2>&1 || kubectl apply -f cluster/monitoring.yaml

if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  PW=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=username=admin --from-literal=password="$PW"
  echo "grafana-admin secret created. Read the password any time with:"
  echo "  kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d"
else
  echo "grafana-admin secret already exists."
fi
kubectl apply -f cluster/monitoring.yaml
