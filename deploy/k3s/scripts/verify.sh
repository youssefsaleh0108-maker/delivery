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
api /s/dekkanet-al-rawche-1a2b3c4d product-service
api /s/dekkanet-al-rawche-1a2b3c4d/qr.png product-service
api /s/dekkanet-al-rawche-1a2b3c4d/manifest.webmanifest product-service
api /s/assets/shop.css product-service
api /s/assets/shop.js product-service
api /sitemap.xml product-service
api /api/table-orders order-manager
api /api/table-orders/8f2 order-manager
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

echo "== the public shop page (/s/{slug}) =="
# The one page on this platform a stranger opens with no app and no account. Three things about it
# are decided here rather than in Java, so this is where they are checked.
#
# Every grep below reads a comment-STRIPPED copy of the rendered overlay. The route and its
# middleware are documented at length in the template — including the sentence "there is no
# contentSecurityPolicy here", which a check looking for that word would read as one.
for env in dev qa; do
  ing="$tmp/$env-ingress-nocomments.yaml"
  sed 's/[[:space:]]*#.*$//' "overlays/$env/ingress.yaml" > "$ing"
  shop_mw=$(awk 'BEGIN{RS="\n---"} /name: shop-page-headers/ {print}' "$ing" | tr -d '\n')
  # THE LOAD-BEARING ONE. product-service sends the page's own Content-Security-Policy, built from
  # the same setting that produced the image URLs in the markup and asserted by its own tests. A
  # `headers` middleware that named a policy would REPLACE that header with a string nothing can
  # test, and the first symptom would be every product photo silently blocked in the browser.
  case "$shop_mw" in
    *contentSecurityPolicy*) fail "$env shop-page-headers sets a CSP: it would replace the page's own" ;;
    *) ok "$env shop-page-headers leaves the CSP to product-service" ;;
  esac
  case "$shop_mw" in
    *"stsSeconds: 15552000"*"stsIncludeSubdomains: false"*"stsPreload: false"*)
      ok "$env shop page HSTS matches the site's (180 days, no subdomains, no preload)" ;;
    *) fail "$env shop page HSTS does not match the portal's and the site's" ;;
  esac
  grep -F -A9 "Host(\`api-$env.youdrop.shop\`) && (PathPrefix(\`/s/\`)" "$ing" \
    | grep -q 'name: shop-page-compress' \
    && ok "$env shop page is compressed on the way out" \
    || fail "$env shop page is served uncompressed: it is read on a phone on 3G"
done
# www is ONE hostname and it points at ONE environment (clients/website/config.js). Rendering this
# route into qa as well would put two identical routers on www in two namespaces and let whichever
# synced last decide which environment's shops the public site serves.
dev_ing="$tmp/dev-ingress-nocomments.yaml"
qa_ing="$tmp/qa-ingress-nocomments.yaml"
grep -q 'Host(`www.youdrop.shop`) && (PathPrefix(`/s/`)' "$dev_ing" \
  && ok "dev serves the shop page on www, the address a shop prints" \
  || fail "no www route for /s/: the canonical URL would 404 on the public site"
grep -q 'Host(`www.youdrop.shop`)' "$qa_ing" \
  && fail "qa also claims www: two routers on one public hostname, last sync wins" \
  || ok "qa claims no www route"
# The site's own router owns the whole of www (cluster/website.yaml). Traefik gives a rule with no
# `priority` one equal to the LENGTH OF ITS RULE, so this route wins today by being the longer
# string — which is not a thing to rely on across two files.
grep -F -A2 'Host(`www.youdrop.shop`) && (PathPrefix(`/s/`)' "$dev_ing" | grep -q 'priority:' \
  && ok "the www shop-page route outranks the site's catch-all explicitly" \
  || fail "the www shop-page route has no explicit priority: the static site would answer /s/"
# Both hostnames share one middleware list, by alias, so a change can never reach one and not the
# other — the way a shop page with no compression on www and compression on the API host would.
grep -F -A4 'Host(`www.youdrop.shop`) && (PathPrefix(`/s/`)' "$dev_ing" \
  | grep -q 'middlewares: \*shop-page-mw' \
  && ok "www and the API host serve the shop page through the same middlewares" \
  || fail "the www shop-page route has a middleware list of its own: the two will drift"
