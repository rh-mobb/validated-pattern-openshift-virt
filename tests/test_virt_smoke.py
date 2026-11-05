import importlib.util
import contextlib
import io
import pathlib
import unittest
import tempfile
from unittest import mock

PATH = pathlib.Path(__file__).resolve().parents[1] / 'scripts/virt-smoke.py'
smoke = None
if PATH.exists():
    spec = importlib.util.spec_from_file_location('virt_smoke', PATH)
    smoke = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(smoke)


def obj(kind, name, status=None, namespace=None):
    return {'kind': kind, 'metadata': {'name': name, 'uid': name + '-uid', 'namespace': namespace}, 'status': status or {}, 'spec': {}}


def cond(**values): return [{'type': k, 'status': v} for k, v in values.items()]


def healthy():
    items = [
        obj('ClusterOperator', 'network', {'conditions': cond(Available='True', Progressing='False', Degraded='False')}),
        {**obj('Node', 'worker', {'conditions': cond(Ready='True')}), 'metadata': {'name': 'worker', 'uid': 'worker-uid', 'labels': {'node-role.kubernetes.io/worker': ''}}},
        obj('Application', 'virt-stack', {'sync': {'status': 'Synced', 'revision': 'abc'}, 'health': {'status': 'Healthy'}, 'operationState': {'phase': 'Succeeded'}}, 'openshift-gitops'),
        obj('ClusterSecretStore', 'customer-key-vault', {'conditions': cond(Ready='True')}),
        obj('HyperConverged', 'kubevirt-hyperconverged', {'conditions': cond(Available='True', Progressing='False', Degraded='False')}, 'openshift-cnv'),
        obj('TridentOrchestrator', 'trident', {'status': 'Installed'}),
        obj('TridentBackendConfig', 'anf-backend', {'phase': 'Bound'}, 'trident'),
        obj('BGPCloudConfiguration', 'cluster', {'phase': 'Ready'}),
        obj('BGPRouting', 'virt', {'phase': 'Ready'}),
        obj('DaemonSet', 'azure-nic-ip-forwarding', {'desiredNumberScheduled': 1, 'numberReady': 1, 'updatedNumberScheduled': 1, 'numberAvailable': 1}, 'openshift-bgp-cloud-connector'),
        obj('DaemonSet', 'frr-k8s', {'desiredNumberScheduled': 1, 'numberReady': 1, 'updatedNumberScheduled': 1, 'numberAvailable': 1}, 'openshift-frr-k8s'),
        obj('CDIConfig', 'config', {'defaultPodResourceRequirements': {'limits': {'memory': '4Gi'}}}),
        obj('DataImportCron', 'fedora-image-cron', {'conditions': cond(UpToDate='True', Progressing='False')}, 'openshift-virtualization-os-images'),
        obj('DataSource', 'fedora', {'conditions': cond(Ready='True')}, 'openshift-virtualization-os-images'),
        obj('DataVolume', 'fedora-image', {'phase': 'Succeeded'}, 'openshift-virtualization-os-images'),
        obj('PersistentVolumeClaim', 'fedora-image', {'phase': 'Bound'}, 'openshift-virtualization-os-images'),
        obj('Pod', 'trident-controller', {'phase': 'Running', 'conditions': cond(Ready='True'), 'containerStatuses': [{'name': 'main', 'restartCount': 0}]}, 'trident'),
    ]
    for ns in ['openshift-gitops', 'openshift-cnv', 'openshift-bgp-cloud-connector', 'openshift-frr-k8s', 'openshift-ovn-kubernetes']:
        items.append(obj('Pod', ns + '-pod', {'phase': 'Running', 'conditions': cond(Ready='True')}, ns))
    for name, ns in [('trident-controller', 'trident'), ('virt-api', 'openshift-cnv'), ('virt-controller', 'openshift-cnv'), ('virt-operator', 'openshift-cnv'), ('openshift-bgp-cloud-connector-controller-manager', 'openshift-bgp-cloud-connector')]:
        x = obj('Deployment', name, {'readyReplicas': 1, 'updatedReplicas': 1, 'availableReplicas': 1, 'observedGeneration': 1}, ns)
        x['metadata']['generation'] = 1; x['spec']['replicas'] = 1; items.append(x)
    items.append(obj('DaemonSet', 'virt-handler', {'desiredNumberScheduled': 1, 'numberReady': 1, 'updatedNumberScheduled': 1, 'numberAvailable': 1}, 'openshift-cnv'))
    items.append(obj('DaemonSet', 'trident-node-linux', {'desiredNumberScheduled': 1, 'numberReady': 1, 'updatedNumberScheduled': 1, 'numberAvailable': 1}, 'trident'))
    x = obj('StatefulSet', 'openshift-gitops-application-controller', {'readyReplicas': 1, 'availableReplicas': 1, 'updatedReplicas': 1, 'observedGeneration': 1, 'currentRevision': 'a', 'updateRevision': 'a'}, 'openshift-gitops')
    x['metadata']['generation'] = 1; x['spec']['replicas'] = 1; items.append(x)
    return items


