# CV Platform — Secure CV Processing MVP

![CI/CD](https://github.com/AnkurDhamija/cv-platform/actions/workflows/cv-platform.yaml/badge.svg)


> DevSecOps technical assignment. A two-service CV-processing platform whose
> focus is the **secure delivery platform** around it — IaC, GitOps, supply-chain
> security, network segmentation, policy enforcement, and observability — not the
> application itself.

---

## What this is

A minimal but genuinely working MVP of a CV-processing system, deployed on a
local Kubernetes cluster with the full production-style security platform around
it. The same platform is also deployed to a live, private GKE cluster on GCP (provisioned by the Terraform in `terraform/gcp/`), with keyless GCS access via Workload Identity.

| Service        | Namespace  | Role                                                       |
| -------------- | ---------- | ---------------------------------------------------------- |
| `public-api`   | `frontend` | Public entry point. Accepts CV uploads, returns a CV ID.   |
| `cv-processor` | `backend`  | Internal only. Extracts PDF metadata, owns all data storage.|

**App behaviour (public-api):**

| Endpoint            | Behaviour                                                              |
| ------------------- | --------------------------------------------------------------------- |
| `POST /cvs`         | Upload PDF + name + email; validates type/size; forwards; returns CV ID|
| `GET /cvs/{id}`     | Returns stored metadata for that CV                                    |
| `DELETE /cvs/{id}`  | Deletes the CV file + all metadata (GDPR erasure)                      |
| `GET /health`       | Health check                                                          |

`cv-processor` extracts page count + first ~500 characters, stores the file in
object storage (MinIO locally / GCS on GCP) and metadata in PostgreSQL.

---

## Quick start

### Prerequisites

| Tool       | Version (tested) | Purpose                       |
| ---------- | ---------------- | ----------------------------- |
| Docker     | ≥ 24             | Build images, run kind        |
| kind       | ≥ 0.23           | Local Kubernetes cluster      |
| kubectl    | ≥ 1.29           | Cluster interaction           |
| cosign     | ≥ 2.2            | Verify image signatures       |
| terraform  | ≥ 1.7            | GCP IaC (applied + validated)     |
| make       | any              | Task runner                   |

### Run it

```bash
make up       # brings up cluster, registry, platform, apps on a clean machine
make verify   # PROVES every security control; exits non-zero if any check fails
make down     # tears it all down
```

`make verify` demonstrates, and hard-fails on any of:

- **(a)** an unsigned image is rejected by admission control
- **(b)** a pod running as root / with a writable root filesystem is rejected
- **(c)** `public-api` **can** reach `cv-processor`
- **(d)** `cv-processor` **cannot** reach the internet
- **(e)** a pod in `frontend` other than `public-api` **cannot** reach `cv-processor`

### Example requests

```bash
# Upload a CV
curl -F "file=@sample.pdf" -F "name=Ada Lovelace" -F "email=ada@example.com" \
  http://localhost:8080/cvs
# -> {"id": "…"}

# Fetch metadata
curl http://localhost:8080/cvs/<id>

# GDPR erasure
curl -X DELETE http://localhost:8080/cvs/<id>
```

---

## Repository layout

```
.
├── README.md
├── Makefile                     # make up / verify / down
├── services/                    # the two apps + hardened Dockerfiles
│   ├── public-api/
│   └── cv-processor/
├── deploy/                      # Kubernetes manifests (GitOps source of truth)
│   ├── namespaces/              # frontend + backend
│   ├── base/                    # Deployments/Services (hardened securityContext)
│   ├── networkpolicies/         # default-deny + explicit allows
│   ├── policies/kyverno/        # signature + security-context enforcement
│   ├── postgres/  minio/        # stateful backends
│   ├── secrets/                 # sealed secrets (no plaintext creds)
│   ├── helm/                    # per-service charts (frontend/backend): HPA, PDB, probes, per-env values
│   ├── argocd/                  # Argo CD Applications (app-of-apps; GKE under argocd/gke/)
│   └── observability/           # Prometheus, Grafana, SLOs, alerts
├── platform/kind/               # cluster + CNI bootstrap
├── terraform/gcp/               # GKE, Artifact Registry, GCS, IAM, WIF (target)
├── .github/workflows/           # secure CI: scan, sign, SBOM, deploy-by-digest
├── scripts/                     # make helpers + verify.sh
├── docs/
│   ├── ARCHITECTURE_AND_THREATS.md
│   ├── COMPLIANCE.md
│   ├── COST.md
│   ├── RUNBOOK.md
│   └── PLAN.md
└── adr/                         # architecture decision records
```

---

## Implementation status

<!-- Filled in as phases complete -->

| Area                              | Status      | Notes |
| --------------------------------- | ----------- | ----- |
| App MVP (both services)           | ✅ done     | Flask; 6 unit tests pass offline |
| Container hardening (Part 2)      | ✅ done     | Distroless nonroot, digest-pinned, multi-stage, no shell |
| Local platform / kind (Part 4)    | _✅ done_   |       |
| NetworkPolicies (Part 4)          | _✅ done_   |       |
| Policy enforcement (Part 5)       | ✅ done     | Kyverno enforce: signatures + security context |
| Secure CI/CD (Part 3)             | ✅ done     | SAST/SCA/secret/IaC/image scan, gates, SBOM, keyless sign, WIF |
| GitOps + secrets (Part 4)         | ✅ done     | Argo CD app-of-apps + Sealed Secrets (ESO on GKE) |
| Observability + SLOs (Part 6)     | ✅ done     | Prom+Grafana, dashboard, 2 SLOs+alerts, PG backup/restore |
| GCP Terraform (Part 4)     | ✅ done     | Private GKE, WIF, bucket IAM (cv-proc yes / public-api no) |
| Docs + ADRs (Parts 1,6,7,8)       | ✅ done     | Architecture+threats, compliance, cost, runbooks, plan, 4 ADRs |
| `make verify` gate (a)–(e)        | ✅ done     | Single script, exits non-zero on any failure |

---

## Known limitations

Honest account of what is fully implemented vs. simplified:

- **Local signature verification runs in Audit mode on kind; Enforced on GKE.**
  In-cluster Kyverno cannot reach the host-local registry (`localhost:5001`) to fetch
  the cosign signature (in a pod, `localhost` is the pod itself), so on kind the
  `verify-image-signatures` policy is set to Audit — it reports violations without
  blocking deployments, and `make verify` check (a) is therefore not asserted locally.
  The same policy is **Enforced on GKE** against Artifact Registry with keyless cosign
  (see `docs/EVIDENCE.md`). Local checks (b)-(e) pass.

- **GCP Terraform is applied and live.** Private GKE, Artifact Registry, the GCS bucket, and least-privilege Workload Identity were applied to a real project; `cv-processor` reads/writes GCS keylessly while `pubapi-gsa` is denied (evidence in `docs/EVIDENCE.md`). Run `terraform destroy` to stop billing.


- **Base-image and action pinning are maintained by a resolver + Dependabot.**
  Committed digests/SHAs carry version comments; the CI `pinning-check` job and
  `scripts/pin-digests.sh` enforce/refresh them. On first clone, run
  `make pin-digests` so the base digests are live for your environment.
- **Local signing uses a generated cosign key**, not keyless OIDC (impossible on
  a laptop). CI/GKE use keyless signing. The two `verify-images` policy variants
  express the same intent; keep them in sync.
- **Local bring-up applies manifests directly** for a hermetic `make up`; Argo CD
  Applications define the same desired state and are the source of truth in cloud
  (register with `make gitops-install` once the repo is pushed).
- **GDPR erasure does not purge existing backups** before their retention expiry;
  we rely on bounded retention + a re-deletion step in the restore runbook. A
  production erasure ledger is described but not built.
- **Service-to-service authn** between `public-api` and `cv-processor` is network-
  restricted (NetworkPolicy) but not yet mTLS/token-authenticated — noted as the
  top residual risk in the threat model.
- **`cv-processor` metrics share the API port**; monitoring scrape is namespace-
  restricted. A separate metrics port would be marginally stricter.

## Time spent

Approximately **9–10 hours**, weighted toward the platform (infra/GitOps, CI
security, policy, observability) per the scoring rubric, and deliberately light on
application code.

## AI-usage note

Per TalentAdore's guidance, this project was built AI-first.

**Tools used:** Claude Code (Anthropic) as the primary agent for scaffolding and
iteration — it drove the Terraform, Helm charts, Kubernetes manifests, the GitHub
Actions pipeline, and the Markdown docs.

**How it was integrated:**
- *Scaffold, then harden.* AI generated first drafts of the IaC, charts, and CI
  workflow; every security-relevant choice (Workload Identity least privilege,
  keyless signing, Kyverno policies, NetworkPolicy design, digest pinning) was
  reviewed, adjusted, and justified by me — see the ADRs and
  `docs/ARCHITECTURE_AND_THREATS.md`.
- *Verify, don't trust.* AI output was validated with `make verify` (controls
  a–e), `helm lint`/`template`, `terraform validate`, and the CI security gates
  (Semgrep, pip-audit, Trivy, Checkov, Gitleaks) rather than accepted as-is. A
  real SSRF finding raised by SAST was fixed at the root (strict UUID validation
  plus a regression test), not suppressed.
- *Debugging partner.* The GKE Dataplane V2 / NodeLocal DNS NetworkPolicy problem
  (ADR 0003) was diagnosed interactively — the AI proposed hypotheses, I tested
  them on the live cluster and chose the ingress-only resolution.

The architecture, threat model, trade-offs, and verification approach are mine;
AI accelerated the boilerplate and acted as a pair.
