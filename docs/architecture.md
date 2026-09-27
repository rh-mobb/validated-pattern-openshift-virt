# Architecture

This stack adds Azure NetApp Files and Trident CSI on top of an existing ARO HCP cluster. Cluster inventory lives in the [installer architecture](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/).

## Network privacy

**Rule (same as the installer):** traffic this pattern owns must stay on **RFC1918** or **Azure Private Endpoints**. Anything else needs an **approved, documented exception** in the table below **in the same change**.

ANF data plane is VNet-native RFC1918. Volumes get IPs on the delegated subnet. There is **no** Private Endpoint — ANF NFS does not use Private Link for that path, and that is compliant.

Azure Route Server BGP neighbors (`virtualRouterIps`) are also RFC1918. Azure still requires a **Standard public IP** on the Route Server for SDN management; that PIP is an exception below, not a customer BGP listener.

### Compliant (no exception)

| Path | How it stays private |
|------|----------------------|
| ANF NFS | Delegated subnet in the cluster VNet (installer reserved `10.0.3.0/24`). Trident mounts NFSv4.1 to those private IPs. |
| ANF subnet | Empty of NICs, **no NSG** (Azure requirement). Worker→ANF is east-west VNet traffic. |
| Azure Route Server BGP | RFC1918 `virtualRouterIps` on `RouteServerSubnet` (installer reserved `10.0.4.0/26`, no NSG/UDR). Speakers and CUDN stay in the VNet. |

### Approved exceptions

