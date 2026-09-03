# AGENTS.md

Instructions for AI agents working in this repository.

## What this repo is

Customer-side **OpenShift RWX storage** (Azure NetApp Files + Trident CSI), with OpenShift Virtualization as a later slice. Terraform provisions a NetApp-delegated subnet, ANF account and capacity pool, and a Trident identity. GitOps installs Trident. A standalone cleanup script drains Trident/ANF volumes that Terraform does not own.

This is **not** an OpenShift cluster installer. The cluster lives in the sibling **ARO HCP** pattern: [`rh-mobb/validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp). Do not create an HCP cluster here. Do not add AWS/GCP providers beyond empty module stubs until those slices exist.

## Sibling: ARO HCP installer

| | ARO HCP (`validated-pattern-aro-hcp`) | This repo |
|--|--------------------------------------|-----------|
| Role | Cluster + GitOps baseline (ESO, OpenShift GitOps) | ANF + Trident (+ later CNV) |
| Canonical consume | `make cluster.<name>.apply` then bootstrap | Second IaC run: slim `terraform/` root |
| In-tree consume | N/A (this module is not called from the installer) | Deployer may `module` `git::…//modules/azure?ref=<tag>` in *their* root |
| Local co-dev | This checkout | Gitignored `references/validated-pattern-openshift-virt` inside the installer, **or** a sibling directory next to it |

**Co-develop:** optional clone at `<aro-hcp>/references/validated-pattern-openshift-virt` (parent gitignores `references/`). Point `ARO_HCP_ROOT` at the installer checkout. Do not add a git submodule either direction.

**Deploy order:** installer apply → kubeconfig → external-auth → installer bootstrap (GitOps + ESO) → `make cluster.<name>.platform` → this repo apply → this repo bootstrap. **Destroy reverse:** this repo cleanup + destroy, then installer destroy.

**Ingest:** live `terraform output` via `ARO_HCP_ROOT` + cluster profile, or `platform.json` from `make cluster.<name>.platform` in the installer. Do **not** `terraform_remote_state` the installer’s local backend.

If the user is asking to create an ARO HCP cluster, stop and work in the installer repo (or tell them to open that workspace).

## Source precedence

When sources disagree:

1. **This repo’s `modules/azure`** and GitOps manifests — what we actually deploy.
2. [Microsoft: ANF + OpenShift Virtualization on ARO](https://learn.microsoft.com/en-us/azure/openshift/howto-netapp-files) — Trident version floor, StorageProfile RWX, Flexible/Manual QoS.
3. [RH experts: Trident on ARO](https://cloud.redhat.com/experts/aro/trident/) — OperatorHub install, backend secret vs inline credentials.
4. Installer sibling `AGENTS.md` / `docs/architecture.md` — VNet, reserved CIDR `10.0.3.0/24`, jump `10.0.2.0/28`, OIDC issuer, Key Vault.

## Hard rules

- **`modules/azure` is the product.** `terraform/` is a thin root (providers, backend, platform ingest → `module "azure"`). Do not pile resources into the root.
- **Network privacy:** RFC1918 or Azure Private Endpoints only. ANF NFS via the delegated subnet is compliant (not a Private Endpoint). If a path cannot comply, add a row to the exception table in [`docs/architecture.md`](docs/architecture.md#network-privacy) **in the same change**.
- **Do not** create ANF volumes in Terraform. Trident provisions them. Cleanup script then `terraform destroy`.
- **Do not** install a second Argo CD. Consume `openshift-gitops` from the installer bootstrap.
- **Do not** steal the cluster default StorageClass (`managed-csi`) unless an explicit flag says so.
- **Do not** use Azure Files for VM disks.
- **`make` is the interface:** run `make fmt lint test` before claiming work is done.
- **Docs and changelog:** keep [`docs/architecture.md`](docs/architecture.md) in sync with code; update [`CHANGELOG.md`](CHANGELOG.md) **only at commit time** from `git diff --cached` vs `HEAD`. Same rule as the installer.
- **Never commit:** operator `clusters/*/terraform.tfvars` (except committed examples), `clusters/*/infrastructure.tfstate*`, `clusters/*/platform.json`, kubeconfig, client secrets, pull secrets.
- **Live Azure:** do not `apply` / `destroy` unless the user asked. ANF pools are expensive (TiB-scale). Follow [Live Azure deployments](#live-azure-deployments).
- **Git:** feature branches only; Conventional Commits; no `Co-authored-by: Cursor` or AI trailers.

## Layout

| Path | Purpose |
|------|---------|
| `modules/azure/` | Delegated subnet, NetApp account + pool, Trident identity + RBAC |
| `modules/aws/` | Stub: Amazon FSx for NetApp ONTAP (not implemented) |
| `modules/gcp/` | Stub: Google Cloud NetApp Volumes (not implemented) |
| `terraform/` | Thin root: providers, backend, compose `module.azure` |
| `clusters/<name>/` | Per-attachment `terraform.tfvars` + state |
| `gitops/` | Trident operator, backend Job, StorageClass |
| `scripts/` | `trident-cleanup.sh` (standalone), bootstrap |
| `docs/` | Operator guides (MkDocs): prerequisites, architecture, consume modes |
| `AGENTS.md` | This file — agents read it first |
| `CHANGELOG.md` | Commit-scoped operator-visible history |
| `tests/` | `terraform test` on `modules/azure` + bats |

## Deploy path

```bash
# installer (sibling checkout)
make cluster.my-cluster.apply
make cluster.my-cluster.kubeconfig
make cluster.my-cluster.external-auth
make cluster.my-cluster.bootstrap
make cluster.my-cluster.platform

# this repo
cp -r clusters/azure clusters/my-cluster   # ARO_HCP_ROOT or platform_json in tfvars
make cluster.my-cluster.apply              # ANF subnet + account + pool + identity
make cluster.my-cluster.bootstrap          # Argo Application → gitops/ (Trident)
make cluster.my-cluster.destroy            # cleanup script, then terraform destroy
```

In-tree: caller adds `module "netapp" { source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>" }`. They still need GitOps + cleanup. Pin `ref` to a tag.

## Live Azure deployments

Use this when the user asks to apply, verify, or destroy real ANF/Trident. `make` is the interface.

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
- Continue with bootstrap. Storage-done signal: PVC on `anf-virt` binds RWX.
- Do not install CNV in the storage slice (#17 in the installer).

### Destroy

1. Confirm subscription, RG, NetApp account, cluster name.
2. `make cluster.<name>.cleanup` (or destroy, which runs it first): delete `anf-virt` PVCs/PVs, Trident backends, leftover ANF volumes.
3. Then `terraform destroy`.
4. Then the installer `make cluster.<name>.destroy`.

### Do not

- `terraform apply` / `destroy` outside Make (skips `-var-file`).
- Destroy the installer cluster while this stack still owns a delegated subnet or ANF volumes.
- Mix CNV / virt node pool into a storage-only ask.

## Documentation

When a change affects deploy behavior or resultant Azure/OpenShift resources, update the docs **in the same work**, not later.

- [`docs/index.md`](docs/index.md) — site home
- [`docs/prerequisites/`](docs/prerequisites/) — ANF quota, NetApp RP, permissions by `make` target
- [`docs/architecture.md`](docs/architecture.md) — inventory, CIDRs, identity, destroy order
- [`docs/guides/consume.md`](docs/guides/consume.md) — second IaC run vs in-tree `module` block
- [`README.md`](README.md) — operator path and troubleshooting
- [`clusters/azure/terraform.tfvars`](clusters/azure/terraform.tfvars) — if a new required variable appears

Keep voice, changelog rules, and `make fmt lint test` aligned with the ARO HCP installer so agents switching repos do not learn two conventions.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md) records **committed** deltas only. It is not a debug log.

- **Do not** edit `CHANGELOG.md` while exploring, debugging, or iterating on uncommitted work.
- **Do** add an entry only when creating a git commit, and only for that commit’s diff (`git diff --cached` against `HEAD`).
- Describe operator-visible changes. Omit `chore` / `test` / `style` with no operator impact.
- Never record tried-and-reverted steps.
