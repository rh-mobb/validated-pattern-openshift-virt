# Prerequisites

- An ARO HCP cluster from [`validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp) (`Succeeded`), with GitOps + ESO bootstrapped.
- Azure: `Microsoft.NetApp` registered; ANF capacity quota in the cluster region. Pool default is **1 TiB** Flexible (billable).
- Tools: Terraform `>= 1.9`, Azure CLI, `oc`, `jq`, `make`.
- Network: reserved CIDR `10.0.3.0/24` (installer `netapp_subnet_prefix`) must be free in the cluster VNet. Jump uses `10.0.2.0/28`.

Permissions: Contributor + User Access Administrator on the customer RG (custom role definition + assignment for Trident). OpenShift `cluster-admin` kubeconfig for GitOps bootstrap and cleanup.
