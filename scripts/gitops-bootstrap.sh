#!/usr/bin/env bash
# Plant Argo Application virt-stack and platform metadata ConfigMaps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
GITOPS_DIR="${ROOT_DIR}/gitops"
GITOPS_REPO="${GITOPS_REPO:-https://github.com/rh-mobb/validated-pattern-openshift-virt.git}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
GITOPS_PLATFORM="${GITOPS_PLATFORM:-hcp}"
GITOPS_OVERLAY="${GITOPS_OVERLAY:-}"
GITOPS_DRY_RUN="${GITOPS_DRY_RUN:-}"
# shellcheck source=installer-kubeconfig.sh
source "${SCRIPT_DIR}/installer-kubeconfig.sh"
KUBECONFIG_PATH="$(resolve_installer_kubeconfig "${ROOT_DIR}")"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

case "${GITOPS_PLATFORM}" in
  classic | hcp) ;;
  *) die "GITOPS_PLATFORM must be classic or hcp" ;;
esac

tf_raw() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

installer_type() {
  tf_raw installer
}

resolve_gitops_path() {
  if [[ -n "${GITOPS_PATH:-}" ]]; then
    printf '%s' "${GITOPS_PATH}"
    return
  fi
  if [[ -n "${GITOPS_OVERLAY}" ]]; then
    printf 'gitops/overlays/%s' "${GITOPS_OVERLAY}"
    return
  fi
  if [[ "$(installer_type)" == "osd-gcp" ]]; then
    printf '%s' "gitops/overlays/osd-gcp"
    return
  fi
  printf 'gitops/overlays/azure-%s' "${GITOPS_PLATFORM}"
}

GITOPS_PATH="$(resolve_gitops_path)"
# The path is also used locally for dry-run, so reject traversal and absolute paths.
[[ "${GITOPS_PATH}" =~ ^gitops/[a-zA-Z0-9_/-]+$ ]] || die "GITOPS_PATH must be a repository-relative gitops directory"
[[ -f "${ROOT_DIR}/${GITOPS_PATH}/kustomization.yaml" ]] || die "Missing ${GITOPS_PATH}/kustomization.yaml"

is_osd_gcp() {
  [[ "$(installer_type)" == "osd-gcp" || "${GITOPS_PATH}" == "gitops/overlays/osd-gcp" || "${GITOPS_OVERLAY}" == "osd-gcp" ]]
}

wait_for_cnv_operator() {
  local timeout="${1:-900}"
  local end=$((SECONDS + timeout))
  log "waiting for CNV operator CSV and webhooks (up to ${timeout}s)..."
  while ((SECONDS < end)); do
    if oc get crd hyperconvergeds.hco.kubevirt.io >/dev/null 2>&1; then
      local phase
      phase="$(oc get csv -n openshift-cnv -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | head -1)"
      if [[ "${phase}" == "Succeeded" ]] \
        && oc get endpoints hco-webhook-service -n openshift-cnv -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -qE '^[0-9]+\.'; then
        log "CNV operator and admission webhooks ready"
        return 0
      fi
    fi
    sleep 20
  done
  die "timeout waiting for CNV operator / HyperConverged CRD"
}

render_app() {
  awk -v repo="${GITOPS_REPO}" -v rev="${GITOPS_REVISION}" -v path="${GITOPS_PATH}" '
    $1 == "repoURL:" { printf "    repoURL: %s\n", repo; next }
    $1 == "path:" { printf "    path: %s\n", path; next }
    $1 == "targetRevision:" { printf "    targetRevision: %s\n", rev; next }
    { print }
  ' "${GITOPS_DIR}/argocd/root-application.yaml"
}

anf_bgp_metadata() {
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: anf-platform-metadata
  namespace: openshift-gitops
data:
  tridentClientId: "$(tf_raw trident_client_id)"
  subscriptionId: "$(tf_raw subscription_id)"
  tenantId: "$(tf_raw tenant_id)"
  location: "$(tf_raw location)"
  resourceGroupName: "$(tf_raw resource_group_name)"
  vnetName: "$(tf_raw vnet_name)"
  subnetName: "$(tf_raw subnet_name)"
  netappAccountName: "$(tf_raw netapp_account_name)"
  capacityPoolName: "$(tf_raw capacity_pool_name)"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: bgp-platform-metadata
  namespace: openshift-gitops
data:
  bgpClientId: "$(tf_raw bgp_client_id)"
  networkInterfaceClientId: "$(tf_raw network_interface_client_id)"
  subscriptionId: "$(tf_raw subscription_id)"
  resourceGroupName: "$(tf_raw resource_group_name)"
  routeServerName: "$(tf_raw route_server_name)"
EOF
}