# A shop's page is the only thing on this platform a crawler can index, so the file that tells it
# where to look has to name the sitemap the service serves.
grep -q 'Sitemap: https://www.youdrop.shop/sitemap.xml' ../../clients/website/nginx.conf \
  && ok "robots.txt points crawlers at the shop sitemap" \
  || fail "clients/website/nginx.conf serves a robots.txt with no Sitemap line"

echo "== ordering at the table (/api/table-orders) =="
# A diner scans the card on table seven and lands on www, because www is the address a shop prints.
# The page may fetch its own origin and nothing else (`connect-src 'self'`), so the endpoint it
# sends to has to answer on www as well — or every send from a scanned card is a cross-origin
# request the browser refuses, and the only ways out would be naming an API host in the page's CSP
# or turning CORS on for an anonymous endpoint that prints paper in a kitchen.
grep -q 'Host(`www.youdrop.shop`) && PathPrefix(`/api/table-orders`)' "$dev_ing" \
  && ok "dev takes table orders on www, the address on the card" \
  || fail "no www route for /api/table-orders: a scanned code could not send, and connect-src 'self' is why"
# Same reasoning as the shop page: ONE www, pointed at ONE environment.
grep -q 'PathPrefix(`/api/table-orders`)' "$qa_ing" \
  && ok "qa takes table orders on its own API host" \
  || fail "qa has no /api/table-orders route at all"
grep -F -A2 'Host(`www.youdrop.shop`) && PathPrefix(`/api/table-orders`)' "$dev_ing" \
  | grep -q 'priority:' \
  && ok "the www table-order route outranks the site's catch-all explicitly" \
  || fail "the www table-order route has no explicit priority: the static site would answer it"
grep -F -A4 'Host(`www.youdrop.shop`) && PathPrefix(`/api/table-orders`)' "$dev_ing" \
  | grep -q 'middlewares: \*table-orders-mw' \
  && ok "www and the API host take table orders through the same middlewares" \
  || fail "the www table-order route has a middleware list of its own: the two will drift"
for env in dev qa; do
  ing="$tmp/$env-ingress-nocomments.yaml"
  # CORS on the one anonymous endpoint that writes into a kitchen would be an invitation for it to
  # be called from anywhere. Same-origin needs none, which is the whole point of the www route.
  grep -F -A6 "PathPrefix(\`/api/table-orders\`)" "$ing" | grep -q 'name: platform-cors' \
    && fail "$env allows CORS on table orders: an anonymous kitchen endpoint callable from any site" \
    || ok "$env takes table orders same-origin only, with no CORS allowance"
  # The edge's limiter is per source IP and a restaurant's guest Wi-Fi is one address, so this is
  # a flood guard and never the rule; TableOrderRate in order-manager is keyed per table and shop.
  grep -F -A6 "PathPrefix(\`/api/table-orders\`)" "$ing" | grep -q 'name: platform-rate-limit' \
    && ok "$env keeps the edge flood guard on table orders" \
    || fail "$env takes table orders with no rate limit at the edge"
  # A route is not a permission: these paths reach order-manager, and order-manager's own
  # permit-all list is what decides they may be called without a token.
  grep -F -A2 "PathPrefix(\`/api/table-orders\`)" "$ing" | grep -q 'name: order-manager' \
    && ok "$env sends table orders to order-manager" \
    || fail "$env routes /api/table-orders somewhere other than order-manager"
done

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
# 14 days idle, 30 days maximum. Rotation guards only the current refresh token, and a thief
# spending a stolen one keeps resetting the idle clock — so the MAXIMUM is what bounds an actively
# abused token, and without these this client inherits the realm's 90 days.
for pair in 'client.session.idle.timeout": "1209600' 'client.session.max.lifespan": "2592000'; do
  case "$mobile" in
    *"$pair"*) ok "mobile-app ${pair%%\"*}" ;;
    *) fail "mobile-app is missing $pair: it would inherit the realm's 30 d / 90 d" ;;
  esac
