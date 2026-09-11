# Consume modes

Canonical **two-checkout e2e** (installer jump-key → apply → kubeconfig → external-auth → bootstrap → platform → this apply → this bootstrap, plus verify and destroy): [installer Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/). Agent done-when: [`clusters/aro-virt/AGENTS.md`](../../clusters/aro-virt/AGENTS.md).

## Second IaC run (canonical)

```bash
# installer
make cluster.aro-virt.jump-key             # then jump_ssh_source_prefix = operator /32
make cluster.aro-virt.apply                # includes np-virt (no virt-pool target)
make cluster.aro-virt.kubeconfig
make cluster.aro-virt.external-auth
make cluster.aro-virt.bootstrap
make cluster.aro-virt.platform

# this repo — kubeconfig is the installer's, not this checkout's .kube/config
export ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp
export ARO_HCP_PROFILE=aro-virt
export KUBECONFIG_PATH="${ARO_HCP_ROOT}/.kube/config"
export KUBECONFIG="${KUBECONFIG_PATH}"
# unset TF_VAR_* in this shell (same rule as the installer)
ARO_HCP_ROOT="${ARO_HCP_ROOT}" ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.apply
make cluster.aro-virt.bootstrap
```

Destroy reverse: `make cluster.aro-virt.destroy` here (BGP CR drain + ANF cleanup then terraform; leftover ANF volumes block the pool — delete them and retry). Then installer destroy.

GitOps: `make cluster.aro-virt.bootstrap` pre-applies `virt-stack-gitops-controller` (`cluster-admin` on `openshift-gitops-argocd-application-controller`) before the `virt-stack` Application — the binding also stays at sync-wave `-1` inside that App. Metadata Jobs (`trident-from-metadata`, `bgp-from-metadata`) are **sync-wave `4` resources**, not `hook: Sync` hooks, so wave `6` (`azure-nic-ip-forwarding`) waits for the Job ConfigMap. The Trident Job uses a ClusterRole for cluster-scoped `TridentOrchestrator` and CRD `get`. BGP operator is an in-cluster build of [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) pinned to commit `2b6ad93989a2adfe4b52d4067f70a782aabd9a11` (`gitops/operators/bgp-cloud-connector` kustomize `config/default?ref=` and BuildConfig `spec.source.git.ref` must stay in lockstep); `bgp-from-metadata` stamps workload identity (sibling BGP MI) and `BGPCloudConfiguration` including `networkInterfaceClientID` (installer `cluster-api-azure`). Sample `BGPRouting` `virt` (`192.168.100.0/24`, namespace `virt`) is in `gitops/samples/cudn`; the operator creates the CUDN. Same Argo CD instance as the installer `cluster-config` Application.

## In-tree module

```hcl
module "netapp" {
  source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>"

  cluster_name        = var.cluster_name
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  vnet_name           = module.network.vnet_name
  subnet_prefix                = "10.0.3.0/24"
  route_server_subnet_prefix   = "10.0.4.0/26"
  bgp_router_pool_names        = ["np-virt"]
  oidc_issuer_url              = module.cluster.oidc_issuer_url
  network_interface_client_id  = module.identities.cluster_api_azure_client_id
}
```

Pin `ref` to a tag. Still install sibling `gitops/` (Argo Application: Trident + OpenShift Virtualization) and run `trident-cleanup.sh` before destroying the module. The ARO HCP installer root does **not** call this module.
