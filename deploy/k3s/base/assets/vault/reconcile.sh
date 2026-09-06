#!/bin/sh
# Reconcile loop for the dev-mode vault pod's vault-reseed sidecar.
#
# Vault runs -dev (in-memory), so its contents are a projection of platform-secrets (which lives in
# the k3s datastore and survives a reboot) plus the dev literals in bootstrap.sh. This loop makes
# seeding happen on EVERY start instead of once - the flaw that took the platform down on the
# 2026-09-05 node reboot was that vault-init is a one-shot Job: a Job is immutable, its pod had
# already Completed, and a node reboot is not an Argo sync, so nothing ever re-ran the seed and
# every Spring service crash-looped against an empty Vault. Moving the seed into a perpetual in-pod
# loop is the fix: it also re-heals if the vault container restarts underneath this sidecar.
#
# No PVC, no operator init, no unseal: dev mode auto-unseals and the root token is pinned to
# platform-secrets/VAULT_ROOT_TOKEN, so VAULT_TOKEN is valid on every boot.
#
# Intentionally NOT `set -e`: a transient failure (vault mid-restart) must retry, not kill the loop.
# NEVER print secret VALUES here - SMTP_PASSWORD is a real mailbox password. Log status text only;
# bootstrap.sh itself only ever lists secret PATHS.
set -u
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
INTERVAL="${RESEED_INTERVAL:-15}"

# Fully-seeded sentinel: Vault reachable AND the config-server AppRole role exists AND the
# completion marker (the LAST thing bootstrap.sh writes) is present. Gating on the marker - not on
# secret/application, which bootstrap writes FIRST - means a bootstrap that died partway is treated
# as not-seeded and re-runs to completion, while a fully-seeded healthy pod does zero rewrites on
# later ticks (which also closes the bootstrap "" erase hazard on healthy boots).
seeded() {
  vault status                                >/dev/null 2>&1 || return 1
  vault read auth/approle/role/config-server  >/dev/null 2>&1 || return 1
  vault kv get secret/_seed_complete          >/dev/null 2>&1 || return 1
  return 0
}

echo "==> vault-reseed reconcile loop started (interval ${INTERVAL}s)"
while true; do
  if ! seeded; then
    echo "==> vault not fully seeded - running bootstrap.sh"
    # bootstrap.sh is idempotent and pulls every value from this container's env (platform-secrets),
    # so re-running is safe. It is `set -eu` and exits non-zero on a transient error; tolerate it so
    # the loop retries rather than dying.
    /bin/sh /bootstrap/bootstrap.sh || echo "    bootstrap attempt failed; retry in ${INTERVAL}s"
  fi
  sleep "$INTERVAL"
done
