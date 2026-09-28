#!/usr/bin/env bash
# scripts/obs-install.sh — install kube-prometheus-stack (Prometheus + Grafana +
# Alertmanager) and apply the ServiceMonitors, SLO rules and dashboard.
set -euo pipefail

NS="monitoring"

echo "==> ensuring monitoring namespace (labelled for NetworkPolicy scrape)"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${NS}" kubernetes.io/metadata.name="${NS}" --overwrite >/dev/null

echo "==> installing kube-prometheus-stack via Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${NS}" \
  -f deploy/observability/values-kube-prometheus-stack.yaml \
  --wait --timeout 10m

echo "==> applying ServiceMonitors, SLO rules, dashboard"
kubectl apply -f deploy/observability/servicemonitors.yaml
kubectl apply -f deploy/observability/prometheus-rules.yaml
kubectl apply -f deploy/observability/grafana-dashboard.yaml

echo "==> observability ready. Grafana:"
echo "    kubectl -n ${NS} port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "    user admin / pass: kubectl -n ${NS} get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d"
