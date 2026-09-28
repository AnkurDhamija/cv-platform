#!/usr/bin/env bash
# scripts/secrets-seal.sh
# Installs the Sealed Secrets controller, then generates the DB + object-store
# credentials, encrypts them with the controller's public key (kubeseal), and
# applies the SealedSecrets. Plaintext credentials NEVER touch Git: they are
# generated here and only their sealed (encrypted) form is written to disk.
#
# GKE alternative (documented in docs/ARCHITECTURE_AND_THREATS.md): External
# Secrets Operator sourcing from GCP Secret Manager via Workload Identity.
set -euo pipefail

SS_VERSION="v0.27.1"
OUT="deploy/secrets/generated"   # git-ignored; only sealed output lives here
mkdir -p "${OUT}"

echo "==> installing Sealed Secrets controller ${SS_VERSION}"
kubectl apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SS_VERSION}/controller.yaml"
kubectl -n kube-system rollout status deploy/sealed-secrets-controller --timeout=180s

# --- generate credentials (random; deterministic within a cluster) -----------
PG_USER="cvuser"; PG_DB="cvs"
PG_PASS="$(head -c18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c24)"
MINIO_USER="cvminio"
MINIO_PASS="$(head -c18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c24)"
PG_DSN="host=postgres.backend.svc.cluster.local dbname=${PG_DB} user=${PG_USER} password=${PG_PASS}"

seal() { # <name> <literal...> -> SealedSecret in backend ns
  local name="$1"; shift
  kubectl create secret generic "${name}" --namespace backend --dry-run=client -o yaml "$@" \
    | kubeseal --controller-namespace kube-system --format yaml \
    > "${OUT}/${name}.sealed.yaml"
  kubectl apply -f "${OUT}/${name}.sealed.yaml"
  echo "sealed + applied: ${name}"
}

echo "==> sealing credentials"
seal cv-db-credentials \
  --from-literal=POSTGRES_USER="${PG_USER}" \
  --from-literal=POSTGRES_PASSWORD="${PG_PASS}" \
  --from-literal=POSTGRES_DB="${PG_DB}" \
  --from-literal=PG_DSN="${PG_DSN}"

seal cv-object-credentials \
  --from-literal=MINIO_ROOT_USER="${MINIO_USER}" \
  --from-literal=MINIO_ROOT_PASSWORD="${MINIO_PASS}" \
  --from-literal=MINIO_ACCESS_KEY="${MINIO_USER}" \
  --from-literal=MINIO_SECRET_KEY="${MINIO_PASS}"

echo "==> secrets sealed (plaintext never written to Git)"
