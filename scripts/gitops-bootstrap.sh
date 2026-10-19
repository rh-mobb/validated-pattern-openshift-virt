#!/usr/bin/env bash
# Plant Argo Application virt-stack and ConfigMaps anf-platform-metadata + bgp-platform-metadata.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
GITOPS_DIR="${ROOT_DIR}/gitops"
GITOPS_REPO="${GITOPS_REPO:-https://github.com/rh-mobb/validated-pattern-openshift-virt.git}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
GITOPS_PLATFORM="${GITOPS_PLATFORM:-hcp}"
GITOPS_PATH="${GITOPS_PATH:-gitops/overlays/azure-${GITOPS_PLATFORM}}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${ROOT_DIR}/.kube/config}"
GITOPS_DRY_RUN="${GITOPS_DRY_RUN:-}"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

case "${GITOPS_PLATFORM}" in
  classic | hcp) ;;
  *) die "GITOPS_PLATFORM must be classic or hcp" ;;
esac
# The path is also used locally for dry-run, so reject traversal and absolute paths.
[[ "${GITOPS_PATH}" =~ ^gitops/[a-zA-Z0-9_/-]+$ ]] || die "GITOPS_PATH must be a repository-relative gitops directory"
[[ -f "${ROOT_DIR}/${GITOPS_PATH}/kustomization.yaml" ]] || die "Missing ${GITOPS_PATH}/kustomization.yaml"

tf_raw() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

render_app() {
  awk -v repo="${GITOPS_REPO}" -v rev="${GITOPS_REVISION}" -v path="${GITOPS_PATH}" '
    $1 == "repoURL:" { printf "    repoURL: %s\n", repo; next }
    $1 == "path:" { printf "    path: %s\n", path; next }
    $1 == "targetRevision:" { printf "    targetRevision: %s\n", rev; next }
    { print }
  ' "${GITOPS_DIR}/argocd/root-application.yaml"
}

metadata_cm() {
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

if [[ -n "${GITOPS_DRY_RUN}" ]]; then
  render_app
  metadata_cm
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
render_app | oc apply -f -
log "Source: ${GITOPS_REPO}@${GITOPS_REVISION}, ${GITOPS_PATH}"
log "Applied virt-stack-gitops-controller, virt-stack Application, anf-platform-metadata, and bgp-platform-metadata"
