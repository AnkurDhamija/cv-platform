#!/usr/bin/env bash
# =============================================================================
# scripts/pin-digests.sh
# Resolves the CURRENT digest of each base image and rewrites the ARG default
# lines in both Dockerfiles so builds are reproducible and digest-pinned.
#
# Run on any machine with registry access (developer laptop or CI). CI also
# *verifies* that every FROM/ARG image reference is digest-pinned and fails
# otherwise (see .github/workflows/ci.yml).
# =============================================================================
set -euo pipefail

BUILDER_REF="python:3.11-slim-bookworm"
RUNTIME_REF="gcr.io/distroless/python3-debian12:nonroot"

resolve() { # <image:tag> -> sha256:...
  if command -v crane >/dev/null 2>&1; then
    crane digest "$1"
  elif command -v docker >/dev/null 2>&1; then
    docker manifest inspect "$1" >/dev/null
    docker buildx imagetools inspect "$1" 2>/dev/null | awk '/Digest:/{print $2; exit}'
  else
    echo "need crane or docker to resolve digests" >&2; exit 1
  fi
}

echo "Resolving base image digests..."
BUILDER_DIGEST="$(resolve "$BUILDER_REF")"
RUNTIME_DIGEST="$(resolve "$RUNTIME_REF")"
echo "  builder : $BUILDER_REF@$BUILDER_DIGEST"
echo "  runtime : $RUNTIME_REF@$RUNTIME_DIGEST"

for df in services/public-api/Dockerfile services/cv-processor/Dockerfile; do
  sed -i -E \
    -e "s#^(ARG BUILDER_IMAGE=).*#\1${BUILDER_REF}@${BUILDER_DIGEST}#" \
    -e "s#^(ARG RUNTIME_IMAGE=).*#\1${RUNTIME_REF}@${RUNTIME_DIGEST}#" \
    "$df"
  echo "pinned: $df"
done
echo "Done. Commit the updated Dockerfiles."
