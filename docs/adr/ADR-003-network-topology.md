# ADR-003: Network Topology — Hub-and-Spoke vs Full Mesh

**Date:** 2024-04-02  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Network Engineering, Security, On-premises Infrastructure  

---

## Context

With a multi-account/subscription model established (ADR-001), we needed to decide how VPCs (AWS) and VNets (Azure) connect to each other and to on-premises networks. The organisation has:

- ~12 workload VPCs/VNets at initial launch, expected to grow to 30+ over 3 years
- On-premises data centres in 2 locations connected via MPLS
- A requirement that all internet egress is inspectable (energy sector compliance)
- Cross-cloud traffic between AWS and Azure workloads (e.g., Azure AD identity + AWS compute)
- Latency-sensitive workloads that cannot route through unnecessary hops

The primary topologies evaluated:

1. **Full mesh VPC peering / VNet peering**
2. **Hub-and-spoke with AWS Transit Gateway + Azure vWAN**
3. **Hybrid: hub-and-spoke within each cloud, direct peering for latency-sensitive cross-cloud paths**

---

## Decision

**Option 2: Hub-and-spoke using AWS Transit Gateway and Azure Virtual WAN.**

A centralised connectivity hub in each cloud provider, connected to each other via site-to-site VPN (with ExpressRoute/Direct Connect as a future upgrade path). All inter-VPC/VNet traffic routes through the hub. Internet egress routes through a dedicated Egress VPC/VNet with inspection.

---

## Rationale

### Why not full mesh peering?

VPC/VNet peering is non-transitive. With N networks, full mesh requires N*(N-1)/2 peering connections. At 30 networks, that is 435 peering connections to manage. More critically:

- No transitive routing — traffic between spoke A and spoke B must be explicitly peered or routed through a transit point anyway
- No centralised policy enforcement — each peering pair requires its own route table and security group rules
- Network Security Groups / Security Group rules sprawl rapidly
- Adding a new VPC requires updating every existing VPC it needs to reach

At 12 initial VPCs this is painful. At 30+ it becomes unmanageable.

### Why Transit Gateway + Azure vWAN?

**AWS Transit Gateway:**
- Single attachment point per VPC — adding a new spoke is one Terraform resource
- Centralised route tables allow policy-based routing (e.g., dev spokes cannot route to prod spokes)
- Supports VPN and Direct Connect attachments natively
- Enables centralised egress inspection by routing 0.0.0.0/0 to an inspection VPC

**Azure Virtual WAN:**
- Managed hub eliminates the need to build and maintain transit VMs
- Integrates with Azure Firewall natively in the hub
- Supports branch connectivity (SD-WAN / VPN) alongside VNet connections
- Global reach across Azure regions without managing inter-hub peering manually

**Cross-cloud connectivity:**
Both hubs connect via site-to-site IPsec VPN as the baseline, providing encrypted cross-cloud transit. This is not the lowest latency path but provides adequate throughput for identity federation traffic, log forwarding, and non-latency-sensitive workloads.

### Trade-offs accepted

| Trade-off | Mitigation |
|---|---|
| Transit Gateway costs per attachment + data processing | Accepted; cost modelled at ~$400/month at target scale, justified by operational savings |
| Single hub is a potential bottleneck | Transit Gateway is a managed service with AWS-backed SLA; bandwidth limits are well above projected usage |
| Cross-cloud VPN latency (~15ms additional) | Latency-sensitive workloads are placed entirely within one cloud |
| vWAN is more opaque than self-managed NVAs | Accepted; operational simplicity outweighs customisation flexibility for this use case |

---

## Network Segmentation Model

```
AWS Transit Gateway Route Tables:
├── prod-rt          → prod spokes only + shared services
├── non-prod-rt      → dev + staging spokes + shared services (no prod)
├── shared-rt        → shared services VPC (reachable from all)
└── inspection-rt    → egress inspection VPC

Azure vWAN Route Tables:
├── prod-rt          → prod VNets + shared services
├── non-prod-rt      → dev + staging VNets
└── default-rt       → internet via Azure Firewall
```

Explicit deny: Production route tables do not contain routes to non-production CIDRs. This is enforced at the Transit Gateway / vWAN routing layer, not just at security group level.

---

## CIDR Allocation

| Block | Purpose |
|---|---|
| 10.0.0.0/8 | All cloud CIDRs (AWS + Azure) |
| 10.0.0.0/12 | AWS workloads |
| 10.16.0.0/12 | Azure workloads |
| 10.32.0.0/12 | Reserved for future expansion |
| 10.48.0.0/16 | Shared services (both clouds) |
| 172.16.0.0/12 | On-premises (existing, not modified) |

No CIDR overlap between AWS, Azure, and on-premises. Verified before deployment.

---

## Consequences

- All new VPCs/VNets must be attached to the respective hub at creation — enforced via SCP/Policy
- CIDR allocation for new accounts comes from a centralised IPAM (AWS VPC IPAM)
- Egress inspection is mandatory for all internet-bound traffic — no direct internet gateways in spoke VPCs
- On-premises connectivity upgrades (Direct Connect / ExpressRoute) are in the roadmap but not in scope for initial launch

---

## Alternatives Considered and Rejected

**Option 1 (full mesh):** Rejected. Does not scale; no centralised policy enforcement point.

**Option 3 (hybrid with direct cross-cloud peering):** Evaluated for latency-sensitive paths. Deferred — no workloads currently require sub-10ms cross-cloud latency. Can be revisited if workload requirements change.
