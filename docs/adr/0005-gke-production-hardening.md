# 0005 — GKE production hardening & configuration model

## Context
The stack must be reproducible, cheap to run in dev, and hardened for prod — with
one set of modules driven per environment by a var-file.

## Decision
**Remote, isolated state**
- State lives in **GCS** (`backend "gcs" {}` in `versions.tf`), initialised per
  environment with `-backend-config=environments/<env>.gcs.tfbackend`
  (bucket `<project>-tfstate`, prefix `cv-platform/<env>`). dev/test/prod never
  share state.

**Everything important is tfvars-driven (nothing hardcoded in the .tf files)**
- Node **machine_type**, **disk_size_gb**, **min_node_count**/**max_node_count**
  (autoscaling), **release_channel**, and **deletion_protection** are all
  variables, set in `terraform.tfvars` / `environments/<env>.tfvars`. Changing the
  cluster size or shape is a var-file edit, not a code change.

**Implemented in Terraform**
- **API enablement** (`apis.tf`) so `apply` works on a clean project.
- **Node autoscaling** in place of a fixed count.
- **deletion_protection** var — false in dev, true in prod.
- **ESO identity as IaC** — the Secret Manager `cv-db-credentials` container,
  `eso-gsa`, its `secretmanager.secretAccessor`, and both Workload Identity
  bindings live in `modules/iam` (the secret *value* stays out-of-band, never
  in tfstate).

**Env-gated / deferred (documented, not applied to dev)**
- **Control-plane exposure** — dev `master_authorized_cidr = 0.0.0.0/0`; **prod must**
  set specific admin CIDRs (VPN/bastion) or `enable_private_endpoint = true` + IAP.
- **CMEK** — Cloud KMS key for the CV bucket + DB backups.
- **Node oauth_scopes** — narrow from `cloud-platform` (recreates the pool).
- **Binary Authorization** — defence-in-depth alongside Kyverno (ADR 0001).

## Consequences
Dev stays reproducible and cheap; prod applies the same modules with a hardened
`-var-file`. Deferred items are tracked here and in `docs/PLAN.md`.
