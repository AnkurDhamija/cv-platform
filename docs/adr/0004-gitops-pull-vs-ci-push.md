# ADR 0004 — Pull-based GitOps (Argo CD) as the deploy model, not CI-push

- **Status:** Accepted
- **Date:** 2026-09-27
- **Deciders:** Platform/Security (candidate), for discussion with the TalentAdore team

## Context

The brief (Part 4) requires a **GitOps controller** and deploy-by-digest, and
(Part 3) a pipeline where every change to `main` produces a **signed, trustworthy
artifact**. There are two common ways to get a new image running on the cluster:

- **CI-push:** the CI job holds cluster credentials and runs `kubectl apply` /
  `helm upgrade` directly against the API server at the end of the pipeline.
- **Pull-based GitOps:** CI only builds, signs, and **writes the new digest into
  Git** (the Helm `values-<env>.yaml`); an in-cluster controller (Argo CD)
  observes Git and reconciles the cluster to match.

The exercise runs a private GKE cluster and a hardened CI pipeline with keyless
signing and Workload Identity Federation, so the choice materially affects the
platform's blast radius and auditability.

## Decision

Use **pull-based GitOps with Argo CD** as the deployment mechanism. The CI
pipeline's responsibility ends at Git:

1. Build → SBOM → scan → **keyless cosign sign** → push to Artifact Registry.
2. Resolve the immutable `sha256` digest and **commit it into
   `deploy/helm/<svc>/values-dev.yaml`** (`[skip ci]`).
3. **Argo CD** (app-of-apps: a root app owning `frontend` + `backend`) detects the
   commit and syncs the cluster to the new digest, with `selfHeal` and `prune`.

CI is granted **no standing deploy credentials to the cluster**; its WIF identity
can read Artifact Registry digests, nothing more. A human **approval gate**
(GitHub Environment `dev`, required reviewer) sits in front of the digest-writing
step so a person authorises what enters the deployed state.

## Alternatives considered

1. **CI-push (`helm upgrade` from the runner).** Simpler and one fewer moving
   part, and fine for a single environment. Rejected as the primary model because
   it requires the CI runner to hold cluster-admin-ish credentials, widening the
   blast radius of a compromised runner or a malicious PR (exactly threat #2 in
   `ARCHITECTURE_AND_THREATS.md`); it also makes Git and cluster state drift
   silently, with no controller to correct manual `kubectl` edits.
2. **Flux instead of Argo CD.** Equivalent pull-based model and a valid choice.
   Argo CD was chosen for its app-of-apps ergonomics and the visual sync/health
   tree, which doubles as reviewer evidence (`docs/EVIDENCE.md`). Not a
   correctness difference.
3. **Argo CD Image Updater (controller writes the digest).** Removes the CI
   commit-back step, but moves registry-watching and write authority into the
   cluster and weakens the "Git is the only way in, behind an approval gate"
   property. Deferred; the CI commit-back keeps the human gate explicit.

## Consequences

- **Positive — smaller blast radius:** the CI runner never holds cluster deploy
  credentials, directly shrinking the attack surface the threat model flags for a
  malicious pull/merge. The cluster's only inbound change path is a signed commit
  to Git that Argo pulls.
- **Positive — drift control & auditability:** `selfHeal` continuously reconciles,
  so manual `kubectl` edits are reverted; Git history is the deploy audit log; a
  rollback is `git revert`.
- **Positive — verifiable trust chain:** deploy-by-digest + Kyverno signature
  enforcement means only a **signed** image matching the committed digest can run;
  the tag is never trusted.
- **Negative — indirection & latency:** a deploy is now "commit → controller
  reconcile", not an immediate imperative apply, so feedback is a few seconds
  slower and requires understanding Argo's sync state. Accepted; the visibility
  and security gains outweigh it.
- **Negative — HPA/GitOps interaction:** because an HPA owns replica counts, the
  Deployment omits `spec.replicas` and the Argo Applications set
  `ignoreDifferences` on `/spec/replicas`, so autoscaling and `selfHeal` do not
  fight. Documented in the charts (see ADR-adjacent Helm values).
- **Operational note:** the `[skip ci]` on the digest commit prevents an infinite
  build loop; the approval gate means the pull model still has a human decision
  point despite being automated end to end.
