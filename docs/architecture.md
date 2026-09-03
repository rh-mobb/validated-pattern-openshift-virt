# Architecture

This stack adds Azure NetApp Files and Trident CSI on top of an existing ARO HCP cluster. Cluster inventory lives in the [installer architecture](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/).

## Network privacy

**Rule (same as the installer):** traffic this pattern owns must stay on **RFC1918** or **Azure Private Endpoints**. Anything else needs an **approved, documented exception** in the table below **in the same change**.

ANF data plane is VNet-native RFC1918. Volumes get IPs on the delegated subnet. There is **no** Private Endpoint — ANF NFS does not use Private Link for that path, and that is compliant.

### Compliant (no exception)

| Path | How it stays private |
|------|----------------------|
| ANF NFS | Delegated subnet in the cluster VNet (installer reserved `10.0.3.0/24`). Trident mounts NFSv4.1 to those private IPs. |
| ANF subnet | Empty of NICs, **no NSG** (Azure requirement). Worker→ANF is east-west VNet traffic. |

### Approved exceptions

| Path | Why it is not RFC1918 / PE | Why it is allowed | How to tighten |
|------|----------------------------|-------------------|----------------|
| Trident → Azure Resource Manager | Public ARM HTTPS (workload identity) | Azure control plane; Trident must create/delete ANF volumes | ARM Private Link is not in this pattern |
| Trident operator catalog / GitOps git | Public HTTPS | OLM + Argo pull payload and git | Private catalog / GHES later; add a row if you keep them public |
| Cluster API / ingress / node outbound | Inherited from the installer cluster | Not created here | See installer [Network privacy](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/#network-privacy) |

Do not add a public IP, public PaaS data plane, or internet listener without a new row here. FSxN / Cloud NetApp Volumes slices must follow the same rule (VPC/VNet RFC1918, documented exceptions).

## Azure (modules/azure)

| Resource | Notes |
|----------|--------|
| Subnet `<cluster>-netapp` | Delegated to `Microsoft.Netapp/volumes` (azurerm spelling; Azure service `Microsoft.NetApp/volumes`). **No NSG.** CIDR from installer `netapp_subnet_prefix` (default `10.0.3.0/24`). NFS is RFC1918 in-VNet, not a Private Endpoint. |
| NetApp account `<cluster>-anf` | Customer RG |
| Capacity pool `<cluster>-anf-pool` | Flexible, Manual QoS, default 1 TiB, `custom_throughput_mibps` 128. Trident backend must set `defaults.qosType: Manual` (not `serviceLevel: Flexible` — Trident only accepts Standard/Premium/Ultra). |
| Trident operator | Certified `trident-operator`; OperatorGroup is **AllNamespaces** (OwnNamespace is unsupported). `TridentOrchestrator` `cloudProvider: Azure` plus `cloudIdentity` for workload identity. |
| UAMI `<cluster>-trident` | Custom role on the RG; federated credential for `trident/trident-controller` |

Trident provisions ANF **volumes**. They are not in Terraform state. `scripts/trident-cleanup.sh` must run before `terraform destroy`.

## Consume

- Canonical: slim `terraform/` root, second state, `platform_json` from installer `make cluster.<name>.platform`.
- In-tree: `module "netapp" { source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>" }` in the deployer’s root. GitOps + cleanup stay outside the module.

Do not create ANF volumes in Terraform. Do not steal the cluster default StorageClass (`managed-csi`).
