#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export GITOPS_DRY_RUN=1
  export TF_DATA_DIR="${BATS_TEST_DIRNAME}/tmp"
  mkdir -p "${BATS_TEST_DIRNAME}/tmp"
}

@test "gitops dry-run includes trident-operator subscription" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: trident-operator"* ]]
  [[ "$output" == *"source: certified-operators"* ]]
  [[ "$output" == *"name: anf-virt"* ]]
  [[ "$output" == *"name: kubevirt-hyperconverged"* ]]
  [[ "$output" == *"source: redhat-operators"* ]]
  [[ "$output" == *"kind: Application"* ]]
  [[ "$output" == *"name: rwx-storage"* ]]
  [[ "$output" == *"name: rwx-storage-gitops-controller"* ]]
  [[ "$output" == *"name: cluster-admin"* ]]
  [[ "$output" == *"name: trident-from-metadata"* ]]
  [[ "$output" == *"tridentorchestrators"* ]]
  [[ "$output" == *"customresourcedefinitions"* ]]
  [[ "$output" == *"name: bgp-platform-metadata"* ]]
  [[ "$output" == *"name: bgp-from-metadata"* ]]
  [[ "$output" == *"kind: BuildConfig"* ]]
  [[ "$output" == *"name: operator"* ]]
  [[ "$output" == *"networkInterfaceClientId:"* ]]
}

@test "sample CUDN is BGPRouting plus namespace, not a ClusterUserDefinedNetwork" {
  ns="${BATS_TEST_DIRNAME}/../../gitops/samples/cudn/namespace.yaml"
  rt="${BATS_TEST_DIRNAME}/../../gitops/samples/cudn/bgprouting.yaml"
  grep -q 'k8s.ovn.org/primary-user-defined-network: ""' "${ns}"
  grep -q 'cluster-udn: virt' "${ns}"
  grep -q 'pod-security.kubernetes.io/enforce: privileged' "${ns}"
  grep -q 'kind: BGPRouting' "${rt}"
  grep -q 'name: virt' "${rt}"
  grep -q '192.168.100.0/24' "${rt}"
  ! grep -q 'kind: ClusterUserDefinedNetwork' "${BATS_TEST_DIRNAME}/../../gitops/samples/cudn/"*.yaml
}

@test "trident-from-metadata job sets Standard networkFeatures" {
  job="${BATS_TEST_DIRNAME}/../../gitops/operators/trident/from-metadata-job.yaml"
  grep -q 'networkFeatures: Standard' "${job}"
}

@test "bgp-from-metadata job sets networkInterfaceClientID from metadata" {
  job="${BATS_TEST_DIRNAME}/../../gitops/operators/bgp-cloud-connector/from-metadata-job.yaml"
  grep -q 'networkInterfaceClientId' "${job}"
  grep -q 'networkInterfaceClientID:' "${job}"
  grep -q 'AZURE_CLIENT_ID' "${job}"
  grep -q 'rollout restart' "${job}"
  grep -q 'wait_for "AZURE_CLIENT_ID on manager pods"' "${job}"
}

@test "cleanup is idempotent when trident CRDs are absent" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleanup finished"* ]] || [[ "$output" == *"Trident CRDs absent"* ]] || [[ "$output" == *"BGPCloudConfiguration CRD absent"* ]]
}
