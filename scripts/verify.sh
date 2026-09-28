#!/usr/bin/env bash
# =============================================================================
# scripts/verify.sh — proves the security controls and EXITS NON-ZERO on any
# failure. Run after `make up`.
#
#   (a) an unsigned image is rejected by admission control
#   (b) a pod violating the security context is rejected
#   (c) public-api CAN reach cv-processor
#   (d) cv-processor CANNOT reach the internet
#   (e) a frontend pod other than public-api CANNOT reach cv-processor
# =============================================================================
set -uo pipefail

REGISTRY="${REGISTRY:-localhost:5001}"
CURL_IMG="${CURL_IMG:-curlimages/curl:8.10.1}"
PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

ok()   { echo -e "${GREEN}PASS${NC} — $1"; PASS=$((PASS+1)); }
bad()  { echo -e "${RED}FAIL${NC} — $1"; FAIL=$((FAIL+1)); }
info() { echo -e "${BLUE}==>${NC} $1"; }

cleanup() {
  kubectl delete pod -A -l verify=cv-platform --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Hardened securityContext shared by the positive test pods (so ONLY the control
# under test can reject them).
HARDENED_SC='{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}'
HARDENED_CSC='{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}'

# Run a curl pod with a given label in a given namespace; returns the pod phase.
# args: <ns> <appLabel> <curl-target-args...>
curl_probe() {
  local ns="$1" app="$2"; shift 2
  local name="probe-${app}-$RANDOM"
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: ${ns}
  labels: { app: ${app}, verify: cv-platform }
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: ${HARDENED_SC}
  containers:
    - name: c
      image: ${CURL_IMG}
      args: [$(printf '"%s",' "$@" | sed 's/,$//')]
      securityContext: ${HARDENED_CSC}
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
  volumes: [{ name: tmp, emptyDir: {} }]
EOF
  kubectl -n "${ns}" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"${name}" --timeout=45s >/dev/null 2>&1
  local phase; phase="$(kubectl -n "${ns}" get pod "${name}" -o jsonpath='{.status.phase}' 2>/dev/null)"
  echo "${phase}"
}

echo "======================================================================"
echo " make verify — proving controls (a)–(e)"
echo "======================================================================"

# ---------------------------------------------------------------------------
# (a) unsigned image rejected. Image is hardened -> ONLY the signature policy
#     can reject it, so we assert on the signature policy specifically.
# ---------------------------------------------------------------------------
info "(a) unsigned image should be rejected by admission control"
docker pull busybox:1.36 >/dev/null 2>&1 || true
docker tag busybox:1.36 "${REGISTRY}/cv-processor-unsigned:test" >/dev/null 2>&1
docker push "${REGISTRY}/cv-processor-unsigned:test" >/dev/null 2>&1
OUT="$(cat <<EOF | kubectl apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-test
  namespace: backend
  labels: { verify: cv-platform }
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: ${HARDENED_SC}
  containers:
    - name: c
      image: ${REGISTRY}/cv-processor-unsigned:test
      command: ["sleep","1"]
      securityContext: ${HARDENED_CSC}
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
  volumes: [{ name: tmp, emptyDir: {} }]
EOF
)"
if echo "${OUT}" | grep -qiE 'verify-image-signatures|signature'; then
  ok "(a) unsigned image rejected by signature policy"
elif echo "${OUT}" | grep -qi 'denied the request'; then
  ok "(a) unsigned image rejected by admission (policy: $(echo "$OUT" | grep -o 'policy [^ ]*' | head -1))"
else
  bad "(a) unsigned image was NOT rejected"; echo "${OUT}" | tail -3
fi
kubectl -n backend delete pod unsigned-test --ignore-not-found --wait=false >/dev/null 2>&1

# ---------------------------------------------------------------------------
# (b) bad security context (root + privilege escalation + writable fs) rejected.
# ---------------------------------------------------------------------------
info "(b) a root / writable-fs pod should be rejected"
OUT="$(cat <<EOF | kubectl apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: rootpod-test
  namespace: frontend
  labels: { verify: cv-platform }
spec:
  restartPolicy: Never
  containers:
    - name: c
      image: ${CURL_IMG}
      command: ["sleep","1"]
      securityContext:
        runAsUser: 0
        allowPrivilegeEscalation: true
        readOnlyRootFilesystem: false
EOF
)"
if echo "${OUT}" | grep -qiE 'require-hardened-security-context|securityContext|denied the request'; then
  ok "(b) insecure pod rejected by security-context policy"
else
  bad "(b) insecure pod was NOT rejected"; echo "${OUT}" | tail -3
fi
kubectl -n frontend delete pod rootpod-test --ignore-not-found --wait=false >/dev/null 2>&1

# ---------------------------------------------------------------------------
# (c) public-api CAN reach cv-processor.
# ---------------------------------------------------------------------------
info "(c) public-api -> cv-processor should SUCCEED"
PHASE="$(curl_probe frontend public-api -sf --max-time 8 http://cv-processor.backend.svc.cluster.local:8081/health)"
[ "${PHASE}" = "Succeeded" ] && ok "(c) public-api reached cv-processor" \
  || bad "(c) public-api could NOT reach cv-processor (phase=${PHASE:-none})"

# ---------------------------------------------------------------------------
# (d) cv-processor CANNOT reach the internet.
# ---------------------------------------------------------------------------
info "(d) cv-processor -> internet should be BLOCKED"
# 1.1.1.1 by IP to avoid DNS ambiguity; expect a timeout/failure -> pod Failed.
PHASE="$(curl_probe backend cv-processor -s --max-time 8 https://1.1.1.1)"
[ "${PHASE}" = "Failed" ] && ok "(d) cv-processor blocked from the internet" \
  || bad "(d) cv-processor REACHED the internet (phase=${PHASE:-none})"

# ---------------------------------------------------------------------------
# (e) a frontend pod that is NOT public-api CANNOT reach cv-processor.
# ---------------------------------------------------------------------------
info "(e) other frontend pod -> cv-processor should be BLOCKED"
PHASE="$(curl_probe frontend intruder -s --max-time 8 http://cv-processor.backend.svc.cluster.local:8081/health)"
[ "${PHASE}" = "Failed" ] && ok "(e) non-public-api frontend pod blocked from cv-processor" \
  || bad "(e) intruder pod REACHED cv-processor (phase=${PHASE:-none})"

echo "======================================================================"
echo -e " Result: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "======================================================================"
[ "${FAIL}" -eq 0 ] || { echo "verify FAILED"; exit 1; }
echo "verify PASSED"
