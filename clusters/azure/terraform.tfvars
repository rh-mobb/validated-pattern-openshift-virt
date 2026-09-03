# Path to installer platform.json (make cluster.<name>.platform in validated-pattern-aro-hcp).
# Canonical two-checkout: set ARO_HCP_ROOT and CLUSTER_PROFILE on make, or put an absolute path here.
# Nested co-dev clone: ../../../clusters/my-cluster/platform.json (from terraform/ via -var-file this file still evaluated from terraform chdir for file()).
platform_json = "../../../clusters/my-cluster/platform.json"

# pool_size_tib = 1
