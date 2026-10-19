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
claims="$(jq -ce --arg sc "$STORAGE_CLASS" '[.items[] | select(.spec.storageClassName == $sc) | {namespace: .metadata.namespace, name: .metadata.name}]' <<<"$claims_json")"
pods="$(oc get pods -A -o json)"
consumers="$(jq -r --argjson claims "$claims" '
  .items[] as $pod | select(any($pod.spec.volumes[]?;
    .persistentVolumeClaim.claimName as $name | any($claims[];
      .namespace == $pod.metadata.namespace and .name == $name))) |
  "\($pod.metadata.namespace)/\($pod.metadata.name)"' <<<"$pods")"
[[ -z "$consumers" ]] || die "Stop storage consumers before cleanup: ${consumers}"
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
