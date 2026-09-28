#!/usr/bin/env bash
# scripts/registry-up.sh — start a local OCI registry and join it to the kind network.
set -euo pipefail

REG_NAME="kind-registry"
REG_PORT="5001"

if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != "true" ]; then
  echo "==> starting local registry ${REG_NAME} on localhost:${REG_PORT}"
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" \
    --name "${REG_NAME}" registry:2
fi

# Connect the registry to the kind network so nodes can pull from it.
if [ -n "$(docker network ls --filter name=^kind$ -q)" ]; then
  docker network connect kind "${REG_NAME}" 2>/dev/null || true
fi
echo "==> registry ready"
