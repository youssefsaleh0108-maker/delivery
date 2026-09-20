#!/bin/sh
# Installs the monitoring stack. Idempotent. Run on the box from /opt/delivery/k3s.
#
# Re-run it after gen-secrets.sh has (re)created platform-secrets in an environment: the Config
# Server scrape credential is copied out of that Secret, and a stale copy is a target that
# answers 401 forever.
set -eu
cd "$(dirname "$0")/.."

kubectl apply -f cluster/monitoring.yaml >/dev/null 2>&1 || kubectl apply -f cluster/monitoring.yaml
# Alertmanager, node-exporter and kube-state-metrics. Separate file, same namespace, same script:
# a Prometheus with an `alerting:` block and no Alertmanager behind it is a stack that looks
# configured and delivers nothing.
kubectl apply -f cluster/alerting.yaml

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

# The relay password Alertmanager sends its email with.
#
# Copied out of an environment's platform-secrets rather than typed again: it is the SAME M365
# password the platform already mails through, and a second copy typed by hand is a second thing to
# rotate and a second thing to get wrong. qa first, because that is the environment becoming
# production and the one whose password will be kept current.
#
# Never printed, never on a command line that another user could read — `create --dry-run | apply`
# keeps it in the pipe. (This is the one place apply is used on a Secret: apply copies values into
# a last-applied-configuration annotation, so the annotation is stripped immediately afterwards.)
SMTP_PASS=$(read_platform_secret delivery-qa SMTP_PASSWORD)
[ -n "$SMTP_PASS" ] || SMTP_PASS=$(read_platform_secret delivery-dev SMTP_PASSWORD)
if [ -n "$SMTP_PASS" ]; then
  kubectl -n monitoring create secret generic alertmanager-smtp \
    --from-literal=password="$SMTP_PASS" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n monitoring annotate secret alertmanager-smtp \
    kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
  echo "alertmanager-smtp updated from platform-secrets (the value is not printed)."
else
  echo "WARNING: SMTP_PASSWORD is empty in both environments' platform-secrets, so Alertmanager"
  echo "has no relay password and every alert email will fail to send. Fill it in, then re-run this."
fi
unset SMTP_PASS

kubectl apply -f cluster/monitoring.yaml
kubectl apply -f cluster/alerting.yaml

# Grafana reads its provisioning directory once, at startup, and Prometheus reads its rules and
# scrape config once at startup too. Applying the ConfigMaps changes no field of either
# Deployment, so nothing rolls and the running processes keep the configuration they booted with:
# that is how a datasource somebody added by hand in the UI survived every redeploy of this file.
# The restart is what makes `deleteDatasources` run and what loads a changed rule.
kubectl -n monitoring rollout restart deployment/grafana deployment/prometheus deployment/alertmanager
kubectl -n monitoring rollout status deployment/grafana --timeout=120s
kubectl -n monitoring rollout status deployment/prometheus --timeout=120s
kubectl -n monitoring rollout status deployment/alertmanager --timeout=120s
kubectl -n monitoring rollout status deployment/kube-state-metrics --timeout=120s
kubectl -n monitoring rollout status daemonset/node-exporter --timeout=120s

# What Prometheus thinks it is talking to. A rule file that failed to parse, or an Alertmanager it
# cannot reach, both leave everything looking installed and nothing being delivered.
echo
echo "== Prometheus"
kubectl -n monitoring exec deploy/prometheus -- \
  wget -qO- http://localhost:9090/api/v1/alertmanagers 2>/dev/null \
  | head -c 400 || echo "(could not query Prometheus)"
echo
echo "== rule groups loaded"
kubectl -n monitoring exec deploy/prometheus -- \
  wget -qO- http://localhost:9090/api/v1/rules 2>/dev/null \
  | tr ',' '\n' | grep -c '"name"' || echo "(could not query Prometheus)"
echo
echo "Send yourself a test alert to prove the whole path — see 'Alerting' in deploy/k3s/README.md."
