"""Controller installer isolation tests. All paths stay in a temporary directory."""
import base64
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'assets' / 'vps_exit'
spec = importlib.util.spec_from_file_location('vps_install', SOURCE / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def bundle():
    return {'files': {name: base64.b64encode((SOURCE/name).read_bytes()).decode() for name in installer.FILES},
            'sha256': json.loads((SOURCE/'manifest.json').read_text())}


EXITS = {'direct': {'ip': '192.0.2.1', 'label': 'VPS direct'}, 'au': {'ip': '198.51.100.1', 'label': 'Residential'}}
CONFIG = {'inbounds': [{'type': 'vmess', 'transport': {'type': 'ws'}}],
          'outbounds': [{'type': 'direct', 'tag': 'direct'}, {'type': 'socks', 'tag': 'au-residential-ai', 'server': '198.51.100.1', 'server_port': 1337, 'username': 'test', 'password': 'test-only-secret'}]}


class BundleTests(unittest.TestCase):
    def test_manifest_matches_every_asset(self):
        self.assertEqual(set(installer.decode_bundle(bundle())), installer.FILES)
    def test_rejects_file_injection_corruption_and_bad_options(self):
        for mutate in [lambda x: x['files'].update({'../config.json': 'eA=='}),
                       lambda x: x['files'].update({'vpn_policy.py': 'eA=='}),
                       lambda x: x.update({'dry_run': 'yes'}),
                       lambda x: x.update({'command': 'id'})]:
            payload = bundle(); mutate(payload)
            with self.assertRaises(ValueError): installer.decode_bundle(payload)
    def test_requires_supported_preconfigured_exits_and_validation_channel(self):
        for config in [{'outbounds': [], 'inbounds': []}, {**CONFIG, 'inbounds': []}]:
            with self.assertRaises(ValueError): installer.check_target(config)
    def test_proxy_credentials_only_use_curl_stdin_and_never_response(self):
        with patch.object(installer, 'run', return_value=SimpleNamespace(stdout='ip=8.8.8.8\nloc=AU\n')) as call:
            result = installer.trace(CONFIG, True)
        args, kwargs = call.call_args
        self.assertNotIn('test-only-secret', str(args))
        self.assertIn('test-only-secret', kwargs['input'])
        self.assertNotIn('test-only-secret', json.dumps(result))


@unittest.skipIf(os.name == 'nt', 'Linux flock is part of the deployed controller')
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gsou-vps-installer-test-')
        self.root = Path(self.temp.name).resolve()
        self.config = self.root/'config.json'; self.config.write_text(json.dumps(CONFIG))
        self.original = self.config.read_bytes()
        self.lib, self.state, self.unit = self.root/'lib', self.root/'state', self.root/'unit.service'
        self.patches = [patch.object(installer, name, value) for name, value in [('CONFIG', self.config), ('LIB', self.lib), ('STATE', self.state), ('UNIT', self.unit)]]
        self.patches += [patch.object(installer, 'check_environment'), patch.object(installer, 'run', return_value=SimpleNamespace(stdout='')),
                         patch.object(installer, 'trace', side_effect=lambda c, au: EXITS['au' if au else 'direct']),
                         patch.object(installer, 'service_status', return_value={'exits': EXITS}),
                         patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=0))]
        self.mocks = [p.start() for p in self.patches]
    def tearDown(self):
        for p in reversed(self.patches): p.stop()
        self.temp.cleanup()
    def test_dry_run_never_installs_or_changes_config(self):
        result = installer.install({**bundle(), 'dry_run': True})
        self.assertTrue(result['policy_preserved']); self.assertFalse(self.lib.exists()); self.assertFalse(self.state.exists())
        self.assertEqual(self.config.read_bytes(), self.original)
    def test_install_never_restarts_the_vpn_or_changes_credentials(self):
        result = installer.install(bundle())
        self.assertTrue(result['installed']); self.assertTrue(result['policy_preserved'])
        self.assertEqual(self.config.read_bytes(), self.original)
        commands = [call.args[0] for call in self.mocks[5].call_args_list]
        self.assertFalse(any('kill' in str(args) or ('restart' in args and args[-1] != 'shaowei-vpn-routes.service') for args in commands))
        self.assertNotIn('test-only-secret', ''.join(p.read_text() for p in self.state.rglob('*') if p.is_file()))
    def test_upgrade_failure_restores_previous_helper_files(self):
        self.lib.mkdir(); (self.lib/'vpn_policy.py').write_text('old policy')
        self.unit.write_text('[Service]\nKillMode=process\n')
        run_mock = self.mocks[5]; failures = [True]
        def command(args, **kwargs):
            if args[:2] == ['systemctl', 'restart'] and failures:
                failures.pop(); raise RuntimeError('simulated service startup failure')
            return SimpleNamespace(stdout='')
        run_mock.side_effect = command
        with self.assertRaisesRegex(ValueError, '已恢复'): installer.install(bundle())
        self.assertEqual((self.lib/'vpn_policy.py').read_text(), 'old policy')
        self.assertEqual(self.unit.read_text(), '[Service]\nKillMode=process\n')
        self.assertEqual(self.config.read_bytes(), self.original)
    def test_first_install_failure_removes_new_unit_and_helper_files(self):
        run_mock = self.mocks[5]
        def command(args, **kwargs):
            if args[:2] == ['systemctl', 'restart']:
                raise RuntimeError('simulated first startup failure')
            return SimpleNamespace(stdout='')
        run_mock.side_effect = command
        with self.assertRaisesRegex(ValueError, '已恢复'): installer.install(bundle())
        self.assertFalse(self.unit.exists())
        self.assertFalse((self.lib/'vpn_policy.py').exists())
        self.assertEqual(self.config.read_bytes(), self.original)
    def test_concurrent_manual_config_change_is_preserved(self):
        def change(config, au):
            if au: self.config.write_text('external update')
            return EXITS['au' if au else 'direct']
        self.mocks[6].side_effect = change
        with self.assertRaisesRegex(ValueError, '已被更新'): installer.install(bundle())
        self.assertEqual(self.config.read_text(), 'external update')
        self.assertFalse(self.lib.exists())


if __name__ == '__main__': unittest.main(verbosity=2)
