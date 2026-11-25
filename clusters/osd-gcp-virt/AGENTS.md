# Agent playbook — `clusters/osd-gcp-virt`

Attach OpenShift Virtualization (Hyperdisk + CNV) to an **OSD GCP** cluster from [validated-pattern-osd-gcp](https://github.com/rh-mobb/validated-pattern-openshift-virt).

## Prerequisites

Installer done-when: `make cluster.virt.platform` → `clusters/virt/platform.json` with `installer = "osd-gcp"`.

## Deploy

```bash
export OSD_GCP_ROOT=/path/to/validated-pattern-osd-gcp
export KUBECONFIG="${OSD_GCP_ROOT}/.kube/config-virt"
unset TF_VAR_*

OSD_GCP_ROOT="${OSD_GCP_ROOT}" OSD_GCP_PROFILE=virt make cluster.osd-gcp-virt.apply   # GCP: pool + BGP; metadata ConfigMap
GITOPS_SYNC_LOCAL=1 make cluster.osd-gcp-virt.bootstrap # applies Hyperdisk SC/VSC from TF; Argo overlay = CNV + BGP

**Storage GitOps debt:** `scripts/gitops-bootstrap.sh` applies Hyperdisk `StorageClass` + `VolumeSnapshotClass` from Terraform outputs (interim). **TODO:** small Helm chart + `helm.parameters` on `virt-stack`, or kustomize + `ignoreDifferences` — not an Argo sync Job.
```

`platform_json` in `terraform.tfvars` is relative to **`terraform/`** (sibling checkout: `../../validated-pattern-osd-gcp/clusters/virt/platform.json`).

**BGP:** `modules/gcp` provisions NCC hub + Cloud Router; `modules/gcp-bgp-operator-iam` provisions GCP SA + OCM WIF binding for [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector). `bgp-from-metadata` stamps manager `PROJECT_NUMBER` / `POOL_ID` / `PROVIDER_ID` / `SERVICE_ACCOUNT_EMAIL` so **CCO** writes `bgp-cloud-connector-gcp-credentials`, then applies `BGPCloudConfiguration`. In-cluster `BuildConfig` from pinned `main` SHA; `GITOPS_SYNC_LOCAL=1 bootstrap` after apply.

**Done when:** `HyperConverged` Available; `StorageProfile` `sp-balanced-storage` exists; (optional BGP) `BGPCloudConfiguration` `cluster` reaches `Ready`.

### OSD: `virt-operator` stuck Pending

CNV may deploy `virt-operator` with `nodeSelector: worker` and affinity for control-plane nodes. On OSD those labels do not coexist. If pods stay Pending after bootstrap:

```bash
oc patch deployment virt-operator -n openshift-cnv --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
```

KubeVirt may re-add the selector; confirm `HyperConverged` becomes Available regardless.

## Destroy

Run **before** installer `make cluster.virt.destroy`. `make cluster.osd-gcp-virt.destroy` runs `trident-cleanup.sh` (deletes `virt-stack`, BGP CRs, HyperConverged, then Hyperdisk PVCs) then Terraform.

```bash
export OSD_GCP_ROOT=/path/to/validated-pattern-osd-gcp
export OSD_GCP_PROFILE=virt
# Kubeconfig resolves to ${OSD_GCP_ROOT}/.kube/config-${OSD_GCP_PROFILE} (no need to set KUBECONFIG_PATH unless non-default)
OSD_GCP_ROOT="${OSD_GCP_ROOT}" OSD_GCP_PROFILE=virt make cluster.osd-gcp-virt.destroy
```

If destroy fails on `google_compute_storage_pool` with `resourceInUseByAnotherResource`, re-run cleanup after CNV finishes winding down, or set `GCP_STORAGE_CLASS` if you renamed the StorageClass.