#!/bin/sh
# Offline test of e2e-smoke.sh's sign-in: the demo passwords come from the demo-logins Secret,
# reach Keycloak on curl's STDIN, and never appear in any command line or in the output.
#   sh deploy/k3s/scripts/test/e2e-smoke.test.sh
# A fake kubectl serves a Secret of throwaway values; a fake curl accepts a sign-in only when the
# right password arrives on stdin, and logs every argv it is given.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SMOKE="$HERE/../e2e-smoke.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "  ok  $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

mkdir "$T/bin" "$T/pw"
for u in customer rider merchant backoffice carrier; do
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' | head -c 16 > "$T/pw/$u"
done
{
  echo '{'; echo '    "apiVersion": "v1",'; echo '    "data": {'
  for u in backoffice carrier customer merchant rider; do
    printf '        "%s": "%s",\n' "$u" "$(base64 < "$T/pw/$u" | tr -d '\n')"
  done
  echo '        "zz": ""'; echo '    },'; echo '    "kind": "Secret",'
  echo '    "metadata": { "name": "demo-logins", "namespace": "delivery-test" }'; echo '}'
} > "$T/secret.json"

cat > "$T/bin/kubectl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/argv.log"
case "\$*" in *"get secret demo-logins -o json"*) cat "$T/secret.json" ;; *) exit 1 ;; esac
EOF
cat > "$T/bin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/argv.log"
out=""; fmt=""; user=""; url=""; stdin_pw=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out=\$2; shift ;;
    -w) fmt=\$2; shift ;;
    -d) case "\$2" in username=*) user=\${2#username=} ;; esac; shift ;;
    --data-urlencode) case "\$2" in password@-) stdin_pw=\$(cat) ;; esac; shift ;;
    -X|-H) shift ;;
    http*) url=\$1 ;;
  esac
  shift
done
case "\$url" in
  */protocol/openid-connect/token)
    if [ -n "\$user" ] && [ -f "$T/pw/\$user" ] && [ "\$stdin_pw" = "\$(cat "$T/pw/\$user")" ]; then
      body='{"access_token":"token-for-'\$user'"}'; code=200
    else body='{"error":"invalid_grant"}'; code=401; fi ;;
  *) body='{"id":"00000000-0000-0000-0000-000000000000"}'; code=200 ;;
esac
if [ -n "\$out" ]; then printf '%s' "\$body" > "\$out"; else printf '%s' "\$body"; fi
[ -n "\$fmt" ] && printf '%s' "\$code"
exit 0
EOF
chmod +x "$T/bin/kubectl" "$T/bin/curl"

PATH="$T/bin:$PATH" sh "$SMOKE" test > "$T/out" 2>&1

for u in customer rider merchant carrier; do
  grep -q "ok   $u signs in" "$T/out" && ok "$u signs in with the Secret's password" || fail "$u did not sign in"
done
grep -q "ok   backoffice signs in on the portal client" "$T/out" && grep -q "ok   backoffice signs in$" "$T/out" \
  && ok "backoffice signs in on both clients" || fail "backoffice sign-in"
grep -q "get secret demo-logins -o json" "$T/argv.log" && [ "$(grep -c 'kubectl\|get secret' "$T/argv.log")" -ge 1 ] \
  && [ "$(grep -c 'get secret demo-logins' "$T/argv.log")" = 1 ] && ok "the Secret is read exactly once" \
  || fail "the Secret was read $(grep -c 'get secret demo-logins' "$T/argv.log") times"
leaked=0
for u in customer rider merchant backoffice carrier; do
  v=$(cat "$T/pw/$u")
  grep -qF -- "$v" "$T/argv.log" && leaked=$((leaked + 1))
  grep -qF -- "$v" "$T/out" && leaked=$((leaked + 1))
done
[ "$leaked" = 0 ] && ok "no password in any argv or in the output" || fail "$leaked password appearance(s) in argv or output"

echo "== without the Secret it stops before signing anybody in =="
cat > "$T/bin/kubectl" <<'EOF'
#!/bin/sh
echo 'Error from server (NotFound): secrets "demo-logins" not found' >&2; exit 1
EOF
chmod +x "$T/bin/kubectl"
: > "$T/argv.log"
PATH="$T/bin:$PATH" sh "$SMOKE" test > "$T/out" 2>&1
st=$?
[ "$st" = 2 ] && ok "exits 2" || fail "exit status $st"
grep -q "cannot read the demo-logins Secret" "$T/out" && ok "says why" || fail "no explanation"
grep -q "openid-connect/token" "$T/argv.log" && fail "tried to sign in anyway" || ok "no sign-in attempted"

echo
[ "$fails" = 0 ] && echo "e2e-smoke: all checks passed" || { echo "e2e-smoke: $fails check(s) failed"; exit 1; }
