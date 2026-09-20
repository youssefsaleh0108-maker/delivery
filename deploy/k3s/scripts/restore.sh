#!/bin/bash
# Bring a database or an object store back from an off-box backup. Run ON THE SERVER, as root:
#
#   bash restore.sh <namespace> <step> [args]
#
#   list [<n>]              what is in the destination: the newest n hourly archives (default 10),
#                           plus the newest daily and monthly, with sizes and ages
#   fetch <archive|latest>  download ONE archive to /root/restore-<ns>-<time>/ and stop there.
#                           Does not decrypt: the private key is yours and this script never asks
#                           for it on a command line.
#   open <dir>              decrypt and unpack an archive already fetched into <dir>. Prompts for
#                           the age identity FILE (its path, not its contents) and prints the
#                           manifest — what was dumped, from which server, with which row counts.
#   dry-run <dir>           restore <dir>'s dumps into a THROWAWAY database in the running Postgres
#                           (delivery_restore_<time>), report Flyway versions and row counts, and
#                           drop it again. Changes nothing anybody is using. DO THIS FIRST.
#   into-live <dir>         replace the LIVE delivery and keycloak databases with <dir>'s dumps.
#                           Refuses unless the environment is scaled to zero and you type the
#                           namespace back. This is the irreversible one.
#   minio <prefix>          copy objects back from the destination into this environment's MinIO.
#                           <prefix> is a bucket name, or `all`.
#
# WHAT ONLY YOU CAN PROVIDE
#   * the age PRIVATE key, as a file on this box, readable only by root. It is the other half of
#     backup-age/recipient and it is deliberately not in the cluster. Without it NOTHING in an
#     archive can be read, by you or by anyone else. If it is lost, every backup ever taken is
#     lost with it — keep two copies, offline, in different places.
#   * the destination's credentials, which are already in the `backup-rclone` Secret if backups are
#     running; this script reads them from there so there is nothing to retype.
#
# WHAT THIS SCRIPT WILL NOT DO
#   * print a password, a key or an archive's contents
#   * restore over a live database without the environment being stopped first
#   * decide that data loss is acceptable. `into-live` replays a snapshot: everything written after
#     the backup was taken is gone. Flyway only moves forward, so a restore of an OLDER schema
#     under NEWER service images starts services that then fail their migration check. Restore only
#     when the data is genuinely corrupt; otherwise fix forward.
set -uo pipefail

NS="${1:?usage: restore.sh <namespace> <step> [args]}"
STEP="${2:?usage: restore.sh <namespace> <step> [args]}"
shift 2