done
case "$mobile" in
  *'https://www.youdrop.shop'*) ok "mobile-app allows the public site's origin" ;;
  *) fail "mobile-app has no web origin for www: the site's receipt panel is refused by CORS" ;;
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
# refresh-rotation's first version signed in ONCE: it replayed the spent token and then checked
# that the rotated one still worked. It failed on dev, and it was right to — replaying a spent
# token is what makes Keycloak revoke the session, so the last assertion was killed by the one
# before it. This script has neither jq nor a Keycloak to re-run it against, so it pins the SHAPE
# that made the mistake possible: one session, and a success expected after the replay.
step=$(awk '/^step_refresh_rotation/ {on=1} on {print} on && /^}/ {exit}' scripts/rotate-secrets.sh)
signins=$(printf '%s\n' "$step" | grep -c 'sign_in "\$WORK/' || true)
[ "${signins:-0}" -ge 2 ] \
  && ok "refresh-rotation signs in twice, so its two proofs cannot share a session" \
  || fail "refresh-rotation signs in ${signins:-0} time(s): the replay proof and the chain proof need a session each"
after=$(printf '%s\n' "$step" | awk '/the token it replaced is refused/ {on = 1; next} on && /check .* 200 /' | wc -l | tr -d ' ')
[ "${after:-0}" = 0 ] \
  && ok "nothing expects a token to be accepted after the replay" \
  || fail "$after assertion(s) expect a 200 after the replay, which has already revoked the session"

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
  # cluster/ is applied with `kubectl apply -f`, not through an overlay, so nothing else here ever
  # parses it. A kustomization that lists the files is the cheapest way to make the same parser
  # read them — and these are the manifests whose failure mode is "monitoring did not come back".
  mkdir -p "$tmp/cluster"
  { echo 'apiVersion: kustomize.config.k8s.io/v1beta1'
    echo 'kind: Kustomization'
    echo 'resources:'
    for f in cluster/*.yaml; do
      # The Traefik HelmChartConfig's `valuesContent` is a Helm document, not Kubernetes objects,
      # and kustomize has no schema for the CRD; it parses as YAML, which is all that is claimed.
      case "$f" in *traefik-config.yaml) continue ;; esac
      cp "$f" "$tmp/cluster/"
      echo "  - ${f##*/}"
    done
  } > "$tmp/cluster/kustomization.yaml"
  if kubectl kustomize "$tmp/cluster" > "$tmp/cluster-render.yaml" 2>"$tmp/cluster.err"; then
    ok "cluster/ parses ($(grep -c '^kind:' "$tmp/cluster-render.yaml") objects)"
  else
    fail "cluster/ does not parse: $(head -n3 "$tmp/cluster.err" | tr '\n' ' ')"
  fi
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
  templates=$(grep -c '^ *priorityClassName:' "$tmp/render-$env.yaml" || true)
  workloads=$(grep -c '^kind: \(Deployment\|StatefulSet\|Job\|CronJob\)$' "$tmp/render-$env.yaml" || true)
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
  # Only while dev has a quota. It had one on 2026-09-20 and it deadlocked every rollout: a ceiling
  # sized for the steady state leaves no room for the second pod a rolling update makes. See the
  # note in overlays/dev/resource-safety.yaml. With no quota, there is no such fact to check.
  quota=$(awk '/^ *limits\.memory:/ { print $2; exit }' overlays/dev/resource-safety.yaml)
  # A ResourceQuota counts RUNNING PODS, so this models the same thing: every Deployment,
  # StatefulSet and Job contributes its pod, and a CronJob contributes its pod only if it is not
  # suspended (a suspended one never creates one). Within a pod, initContainers count alongside
  # containers because a native sidecar runs beside the main container rather than before it.
  used=$(awk '
    BEGIN { RS = "\n---\n" }
    {
      # The record ENDS just before the "\n---\n" separator, so the last line has no trailing
      # newline of its own — hence (\n|$) rather than \n on the suspend match.
      if ($0 ~ /(^|\n)kind: CronJob\n/ && $0 ~ /(^|\n)  suspend: true(\n|$)/) next
      n = split($0, lines, "\n")
      inlim = 0
      for (i = 1; i <= n; i++) {
        l = lines[i]
        if (l ~ /^ *limits: *$/) { inlim = 1; continue }
        if (!inlim) continue
        if (l ~ /^ *(cpu|ephemeral-storage): /) continue
        if (l ~ /^ *memory: /) {
          split(l, f, ":"); v = f[2]; gsub(/ /, "", v); m = v + 0
          if (v ~ /Mi$/) m *= 1048576; else if (v ~ /Gi$/) m *= 1073741824; else if (v ~ /Ki$/) m *= 1024
          total += m
        }
        inlim = 0
      }
    }
    END { printf "%d", total }
  ' "$tmp/render-dev.yaml")
  cap=$(printf '%s' "$quota" | awk '{ v = $0; n = v + 0; if (v ~ /Mi$/) n *= 1048576; else if (v ~ /Gi$/) n *= 1073741824; printf "%d", n }')
  if [ -z "$quota" ]; then
    ok "dev has no ResourceQuota; production is protected by priority instead"
  elif [ "$used" -le "$cap" ]; then
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

echo "== the safe value is the default (PD-1) =="
# `env_literal <env> <KEY>` — what an overlay's platform-env sets, or empty.
env_literal() { sed -n "s/^ *- \{0,4\}$2=//p" "overlays/$1/kustomization.yaml" | head -n1; }

# A dev switch on platform-common is a dev switch in EVERY environment, production included, by
# default and silently. These two are the ones that cost money or take an order: SIMULATE_WALLETS
# offers a customer a wallet payment that never happens, for an order the platform then treats as
# paid, and WHATSAPP_SIMULATOR_ENABLED replaces the Meta Cloud API with a loopback.
for key in SIMULATE_WALLETS WHATSAPP_SIMULATOR_ENABLED; do
  v=$(sed -n "s/^ *$key: *//p" base/configmap-common.yaml | tr -d '"')
  [ "$v" = false ] \
    && ok "platform-common defaults $key to false" \
    || fail "platform-common has $key=$v: every environment inherits it, production included"
done
# The mail sink was the quietest one of all: a code delivered successfully to a mailbox nobody
# reads, with no error anywhere. It is gone from the shared file, so an environment must name its
# own relay — and if it forgets, this is what says so rather than a customer.
for key in SMTP_HOST SMTP_PORT EMAIL_FROM; do
  grep -qE "^ *$key:" base/configmap-common.yaml \
    && fail "platform-common still carries $key: an environment that forgets mail config gets the sink" \
    || ok "platform-common carries no $key"
done
case "$(sed -n 's/^ *NOMINATIM_USER_AGENT: *//p' base/configmap-common.yaml)" in
  *-dev*) fail "platform-common's NOMINATIM_USER_AGENT still says -dev: that is what a live shop's geocoding would report" ;;
  "") fail "platform-common sets no NOMINATIM_USER_AGENT; Nominatim refuses a request without one" ;;
  *) ok "platform-common's Nominatim User-Agent is the honest one" ;;
