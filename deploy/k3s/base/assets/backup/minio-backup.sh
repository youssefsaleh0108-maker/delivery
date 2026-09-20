#!/bin/sh
# The nightly copy of every MinIO bucket to the same destination as the database backups. Run by
# the `minio-backup` CronJob (base/backup.yaml).
#
# Objects, unlike the database, are already their own final form: there is nothing to dump and
# nothing to replay, so this is a sync rather than a snapshot — each night moves only what changed.
# The way back is the same command with the two ends swapped (scripts/restore.sh minio).
set -eu

NS="${NAMESPACE:?NAMESPACE is not set}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
say() { echo "[minio-backup $STAMP] $*"; }

missing=""
[ -s /etc/rclone/rclone.conf ] || missing="$missing backup-rclone/rclone.conf"
[ -s /etc/rclone/dest ] || missing="$missing backup-rclone/dest"
if [ -n "$missing" ]; then
  say "NOT CONFIGURED — nothing was copied. Missing:$missing"
  say "See 'Backups' in deploy/k3s/README.md. Exiting 0 rather than crash-looping."
  exit 0
fi
DEST=$(cat /etc/rclone/dest)

say "installing rclone"
apk add --no-cache rclone >/dev/null

# The source remote is built entirely from environment variables, so MinIO's root credentials never
# reach a file. rclone reads RCLONE_CONFIG_<REMOTE>_<OPTION> for a remote it was never told about.
export RCLONE_CONFIG=/etc/rclone/rclone.conf
export RCLONE_CONFIG_SRC_TYPE=s3
export RCLONE_CONFIG_SRC_PROVIDER=Minio
export RCLONE_CONFIG_SRC_ENV_AUTH=false
export RCLONE_CONFIG_SRC_ENDPOINT="${MINIO_ENDPOINT:?MINIO_ENDPOINT is not set}"
export RCLONE_CONFIG_SRC_ACCESS_KEY_ID="${MINIO_ROOT_USER:?MINIO_ROOT_USER is not set}"
export RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is not set}"
export RCLONE_CONFIG_SRC_REGION=us-east-1
export RCLONE_CONFIG_SRC_FORCE_PATH_STYLE=true

# With no bucket after the colon, `src:` is every bucket on the server — so a bucket added later is
# copied the night it appears, with no edit here.
#
# product-images/scans/ is excluded deliberately: those are the merchant shelf photographs Merchant
# Blitz reads to build a catalogue. They are large, they are uploaded in bursts, and they are
# INPUT — once a scan has produced products, the photograph has no further use and can be taken
# again. Copying them nightly would be most of the bill for none of the value.
say "syncing every bucket except product-images/scans/"
rclone sync src: "$DEST/$NS/minio" \
  --exclude "product-images/scans/**" \
  --s3-no-check-bucket \
  --stats-one-line --stats 1m \
  --transfers 4 --checkers 8

# `sync` deletes at the destination what is gone at the source — which is the correct behaviour for
# a mirror and the wrong behaviour if somebody has just emptied a bucket by accident. That is what
# the destination's OBJECT VERSIONING is for, and it is the one setting this script cannot check:
# see README. Without versioning, this command propagates a deletion within a day.
say "checking what is at the other end"
rclone size "$DEST/$NS/minio" --json

if [ -s /etc/deadman/minio-url ]; then
  wget -q -T 15 -O /dev/null "$(cat /etc/deadman/minio-url)" \
    && say "dead-man ping sent" \
    || say "WARNING: the dead-man ping did not go through; the sync itself completed"
fi
say "done"