| Path | Why it is not RFC1918 / PE | Why it is allowed | How to tighten |
|------|----------------------------|-------------------|----------------|
| Trident → Azure Resource Manager | Public ARM HTTPS (workload identity) | Azure control plane; Trident must create/delete ANF volumes | ARM Private Link is not in this pattern |
| Azure Route Server Standard public IP | Azure requires a PIP for SDN management of Route Server; not a customer BGP listener | Created with Route Server in this module | None; required by the Azure service |
| Trident / kubevirt-hyperconverged catalog, GitOps git, bgp-cloud-connector source | Public HTTPS | OLM + Argo + OpenShift builds pull payload and git | Private catalog / GHES later; add a row if you keep them public |
| Cluster API / ingress / node outbound | Inherited from the installer cluster | Not created here | See installer [Network privacy](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/#network-privacy) |

Do not add a public IP, public PaaS data plane, or internet listener without a new row here. FSxN / Cloud NetApp Volumes slices must follow the same rule (VPC/VNet RFC1918, documented exceptions).

## Azure (modules/azure)

| Resource | Notes |
|----------|--------|
| Subnet `<cluster>-netapp` | Delegated to `Microsoft.Netapp/volumes` (azurerm spelling; Azure service `Microsoft.NetApp/volumes`). **No NSG.** CIDR from installer `netapp_subnet_prefix` (default `10.0.3.0/24`). NFS is RFC1918 in-VNet, not a Private Endpoint. |
| Subnet `RouteServerSubnet` | Azure-required name, **no NSG, no UDR**, CIDR from installer `route_server_subnet_prefix` (default `10.0.4.0/26`). |
| Public IP + Azure Route Server `<cluster>-routeserver` | Standard PIP (management plane exception). BGP neighbors are RFC1918 `virtualRouterIps`. Apply fails without `bgp_router=true` in `platform.json` `node_pools`. |
| UAMI `<cluster>-bgp` | Custom role: Route Server BGP connections **in the customer RG** only (no NIC write). Federated credential for `openshift-bgp-cloud-connector/openshift-bgp-cloud-connector-controller-manager`. NIC IP forwarding uses installer **`cluster-api-azure`** via `spec.azure.networkInterfaceClientID` (`platform.json` `cluster_api_azure_client_id`). Worker NICs are in the managed RG (RP deny assignment). Blast radius: the operator can act as full CAPI there. Installer [#20](https://github.com/rh-mobb/validated-pattern-aro-hcp/issues/20). |
| bgp-cloud-connector | GitOps in-cluster build from `github.com/openshift/bgp-cloud-connector` commit `2b6ad93989a2adfe4b52d4067f70a782aabd9a11` (kustomize `config/default?ref=`, Shipwright `Build.spec.source.git.revision`, and `BuildRun` name suffix; not OLM until GA). Requires OpenShift Pipelines + Builds for OpenShift (`gitops/operators/openshift-pipelines`, `openshift-builds`). `bgp-from-metadata` is a **sync-wave `4` Job** (not `hook: Sync`) so it finishes before wave `6` `azure-nic-ip-forwarding`. It stamps WI + `BGPCloudConfiguration` `platform: Azure` from `bgp-platform-metadata` (including `networkInterfaceClientID`). Deployment sync-wave `5` so the Job annotates the SA before manager pods admit. If the Deployment already exists (`oc apply -k` ignores waves), the Job `rollout restart`s it and waits until some pod spec has `AZURE_CLIENT_ID` (ImagePullBackOff is fine; the WI webhook only injects at create). **Temporary** DaemonSet `azure-nic-ip-forwarding` (wave 6) sets `enableIPForwarding` on **all worker NICs** so CUDN extra-hop replies from non-speakers are not dropped. Operator only does this for `bgp_router=true` today (Azure Route Server **16 peer** cap). Remove the DS when [bgp-cloud-connector#121](https://github.com/openshift/bgp-cloud-connector/issues/121) ships ([tracking #9](https://github.com/rh-mobb/validated-pattern-openshift-virt/issues/9)). Sample **`BGPRouting` `virt`** (wave 7, `gitops/samples/cudn`) creates namespace `virt` (`cluster-udn: virt`, primary-UDN label at create) and subnet `192.168.100.0/24`. The operator creates `ClusterUserDefinedNetwork` `cluster-udn-virt` and shared `RouteAdvertisements` — do not GitOps a CUDN for this path. Put VMs/pods in `virt`; jump/VNet reach the CUDN IPs, not overlay `10.128.0.0/14`. |
| OpenShift Pipelines | GitOps `gitops/operators/openshift-pipelines`: prerequisite for Builds for OpenShift (`openshift-pipelines-operator`, `redhat-operators`, sync-wave `-4`). |
| Builds for OpenShift | GitOps `gitops/operators/openshift-builds`: Shipwright CRDs + `buildah` `ClusterBuildStrategy` (`openshift-builds-operator`, sync-wave `-3`). |
| NetApp account `<cluster>-anf` | Customer RG |
| Capacity pool `<cluster>-anf-pool` | Flexible, Manual QoS, default 1 TiB, `custom_throughput_mibps` 128. Trident backend must set `defaults.qosType: Manual` (not `serviceLevel: Flexible` — Trident only accepts Standard/Premium/Ultra) and `networkFeatures: Standard` (pools under 4 TiB reject Basic; snapshot clones of Basic golden images fail with `VolumesInSub4TiBPoolsCannotUseBasicNetworking`). |
| Trident operator | Certified `trident-operator`; OperatorGroup is **AllNamespaces** (OwnNamespace is unsupported). `TridentOrchestrator` `cloudProvider: Azure` plus `cloudIdentity` for workload identity. |
| OpenShift Virtualization | GitOps `gitops/operators/cnv`: `kubevirt-hyperconverged` from `redhat-operators` (`stable`) into `openshift-cnv`. HyperConverged `infra`/`workloads` nodePlacement is worker-only (HCP has no masters). Job patches StorageProfile `anf-virt` to RWX Filesystem for live migration. StorageClass annotation `storageclass.kubevirt.io/is-default-virt-class` — cluster default StorageClass stays `managed-csi`. |
| GitOps controller | `gitops/base/gitops-controller-rbac.yaml` binds OpenShift `cluster-admin` to `openshift-gitops-argocd-application-controller` (`virt-stack-gitops-controller`, sync-wave `-1` inside `virt-stack`). `scripts/gitops-bootstrap.sh` also `oc apply`s it **before** planting the Application so the first sync can create operator Subscriptions, Shipwright Builds, and Trident resources. Default OpenShift GitOps is get/list/watch plus a few API groups — not enough for this overlay. The installer baseline keeps the limited controller (ESO ignores ServiceAccount drift). |
| `trident-from-metadata` Job | Namespaced Role in `trident` for ServiceAccounts / `TridentBackendConfig`. **ClusterRole** for cluster-scoped `TridentOrchestrator` and `get` on CRDs (the Job `oc get crd` / `oc patch tridentorchestrator`). |
| UAMI `<cluster>-trident` | Custom role on the RG; federated credential for `trident/trident-controller` |

Trident provisions ANF **volumes**. They are not in Terraform state. `scripts/trident-cleanup.sh` must run before `terraform destroy` (it also deletes `BGPCloudConfiguration` so the operator can drop Azure BGP connections).

## Consume

- Canonical: slim `terraform/` root, second state, `platform_json` from installer `make cluster.<name>.platform`.
- In-tree: `module "netapp" { source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>" }` in the deployer’s root. GitOps + cleanup stay outside the module.

Do not create ANF volumes in Terraform. Do not steal the cluster default StorageClass (`managed-csi`). OpenShift Virtualization uses `anf-virt` via the virt-class annotation and StorageProfile RWX, not by changing the cluster default.
