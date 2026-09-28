#!/usr/bin/env bash
# scripts/pg-restore.sh — restore the latest logical backup.
#   pg-restore.sh            -> restore into the live cvs database
#   pg-restore.sh --verify   -> restore into a scratch DB and assert it loads,
#                               proving the backup is actually recoverable
#                               (a backup you have never restored is not a backup).
set -euo pipefail

NS="backend"
OUTDIR="backups"
MODE="${1:-live}"

LATEST="$(ls -t "${OUTDIR}"/cvs-*.sql 2>/dev/null | head -1 || true)"
[ -n "${LATEST}" ] || { echo "no backup found in ${OUTDIR}/" >&2; exit 1; }
POD="$(kubectl -n "${NS}" get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
echo "==> using backup ${LATEST}"

if [ "${MODE}" = "--verify" ]; then
  echo "==> restoring into scratch DB 'cvs_verify'"
  kubectl -n "${NS}" exec "${POD}" -- sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP DATABASE IF EXISTS cvs_verify; CREATE DATABASE cvs_verify;"'
  kubectl -n "${NS}" exec -i "${POD}" -- sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d cvs_verify' < "${LATEST}"
  COUNT="$(kubectl -n "${NS}" exec "${POD}" -- sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -tA -U "$POSTGRES_USER" -d cvs_verify -c "SELECT count(*) FROM cvs;"')"
  echo "==> restore verified: cvs table present, ${COUNT} rows"
  kubectl -n "${NS}" exec "${POD}" -- sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP DATABASE cvs_verify;"'
else
  echo "==> restoring into LIVE cvs database"
  kubectl -n "${NS}" exec -i "${POD}" -- sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "${LATEST}"
  echo "==> restore complete"
fi
