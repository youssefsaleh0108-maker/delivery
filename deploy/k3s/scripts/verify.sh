#!/bin/sh
# The assertions about this deployment that can be made without a cluster. Run from anywhere:
#   sh deploy/k3s/scripts/verify.sh
#
# Kustomize renders and kubectl dry-runs prove the YAML parses; they cannot prove that a request
# reaches the service it was meant for, because that answer lives in Traefik's router ordering
# rather than in the document. So the routing section below reimplements the one rule of that
# ordering — a route's priority is its explicit `priority`, or else the LENGTH OF ITS RULE — and
# resolves a table of real request paths through it. That is what caught /api/notifications/direct
# being answered by App Notification and /api/riders being answered by Accounting.
set -eu
cd "$(dirname "$0")/.."

fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "  ok  $*"; }

echo "== overlays are what the template renders =="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for env in dev qa; do
  sed -e "s/__API_HOST__/api-$env.youdrop.shop/g" \
      -e "s/__IAM_HOST__/iam-$env.youdrop.shop/g" \
      -e "s/__PORTAL_HOST__/portal-$env.youdrop.shop/g" \
      -e "s/__MON_HOST__/monitoring-$env.youdrop.shop/g" \
      overlays/ingress.template.yaml > "$tmp/$env.yaml"
  if diff -q "$tmp/$env.yaml" "overlays/$env/ingress.yaml" >/dev/null; then
    ok "overlays/$env/ingress.yaml"
  else
    fail "overlays/$env/ingress.yaml has drifted from the template — run scripts/render-overlays.sh"
  fi
done

echo "== requests reach the service that owns them =="
# host-suffix path expected-service
routes='
api /api/notifications/direct notifications-manager
api /api/notifications/direct/email notifications-manager
api /api/notifications app-notification
api /api/notifications/8f2/read app-notification
api /api/chat/threads app-notification
api /api/notification-preferences notifications-manager
api /api/riders/me/rating order-manager
api /api/riders/8f2/rating/comments order-manager
api /api/rider/earnings accounting-service
api /api/rider/cash-outs accounting-service
api /api/points/balance accounting-service
api /api/accounting/statements accounting-service
api /api/orders/8f2 order-manager
api /api/products/8f2 product-service
api /product-images/8f2.png minio
api /webhooks/dlr sms-connector
'

