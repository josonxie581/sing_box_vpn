"""Read-only recovery preflight tests; no SSH, registry or real user data writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


@unittest.skipUnless(PWSH, 'PowerShell 7 is required')
class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'build')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.release = self.base / 'release'
        for name in ('Gsou.exe', 'GsouDmitBridge.exe', 'dmit-extension/manifest.json'):
            path = self.release / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
        self.key = self.base / 'test-key'
        self.hosts = self.base / 'known_hosts'
        self.key.touch()
        self.hosts.touch()
        self.prefs = self.base / 'roaming/josonxie/Gsou/shared_preferences.json'
        self.prefs.parent.mkdir(parents=True)
        self.profile = dict(version=1, host='192.0.2.1', port=22, user='root',
                            identityFile=str(self.key), knownHostsFile=str(self.hosts))
        self.save()

    def save(self):
        self.prefs.write_text(json.dumps({
            'flutter.vps_exit_management_profile_v1': json.dumps(self.profile)
        }), encoding='utf-8')

    def run_check(self, *args):
        return subprocess.run([
            PWSH, '-NoProfile', '-File', str(ROOT / 'tools/restore_dmit.ps1'),
            '-ReleaseDirectory', str(self.release), '-CheckOnly', *args,
        ], env={**os.environ, 'APPDATA': str(self.base / 'roaming'),
                'LOCALAPPDATA': str(self.base / 'local')},
            capture_output=True, text=True, encoding='utf-8', timeout=15)

    def test_missing_state_is_diagnosed_without_creation_or_prompt(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('192.0.2.1:22', result.stdout)
        self.assertIn('待确认', result.stdout)
        self.assertFalse((self.base / 'local').exists())

    def test_unique_host_snapshot_supplies_id(self):
        state = self.base / 'local/Gsou/dmit'
        state.mkdir(parents=True)
        (state / 'snapshot.json').write_text(json.dumps({'servers': [
            {'serviceId': '456', 'addresses': ['192.0.2.2']},
            {'serviceId': '123', 'addresses': ['192.0.2.1']},
        ]}), encoding='utf-8')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('服务编号：123', result.stdout)
        self.assertEqual([p.name for p in state.iterdir()], ['snapshot.json'])

    def test_invalid_host_blocks_recovery(self):
        self.profile['host'] = '-oProxyCommand=bad'
        self.save()
        self.assertNotEqual(self.run_check().returncode, 0)
        self.assertFalse((self.base / 'local').exists())

    def test_invalid_explicit_id_blocks_recovery(self):
        self.assertNotEqual(self.run_check('-ServiceId', 'not-a-service').returncode, 0)
        self.assertFalse((self.base / 'local').exists())


if __name__ == '__main__':
    unittest.main()
