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
# Rendered by the real script into a scratch directory, rather than by a copy of its sed list kept
# here. The two drifted apart the moment the template grew a rule the copy did not know (the
# dev-only CORS origins), and a drift check that renders differently from the renderer reports
# drift that is not there — or worse, misses drift that is.
sh scripts/render-overlays.sh "$tmp" >/dev/null
for env in dev qa; do
  if diff -q "$tmp/$env/ingress.yaml" "overlays/$env/ingress.yaml" >/dev/null; then
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
api /user-avatars/8f2.jpg minio
api /order-attachments/8f2.pdf minio
api /merchant-kyc/applications/8f2/8f2.jpg minio
api /delivery-proof/8f2.jpg UNROUTED
api /receipts/8f2.pdf UNROUTED
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

echo "== presigned uploads meet their body limit before storage =="
# Neither a presigned PUT nor MinIO can cap a body, so the route's own middleware is the only limit a
# file meets before MinIO stores it. It sits in the four lines after the route's match.
for env in dev qa; do
  for pair in order-attachments:order-attachment-upload-limit merchant-kyc:merchant-kyc-upload-limit; do
    prefix=${pair%%:*}
    limit=${pair#*:}
    if grep -F -A4 "PathPrefix(\`/$prefix\`)" "overlays/$env/ingress.yaml" | grep -q "name: $limit }"; then
      ok "$env /$prefix carries $limit"
    else
      fail "$env /$prefix is routed without $limit"
    fi
  done
done

echo "== the two sites a human opens carry their headers (PT-1) =="
sh scripts/test/public-site-headers.test.sh > "$tmp/headers.out" 2>&1 \
  && ok "scripts/test/public-site-headers.test.sh" \
  || { fail "scripts/test/public-site-headers.test.sh:"; grep FAIL "$tmp/headers.out"; }
for env in dev qa; do
  ing="overlays/$env/ingress.yaml"
  # The middleware has to be ON the route, not merely defined in the file.
  grep -F -A3 "Host(\`portal-$env.youdrop.shop\`)" "$ing" | grep -q 'name: portal-security-headers' \
    && ok "$env portal route carries portal-security-headers" \
    || fail "$env portal route does not carry portal-security-headers"
  csp=$(awk 'BEGIN{RS="\n---"} /name: portal-security-headers/ {print}' "$ing" | tr -d '\n')
  # 180 days. Not includeSubDomains (it would bind hostnames that do not exist yet) and not
  # preload (browsers ship that list; it is very hard to undo).
  case "$csp" in
    *"stsSeconds: 15552000"*) ok "$env portal HSTS is 180 days" ;;
    *) fail "$env portal HSTS is not 15552000 seconds" ;;
  esac
  case "$csp" in
    *"stsIncludeSubdomains: false"*"stsPreload: false"*) ok "$env portal HSTS claims no subdomain and no preload" ;;
    *) fail "$env portal HSTS must set stsIncludeSubdomains and stsPreload false explicitly" ;;
  esac
  case "$csp" in
    *"referrerPolicy: strict-origin-when-cross-origin"*) ok "$env portal Referrer-Policy" ;;
    *) fail "$env portal Referrer-Policy is not strict-origin-when-cross-origin" ;;
  esac
  case "$csp" in
    *"frame-ancestors 'none'"*) ok "$env portal CSP refuses framing" ;;
    *) fail "$env portal CSP has no frame-ancestors 'none'" ;;
  esac
  # Without this the CanvasKit wasm never compiles and the portal renders a blank page.
  case "$csp" in
    *"'wasm-unsafe-eval'"*) ok "$env portal CSP allows the CanvasKit wasm" ;;
    *) fail "$env portal CSP has no 'wasm-unsafe-eval': the Flutter build would render nothing" ;;
  esac
  case "$csp" in
    *"unsafe-eval"*) case "$csp" in *"'unsafe-eval'"*) fail "$env portal CSP allows 'unsafe-eval'" ;; esac ;;
  esac
  for host in "api-$env.youdrop.shop" "iam-$env.youdrop.shop"; do
    case "$csp" in
      *"https://$host"*) ok "$env portal CSP reaches $host" ;;
      *) fail "$env portal CSP does not name $host" ;;
    esac
  done
  # A CSP naming the OTHER environment's hosts would let the qa portal talk to dev.
  other=qa; [ "$env" = qa ] && other=dev
  case "$csp" in
    *"-$other.youdrop.shop"*) fail "$env portal CSP names a $other host" ;;
    *) ok "$env portal CSP names no $other host" ;;
  esac
  # The one third-party origin. The app reads it from a dart-define whose default lives in the
  # client tree, so the policy and the app can drift apart silently; this is the tripwire.
  tile=$(sed -n "s|.*defaultValue: 'https://\([a-z0-9.-]*\)/.*|\1|p" \
    ../../clients/packages/delivery_core/lib/src/util/map_tiles.dart)
  if [ -z "$tile" ]; then
    fail "could not read MAP_TILE_URL's default host from map_tiles.dart"
  else
    case "$csp" in
      *"https://$tile"*) ok "$env portal CSP allows the map tiles ($tile)" ;;
      *) fail "$env portal CSP does not allow $tile, the MAP_TILE_URL default: every map would be blank" ;;
    esac
  fi

  echo "-- $env CORS (PT-9)"
  cors=$(awk 'BEGIN{RS="\n---"} /name: platform-cors/ {print}' "$ing")
  # The regex list is what echoed any *.youdrop.shop back as an allowed origin.
  case "$cors" in
    *accessControlAllowOriginListRegex*) fail "$env CORS is back on a regex origin list" ;;
    *) ok "$env CORS lists exact origins" ;;
  esac
  case "$cors" in
    *"accessControlAllowCredentials: false"*) ok "$env CORS sends no credentials" ;;
    *) fail "$env CORS allows credentials; no client in this repository needs them" ;;
  esac
  origins=$(printf '%s' "$cors" | sed -n 's|^ *- \(https\{0,1\}://[^ ]*\)$|\1|p' | sort | tr '\n' ' ')
  want="https://portal-$env.youdrop.shop https://www.youdrop.shop "
  [ "$env" = dev ] && want="http://127.0.0.1:5010 http://127.0.0.1:5012 http://localhost:5010 http://localhost:5012 https://portal-dev.youdrop.shop https://www.youdrop.shop "
  [ "$origins" = "$want" ] \
    && ok "$env CORS origins: $origins" \
    || fail "$env CORS origins are [$origins], expected [$want]"
  # app-notification checks the same origins on a browser WebSocket. Two lists that disagree fail
  # in different places for different clients, which is the hardest kind of CORS problem to see.
  spring=$(sed -n 's/^ *- \{0,4\}CORS_ALLOWED_ORIGINS=//p' "overlays/$env/kustomization.yaml" | tr ',' '\n' | sort | tr '\n' ' ')
  [ "$spring" = "$want" ] \
    && ok "$env CORS_ALLOWED_ORIGINS matches the edge" \
    || fail "$env CORS_ALLOWED_ORIGINS is [$spring] but the edge admits [$want]"

  echo "-- $env the Keycloak admin console is not public (PT-7)"
  grep -F -A4 "Host(\`iam-$env.youdrop.shop\`) && PathPrefix(\`/admin\`)" "$ing" | grep -q 'name: deny-public' \
    && ok "$env /admin on the public iam host is refused" \
    || fail "$env has no route refusing /admin on iam-$env.youdrop.shop"
  # ...and the endpoints every client needs are NOT behind it.
  grep -q 'PathPrefix(`/realms`)' "$ing" \
    && fail "$env has a /realms rule: the token, JWKS and login endpoints must stay on the catch-all" \
    || ok "$env leaves /realms on the host's catch-all rule"
