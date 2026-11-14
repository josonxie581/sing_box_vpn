"""Exercise the actual Windows DLL through loopback servers (no external routes)."""
import ctypes
import datetime
import ipaddress
import json
import os
from pathlib import Path
import socket
import socketserver
import threading
import sys
import subprocess
import time
import hashlib
import urllib.request
import zipfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

root = Path(__file__).resolve().parent.parent
masque = '--masque' in sys.argv
work = root / ('build/masque-experiment' if masque else 'build/protocol-loopback')
work.mkdir(parents=True, exist_ok=True)
if masque:
    archive = work / 'sing-box-1.15.0-alpha.13-windows-amd64.zip'
    if not archive.exists():
        urllib.request.urlretrieve('https://github.com/SagerNet/sing-box/releases/download/v1.15.0-alpha.13/' + archive.name, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != '7cff6a39687a12d51b289bd57a203723629eb8fd42f6668601b4484456436bc9':
        raise RuntimeError('Experimental release checksum mismatch')
    with zipfile.ZipFile(archive) as z:
        entry = next(n for n in z.namelist() if n.endswith('/sing-box.exe'))
        (work / 'sing-box.exe').write_bytes(z.read(entry))
os.environ['PATH'] = str(root / 'windows') + os.pathsep + os.environ['PATH']
runtime = os.add_dll_directory(str(root / 'windows'))
lib = ctypes.CDLL(str(root / 'windows/singbox.dll'))
lib.StartSingBox.argtypes = [ctypes.c_char_p]
lib.TestConfig.argtypes = [ctypes.c_char_p]
lib.GetVersion.restype = ctypes.c_void_p
lib.SbGetLastError.restype = ctypes.c_void_p
lib.SbDrainLogs.restype = ctypes.c_void_p
lib.FreeCString.argtypes = [ctypes.c_void_p]

def text_result(fn):
    p = fn()
    try:
        return ctypes.string_at(p).decode()
    finally:
        lib.FreeCString(p)

class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            while data := self.request.recv(65536):
                self.request.sendall(data)
        except ConnectionResetError:
            pass  # The client verifies all bytes before tearing down the tunnel.

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

def read(s, count):
    result = b''
    while len(result) < count:
        data = s.recv(count - len(result))
        if not data:
            raise RuntimeError('Unexpected EOF')
        result += data
    return result

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
now = datetime.datetime.now(datetime.timezone.utc)
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
        .public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost'),
            x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), critical=False)
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256()))
cert_path = work / 'test-cert.pem'
key_path = work / 'test-key.pem'
cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
server_tls = {'enabled': True, 'certificate_path': str(cert_path), 'key_path': str(key_path)}
client_tls = {'enabled': True, 'server_name': '127.0.0.1', 'certificate_path': str(cert_path)}
results = []
print('MASQUE experimental 1.15.0-alpha.13' if masque else text_result(lib.GetVersion), flush=True)
echo = socketserver.ThreadingTCPServer(('127.0.0.1', 0), Echo)
threading.Thread(target=echo.serve_forever, daemon=True).start()
try:
    cases = [('masque', 2), ('masque', 3)] if masque else [('snell', 4), ('snell', 6), ('naive', False),
            ('naive', True), ('hysteria2', 'salamander'), ('hysteria2', 'gecko')]
    for protocol, variant in cases:
        proxy_port, listen_port = port(), port()
        inbound = {'type': protocol, 'tag': 'server', 'listen': '127.0.0.1', 'listen_port': proxy_port}
        outbound = {'type': protocol, 'tag': 'proxy', 'server': '127.0.0.1', 'server_port': proxy_port}
        if protocol == 'snell':
            inbound.update(version=5 if variant == 4 else 6, psk='loopback-test-secret')
            outbound.update(version=variant, psk='loopback-test-secret')
        else:
            inbound['tls'], outbound['tls'] = server_tls, client_tls
            if protocol == 'naive':
                inbound['users'] = [{'username': 'test', 'password': 'loopback-test'}]
                outbound.update(username='test', password='loopback-test', quic=variant)
            else:
                inbound['users'] = [{'password': 'loopback-test'}]
                outbound['password'] = 'loopback-test'
                inbound['obfs'] = outbound['obfs'] = {'type': variant, 'password': 'loopback-obfs'}
                outbound['bbr_profile'] = 'conservative'
        config = {'log': {'level': 'debug', 'output': str(work / 'smoke.log')}, 'inbounds': [inbound,
            {'type': 'socks', 'tag': 'local', 'listen': '127.0.0.1', 'listen_port': listen_port}],
            'outbounds': [outbound, {'type': 'direct', 'tag': 'direct'}],
            'route': {'rules': [{'inbound': ['server'], 'outbound': 'direct'}], 'final': 'proxy'}}
        data = json.dumps(config).encode()
        process = None
        if masque:
            config['inbounds'] = config['inbounds'][1:]
            # L3 stacks handle 127/8 internally; use TEST-NET and rewrite on the server.
            config['route']['rules'][0]['override_address'] = '127.0.0.1'
            config['outbounds'] = [{'type': 'direct', 'tag': 'direct'}]
            config['endpoints'] = [
                {'type': 'masque-server', 'tag': 'server', 'listen': '127.0.0.1', 'listen_port': proxy_port,
                 'version': [variant], 'users': [{'username': 'test', 'password': 'loopback-test'}],
                 'tls': server_tls, 'address': ['10.77.0.1/24'], 'system': False},
                {'type': 'masque-client', 'tag': 'proxy', 'server': '127.0.0.1', 'server_port': proxy_port,
                 'version': variant, 'disable_version_fallback': True, 'username': 'test',
                 'password': 'loopback-test', 'tls': client_tls, 'system': False}]
            config_path = work / f'masque-http{variant}.json'
            config_path.write_text(json.dumps(config, indent=2), encoding='utf-8')
            subprocess.run([str(work / 'sing-box.exe'), 'check', '-c', str(config_path)], check=True)
            process = subprocess.Popen([str(work / 'sing-box.exe'), 'run', '-c', str(config_path)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError('Experimental core exited; inspect smoke.log')
                try:
                    with socket.create_connection(('127.0.0.1', listen_port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.1)
        else:
            if lib.TestConfig(data) != 0:
                raise RuntimeError(text_result(lib.SbGetLastError))
            if lib.StartSingBox(data) != 0:
                raise RuntimeError(text_result(lib.SbGetLastError))
        try:
            with socket.create_connection(('127.0.0.1', listen_port), timeout=15) as s:
                s.sendall(b'\x05\x01\x00')
                assert read(s, 2) == b'\x05\x00'
                destination = '192.0.2.99' if masque else '127.0.0.1'
                s.sendall(b'\x05\x01\x00\x01' + socket.inet_aton(destination) + echo.server_address[1].to_bytes(2, 'big'))
                header = read(s, 4)
                assert header[1] == 0, header
                address_size = {1: 4, 4: 16}.get(header[3])
                if address_size is None:
                    address_size = read(s, 1)[0]
                read(s, address_size + 2)
                payload = bytes(range(256)) * 1024
                s.sendall(payload)
                assert read(s, len(payload)) == payload
            label = f'{protocol}/{variant}'
            results.append({'protocol': label, 'tcp_bytes': len(payload), 'result': 'PASS'})
            print(f'PASS {label}: {len(payload)} bytes', flush=True)
        except Exception:
            print(text_result(lib.SbDrainLogs), flush=True)
            raise
        finally:
            if process is not None:
                process.terminate()
                process.wait(timeout=10)
            else:
                lib.StopSingBox()
finally:
    echo.shutdown()
    echo.server_close()
    lib.Cleanup()
    key_path.unlink(missing_ok=True)
    (work / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
