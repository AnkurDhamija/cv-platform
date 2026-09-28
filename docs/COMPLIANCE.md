# Compliance

## ISO/IEC 27001:2022 — Annex A control mapping

Four controls we implement, with the evidence an auditor would ask for and where
it lives in this repo.

### A.8.9 — Configuration management
**Implemented:** Hardened, declarative baselines for every workload — non-root,
read-only root filesystem, dropped capabilities, no privilege escalation,
seccomp `RuntimeDefault`, pinned image digests. Enforced at admission by Kyverno,
so drift cannot be deployed. All configuration is in Git (IaC), peer-reviewed and
scanned.
**Auditor evidence:** the enforce-mode `ClusterPolicy`
`require-hardened-security-context`; a rejected-deployment log from `make verify`;
Checkov/Trivy-config CI run output; the deployment manifests themselves.
**Where:** `deploy/policies/kyverno/`, `deploy/base/`, `.github/workflows/cv-platform.yaml`.

### A.8.28 — Secure coding
**Implemented:** SAST (Semgrep), dependency scanning (Trivy/SCA), secret scanning
across full git history (Gitleaks), and IaC scanning run on every PR and gate the
build. Input validation in `public-api` (content-type by magic bytes, size,
email).
**Auditor evidence:** CI run logs showing the scan jobs and their pass/fail
gates; the branch-protection required-checks configuration; the pipeline
definition.
**Where:** `.github/workflows/cv-platform.yaml` (jobs `sast`, `sca`, `secret-scan`,
`iac-scan`), `services/public-api/app/main.py`.

### A.8.24 — Use of cryptography
**Implemented:** Keyless container signing (Cosign/Sigstore) with signatures
verified at admission; TLS in transit; encryption at rest for object storage
(GCS default/CMEK) and secrets sealed with asymmetric crypto (Sealed Secrets) or
held in GCP Secret Manager. A documented control over *which* signer is trusted
(our CI identity only).
**Auditor evidence:** the `verify-image-signatures` policy naming the exact
issuer/subject; a Rekor transparency-log entry for a signed image; the bucket
encryption configuration in Terraform.
**Where:** `deploy/policies/kyverno/verify-images-keyless.yaml`,
`.github/workflows/cv-platform.yaml` (sign step), `terraform/gcp/storage.tf`.

### A.8.16 — Monitoring activities
**Implemented:** Prometheus scrapes both services; two SLOs (availability,
latency) with multi-window burn-rate alerts routed through Alertmanager; a
Grafana dashboard of service health. Alerts give early warning of availability or
latency degradation.
**Auditor evidence:** the `PrometheusRule` with alert definitions; a screenshot
or export of the Grafana dashboard; Alertmanager routing config.
**Where:** `deploy/observability/`.

> Related controls also covered in substance: **A.5.15 / A.8.2** (least-privilege
> access — Workload Identity, `public-api` has no storage rights),
> **A.8.15** (logging), **A.5.23** (secure use of cloud services).

## GDPR — technical measures for CV personal data

A CV plus name and email is personal data; some CVs contain special-category
data. Technical measures implemented or specified:

| Requirement | Measure | Where |
| --- | --- | --- |
| **Right to erasure (Art. 17)** | `DELETE /cvs/{id}` removes the metadata row **and** the object together; GDPR erasure is a first-class endpoint, not a manual process. | `services/*/app/main.py` |
| **Storage limitation (Art. 5(1)(e))** | Object bucket has a 30-day lifecycle-delete rule; retention is enforced by the platform, not left to policy. | `terraform/gcp/storage.tf` |
| **Integrity & confidentiality (Art. 5(1)(f))** | Encryption at rest (GCS/CMEK, PG), TLS in transit, least-privilege access (only `cv-processor` reaches data), network isolation of the data tier. | `terraform/gcp/`, `deploy/networkpolicies/` |
| **Backups vs erasure tension** | Backups are retained on a bounded window and encrypted; an erasure request is recorded so that if a backup is restored, previously-erased records are re-deleted as part of the restore runbook. | `docs/RUNBOOK.md`, `scripts/pg-*.sh` |
| **Access logging / accountability (Art. 5(2))** | GCS data-access audit logs + application request metrics/logs provide an access trail; who-accessed-what is auditable. | `deploy/observability/`, GCP audit logs |
| **Data minimisation (Art. 5(1)(c))** | `cv-processor` extracts only page count + a short text snippet; it does not derive or store more than needed. | `services/cv-processor/app/main.py` |

**Known gap (honest):** a full erasure that also purges the value from existing
backups before their natural expiry is not implemented; we rely on bounded backup
retention + a re-deletion step in the restore runbook. A production system should
add an erasure ledger checked on every restore.
