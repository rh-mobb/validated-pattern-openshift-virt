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
  [[ "$output" == *"kind: Application"* ]]
  [[ "$output" == *"name: rwx-storage"* ]]
}

@test "cleanup is idempotent when trident CRDs are absent" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Trident CRDs absent"* ]] || [[ "$output" == *"Cleanup finished"* ]]
}
