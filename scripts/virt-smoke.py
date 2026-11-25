#!/usr/bin/env python3
"""Wait for a continuously healthy virt stack, then boot disposable smoke VMIs."""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import time
import uuid

NAMESPACES = {'openshift-gitops', 'openshift-cnv', 'trident', 'openshift-bgp-cloud-connector',
              'openshift-frr-k8s', 'openshift-ovn-kubernetes', 'openshift-virtualization-os-images'}
IMAGES = 'openshift-virtualization-os-images'
RESOURCES = ('clusteroperators,nodes,applications.argoproj.io,clustersecretstores.external-secrets.io,'
             'hyperconvergeds.hco.kubevirt.io,tridentorchestrators.trident.netapp.io,'
             'tridentbackendconfigs.trident.netapp.io,bgpcloudconfigurations.networking.openshift.io,'
             'bgproutings.networking.openshift.io,daemonsets.apps,deployments.apps,statefulsets.apps,pods,cdiconfigs.cdi.kubevirt.io,'
             'dataimportcrons.cdi.kubevirt.io,datasources.cdi.kubevirt.io,datavolumes.cdi.kubevirt.io,pvc')


def condition(obj, name, value='True'):
    return any(c.get('type') == name and c.get('status') == value
               for c in obj.get('status', {}).get('conditions', []))


