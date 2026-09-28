# Runbooks

Concrete, actionable procedures. Each assumes on-call has `kubectl` + repo access.

---

## Runbook 1 — Critical CVE in a sub-dependency (Security)

**Trigger:** an advisory (or the CI SCA/image gate) flags a HIGH/CRITICAL CVE in
a transitive dependency of `public-api` or `cv-processor`.

### 1. Identify
- Confirm the affected package + version and whether it's reachable:
  ```bash
  # Which image/layer? Use the SBOM already produced by CI.
  gh run download -n sbom-cv-processor && grep -i "<package>" sbom-cv-processor.json
  # Or scan locally:
  trivy image --severity HIGH,CRITICAL ghcr.io/<org>/cv-processor@<digest>
  ```
- Determine exposure: is the vulnerable code path used? Is the pod internet-
  reachable? (`cv-processor` is not — this lowers, not removes, urgency.)

### 2. Patch
- Bump the dependency (or base image) and let Dependabot's PR or a manual PR carry
  the fix. Pin the new version in `requirements.txt` / refresh the base digest
  (`make pin-digests`).
- Push to a branch → CI re-runs SAST/SCA/image scan; the gate must go green.

### 3. Verify
- Confirm the CVE is gone from the rebuilt image:
  ```bash
  trivy image --severity HIGH,CRITICAL <new-digest>   # expect: no findings
  ```
- Confirm the image is signed by CI and admission still accepts it (staging).

### 4. Deploy
- Merge to `main` → CI builds, signs, and publishes the new digest.
- GitOps: Argo CD syncs the new digest; or update the manifest digest and let
  Argo reconcile. Watch rollout:
  ```bash
  kubectl -n backend rollout status deploy/cv-processor
  ```
- **Evidence to capture:** the advisory ID, the fixing PR/commit, the before/after
  Trivy output, the signed new digest, and the Rekor entry. File in the security
  ticket for audit (ISO A.8.28 / A.8.8).

### 5. Follow-up
- If exploited-in-the-wild, check access logs/metrics for indicators over the
  exposure window. Add a regression note. Confirm SLA (e.g. CRITICAL patched
  ≤ 48 h) was met.

---

## Runbook 2 — POST /cvs error rate jumps to 30% (Reliability)

**Trigger:** alert `PublicAPIAvailabilityFastBurn` fires; dashboard shows ~30%
5xx on `POST /cvs`.

### 1. Detect / assess
- Open the **CV Platform** Grafana dashboard: is it `public-api` 5xx, or
  `cv-processor`/DB/object-store errors surfacing as 502s? Check the
  error-ratio and latency panels and `up{}` for both services.
  ```bash
  kubectl -n frontend logs -l app=public-api --tail=100
  kubectl -n backend  logs -l app=cv-processor --tail=100
  ```

### 2. Triage (localise the fault)
- **Deploy-correlated?** Did the spike start at a rollout?
  ```bash
  kubectl -n backend rollout history deploy/cv-processor
  ```
- **Dependency down?** `cv-processor` → Postgres/MinIO failing (readiness red,
  connection errors in logs)?
- **Saturation?** CPU/memory at limits, restarts/OOMKills?
  ```bash
  kubectl -n backend get pods -o wide ; kubectl top pods -n backend
  ```

### 3. Mitigate (stop the bleeding first)
- **If a bad deploy:** roll back immediately.
  ```bash
  kubectl -n backend rollout undo deploy/cv-processor
  # GitOps: revert the digest-bump commit; Argo self-heals to the good digest.
  ```
- **If a dependency:** restart/scale the failing backend; verify PVC/health.
- **If saturation:** scale out (`kubectl -n frontend scale deploy/public-api
  --replicas=4`) and/or raise limits; confirm HPA.
- Confirm error ratio recovers on the dashboard; the burn alert should clear.

### 4. Follow-up
- Root-cause with logs + the change that triggered it; add a test/guardrail so it
  can't recur (e.g. a canary, a readiness gate, a schema migration check).
- Write a short blameless postmortem: timeline, detection→mitigation time,
  contributing factors, corrective actions with owners.
- If the error budget was materially burned, freeze risky changes until it
  recovers.
