# ADR 0003 — Ingress-only NetworkPolicies on GKE (egress enforced on kind)

- **Status:** Accepted
- **Date:** 2026-09-27
- **Deciders:** Platform/Security (candidate), for discussion with the TalentAdore team

## Context

The brief (Part 4, "Network security") asks for **strict NetworkPolicies** that,
among other things, **block cv-processor from reaching the internet** and stop any
frontend pod other than `public-api` from reaching `cv-processor`. The natural
expression of "no internet" is an **egress default-deny** in the `backend`
namespace, with narrow allow-list exceptions for DNS, the API server, PostgreSQL,
and the Google APIs VIP (for GCS over Workload Identity).

That model works and is proven on the **local kind** cluster, whose CNI evaluates
standard `NetworkPolicy` egress rules against pod and service IPs directly.

On the **live GKE cluster** the same egress default-deny broke all pod networking,
including DNS. Two GKE-specific facts combine to cause this:

1. **Dataplane V2 (managed Cilium).** GKE Dataplane V2 implements
   `NetworkPolicy` via Cilium. Cilium does **not** match cluster-internal or host
   IPs through `ipBlock` CIDRs — an `ipBlock` egress allow for the kube-dns
   ClusterIP or the node IP simply does not take effect the way it does on a
   textbook CNI.
2. **NodeLocal DNSCache.** Pods resolve DNS via a node-local cache
   (link-local `169.254.20.10`) that forwards to kube-dns (`10.30.0.10`). An
   egress default-deny drops the pod→node-local-DNS hop, and it cannot be
   re-allowed with an `ipBlock` for the reasons above.

The Cilium-native fix (`CiliumNetworkPolicy` with `toEntities: host / kube-apiserver`,
or an FQDN/`toServices` egress policy) is unavailable: the `CiliumNetworkPolicy`
CRD is **not exposed** on GKE Dataplane V2 (`kubectl` returns
`no matches for kind "CiliumNetworkPolicy" in version "cilium.io/v2"`). We verified
this on the live cluster with a labelled test pod, which showed
`RESOLVE: connection timed out` the moment egress default-deny was applied.

## Decision

On **GKE**, enforce **ingress-only** NetworkPolicies:

- `default-deny-ingress` in both `frontend` and `backend`.
- `public-api` accepts ingress only from the ingress path.
- `cv-processor` accepts ingress **only** from `public-api` (namespace + pod
  selector) on `:8081`.
- `postgres` accepts ingress only from `cv-processor` on `:5432`.

On **kind**, keep the **full ingress + egress default-deny** model (including the
"cv-processor cannot reach the internet" egress rule), and let `make verify`
prove control (d) there.

Restricting **cv-processor egress to the internet on GKE** is achieved with a
**platform control instead of a NetworkPolicy**: the node pool has **no external
IP** and egress to Google APIs uses **Private Google Access** (restricted VIP
`199.36.153.4/30`). There is no NAT/egress path to the public internet for the
workload to use, so "no open internet" holds by construction, and the policy layer
is left to do what it does reliably on GKE — east-west segmentation.

## Alternatives considered

1. **Egress default-deny on GKE via `ipBlock` allow-lists.** Rejected — does not
   work under Dataplane V2/NodeLocal DNS (the root cause above). Pursuing it cost
   real debugging time and produced only broken DNS.
2. **`CiliumNetworkPolicy` with `toEntities` / FQDN egress.** The *correct* GKE-
   native tool, but the CRD is not exposed on Dataplane V2, so it is not an option
   on this cluster without a different networking mode.
3. **Switch the cluster off Dataplane V2** to a CNI where `ipBlock` egress works.
   Rejected — a large, cluster-wide change that trades away eBPF dataplane
   benefits to satisfy one policy expression; disproportionate for the goal.
4. **Cloud NAT + FQDN egress firewall.** A production-grade way to bound egress,
   but adds infrastructure and cost beyond the exercise; noted as the production
   path (see Consequences).

## Consequences

- **Positive:** East-west segmentation — the security property the threat model
  cares about most (a compromised `public-api` cannot pivot to storage; no other
  frontend pod can reach `cv-processor`) — is enforced on GKE and provable. The
  "no internet egress" guarantee is *stronger* than a NetworkPolicy because it is
  physical (no external IP + restricted VIP), not just a policy a future edit could
  weaken.
- **Negative / residual risk:** On GKE the guarantee that *"cv-processor cannot
  initiate arbitrary outbound"* rests on the node/VPC egress design rather than a
  namespace-scoped egress policy. If a future node pool were given a public IP or
  Cloud NAT, that guarantee would silently weaken. Mitigation: an Org Policy /
  firewall guardrail denying public egress, asserted in IaC.
- **Production path:** enforce egress with a **Cloud NAT + FQDN-based egress
  firewall** (or a service mesh with egress control), which restores an explicit,
  auditable egress allow-list on GKE without fighting Dataplane V2.
- **Consistency cost:** the local and cloud NetworkPolicy sets differ. This is
  documented here and in `docs/EVIDENCE.md` so a reviewer is not surprised by the
  divergence.