done
# One public site, one API host in its CSP, one API host in the file that configures its JS. They
# move together at go-live, and this is what says so out loud if only one of them moves.
site_csp=$(awk 'BEGIN{RS="\n---"} /name: site-security-headers/ {print}' cluster/website.yaml | tr -d '\n')
for key in DELIVERY_API_BASE DELIVERY_IAM_BASE; do
  host=$(sed -n "s|^window\.$key *= *'https://\([a-z0-9.-]*\)'.*|\1|p" ../../clients/website/config.js)
  if [ -z "$host" ]; then
    fail "could not read $key from clients/website/config.js"
  else
    case "$site_csp" in
      *"https://$host"*) ok "the site's CSP reaches $host ($key)" ;;
      *) fail "clients/website/config.js points at $host, which the site's CSP does not allow" ;;
    esac
  fi
done
case "$site_csp" in
  *"style-src 'self';"*) ok "the site's CSP allows no inline style" ;;
  *) fail "the site's CSP allows inline styles; admin.html's block belongs in admin.css" ;;
esac
grep -q 'add_header Cache-Control "no-cache"' ../../clients/website/nginx.conf \
  && ok "the site revalidates its unhashed HTML, JS and config.js (PT-11)" \
  || fail "clients/website/nginx.conf has no server-level Cache-Control: the site goes stale again"

