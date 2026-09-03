# OpenShift virt / RWX storage

Second IaC run for **Azure NetApp Files + Trident CSI + OpenShift Virtualization**. This is **not** part of [`validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp) `make cluster.<name>.apply`.

Canonical install is **two GitHub checkouts**. Optional co-dev: gitignored `references/validated-pattern-openshift-virt` inside the installer.

## Operator path

```bash
# installer checkout
make cluster.my-cluster.apply
make cluster.my-cluster.kubeconfig
make cluster.my-cluster.external-auth
make cluster.my-cluster.bootstrap
make cluster.my-cluster.platform

# this checkout
cp -r clusters/aro-virt clusters/my-cluster   # or use clusters/aro-virt in place
ARO_HCP_ROOT=/path/to/validated-pattern-aro-hcp ARO_HCP_PROFILE=aro-virt \
  make cluster.aro-virt.apply
make cluster.aro-virt.bootstrap
```

Destroy **this stack first** (`make cluster.<name>.destroy` runs Trident/ANF volume cleanup, then Terraform). Then destroy the installer cluster.

Do not install a second Argo CD. Do not create ANF volumes in Terraform.

## Layout

```text
modules/azure/             # product: delegated subnet, ANF account+pool, identity
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