esac

for env in dev qa; do
  # Every environment must say what it is: the demo-storefront gate refuses to guess, and the
  # production checks below have nothing to key on without it.
  tier=$(env_literal "$env" ENVIRONMENT_TIER)
  case "$tier" in
    development|test|production) ok "$env declares ENVIRONMENT_TIER=$tier" ;;
    "") fail "overlays/$env sets no ENVIRONMENT_TIER; the demo-storefront gate will refuse to run" ;;
    *) fail "overlays/$env has ENVIRONMENT_TIER=$tier (expected development, test or production)" ;;
  esac
  # Six values, all of which used to come free from platform-common's mailpit defaults.
  for key in SMTP_HOST SMTP_PORT SMTP_USER SMTP_AUTH SMTP_STARTTLS EMAIL_FROM; do
    [ -n "$(env_literal "$env" "$key")" ] \
      && ok "$env sets $key" \
      || fail "overlays/$env sets no $key, and platform-common no longer provides one"
  done

  # THE PRODUCTION GATE. Everything here is allowed in a test environment and forbidden in a real
  # one, and flipping ENVIRONMENT_TIER to production is what turns this from a list into a
  # checklist: the failing run names, one by one, what is still to be changed.
  [ "$tier" = production ] || continue
  echo "-- $env is PRODUCTION"
  # The test code sink keeps one-time codes in a table for the smoke tests to read. In production
  # it is a table of live verification codes for anyone who reaches the database.
  [ "$(env_literal "$env" TEST_CODE_SINK_ENABLED)" = true ] \
    && fail "$env is production and TEST_CODE_SINK_ENABLED=true: live one-time codes would be kept in notification.test_code_sink" \
    || ok "$env has no test code sink"
  for key in SIMULATE_WALLETS WHATSAPP_SIMULATOR_ENABLED; do
    [ "$(env_literal "$env" "$key")" = true ] \
      && fail "$env is production and $key=true" \
      || ok "$env has $key off"
  done
  for key in AUTO_APPROVE_RIDER AUTO_APPROVE_MERCHANT AUTO_APPROVE_CARRIER; do
    [ "$(env_literal "$env" "$key")" = true ] \
      && fail "$env is production and $key=true: applicants would be approved with nobody reading the documents" \
      || ok "$env approves $key by hand"
  done
  case "$(env_literal "$env" SMTP_HOST)" in
    mailpit|localhost|"") fail "$env is production and its mail goes to a sink" ;;
    *) ok "$env mails through a real relay" ;;
  esac
  case "$(env_literal "$env" EMAIL_FROM)" in
    *.local|*mydelivery*) fail "$env is production and EMAIL_FROM is a made-up domain: SPF and DKIM would both fail" ;;
    *) ok "$env sends from a real domain" ;;
  esac
  [ "$(env_literal "$env" TRACKING_SERVICE_AREA_ENABLED)" = false ] \
    && fail "$env is production with the rider service area off: a spoofed position from anywhere would be accepted" \
    || ok "$env keeps the rider service area"