umask 077
WORK=$(mktemp -d "${SHM_DIR:-/dev/shm}/restore.XXXXXX") || { echo "no private directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM

k() { kubectl -n "$NS" "$@"; }
die() { echo "STOP: $*" >&2; exit 1; }
ok() { echo "  ok    $*"; }
say() { echo "== $*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed on this box (apk/apt install $1)"; }

# The destination's configuration comes out of the Secret the CronJobs use, into a private file in
# RAM. It is never printed and never passed on a command line.
rclone_ready() {
  need rclone
  k get secret backup-rclone >/dev/null 2>&1 || die "no backup-rclone Secret in $NS: backups are not configured (see README)"
  k get secret backup-rclone -o jsonpath='{.data.rclone\.conf}' | base64 -d > "$WORK/rclone.conf"
  DEST=$(k get secret backup-rclone -o jsonpath='{.data.dest}' | base64 -d)
  [ -s "$WORK/rclone.conf" ] && [ -n "$DEST" ] || die "backup-rclone is missing rclone.conf or dest"
  export RCLONE_CONFIG="$WORK/rclone.conf"
  PG_PREFIX="$DEST/$NS/postgres"
  MINIO_PREFIX="$DEST/$NS/minio"
}

step_list() {
  rclone_ready
  local n="${1:-10}"
  say "$PG_PREFIX"
  for tier in hourly daily monthly; do
    echo "-- $tier"
    rclone lsl "$PG_PREFIX/$tier/" 2>/dev/null | sort -k4 | tail -n "$n" \
      | awk '{ printf "  %12s bytes  %s %s  %s\n", $1, $2, $3, $4 }'
  done
  echo "-- objects"
  rclone size "$MINIO_PREFIX" 2>/dev/null
}

step_fetch() {
  rclone_ready
  local which="${1:?usage: fetch <archive-name|latest>}" dir name
  if [ "$which" = latest ]; then
    name=$(rclone lsf "$PG_PREFIX/hourly/" | sort | tail -n1)
    [ -n "$name" ] || die "there is nothing under $PG_PREFIX/hourly/"
  else
    name="$which"
  fi
  dir="/root/restore-$NS-$(date +%Y%m%d-%H%M%S)"
  mkdir -m 700 "$dir" || die "cannot create $dir"
  # Try each tier: a name from `list` may have come from any of them.
  for tier in hourly daily monthly; do
    if rclone copyto "$PG_PREFIX/$tier/$name" "$dir/$name" 2>/dev/null; then
      ok "$tier/$name -> $dir/$name ($(wc -c < "$dir/$name" | tr -d ' ') bytes)"
      echo
      echo "Next: bash restore.sh $NS open $dir"
      return 0
    fi
  done
  rmdir "$dir"
  die "no archive called $name under $PG_PREFIX/{hourly,daily,monthly}"
}

step_open() {
  need age
  local dir="${1:?usage: open <dir>}" archive key
  archive=$(ls "$dir"/*.tar.age 2>/dev/null | head -n1)
  [ -n "$archive" ] || die "no *.tar.age in $dir — run fetch first"
  echo "The age identity is a FILE on this box. Type its path (nothing is echoed back from it)."
  read -r -p "path to the age private key: " key
  [ -s "$key" ] || die "$key is empty or does not exist"
  age -d -i "$key" "$archive" > "$dir/bundle.tar" || die "that identity did not decrypt $archive"
  tar xf "$dir/bundle.tar" -C "$dir" || die "the decrypted archive is not a tar"
  rm -f "$dir/bundle.tar"
  ok "unpacked into $dir"
  echo
  say "manifest"
  cat "$dir/manifest.txt"
  echo
  say "the files are readable only by root, and they are the database in the clear"
  ls -l "$dir"
  echo
  echo "Next, and DO THIS FIRST: bash restore.sh $NS dry-run $dir"
}

# psql against the environment's own Postgres, as its superuser. The password goes in through the
# pod's environment, never argv.
psq() { k exec -i postgres-0 -- psql -U delivery -d "$1" -At -c "$2"; }
psq_admin() { k exec -i postgres-0 -- psql -U delivery -d postgres -At -c "$1"; }

step_dry_run() {
  local dir="${1:?usage: dry-run <dir>}" scratch fails=0
  [ -s "$dir/delivery.dump" ] || die "no delivery.dump in $dir — run open first"
  scratch="delivery_restore_$(date +%Y%m%d%H%M%S)"
  say "restoring into $scratch, beside the live database, changing nothing"
  psq_admin "create database $scratch" >/dev/null || die "could not create $scratch"
  # The dump goes in over stdin, so nothing is copied onto the node's disk.
  k exec -i postgres-0 -- pg_restore -U delivery -d "$scratch" --no-owner --no-privileges \
    < "$dir/delivery.dump" > "$WORK/restore.log" 2>&1
  echo "  pg_restore errors: $(grep -c '^pg_restore: error' "$WORK/restore.log")"

  say "Flyway versions: restored against live"
  for schema in $(psq delivery "select table_schema from information_schema.tables where table_name = 'flyway_schema_history' order by 1"); do
    local live back
    live=$(psq delivery "select coalesce(max(version), 'none') from $schema.flyway_schema_history where success")
    back=$(psq "$scratch" "select coalesce(max(version), 'none') from $schema.flyway_schema_history where success" 2>/dev/null || echo unreadable)
    if [ "$live" = "$back" ]; then ok "$schema V$back"
    else echo "  DIFFERS  $schema: live V$live, backup V$back"; fails=$((fails + 1)); fi
  done

  say "row counts: restored against live"
  for t in stores products orders; do
    local live back
    live=$(psq delivery "select count(*) from $t" 2>/dev/null || echo -)
    back=$(psq "$scratch" "select count(*) from $t" 2>/dev/null || echo -)
    echo "  $t: backup $back, live $live"
  done

  say "dropping $scratch"
  psq_admin "drop database $scratch" >/dev/null
  echo
  if [ "$fails" = 0 ]; then
    echo "The backup restores and is at the same schema version as live."
    echo "If you still want to REPLACE live with it: bash restore.sh $NS into-live $dir"
  else
    echo "$fails schema(s) differ. Read the table above before going any further: restoring an"
    echo "OLDER schema under the CURRENT service images starts services that fail their migration"
    echo "check, and Flyway does not migrate backwards."
  fi
}

step_into_live() {
  local dir="${1:?usage: into-live <dir>}" typed running
  [ -s "$dir/delivery.dump" ] || die "no delivery.dump in $dir — run open first"

  # Nothing may be holding a connection or writing while the database underneath it is replaced.
  running=$(k get deploy -o json | jq -r '.items[] | select((.spec.replicas // 0) > 0) | .metadata.name' | tr '\n' ' ')
  if [ -n "$running" ]; then
    die "these are still running and would write to the database mid-restore: $running
Stop them first:  kubectl -n $NS scale deploy --all --replicas=0
Then run this again, and afterwards:  kubectl -n $NS scale deploy --all --replicas=1"
  fi

  echo
  echo "This REPLACES the live delivery and keycloak databases in $NS with the contents of $dir."
  echo "Everything written since that backup was taken is lost, and there is no undo."
  echo "Take a dump of what is there now first if you have not:"
  echo "  kubectl -n $NS exec postgres-0 -- pg_dump -Fc -U delivery -d delivery > /root/pre-restore.dump"
  echo
  read -r -p "Type the namespace to confirm: " typed
  [ "$typed" = "$NS" ] || die "you typed '$typed'; nothing was changed"

  for db in delivery keycloak; do
    [ -s "$dir/$db.dump" ] || { echo "  (no $db.dump in $dir; skipped)"; continue; }
    say "$db"
    psq_admin "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$db' and pid <> pg_backend_pid()" >/dev/null
    psq_admin "drop database if exists ${db}_before_restore" >/dev/null
    # Renamed rather than dropped: if the restore is wrong, the old database is still here.
    psq_admin "alter database $db rename to ${db}_before_restore" >/dev/null \
      || die "could not rename $db out of the way; nothing has been replaced"
    psq_admin "create database $db" >/dev/null || die "could not create a fresh $db (the old one is ${db}_before_restore)"
    k exec -i postgres-0 -- pg_restore -U delivery -d "$db" --no-owner --no-privileges \
      < "$dir/$db.dump" > "$WORK/restore-$db.log" 2>&1
    ok "$db restored, $(grep -c '^pg_restore: error' "$WORK/restore-$db.log") pg_restore error(s)"
    ok "the database that was there is kept as ${db}_before_restore"
  done

  # Roles live outside every database, so a restore that skips them rebuilds the schemas and then
  # refuses every service's login.
  if [ -s "$dir/globals.sql" ]; then
    say "roles"
    k exec -i postgres-0 -- psql -U delivery -d postgres -q < "$dir/globals.sql" > "$WORK/globals.log" 2>&1
    ok "$(grep -c '^CREATE ROLE' "$dir/globals.sql") role(s) in the dump applied (existing ones are left as they are)"
  fi

  echo
  echo "Now bring the environment back:"
  echo "  kubectl -n $NS scale deploy --all --replicas=1"
  echo "  kubectl -n $NS rollout status deploy --timeout=600s"
  echo "  bash scripts/rotate-secrets.sh $NS verify"
  echo
  echo "Once you are satisfied, remove the databases this replaced:"
  echo "  kubectl -n $NS exec postgres-0 -- psql -U delivery -d postgres -c 'drop database delivery_before_restore'"
}

step_minio() {
  rclone_ready
  local what="${1:?usage: minio <bucket|all>}" src dst answer
  k get pod minio-0 >/dev/null 2>&1 || die "minio-0 is not running in $NS"

  # The live MinIO as a second remote, built entirely from environment variables so its root
  # credentials never reach a file. rclone reads RCLONE_CONFIG_<REMOTE>_<OPTION> for a remote that
  # is in no configuration file.
  export RCLONE_CONFIG_LIVE_TYPE=s3
  export RCLONE_CONFIG_LIVE_PROVIDER=Minio
  export RCLONE_CONFIG_LIVE_ENV_AUTH=false
  export RCLONE_CONFIG_LIVE_REGION=us-east-1
  export RCLONE_CONFIG_LIVE_FORCE_PATH_STYLE=true
  export RCLONE_CONFIG_LIVE_ENDPOINT="http://$(k get svc minio -o jsonpath='{.spec.clusterIP}'):9000"
  export RCLONE_CONFIG_LIVE_ACCESS_KEY_ID
  RCLONE_CONFIG_LIVE_ACCESS_KEY_ID=$(k get secret platform-secrets -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d)
  export RCLONE_CONFIG_LIVE_SECRET_ACCESS_KEY
  RCLONE_CONFIG_LIVE_SECRET_ACCESS_KEY=$(k get secret platform-secrets -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)

  if [ "$what" = all ]; then src="$MINIO_PREFIX"; dst="live:"; else src="$MINIO_PREFIX/$what"; dst="live:$what"; fi

  say "what would be copied from $src (nothing is written yet)"
  rclone copy "$src" "$dst" --dry-run --s3-no-check-bucket
  echo
  read -r -p "copy these objects back into $NS's MinIO? type yes: " answer
  [ "$answer" = yes ] || { echo "nothing copied"; return 0; }
  # `copy`, never `sync`: copy adds and overwrites, sync would DELETE anything live has that the
  # backup does not — which, restoring into a running environment, is everything uploaded since.
  rclone copy "$src" "$dst" --s3-no-check-bucket --stats-one-line --stats 10s
  ok "copied; nothing that was already in MinIO was removed"
}

case "$STEP" in
  list) step_list "$@" ;;
  fetch) step_fetch "$@" ;;
  open) step_open "$@" ;;
  dry-run) step_dry_run "$@" ;;
  into-live) step_into_live "$@" ;;
  minio) step_minio "$@" ;;
  *) die "unknown step '$STEP' (see the header of this script)" ;;
esac
