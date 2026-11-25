# GCP OpenShift Virtualization storage (OSD)

This slice targets **OSD on GCP** (`platform.json` with `installer = "osd-gcp"`). It does **not** use Azure NetApp Files or Trident.

| Azure (ARO) | GCP (OSD) equivalent |
|-------------|----------------------|
| ANF delegated subnet + capacity pool | **Hyperdisk Balanced zonal storage pool** (`gcloud compute storage-pools create`) |
| Trident CSI + `anf-virt` StorageClass | **`pd.csi.storage.gke.io`** + `sp-balanced-storage` |
| Trident provisions NFS volumes | CSI provisions disks from the storage pool |

[Google Cloud NetApp Volumes](https://cloud.google.com/netapp/volumes/docs) is a separate product; Red Hat’s GA OpenShift Virtualization on GCP path documented for CCS uses **Hyperdisk**, not GCNV.

Terraform creates **`google_compute_storage_pool`**. **`make cluster.<profile>.bootstrap`** applies StorageClass/VSC from TF outputs (interim; TODO: Helm params on `virt-stack`). StorageProfile RWX remains GitOps (CNV overlay job).

**BGP (parity with `modules/azure` route server):** when `enable_bgp` is true (default), Terraform creates an **NCC hub**, a dedicated **Cloud Router** with two interfaces on the OSD worker subnet, and BGP/CUDN firewall rules. Root stack `gcp_bgp_operator_iam` (`modules/gcp-bgp-operator-iam`) adds a GCP SA + OCM WIF impersonation for bgp-cloud-connector (**CCO** path). Outputs feed `gcp-virt-platform-metadata` for `bgp-from-metadata`.