def assess(items):
    """Return safe diagnostics only: never retain annotations, tokens or full objects."""
    blockers, fingerprint = [], []

    def check(ok, detail):
        if not ok: blockers.append(detail)

    def group(kind): return [x for x in items if x['kind'] == kind]

    def one(kind, name, namespace=None):
        matches = [x for x in group(kind) if x['metadata']['name'] == name and
                   (namespace is None or x['metadata'].get('namespace') == namespace)]
        check(len(matches) == 1, f'{kind}/{name}: missing or ambiguous')
        return matches[0] if len(matches) == 1 else {}

    for kind in ('ClusterOperator', 'Node'):
        check(bool(group(kind)), f'{kind}: inventory empty')
    for x in group('ClusterOperator'):
        check(condition(x, 'Available') and condition(x, 'Progressing', 'False') and condition(x, 'Degraded', 'False'),
              f"ClusterOperator/{x['metadata']['name']}: unavailable, progressing or degraded")
    for x in group('Node'):
        check(condition(x, 'Ready'), f"Node/{x['metadata']['name']}: not Ready")
        if 'node-role.kubernetes.io/worker' in x['metadata'].get('labels', {}):
            check(not x.get('spec', {}).get('unschedulable'), f"Node/{x['metadata']['name']}: worker cordoned")
        fingerprint.append(('Node', x['metadata']['uid']))
    app = one('Application', 'virt-stack', 'openshift-gitops').get('status', {})
    check(app.get('sync', {}).get('status') == 'Synced' and app.get('health', {}).get('status') == 'Healthy'
          and app.get('operationState', {}).get('phase') == 'Succeeded', 'virt-stack: sync not completed and healthy')
    fingerprint.append(('revision', app.get('sync', {}).get('revision')))
    check(condition(one('ClusterSecretStore', 'customer-key-vault'), 'Ready'), 'customer-key-vault: not Ready')
    hco = one('HyperConverged', 'kubevirt-hyperconverged', 'openshift-cnv')
    check(condition(hco, 'Available') and condition(hco, 'Progressing', 'False') and condition(hco, 'Degraded', 'False'), 'CNV: not settled')
    check(one('TridentOrchestrator', 'trident').get('status', {}).get('status') == 'Installed', 'Trident: not Installed')
    check(one('TridentBackendConfig', 'anf-backend', 'trident').get('status', {}).get('phase') == 'Bound', 'ANF backend: not Bound')
    for kind, name in [('BGPCloudConfiguration', 'cluster'), ('BGPRouting', 'virt')]:
        check(one(kind, name).get('status', {}).get('phase') == 'Ready', f'{kind}/{name}: not Ready')
    for name, ns in [('azure-nic-ip-forwarding', 'openshift-bgp-cloud-connector'), ('frr-k8s', 'openshift-frr-k8s'), ('trident-node-linux', 'trident'), ('virt-handler', 'openshift-cnv')]:
        ds = one('DaemonSet', name, ns)
        status = ds.get('status', {})
        desired = status.get('desiredNumberScheduled', 0)
        check(status.get('observedGeneration', 0) >= ds.get('metadata', {}).get('generation', 0)
              and desired > 0 and status.get('numberReady') == desired and status.get('numberAvailable', 0) == desired and status.get('updatedNumberScheduled') == desired
              and not status.get('numberUnavailable', 0), f'DaemonSet/{name}: rollout incomplete')
    for name, ns in [('trident-controller', 'trident'), ('virt-api', 'openshift-cnv'),
                     ('virt-controller', 'openshift-cnv'), ('virt-operator', 'openshift-cnv'),
                     ('openshift-bgp-cloud-connector-controller-manager', 'openshift-bgp-cloud-connector')]:
        controller = one('Deployment', name, ns)
        check(controller.get('spec', {}).get('replicas', 1) > 0, f'Deployment/{name}: scaled down')
    controller = one('StatefulSet', 'openshift-gitops-application-controller', 'openshift-gitops')
    check(bool(controller) and controller.get('spec', {}).get('replicas', 1) > 0, 'GitOps application controller: missing or disabled')
    for kind in ('Deployment', 'StatefulSet'):
        for x in group(kind):
            if x['metadata'].get('namespace') not in NAMESPACES: continue
            status, meta = x.get('status', {}), x['metadata']
            desired = x.get('spec', {}).get('replicas', 1)
            check(status.get('observedGeneration', -1) >= meta.get('generation', 0)
                  and status.get('readyReplicas', 0) == desired and status.get('updatedReplicas', 0) == desired
                  and (kind != 'Deployment' or status.get('availableReplicas', 0) == desired),
                  f"{kind}/{meta['name']}: rollout incomplete")
            if kind == 'StatefulSet' and desired:
                check(bool(status.get('currentRevision')) and status.get('currentRevision') == status.get('updateRevision'),
                      f"StatefulSet/{meta['name']}: revision not converged")
            fingerprint.append((kind, meta['uid'], meta.get('generation')))
    cdi = one('CDIConfig', 'config').get('status', {}).get('defaultPodResourceRequirements', {})
    check(cdi.get('limits', {}).get('memory') == '4Gi', 'CDI: expected 4Gi importer memory limit')
    check(condition(one('DataSource', 'fedora', IMAGES), 'Ready'), 'Fedora image: not Ready')
    crons = [x for x in group('DataImportCron') if x['metadata'].get('namespace') == IMAGES]
    check(bool(crons), 'Base-image imports: no configured DataImportCrons')
    for x in crons:
        check(condition(x, 'UpToDate') and condition(x, 'Progressing', 'False'), f"DataImportCron/{x['metadata']['name']}: import not settled")
    for kind, phase in [('DataVolume', 'Succeeded'), ('PersistentVolumeClaim', 'Bound')]:
        for x in group(kind):
            if x['metadata'].get('namespace') == IMAGES:
                check(x.get('status', {}).get('phase') == phase, f"{kind}/{x['metadata']['name']}: not {phase}")
                fingerprint.append((kind, x['metadata']['uid']))
    active_namespaces = set()
    for x in group('Pod'):
        if x['metadata'].get('namespace') not in NAMESPACES: continue
        status, meta = x.get('status', {}), x['metadata']
        if status.get('phase') in ('Succeeded', 'Failed'): continue  # Historical Jobs are not active work.
        active_namespaces.add(meta.get('namespace'))
        check(not meta.get('deletionTimestamp') and status.get('phase') == 'Running' and condition(x, 'Ready'),
              f"Pod/{meta.get('namespace')}/{meta['name']}: not Ready or terminating")
        restarts = tuple(sorted((c['name'], c.get('restartCount', 0)) for c in status.get('containerStatuses', [])))
        fingerprint.append(('Pod', meta['uid'], restarts))
    for ns in sorted(NAMESPACES - {IMAGES}):
        check(ns in active_namespaces, f'{ns}: no active stack Pods')
    return {'blockers': blockers, 'fingerprint': sorted(fingerprint, key=str)}


