#!/bin/sh
# Weekly: prove that what is being written off the box can be read back and turned into a database.
# Run by the `restore-test` CronJob (base/backup.yaml).
#
# A backup nobody has ever restored is a belief, not a backup. Every part of the path has a way of
# failing quietly — a dump taken against the wrong database, an archive truncated by a disk that
# filled, a bucket policy that accepts writes and serves nothing, a pg_dump from a server newer
# than the pg_restore that will one day read it. None of that shows up until the hour it matters.
#
# The throwaway Postgres is a SIDECAR in this pod, reachable only on 127.0.0.1 and gone when this
# script exits. It trusts local connections because nothing else can open one.
#
# TWO MODES, and it says which one it ran:
#   full      the archive itself is downloaded and decrypted, with the age identity in
#             backup-age/restore-test.key, and THAT is what is restored. This is the mode that
#             proves the whole path. It needs a second age recipient on the backups (README).
#   dump-only the archive is fetched and checked for integrity but not decrypted, because the
#             private key is deliberately offline; a dump taken here and now is restored instead.
#             Proves pg_dump/pg_restore and the schema, not the archive's contents.
set -eu

NS="${NAMESPACE:?NAMESPACE is not set}"
SCRATCH=127.0.0.1
WORK=/work
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
umask 077
fails=0
say()  { echo "[restore-test $STAMP] $*"; }
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fails=$((fails + 1)); }

mkdir -p "$WORK"
cd "$WORK"
apk add --no-cache age rclone >/dev/null

MODE=dump-only
ARCHIVE=""
if [ -s /etc/rclone/rclone.conf ] && [ -s /etc/rclone/dest ]; then
  export RCLONE_CONFIG=/etc/rclone/rclone.conf
  DEST=$(cat /etc/rclone/dest)
  # Newest by name: the names are UTC timestamps in a sortable form, so this needs no listing of
  # modification times and no clock agreement with the destination.
  ARCHIVE=$(rclone lsf "$DEST/$NS/postgres/hourly/" 2>/dev/null | sort | tail -n1)
  if [ -n "$ARCHIVE" ]; then
    say "newest archive: $ARCHIVE"
    rclone copyto "$DEST/$NS/postgres/hourly/$ARCHIVE" bundle.tar.age
    SIZE=$(wc -c < bundle.tar.age | tr -d ' ')
    [ "$SIZE" -gt 1024 ] && ok "the archive downloads and is $SIZE bytes" \
                         || bad "the archive is $SIZE bytes, which cannot be a database"
    # An age file begins with this exact string. A bucket serving an error page instead of the
    # object is the failure this catches, and it looks like a successful download.
    head -c 21 bundle.tar.age | grep -q 'age-encryption.org' \
      && ok "it is an age file" \
      || bad "the downloaded object is not an age file: the destination may be serving something else"
    # How old is the newest backup? An archive from six hours ago means the hourly job has been
    # failing for six hours and nothing said so.
    age_h=$(( ( $(date -u +%s) - $(date -u -d "$(echo "$ARCHIVE" | sed -n 's/bundle-\(........\)T\(..\)\(..\)\(..\)Z.tar.age/\1 \2:\3:\4/p')" +%s 2>/dev/null || echo 0) ) / 3600 ))
    if [ "$age_h" -ge 0 ] && [ "$age_h" -le 3 ]; then ok "it is ${age_h}h old"
    else bad "the newest archive is ${age_h}h old; the hourly backup is not running"; fi
    if [ -s /etc/age/restore-test.key ]; then
      if age -d -i /etc/age/restore-test.key bundle.tar.age > bundle.tar 2>/dev/null; then
        tar xf bundle.tar && MODE=full && ok "it decrypts and unpacks"
      else
        bad "the archive did not decrypt with backup-age/restore-test.key"
      fi
      rm -f bundle.tar
    else
      say "no backup-age/restore-test.key: the private key is offline, so this is the dump-only mode"
    fi
    rm -f bundle.tar.age
  else
    bad "no archive under $DEST/$NS/postgres/hourly/: nothing has ever been uploaded"
  fi
else
  say "backups are not configured yet, so there is no archive to read back"
fi

if [ "$MODE" = dump-only ]; then
  say "taking a dump now and restoring that instead"
  pg_dumpall --globals-only -h "$PGHOST" -U "$PGUSER" > globals.sql
  for db in delivery keycloak; do pg_dump -Fc -h "$PGHOST" -U "$PGUSER" -d "$db" > "$db.dump"; done
fi

