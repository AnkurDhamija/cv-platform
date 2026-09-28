#!/usr/bin/env bash
# scripts/sign-images.sh — sign the locally-built images with the local cosign
# key so they satisfy the enforce-mode verify-images policy on kind.
# (In CI this is replaced by keyless cosign signing via GitHub OIDC.)
set -euo pipefail

REGISTRY="${REGISTRY:-localhost:5001}"
KEY=".local-keys/cosign.key"

for img in public-api cv-processor; do
  digest="$(docker inspect --format='{{index .RepoDigests 0}}' "${REGISTRY}/${img}:dev" 2>/dev/null | cut -d'@' -f2)"
  if [ -z "${digest}" ]; then
    echo "!! could not resolve digest for ${img}; did you push it?" >&2; exit 1
  fi
  echo "==> signing ${REGISTRY}/${img}@${digest}"
  COSIGN_PASSWORD="" cosign sign --tlog-upload=false --key "${KEY}" --yes "${REGISTRY}/${img}@${digest}"
done
echo "==> images signed"
