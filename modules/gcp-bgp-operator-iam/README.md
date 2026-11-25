# gcp-bgp-operator-iam

GCP service account, custom IAM role, and **OCM WIF pool** `workloadIdentityUser` binding for [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) on OSD GCP.

OpenShift wiring (sibling GitOps): `bgp-from-metadata` sets manager `PROJECT_NUMBER`, `POOL_ID`, `PROVIDER_ID`, and `SERVICE_ACCOUNT_EMAIL` so **CCO** writes `bgp-cloud-connector-gcp-credentials` (`external_account` + projected token audience `openshift`).

Inputs resolve from installer `platform.json` (`wif_config_id`, `eso.wif_provider_resource_name`). Pattern mirrors [osd-gcp-cudn-routing `osd-bgp-controller-iam`](https://github.com/rh-mobb/osd-gcp-cudn-routing) and validated-pattern-osd-gcp `osd-eso-iam`.