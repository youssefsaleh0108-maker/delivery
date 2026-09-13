#!/bin/sh
# Creates the five buckets from Section 5 with the access pattern each one requires.
# Idempotent: safe to re-run, and `docker compose up` re-runs it on every start.
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

echo "==> Creating buckets"
for bucket in product-images delivery-proof merchant-kyc user-avatars receipts; do
  mc mb --ignore-existing "local/$bucket"
done

# product-images is the only bucket served publicly - product photos sit behind a CDN and are read
# by anonymous browsers on the catalog screen. Writes still require a presigned PUT issued to a
# MERCHANT, so "public" here means read-only.
echo "==> Setting product-images public-read"
mc anonymous set download local/product-images

# Merchant Blitz's shelf photos (product-images, under scans/) are working copies, not catalogue
# images. product-service deletes a scan's photos once every line on it is decided; this expires the
# rest — scans abandoned half way, uploads never confirmed. Two days: past the 24 hours in which a
# scan can still be picked up again, so nothing goes from under a scan its merchant can reopen, and
# no longer, because this bucket is public-read and these are photos of somebody's shop. Checked
# first, because `mc ilm rule add` would add the same rule again on every run.
echo "==> Expiring Merchant Blitz shelf photos (scans/) after 2 days"
if mc ilm rule export local/product-images 2>/dev/null | grep -q '"scans/"'; then
  echo "    (expiry rule already present)"
else
  mc ilm rule add local/product-images --prefix "scans/" --expire-days 2
fi

# Everything else stays private. Clients reach these objects only through short-TTL presigned URLs
# issued by the file service after it has checked the caller's role AND resource ownership - no
# client ever holds MinIO credentials (Section 5).
echo "==> Keeping delivery-proof, merchant-kyc, user-avatars, receipts private"
for bucket in delivery-proof merchant-kyc user-avatars receipts; do
  mc anonymous set none "local/$bucket"
done

# Proof-of-delivery photos are dispute evidence. Versioning plus a retention lock means a rider or
# a bug cannot silently overwrite or delete the only record of a contested delivery (Section 10).
echo "==> Enabling versioning + retention on delivery-proof"
mc version enable local/delivery-proof
mc ilm rule add local/delivery-proof --expire-delete-marker --noncurrent-expire-days 365 || \
  echo "    (retention rule already present)"

# KYC documents are personal data: keep them, but not forever, and never publicly.
echo "==> Enabling versioning on merchant-kyc"
mc version enable local/merchant-kyc

echo "==> MinIO bootstrap complete"
mc ls local
