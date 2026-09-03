# Consume modes

## Second IaC run (canonical)

```bash
# installer
make cluster.my-cluster.apply
make cluster.my-cluster.kubeconfig
make cluster.my-cluster.external-auth
make cluster.my-cluster.bootstrap
make cluster.my-cluster.platform

# this repo
cp -r clusters/aro-virt clusters/my-cluster
# set platform_json in terraform.tfvars, or:
ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.apply
make cluster.aro-virt.bootstrap
```

Destroy reverse: `make cluster.my-cluster.destroy` here (cleanup then terraform), then installer destroy.

GitOps: this overlay binds `cluster-admin` to `openshift-gitops-argocd-application-controller` (the installer keeps the default least-privilege GitOps ClusterRole). The `trident-from-metadata` Job uses a ClusterRole for cluster-scoped `TridentOrchestrator` and CRD `get`.

## In-tree module

```hcl
module "netapp" {
  source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>"

  cluster_name        = var.cluster_name
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  vnet_name           = module.network.vnet_name
  subnet_prefix       = "10.0.3.0/24"
  oidc_issuer_url     = module.cluster.oidc_issuer_url
}
```

Pin `ref` to a tag. Still install sibling `gitops/` (Argo Application: Trident + OpenShift Virtualization) and run `trident-cleanup.sh` before destroying the module. The ARO HCP installer root does **not** call this module.
