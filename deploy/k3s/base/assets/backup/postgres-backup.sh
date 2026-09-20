#!/bin/sh
# One hourly backup of this namespace's Postgres, encrypted before it leaves the pod and uploaded
# off the box. Run by the `postgres-backup` CronJob (base/backup.yaml).
#
# Nothing here prints a password, a key or an rclone configuration. Values arrive through the
# environment or through a mounted Secret and are used from there.
#
# THE UNCONFIGURED CASE IS A SUCCESS, NOT A FAILURE. Until the owner creates the `backup-rclone` and
# `backup-age` Secrets there is nowhere to send a backup and nothing to encrypt it to. A Job that
# failed in that state would restart, back off, restart, and stand red in Argo CD forever, which
# teaches everyone to ignore it. So it says what is missing and exits 0 — and it does NOT ping the
# dead-man switch, so `BackupNotConfigured` and `BackupDidNotReport` are what actually tell anybody.
set -eu

NS="${NAMESPACE:?NAMESPACE is not set}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
HOUR=$(date -u +%H)
DAY=$(date -u +%d)
WORK=/work
umask 077

say() { echo "[backup $STAMP] $*"; }

# ----------------------------------------------------------------------- telling Prometheus
# A CronJob cannot be scraped: by the time Prometheus comes round the pod is gone, and whether this
# run did anything is exactly what has to outlive it. node-exporter's textfile collector is the
# standard answer — a file written here is served as metrics until it is replaced.
#
# The label is `env`, not `namespace`: the scrape already attaches namespace=monitoring (that is
# where node-exporter lives), and a metric carrying its own `namespace` would be renamed
# `exported_namespace` and every alert written against the obvious name would match nothing.
METRICS_DIR=/metrics-out
METRICS_FILE="$METRICS_DIR/backup-$NS-postgres.prom"
ENV_LABEL="${NS#delivery-}"

# The previous run's success time, carried forward so that a run which FAILS does not erase the
# record of the last one that worked — which is the number the alert measures.
prev_success() {
  [ -f "$METRICS_FILE" ] || return 0
  sed -n 's/^youdrop_backup_last_success_timestamp_seconds{.*} //p' "$METRICS_FILE" | head -n1
}

# publish <configured 0|1> <success-epoch or empty> <bytes or empty>
publish() {
  [ -d "$METRICS_DIR" ] || return 0
  L="env=\"$ENV_LABEL\",backup=\"postgres\""
  {
    echo "# HELP youdrop_backup_configured Whether this backup has a destination and a key to encrypt to."
    echo "# TYPE youdrop_backup_configured gauge"
    echo "youdrop_backup_configured{$L} $1"
    if [ -n "$2" ]; then
      echo "# HELP youdrop_backup_last_success_timestamp_seconds When a backup was last uploaded and verified."
      echo "# TYPE youdrop_backup_last_success_timestamp_seconds gauge"
      echo "youdrop_backup_last_success_timestamp_seconds{$L} $2"
    fi
    if [ -n "$3" ]; then
      echo "# HELP youdrop_backup_bytes The size of the encrypted archive last uploaded."
      echo "# TYPE youdrop_backup_bytes gauge"
      echo "youdrop_backup_bytes{$L} $3"
    fi
  } > "$METRICS_FILE.tmp" 2>/dev/null || return 0
  # Replaced atomically: node-exporter reads this directory on every scrape and a half-written file
  # is a parse error that takes out the whole textfile collector, not just this metric.
  mv "$METRICS_FILE.tmp" "$METRICS_FILE" 2>/dev/null || rm -f "$METRICS_FILE.tmp"
}

# --------------------------------------------------------------------------------- preconditions
missing=""
[ -s /etc/rclone/rclone.conf ] || missing="$missing backup-rclone/rclone.conf"
[ -s /etc/rclone/dest ] || missing="$missing backup-rclone/dest"
[ -s /etc/age/recipient ] || missing="$missing backup-age/recipient"
if [ -n "$missing" ]; then
  say "NOT CONFIGURED — nothing was backed up. Missing:$missing"
  say "Create them on the box; see 'Backups' in deploy/k3s/README.md. Exiting 0 so this Job does"
  say "not crash-loop; the BackupNotConfigured alert is what reports this state."
  publish 0 "$(prev_success)" ""
  exit 0
fi
DEST=$(cat /etc/rclone/dest)

# ------------------------------------------------------------------------------------- the tools
# `age` and `rclone` are not in any image that also carries a matching pg_dump, and building one is
# a CI job this platform does not have yet (see README, "Backups"). Installed here from Alpine's
# own repositories, pinned only by the image's Alpine version. If this fails the Job fails loudly,
# which is the right outcome: no ping is sent and the dead-man alert fires.
say "installing age, rclone and curl"
# curl rather than BusyBox's wget for the dead-man ping below: BusyBox only speaks HTTPS through
# ssl_client, and a dead-man switch that silently cannot reach its own URL is worse than not having
# one — it is the alert that is supposed to fire when everything else is unreachable.
apk add --no-cache age rclone curl >/dev/null

mkdir -p "$WORK"
cd "$WORK"

