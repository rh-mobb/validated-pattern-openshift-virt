# Security

Please report vulnerabilities through [GitHub Security Advisories](https://github.com/rh-mobb/validated-pattern-openshift-virt/security/advisories/new) on this repository. Do not file a public issue for secrets, credentials, or exploitable bugs.

Do not commit:

- kubeconfig or cluster credentials
- Terraform state (`*.tfstate*`)
- operator `terraform.tfvars` copies (except committed examples)
- `platform.json`
- Entra / Key Vault / ANF secrets
- Red Hat pull secrets

This stack can create a billable Azure NetApp Files capacity pool. Treat live `apply` / `destroy` as operator-requested only.
