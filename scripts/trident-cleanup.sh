#!/usr/bin/env bash
# Drain in-cluster resources while Trident and BGP identities still exist.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${ROOT_DIR}/.kube/config}"
STORAGE_CLASS="${STORAGE_CLASS:-anf-virt}"
GITOPS_APP_NAMESPACE="${GITOPS_APP_NAMESPACE:-openshift-gitops}"
GITOPS_APP_NAME="${GITOPS_APP_NAME:-virt-stack}"
log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}
case "${1:-}" in
  -h | --help)
    echo 'Usage: trident-cleanup.sh [--backend-only]'
    echo 'Drain GitOps, imports, BGP and PVCs/PVs. Stop consumers first.'
    echo 'make cluster.<profile>.cleanup also verifies the Azure pool is empty before removing the backend.'
    exit 0
    ;;
  '' | --backend-only) ;;
  *) die 'Unknown argument' ;;
esac
command -v oc >/dev/null || die 'oc is required'
command -v jq >/dev/null || die 'jq is required'
export KUBECONFIG="${KUBECONFIG_PATH}"
oc whoami >/dev/null || die 'Cannot reach the API. Set KUBECONFIG_PATH.'
# NotFound is the only absence we tolerate; authorization/transport failures stop teardown.
if [[ "${1:-}" == --backend-only ]]; then
  found="$(oc get crd tridentbackendconfigs.trident.netapp.io --ignore-not-found -o name)"
  if [[ -n "$found" ]]; then
    oc -n trident delete tridentbackendconfig anf-backend --ignore-not-found --wait=true --timeout=180s
  fi
  exit 0
fi
found="$(oc get crd applications.argoproj.io --ignore-not-found -o name)"
if [[ -n "$found" ]]; then
  log 'Removing the GitOps Application before draining managed resources'
  oc -n "${GITOPS_APP_NAMESPACE}" delete application "${GITOPS_APP_NAME}" --ignore-not-found --wait=true --timeout=120s
fi
found="$(oc get crd hyperconvergeds.hco.kubevirt.io --ignore-not-found -o name)"
if [[ -n "$found" ]]; then
  hco="$(oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv --ignore-not-found -o name)"
  if [[ -n "$hco" ]]; then
    log 'Disabling CNV common boot-image imports'
    oc patch hyperconverged kubevirt-hyperconverged -n openshift-cnv --type merge -p '{"spec":{"enableCommonBootImageImport":false}}'
  fi
fi
found="$(oc get crd dataimportcrons.cdi.kubevirt.io --ignore-not-found -o name)"
if [[ -n "$found" ]]; then
  # Custom imports also block teardown; do not silently leave a PVC producer running.
  oc wait --for=delete dataimportcron --all -A --timeout=180s
fi
found="$(oc get crd bgpcloudconfigurations.networking.openshift.io --ignore-not-found -o name)"
if [[ -n "$found" ]]; then
  oc delete bgproutings.networking.openshift.io --all --ignore-not-found --wait=true --timeout=120s
  oc delete bgpcloudconfiguration cluster --ignore-not-found --wait=true --timeout=600s
else
  log 'BGPCloudConfiguration CRD absent; skipping BGP drain'
fi
found="$(oc get crd tridentbackendconfigs.trident.netapp.io --ignore-not-found -o name)"
if [[ -z "$found" ]]; then
  log 'Trident CRDs absent; nothing to drain'
  exit 0
fi
claims_json="$(oc get pvc -A -o json)"
claims="$(jq -ce --arg sc "$STORAGE_CLASS" '[.items[] | select(.spec.storageClassName == $sc) | {namespace: .metadata.namespace, name: .metadata.name, owners: (.metadata.ownerReferences // [])}]' <<<"$claims_json")"
pods="$(oc get pods -A -o json)"
consumers="$(jq -r --argjson claims "$claims" '
  .items[] as $pod | select(any($pod.spec.volumes[]?;
    .persistentVolumeClaim.claimName as $name | any($claims[];
      .namespace == $pod.metadata.namespace and .name == $name))) |
  "\($pod.metadata.namespace)/\($pod.metadata.name)"' <<<"$pods")"
[[ -z "$consumers" ]] || die "Stop storage consumers before cleanup: ${consumers}"
# Retained DataVolumes can recreate claims after a DataImportCron is removed.
# Resolve only actual owner UIDs of this storage class's claims; never match by name alone.
dv_refs="$(jq -c '[.[] as $claim | $claim.owners[]? | select(.kind == "DataVolume") |
  {namespace: $claim.namespace, name: .name, uid: .uid}] | unique_by([.namespace, .name, .uid])' <<<"$claims")"
if [[ "$(jq 'length' <<<"$dv_refs")" -gt 0 ]]; then
  dvs="$(oc get datavolumes.cdi.kubevirt.io -A -o json)"
  owned_dvs="$(jq -ce --argjson refs "$dv_refs" '[
    $refs[] as $ref | .items[] |
    select(.metadata.namespace == $ref.namespace and .metadata.name == $ref.name) |
    if .metadata.uid != $ref.uid then error("DataVolume ownership changed; refusing storage drain") else . end
  ]' <<<"$dvs")"
  controllers="$(jq -r '.[] | select(.metadata.deletionTimestamp == null) |
    select(any(.metadata.ownerReferences[]?; .kind == "VirtualMachine" or .kind == "VirtualMachinePool")) |
    "\(.metadata.namespace)/\(.metadata.name)"' <<<"$owned_dvs")"
  [[ -z "$controllers" ]] || die "Remove VM controllers owning DataVolumes before cleanup: ${controllers}"
  dv_rows="$(jq -r '.[] | [.metadata.namespace, .metadata.name, .metadata.uid] | @tsv' <<<"$owned_dvs")"
  while IFS=$'\t' read -r ns name uid; do
    [[ -z "$ns" ]] && continue
    log "Deleting DataVolume producer ${ns}/${name}"
    # Server-side preconditions protect replacements created after inventory.
    # A conflict (or any API failure) stops the drain before deleting claims.
    options="$(jq -cn --arg uid "$uid" '{apiVersion:"v1", kind:"DeleteOptions", preconditions:{uid:$uid}}')"
    oc delete --raw "/apis/cdi.kubevirt.io/v1beta1/namespaces/${ns}/datavolumes/${name}" -f - <<<"$options"
    oc -n "$ns" wait --for=delete "datavolume/${name}" --timeout=180s
  done <<<"$dv_rows"
fi
claim_rows="$(jq -r '.[] | [.namespace, .name] | @tsv' <<<"$claims")"
while IFS=$'\t' read -r ns name; do
  [[ -z "$ns" ]] && continue
  log "Deleting pvc/${name} in ${ns}"
  oc -n "$ns" delete pvc "$name" --ignore-not-found --wait=true --timeout=180s
done <<<"$claim_rows"
pvs="$(oc get pv -o json)"
pv_names="$(jq -r --arg sc "$STORAGE_CLASS" '.items[] | select(.spec.storageClassName == $sc) | .metadata.name' <<<"$pvs")"
while IFS= read -r pv; do
  [[ -z "$pv" ]] && continue
  oc delete pv "$pv" --ignore-not-found --wait=true --timeout=180s
done <<<"$pv_names"
log 'Kubernetes drain finished. Keep the backend and identities until Azure verifies the pool is empty.'