done

# The demo storefront: eight shops seeded into every fresh database by V12, which a migration
# cannot gate.
grep -q "demo-merchant" base/assets/demo-data/purge-demo-storefront.sh \
  && ok "the demo storefront gate knows what to remove" \
  || fail "base/assets/demo-data/purge-demo-storefront.sh does not identify the demo merchant"
grep -q 'argocd.argoproj.io/hook: PostSync' base/demo-storefront-gate.yaml \
  && ok "it runs after every sync, not once" \
  || fail "the demo-storefront gate is not a PostSync hook, so it would run once and never again"
grep -q 'ENVIRONMENT_TIER' base/demo-storefront-gate.yaml \
  && ok "it is gated on the environment's tier" \
  || fail "the demo-storefront gate is not gated: it would delete dev's demo shops too"

echo "== backups (BK-1) =="
for cj in postgres-backup minio-backup restore-test; do
  grep -q "^  name: $cj$" base/backup.yaml \
    && ok "CronJob $cj" \
    || fail "base/backup.yaml has no $cj CronJob"
done
# Suspended in base, so a namespace created later starts safe instead of starting to upload.
[ "$(grep -c '^  suspend: true$' base/backup.yaml)" = 3 ] \
  && ok "all three ship suspended in base" \
  || fail "base/backup.yaml must ship every backup CronJob suspended: an overlay opts in"
if [ -s "$tmp/render-dev.yaml" ] && [ -s "$tmp/render-qa.yaml" ]; then
  [ "$(grep -c '^  suspend: true$' "$tmp/render-dev.yaml")" = 3 ] \
    && ok "dev keeps them suspended (its quota has no room for a backup pod)" \
    || fail "dev un-suspends a backup CronJob: the pod would be refused by dev's ResourceQuota"
  [ "$(grep -c '^  suspend: false$' "$tmp/render-qa.yaml")" = 3 ] \
    && ok "qa runs all three" \
    || fail "qa does not un-suspend the backup CronJobs, so nothing is backed up"