class ReadinessError(RuntimeError):
    def __init__(self, message, assessment):
        super().__init__(message)
        self.assessment = assessment


def wait_stable(observe, *, stable_seconds=120, timeout=1800, poll=10, now=time.monotonic, sleep=time.sleep, report=print):
    if stable_seconds < 0 or timeout <= stable_seconds or poll <= 0:
        raise ValueError('Require timeout > stable seconds >= 0 and poll > 0')
    deadline, since, previous = now() + timeout, None, None
    while True:
        try:
            sample = observe()
        except RuntimeError as exc:
            raise ReadinessError(f'Readiness API failed: {exc}', {'blockers': ['API inventory failed']}) from exc
        t = now()
        if sample['blockers']:
            since = None
            report('Waiting: ' + '; '.join(sample['blockers']))
        elif since is None or sample['fingerprint'] != previous:
            since = t
            report(f'Healthy snapshot; starting {stable_seconds}s stability window')
        previous = sample['fingerprint']
        if t >= deadline:
            detail = '; '.join(sample['blockers']) or 'health kept changing; continuous stability window not reached'
            raise ReadinessError('Stack did not settle: ' + detail, sample)
        if not sample['blockers'] and t - since >= stable_seconds:
            return sample
        sleep(min(poll, deadline - t))


