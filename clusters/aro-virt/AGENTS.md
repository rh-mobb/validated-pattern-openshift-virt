# Agent playbook — `clusters/aro-virt`

Step-by-step **done-when** gates for the virt/storage attach. Human runbook: installer [Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/) and [consume](../../docs/guides/consume.md). Generic Live Azure (preflight, `TF_VAR_*`, tmux): root [`AGENTS.md`](../../AGENTS.md#live-azure-deployments).

The HCP cluster, jump, and `platform.json` live in the **installer**. If the user asks to create the cluster, stop and work there (`clusters/aro-virt/AGENTS.md`). Extra-hop jump ping/curl (speaker **and** `np-1`) is the installer playbook section **Extra-hop e2e** after this bootstrap.

If this file and consume/virt-stack disagree on a `make` target, **the operator guide wins for commands**; **this file wins for stop-and-ask**. Fix the loser in the same PR.

There is **no** installer `make cluster.aro-virt.virt-pool`. `np-virt` is in installer `node_pools`.

## When to run

- User asks to attach ANF/Trident/CNV/Route Server to an existing `aro-virt` cluster.
- PR changes `modules/azure` Route Server/ANF, GitOps Trident/CNV/BGP, the NIC-forwarding DaemonSet, or `trident-cleanup.sh`.
- After installer `platform.json` / CAPI client-id contract changes.

Skip live E2E for refactors with no operator-facing behavior.

## Recipe facts

| Item | Value |
|------|--------|
| Profile | `aro-virt` (same name as the installer profile) |
| Ingest | `ARO_HCP_ROOT` + `ARO_HCP_PROFILE=aro-virt`, or `platform_json` |
| Kubeconfig | **Installer** `.kube/config` (`KUBECONFIG_PATH` / `KUBECONFIG`). This checkout’s `.kube/config` is empty. |
| ANF | Delegated subnet `10.0.3.0/24`, pool default **1 TiB** Flexible (billable) |
| Route Server | `RouteServerSubnet` `10.0.4.0/26`; **16** BGP peers max; speakers only |
| CUDN sample | GitOps `BGPRouting` `virt` → operator creates `cluster-udn-virt` `192.168.100.0/24`, namespace `virt` |
| NIC forwarding | DaemonSet `azure-nic-ip-forwarding` on **all** workers via installer `cluster-api-azure` |

## Steps 0–4 (this repo)

Use tmux when possible. Unset leftover `TF_VAR_*` in the **same** session as `make`.

```bash
export ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp
export ARO_HCP_PROFILE=aro-virt
export KUBECONFIG_PATH="${ARO_HCP_ROOT}/.kube/config"
export KUBECONFIG="${KUBECONFIG_PATH}"
```

### Step 0 — Preflight

Follow root Live Azure preflight. Also: installer cluster `Succeeded`; GitOps + ESO up; `platform.json` (or `ARO_HCP_ROOT`) resolves; `oc whoami` works with the installer kubeconfig.

**Done when:** Subscription matches the installer; operator approved ANF cost; no unapproved `TF_VAR_*`.

### Step 1 — Plan

```bash
ARO_HCP_ROOT="${ARO_HCP_ROOT}" ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.plan
```

**Done when:** Plan creates NetApp subnet, Route Server subnet + RS, ANF account/pool, Trident + BGP identities. No unexpected destroys.

### Step 2 — Apply

```bash
# tmux
ARO_HCP_ROOT="${ARO_HCP_ROOT}" ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.apply
```

**Done when:** Delegated subnet `Microsoft.NetApp/volumes`; Route Server exists; capacity pool exists.

### Step 3 — Bootstrap

```bash
make cluster.aro-virt.bootstrap
```

**Done when:**

| Check | Expected |
|-------|----------|
| Argo `virt-stack` | Synced / Healthy (or syncing with a known reason) |
| `oc get sc anf-virt` | virt-class annotation; cluster default remains `managed-csi` |
| `oc -n trident get tbc anf-backend` | Bound |
| HyperConverged | `systemHealthStatus` healthy |
| `oc get cdiconfig config -o jsonpath='{.status.defaultPodResourceRequirements.limits.memory}'` | **4Gi** |
| `oc get bgpcloudconfiguration cluster` | platform Azure, phase Ready |
| `oc get bgprouting virt` | Ready; `cluster-udn-virt` exists (do **not** apply a CUDN yourself) |
| `azure-nic-ip-forwarding` DS | 1/1 on every linux worker |

Optional RWX smoke: PVC `anf-virt` in a throwaway namespace (first ANF volume **5–15 min**; CSI timeout then bind is normal).

### Step 4 — Extra-hop

Do **not** stop at speaker-only ping. Run the installer playbook **Extra-hop e2e** (jump `10.0.2.4` → CUDN on `np-virt` **and** `np-1`, curl body `10.0.2.4`).

OpenShift 4.21.8+ OVN wrong-node egress is assumed (installer example is 4.22). That does **not** replace `enableIPForwarding` on non-speakers.

**Done when:** installer extra-hop **Done when** is met.

## Destroy

```bash
# tmux; kubeconfig still the installer
make cluster.aro-virt.destroy
```

Cleanup also removes DataVolumes proven by PVC owner UID to produce this storage class; retained VM controllers must be removed first.

Cleanup now disables common boot-image imports and blocks on remaining
DataImportCrons or Pod consumers before draining PVCs/PVs. The Azure gate must verify
an empty pool before backend and identity teardown. Preview before confirming direct
leftover-volume deletion:

```bash
make cluster.aro-virt.anf-preview
ANF_DELETE_CONFIRM=aro-virt-rg/aro-virt-anf/aro-virt-anf-pool make cluster.aro-virt.destroy
```

If an earlier partial destroy removed Trident's identity, use the same confirmation
with `.anf-cleanup` for Azure-only recovery, then resolve any Kubernetes drain errors
and retry this sibling's destroy. Never overlap Terraform/ARM mutations. Inventory
errors and incomplete deletes must stop teardown, not be treated as absence.

**Done when:** sibling Terraform state empty; no ANF account/pool/netapp subnet/Route Server. **Then** installer `make cluster.aro-virt.destroy`. Do not start installer destroy while this stack still owns the delegated subnet.

## Do not

- GitOps a raw `ClusterUserDefinedNetwork` — `BGPRouting` only.
- Add a customer MI for managed-RG NIC write; use installer `cluster_api_azure_client_id`.
- Disable src/dest / IP forwarding **only** on `bgp_router` nodes.
- Label `np-1` `bgp_router=true` to get forwarding (peer cap 16).
- Install a second Argo CD.
- Steal cluster default StorageClass `managed-csi`.
- Create ANF volumes in Terraform.
- Run `make cluster.*.virt-pool` on the installer.

## Known failure modes

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| `oc whoami` fails | Empty sibling kubeconfig | `KUBECONFIG_PATH` = installer `.kube/config` |
| Destroy 409 on pool / subnet in use | PVC wait 180s < ANF delete | Preview `.anf-preview`, explicitly confirm direct leftovers with `.anf-cleanup`, wait empty, retry **this** destroy |
| Jump → `np-1` CUDN fails | NIC forwarding false | DS logs; CAPI client ID; `HOME=/tmp` |
| DV clone ~65% OOM | CDI ~600M | `cdiconfig` 4Gi; see CDI guide |
| `disk.img: file exists` | Partial clone after OOM | Delete DV/tmp PVCs; retry |
| Wrong tags/region | `TF_VAR_*` | Unset; same as installer A/B/C |
| `virt-stack` Forbidden (ImageStream, TridentOrchestrator, …) | GitOps controller lacks `cluster-admin` on first sync | Bootstrap pre-applies `gitops-controller-rbac.yaml`; if skipped: `oc apply -f gitops/base/gitops-controller-rbac.yaml`, sync `virt-stack` |
| `azure-nic-ip-forwarding` missing ConfigMap | DS applied before `bgp-from-metadata` Job (legacy `hook: Sync`) | Use current GitOps (Job sync-wave `4`); `oc apply -f gitops/operators/bgp-cloud-connector/from-metadata-job.yaml` once |

After a new live failure: add a row here. If operators would hit it, update consume.md and/or installer virt-stack troubleshooting in the same PR.

### Classic attachment findings (2026-10-19)

The separate `aro-classic-virt` attachment used Classic `machine_api_client_id` and
initially Argo inline Kustomize patches. The maintained
`gitops/profiles/aro-classic-virt` profile replaces those patches; bootstrap with
`GITOPS_PLATFORM=classic GITOPS_PATH=gitops/profiles/aro-classic-virt`. Preserve HCP
behavior for this `aro-virt` profile.

| Symptom | Cause / evidence | Action |
|---------|------------------|--------|
| Classic `virt-operator` Pending | Subscription forces worker selector while CSV requires control-plane affinity | Remove the HCP-only Subscription selector in Classic-specific GitOps configuration; keep workload placement/tolerations separate |
| BGP BuildConfig keeps Argo OutOfSync after a successful build | API removes its empty ImageChange trigger | Use ConfigChange only unless an actual image-change source is configured |
| Default-worker host HTTP to CUDN times out despite Established BGP | Approved lookup selected ovn-k8s-mp1/table 1053, bypassing Route Server | Do not call this external dataplane evidence; use a separate private VNet probe host |
| ANF pool delete fails after PVC cleanup | CNV common boot-image imports recreate PVCs/volumes during drain | Use the current Make cleanup/destroy drain and Azure gate; stop consumers first, preview with .anf-preview, and explicitly confirm any direct leftover deletion. For a partial destroy with a missing Trident identity, use .anf-cleanup before retrying; never overlap Terraform operations |

CNV Healthy, Trident backend Bound, cross-node RWX shared-file access, a Running/Ready
VMI with an RWX data disk, and all four speaker-to-Route-Server sessions were verified.
A separate private VNet VM at 10.0.5.4 successfully reached HTTP endpoints on both
speaker and non-speaker CUDN Pods; both preserved the original source IP. Its NIC had
an active 192.168.100.0/24 route through the two speakers.
No guest networking, migration or worker replacement result is implied.


### Clean Classic rebuild follow-up (2026-10-19)

A fresh Classic cluster consumed branch `feat/classic-gitops-overlays` at `c694230`
with `gitops/profiles/aro-classic-virt` and no inline Argo patches. Argo reached
Synced/Healthy/Succeeded, CNV was Available and not Degraded, Trident's backend was
Bound, four FRR sessions established, and all seven worker NICs had forwarding.
Cross-node RWX access passed. A fresh private VM probe reached speaker and
non-speaker CUDN Pods with source IP preserved; its VM, disk, NIC and subnet were
verified absent afterward.

The fresh VMI boot check failed twice with SyncVMI timeouts followed by
`containerdisk rootdisk still not ready after one minute`; the root-disk sidecar
had exited. Cause remains unresolved. Do not infer VM boot success on this fresh
cluster from the earlier attachment's successful VMI test. Inspect launcher and
handler logs before retrying; remove disposable failed instances through normal
finalization, without force deletion or finalizer removal.


### Repeatable settled-stack smoke

Use `make cluster.<profile>.stack-ready` before ad hoc VM tests and
`make cluster.<profile>.smoke` for the committed disposable boot tests. They use
`KUBECONFIG_PATH` from the installer and require a continuous 120-second healthy
window; `smoke` repeats the barrier after disk provisioning and before each VM.
Do not replace this with an arbitrary sleep or silently retry failed VM startup.
Success requires Running/Ready and AgentConnected for both configured boot sources,
then cleanup of the run's namespace/PVs. Reports are in the profile's ignored logs.
Use the [operator guide](../../docs/guides/consume.md#settled-stack-smoke-test) for
settings and prerequisites. This does not validate migration or guest CUDN routing.

Fresh Classic validation on 2026-10-20 found two entry-point limits: invoking the
gate before operator API registration fails immediately without creating test
resources; waiting for cold catalog imports can exhaust the default 1800-second
overall budget before a VM starts. Wait for CNV/CDI/BGP APIs and allow
`SMOKE_TIMEOUT_SECONDS=3600` for a cold deployment. Preserve failed reports and
verify cleanup before another run. Do not describe these pre-boot failures as VM
boot failures or silently retry a failed VM. The longer-budget validation passed
both boot sources and cleanup with the same 120-second barriers.

The clean Classic rebuild used infrastructure ID `aro-classic-virt-98vk6` and
GitOps profile `gitops/profiles/aro-classic-virt` at `8b76ccf`, without inline
patches. Both Fedora boot sources passed. A separate PVC-backed Fedora VMI
live-migrated from virt worker 1 to worker 2 in PreCopy mode with unchanged VMI
UID/guest boot ID and heartbeat counter 2 → 14; this used default pod networking.
An external private VM reached speaker and non-speaker CUDN Pods with source IP
preserved. Disposable VM/storage namespaces and the private probe VM/disk/NIC/subnet
were removed. Guest CUDN migration and worker replacement were not tested.

Final drift check: installer no changes; sibling six tag-only updates removing
`app-code` and `cost-center`, consistent with the previously observed policy tags.
These were not applied. No additions, deletions or replacements were planned;
sibling tag ownership remains a follow-up.

A repeat clean Classic deployment on 2026-10-21 (`aro-classic-virt-wfdbr`, sibling
`8b76ccf`) completed both applies without recovery. Waiting for API registration
before the 3600-second smoke run allowed all six catalog imports, both boot
sources and cleanup to pass. A separate Fedora VMI migrated from virt worker 2
to worker 1 with unchanged VMI UID/guest boot ID and heartbeat 2 → 15. External
speaker/non-speaker CUDN HTTP preserved source IP; the temporary probe VM, disk,
NIC and subnet and all test namespaces/volumes were removed. No effective route
table was captured in this repeat. Guest CUDN migration and worker replacement
remain untested. The same six sibling policy-tag updates were left unapplied.
The sibling and installer were then destroyed successfully in that order; both
resource groups were absent and both Terraform states had zero managed resources.
