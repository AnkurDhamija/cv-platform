#!/usr/bin/env bash
# scripts/cluster-up.sh — create the kind cluster and install a
# NetworkPolicy-enforcing CNI (Calico).
set -euo pipefail

CLUSTER_NAME="cv-platform"
KIND_CONFIG="platform/kind/kind-config.yaml"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> cluster ${CLUSTER_NAME} already exists"
else
  echo "==> creating kind cluster ${CLUSTER_NAME}"
  kind create cluster --config "${KIND_CONFIG}"
fi

echo "==> installing Calico CNI (enforces NetworkPolicy)"
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

echo "==> waiting for Calico to be ready"
kubectl -n kube-system rollout status ds/calico-node --timeout=180s

echo "==> waiting for nodes Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
echo "==> cluster up"