for env in dev qa; do
  echo "-- $env"
  printf '%s' "$routes" | while read -r hostpart path expected; do
    [ -n "${hostpart:-}" ] || continue
    winner=$(awk -v want_host="$hostpart-$env.youdrop.shop" -v path="$path" '
      # One record per route: the match line, an optional priority, then the service.
      /^ *- kind: Rule$/         { rule = ""; prio = "" }
      /^ *match: /               { rule = $0; sub(/^ *match: /, "", rule) }
      /^ *priority: /            { prio = $0; sub(/^ *priority: /, "", prio) }
      /^ *services: \[\{ name: / {
        svc = $0
        sub(/^ *services: \[\{ name: /, "", svc)
        sub(/,.*$/, "", svc)
        if (rule == "") next

        host = rule
        if (host !~ /Host\(`/) next
        sub(/^.*Host\(`/, "", host)
        sub(/`.*$/, "", host)
        if (host != want_host) next

        # A rule with no path matcher owns its whole host.
        matched = (rule !~ /Path(Prefix)?\(`/)

        rest = rule
        while (!matched && match(rest, /PathPrefix\(`[^`]*`\)/)) {
          p = substr(rest, RSTART + 12, RLENGTH - 14)
          if (substr(path, 1, length(p)) == p) matched = 1
          rest = substr(rest, RSTART + RLENGTH)
        }
        rest = rule
        while (!matched && match(rest, /Path\(`[^`]*`\)/)) {
          p = substr(rest, RSTART + 6, RLENGTH - 8)
          if (path == p) matched = 1
          rest = substr(rest, RSTART + RLENGTH)
        }
        if (!matched) next

        # Traefik: an explicit priority REPLACES the length-derived default, it does not add to it.
        effective = (prio == "" ? length(rule) : prio + 0)
        if (effective > best) { best = effective; winner = svc; ties = 0 }
        else if (effective == best) { ties = 1 }
      }
      END { print (ties ? "AMBIGUOUS" : (winner == "" ? "UNROUTED" : winner)) }
    ' "overlays/$env/ingress.yaml")

    if [ "$winner" = "$expected" ]; then
      ok "$path -> $winner"
    else
      echo "FAIL: $env $path -> $winner (expected $expected)"
      echo fail >> "$tmp/failed"
    fi
  done
done
[ ! -f "$tmp/failed" ] || fails=$((fails + $(wc -l < "$tmp/failed" | tr -d ' ')))

echo "== every YAML alias resolves =="
# A ConfigMap's `data:` values are strings to Kubernetes, so a dangling `*alias` inside one is
# waved through by kubectl and by kustomize and only fails when Prometheus or Grafana parses it —
# at which point that process does not start and there is nothing left to notice. Anchors here are
# per file, which is stricter than YAML's per document; nothing in this tree reuses a name.
for f in $(find base cluster overlays -name '*.yaml'); do
  missing=$(awk '
    { line = $0
      while (match(line, /&[A-Za-z0-9_.-]+/)) {
        anchors[substr(line, RSTART + 1, RLENGTH - 1)] = 1
        line = substr(line, RSTART + RLENGTH)
      }
      line = $0
      # Only a `*` that starts a value is an alias; `rules/*.yaml` and `$1:$2` are not.
      while (match(line, /(: |- |\[|, )\*[A-Za-z0-9_.-]+/)) {
        a = substr(line, RSTART, RLENGTH)
        sub(/^.*\*/, "", a)
        aliases[a] = 1
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { for (a in aliases) if (!(a in anchors)) printf "%s ", a }
  ' "$f")
  if [ -n "$missing" ]; then
    fail "$f references undefined YAML anchor(s): $missing"
    dangling=1
  fi
done
[ "${dangling:-0}" = 1 ] || ok "no dangling aliases in base, cluster or overlays"

echo "== monitoring =="
mon=cluster/monitoring.yaml
# E2E-29: the Config Server's actuator needs basic auth, so it must not be left in the job that
# sends none, and the job that does scrape it must carry credentials for both environments.
grep -q 'regex: config-server' "$mon" \
  && ok "config-server dropped from the credential-less pod job" \
  || fail "the kubernetes-pods job still scrapes config-server without credentials"
for env in dev qa; do
  grep -q "job_name: config-server-$env" "$mon" \
    && grep -q "$env-password" "$mon" \
    && ok "config-server-$env job has a credential" \
    || fail "no credentialed scrape job for config-server in delivery-$env"
done

# E2E-46: provisioning is the source of truth, and only deleteDatasources removes what the UI added.
grep -q 'deleteDatasources' "$mon" && grep -q 'name: jaeger' "$mon" \
  && ok "the hand-created jaeger datasource is provisioned away" \
  || fail "cluster/monitoring.yaml does not delete the unprovisioned jaeger datasource"
# ...and provisioning is only read at startup, so applying the ConfigMap deletes nothing on its own.
grep -q 'rollout restart deployment/grafana' scripts/setup-monitoring.sh \
  && ok "setup-monitoring.sh restarts grafana so provisioning is re-read" \
  || fail "nothing restarts grafana, so the datasource change never reaches the running instance"

# E2E-47: the dead-letter queues are drained by hand, so something has to say they are filling.
grep -q 'NotificationDeadLettersParked' "$mon" && grep -q 'rule_files' "$mon" \
  && ok "dead-letter alert rule is loaded" \
  || fail "no alert covers a filling dead-letter queue"
grep -q '/metrics/per-object' base/data-layer.yaml \
  && ok "rabbitmq exports per-queue metrics for it" \
  || fail "rabbitmq is not scraped per queue, so the dead-letter alert has no series"
grep -q 'Draining a dead-letter queue' README.md \
  && ok "the drain procedure is documented" \
  || fail "README.md documents no drain procedure"

echo
if [ "$fails" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$fails check(s) failed"
  exit 1
fi
