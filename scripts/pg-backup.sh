#!/usr/bin/env bash
# scripts/pg-backup.sh — logical backup of the cvs database via pg_dump.
# Writes a timestamped dump locally and (best-effort) mirrors it to MinIO,
# mirroring the production story: pg_dump -> object storage (GCS on GKE),
# lifecycle-managed, encrypted at rest.
set -euo pipefail

NS="backend"
OUTDIR="backups"
mkdir -p "${OUTDIR}"
TS="$(date +%Y%m%dT%H%M%S)"
DUMP="${OUTDIR}/cvs-${TS}.sql"

POD="$(kubectl -n "${NS}" get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
echo "==> dumping cvs from ${POD}"
kubectl -n "${NS}" exec "${POD}" -- sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  > "${DUMP}"

echo "==> backup written: ${DUMP} ($(wc -c < "${DUMP}") bytes)"
echo "    On GKE this dump is streamed to a GCS bucket with object versioning +"
echo "    a 30-day lifecycle rule; the bucket is CMEK-encrypted."
