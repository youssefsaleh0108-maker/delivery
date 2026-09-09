#!/bin/sh
# Installs the monitoring stack. Idempotent. Run on the box from /opt/delivery/k3s.
#
# Re-run it after gen-secrets.sh has (re)created platform-secrets in an environment: the Config
# Server scrape credential is copied out of that Secret, and a stale copy is a target that
# answers 401 forever.
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

# Prometheus scrapes the Config Server's actuator, which wants the same basic-auth login every
# config client uses. That credential is minted per environment by gen-secrets.sh and lives in
# each namespace's platform-secrets; this copies exactly those two keys — not the rest of the
# Secret — into monitoring, where the scrape jobs read them as files.
#
# Applied rather than created, so a rerun after a password rotation replaces the copy. An
# environment that does not exist yet contributes an empty password: its job then fails to
# authenticate, which the ScrapeTargetDown alert reports, instead of Prometheus refusing to start.
read_platform_secret() {
  kubectl -n "$1" get secret platform-secrets -o "jsonpath={.data.$2}" 2>/dev/null \
    | base64 -d 2>/dev/null || true
}

CS_USER=$(read_platform_secret delivery-dev CONFIG_SERVER_USER)
[ -n "$CS_USER" ] || CS_USER=$(read_platform_secret delivery-qa CONFIG_SERVER_USER)
[ -n "$CS_USER" ] || CS_USER=config

kubectl -n monitoring create secret generic config-server-scrape \
  --from-literal=username="$CS_USER" \
  --from-literal=dev-password="$(read_platform_secret delivery-dev CONFIG_SERVER_PASSWORD)" \
  --from-literal=qa-password="$(read_platform_secret delivery-qa CONFIG_SERVER_PASSWORD)" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f cluster/monitoring.yaml

# Grafana reads its provisioning directory once, at startup, and Prometheus reads its rules and
# scrape config once at startup too. Applying the ConfigMaps changes no field of either
# Deployment, so nothing rolls and the running processes keep the configuration they booted with:
# that is how a datasource somebody added by hand in the UI survived every redeploy of this file.
# The restart is what makes `deleteDatasources` run and what loads a changed rule.
kubectl -n monitoring rollout restart deployment/grafana deployment/prometheus
kubectl -n monitoring rollout status deployment/grafana --timeout=120s
kubectl -n monitoring rollout status deployment/prometheus --timeout=120s
