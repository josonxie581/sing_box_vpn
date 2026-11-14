"""Isolated configuration tests: no downloads, firewall changes or VPS operations."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest
from urllib.parse import parse_qs, unquote, urlsplit

import secure_ss4_install_test as installer

SOURCE, function, ROOT = installer.SOURCE, installer.function, installer.ROOT


def embedded_python(name):
    return re.search(r"<<'PY'\n(.*?)\nPY", function(name), re.S).group(1)


class ProtocolTest(unittest.TestCase):
    setUp = installer.InstallerTest.setUp
    tearDown = installer.InstallerTest.tearDown
    run_bash = installer.InstallerTest.run_bash
    def configure(self, **options):
        base = {'inbounds': [dict(type='hysteria2', listen_port=20001,
                                 users=[dict(password='test-uuid')]),
                             dict(type='vmess', listen_port=20002),
                             dict(type='tuic', listen_port=20003)]}
        path = self.install / 'config.json'
        path.write_text(json.dumps(base))
        env = {k: v for k, v in os.environ.items() if not k.startswith(
            ('SNELL_', 'NAIVE_', 'HY2_'))}
        env.update(WORKDIR=str(self.install), **options)
        result = subprocess.run([sys.executable, '-c', embedded_python(
            'modern_protocol_config'), 'configure'], env=env, capture_output=True)
        return result, json.loads(path.read_text()), env

    def test_links_match_config_and_escape_credentials(self):
        for obfs in ('none', 'salamander', 'gecko'):
            result, config, env = self.configure(
                SNELL_PORT='20004', SNELL_PSK='test:@/&?# password',
                NAIVE_PORT='20005', NAIVE_DOMAIN='proxy.example.com',
                NAIVE_USERNAME='user:@', NAIVE_PASSWORD='pass/&?#',
                NAIVE_CERT_FILE='/etc/cert.pem', NAIVE_KEY_FILE='/etc/key.pem',
                HY2_OBFS=obfs, HY2_OBFS_PASSWORD='obfs/&?#', HY2_BBR_PROFILE='conservative')
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([sys.executable, '-c', embedded_python(
                'modern_protocol_config'), 'links', '2001:db8::1'],
                env=env, capture_output=True, text=True, check=True)
            links = {urlsplit(line).scheme: urlsplit(line) for line in result.stdout.splitlines()}
            self.assertEqual(set(links), {'snell', 'naive+https', 'naive+quic', 'hysteria2'})
            self.assertEqual(unquote(links['snell'].username), config['inbounds'][3]['psk'])
            self.assertEqual(links['snell'].hostname, '2001:db8::1')
            self.assertEqual(unquote(links['naive+quic'].password), 'pass/&?#')
            self.assertNotIn('insecure', links['naive+https'].query)
            self.assertEqual(links['naive+https'].hostname, '2001:db8::1')
            self.assertEqual(parse_qs(links['naive+https'].query)['sni'], ['proxy.example.com'])
            query = parse_qs(links['hysteria2'].query)
            self.assertEqual(query['bbr_profile'], ['conservative'])
            self.assertEqual(query.get('obfs'), None if obfs == 'none' else [obfs])
            if obfs != 'none':
                self.assertEqual(query['obfs-password'], [config['inbounds'][0]['obfs']['password']])

    def test_invalid_options_do_not_write_config(self):
        for options in ({'SNELL_PORT': '20001'}, {'SNELL_PORT': '70000'},
                        {'SNELL_PORT': '20004', 'SNELL_PSK': 'short'},
                        {'HY2_OBFS': 'invalid'}, {'HY2_BBR_PROFILE': 'invalid'}):
            result, config, _ = self.configure(**options)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(config['inbounds']), 3)
            self.assertNotIn('bbr_profile', config['inbounds'][0])

    def test_default_and_generated_credentials(self):
        result, config, _ = self.configure(SNELL_PORT='20004', HY2_OBFS='gecko')
        self.assertEqual(result.returncode, 0, result.stderr)
        psk = config['inbounds'][3]['psk']
        self.assertEqual(len(psk), 64)
        self.assertNotEqual(psk, config['inbounds'][0]['obfs']['password'])
        self.assertFalse(any(x['type'] == 'naive' for x in config['inbounds']))

    def test_release_digest_is_required_and_fail_closed(self):
        archive = self.base / 'archive.tar.gz'
        archive.write_bytes(b'test artifact')
        release = self.base / 'release.json'
        for digest, success in (('sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest(), True),
                                ('sha256:' + '0' * 64, False), ('', False)):
            release.write_text(json.dumps({'assets': [{'name': archive.name, 'digest': digest}]}))
            result = subprocess.run([sys.executable, '-c', embedded_python('verify_release_archive'),
                                     str(archive), str(release)], capture_output=True)
            self.assertEqual(result.returncode == 0, success)

    def test_preflight_rejects_bad_settings_before_file_changes(self):
        marker = self.install / 'config.json'
        marker.write_text('existing configuration')
        functions = function('get_latest_version') + '\n' + function('modern_protocol_preflight')
        for settings in ('HY2_OBFS=invalid', 'ENABLE_SNELL=2', 'SNELL_PSK=short',
                         'SNELL_PORT=70000', 'NAIVE_DOMAIN=proxy.example.com',
                         'SINGBOX_VERSION=v1.15.0-alpha.13'):
            result = self.run_bash('FALLBACK_SINGBOX_VERSION=v1.14.4\n' + settings + '\n'
                                   + functions + '\nmodern_protocol_preflight\n')
            self.assertNotEqual(result.returncode, 0, settings)
            self.assertEqual(marker.read_text(), 'existing configuration')

    @unittest.skipUnless(os.name == 'nt' and (ROOT / 'windows/singbox.dll').exists(),
                         'Requires built Windows core')
    def test_full_generated_config_with_actual_core(self):
        # Only test directory files are created; installer entrypoint is never run.
        wrapper = '''
python3() { WORKDIR="$(cygpath -m "$WORKDIR")" command python "$@"; }
get_ip() { echo 127.0.0.1; }
generate_ssl_certificate() {
    MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \\
        -keyout "$(cygpath -m "$WORKDIR/private.key")" -out "$(cygpath -m "$WORKDIR/cert.pem")" >/dev/null
}
UUID=11111111-1111-4111-8111-111111111111
VMESS_PORT=20002 TUIC_PORT=20003 HY2_PORT=20001 SNELL_PORT=20004
NAIVE_PORT=20005 NAIVE_DOMAIN=localhost
NAIVE_CERT_FILE="$(cygpath -m "$WORKDIR/cert.pem")"
NAIVE_KEY_FILE="$(cygpath -m "$WORKDIR/private.key")"
HY2_OBFS=gecko HY2_BBR_PROFILE=conservative CURRENT_DOMAIN=localhost
printf '#!/bin/bash\\nexit 0\\n' > "$WORKDIR/sing-box"
chmod +x "$WORKDIR/sing-box"
'''
        generator = 'generate_config() {' + SOURCE.split('generate_config() {', 1)[1].split(
            '\n# 新协议', 1)[0]
        wrapper += function('modern_protocol_config') + '\n' + generator + '\ngenerate_config\n'
        result = self.run_bash(wrapper)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads((self.install / 'config.json').read_text())
        for inbound in config['inbounds']:
            if 'tls' in inbound:
                inbound['tls']['certificate_path'] = str(self.install / 'cert.pem')
                inbound['tls']['key_path'] = str(self.install / 'private.key')
        with os.add_dll_directory(str(ROOT / 'windows')):
            lib = ctypes.CDLL(str(ROOT / 'windows/singbox.dll'))
            lib.TestConfig.argtypes = [ctypes.c_char_p]
            lib.SbGetLastError.restype = ctypes.c_void_p
            lib.FreeCString.argtypes = [ctypes.c_void_p]
            status = lib.TestConfig(json.dumps(config).encode())
            error = lib.SbGetLastError()
            try:
                self.assertEqual(status, 0, ctypes.string_at(error).decode() if error else '')
            finally:
                if error:
                    lib.FreeCString(error)


if __name__ == '__main__':
    unittest.main(verbosity=2)
