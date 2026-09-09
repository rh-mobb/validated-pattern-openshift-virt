# OpenShift virt / RWX storage

Second IaC run for **Azure NetApp Files + Trident CSI + OpenShift Virtualization + Azure Route Server**. This is **not** part of [`validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp) `make cluster.<name>.apply`.

Canonical install is **two GitHub checkouts**. Optional co-dev: gitignored `references/validated-pattern-openshift-virt` inside the installer.

## Operator path

Canonical e2e (both repos, verify, destroy): [installer Virt stack](https://rh-mobb.github.io/validated-pattern-aro-hcp/guides/virt-stack/).

```bash
# installer checkout
make cluster.aro-virt.apply
make cluster.aro-virt.kubeconfig
make cluster.aro-virt.external-auth
make cluster.aro-virt.bootstrap
make cluster.aro-virt.platform

# this checkout — use the installer kubeconfig
export ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp
export KUBECONFIG_PATH="${ARO_HCP_ROOT}/.kube/config"
ARO_HCP_ROOT="${ARO_HCP_ROOT}" ARO_HCP_PROFILE=aro-virt \
  make cluster.aro-virt.apply
make cluster.aro-virt.bootstrap
```

Destroy **this stack first** (`make cluster.<name>.destroy` drains BGP CRs then Trident/ANF volumes, then Terraform). Then destroy the installer cluster.

Do not install a second Argo CD. Do not create ANF volumes in Terraform.

## Layout

```text
modules/azure/             # product: ANF, Route Server, identities
terraform/                 # slim root — platform.json → module.azure
gitops/                    # Trident + OpenShift Virtualization (outside the Terraform module)
scripts/trident-cleanup.sh
clusters/azure/            # generic in-tree / module consume example
clusters/aro-virt/         # matches installer clusters/aro-virt
```

In-tree consume: `source = "git::https://github.com/rh-mobb/validated-pattern-openshift-virt.git//modules/azure?ref=<tag>"` in the deployer's root. Pin `ref` to a tag. GitOps and cleanup stay outside the module.

Agents: [`AGENTS.md`](AGENTS.md). Consume modes: [`docs/guides/consume.md`](docs/guides/consume.md). Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE).
