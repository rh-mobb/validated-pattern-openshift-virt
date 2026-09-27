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

Cleanup deletes BGP CRs then `anf-virt` PVCs (wait timeout **180s**). Azure volume delete is slower; leftover volumes 409 the pool.

If `CannotDeleteResource` / `InUseSubnetCannotBeDeleted`:

```bash
az netappfiles volume list -g aro-virt-rg --account-name aro-virt-anf --pool-name aro-virt-anf-pool -o table
az netappfiles volume delete -g aro-virt-rg --account-name aro-virt-anf --pool-name aro-virt-anf-pool --name <pvc-…> --yes
# wait until the list is empty, then retry destroy
```

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
| Destroy 409 on pool / subnet in use | PVC wait 180s < ANF delete | `az netappfiles volume delete`, wait, retry **this** destroy |
| Jump → `np-1` CUDN fails | NIC forwarding false | DS logs; CAPI client ID; `HOME=/tmp` |
| DV clone ~65% OOM | CDI ~600M | `cdiconfig` 4Gi; see CDI guide |
| `disk.img: file exists` | Partial clone after OOM | Delete DV/tmp PVCs; retry |
| Wrong tags/region | `TF_VAR_*` | Unset; same as installer A/B/C |
| `virt-stack` Forbidden (Shipwright Build, TridentOrchestrator, …) | GitOps controller lacks `cluster-admin` on first sync | Bootstrap pre-applies `gitops-controller-rbac.yaml`; if skipped: `oc apply -f gitops/base/gitops-controller-rbac.yaml`, sync `virt-stack` |
| `azure-nic-ip-forwarding` missing ConfigMap | DS applied before `bgp-from-metadata` Job (legacy `hook: Sync`) | Use current GitOps (Job sync-wave `4`); `oc apply -f gitops/operators/bgp-cloud-connector/from-metadata-job.yaml` once |

After a new live failure: add a row here. If operators would hit it, update consume.md and/or installer virt-stack troubleshooting in the same PR.
