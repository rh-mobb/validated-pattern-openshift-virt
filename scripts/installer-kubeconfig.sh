#!/usr/bin/env bash
# Resolve kubeconfig path from sibling installer checkouts (OSD GCP or ARO HCP).
set -euo pipefail

resolve_installer_kubeconfig() {
  local root="${1:-}"
  local default="${2:-${root}/.kube/config}"

  if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
    printf '%s\n' "${KUBECONFIG_PATH}"
    return 0
  fi
  if [[ -n "${KUBECONFIG:-}" ]]; then
    printf '%s\n' "${KUBECONFIG}"
    return 0
  fi
  if [[ -n "${OSD_GCP_ROOT:-}" ]]; then
    local prof="${OSD_GCP_PROFILE:-virt}"
    printf '%s\n' "${OSD_GCP_ROOT}/.kube/config-${prof}"
    return 0
  fi
  if [[ -n "${ARO_HCP_ROOT:-}" ]]; then
    printf '%s\n' "${ARO_HCP_ROOT}/.kube/config"
    return 0
  fi
  printf '%s\n' "${default}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  resolve_installer_kubeconfig "${ROOT_DIR}"
fi