# Cost estimate (GCP target)

**Scope:** the target GKE deployment in `europe-west1`, low but production-shaped
traffic (a few requests/sec, tens of GB of CVs). On-demand list prices, rounded;
indicative, not a quote.

## Assumptions
- Regional (HA) GKE, 2× `e2-standard-2` nodes.
- Metadata on Cloud SQL `db-custom-1-3840` (1 vCPU / 3.75 GB), zonal.
- ~50 GB CVs in GCS Standard, modest egress.
- One external HTTPS load balancer.
- ~10–20 GB logs/metrics per month.

## Estimated monthly cost

| Item | Assumption | ~ USD/mo |
| --- | --- | ---: |
| GKE cluster management | 1 regional cluster (@ ~$0.10/hr) | 74 |
| Compute (nodes) | 2× e2-standard-2 on-demand | 98 |
| Cloud SQL (PostgreSQL) | db-custom-1-3840, zonal, 20 GB SSD | 55 |
| Object storage (GCS) | 50 GB Standard + operations | 3 |
| Egress / networking | HTTPS LB + modest egress | 25 |
| Artifact Registry | a few GB of images | 2 |
| Logging & Monitoring | ~15 GB beyond free tier | 8 |
| **Total** | | **~265** |

## Main cost drivers
1. **Compute** (nodes) and **GKE management fee** — together ~65% of the bill.
2. **Cloud SQL** — the largest single managed component.
3. **Egress / load balancing** — grows with real traffic and CV downloads.

## Optimisation levers
- **Committed-use discounts / Spot nodes** for the node pool → 30–60% off compute
  (Spot suits stateless `public-api`; keep `cv-processor`/data on standard).
- **Right-size + autoscale**: cluster autoscaler + HPA; `e2-medium` may suffice
  at low traffic, cutting node cost roughly in half.
- **Zonal instead of regional** GKE/SQL in non-prod → removes the HA premium.
- **GCS lifecycle** already deletes CVs at 30 days; add Nearline for any
  longer-lived, rarely-read data.
- **Log routing**: exclude noisy logs, sample metrics to stay near free tiers.

## Trade-off: cost vs reliability/security
The estimate keeps HA where it protects users (regional GKE, LB) and economises
where it doesn't (zonal SQL, small nodes). Pushing cost lower — single-zone
everything, Spot for stateful workloads, dropping the managed DB — would raise the
risk of downtime and data loss and weaken the security posture (e.g. losing
managed patching/backups). The chosen point spends ~$265/mo to keep the
user-facing path highly available and the data tier managed and backed up; I'd
revisit node sizing and commitments first, and only trade away HA in
non-production.
