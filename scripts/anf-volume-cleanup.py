#!/usr/bin/env python3
"""Preview or drain one attachment's ANF pool before Terraform removes identities."""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import uuid

FIELDS = ("subscription_id", "resource_group_name", "netapp_account_name", "capacity_pool_name")


def azure(args):
    result = subprocess.run(["az", *args, "--only-show-errors", "--output", "json"],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Azure command failed: {result.stderr.strip()}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def clean(scope, *, apply=False, confirm="", wait_seconds=600, run=azure, sleep=time.sleep):
    if any(not isinstance(scope.get(k), str) or not scope[k].strip() for k in FIELDS):
        raise RuntimeError("Missing Terraform ANF scope; refusing Azure cleanup")
    try:
        uuid.UUID(scope["subscription_id"])
    except ValueError as exc:
        raise RuntimeError("Invalid subscription ID") from exc
    for key in FIELDS[1:]:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.()\-]*", scope[key]):
            raise RuntimeError(f"Invalid ANF scope field: {key}")
    sub, rg, account, pool = (scope[k] for k in FIELDS)
    prefix = f"/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.NetApp/netAppAccounts/{account}/capacityPools/{pool}"
    token = f"{rg}/{account}/{pool}"
    flags = ["--subscription", sub, "--resource-group", rg, "--account-name", account, "--pool-name", pool]
    if run(["account", "show"])["id"].lower() != sub.lower():
        raise RuntimeError("Active Azure subscription does not match Terraform pool scope")
    print(f"ANF scope: {prefix}", flush=True)

    def inventory():
        volumes = run(["netappfiles", "volume", "list", *flags])
        if not isinstance(volumes, list):
            raise RuntimeError("Azure inventory was not a volume list")
        for v in volumes:
            vid = v.get("id", "")
            expected = prefix + "/volumes/"
            if not isinstance(vid, str) or not vid.lower().startswith(expected.lower()):
                raise RuntimeError("Volume outside the confirmed ANF pool; refusing deletion")
            name = vid[len(expected):]
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.\-]*", name):
                raise RuntimeError("Invalid volume ID; refusing deletion")
        return volumes

    def wait_empty(volumes):
        deadline = time.monotonic() + wait_seconds
        while volumes and time.monotonic() < deadline:
            print(f"Waiting for {len(volumes)} ANF volume(s) to disappear", flush=True)
            sleep(min(10, max(0, deadline - time.monotonic())))
            volumes = inventory()
        return volumes

    volumes = inventory()
    for v in volumes:
        print(f"  {v['id']} ({v.get('provisioningState', 'unknown')})", flush=True)
    if not apply:
        print(f"Preview only. Direct leftover deletion requires ANF_DELETE_CONFIRM={token}")
        return
    # Give CSI time to release volumes before considering direct Azure deletion.
    volumes = wait_empty(volumes)
    if volumes:
        if confirm != token:
            raise RuntimeError(f"Pool still contains volumes; set ANF_DELETE_CONFIRM={token} only for a confirmed full teardown")
        for v in volumes:
            if v.get("provisioningState", "").lower() == "deleting":
                continue
            name = v["id"].rsplit("/", 1)[1]
            print(f"Deleting confirmed leftover ANF volume: {name}", flush=True)
            run(["netappfiles", "volume", "delete", *flags, "--name", name, "--yes"])
        volumes = wait_empty(inventory())
    if volumes:
        raise RuntimeError("ANF pool is not empty; Terraform destroy must not continue")
    print("ANF pool verified empty; Terraform teardown may proceed", flush=True)


def scope_from_state(state):
    # A failed full destroy can remove every output while retaining the pool.
    # Read its exact managed ARM ID instead of guessing names from a profile.
    if state.get("version") != 4 or not isinstance(state.get("resources"), list):
        raise RuntimeError("Invalid Terraform state; cannot establish ANF ownership")
    pools = [r for r in state["resources"] if r.get("mode") == "managed"
             and r.get("type") == "azurerm_netapp_pool" and r.get("instances")]
    if not pools:
        return None
    if len(pools) != 1 or pools[0].get("module") != "module.azure" or pools[0].get("name") != "this" or len(pools[0]["instances"]) != 1:
        raise RuntimeError("Ambiguous Terraform ANF pool ownership")
    arm_id = pools[0]["instances"][0]["attributes"].get("id", "")
    match = re.fullmatch(
        r"/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.NetApp/netAppAccounts/([^/]+)/capacityPools/([^/]+)",
        arm_id, re.IGNORECASE,
    )
    if not match:
        raise RuntimeError("Invalid managed ANF pool ID in Terraform state")
    return dict(zip(FIELDS, match.groups()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--apply", action="store_true", help="Wait for CSI, then delete confirmed leftovers; default is preview")
    modes.add_argument("--drain", action="store_true", help="Preflight, drain Kubernetes, verify Azure empty, then remove backend")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    result = subprocess.run(["terraform", f"-chdir={root / 'terraform'}", "state", "pull"],
                            capture_output=True, text=True, check=True)
    scope = scope_from_state(json.loads(result.stdout))
    if scope is None:
        print("Terraform state owns no ANF pool; skipping storage drain (no Azure absence claim)")
        return
    wait = int(os.environ.get("ANF_VOLUME_WAIT_SECONDS", "600"))
    if not 0 <= wait <= 7200:
        raise RuntimeError("ANF_VOLUME_WAIT_SECONDS must be between 0 and 7200")
    if args.drain:
        clean(scope)  # Read-only Azure preflight before any Kubernetes mutation.
        subprocess.run(["bash", str(root / "scripts/trident-cleanup.sh")], check=True)
    clean(scope, apply=args.apply or args.drain, confirm=os.environ.get("ANF_DELETE_CONFIRM", ""), wait_seconds=wait)
    if args.drain:
        subprocess.run(["bash", str(root / "scripts/trident-cleanup.sh"), "--backend-only"], check=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit(f"ERROR: {exc}")