class Clock:
    def __init__(self): self.t = 0
    def now(self): return self.t
    def sleep(self, seconds): self.t += seconds


class Readiness(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(smoke, 'smoke readiness implementation is missing')
        capture = contextlib.redirect_stdout(io.StringIO())
        capture.__enter__()
        self.addCleanup(capture.__exit__, None, None, None)

    def test_healthy_stack_and_missing_components(self):
        self.assertEqual(smoke.assess(healthy())['blockers'], [])
        for kind in ['Application', 'HyperConverged', 'BGPCloudConfiguration', 'DataSource', 'TridentBackendConfig', 'ClusterOperator', 'Node']:
            with self.subTest(kind=kind):
                self.assertTrue(smoke.assess([x for x in healthy() if x['kind'] != kind])['blockers'])

    def test_rollouts_and_imports_block_even_with_healthy_argo(self):
        cases = [('ClusterOperator', {'conditions': cond(Available='True', Progressing='True', Degraded='False')}),
                 ('DataVolume', {'phase': 'ImportInProgress'}), ('PersistentVolumeClaim', {'phase': 'Pending'}),
                 ('BGPCloudConfiguration', {'phase': 'Configuring'}), ('Pod', {'phase': 'Pending'}),
                 ('DaemonSet', {'desiredNumberScheduled': 1, 'numberReady': 0}),
                 ('DataImportCron', {'conditions': cond(UpToDate='False', Progressing='True')})]
        for kind, status in cases:
            with self.subTest(kind=kind):
                items = healthy(); next(x for x in items if x['kind'] == kind)['status'] = status
                self.assertTrue(smoke.assess(items)['blockers'])

    def test_completed_import_pods_are_not_pending_work(self):
        self.assertEqual(smoke.assess(healthy() + [obj('Pod', 'old-importer', {'phase': 'Succeeded'}, 'openshift-virtualization-os-images')])['blockers'], [])

    def test_restart_or_replacement_changes_fingerprint(self):
        items = healthy(); initial = smoke.assess(items)['fingerprint']
        pod = next(x for x in items if x['kind'] == 'Pod')
        pod['status']['containerStatuses'][0]['restartCount'] = 1
        self.assertNotEqual(initial, smoke.assess(items)['fingerprint'])
        pod['metadata']['uid'] = 'replacement'
        self.assertNotEqual(initial, smoke.assess(items)['fingerprint'])

    def test_unhealthy_sample_resets_continuous_window(self):
        clock = Clock()
        def observe(): return {'blockers': ['network rollout'] if clock.t == 1 else [], 'fingerprint': 'a'}
        smoke.wait_stable(observe, stable_seconds=3, timeout=10, poll=1, now=clock.now, sleep=clock.sleep, report=lambda _: None)
        self.assertEqual(clock.t, 5)

    def test_ready_but_changed_stack_must_settle_again(self):
        clock = Clock()
        def observe(): return {'blockers': [], 'fingerprint': 'a' if clock.t < 2 else 'b'}
        smoke.wait_stable(observe, stable_seconds=3, timeout=10, poll=1, now=clock.now, sleep=clock.sleep, report=lambda _: None)
        self.assertEqual(clock.t, 5)

    def test_timeout_and_api_errors_cannot_pass(self):
        clock = Clock()
        with self.assertRaisesRegex(RuntimeError, 'import pending'):
            smoke.wait_stable(lambda: {'blockers': ['import pending'], 'fingerprint': ''}, stable_seconds=2, timeout=3, poll=1, now=clock.now, sleep=clock.sleep, report=lambda _: None)
        with self.assertRaisesRegex(RuntimeError, 'Forbidden'):
            smoke.wait_stable(lambda: (_ for _ in ()).throw(RuntimeError('Forbidden')), stable_seconds=0, timeout=3)

    def test_unschedulable_workers_block_smoke(self):
        items = healthy(); next(x for x in items if x['kind'] == 'Node')['spec']['unschedulable'] = True
        self.assertTrue(smoke.assess(items)['blockers'])

    def test_slow_snapshot_cannot_pass_after_deadline(self):
        clock = Clock()
        def observe():
            if clock.t: clock.t += 10
            return {'blockers': [], 'fingerprint': 'a'}
        with self.assertRaisesRegex(RuntimeError, 'settle'):
            smoke.wait_stable(observe, stable_seconds=3, timeout=5, poll=1, now=clock.now, sleep=clock.sleep, report=lambda _: None)

    def test_disk_provisioning_must_be_followed_by_another_barrier(self):
        api = mock.Mock()
        api.create.return_value = {'metadata': {'uid': 'owned-ns'}}
        api.get.return_value = {'spec': {}, 'status': {'phase': 'Succeeded'}}
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', side_effect=[{}, RuntimeError('network rolling again')]):
            with self.assertRaisesRegex(RuntimeError, 'network rolling again'):
                smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
            self.assertNotIn('VirtualMachineInstance', [c.args[0]['kind'] for c in api.create.call_args_list])
            api.cleanup.assert_called_once()
            self.assertEqual(api.cleanup.call_args.args[1], 'owned-ns')

    def test_cleanup_refuses_replaced_namespace(self):
        api = smoke.Kube()
        api.get = mock.Mock(return_value={'metadata': {'uid': 'other'}})
        api.command = mock.Mock()
        with self.assertRaisesRegex(RuntimeError, 'UID'):
            api.cleanup('test', 'owned-ns')
        api.command.assert_not_called()

    def test_slow_object_read_cannot_succeed_past_deadline(self):
        api = mock.Mock()
        api.get.return_value = {'status': {'phase': 'Succeeded'}}
        with mock.patch.object(smoke.time, 'monotonic', side_effect=[0, 10]):
            with self.assertRaisesRegex(RuntimeError, 'Timed out'):
                smoke.wait_object(api, 'dv', 'root', 'test', lambda x: True, 5)

    def test_each_boot_is_gated_and_keeps_hco_placement(self):
        api = mock.Mock(); events = []; created = []
        def create(value):
            created.append(value); events.append(value['kind'])
            return {'metadata': {'uid': 'owned-ns'}}
        api.create.side_effect = create
        def get(kind, *args):
            if kind == 'hyperconverged':
                return {'spec': {'workloads': {'nodePlacement': {'nodeSelector': {'pool': 'my-virt'}, 'tolerations': [{'key': 'workload', 'operator': 'Exists'}]}}}}
            if kind == 'dv': return {'status': {'phase': 'Succeeded'}}
            if kind == 'vmi': return {'status': {'phase': 'Running', 'nodeName': 'worker', 'conditions': cond(Ready='True', AgentConnected='True')}}
            raise AssertionError(kind)
        api.get.side_effect = get
        api.remove.side_effect = lambda *a: events.append('removed')
        def settled(*args): events.append('barrier'); return {}
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', side_effect=settled):
            result = smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
        self.assertEqual([x['source'] for x in result['boots']], ['pvc', 'container'])
        self.assertEqual(events.count('barrier'), 3)
        for i, event in enumerate(events):
            if event == 'VirtualMachineInstance': self.assertEqual(events[i - 1], 'barrier')
        vmis = [x for x in created if x['kind'] == 'VirtualMachineInstance']
        self.assertTrue(all(x['spec']['nodeSelector'] == {'pool': 'my-virt'} for x in vmis))
        self.assertTrue(result['cleanup_complete'])

    def test_cleanup_error_prevents_success_result(self):
        api = mock.Mock(); api.create.return_value = {'metadata': {'uid': 'owned-ns'}}
        api.get.return_value = {'spec': {}, 'status': {'phase': 'Succeeded'}}
        api.cleanup.side_effect = RuntimeError('cleanup blocked')
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', side_effect=[{}, RuntimeError('rollout')]):
            with self.assertRaises(RuntimeError):
                smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
            import json
            result = json.loads(next(pathlib.Path(d).glob('*.json')).read_text())
            self.assertFalse(result['cleanup_complete'])
            self.assertEqual(result['cleanup_error'], 'cleanup blocked')

    def test_missing_controller_or_empty_pod_inventory_fails_closed(self):
        for kind in ('Deployment', 'Pod'):
            self.assertTrue(smoke.assess([x for x in healthy() if x['kind'] != kind])['blockers'])
        items = healthy(); dep = next(x for x in items if x['kind'] == 'Deployment')
        dep['metadata']['generation'] = 2
        self.assertTrue(smoke.assess(items)['blockers'])

    def test_initial_failure_report_exists_without_creating_namespace(self):
        api = mock.Mock()
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', side_effect=RuntimeError('network rolling')):
            with self.assertRaisesRegex(RuntimeError, 'network rolling'):
                smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
            import json
            reports = list(pathlib.Path(d).glob('*.json'))
            self.assertTrue(reports, 'initial failure must write diagnostic evidence')
            result = json.loads(reports[0].read_text())
            self.assertFalse(result['readiness'][0]['passed'])
            self.assertIsNone(result['namespace'])
        api.create.assert_not_called()
        api.cleanup.assert_not_called()

    def test_daemonset_stale_generation_and_disabled_gitops_controller_block(self):
        items = healthy(); ds = next(x for x in items if x['kind'] == 'DaemonSet')
        ds['metadata']['generation'] = 2; ds['status']['observedGeneration'] = 1
        self.assertTrue(smoke.assess(items)['blockers'])
        items = healthy(); controller = next(x for x in items if x['kind'] == 'StatefulSet')
        controller['spec']['replicas'] = 0
        controller['status'].update(readyReplicas=0, updatedReplicas=0)
        redis = obj('StatefulSet', 'redis-ha-server', {'observedGeneration': 1, 'readyReplicas': 1, 'updatedReplicas': 1, 'currentRevision': 'a', 'updateRevision': 'a'}, 'openshift-gitops')
        redis['spec']['replicas'] = 1; redis['metadata']['generation'] = 1; items.append(redis)
        self.assertTrue(smoke.assess(items)['blockers'])

    def test_ambiguous_namespace_create_does_not_claim_cleanup(self):
        api = mock.Mock(); api.create.side_effect = RuntimeError('request timed out')
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', return_value={}):
            with self.assertRaises(RuntimeError):
                smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
            import json
            result = json.loads(next(pathlib.Path(d).glob('*.json')).read_text())
            self.assertFalse(result['cleanup_complete'])
            self.assertIsNotNone(result['namespace'])
        api.cleanup.assert_not_called()

    def test_annotations_never_appear_in_readiness_or_namespace_diagnostics(self):
        import json
        items = healthy()
        for x in items: x['metadata']['annotations'] = {'clone-token': 'DO-NOT-LOG-CLONE-TOKEN'}
        self.assertNotIn('DO-NOT-LOG-CLONE-TOKEN', json.dumps(smoke.assess(items)))
        api = mock.Mock(); api.get.return_value = {'items': [x for x in items if x['kind'] == 'DataVolume']}
        self.assertNotIn('DO-NOT-LOG-CLONE-TOKEN', json.dumps(smoke.diagnostics(api, 'test')))

    def test_required_virt_handler_and_available_replicas(self):
        items = [x for x in healthy() if x['metadata']['name'] != 'virt-handler']
        self.assertTrue(smoke.assess(items)['blockers'])
        for kind, field in [('Deployment', 'availableReplicas'), ('DaemonSet', 'numberAvailable')]:
            items = healthy(); next(x for x in items if x['kind'] == kind)['status'][field] = 0
            self.assertTrue(smoke.assess(items)['blockers'])

    def test_initial_gate_failure_cannot_create_resources(self):
        api = mock.Mock()
        with tempfile.TemporaryDirectory() as d, mock.patch.object(smoke, 'settle', side_effect=RuntimeError('unsettled')):
            with self.assertRaisesRegex(RuntimeError, 'unsettled'):
                smoke.run_smoke(api, stable_seconds=2, timeout=10, output=pathlib.Path(d))
        api.create.assert_not_called()


if __name__ == '__main__': unittest.main()