gcp_metadata() {
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: gcp-virt-platform-metadata
  namespace: openshift-gitops
data:
  gcpProjectId: "$(tf_raw gcp_project_id)"
  gcpRegion: "$(tf_raw gcp_region)"
  storageZone: "$(tf_raw storage_zone)"
  storagePoolName: "$(tf_raw storage_pool_name)"
  storagePoolPath: "$(tf_raw storage_pool_path)"
  storageClassName: "$(tf_raw storage_class_name)"
  cloudRouterName: "$(tf_raw bgp_cloud_router_name)"
  nccHubName: "$(tf_raw bgp_ncc_hub_name)"
  nccSpokePrefix: "$(tf_raw bgp_ncc_spoke_prefix)"
  bgpLocalAsn: "$(tf_raw bgp_local_asn)"
  bgpRouterNodeSelectorKey: "$(tf_raw bgp_router_node_selector_key)"
  bgpRouterNodeSelectorValue: "$(tf_raw bgp_router_node_selector_value)"
  gcpProjectNumber: "$(tf_raw bgp_gcp_project_number)"
  wifPoolId: "$(tf_raw bgp_wif_pool_id)"
  wifProviderId: "$(tf_raw bgp_wif_provider_id)"
  wifKubernetesTokenAudience: "$(tf_raw bgp_wif_kubernetes_token_audience)"
  bgpGcpServiceAccountEmail: "$(tf_raw bgp_gcp_service_account_email)"
EOF
}

metadata_cm() {
  if is_osd_gcp; then
    gcp_metadata
  else
    anf_bgp_metadata
  fi
}

# OSD GCP: Hyperdisk StorageClass + image VolumeSnapshotClass (TF outputs).
# TODO(gitops): replace bootstrap apply with a small Helm chart + Application helm.parameters,
# or kustomize placeholders + ignoreDifferences — see clusters/osd-gcp-virt/AGENTS.md.
apply_osd_gcp_hyperdisk_storage() {
  [[ "$(installer_type)" == "osd-gcp" ]] || return 0
  local pool sc
  pool="$(tf_raw storage_pool_path)"
  sc="$(tf_raw storage_class_name)"
  [[ -n "${pool}" && -n "${sc}" ]] || die "missing storage_pool_path/storage_class_name (run make cluster.<profile>.apply first)"
  if [[ -n "${GITOPS_DRY_RUN}" ]]; then
    log "osd-gcp: would apply StorageClass ${sc} (pool=${pool})"
    return 0
  fi
  oc apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${sc}
  annotations:
    storageclass.kubevirt.io/is-default-virt-class: "true"
allowVolumeExpansion: true
parameters:
  storage-pools: ${pool}
  type: hyperdisk-balanced
provisioner: pd.csi.storage.gke.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-gce-pd-vsc-images
driver: pd.csi.storage.gke.io
deletionPolicy: Delete
parameters:
  snapshot-type: images
EOF
  log "applied Hyperdisk StorageClass ${sc} and VolumeSnapshotClass csi-gce-pd-vsc-images"
}

if [[ -n "${GITOPS_DRY_RUN}" ]]; then
  render_app
  metadata_cm
  apply_osd_gcp_hyperdisk_storage
  if command -v oc >/dev/null 2>&1; then
    oc kustomize "${ROOT_DIR}/${GITOPS_PATH}"
  elif command -v kubectl >/dev/null 2>&1; then
    kubectl kustomize "${ROOT_DIR}/${GITOPS_PATH}"
  fi
  exit 0
fi

command -v oc >/dev/null || die "oc is required"
export KUBECONFIG="${KUBECONFIG_PATH}"
oc get ns openshift-gitops >/dev/null 2>&1 || die "openshift-gitops missing. Run installer make cluster.<name>.bootstrap first."
oc whoami >/dev/null 2>&1 || die "Cannot reach the API."

# cluster-admin for openshift-gitops-argocd-application-controller must exist
# before virt-stack's first sync (ImageStream, TridentOrchestrator, …). Wave -1
# inside the Application is not enough when ApplyOutOfSyncOnly retries skip it.
oc apply -f "${GITOPS_DIR}/base/gitops-controller-rbac.yaml"

metadata_cm | oc apply -f -
apply_osd_gcp_hyperdisk_storage
render_app | oc apply -f -
if [[ "${GITOPS_SYNC_LOCAL:-}" == "1" ]]; then
  log "GITOPS_SYNC_LOCAL=1: applying ${GITOPS_PATH} directly (branch not on remote yet)"
  set +e
  oc apply -k "${ROOT_DIR}/${GITOPS_PATH}" 2>&1 | tee /tmp/virt-local-kustomize-apply.log
  apply_rc=${PIPESTATUS[0]}
  set -e
  if ((apply_rc != 0)); then
    if grep -qE 'HyperConverged|hco-webhook' /tmp/virt-local-kustomize-apply.log 2>/dev/null; then
      wait_for_cnv_operator
      oc apply -k "${ROOT_DIR}/${GITOPS_PATH}"
    else
      exit "${apply_rc}"
    fi
  fi
fi
log "Source: ${GITOPS_REPO}@${GITOPS_REVISION}, ${GITOPS_PATH}"
if is_osd_gcp; then
  log "Applied virt-stack-gitops-controller, virt-stack Application, and gcp-virt-platform-metadata"
else
  log "Applied virt-stack-gitops-controller, virt-stack Application, anf-platform-metadata, and bgp-platform-metadata"
fi
