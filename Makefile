.DEFAULT_GOAL := help
SHELL := /bin/bash
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TF_DIR := $(ROOT_DIR)/terraform
SCRIPTS := $(ROOT_DIR)/scripts

ARO_HCP_ROOT ?=
ARO_HCP_PROFILE ?=

.PHONY: help fmt lint test docs-venv docs-preview docs-build cluster.%

help: ## Show targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-28s %s\n", $$1, $$2}'
	@echo "Cluster operations: make cluster.<name>.<operation>"
	@echo "  init plan apply destroy cleanup bootstrap"
	@echo "Set ARO_HCP_ROOT to the installer checkout to refresh platform.json before apply."

cluster.%:
	@CLUSTER_PROFILE=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_PROFILE" ] || [ -z "$$OPERATION" ]; then \
		echo "Usage: make cluster.<name>.<operation>" >&2; exit 1; \
	fi; \
	if [ ! -d "$(ROOT_DIR)/clusters/$$CLUSTER_PROFILE" ]; then \
		echo "Missing clusters/$$CLUSTER_PROFILE" >&2; exit 1; \
	fi; \
	ARO_PROF="$(ARO_HCP_PROFILE)"; \
	[ -n "$$ARO_PROF" ] || ARO_PROF=$$CLUSTER_PROFILE; \
	$(MAKE) -f Makefile.cluster CLUSTER_PROFILE=$$CLUSTER_PROFILE ARO_HCP_ROOT="$(ARO_HCP_ROOT)" ARO_HCP_PROFILE="$$ARO_PROF" $$OPERATION

fmt: ## Format Terraform and shell
	terraform -chdir=$(TF_DIR) fmt -recursive
	terraform -chdir=$(ROOT_DIR)/modules/azure fmt
	@command -v shfmt >/dev/null && shfmt -w -i 2 -ci -bn $(SCRIPTS) || echo "shfmt not installed; skipping"

lint: ## Validate Terraform
	terraform -chdir=$(ROOT_DIR)/modules/azure init -backend=false -input=false
	terraform -chdir=$(ROOT_DIR)/modules/azure validate
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate
	@command -v shellcheck >/dev/null && (cd $(SCRIPTS) && shellcheck --external-sources *.sh) || echo "shellcheck not installed; skipping"

test: lint ## terraform test + bats
	terraform -chdir=$(ROOT_DIR)/modules/azure test
	@if command -v bats >/dev/null; then bats $(ROOT_DIR)/tests/bats; else echo "bats not installed; skipping"; fi

docs-venv:
	python3 -m venv $(ROOT_DIR)/.venv-docs
	$(ROOT_DIR)/.venv-docs/bin/pip install -q -r $(ROOT_DIR)/requirements-docs.txt

docs-preview: docs-venv ## Serve MkDocs locally
	$(ROOT_DIR)/.venv-docs/bin/mkdocs serve

docs-build: docs-venv ## mkdocs build --strict
	$(ROOT_DIR)/.venv-docs/bin/mkdocs build --strict