# ------------------------------------------------------------------------- the throwaway server
say "waiting for the scratch Postgres in this pod"
i=0
until pg_isready -h "$SCRATCH" -U postgres >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 60 ] || { say "the scratch Postgres never came up"; exit 1; }
  sleep 2
done
ok "the scratch Postgres is up"

# Roles first: they live outside any database, and a restore without them rebuilds every schema and
# then refuses every service's login. Errors are tolerated here only because `postgres` itself is
# in the dump and already exists; the count is what is checked.
roles_in_dump=$(grep -c '^CREATE ROLE' globals.sql || true)
PGPASSWORD="" psql -h "$SCRATCH" -U postgres -d postgres -q -f globals.sql >/dev/null 2>&1 || true
roles_restored=$(psql -h "$SCRATCH" -U postgres -d postgres -At -c \
  "select count(*) from pg_roles where rolname not like 'pg\_%'")
[ "$roles_restored" -ge "$roles_in_dump" ] \
  && ok "$roles_restored roles exist (the dump carried $roles_in_dump)" \
  || bad "the dump carried $roles_in_dump roles and only $roles_restored exist after restoring it"

for db in delivery keycloak; do
  psql -h "$SCRATCH" -U postgres -d postgres -q -c "create database $db" >/dev/null
  # Not --exit-on-error: a restore into a server that lacks an extension or an owner reports those
  # per object and completes the rest, and a count of what arrived is a better answer than a stop
  # at the first complaint. The checks below are what decide whether it worked.
  pg_restore -h "$SCRATCH" -U postgres -d "$db" --no-owner --no-privileges "$db.dump" \
    > "restore-$db.log" 2>&1 || true
  errs=$(grep -c '^pg_restore: error' "restore-$db.log" || true)
  tables=$(psql -h "$SCRATCH" -U postgres -d "$db" -At -c \
    "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema')")
  [ "$tables" -gt 0 ] \
    && ok "$db restored: $tables tables, $errs pg_restore error(s)" \
    || bad "$db restored no tables at all ($errs pg_restore errors; see restore-$db.log)"
done

# ------------------------------------------------------------------------------- what it holds
# Flyway's history is the one table that says which migrations this database has, so a restore that
# lost it, or that came from a database at a different version, is a restore that will not start
# the services. Compared against the LIVE database, which is the only honest comparison.
say "Flyway versions, restored against live"
for schema in $(psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c \
    "select table_schema from information_schema.tables where table_name = 'flyway_schema_history' order by 1"); do
  live=$(psql -h "$PGHOST" -U "$PGUSER" -d delivery -At -c \
    "select coalesce(max(version), 'none') from $schema.flyway_schema_history where success")
  back=$(psql -h "$SCRATCH" -U postgres -d delivery -At -c \
    "select coalesce(max(version), 'none') from $schema.flyway_schema_history where success" 2>/dev/null || echo unreadable)
  [ "$live" = "$back" ] \
    && ok "$schema at V$back" \
    || bad "$schema: live is at V$live, the restore is at V$back"
done

# Row counts. A dump that restores cleanly and is EMPTY is the failure mode nobody expects, and it
# is what a pg_dump pointed at the wrong host produces. Hourly backups mean the restore can be
# slightly behind live, so this checks that the restore is not empty and not wildly short, rather
# than that the two match exactly.
say "row counts, restored against live"
for pair in delivery:stores delivery:products delivery:orders keycloak:user_entity; do
  db=${pair%%:*}; t=${pair##*:}
  has=$(psql -h "$SCRATCH" -U postgres -d "$db" -At -c \
    "select count(*) from information_schema.tables where table_name = '$t'" 2>/dev/null || echo 0)
  [ "$has" = "1" ] || { say "  (no $db.$t in this environment; skipped)"; continue; }
  live=$(psql -h "$PGHOST" -U "$PGUSER" -d "$db" -At -c "select count(*) from $t")
  back=$(psql -h "$SCRATCH" -U postgres -d "$db" -At -c "select count(*) from $t")
  if [ "$live" = 0 ] && [ "$back" = 0 ]; then
    ok "$db.$t is empty in both"
  elif [ "$back" -gt 0 ] && [ "$back" -ge $((live * 9 / 10)) ]; then
    ok "$db.$t: $back rows restored, $live live"
  else
    bad "$db.$t: $back rows restored against $live live"
  fi
done

rm -rf "$WORK"/*.dump "$WORK"/globals.sql
echo
if [ "$fails" = 0 ]; then
  say "PASS (mode: $MODE${ARCHIVE:+, archive: $ARCHIVE})"
else
  say "FAILED: $fails check(s) (mode: $MODE). The backups cannot be relied on until this passes."
  exit 1
fi
