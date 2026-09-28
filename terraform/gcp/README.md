# GCP target platform (Terraform) — modular

Reusable modules composed by a thin root, driven per-environment by tfvars.

## Layout
```
terraform/gcp/
  main.tf            # root: instantiates the modules and wires them together
  variables.tf       # root inputs (environment, project_id, region, ...)
  locals.tf          # per-env naming (suffix/name/labels) from `environment`
  outputs.tf         # re-exports module outputs
  versions.tf        # providers + (optional) GCS backend
  moved.tf           # preserves already-applied WIF state across the refactor
  modules/
    network/   # VPC, subnet (+ flow logs), egress-deny firewall
    gke/       # private GKE, WI, Dataplane V2, shielded, auto repair/upgrade
    storage/   # GCS CV bucket + Artifact Registry
    iam/       # cvproc GSA (bucket) / pubapi GSA (no storage) + WI bindings
    wif/       # GitHub Actions Workload Identity Federation
  environments/
    dev.tfvars  test.tfvars  prod.tfvars
    dev.gcs.tfbackend  test.gcs.tfbackend  prod.gcs.tfbackend
```

## Per-environment usage
Same code for every env; only the `-var-file` changes.
```bash
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars     # billable

# test / prod
terraform plan  -var-file=environments/test.tfvars
terraform plan  -var-file=environments/prod.tfvars
```

`environment` drives naming: dev keeps names unchanged (suffix ""), test/prod
get `-test`/`-prod` so they never collide (project-per-env still recommended).

## Remote state (optional)
Uncomment `backend "gcs" {}` in versions.tf, create the bucket once, then:
```bash
terraform init -reconfigure -backend-config=environments/dev.gcs.tfbackend
```
