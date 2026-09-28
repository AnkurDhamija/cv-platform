#!/usr/bin/env bash
# scripts/gitops-install.sh
# Installs Argo CD + Sealed Secrets, seals the credentials, and (if a git
# remote exists) registers the app-of-apps so Argo owns the desired state.
set -euo pipefail

ARGO_VERSION="v2.12.3"

echo "==> installing Argo CD ${ARGO_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=240s

# --- credentials (sealed) ----------------------------------------------------
bash scripts/secrets-seal.sh

# --- register the app-of-apps if we have a remote ----------------------------
REPO_URL="$(git config --get remote.origin.url 2>/dev/null || true)"
if [ -n "${REPO_URL}" ]; then
  echo "==> registering Argo CD app-of-apps against ${REPO_URL}"
  tmp="$(mktemp -d)"
  cp deploy/argocd/root-app.yaml deploy/argocd/apps/*.yaml "${tmp}/"
  sed -i "s#__REPO_URL__#${REPO_URL}#g" "${tmp}"/*.yaml
  kubectl apply -f "${tmp}/root-app.yaml"
  echo "==> Argo CD will reconcile the platform from Git."
else
  echo "!! no git remote configured; skipping Argo registration."
  echo "   Local bring-up still applies manifests directly (make platform-install/apps-deploy)."
  echo "   Push the repo and re-run 'make gitops-install' to enable GitOps."
fi
echo "==> gitops-install done"