class Kube:
    def __init__(self):
        self.env = dict(os.environ)
        self.env['KUBECONFIG'] = os.environ.get('KUBECONFIG_PATH') or os.environ.get('KUBECONFIG') or str(pathlib.Path(__file__).resolve().parents[1] / '.kube/config')

    def command(self, args, body=None, timeout=60):
        try:
            p = subprocess.run(['oc', *args, '--request-timeout=20s'], env=self.env,
                               input=json.dumps(body) if body is not None else None,
                               capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError('oc request timed out') from exc
        if p.returncode:
            raise RuntimeError(f"oc {' '.join(args[:3])} failed: {p.stderr.strip()}")
        return p.stdout

    def get(self, kind, name=None, namespace=None):
        args = ['get', kind] + ([name] if name else []) + (['-n', namespace] if namespace else ['-A'])
        return json.loads(self.command(args + ['-o', 'json']))

    def create(self, obj):
        return json.loads(self.command(['create', '-f', '-', '-o', 'json'], obj))

    def remove(self, kind, name, namespace):
        self.command(['delete', kind, name, '-n', namespace, '--wait=true', '--timeout=180s'], timeout=200)

    def cleanup(self, namespace, uid):
        current = self.get('namespace', namespace)
        if current['metadata']['uid'] != uid:
            raise RuntimeError('Smoke namespace UID changed; refusing cleanup')
        pvs = [x['metadata']['name'] for x in self.get('pv')['items']
               if x.get('spec', {}).get('claimRef', {}).get('namespace') == namespace]
        self.command(['delete', '--raw', f'/api/v1/namespaces/{namespace}', '-f', '-'],
                     {'apiVersion': 'v1', 'kind': 'DeleteOptions', 'preconditions': {'uid': uid}})
        self.command(['wait', '--for=delete', f'namespace/{namespace}', '--timeout=180s'], timeout=200)
        for pv in pvs:
            self.command(['wait', '--for=delete', f'pv/{pv}', '--timeout=600s'], timeout=620)


def collect(api): return assess(api.get(RESOURCES)['items'])


def settle(api, stable_seconds, timeout):
    return wait_stable(lambda: collect(api), stable_seconds=stable_seconds, timeout=timeout)


def wait_object(api, kind, name, namespace, predicate, deadline):
    while time.monotonic() < deadline:
        value = api.get(kind, name, namespace)
        if time.monotonic() >= deadline: break
        if predicate(value): return value
        if value.get('status', {}).get('phase') in ('Failed', 'Unknown'):
            raise RuntimeError(f'{kind}/{name}: failed')
        time.sleep(min(5, max(0, deadline - time.monotonic())))
    raise RuntimeError(f'Timed out waiting for {kind}/{name}')


def diagnostics(api, namespace):
    result = {}
    for kind in ('vmi', 'dv', 'pvc', 'pods', 'events'):
        try:
            value = api.get(kind, namespace=namespace)
            # In particular, CDI annotations contain clone tokens. Never dump raw objects.
            result[kind] = [{'name': x['metadata']['name'], 'phase': x.get('status', {}).get('phase'),
                             'conditions': x.get('status', {}).get('conditions'),
                             'reason': x.get('reason'), 'message': x.get('message'),
                             'containers': [{k: c.get(k) for k in ('name', 'ready', 'restartCount', 'state', 'imageID')}
                                            for c in x.get('status', {}).get('containerStatuses', [])]}
                            for x in value.get('items', [])]
            if kind == 'pods':
                result['launch_events'] = []
                for pod in value.get('items', []):
                    if not any(c['name'] == 'compute' for c in pod.get('spec', {}).get('containers', [])): continue
                    logs = api.command(['logs', '-n', namespace, pod['metadata']['name'], '-c', 'compute', '--tail=200'])
                    for line in logs.splitlines():
                        try: event = json.loads(line)
                        except ValueError: continue
                        if event.get('msg') in ('Domain defined.', 'Domain started.', 'Synced vmi', 'Signaled vmi deletion'):
                            result['launch_events'].append({'pod': pod['metadata']['name'], 'time': event.get('timestamp'), 'message': event['msg']})
        except RuntimeError as exc: result[kind] = {'error': str(exc)}
    return result


def run_smoke(api, *, stable_seconds, timeout, output, boot_source='both', ready_only=False):
    deadline = time.monotonic() + timeout
    output.mkdir(parents=True, exist_ok=True)
    name = ('stack-ready-' if ready_only else 'virt-smoke-') + uuid.uuid4().hex[:10]
    report = {'namespace': None, 'stable_seconds': stable_seconds, 'readiness': [], 'boots': [], 'cleanup_complete': False}
    owner, failure, attempted_namespace = None, None, False
    def barrier():
        try:
            assessment = settle(api, stable_seconds, deadline - time.monotonic())
            report['readiness'].append({'passed': True, 'assessment': assessment})
            print(f'Stack stable for {stable_seconds}s', flush=True)
        except Exception as exc:
            report['readiness'].append({'passed': False, 'error': str(exc), 'assessment': getattr(exc, 'assessment', None)})
            raise
    try:
        barrier()  # No namespace, PVC or VM may be created before this succeeds.
        if ready_only: return report
        attempted_namespace = True
        report['namespace'] = name
        owner = api.create({'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': name, 'labels': {'app.kubernetes.io/part-of': 'virt-smoke'}}})
        report['namespace'] = name
        print(f'Smoke namespace: {name}', flush=True)
        placement = api.get('hyperconverged', 'kubevirt-hyperconverged', 'openshift-cnv').get('spec', {}).get('workloads', {}).get('nodePlacement', {})
        scheduling = {k: placement[k] for k in ('nodeSelector', 'tolerations', 'affinity') if k in placement}
        scheduling.setdefault('nodeSelector', {'node-role.kubernetes.io/worker': ''})
        disks = [('data', {'blank': {}})]
        if boot_source in ('pvc', 'both'): disks.append(('root', None))
        for disk, source in disks:
            print(f'Preparing {disk} disk', flush=True)
            spec = {'storage': {'storageClassName': 'anf-virt', 'accessModes': ['ReadWriteMany'], 'volumeMode': 'Filesystem', 'resources': {'requests': {'storage': '100Gi' if disk == 'data' else '50Gi'}}}}
            if source is not None: spec['source'] = source
            else: spec['sourceRef'] = {'kind': 'DataSource', 'name': 'fedora', 'namespace': IMAGES}
            api.create({'apiVersion': 'cdi.kubevirt.io/v1beta1', 'kind': 'DataVolume', 'metadata': {'name': disk, 'namespace': name}, 'spec': spec})
            wait_object(api, 'dv', disk, name, lambda x: x.get('status', {}).get('phase') == 'Succeeded', deadline)
        sources = ['pvc', 'container'] if boot_source == 'both' else [boot_source]
        for source in sources:
            barrier()  # Also settle after CSI provisioning and before EACH VM creation.
            root = {'dataVolume': {'name': 'root'}} if source == 'pvc' else {'containerDisk': {'image': 'quay.io/containerdisks/fedora:42'}}
            vmi = {'apiVersion': 'kubevirt.io/v1', 'kind': 'VirtualMachineInstance', 'metadata': {'name': 'boot-' + source, 'namespace': name},
                   'spec': {**scheduling,
                            'domain': {'cpu': {'cores': 1}, 'resources': {'requests': {'memory': '1Gi'}},
                                       'devices': {'disks': [{'name': n, 'disk': {'bus': 'virtio'}} for n in ('rootdisk', 'data', 'cloudinit')],
                                                   'interfaces': [{'name': 'default', 'masquerade': {}}]}},
                            'networks': [{'name': 'default', 'pod': {}}],
                            'volumes': [{'name': 'rootdisk', **root}, {'name': 'data', 'dataVolume': {'name': 'data'}},
                                        {'name': 'cloudinit', 'cloudInitNoCloud': {'userData': '#cloud-config\nruncmd:\n  - [sh, -c, "echo VIRT_SMOKE_BOOTED > /dev/ttyS0"]\n'}}]}}
            print(f'Starting {source} VM', flush=True)
            api.create(vmi)
            value = wait_object(api, 'vmi', vmi['metadata']['name'], name,
                                lambda x: x.get('status', {}).get('phase') == 'Running' and condition(x, 'Ready') and condition(x, 'AgentConnected'), deadline)
            report['boots'].append({'source': source, 'node': value['status']['nodeName'], 'phase': value['status']['phase'], 'guest_os': value['status'].get('guestOSInfo')})
            print(f'{source} boot: Running/Ready with guest agent', flush=True)
            api.remove('vmi', vmi['metadata']['name'], name)
    except (Exception, KeyboardInterrupt) as exc:
        failure = exc
        report['error'] = str(exc)
        if owner is not None: report['diagnostics'] = diagnostics(api, name)
    finally:
        try:
            if owner is not None:
                print(f'Cleaning smoke namespace {name}', flush=True)
                api.cleanup(name, owner['metadata']['uid'])
            elif attempted_namespace:
                raise RuntimeError('Namespace creation outcome unknown; verify the reported namespace manually')
            report['cleanup_complete'] = True
        except Exception as exc:
            report['cleanup_error'] = str(exc)
            if failure is None: failure = exc
        (output / (name + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    if failure is not None: raise RuntimeError(f'Smoke failed; see {output / (name + ".json")}: {failure}') from failure
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ready-only', action='store_true', help='Read-only readiness and stability gate')
    parser.add_argument('--stable-seconds', type=int, default=120)
    parser.add_argument('--timeout', type=int, default=1800, help='Overall test deadline, excluding cleanup')
    parser.add_argument('--boot-source', choices=('pvc', 'container', 'both'), default='both')
    parser.add_argument('--output-dir', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1] / 'clusters/aro-virt/logs/virt-smoke')
    args = parser.parse_args()
    if args.stable_seconds < 0 or args.timeout <= args.stable_seconds:
        parser.error('Require timeout > stable-seconds >= 0')
    api = Kube()
    run_smoke(api, stable_seconds=args.stable_seconds, timeout=args.timeout, output=args.output_dir, boot_source=args.boot_source, ready_only=args.ready_only)


if __name__ == '__main__':
    try: main()
    except (RuntimeError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
