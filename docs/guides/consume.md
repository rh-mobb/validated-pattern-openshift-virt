# Consume modes

Canonical **two-checkout e2e** (installer apply → kubeconfig → external-auth → bootstrap → platform → this apply → this bootstrap, plus verify and destroy): [installer Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/).

## Second IaC run (canonical)

```bash
# installer
make cluster.aro-virt.apply
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

GitOps: this overlay binds `cluster-admin` to `openshift-gitops-argocd-application-controller` (the installer keeps the default least-privilege GitOps ClusterRole). The `trident-from-metadata` Job uses a ClusterRole for cluster-scoped `TridentOrchestrator` and CRD `get`. BGP operator is an in-cluster build of [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) `main`; `bgp-from-metadata` stamps workload identity (sibling BGP MI) and `BGPCloudConfiguration` including `networkInterfaceClientID` (installer `cluster-api-azure`). Same Argo CD instance as the installer `cluster-config` Application.

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
