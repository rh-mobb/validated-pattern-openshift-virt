#!/usr/bin/env bash
# Drain Trident PVs / ANF volumes so terraform destroy can delete the pool.
# Safe to re-run. Does not terraform destroy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${ROOT_DIR}/.kube/config}"
STORAGE_CLASS="${STORAGE_CLASS:-anf-virt}"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: trident-cleanup.sh

Deletes BGPCloudConfiguration / BGPRouting (so Azure Route Server peerings
drain), then PVCs/PVs using STORAGE_CLASS (default anf-virt) and
TridentBackendConfig anf-backend. Requires oc and a kubeconfig. Does not run
terraform destroy.
EOF
  exit 0
fi

command -v oc >/dev/null || die "oc is required"
export KUBECONFIG="${KUBECONFIG_PATH}"
oc whoami >/dev/null 2>&1 || die "Cannot reach the API (oc whoami failed). Set KUBECONFIG."

if oc get crd bgpcloudconfigurations.networking.openshift.io >/dev/null 2>&1; then
  log "Deleting BGPRouting and BGPCloudConfiguration so the operator can drop Azure peerings"
  oc delete bgproutings.networking.openshift.io --all --ignore-not-found --wait=true --timeout=120s || true
  oc delete bgpcloudconfiguration cluster --ignore-not-found --wait=true --timeout=300s || true
else
  log "BGPCloudConfiguration CRD absent; skipping BGP drain"
fi

if ! oc get crd tridentbackendconfigs.trident.netapp.io >/dev/null 2>&1; then
  log "Trident CRDs absent; nothing to drain"
  exit 0
fi

log "Deleting PVCs that use StorageClass ${STORAGE_CLASS}"
mapfile -t pvcs < <(oc get pvc -A -o jsonpath='{range .items[?(@.spec.storageClassName=="'"${STORAGE_CLASS}"'")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
for line in "${pvcs[@]:-}"; do
  [[ -z "${line}" ]] && continue
  ns="${line%% *}"
  name="${line##* }"
  log "Deleting pvc/${name} in ${ns}"
  oc -n "${ns}" delete pvc "${name}" --wait=true --timeout=180s || true
done

log "Deleting PVs still bound to ${STORAGE_CLASS}"
mapfile -t pvs < <(oc get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="'"${STORAGE_CLASS}"'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
for pv in "${pvs[@]:-}"; do
  [[ -z "${pv}" ]] && continue
  log "Deleting pv/${pv}"
  oc delete pv "${pv}" --wait=true --timeout=180s || true
done

if oc -n trident get tridentbackendconfig anf-backend >/dev/null 2>&1; then
  log "Deleting TridentBackendConfig anf-backend"
  oc -n trident delete tridentbackendconfig anf-backend --wait=true --timeout=180s || true
fi

log "Cleanup finished. Remaining ANF volumes in Azure, if any, must be deleted before terraform destroy of the pool."
