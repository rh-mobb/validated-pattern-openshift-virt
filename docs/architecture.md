# Architecture

This stack adds Azure NetApp Files and Trident CSI on top of an existing ARO HCP cluster. Cluster inventory lives in the [installer architecture](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/).

## Azure (modules/azure)

| Resource | Notes |
|----------|--------|
| Subnet `<cluster>-netapp` | Delegated to `Microsoft.Netapp/volumes` (azurerm spelling; Azure service `Microsoft.NetApp/volumes`). **No NSG.** CIDR from installer `netapp_subnet_prefix` (default `10.0.3.0/24`). |
| NetApp account `<cluster>-anf` | Customer RG |
| Capacity pool `<cluster>-anf-pool` | Flexible, Manual QoS, default 1 TiB, `custom_throughput_mibps` 128. Trident backend must set `defaults.qosType: Manual` (not `serviceLevel: Flexible` — Trident only accepts Standard/Premium/Ultra). |
| Trident operator | Certified `trident-operator`; OperatorGroup is **AllNamespaces** (OwnNamespace is unsupported). `TridentOrchestrator` `cloudProvider: Azure` plus `cloudIdentity` for workload identity. |
| UAMI `<cluster>-trident` | Custom role on the RG; federated credential for `trident/trident-controller` |

Trident provisions ANF **volumes**. They are not in Terraform state. `scripts/trident-cleanup.sh` must run before `terraform destroy`.

## Consume

- Canonical: slim `terraform/` root, second state, `platform_json` from installer `make cluster.<name>.platform`.
- In-tree: `module "netapp" { source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>" }` in the deployer’s root. GitOps + cleanup stay outside the module.

Do not create ANF volumes in Terraform. Do not steal the cluster default StorageClass (`managed-csi`).
