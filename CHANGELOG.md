# Changelog

Operator-visible history. Update **only at commit time** from `git diff --cached` vs `HEAD`. Same rule as `validated-pattern-aro-hcp`.

## Unreleased

### Guarded ANF teardown

- Add `.anf-preview` and `.anf-cleanup` targets scoped to the managed ANF pool in per-profile Terraform state, including recovery when failed destroy removed outputs.
- Require explicit resource-group/account/pool confirmation for direct leftover-volume deletion, and verify an empty Azure pool before removing the Trident backend or Terraform-managed identities.
- Disable common boot-image imports, reject active Pod consumers, and stop teardown on Kubernetes or Azure drain errors.
- Cover deletion scoping, confirmation, partial-destroy retries and Make ordering with mocked tests; document the workflow and recovery targets.

### Classic and HCP GitOps overlays

- Add shared GitOps base consumption through `azure-classic` and `azure-hcp` overlays; retain `azure` as an HCP compatibility alias.
- Add a Classic virt example profile with pool placement and taint tolerations, selected through bootstrap `GITOPS_PLATFORM` / `GITOPS_PATH` and branch revision controls.
- Accept Classic `machine_api_client_id` for NIC operations while retaining HCP `cluster_api_azure_client_id` support.
- Restrict the NIC-forwarding agent to workers and remove the empty BGP image-change trigger that caused Argo drift.
- Document Classic attachment requirements and validation, with real overlay-render checks in the test gate.

### Added

- Azure Route Server (`RouteServerSubnet` + Standard PIP) and BGP UAMI in `modules/azure`, consumed from installer `platform.json` (`route_server_subnet_prefix`, `bgp_router` pools, `cluster_api_azure_client_id`)
- GitOps for in-cluster [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) (`gitops/operators/bgp-cloud-connector`): BuildConfig, WI Job, `BGPCloudConfiguration` `platform: Azure`
- Temporary DaemonSet `azure-nic-ip-forwarding` so extra-hop CUDN replies from non-speakers are not dropped (remove when [bgp-cloud-connector#121](https://github.com/openshift/bgp-cloud-connector/issues/121) ships; [#9](https://github.com/rh-mobb/validated-pattern-openshift-virt/issues/9))
- Sample `BGPRouting` `virt` (`gitops/samples/cudn`, `192.168.100.0/24`); the operator creates the CUDN
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
