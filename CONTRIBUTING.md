# Contributing

Thank you for contributing to **validated-pattern-openshift-virt**. This repository is the Azure NetApp Files + Trident (later CNV) sibling of [`validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp). Cluster create stays in the installer.

By contributing you agree that your work is licensed under the [Apache License 2.0](LICENSE).

## Prerequisites

- Git, Make, Terraform >= 1.9
- Azure CLI (`az`) for live deploys
- OpenShift CLI (`oc`) for GitOps bootstrap and Trident
- `shellcheck`, `shfmt`, TFLint (optional locally; required in CI)
- `bats` for script tests
- Python 3.12+ for docs (`pip install -r requirements-docs.txt`)

Do not commit kubeconfig, Terraform state, operator `terraform.tfvars` copies (except the committed examples), or `platform.json`.

## Workflow

1. Fork (or clone `rh-mobb/validated-pattern-openshift-virt`) and branch from `main`.
2. Use Conventional Commits and a feature branch (`feat/…`, `fix/…`). Do not commit to `main`.
3. Run `make fmt lint test` before opening a PR.
4. Update `docs/architecture.md` when Azure resources, RBAC, Make targets, or CIDRs change.
5. Update `CHANGELOG.md` **only in the same commit**, and only for `git diff --cached` vs `HEAD`. Skip `chore` / `test` / `style` with no operator-visible effect.
6. Open a PR using the template. Link issues with `Closes #N`.

Do not add `Co-authored-by: Cursor` or other AI trailers.

## Make targets

```bash
make fmt          # terraform fmt + shfmt
make lint         # terraform validate (+ tflint/shellcheck when installed)
make test         # lint + terraform test (modules/azure) + bats
make docs-preview # MkDocs at http://127.0.0.1:8000
make docs-build   # mkdocs build --strict
```

Cluster operations: `make cluster.<name>.{init,plan,apply,bootstrap,cleanup,destroy}`. Live Azure apply/destroy only when the operator asked. Destroy this stack **before** the installer cluster.

Set `ARO_HCP_ROOT` to an installer checkout to refresh `platform.json` before apply. Example ingest path for a nested co-dev clone: `clusters/azure/terraform.tfvars`.

## Code style

- Terraform: `terraform fmt`, descriptions on variables/outputs, no ANF **volumes** in Terraform (Trident owns those).
- Shell: `set -euo pipefail`, quote expansions, `shellcheck --external-sources`.
- GitOps YAML: keep StorageClass `anf-virt`; do not steal `managed-csi`.

## Pull requests

CI runs `make fmt lint test` on pull requests and on `main`. Docs deploy to GitHub Pages from `main` when `docs/` or `mkdocs.yml` change.

## License

Contributions are Apache License 2.0.
