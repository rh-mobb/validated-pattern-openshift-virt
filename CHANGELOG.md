# Changelog

Operator-visible history. Update **only at commit time** from `git diff --cached` vs `HEAD`. Same rule as `validated-pattern-aro-hcp`.

## Unreleased

### Added

- GitOps for OpenShift Virtualization (`kubevirt-hyperconverged` in `openshift-cnv`): worker-only HyperConverged, Job patches StorageProfile `anf-virt` to RWX Filesystem, StorageClass virt-class annotation (cluster default stays `managed-csi`)
- Example profile `clusters/aro-virt` matching the installer virt-ready directory
- Azure NetApp Files Terraform module (`modules/azure`): delegated subnet, Flexible/Manual capacity pool, Trident workload identity
- Slim `terraform/` root that ingests installer `platform.json`
- GitOps for certified Trident operator, StorageClass `anf-virt`, and backend Job
- `make cluster.<name>.{apply,bootstrap,cleanup,destroy}` with standalone `scripts/trident-cleanup.sh`
