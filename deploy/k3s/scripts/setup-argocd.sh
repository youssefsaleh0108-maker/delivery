#!/bin/sh
# Installs Argo CD and wires it to the shared Traefik edge. Idempotent. Run on the box from
# /opt/delivery/k3s.
#
# The server is switched to --insecure because TLS terminates at Traefik; without it Argo's own
# self-signed HTTPS answers through the edge and every browser refuses the redirect loop.
#
# The initial admin password:
#   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
set -eu
cd "$(dirname "$0")/.."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# --insecure via the parameters ConfigMap, then restart the server to read it.
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deploy/argocd-server

echo "Waiting for the server..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

kubectl apply -f cluster/argocd.yaml
echo "Argo CD installed; Applications delivery-dev (branch develop) and delivery-qa (branch qa) created."
