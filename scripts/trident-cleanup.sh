#!/usr/bin/env bash
# Drain in-cluster virt storage (ANF/Trident or GCP Hyperdisk) so terraform destroy can delete the pool.
# Safe to re-run. Does not terraform destroy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=installer-kubeconfig.sh
source "${SCRIPT_DIR}/installer-kubeconfig.sh"

KUBECONFIG_PATH="$(resolve_installer_kubeconfig "${ROOT_DIR}")"
STORAGE_CLASS="${STORAGE_CLASS:-anf-virt}"
GCP_STORAGE_CLASS="${GCP_STORAGE_CLASS:-sp-balanced-storage}"
GITOPS_APP_NAMESPACE="${GITOPS_APP_NAMESPACE:-openshift-gitops}"
GITOPS_APP_NAME="${GITOPS_APP_NAME:-virt-stack}"
PVC_WAIT_TIMEOUT="${PVC_WAIT_TIMEOUT:-300s}"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: trident-cleanup.sh

Deletes the sibling virt-stack Argo CD Application (so GitOps does not
recreate BGP/Trident CRs), then BGPCloudConfiguration / BGPRouting, then
storage drain:

  - Azure: PVCs/PVs on STORAGE_CLASS (default anf-virt) and TridentBackendConfig
  - GCP osd-gcp: HyperConverged / CNV subscription, then PVCs on
    GCP_STORAGE_CLASS (default sp-balanced-storage)

Requires oc and a kubeconfig (KUBECONFIG_PATH, KUBECONFIG, OSD_GCP_ROOT, or
ARO_HCP_ROOT). Does not run terraform destroy.
EOF
  exit 0
fi

command -v oc >/dev/null || die "oc is required"
export KUBECONFIG="${KUBECONFIG_PATH}"
oc whoami >/dev/null 2>&1 || {
  die "Cannot reach the API (oc whoami failed). Expected kubeconfig ${KUBECONFIG_PATH} (set KUBECONFIG_PATH, or OSD_GCP_ROOT + OSD_GCP_PROFILE)."
}

if oc get crd applications.argoproj.io >/dev/null 2>&1; then
  if oc -n "${GITOPS_APP_NAMESPACE}" get application "${GITOPS_APP_NAME}" >/dev/null 2>&1; then
    log "Deleting Argo CD Application ${GITOPS_APP_NAME} (namespace ${GITOPS_APP_NAMESPACE}) so GitOps does not recreate BGP/Trident CRs during cleanup"
    oc -n "${GITOPS_APP_NAMESPACE}" delete application "${GITOPS_APP_NAME}" --ignore-not-found --wait=false || true
  else
    log "Argo CD Application ${GITOPS_APP_NAME} absent; skipping GitOps pause"
  fi
else
  log "Argo CD Application CRD absent; skipping GitOps pause"
fi

if oc get crd bgpcloudconfigurations.networking.openshift.io >/dev/null 2>&1; then
  log "Deleting BGPRouting and BGPCloudConfiguration so the BGP operator can drop cloud peerings"
  oc delete bgproutings.networking.openshift.io --all --ignore-not-found --wait=true --timeout=120s || true
  oc delete bgpcloudconfiguration cluster --ignore-not-found --wait=true --timeout=300s || true
else
  log "BGPCloudConfiguration CRD absent; skipping BGP drain"
fi

delete_pvcs_for_storage_class() {
  local sc="$1"
  log "Deleting PVCs that use StorageClass ${sc}"
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    ns="${line%% *}"
    name="${line##* }"
    log "Deleting pvc/${name} in ${ns}"
    oc -n "${ns}" delete pvc "${name}" --wait=true --timeout="${PVC_WAIT_TIMEOUT}" || true
  done < <(oc get pvc -A -o jsonpath='{range .items[?(@.spec.storageClassName=="'"${sc}"'")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  log "Deleting PVs still bound to ${sc}"
  while IFS= read -r pv; do
    [[ -z "${pv}" ]] && continue
    log "Deleting pv/${pv}"
    oc delete pv "${pv}" --wait=true --timeout="${PVC_WAIT_TIMEOUT}" || true
  done < <(oc get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="'"${sc}"'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
}

drain_gcp_hyperdisk() {
  if ! oc get storageclass "${GCP_STORAGE_CLASS}" >/dev/null 2>&1; then
    log "StorageClass ${GCP_STORAGE_CLASS} absent; skipping GCP Hyperdisk drain"
    return 0
  fi

  if oc get crd hyperconvergeds.hco.kubevirt.io >/dev/null 2>&1; then
    if oc -n openshift-cnv get hyperconverged kubevirt-hyperconverged >/dev/null 2>&1; then
      log "Deleting HyperConverged (stops CDI from recreating image PVCs on the Hyperdisk pool)"
      oc -n openshift-cnv delete hyperconverged kubevirt-hyperconverged --ignore-not-found --wait=false || true
    fi
    oc -n openshift-cnv delete subscription kubevirt-hyperconverged --ignore-not-found --wait=false || true
    sleep 15
  fi

  delete_pvcs_for_storage_class "${GCP_STORAGE_CLASS}"
  log "GCP Hyperdisk drain finished; pool must have disk_count=0 before terraform destroy."
}

if oc get crd tridentbackendconfigs.trident.netapp.io >/dev/null 2>&1; then
  delete_pvcs_for_storage_class "${STORAGE_CLASS}"
  if oc -n trident get tridentbackendconfig anf-backend >/dev/null 2>&1; then
    log "Deleting TridentBackendConfig anf-backend"
    oc -n trident delete tridentbackendconfig anf-backend --wait=true --timeout=180s || true
  fi
  log "ANF drain finished. Remaining NetApp volumes in Azure, if any, must be deleted before terraform destroy of the pool."
else
  log "Trident CRDs absent; skipping ANF drain"
  drain_gcp_hyperdisk
fi

log "Cleanup finished."