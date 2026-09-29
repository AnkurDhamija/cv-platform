# ADR 0001 — Kyverno for admission policy (signatures + security context)

- **Status:** Accepted
- **Date:** 2026-09-26

## Context
We must enforce, at admission time, that (a) only images signed by our CI
identity run, and (b) every workload meets a hardened security context. The
control must work identically on local kind and on GKE, and be provable by
`make verify`. Candidate approaches: **Kyverno**, **OPA Gatekeeper**, and (for
signatures on GKE only) **Binary Authorization**.

## Decision
Use **Kyverno** as the single admission engine for both signature verification
and security-context enforcement, in **enforce** mode, in both environments. On
GKE, **Binary Authorization** is planned as additional defence in depth (deferred — see ADR 0005).

## Alternatives considered
- **OPA Gatekeeper:** powerful and CNCF-graduated, but Rego is a steeper language
  and image-signature verification is less first-class than Kyverno's built-in
  `verifyImages`. More moving parts for the same outcome.
- **Binary Authorization only:** excellent managed signature enforcement, but
  GKE-specific (no local parity) and doesn't cover security-context policy, so
  we'd still need a second engine.

## Consequences
- **Positive:** one policy language and engine for both controls; local/cloud
  parity so `make verify` proves the real thing; `verifyImages` gives keyless
  signature checks and digest mutation in a few lines.
- **Negative / trade-offs:** local keyless signing is impossible, so locally we
  verify against a generated cosign key while CI/GKE use keyless OIDC — two policy
  variants to keep in sync. Kyverno's admission webhook is now in the critical
  path (mitigated by its HA install and `failurePolicy` tuning).