echo "== the realm a fresh import would build (PT-3, PT-7) =="
# Greps rather than jq: jq is not assumed anywhere in this script, and every value below is alone
# on its line in the realm file. These assert the FILE, which is what a fresh database imports; a
# running environment is brought to the same place by `rotate-secrets.sh <ns> edge-identity`, and
# that step re-checks every one of them against Keycloak itself.
realm=base/assets/keycloak/realm-delivery-platform.json
grep -q '"sslRequired": "external"' "$realm" \
  && ok "sslRequired: external" \
  || fail "sslRequired is not external: Keycloak would accept a plain-HTTP sign-in from outside"
grep -q '"revokeRefreshToken": true' "$realm" && grep -q '"refreshTokenMaxReuse": 0' "$realm" \
  && ok "refresh tokens rotate and cannot be reused" \
  || fail "the realm does not rotate refresh tokens (revokeRefreshToken true, refreshTokenMaxReuse 0)"
# The delivery-portal client, from its clientId line to the end of its object.
portal=$(awk '/"clientId": "delivery-portal"/ {on=1} on {print} on && /^    },?$/ {exit}' "$realm")
case "$portal" in
  *'"directAccessGrantsEnabled": false'*) ok "delivery-portal has no password grant" ;;
  *) fail "delivery-portal still allows the password grant: a phished password is a back-office session" ;;
esac
# Both lists have to be DECLARED. Leaving them out is not neutral — Keycloak then applies the
# realm defaults, and offline_access is one of them, which is how the back office got a token
# that never expires.
case "$portal" in
  *'"defaultClientScopes"'*'"optionalClientScopes"'*) ok "delivery-portal declares its own client scopes" ;;
  *) fail "delivery-portal declares no client scopes, so the realm defaults apply and offline_access comes back" ;;
esac
case "$portal" in
  *offline_access*) fail "delivery-portal still has the offline_access scope" ;;
  *) ok "delivery-portal cannot ask for offline_access" ;;
esac
for pair in 'client.session.idle.timeout": "28800' 'client.session.max.lifespan": "86400'; do
  case "$portal" in
    *"$pair"*) ok "delivery-portal ${pair%%\"*}" ;;
    *) fail "delivery-portal is missing $pair" ;;
  esac
done
# The one client the scripts and the phones still sign in on directly.
mobile=$(awk '/"clientId": "mobile-app"/ {on=1} on {print} on && /^    },?$/ {exit}' "$realm")
case "$mobile" in
  *'"directAccessGrantsEnabled": true'*) ok "mobile-app keeps the password grant the apps need" ;;
  *) fail "mobile-app lost the password grant: the phone sign-in and every smoke script use it" ;;
esac
# ...and no script may ask delivery-portal for one, because it will be refused. The three files
# excluded here name the client in order to ASSERT on it rather than to sign in with it: this
# script, scripts/test/, and rotate-secrets.sh — which proves the refusal against the live realm
# instead of against the text.
stale=$(grep -rl 'client_id=.*delivery-portal\|token .* delivery-portal' --include='*.sh' . ../../infra 2>/dev/null \
  | grep -v -e 'scripts/verify\.sh' -e 'scripts/rotate-secrets\.sh' -e 'scripts/test/' | sort -u | tr '\n' ' ')
[ -z "$stale" ] \
  && ok "no script signs in on delivery-portal's password grant" \
  || fail "these still use delivery-portal's password grant, which is now refused: $stale"
# The admin REST API is closed on the public hostname, so this script cannot reach it there.
grep -q 'port-forward svc/keycloak' scripts/rotate-secrets.sh \
  && ok "rotate-secrets.sh reaches the admin API inside the cluster" \
  || fail "rotate-secrets.sh does not port-forward to keycloak: its admin calls would meet the edge's 403"
grep -q '^ADMIN="\$IAM' scripts/rotate-secrets.sh \
  && fail "rotate-secrets.sh builds the admin API URL from the public hostname again" \
  || ok "no admin API URL is built from the public iam hostname"

