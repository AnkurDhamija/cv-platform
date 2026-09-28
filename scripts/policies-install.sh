#!/usr/bin/env bash
# scripts/policies-install.sh
# Installs Kyverno, applies the enforce-mode policies, and (for local kind)
# generates a cosign key pair whose public key backs the local verify-images
# policy. The private key signs the app images in scripts/sign-images.sh.
set -euo pipefail

KYVERNO_VER="v1.12.5"
KEYDIR=".local-keys"

echo "==> installing Kyverno ${KYVERNO_VER}"
# Kyverno CRDs exceed the client-side 262144-byte annotation limit;
# server-side apply avoids it.
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VER}/install.yaml"
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

echo "==> allowing Kyverno to use the insecure (http) local registry"
if ! kubectl -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q allowInsecureRegistry; then
  kubectl -n kyverno patch deploy kyverno-admission-controller --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--allowInsecureRegistry=true"}]'
  kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s
fi

echo "==> exposing local registry to Kyverno (in-cluster Service -> registry container)"
REG_IP="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' kind-registry)"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata: { name: kind-registry, namespace: kyverno }
spec:
  ports: [{ port: 5000, targetPort: 5000, protocol: TCP }]
---
apiVersion: v1
kind: Endpoints
metadata: { name: kind-registry, namespace: kyverno }
subsets:
  - addresses: [{ ip: ${REG_IP} }]
    ports: [{ port: 5000, protocol: TCP }]
EOF

echo "==> adding registry forwarder sidecar to Kyverno (localhost:5001 -> registry)"
if ! kubectl -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[*].name}' | grep -q registry-localhost; then
  kubectl -n kyverno patch deploy kyverno-admission-controller --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/-","value":{"name":"registry-localhost","image":"alpine/socat:latest","args":["TCP-LISTEN:5001,fork,reuseaddr","TCP:kind-registry.kyverno.svc.cluster.local:5000"],"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}}]'
  kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s
fi

echo "==> generating local cosign key pair (if absent)"
mkdir -p "${KEYDIR}"
if [ ! -f "${KEYDIR}/cosign.key" ]; then
  COSIGN_PASSWORD="" cosign generate-key-pair --output-key-prefix "${KEYDIR}/cosign"
fi

echo "==> rendering local verify-images policy with the public key"
# Indent the PEM by 22 spaces to sit under 'publicKeys: |-'.
PUB_INDENTED="$(sed 's/^/                      /' "${KEYDIR}/cosign.pub")"
python3 - "$PUB_INDENTED" <<'PY' > /tmp/verify-images-local.yaml
import sys
tmpl=open("deploy/policies/kyverno/verify-images-local.yaml.tmpl").read()
print(tmpl.replace("__COSIGN_PUB__", sys.argv[1]))
PY

echo "==> applying enforce-mode policies"
kubectl apply -f deploy/policies/kyverno/require-security-context.yaml
kubectl apply -f /tmp/verify-images-local.yaml
# NOTE: verify-images-keyless.yaml is the GKE/CI policy; not applied locally.

echo "==> waiting for policies to be ready"
kubectl wait --for=condition=Ready clusterpolicy/require-hardened-security-context --timeout=60s || true
kubectl wait --for=condition=Ready clusterpolicy/verify-image-signatures --timeout=60s || true
echo "==> policies installed (enforce mode)"
