# ADR 0002 — Distroless base images, pinned by digest, signed and deployed by digest

- **Status:** Accepted
- **Date:** 2026-09-26

## Context
The application is a small part of the grade; the platform's supply-chain posture
is not. We need container images that minimise attack surface and a deploy path
where what runs is exactly what CI built and signed. Choices span the base image
(distroless vs slim vs Alpine vs scratch) and the reference style (tag vs digest).

## Decision
Build **multi-stage** images on **`gcr.io/distroless/python3:nonroot`**, with the
base images **pinned by digest** (maintained by `scripts/pin-digests.sh` +
Dependabot, verified in CI). Images are **keyless-signed** in CI and **deployed by
digest**; a moved or re-pushed tag can never change what runs.

## Alternatives considered
- **`python:3.11-slim` / Alpine:** ship a shell + package manager (bigger attack
  surface, easier post-exploitation); Alpine's musl also risks subtle Python wheel
  issues. Rejected for the runtime image (slim is used only as the *builder*).
- **`scratch` with a fully static build:** smallest possible, but painful for
  CPython (must bundle interpreter + shared libs); high effort for marginal gain
  over distroless. Better suited to Go. Rejected given the time budget.
- **Tag-based references:** simplest, but tags are mutable — incompatible with
  a verifiable supply chain. Rejected.

## Consequences
- **Positive:** no shell/package manager in the runtime image (harder to exploit,
  smaller CVE surface); non-root by construction (UID 65532); digest pinning +
  signing + deploy-by-digest give end-to-end integrity from build to admission.
- **Negative / trade-offs:** no shell means no `kubectl exec` debugging into the
  app container — we rely on logs/metrics and ephemeral debug containers instead.
  Digest pinning needs upkeep (Dependabot handles it) or bases go stale. Local
  builds can't resolve digests offline, so the resolver runs at build time on a
  networked machine/CI.