echo "== every image is pinned (PIN-1) =="
# A moving tag is a deployment nobody performed. The pod restarts for an unrelated reason, re-pulls
# `:main` / `:latest` / `:qa` / `:develop` / `:3-management`, and comes back on a build nobody chose
# at an hour nobody picked — with nothing in git to say it happened. That is how `minio:latest`
# became an outage when Docker Hub stopped serving the repository.
#
# Two shapes are allowed and nothing else: a digest (`@sha256:<64 hex>`), which is the content
# itself, or one of our own CI's `sha-<40 hex>` tags, which that CI never re-points.
pinned() {   # pinned <image reference>
  printf '%s' "$1" | grep -Eq '@sha256:[0-9a-f]{64}$|:sha-[0-9a-f]{40}$'
}
for f in base/data-layer.yaml base/identity.yaml base/services.yaml base/portal.yaml \
         cluster/monitoring.yaml cluster/logging.yaml cluster/website.yaml cluster/traefik-config.yaml; do
  sed -n 's/^ *image: *//p' "$f" | while read -r img; do
    [ -n "$img" ] || continue
    if pinned "$img"; then
      ok "$f ${img##*/}"
    else
      echo "FAIL: $f pulls a moving tag: $img"
      echo fail >> "$tmp/failed"
    fi
  done
done
# The overlays override those defaults, so an overlay may not reintroduce a moving tag either.
for env in dev qa; do
  bad_tags=$(sed -n 's/^ *newTag: *//p' "overlays/$env/kustomization.yaml" | grep -Ev '^sha-[0-9a-f]{40}$' | tr '\n' ' ')
  [ -z "$bad_tags" ] \
    && ok "$env overlay pins every newTag" \
    || fail "$env overlay carries moving tag(s): $bad_tags"
  bad_digests=$(sed -n 's/^ *digest: *//p' "overlays/$env/kustomization.yaml" | grep -Ev '^sha256:[0-9a-f]{64}$' | tr '\n' ' ')
  [ -z "$bad_digests" ] \
    && ok "$env overlay's digests are well formed" \
    || fail "$env overlay has malformed digest(s): $bad_digests"
done
[ ! -f "$tmp/failed" ] || { fails=$((fails + $(wc -l < "$tmp/failed" | tr -d ' '))); rm -f "$tmp/failed"; }

echo "== both overlays render (kubectl kustomize) =="
# The one check that proves the whole document set parses AND that every patch still finds its
# target. Skipped rather than failed where kubectl is absent, so this script still runs on a
# machine that has no cluster tooling at all — but it is never silently skipped.
if command -v kubectl >/dev/null 2>&1; then
  for env in dev qa; do
    if kubectl kustomize "overlays/$env" > "$tmp/render-$env.yaml" 2>"$tmp/render-$env.err"; then
      ok "overlays/$env renders ($(grep -c '^kind:' "$tmp/render-$env.yaml") objects)"
    else
      fail "overlays/$env does not render: $(head -n3 "$tmp/render-$env.err" | tr '\n' ' ')"
    fi
  done
else
  echo "  --    kubectl not on PATH: the kustomize render is not checked here"
fi

