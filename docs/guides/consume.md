# Consume modes

Canonical **two-checkout e2e** (installer jump-key → apply → kubeconfig → external-auth → bootstrap → platform → this apply → this bootstrap, plus verify and destroy): [installer Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/). Agent done-when: [`clusters/aro-virt/AGENTS.md`](https://github.com/rh-mobb/validated-pattern-openshift-virt/blob/main/clusters/aro-virt/AGENTS.md).

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

## Storage cleanup and full teardown

Use the attachment's Make targets so the managed pool ARM ID in per-profile state binds
Azure operations to the correct subscription, resource group, ANF account and pool:

```bash
make cluster.aro-virt.anf-preview
make cluster.aro-virt.destroy
```

Preview lists volumes without changing Kubernetes or Azure. Destroy removes the
GitOps Application, disables CNV common boot-image imports, waits for DataImportCrons
to disappear, drains BGP, and deletes `anf-virt` PVCs/PVs. Stop VMs, Pods and their
owning controllers first; cleanup reports remaining Pod consumers and refuses to
delete their claims. Custom DataImportCrons must also be stopped before drain.
After the consumer check, cleanup also removes DataVolumes identified by the exact
owner UIDs of this storage class's PVCs, before deleting the claims. This prevents
retained catalog DataVolumes from recreating PVCs after DataImportCrons disappear.
Deletion uses an API-enforced UID precondition, so a replacement DataVolume is
protected even if it appears after inventory. A changed UID or a retained
VM/VM-pool controller blocks deletion.
API, authorization, import-drain or PVC-deletion errors stop teardown.

The Azure gate waits up to 600 seconds for CSI to remove volumes while the Trident
backend and identities still exist. If volumes remain, it stops before Terraform
destroy. A missing PVC is not proof that the remaining volume's data is disposable.
For an explicitly confirmed full teardown, review the preview and supply the exact
`resource-group/account/pool` confirmation printed by it:

```bash
ANF_DELETE_CONFIRM=aro-virt-rg/aro-virt-anf/aro-virt-anf-pool \
  make cluster.aro-virt.destroy
```

Confirmed cleanup deletes only volume IDs inside that exact Terraform-managed pool,
then waits for an empty Azure inventory. It does not force-break replication or
remove Kubernetes finalizers. Only after the pool is empty does it remove the
Trident backend and run Terraform destroy of the pool, account, subnet and identities.
Read-only scope and account validation runs before Kubernetes drain. The active Azure
subscription must match the managed pool ID; inventory failures
are errors, never an empty-pool result. Azure CLI, Python 3, jq, Terraform and oc are
required for the complete workflow.

For recovery after a previous partial destroy has already removed Trident or its
identity, use the Azure-only gate after reviewing its inventory:

```bash
make cluster.aro-virt.anf-preview
ANF_DELETE_CONFIRM=aro-virt-rg/aro-virt-anf/aro-virt-anf-pool \
  make cluster.aro-virt.anf-cleanup
# Then retry the sibling destroy, after any remaining Kubernetes drain issues are resolved.
```

`anf-cleanup` defaults to waiting without direct deletion unless the confirmation
matches. `ANF_VOLUME_WAIT_SECONDS` controls each wait window (default 600, maximum
7200; zero performs immediate checks). Azure errors or volumes still present after
the final wait cause a nonzero exit. Scope comes from the exact `module.azure.azurerm_netapp_pool.this` ARM ID in state,
so recovery also works when a failed destroy has already removed all outputs. Invalid
or ambiguous state stops cleanup. If state proves there is no managed ANF pool left,
the workflow skips storage drain and lets Terraform finish other resources; it does
not claim to have inventoried Azure or delete any untracked pools. There is no fallback
to guessed resource names or subscription-wide deletion.

Destroy reverse: `make cluster.aro-virt.destroy` here (Kubernetes drain, Azure volume gate, backend removal, then Terraform). Then installer destroy.

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

## Classic MIWI attachment notes

Use an installer contract with `machine_api_client_id` for managed-RG NIC operations.
Keep the BGP identity scoped to Route Server operations and reuse installer Argo CD.

The GitOps layout separates shared resources from platform and cluster placement:

- `gitops/base`: shared Trident, CNV, BGP and sample CUDN resources.
- `gitops/overlays/azure-hcp`: forces CNV operators onto workers, preserving HCP behavior.
- `gitops/overlays/azure-classic`: uses the operators' default control-plane placement.
- `gitops/overlays/azure`: compatibility alias for `azure-hcp`.
- `gitops/profiles/aro-classic-virt`: example Classic overlay selecting `pool=np-virt`
  for virt workloads and tolerating `workload=virtualization:NoSchedule`. HCO infra
  remains on untainted workers. Adjust this profile for your actual labels and taints.

`GITOPS_PLATFORM` accepts `classic` or `hcp` (default `hcp` for existing callers).
`GITOPS_PATH` overrides the selected directory for a committed cluster profile; the
profile's Kustomization chooses its platform base. Bootstrap validates the local path
and uses it both in dry-run and in the Argo Application. It does not infer the platform
from the presence of worker nodes. Platform identity selection stays in Terraform.

```bash
# Generic Classic placement, without this example's pool selectors:
GITOPS_PLATFORM=classic make cluster.aro-classic-virt.bootstrap

# Example tainted virt pool; test an already-pushed branch:
GITOPS_PLATFORM=classic \
GITOPS_PATH=gitops/profiles/aro-classic-virt \
GITOPS_REVISION=feat/classic-gitops-overlays \
make cluster.aro-classic-virt.bootstrap
```

Create the attachment's local tfvars/state and set the installer kubeconfig as above
before bootstrap. `GITOPS_REPO` can point at a fork; Argo must be able to read the
chosen repository and revision. Copy the example profile into your own committed
profile when labels, taints or placement differ.

The shared NIC-forwarding DaemonSet selects Linux workers and tolerates pool taints.
The shared BGP BuildConfig uses only ConfigChange: OpenShift discards an empty
ImageChange trigger, which otherwise causes persistent Argo drift.

When migrating an Application that already has inline `spec.source.kustomize.patches`,
first represent every override in the selected Git profile and compare the render.
Then remove the old inline patches. Bootstrap does not discard existing inline
customizations automatically. The 2026-10-19 Classic test originally used those
patches before moving to the maintained profile.

Established BGP and an active effective route do not prove external CUDN connectivity.
A Classic worker host can select OVN policy-routing table 1053 instead of the Azure
path. Use a separate private VNet host for the Route Server dataplane check; do not
interpret that worker-host probe's result as an external routing result.