fi
# Every Secret these Jobs read must be optional, or the pod cannot START before the owner has
# created it — which is a CreateContainerConfigError, not a message anybody can act on.
for s in backup-rclone backup-age backup-deadman; do
  n=$(grep -c "secretName: $s" base/backup.yaml || true)
  opt=$(grep -A1 "secretName: $s" base/backup.yaml | grep -c 'optional: true' || true)
  [ "$n" -gt 0 ] && [ "$n" = "$opt" ] \
    && ok "$s is mounted optional in all $n place(s)" \
    || fail "$s is mounted non-optionally: the backup pod would not start until it exists"
done
# ...and the scripts must then say what is missing and SUCCEED, rather than crash-looping.
for f in base/assets/backup/postgres-backup.sh base/assets/backup/minio-backup.sh; do
  grep -q 'NOT CONFIGURED' "$f" && grep -q '^  exit 0$' "$f" \
    && ok "${f##*/} exits 0 when the destination is not configured" \
    || fail "${f##*/} does not exit 0 when unconfigured: the CronJob would crash-loop"
done
# pg_dump refuses to dump a server NEWER than itself, so the backup image's major version must
# never fall behind Postgres's. This is the check that catches a Postgres upgrade done alone.
server_major=$(sed -n 's|.*image: postgis/postgis:\([0-9]*\)-.*|\1|p' base/data-layer.yaml | head -n1)
dump_major=$(sed -n 's|.*image: postgres:\([0-9]*\)-alpine@.*|\1|p' base/backup.yaml | head -n1)
[ -n "$server_major" ] && [ "$server_major" = "$dump_major" ] \
  && ok "the backup image is Postgres $dump_major, the same major as the server" \
  || fail "Postgres is $server_major and the backup image is $dump_major: pg_dump refuses a newer server"
# A backup nobody can restore is not a backup, so the way back ships with the way out.
[ -s scripts/restore.sh ] && grep -q 'into-live' scripts/restore.sh \
  && ok "scripts/restore.sh exists and can restore into a live environment" \
  || fail "there is no scripts/restore.sh"
grep -q 'Backups' README.md && grep -q 'lifecycle' README.md \
  && ok "README documents the backups and their retention" \
  || fail "README.md does not document the backups"
