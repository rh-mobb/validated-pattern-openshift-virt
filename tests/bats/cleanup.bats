#!/usr/bin/env bats
setup() {
  export PATH="${BATS_TEST_DIRNAME}/cleanup-bin:${PATH}"
  export CLEANUP_CALLS="${BATS_TEST_TMPDIR}/calls"
  export CLEANUP_SCENARIO=normal
}
@test "drain disables imports and waits before deleting storage" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -eq 0 ]
  patch=$(awk '/patch hyperconverged/ {print NR}' "$CLEANUP_CALLS")
  wait=$(awk '/wait.*dataimportcron/ {print NR}' "$CLEANUP_CALLS")
  claim=$(awk '/delete pvc/ {print NR}' "$CLEANUP_CALLS")
  [ "$patch" -lt "$wait" ]
  [ "$wait" -lt "$claim" ]
  ! grep -q 'delete tridentbackendconfig' "$CLEANUP_CALLS"
}
@test "active storage consumers stop cleanup before PVC deletion" {
  export CLEANUP_SCENARIO=consumer
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Stop storage consumers"* ]]
  ! grep -q 'delete pvc' "$CLEANUP_CALLS"
}
@test "BGP drain errors stop cleanup" {
  export CLEANUP_SCENARIO=bgp_error
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -ne 0 ]
  ! grep -q 'delete pvc' "$CLEANUP_CALLS"
}
@test "PVC inventory errors stop cleanup" {
  export CLEANUP_SCENARIO=inventory_error
  run bash "${BATS_TEST_DIRNAME}/../../scripts/trident-cleanup.sh"
  [ "$status" -ne 0 ]
  ! grep -q 'delete pvc' "$CLEANUP_CALLS"
}

run_make() {
  root="${BATS_TEST_DIRNAME}/../.."
  mkdir -p "${BATS_TEST_TMPDIR}/clusters/test"
  touch "${BATS_TEST_TMPDIR}/clusters/test/terraform.tfvars"
  make -f "$root/Makefile.cluster" ROOT_DIR="$BATS_TEST_TMPDIR" SCRIPTS="$root/scripts" CLUSTER_PROFILE=test "$1"
}

@test "Make destroy stops before backend and identity teardown when volumes remain" {
  export ANF_VOLUME_WAIT_SECONDS=0
  run run_make destroy
  [ "$status" -ne 0 ]
  [[ "$output" == *"ANF_DELETE_CONFIRM"* ]]
  ! grep -q 'terraform.*destroy' "$CLEANUP_CALLS"
  ! grep -q 'delete tridentbackendconfig' "$CLEANUP_CALLS"
}

@test "Make destroy removes backend and invokes Terraform only after confirmed Azure drain" {
  export ANF_VOLUME_WAIT_SECONDS=0
  export ANF_DELETE_CONFIRM=test-rg/test-anf/test-pool
  run run_make destroy
  [ "$status" -eq 0 ]
  volume=$(awk '/az netappfiles volume delete/ {print NR}' "$CLEANUP_CALLS")
  backend=$(awk '/delete tridentbackendconfig/ {print NR}' "$CLEANUP_CALLS")
  destroy=$(awk '/terraform.*destroy/ {print NR}' "$CLEANUP_CALLS")
  [ "$volume" -lt "$backend" ]
  [ "$backend" -lt "$destroy" ]
}

@test "Make ANF preview does not drain Kubernetes or delete volumes" {
  run run_make anf-preview
  [ "$status" -eq 0 ]
  ! grep -q 'delete\|patch' "$CLEANUP_CALLS"
}

@test "Make destroy validates Azure before changing Kubernetes" {
  export CLEANUP_SCENARIO=wrong_subscription
  export ANF_VOLUME_WAIT_SECONDS=0
  run run_make destroy
  [ "$status" -ne 0 ]
  [[ "$output" == *"subscription"* ]]
  ! grep -q 'delete pvc\|patch hyperconverged' "$CLEANUP_CALLS"
  ! grep -q 'terraform.*destroy' "$CLEANUP_CALLS"
}

@test "Make destroy resumes when state proves its ANF pool already removed" {
  export CLEANUP_SCENARIO=pool_removed
  run run_make destroy
  [ "$status" -eq 0 ]
  grep -q 'terraform.*destroy' "$CLEANUP_CALLS"
  ! grep -q 'az \|delete pvc\|patch hyperconverged' "$CLEANUP_CALLS"
}
