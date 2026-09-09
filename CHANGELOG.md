# Changelog

Operator-visible history. Update **only at commit time** from `git diff --cached` vs `HEAD`. Same rule as `validated-pattern-aro-hcp`.

## Unreleased

### Added

- Azure Route Server (`RouteServerSubnet` + Standard PIP) and BGP UAMI in `modules/azure`, consumed from installer `platform.json` (`route_server_subnet_prefix`, `bgp_router` pools, `cluster_api_azure_client_id`)
- GitOps for in-cluster [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) (`gitops/operators/bgp-cloud-connector`): BuildConfig, WI Job, `BGPCloudConfiguration` `platform: Azure`
- `bgp-platform-metadata` ConfigMap from sibling bootstrap; cleanup deletes `BGPCloudConfiguration` before Terraform destroy

### Changed

- Trident backend sets `networkFeatures: Standard` so ANF volumes and snapshot clones work on capacity pools under 4 TiB
- HyperConverged `resourceRequirements.storageWorkloads` so CDI importers have enough memory for qcow2 HTTP imports
- Point consume/README at the installer [Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/) e2e (KUBECONFIG_PATH, TF_VAR unset, leftover ANF volumes on destroy)

### Fixed

- `bgp-from-metadata` always restarts the manager when the Deployment already exists (WI webhook only injects `AZURE_CLIENT_ID` at pod create; skip-if-empty-env raced ImagePullBackOff)
- Bind `cluster-admin` to the OpenShift GitOps application controller (`rwx-storage-gitops-controller`, sync-wave `-1`) so Argo can create Trident ServiceAccounts, `VolumeSnapshotClass`, `TridentOrchestrator`, and `HyperConverged`
- Grant the `trident-from-metadata` Job a ClusterRole for cluster-scoped `TridentOrchestrator` and CRD `get` (namespaced Role cannot `oc get`/`oc patch` those)

### Added

- GitOps for OpenShift Virtualization (`kubevirt-hyperconverged` in `openshift-cnv`): worker-only HyperConverged, Job patches StorageProfile `anf-virt` to RWX Filesystem, StorageClass virt-class annotation (cluster default stays `managed-csi`)
- Example profile `clusters/aro-virt` matching the installer virt-ready directory
- Azure NetApp Files Terraform module (`modules/azure`): delegated subnet, Flexible/Manual capacity pool, Trident workload identity
- Slim `terraform/` root that ingests installer `platform.json`
- GitOps for certified Trident operator, StorageClass `anf-virt`, and backend Job
- `make cluster.<name>.{apply,bootstrap,cleanup,destroy}` with standalone `scripts/trident-cleanup.sh`