# Nothing on this branch may print a secret. These scripts read passwords from the environment and
# keys from mounted files; an echo of either is the bug this catches.
leak=$(grep -n 'echo.*\$\(PGPASSWORD\|MINIO_ROOT_PASSWORD\|AGE\)' base/assets/backup/*.sh scripts/restore.sh | tr '\n' ' ')
[ -z "$leak" ] \
  && ok "no backup script echoes a credential" \
  || fail "a backup script prints a credential: $leak"

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

echo "== alerting: it reaches somebody (AL-1) =="
mon=cluster/monitoring.yaml
alert=cluster/alerting.yaml
# A Prometheus with rules and no Alertmanager behind it is what both environments ran for their
# whole lives: every rule evaluated, every alert marked firing, nobody told.
grep -q '^    alerting:' "$mon" && grep -q 'targets: \["alertmanager:9093"\]' "$mon" \
  && ok "Prometheus sends firing alerts to Alertmanager" \
  || fail "cluster/monitoring.yaml has no alerting: block, so nothing leaves Prometheus"
for want in alertmanager node-exporter kube-state-metrics; do
  grep -q "name: $want$" "$alert" \
    && ok "$want is deployed" \
    || fail "cluster/alerting.yaml does not deploy $want"
done
grep -q 'smtp_auth_password_file' "$alert" \
  && ok "the relay password is read from a file, not written in the ConfigMap" \
  || fail "Alertmanager's SMTP password is not a _file reference: it would be in the ConfigMap"
grep -q 'smtp_password\|smtp_auth_password:' "$alert" \
  && fail "cluster/alerting.yaml contains a literal SMTP password" \
  || ok "no literal SMTP password in cluster/alerting.yaml"
grep -q 'alertmanager-smtp' scripts/setup-monitoring.sh \
  && ok "setup-monitoring.sh copies the relay password into monitoring" \
  || fail "nothing creates alertmanager-smtp, so every alert email fails to send"
grep -q 'cluster/alerting.yaml' scripts/setup-monitoring.sh \
  && ok "setup-monitoring.sh applies cluster/alerting.yaml" \
  || fail "setup-monitoring.sh never applies cluster/alerting.yaml"
# Telegram must be OFF by being absent. Alertmanager validates its whole configuration at startup
# and refuses to start on a half-filled receiver — which would take monitoring down entirely.
awk '/telegram_configs:/ && $0 !~ /^ *#/ { found = 1 } END { exit !found }' "$alert" \
  && fail "an active telegram receiver is configured; a placeholder chat_id stops Alertmanager starting" \
  || ok "Telegram is off (the receiver is commented, with instructions)"
# kube-state-metrics must not be able to read Secrets: `list` on secrets returns their values.
awk 'BEGIN{RS="\n---\n"} /(^|\n)kind: ClusterRole\n/ && /kube-state-metrics/ {print}' "$alert" \
  | sed 's/#.*//' | grep -q 'secrets' \
  && fail "the kube-state-metrics ClusterRole grants access to secrets, which returns their values" \
  || ok "kube-state-metrics cannot read Secrets"
grep -q 'metrics.prometheus=true' cluster/traefik-config.yaml \
  && ok "Traefik exports its metrics (5xx, 429 and certificate expiry)" \
  || fail "Traefik metrics are off: nothing can see the 5xx rate, the 429 rate or a certificate about to expire"
sed 's/#.*//' cluster/traefik-config.yaml | grep -q 'entrypoints\.metrics\.address' \
  && fail "a new Traefik entrypoint is defined for metrics: a name collision with the chart's own takes the whole edge down" \
  || ok "Traefik metrics reuse the chart's existing entrypoint"
grep -q 'postgres-exporter' base/data-layer.yaml \
  && ok "the Postgres connection count has an exporter behind it" \
  || fail "nothing exports pg_stat_activity_count, so the connection alert can never fire"

# Every rule the production plan asks for, by name.
for a in NodeDiskFilling NodeMemoryCritical PodCrashLooping JobFailed BackupDidNotReport \
         CertificateExpiringSoon HighServerErrorRate PostgresConnectionsHigh \
         RateLimitRejectionsHigh SmsRateHigh SettlementFailuresRecorded RestoreTestFailing; do
  grep -q "alert: $a$" "$mon" \
    && ok "rule $a" \
    || fail "no alert rule called $a"
done
# ...and each one has an expression. An alert with no expr is not a rule, it is a comment.
noexpr=$(awk '
  /^ *- alert: / { name = $3; seen = 0 }
  /^ *expr: / { if (name != "") seen = 1 }
  /^ *- alert: / && prev != "" && !prevseen { print prev }
  { if ($0 ~ /^ *- alert: /) { prev = name; prevseen = 0 } else if ($0 ~ /^ *expr: /) prevseen = 1 }
  END { if (prev != "" && !prevseen) print prev }
' "$mon" | tr '\n' ' ')
[ -z "$noexpr" ] \
  && ok "every alert rule has an expression" \
  || fail "alert rule(s) with no expr: $noexpr"

# A rule whose metric nothing produces never fires, and looks exactly like a rule that is fine.
# Every custom metric an expression names is resolved back to whatever emits it.
#
# PENDING is the honest half: these two need a service change this branch does not own (see the
# report). They are listed here so the gap is visible and so removing a name from this line is the
# entire edit once the metric exists.
PENDING_METRICS="delivery_sms_sent_total delivery_settlement_failures"
for m in $(grep -o 'delivery_[a-z_]*\|youdrop_[a-z_]*' "$mon" | sort -u); do
  case " $PENDING_METRICS " in
    *" $m "*)
      ok "$m is PENDING a service change (the rule is written and waiting)"
      continue ;;
  esac
  # Micrometer names its meters with dots and Prometheus exports them with underscores, and which
  # separator sits where is not recoverable from the exported name — so each `_` is allowed to be
  # either. `_total` is the suffix Prometheus adds to a counter. Main sources only: a test that
  # asserts on the scraped name is not something that produces the metric.
  pat=$(printf '%s' "$m" | sed 's/_total$//; s/_/[._]/g')
  if grep -rEq "\"$pat\"" --include='*.java' ../../platform/*/src/main ../../services/*/src/main 2>/dev/null; then
    ok "$m is registered by a service"
  elif grep -q "$m" base/assets/backup/*.sh; then
    ok "$m is written by a backup job (node-exporter textfile)"
  else
    fail "the rules use $m and nothing in this repository produces it: that alert can never fire"
  fi
done

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
# Every service account that presents its own token to ANOTHER PLATFORM SERVICE has to be on the
# azp allow-list, or AuthorizedPartyValidator refuses it: 401, empty body, one WARN line in the
# service that refused. Nothing else in this repository connects the two facts, and the two are
# five files apart — the Deployment that reads a client secret, and the config rows.
#
# So: a Deployment reading keycloak-clients/<X>_CLIENT_SECRET is a service account; if it calls a
# platform service it must be on the list. accounting-service and notifications-manager call
# Keycloak's admin API instead and are deliberately absent, which is why this is a named list
# rather than a derivation — the two SQL copies must simply agree with it, and with each other.
allowlist_callers="onboarding-service order-manager"
for sql in ../../infra/postgres/init/03-config-properties.sql base/assets/postgres-init/03-config-properties.sql; do
  [ -f "$sql" ] || { fail "$sql is missing: the azp allow-list has nowhere to come from"; continue; }
  for c in $allowlist_callers; do
    grep -q "delivery.security.allowed-client-ids\[[0-9]\+\]', '$c'" "$sql" \
      && ok "$c is on the azp allow-list in $(basename "$(dirname "$(dirname "$sql")")")/$(basename "$sql")" \
      || fail "$c presents a service-account token to a platform service but is NOT on delivery.security.allowed-client-ids in $sql: every call it makes would be answered 401 with an empty body"
  done
  # Relaxed binding stops at the first gap, so [0],[1],[3] binds two entries and drops the third
  # without a word. Checked rather than trusted: the rows are edited by hand.
  idx=$(grep -o "allowed-client-ids\[[0-9]\+\]" "$sql" | grep -o '[0-9]\+' | sort -n | tr '\n' ' ')
  expected=$(i=0; for _ in $idx; do printf '%s ' "$i"; i=$((i + 1)); done)
  [ "$idx" = "$expected" ] \
    && ok "the allow-list indices run 0..n with no gap in $(basename "$sql")" \
    || fail "delivery.security.allowed-client-ids in $sql is indexed '$idx', not '$expected': Spring binds up to the first gap and silently drops the rest"
done
# One list, two copies, and only the k3s one is applied by the cluster. A row added to one and not
# the other is a difference between what docker compose runs and what the cluster runs.
diff -q ../../infra/postgres/init/03-config-properties.sql base/assets/postgres-init/03-config-properties.sql >/dev/null 2>&1 \
  && ok "both copies of 03-config-properties.sql are identical" \
  || fail "infra/postgres/init/03-config-properties.sql and base/assets/postgres-init/03-config-properties.sql have drifted"
for secret in $( { grep -h -o 'secretKeyRef: { name: [a-z0-9-]*' base/*.yaml | awk '{print $4}'
                   grep -h -A1 'secretKeyRef:$' base/*.yaml | grep -o 'name: [a-z0-9-]*' | awk '{print $2}'
                   grep -h -o 'secret: [a-z0-9-]*' overlays/ingress.template.yaml | awk '{print $2}'; } | sort -u); do
  [ "$secret" = anthropic-api ] && continue   # optional, created by hand (README.md)
  [ "$secret" = demand-seen ] && continue   # optional, minted by rotate-secrets.sh <ns> demand-seen
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
