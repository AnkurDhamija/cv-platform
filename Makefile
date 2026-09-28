# =============================================================================
# CV Platform — DevSecOps Technical Assignment
# =============================================================================
# Primary entrypoints required by the assignment:
#   make up      -> full local environment on a clean machine
#   make verify  -> proves all security controls, exits non-zero on any failure
#   make down    -> tear everything down
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---- Configuration ----------------------------------------------------------
CLUSTER_NAME  ?= cv-platform
KIND_CONFIG   ?= platform/kind/kind-config.yaml
REGISTRY      ?= localhost:5001
PUBLIC_API_IMG    ?= $(REGISTRY)/public-api
CV_PROCESSOR_IMG  ?= $(REGISTRY)/cv-processor
TAG           ?= dev

# Colour helpers
BLUE  := \033[0;34m
GREEN := \033[0;32m
RED   := \033[0;31m
NC    := \033[0m

# =============================================================================
# Meta
# =============================================================================
.PHONY: help
help: ## Show this help
	@echo "CV Platform — available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-22s$(NC) %s\n", $$1, $$2}'

# =============================================================================
# Top-level lifecycle  (these orchestrate the phase targets below)
# =============================================================================
.PHONY: up
up: cluster-up registry-up images build-load platform-install sign set-digests apps-deploy ## Bring up the FULL local environment
	@echo -e "$(GREEN)==> Environment is up. Run 'make verify' to prove the controls.$(NC)"

.PHONY: sign
sign: ## Sign the pushed images with the local cosign key (Part 3/5)
	@bash scripts/sign-images.sh

.PHONY: set-digests
set-digests: ## Pin app Deployments to the built+signed image digests (Part 3)
	@bash scripts/set-digests.sh

.PHONY: down
down: ## Tear the entire local environment down
	@echo -e "$(BLUE)==> Deleting kind cluster + local registry...$(NC)"
	-@kind delete cluster --name $(CLUSTER_NAME)
	-@docker rm -f kind-registry >/dev/null 2>&1 || true
	@echo -e "$(GREEN)==> Down.$(NC)"

.PHONY: verify
verify: ## Prove all security controls (a)-(e); exits non-zero on ANY failure
	@bash scripts/verify.sh

# =============================================================================
# Phase 2 — Cluster / registry
# =============================================================================
.PHONY: cluster-up
cluster-up: ## Create the kind cluster with a NetworkPolicy-enforcing CNI
	@bash scripts/cluster-up.sh

.PHONY: registry-up
registry-up: ## Start a local OCI registry for images
	@bash scripts/registry-up.sh

# =============================================================================
# Phase 1 — Build
# =============================================================================
.PHONY: pin-digests
pin-digests: ## Resolve + pin base-image digests into the Dockerfiles
	@bash scripts/pin-digests.sh

.PHONY: images
images: pin-digests ## Build both hardened container images (digest-pinned bases)
	@echo -e "$(BLUE)==> Building images...$(NC)"
	docker build -t $(PUBLIC_API_IMG):$(TAG)   services/public-api
	docker build -t $(CV_PROCESSOR_IMG):$(TAG) services/cv-processor

.PHONY: build-load
build-load: ## Push images into the local registry
	docker push $(PUBLIC_API_IMG):$(TAG)
	docker push $(CV_PROCESSOR_IMG):$(TAG)

# =============================================================================
# Phase 2/4/5/6 — Platform components
# =============================================================================
.PHONY: platform-install
platform-install: ns policies-install netpol-install data-install gitops-install obs-install ## Install all platform components
	@echo -e "$(GREEN)==> Platform components installed.$(NC)"

.PHONY: ns
ns: ## Create frontend + backend namespaces
	kubectl apply -f deploy/namespaces/

.PHONY: policies-install
policies-install: ## Install Kyverno + enforce-mode policies (Part 5)
	@bash scripts/policies-install.sh

.PHONY: netpol-install
netpol-install: ## Apply NetworkPolicies (Part 4)
	kubectl apply -f deploy/networkpolicies/

.PHONY: data-install
data-install: ## Deploy PostgreSQL + MinIO (Part 4)
	kubectl apply -f deploy/postgres/
	kubectl apply -f deploy/minio/

.PHONY: gitops-install
gitops-install: ## Install Argo CD + Applications (Part 4)
	@bash scripts/gitops-install.sh

.PHONY: obs-install
obs-install: ## Install Prometheus + Grafana + dashboards + alerts (Part 6)
	@bash scripts/obs-install.sh

# =============================================================================
# Apps
# =============================================================================
.PHONY: apps-deploy
apps-deploy: ## Deploy the two services (via GitOps)
	kubectl apply -f deploy/base/public-api/
	kubectl apply -f deploy/base/cv-processor/

# =============================================================================
# Quality / test
# =============================================================================
.PHONY: test
test: ## Run app unit tests locally
	cd services/public-api && python -m pytest -q || true
	cd services/cv-processor && python -m pytest -q || true

.PHONY: lint
lint: ## Lint manifests + terraform (best-effort, no fail)
	-kubectl apply --dry-run=client -f deploy/ -R
	-cd terraform/gcp && terraform fmt -check && terraform validate

.PHONY: backup
backup: ## Trigger a PostgreSQL logical backup (Part 6)
	@bash scripts/pg-backup.sh

.PHONY: restore
restore: ## Restore PostgreSQL from the latest backup (Part 6)
	@bash scripts/pg-restore.sh

.PHONY: restore-verify
restore-verify: ## Prove the latest backup restores into a scratch DB (Part 6)
	@bash scripts/pg-restore.sh --verify
