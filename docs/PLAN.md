# First 90 days

If this were the real platform, how I'd take it from this MVP to production.
Framed as outcomes, not just tasks.

## Days 1–30 — Learn, harden the foundations, close the biggest gaps
- **Understand context:** meet the team, map real data flows, confirm the threat
  model against reality, review existing incidents and compliance obligations.
- **Make the pipeline the source of truth:** enforce branch protection
  (required reviews, `CODEOWNERS`, required status checks), so no single actor can
  merge to `main`. Verify fork-PR safety end to end.
- **Secrets & identity for real:** move all secrets to a managed store (GCP Secret
  Manager + External Secrets); confirm no static cloud keys exist anywhere;
  audit IAM for least privilege (especially that `public-api` truly has no data
  access).
- **Close the top residual risks** from the threat model: add
  service-to-service authn (mesh mTLS or signed tokens) between `public-api` and
  `cv-processor`; add rate limiting on `POST /cvs`.
- **Deliverable:** a risk register with owners and a 60/90-day remediation plan.

## Days 31–60 — Reliability, observability, and operational muscle
- **SLOs that page correctly:** validate the availability + latency SLOs against
  real traffic, tune burn-rate thresholds, wire Alertmanager to the on-call
  rotation, run a game-day.
- **Prove backup/restore:** schedule automated PostgreSQL backups to encrypted
  object storage and run a **restore drill** (the `--verify` path) on a cadence;
  document RPO/RTO.
- **Progressive delivery:** introduce canary or blue/green for `cv-processor` so
  a bad deploy is caught before full rollout (directly addresses Runbook 2).
- **Supply chain to SLSA:** add provenance attestation verification at admission;
  track SBOMs centrally; enable Binary Authorization on GKE as defence in depth.
- **Deliverable:** signed-off runbooks, tested restore, on-call handbook.

## Days 61–90 — Scale, compliance, and paying down debt
- **Compliance evidence automation:** turn the ISO 27001 control mapping into
  continuously-collected evidence (policy reports, scan history, access logs);
  prep for an internal audit.
- **GDPR erasure hardening:** implement the erasure ledger so restores re-apply
  deletions; document the data-retention lifecycle end to end.
- **Cost & capacity:** apply committed-use/Spot where safe, right-size nodes and
  DB, set budgets/alerts; publish the cost model.
- **Resilience testing:** lightweight chaos (kill pods, sever a dependency) to
  confirm the NetworkPolicies, probes, and alerts behave as designed.
- **Deliverable:** a production-readiness review and a prioritised backlog for the
  next quarter.

**Throughout:** keep everything in Git and GitOps-reconciled, prefer boring and
reversible changes, and measure detection→mitigation time as the health metric
for the platform team.
