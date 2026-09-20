#!/bin/sh
# PT-1 (portal deep test, 2026-09-19): the two sites people open in a browser carry no security
# headers at all, while the API does.
#   sh deploy/k3s/scripts/test/public-site-headers.test.sh
#
# Measured on 2026-09-19 with plain GETs: api-dev answers with HSTS, X-Frame-Options DENY, nosniff
# and no-referrer; portal-dev.youdrop.shop and www.youdrop.shop answer with none of them - no CSP, no
# frame protection, no HSTS, no nosniff, no Referrer-Policy. The portal is the back office: without
# frame-ancestors / X-Frame-Options any page can frame it (clickjacking of Approve, Suspend, Remit),
# and without a CSP nothing limits what an injected script could do with the refresh token the web
# build keeps in localStorage.
#
# Offline: reads the files the deployment is built from. A header counts if either the site's nginx
# config sets it (add_header ... always) or the site's Traefik route uses a middleware that sets it.
# Fails until both sites send every header below.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
K3S="$HERE/../.."
ROOT="$K3S/../.."
fails=0
ok()   { echo "  ok  $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

INGRESS="$K3S/overlays/ingress.template.yaml"
WEBSITE_ROUTE="$K3S/cluster/website.yaml"
PORTAL_NGINX="$K3S/base/assets/portal-nginx.conf"
WEBSITE_NGINX="$ROOT/clients/website/nginx.conf"

# The IngressRoute document named $2 in file $1.
route() { awk -v name="$2" 'BEGIN{RS="\n---"} $0 ~ "kind: IngressRoute" && $0 ~ "name: " name "\n" {print}' "$1"; }
# The Middleware document named $2 in file $1.
middleware() { awk -v name="$2" 'BEGIN{RS="\n---"} $0 ~ "kind: Middleware" && $0 ~ "name: " name "\n" {print}' "$1"; }

# add_header lines at server level only. One inside a location covers that location alone (the
# website's nosniff is on /app and nowhere else), and nginx does not inherit server-level add_header
# into a location that sets any of its own - so a fix has to repeat them there, or use Traefik.
server_headers() {
  awk '{
    line = $0; sub(/#.*/, "", line)
    if (depth == 1 && line ~ /add_header/) print line
    n = gsub(/\{/, "{", line); m = gsub(/\}/, "}", line); depth += n - m
  }' "$1" 2>/dev/null
}

# What the site sends, as one blob: its nginx config plus every middleware its route names.
headers_of() { # headers_of <route-file> <route-name> <nginx-conf>
  server_headers "$3"
  for m in $(route "$1" "$2" | sed -n 's/.*{ *name: *\([a-z0-9-]*\) *}.*/\1/p'); do
    middleware "$1" "$m"
    middleware "$INGRESS" "$m"
  done
}

check() { # check <site> <blob-file>
  b="$2"
  grep -qiE 'frameDeny: *true|customFrameOptionsValue|X-Frame-Options|frame-ancestors' "$b" \
    && ok "$1: framing is refused" || fail "$1: nothing stops another site from framing it"
  grep -qiE 'contentTypeNosniff: *true|X-Content-Type-Options' "$b" \
    && ok "$1: nosniff" || fail "$1: no X-Content-Type-Options: nosniff"
  grep -qiE 'referrerPolicy|Referrer-Policy' "$b" \
    && ok "$1: a referrer policy" || fail "$1: no Referrer-Policy"
  grep -qiE 'stsSeconds|Strict-Transport-Security' "$b" \
    && ok "$1: HSTS" || fail "$1: no Strict-Transport-Security"
  grep -qiE 'contentSecurityPolicy|Content-Security-Policy' "$b" \
    && ok "$1: a content security policy" || fail "$1: no Content-Security-Policy"
}

T=$(mktemp)
trap 'rm -f "$T"' EXIT

echo "== the portal (back office, merchant and carrier consoles) =="
headers_of "$INGRESS" portal "$PORTAL_NGINX" > "$T"
check portal "$T"

echo "== the public website (landing, /register, /app) =="
headers_of "$WEBSITE_ROUTE" website "$WEBSITE_NGINX" > "$T"
check www "$T"

echo "== the API, for comparison: it already has most of them =="
middleware "$INGRESS" security-headers > "$T"
grep -q 'frameDeny: true' "$T" && ok "api: security-headers middleware refuses framing" \
  || fail "api: the security-headers middleware lost frameDeny"

echo
[ "$fails" -eq 0 ] && echo "all ok" || echo "$fails failing"
[ "$fails" -eq 0 ]
