"""Exercise Azure cleanup scoping, confirmation, failures and delayed deletion."""
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts/anf-volume-cleanup.py"
if PATH.exists():
    spec = importlib.util.spec_from_file_location("anf_cleanup", PATH)
    cleanup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cleanup)
else:
    cleanup = None

SUB = "00000000-0000-0000-0000-000000000004"
SCOPE = {"subscription_id": SUB, "resource_group_name": "test-rg", "netapp_account_name": "test-anf", "capacity_pool_name": "test-pool"}
PREFIX = f"/subscriptions/{SUB}/resourceGroups/test-rg/providers/Microsoft.NetApp/netAppAccounts/test-anf/capacityPools/test-pool"
CONFIRM = "test-rg/test-anf/test-pool"


class FakeAzure:
    def __init__(self, inventories):
        self.inventories = iter(inventories)
        self.calls = []

    def __call__(self, args):
        self.calls.append(args)
        if args[:2] == ["account", "show"]:
            return {"id": SUB}
        if args[:3] == ["netappfiles", "volume", "list"]:
            return next(self.inventories)
        if args[:3] == ["netappfiles", "volume", "delete"]:
            return None
        raise AssertionError(args)


def volume(name="pvc-123", prefix=PREFIX, state="Succeeded"):
    return {"id": f"{prefix}/volumes/{name}", "name": f"test-anf/test-pool/{name}", "provisioningState": state}


class AnfCleanup(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(cleanup, "ANF cleanup implementation is missing")

    def run_cleanup(self, azure, apply=False, confirm=""):
        return cleanup.clean(SCOPE, apply=apply, confirm=confirm, wait_seconds=0, run=azure, sleep=lambda _: None)

    def test_preview_never_deletes(self):
        az = FakeAzure([[volume()]])
        self.run_cleanup(az)
        self.assertFalse(any(c[:3] == ["netappfiles", "volume", "delete"] for c in az.calls))

    def test_nonempty_pool_requires_exact_confirmation(self):
        for confirm in ("", "yes", "other-rg/test-anf/test-pool"):
            az = FakeAzure([[volume()]])
            with self.assertRaisesRegex(RuntimeError, "ANF_DELETE_CONFIRM"):
                self.run_cleanup(az, True, confirm)
            self.assertFalse(any(c[:3] == ["netappfiles", "volume", "delete"] for c in az.calls))

    def test_empty_pool_needs_no_deletion_confirmation(self):
        self.run_cleanup(FakeAzure([[]]), True)

    def test_confirmed_delete_uses_only_the_scoped_volume_name(self):
        az = FakeAzure([[volume()], []])
        self.run_cleanup(az, True, CONFIRM)
        delete = next(c for c in az.calls if c[:3] == ["netappfiles", "volume", "delete"])
        self.assertEqual(delete, ["netappfiles", "volume", "delete", "--subscription", SUB,
                                 "--resource-group", "test-rg", "--account-name", "test-anf",
                                 "--pool-name", "test-pool", "--name", "pvc-123", "--yes"])

    def test_wrong_scope_or_subscription_never_deletes(self):
        for bad in (volume(prefix=PREFIX.replace("test-rg", "other-rg")), volume(name="a/b")):
            az = FakeAzure([[bad]])
            with self.assertRaises(RuntimeError):
                self.run_cleanup(az, True, CONFIRM)
            self.assertFalse(any(c[:3] == ["netappfiles", "volume", "delete"] for c in az.calls))

    def test_subscription_mismatch_fails_before_inventory(self):
        with self.assertRaisesRegex(RuntimeError, "subscription"):
            self.run_cleanup(lambda _: {"id": "wrong"}, True, CONFIRM)

    def test_inventory_error_is_not_an_empty_pool(self):
        az = FakeAzure([])
        def run(args):
            if args[:2] == ["account", "show"]:
                return {"id": SUB}
            raise RuntimeError("Azure authorization failed")
        with self.assertRaisesRegex(RuntimeError, "authorization"):
            self.run_cleanup(run, True, CONFIRM)

    def test_delete_must_finish_before_success(self):
        az = FakeAzure([[volume()], [volume(state="Deleting")]])
        with self.assertRaisesRegex(RuntimeError, "not empty"):
            self.run_cleanup(az, True, CONFIRM)

    def test_csi_deletion_during_grace_period_needs_no_force_confirmation(self):
        az = FakeAzure([[volume()], []])
        clock = [0]
        def sleep(seconds):
            clock[0] += seconds
        with patch.object(cleanup.time, "monotonic", side_effect=lambda: clock[0]):
            cleanup.clean(SCOPE, apply=True, wait_seconds=10, run=az, sleep=sleep)
        self.assertFalse(any(c[:3] == ["netappfiles", "volume", "delete"] for c in az.calls))

    def test_delete_errors_abort(self):
        az = FakeAzure([[volume()]])
        def run(args):
            if args[:3] == ["netappfiles", "volume", "delete"]:
                raise RuntimeError("Volume deletion failed")
            return az(args)
        with self.assertRaisesRegex(RuntimeError, "deletion failed"):
            self.run_cleanup(run, True, CONFIRM)

    def test_scope_survives_partial_destroy_without_outputs(self):
        state = {"version": 4, "resources": [{"module": "module.azure", "mode": "managed", "type": "azurerm_netapp_pool", "name": "this", "instances": [{"attributes": {"id": PREFIX}}]}]}
        self.assertEqual(cleanup.scope_from_state(state), SCOPE)

    def test_removed_pool_is_distinct_from_invalid_state(self):
        self.assertIsNone(cleanup.scope_from_state({"version": 4, "resources": []}))
        for bad in ({}, {"version": 4, "resources": None}):
            with self.assertRaises(RuntimeError):
                cleanup.scope_from_state(bad)

    def test_missing_scope_is_rejected(self):
        with self.assertRaises(RuntimeError):
            cleanup.clean({}, run=FakeAzure([]))


if __name__ == "__main__":
    unittest.main()
