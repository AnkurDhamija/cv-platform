# Secrets — no plaintext credentials in Git

The `cv-processor` database credential (and the object-store credential) are
**never** committed in plaintext. Two mechanisms, one per environment:

## Local (kind) — Sealed Secrets
`scripts/secrets-seal.sh` (run by `make up`) installs the Bitnami Sealed Secrets
controller, generates random credentials, and encrypts them with the
controller's public key via `kubeseal`. Only the **encrypted** `SealedSecret`
is written to disk (`deploy/secrets/generated/`, git-ignored). The controller
decrypts them in-cluster into the `cv-db-credentials` / `cv-object-credentials`
Secrets consumed by Postgres, MinIO and cv-processor.

A committed `SealedSecret` is safe to store in Git because it can only be
decrypted by the specific controller that holds the private key. In this repo we
generate them per-cluster for reproducibility rather than committing them.

## GKE — External Secrets Operator + GCP Secret Manager
In cloud, the credential lives in **GCP Secret Manager**. External Secrets
Operator (running as a Workload-Identity-bound KSA) reads it and projects it into
a Kubernetes Secret. No credential is stored in Git or in a static key at all;
rotation happens in Secret Manager. See `docs/ARCHITECTURE_AND_THREATS.md`.

## What must never happen
- No `Secret` with a `data:`/`stringData:` plaintext value committed here.
- `.gitignore` blocks `secrets.yaml`, `*.key`, `.env*`; only `*sealed*.yaml`
  is allowed through.