# ------------------------------------------------------------------------------------- the dumps
# --globals-only first: roles and their passwords live outside any single database, so a restore
# without them recreates the schemas and then refuses every service's login.
say "pg_dumpall --globals-only"
pg_dumpall --globals-only -h "$PGHOST" -U "$PGUSER" > globals.sql

# Custom format (-Fc): compressed, and pg_restore can then rebuild selectively and in parallel.
# A plain SQL dump can only be replayed whole, in order, into a database that already matches.
for db in delivery keycloak; do
  say "pg_dump -Fc $db"
  pg_dump -Fc -h "$PGHOST" -U "$PGUSER" -d "$db" > "$db.dump"
done

# What the archive contains and what it came from, so a restore can be checked against it without
# opening the dumps. Read by scripts/restore.sh and by the weekly restore test.
{
  echo "namespace=$NS"
  echo "taken_at=$STAMP"
  echo "postgres_version=$(psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c 'show server_version')"
  for f in globals.sql delivery.dump keycloak.dump; do
    echo "file=$f bytes=$(wc -c < "$f" | tr -d ' ') sha256=$(sha256sum "$f" | cut -d' ' -f1)"
  done
  for t in flyway_schema_history stores products orders; do
    n=$(psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c \
        "select count(*) from information_schema.tables where table_name = '$t'")
    [ "$n" = 0 ] && continue
    echo "rows=$t count=$(psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c "select count(*) from $t")"
  done
} > manifest.txt

# ------------------------------------------------------------------------------------ encryption
# Encrypted HERE, in the pod, before anything is written anywhere a third party can read. The
# recipient is a public key: this pod can create a backup it cannot itself read, which is the point
# — a compromise of the cluster does not hand over the archive of every previous state of the
# database. The private half is the owner's and stays offline.
#
# A second recipient may be listed for the weekly restore test (README): every recipient can
# decrypt independently, so adding one does not weaken the first.
say "tar + age"
tar cf - globals.sql delivery.dump keycloak.dump manifest.txt \
  | age -R /etc/age/recipient > "bundle-$STAMP.tar.age"
rm -f globals.sql delivery.dump keycloak.dump
SIZE=$(wc -c < "bundle-$STAMP.tar.age" | tr -d ' ')
[ "$SIZE" -gt 1024 ] || { say "the encrypted bundle is $SIZE bytes, which cannot be right"; exit 1; }

# -------------------------------------------------------------------------------------- upload
# Three prefixes rather than one, because retention is enforced by the BUCKET's lifecycle rules and
# a lifecycle rule can only say "everything under this prefix, after N days". Hourly copies expire
# in three days, daily in thirty-five, monthly in a year — see README. The daily and monthly copies
# are server-side copies of the object just uploaded, so the dump crosses the network once.
export RCLONE_CONFIG=/etc/rclone/rclone.conf
HOURLY="$DEST/$NS/postgres/hourly/bundle-$STAMP.tar.age"
say "uploading $SIZE bytes"
rclone copyto "bundle-$STAMP.tar.age" "$HOURLY" --s3-no-check-bucket

if [ "$HOUR" = "03" ]; then
  say "also keeping today's daily copy"
  rclone copyto "$HOURLY" "$DEST/$NS/postgres/daily/$(date -u +%Y%m%d).tar.age" --s3-no-check-bucket
  if [ "$DAY" = "01" ]; then
    say "also keeping this month's copy"
    rclone copyto "$HOURLY" "$DEST/$NS/postgres/monthly/$(date -u +%Y%m).tar.age" --s3-no-check-bucket
  fi
fi

# Read it back. An upload that reported success and left nothing readable at the other end is the
# failure this whole file exists to prevent, and it is not hypothetical — a misconfigured bucket
# policy accepts writes and serves nothing.
REMOTE_SIZE=$(rclone size "$HOURLY" --json 2>/dev/null | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
[ "$REMOTE_SIZE" = "$SIZE" ] \
  || { say "FAILED: uploaded $SIZE bytes, the destination reports '${REMOTE_SIZE:-nothing}'"; exit 1; }
say "verified $REMOTE_SIZE bytes at $HOURLY"
# Only now, with the object read back at the right size, is this a backup.
publish 1 "$(date -u +%s)" "$SIZE"

# ------------------------------------------------------------------------------------- dead man
# The only signal that survives the whole box dying. Everything else in this file is observed from
# inside the cluster, and a cluster that is gone reports nothing at all; a dead-man switch alerts
# on the ABSENCE of this request. Optional, and silently skipped when unset — but then the only
# thing watching backups is Prometheus, which is on the same box.
if [ -s /etc/deadman/url ]; then
  # The URL itself is a capability — anyone who has it can keep the switch alive — so it comes out
  # of a file into curl's argument and is never echoed.
  if curl -fsS -m 20 -o /dev/null "$(cat /etc/deadman/url)"; then
    say "dead-man ping sent"
  else
    # Deliberately not fatal: the backup IS uploaded and verified. A failed ping is a monitoring
    # problem, and failing here would throw away a good backup to report it.
    say "WARNING: the dead-man ping did not go through; the backup itself is uploaded and verified"
  fi
else
  say "no dead-man URL configured (backup-deadman/url); skipping the ping"
fi

rm -f "$WORK/bundle-$STAMP.tar.age"
say "done"
