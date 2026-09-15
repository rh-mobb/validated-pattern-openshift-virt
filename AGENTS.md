# AGENTS.md

Instructions for AI agents working in this repository.

## What this repo is

Customer-side **OpenShift RWX storage** (Azure NetApp Files + Trident CSI), **OpenShift Virtualization**, and **CUDN BGP** (Azure Route Server + in-cluster [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector)). Terraform provisions a NetApp-delegated subnet, ANF account and capacity pool, `RouteServerSubnet` + Route Server, and Trident/BGP identities. GitOps installs Trident, kubevirt-hyperconverged, and builds the BGP operator from [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) commit `2b6ad93989a2adfe4b52d4067f70a782aabd9a11` (kustomize remote + Shipwright `Build` git `revision` + `BuildRun` name suffix; bump all three together). Cleanup drains BGP CRs then Trident/ANF volumes.

This is **not** an OpenShift cluster installer. The cluster lives in the sibling **ARO HCP** pattern: [`rh-mobb/validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp). Do not create an HCP cluster here. Do not add AWS/GCP providers beyond empty module stubs until those slices exist.

## Sibling: ARO HCP installer

| | ARO HCP (`validated-pattern-aro-hcp`) | This repo |
|--|--------------------------------------|-----------|
| Role | Cluster + GitOps baseline (ESO, OpenShift GitOps) | ANF + Trident + OpenShift Virtualization + Azure Route Server |
| Canonical consume | `make cluster.<name>.apply` then bootstrap | Second IaC run: slim `terraform/` root |
| In-tree consume | N/A (this module is not called from the installer) | Deployer may `module` `git::…//modules/azure?ref=<tag>` in *their* root |
| Local co-dev | This checkout | Gitignored `references/validated-pattern-openshift-virt` inside the installer, **or** a sibling directory next to it |

**Co-develop:** optional clone at `<aro-hcp>/references/validated-pattern-openshift-virt` (parent gitignores `references/`). Point `ARO_HCP_ROOT` at the installer checkout. Do not add a git submodule either direction.

**Deploy order:** installer `jump-key` + `/32` → apply (includes `np-virt`) → kubeconfig → external-auth → installer bootstrap → `make cluster.<name>.platform` → this repo apply → this repo bootstrap. **Destroy reverse:** this repo cleanup + destroy (leftover ANF volumes if 409), then installer destroy.

**Ingest:** live `terraform output` via `ARO_HCP_ROOT` + cluster profile, or `platform.json` from `make cluster.<name>.platform` in the installer. Do **not** `terraform_remote_state` the installer’s local backend.

If the user is asking to create an ARO HCP cluster, stop and work in the installer repo (or tell them to open that workspace).

## Human docs vs agent docs

Operators follow MkDocs (`docs/guides/consume.md`, installer virt-stack). Agents follow this file plus [`clusters/aro-virt/AGENTS.md`](clusters/aro-virt/AGENTS.md).

If they disagree: **the operator guide wins for command names**; **AGENTS.md wins for stop-and-ask**. Fix the loser in the same PR. Do not paste a second installer `make` list here (that is how `virt-pool` went stale).

## Source precedence

When sources disagree:

1. **This repo’s `modules/azure`** and GitOps manifests — what we actually deploy.
2. [Microsoft: ANF + OpenShift Virtualization on ARO](https://learn.microsoft.com/en-us/azure/openshift/howto-netapp-files) — Trident version floor, StorageProfile RWX, Flexible/Manual QoS.
3. [RH experts: Trident on ARO](https://cloud.redhat.com/experts/aro/trident/) — OperatorHub install, backend secret vs inline credentials.
4. Installer sibling `AGENTS.md` / `docs/architecture.md` — VNet, reserved CIDRs `10.0.3.0/24` (ANF) and `10.0.4.0/26` (Route Server), jump `10.0.2.0/28`, OIDC issuer, Key Vault.

## Hard rules

- **`modules/azure` is the product.** `terraform/` is a thin root (providers, backend, platform ingest → `module "azure"`). Do not pile resources into the root.
- **Network privacy:** RFC1918 or Azure Private Endpoints only. ANF NFS via the delegated subnet is compliant (not a Private Endpoint). If a path cannot comply, add a row to the exception table in [`docs/architecture.md`](docs/architecture.md#network-privacy) **in the same change**.
- **Do not** create ANF volumes in Terraform. Trident provisions them. Cleanup script then `terraform destroy`.
- **BGP NIC writes:** sibling MI is Route Server BGP connections only. `networkInterfaceClientID` is installer `cluster_api_azure_client_id`. Do not add a customer MI for managed-RG NIC write.
- **Do not** install a second Argo CD. Consume `openshift-gitops` from the installer bootstrap.
- **Do not** steal the cluster default StorageClass (`managed-csi`) unless an explicit flag says so.
- **Do not** use Azure Files for VM disks.
- **`make` is the interface:** run `make fmt lint test` before claiming work is done.
- **Docs and changelog:** keep [`docs/architecture.md`](docs/architecture.md) in sync with code; update [`CHANGELOG.md`](CHANGELOG.md) **only at commit time** from `git diff --cached` vs `HEAD`. Same rule as the installer.
- **Never commit:** operator `clusters/*/terraform.tfvars` (except committed examples), `clusters/*/infrastructure.tfstate*`, `clusters/*/platform.json`, `clusters/*/logs/`, kubeconfig, client secrets, pull secrets.
- **Live Azure:** do not `apply` / `destroy` unless the user asked. ANF pools are expensive (TiB-scale). Follow [Live Azure deployments](#live-azure-deployments).
- **Git:** feature branches only; Conventional Commits; no `Co-authored-by: Cursor` or AI trailers.

## Layout

| Path | Purpose |
|------|---------|
| `modules/azure/` | Delegated ANF subnet, NetApp account + pool, Route Server, Trident + BGP identities |
| `modules/aws/` | Stub: Amazon FSx for NetApp ONTAP (not implemented) |
| `modules/gcp/` | Stub: Google Cloud NetApp Volumes (not implemented) |
| `terraform/` | Thin root: providers, backend, compose `module.azure` |
| `clusters/<name>/` | Per-attachment `terraform.tfvars` + state; `aro-virt/AGENTS.md` (agent E2E, not MkDocs) |
| `gitops/` | Trident, CNV, in-cluster bgp-cloud-connector build |
| `scripts/` | `trident-cleanup.sh` (standalone), bootstrap |
| `docs/` | Operator guides (MkDocs): prerequisites, architecture, consume modes |
| `AGENTS.md` | This file — agents read it first |
| `CHANGELOG.md` | Commit-scoped operator-visible history |
| `tests/` | `terraform test` on `modules/azure` + bats |

## Deploy path

Commands: installer [Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/) and [consume](docs/guides/consume.md). Agent done-when: [`clusters/aro-virt/AGENTS.md`](clusters/aro-virt/AGENTS.md).

Installer apply already creates `np-virt` (`node_pools`). There is **no** `make cluster.aro-virt.virt-pool`. Jump (`jump-key` + `/32`) is required on the installer before apply.

```bash
# this repo (after installer platform)
export ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp
export ARO_HCP_PROFILE=aro-virt
export KUBECONFIG_PATH="${ARO_HCP_ROOT}/.kube/config"
# unset TF_VAR_* in this shell
ARO_HCP_ROOT="${ARO_HCP_ROOT}" ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.apply
make cluster.aro-virt.bootstrap
make cluster.aro-virt.destroy              # cleanup + terraform destroy; leftover ANF volumes: az delete, retry
```

In-tree: caller adds `module "netapp" { source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>" }`. They still need GitOps + cleanup. Pin `ref` to a tag.

## Live Azure deployments

Use this when the user asks to apply, verify, or destroy real ANF/Trident. `make` is the interface.

### Long-running operations (tmux)

Apply, destroy, and `trident-cleanup` must outlive the chat turn. A dead foreground shell leaves ANF volumes, Route Server, and a delegated subnet that block installer destroy.

1. **Prefer tmux** whenever `tmux` or the tmux MCP is available. Run `make cluster.<name>.apply` / `.destroy` in a session the operator can `tmux attach`. Tee to `clusters/<name>/logs/<utc>-<phase>.log` (gitignored). Same rule as the installer.
2. **Fallback only:** if tmux is not available, use a Cursor **background** shell (`block_until_ms: 0`), same log path. Do not run cleanup or terraform destroy in a foreground tool call that dies with the turn.
3. Do **not** fail preflight solely because tmux is missing.
4. On failure: diagnose, discuss non-obvious fixes with the operator, **resume from the failed step**. If destroy 409s on the pool, delete leftover ANF volumes, wait until the list is empty, then retry destroy (do not restart installer destroy first).

### Preflight (every apply or destroy)

1. **Azure identity.** `az account show` — confirm subscription matches the installer cluster.
2. **Cluster exists.** Installer cluster is `Succeeded`; GitOps + ESO are up (`make cluster.<name>.bootstrap` already ran there).
3. **`clusters/<name>/terraform.tfvars`.** Must exist. `ARO_HCP_ROOT` + profile or `platform_json` must resolve. Never commit operator copies.
4. **`TF_VAR_*` leftovers.** Same rule as the installer: list them, stop, ask A/B/C (unset / keep and update tfvars / abort).
5. **CIDR.** `subnet_prefix` default `10.0.3.0/24` must not overlap worker, integration, or jump (`10.0.2.0/28`).
6. **Quota.** `Microsoft.NetApp` registered; ANF capacity quota in `location`.
7. **Existing resources.** If a NetApp account/pool or non-empty sibling state already exists, stop and ask.
8. **Plan first.** Summarize create/change/destroy. Apply only if it matches the ask.

### After apply

- Capacity pool exists; delegated subnet is `Microsoft.NetApp/volumes`.
- Continue with bootstrap. Storage-done signal: PVC on `anf-virt` binds RWX. Virt-done signal: `HyperConverged` Available and StorageProfile `anf-virt` is RWX Filesystem.
- Before large DataVolume clone/upload tests: `oc get cdiconfig config -o jsonpath='{.status.defaultPodResourceRequirements.limits.memory}'` must show **4Gi** (GitOps `spec.resourceRequirements.storageWorkloads` on `kubevirt-hyperconverged`). Default ~600M OOMs around 65% on large images.

### Destroy

1. Confirm subscription, RG, NetApp account, cluster name.
2. `make cluster.<name>.cleanup` (or destroy, which runs it first): BGP CR drain, then `anf-virt` PVCs/PVs (wait timeout 180s). Azure volume delete is slower — leftover volumes 409 the pool; `az netappfiles volume delete`, wait until the list is empty, retry **this** destroy.
3. Then `terraform destroy`.
4. Then the installer `make cluster.<name>.destroy`.

### Do not

- `terraform apply` / `destroy` outside Make (skips `-var-file`).
- Destroy the installer cluster while this stack still owns a delegated subnet or ANF volumes.
- Mix a virt **node pool** (installer extra pool) into a storage-only ask. CNV GitOps lives here; extra workers stay in the installer.

## Documentation

When a change affects deploy behavior or resultant Azure/OpenShift resources, update the docs **in the same work**, not later.

**Recipe change workflow:** consume.md / installer virt-stack → [`clusters/aro-virt/AGENTS.md`](clusters/aro-virt/AGENTS.md) → this file if all attachments are affected. Do not re-introduce a pasted installer `make` list.

- [`docs/index.md`](docs/index.md) — site home
- [`docs/prerequisites/`](docs/prerequisites/) — ANF quota, NetApp RP, permissions by `make` target
- [`docs/architecture.md`](docs/architecture.md) — inventory, CIDRs, identity, destroy order
- [`docs/guides/consume.md`](docs/guides/consume.md) — second IaC run vs in-tree `module` block
- [`clusters/aro-virt/AGENTS.md`](clusters/aro-virt/AGENTS.md) — agent E2E (done-when). Not published to MkDocs.
- [`README.md`](README.md) — operator path and troubleshooting
- [`clusters/azure/terraform.tfvars`](clusters/azure/terraform.tfvars) — if a new required variable appears

Keep voice, changelog rules, and `make fmt lint test` aligned with the ARO HCP installer so agents switching repos do not learn two conventions.

After live E2E: add a **Known failure modes** row to `clusters/aro-virt/AGENTS.md`. If operators would hit it, update consume.md and/or installer virt-stack troubleshooting in the same PR.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md) records **committed** deltas only. It is not a debug log.

- **Do not** edit `CHANGELOG.md` while exploring, debugging, or iterating on uncommitted work.
- **Do** add an entry only when creating a git commit, and only for that commit’s diff (`git diff --cached` against `HEAD`).
- Describe operator-visible changes. Omit `chore` / `test` / `style` with no operator impact.
- Never record tried-and-reverted steps.
