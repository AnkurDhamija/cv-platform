#!/usr/bin/env bash
# scripts/set-digests.sh — pin the app Deployments to the exact image digests
# the REGISTRY holds (deploy-by-digest, Part 3). Resolving from the registry is
# robust to Docker's containerd image store, which rewrites digests on push.
set -euo pipefail
REGISTRY="${REGISTRY:-localhost:5001}"

reg_digest() { # <service> -> sha256:...
  curl -fsS -o /dev/null -D - \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    "http://${REGISTRY}/v2/$1/manifests/dev" \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'
}

pin() { # <service> <manifest>
  local svc="$1" manifest="$2" digest; digest="$(reg_digest "${svc}")"
  case "${digest}" in sha256:*) : ;; *) echo "no registry digest for ${svc}" >&2; exit 1 ;; esac
  sed -i -E "s#(image: [^[:space:]@]*/${svc})@sha256:[0-9a-f]{64}#\1@${digest}#" "${manifest}"
  echo "pinned ${svc} -> ${digest}"
}

pin public-api   deploy/base/public-api/deployment.yaml
pin cv-processor deploy/base/cv-processor/deployment.yaml
