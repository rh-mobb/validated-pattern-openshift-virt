"""Render real overlays and check scheduling and API-normalization contracts."""
import pathlib
import shutil
import subprocess
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]


def render(path):
    tool = shutil.which("kubectl") or shutil.which("oc")
    if not tool:
        raise RuntimeError("kubectl or oc is required for GitOps render tests")
    result = subprocess.run(
        [tool, "kustomize", str(ROOT / path)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise AssertionError(f"Kustomize render failed for {path}:\n{result.stderr}")
    return {
        (d["kind"], d["metadata"]["name"]): d
        for d in yaml.safe_load_all(result.stdout) if d
    }


class GitOpsPlacement(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.classic = render("gitops/overlays/azure-classic")
        cls.hcp = render("gitops/overlays/azure-hcp")
        cls.profile = render("gitops/profiles/aro-classic-virt")
        cls.legacy = render("gitops/overlays/azure")

    def test_operator_placement_is_platform_specific(self):
        self.assertNotIn("config", self.classic[("Subscription", "kubevirt-hyperconverged")]["spec"])
        self.assertEqual(
            self.hcp[("Subscription", "kubevirt-hyperconverged")]["spec"]["config"]["nodeSelector"],
            {"node-role.kubernetes.io/worker": ""},
        )
        self.assertEqual(self.legacy, self.hcp)
        self.assertEqual(set(self.classic), set(self.hcp))

    def test_shared_worker_agent_and_build_normalization(self):
        for objects in (self.classic, self.hcp, self.profile):
            pod = objects[("DaemonSet", "azure-nic-ip-forwarding")]["spec"]["template"]["spec"]
            self.assertEqual(pod["nodeSelector"], {
                "kubernetes.io/os": "linux", "node-role.kubernetes.io/worker": "",
            })
            self.assertIn({"operator": "Exists"}, pod["tolerations"])
            self.assertEqual(objects[("BuildConfig", "operator")]["spec"]["triggers"], [{"type": "ConfigChange"}])

    def test_pool_placement_belongs_to_profile(self):
        for objects in (self.classic, self.hcp):
            placement = objects[("HyperConverged", "kubevirt-hyperconverged")]["spec"]["workloads"]["nodePlacement"]
            self.assertNotIn("pool", placement["nodeSelector"])
            self.assertNotIn("tolerations", placement)
        hco = self.profile[("HyperConverged", "kubevirt-hyperconverged")]["spec"]
        self.assertEqual(hco["workloads"]["nodePlacement"], {
            "nodeSelector": {"node-role.kubernetes.io/worker": "", "pool": "np-virt"},
            "tolerations": [{"key": "workload", "operator": "Equal", "value": "virtualization", "effect": "NoSchedule"}],
        })
        self.assertEqual(hco["infra"]["nodePlacement"]["nodeSelector"], {"node-role.kubernetes.io/worker": ""})
        self.assertNotIn("config", self.profile[("Subscription", "kubevirt-hyperconverged")]["spec"])


if __name__ == "__main__":
    unittest.main()
