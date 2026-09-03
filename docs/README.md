# Documentation

Published site: TBD (MkDocs Material, same pattern as [validated-pattern-aro-hcp](https://rh-mobb.github.io/validated-pattern-aro-hcp/)). Local preview: `make docs-preview`.

Keep structure, voice, and changelog rules aligned with the ARO HCP installer sibling so operators and agents switching repos see one convention.

| Document | Purpose |
|----------|---------|
| [Prerequisites](prerequisites/index.md) | ANF quota, `Microsoft.NetApp`, tools |
| [Full-stack](prerequisites/full-stack.md) | Workflow and least-privilege permissions per `make` target |
| [Consume](guides/consume.md) | Second IaC run vs in-tree `module` block |
| [Architecture](architecture.md) | Resultant Azure/OpenShift resources, CIDRs, destroy order |

## Sibling docs

Cluster, VNet, reserved CIDR `10.0.3.0/24`, jump `10.0.2.0/28`, OIDC, Key Vault: [ARO HCP architecture](https://rh-mobb.github.io/validated-pattern-aro-hcp/architecture/). Do not duplicate that inventory here; link it and document only what this stack adds.