echo "== one node, two environments: resource safety (PS-3) =="
# Every container that base declares must carry its own memory limit. dev's ResourceQuota makes a
# limit compulsory, and its LimitRange exists so that a missing one does not REFUSE the pod — but
# leaning on that default is how a namespace quietly goes over budget, so the default should never
# have anything to do. (The `mc` bootstrap container is the one exception: its Job has Completed,
# and a Job's pod spec is immutable, so giving it limits means renaming the Job.)
for f in base/data-layer.yaml base/identity.yaml base/services.yaml base/portal.yaml; do
  missing=$(awk '
    /^ *- name: [a-z0-9-]+$/ && match($0, /^ {8}- name: /) { if (c != "") { if (!seen) print c }; c = $NF; seen = 0 }
    /^ *limits: *\{? *memory/ { seen = 1 }
    /^ *limits: *$/ { inlim = 1; next }
    inlim && /memory:/ { seen = 1; inlim = 0 }
    END { if (c != "" && !seen) print c }
  ' "$f" | grep -v -e '^realm$' -e '^theme$' -e '^bootstrap$' -e '^policies$' -e '^conf$' -e '^web$' -e '^init$' -e '^data$' -e '^mc$' | tr '\n' ' ')
  [ -z "$missing" ] \
    && ok "$f: every container declares a memory limit" \
    || fail "$f: container(s) with no memory limit: $missing"
done

for env in dev qa; do
  [ -s "$tmp/render-$env.yaml" ] || continue
  want=prod-critical; [ "$env" = dev ] && want=dev-standard
  # Count pod templates (every Deployment, StatefulSet and Job has exactly one) against the number
  # that name a priority. A workload added later without one is what this catches.
  templates=$(grep -c '^      priorityClassName:\|^          priorityClassName:' "$tmp/render-$env.yaml" || true)
  workloads=$(grep -c '^kind: \(Deployment\|StatefulSet\|Job\)$' "$tmp/render-$env.yaml" || true)
  [ "$templates" = "$workloads" ] && [ "$workloads" -gt 0 ] \
    && ok "$env: all $workloads workloads carry a priorityClassName" \
    || fail "$env: $workloads workloads but $templates priorityClassName(s)"
  wrong=$(grep 'priorityClassName:' "$tmp/render-$env.yaml" | awk '{print $2}' | sort -u | grep -v "^$want$" | tr '\n' ' ')
  [ -z "$wrong" ] \
    && ok "$env: the priority is $want" \
    || fail "$env: unexpected priority class(es): $wrong (expected $want)"
  # The two policies that make the wall, and the mistake that silently removes it.
  for pol in default-deny-ingress allow-same-namespace allow-edge allow-monitoring; do
    grep -q "name: $pol" "$tmp/render-$env.yaml" \
      && ok "$env: NetworkPolicy $pol" \
      || fail "$env: no NetworkPolicy $pol — the two environments can reach each other"
  done
done
# `namespaceSelector: {}` inside allow-same-namespace means "every namespace", which is the exact
# opposite of what the policy is named for and is invisible in a diff that only reads the name.
awk 'BEGIN{RS="\n---"} /name: allow-same-namespace/ {print}' base/network-policies.yaml \
  | sed 's/#.*//' | grep -q 'namespaceSelector: *{}' \
  && fail "allow-same-namespace uses an empty namespaceSelector: that admits EVERY namespace" \
  || ok "allow-same-namespace admits only its own namespace"

# Two things no manifest can assert, so the live steps that do are checked for instead: a PV's
# reclaim policy (the PV does not exist until the PVC binds) and whether k3s enforces
# NetworkPolicies at all (a cluster started with --disable-network-policy accepts them and does
# nothing).
for step in pv-retain netpol-proof; do
  grep -q "^  $step)" scripts/rotate-secrets.sh \
    && ok "rotate-secrets.sh has the $step step" \
    || fail "rotate-secrets.sh has no $step step, and $step is not something a manifest can do"
done
grep -q 'persistentVolumeReclaimPolicy' scripts/rotate-secrets.sh \
  && ok "pv-retain patches the reclaim policy" \
  || fail "nothing sets persistentVolumeReclaimPolicy: deleting a PVC would delete the database"

# dev's rendered limits against dev's own quota, from the same two files the cluster reads.
if [ -s "$tmp/render-dev.yaml" ]; then
  quota=$(awk '/^ *limits\.memory:/ { print $2; exit }' overlays/dev/resource-safety.yaml)
  used=$(awk '
    /^ *limits: *$/ { inlim = 1; next }
    inlim && /^ *memory: / {
      v = $2; n = v + 0
      if (v ~ /Mi$/) n *= 1048576; else if (v ~ /Gi$/) n *= 1073741824; else if (v ~ /Ki$/) n *= 1024
      total += n; inlim = 0; next
    }
    inlim && /^ *(cpu|ephemeral-storage): / { next }
    { inlim = 0 }
    END { printf "%d", total }
  ' "$tmp/render-dev.yaml")
  cap=$(printf '%s' "$quota" | awk '{ v = $0; n = v + 0; if (v ~ /Mi$/) n *= 1048576; else if (v ~ /Gi$/) n *= 1073741824; printf "%d", n }')
  if [ "$used" -le "$cap" ]; then
    ok "dev fits its own quota: $((used / 1048576))Mi of $quota ($(( (cap - used) / 1048576 ))Mi spare)"
  else
    fail "dev's rendered limits are $((used / 1048576))Mi, over its $quota ResourceQuota by $(( (used - cap) / 1048576 ))Mi: every pod in delivery-dev would be refused at admission"
  fi
fi

# Production's Postgres asks for what it is allowed to use, so the kubelet's OOM score for it is
# the lowest a container can have without a CPU limit.
if [ -s "$tmp/render-qa.yaml" ]; then
  # The StatefulSet's own document: the Service is also called postgres, and it has no resources.
  # `^` anchors to the RECORD here, not the line, so both matches spell out the newline.
  pg=$(awk 'BEGIN{RS="\n---\n"} /(^|\n)kind: StatefulSet\n/ && /(^|\n)  name: postgres\n/ {print}' "$tmp/render-qa.yaml")
  pg_req=$(printf '%s\n' "$pg" | awk '/^ *requests: *$/ {inr=1;next} inr && /memory:/ {print $2; exit}')
  pg_lim=$(printf '%s\n' "$pg" | awk '/^ *limits: *$/ {inl=1;next} inl && /memory:/ {print $2; exit}')
  [ -n "$pg_req" ] && [ "$pg_req" = "$pg_lim" ] \
    && ok "qa postgres requests what it may use ($pg_req = $pg_lim)" \
    || fail "qa postgres requests $pg_req against a $pg_lim limit: it is evicted as if it were over budget"
fi

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

echo "== credentials stay out of the repository =="
# 2026-09: the repository was public and carried working dev/qa credentials. These keep them out.
realm=base/assets/keycloak/realm-delivery-platform.json
# "value" also names protocol-mapper config values; only credentials and client secrets matter.
cred_literals=$(awk '/"type": "password"/ { getline; if ($0 !~ /"value": "\$\{[A-Z][A-Z0-9_]*\}"/) n++ } END { print n + 0 }' "$realm")
secret_literals=$(grep -E '"secret": "' "$realm" | grep -c -v -E '"secret": "\$\{[A-Z][A-Z0-9_]*\}"' || true)
[ "$cred_literals" = 0 ] && [ "$secret_literals" = 0 ] \
  && ok "the realm file's client secrets and passwords are all \${...} placeholders" \
  || fail "the realm file carries $secret_literals literal client secret(s) and $cred_literals literal password(s)"
# A placeholder Keycloak cannot resolve is imported as its own text, so every one must come from a
# Secret on the keycloak container.
for name in $(grep -o '"\${[A-Z][A-Z0-9_]*}"' "$realm" | tr -d '"${}' | sort -u); do
  grep -A1 -- "- name: $name\$" base/identity.yaml | grep -q secretKeyRef \
    && ok "placeholder $name is fed from a Secret" \
    || fail "placeholder $name has no secretKeyRef on the keycloak container: it would import as literal text"
done
for secret in $( { grep -h -o 'secretKeyRef: { name: [a-z0-9-]*' base/*.yaml | awk '{print $4}'
                   grep -h -A1 'secretKeyRef:$' base/*.yaml | grep -o 'name: [a-z0-9-]*' | awk '{print $2}'
                   grep -h -o 'secret: [a-z0-9-]*' overlays/ingress.template.yaml | awk '{print $2}'; } | sort -u); do
  [ "$secret" = anthropic-api ] && continue   # optional, created by hand (README.md)
  grep -q -E "(mint|create secret generic) $secret( |\\\\|\$)" scripts/gen-secrets.sh \
    && ok "Secret $secret is minted by gen-secrets.sh" \
    || fail "Secret $secret is referenced but gen-secrets.sh never creates it"
done
grep -q -E '^\s+WHATSAPP_(APP_SECRET|VERIFY_TOKEN):' base/configmap-common.yaml \
  && fail "platform-common carries a WhatsApp secret again" \
  || ok "platform-common carries no WhatsApp secret"
grep -r -l -E '\$(2[aby]|apr1)\$' base cluster overlays scripts >/dev/null 2>&1 \
  && fail "a password hash is in the repository: $(grep -r -l -E '\$(2[aby]|apr1)\$' base cluster overlays scripts | tr '\n' ' ')" \
  || ok "no password hash in base, cluster, overlays or scripts"
grep -q 'keycloak\.client-secret=' base/assets/vault/bootstrap.sh \
  && fail "vault/bootstrap.sh seeds a Keycloak client secret" \
  || ok "the Vault seed carries no Keycloak client secret"
grep -q -E 'tok (customer|rider|merchant|backoffice|carrier) [^)]' scripts/e2e-smoke.sh || grep -q -E 'password=[^$"]' scripts/e2e-smoke.sh \
  && fail "scripts/e2e-smoke.sh carries a password" \
  || ok "scripts/e2e-smoke.sh reads the demo logins from their Secret"
for t in scripts/test/gen-secrets.test.sh scripts/test/e2e-smoke.test.sh; do
  sh "$t" > "$tmp/test.out" 2>&1 && ok "$t" || { fail "$t:"; grep FAIL "$tmp/test.out"; }
done

echo
if [ "$fails" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$fails check(s) failed"
  exit 1
fi
