"""Authorized VPS fresh deployment and Windows-to-VPS protocol smoke checks.

Credentials are read through verified SSH into memory only, never printed.
The deploy operation requires an empty /root/sing-box directory.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import socket
import shlex
import ssl
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--ssh-dir')
parser.add_argument('--ssh-alias')
parser.add_argument('--remote-config', default='/root/sing-box/config.json')
parser.add_argument('--host', required=True)
parser.add_argument('--deploy', action='store_true')
parser.add_argument('--latency', action='store_true')
parser.add_argument('--protocol')
parser.add_argument('--inbound-tag')
parser.add_argument('--repeat', type=int, default=1)
parser.add_argument('--disable-chrome-parrot', action='store_true')
args = parser.parse_args()
if args.deploy and args.host != '191.222.212.13':
    parser.error('This deployment profile is restricted to the authorized DMIT VPS')
root = Path(__file__).resolve().parent.parent
if args.ssh_alias:
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', args.ssh_alias]
elif args.ssh_dir:
    identity = Path(args.ssh_dir)
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o',
           'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={identity / "known_hosts"}',
           '-i', str(identity / 'id_rsa.pem'), f'root@{args.host}']
else:
    parser.error('--ssh-alias or --ssh-dir is required')


def remote(script):
    result = subprocess.run(ssh + ['bash', '-s'], input=script.encode(), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace')[-2000:])
    return result.stdout.decode()


if args.deploy:
    print(remote(r'''
set -eu
umask 077
test "$(hostname)" = DMIT-JP-Gsou
cd /root
test ! -e /root/sing-box/config.json
source /root/secure_ss4.sh
VMESS_PORT=20002 TUIC_PORT=20003 HY2_PORT=20001 SNELL_PORT=20004
NAIVE_PORT=20005 NAIVE_DOMAIN=voxinks.com
NAIVE_CERT_FILE=/etc/letsencrypt/live/voxinks.com/fullchain.pem
NAIVE_KEY_FILE=/etc/letsencrypt/live/voxinks.com/privkey.pem
HY2_OBFS=salamander HY2_BBR_PROFILE=conservative
modern_protocol_preflight
for port in 20001 20002 20003 20004 20005; do validate_port "$port" tcp; done
mkdir -p "$FILE_PATH"
if [[ -f /root/sing-box-1.14.4-linux-amd64.tar.gz ]]; then
    echo '699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968  /root/sing-box-1.14.4-linux-amd64.tar.gz' | sha256sum -c -
    tar -xOf /root/sing-box-1.14.4-linux-amd64.tar.gz sing-box-1.14.4-linux-amd64/sing-box > "$WORKDIR/sing-box"
    chmod 700 "$WORKDIR/sing-box"
else
    download_official_singbox > /root/sing-box/deploy.log 2>&1
fi
prepare_modern_protocols >> /root/sing-box/deploy.log 2>&1
get_ip() { echo 191.222.212.13; }
get_argodomain() { echo temp-domain-pending; }
generate_config >> /root/sing-box/deploy.log 2>&1
generate_links >> /root/sing-box/deploy.log 2>&1
cat > /etc/systemd/system/sing-box.service <<'UNIT'
[Unit]
Description=Gsou sing-box 1.14.4 proxy
After=network-online.target
Wants=network-online.target
[Service]
WorkingDirectory=/root/sing-box
ExecStart=/root/sing-box/sing-box run -c /root/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
UMask=0077
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now sing-box.service
sleep 2
systemctl is-active sing-box nginx shaowei-publisher shaowei-vpn-routes
/root/sing-box/sing-box version | head -1
'''), flush=True)

if args.deploy:
    manager = (root / 'tools/singbox-manager.sh').read_text(encoding='utf-8')
    remote("set -eu\ncat > /usr/local/bin/.singbox.new <<'GSOU_MANAGER_EOF'\n" + manager
           + "\nGSOU_MANAGER_EOF\nbash -n /usr/local/bin/.singbox.new\n"
           "chmod 755 /usr/local/bin/.singbox.new\n"
           "mv -f /usr/local/bin/.singbox.new /usr/local/bin/singbox\n")

# Secrets stay in process memory; no config files or credential-bearing error logs.
config = json.loads(remote('cat ' + shlex.quote(args.remote_config) + '\n'))
os.environ['PATH'] = str(root / 'windows') + os.pathsep + os.environ['PATH']
runtime = os.add_dll_directory(str(root / 'windows'))
lib = ctypes.CDLL(str(root / 'windows/singbox.dll'))
lib.StartSingBox.argtypes = [ctypes.c_char_p]
lib.TestConfig.argtypes = [ctypes.c_char_p]
lib.ProbeNodeDelay.argtypes = [ctypes.c_char_p, ctypes.c_int]
results = []


def receive(stream, count):
    data = b''
    while len(data) < count:
        part = stream.recv(count - len(data))
        if not part:
            raise RuntimeError('Unexpected EOF')
        data += part
    return data


def test(outbound, label):
    with socket.socket() as temp:
        temp.bind(('127.0.0.1', 0))
        port = temp.getsockname()[1]
    outbound['tag'] = 'proxy'
    client = dict(log={'disabled': True},
                  dns={'servers': [{'type': 'udp', 'tag': 'dns', 'server': '1.1.1.1'}]},
                  inbounds=[dict(type='socks', tag='test-in', listen='127.0.0.1', listen_port=port)],
                  outbounds=[outbound], route={'final': 'proxy', 'default_domain_resolver': 'dns'})
    data = json.dumps(client).encode()
    started = time.monotonic()
    try:
        if lib.TestConfig(data) != 0 or lib.StartSingBox(data) != 0:
            raise RuntimeError('Client core rejected configuration')
        with socket.create_connection(('127.0.0.1', port), timeout=25) as stream:
            stream.sendall(b'\x05\x01\x00')
            assert receive(stream, 2) == b'\x05\x00'
            host = b'www.cloudflare.com'
            stream.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + (443).to_bytes(2, 'big'))
            head = receive(stream, 4)
            if head[1]:
                raise RuntimeError(f'SOCKS response {head[1]}')
            size = {1: 4, 4: 16}.get(head[3])
            if size is None:
                size = receive(stream, 1)[0]
            receive(stream, size + 2)
            with ssl.create_default_context().wrap_socket(stream, server_hostname=host.decode()) as tls:
                tls.sendall(b'GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n')
                response = b''
                while chunk := tls.recv(65536):
                    response += chunk
                assert response.startswith(b'HTTP/1.1 200'), response[:30]
                assert ('ip=' + args.host).encode() in response, 'Unexpected exit IP'
        result = dict(protocol=label, result='PASS', seconds=round(time.monotonic() - started, 2),
                      verified_exit=args.host, response_bytes=len(response))
        if args.latency and outbound['type'] == 'hysteria2':
            delay = lib.ProbeNodeDelay(json.dumps(outbound).encode(), 5000)
            if delay < 0:
                raise RuntimeError('Hysteria2 latency probe returned failure')
            result['transport_rtt_ms'] = delay
    except Exception as error:
        result = dict(protocol=label, result='FAIL', error=type(error).__name__ + ': ' + str(error))
    finally:
        lib.StopSingBox()
    results.append(result)
    print(json.dumps(result), flush=True)


try:
    for inbound in config['inbounds']:
        kind = inbound['type']
        if args.protocol and kind != args.protocol:
            continue
        if args.inbound_tag and inbound.get('tag') != args.inbound_tag:
            continue
        outbound = dict(type=kind, server=args.host, server_port=inbound['listen_port'])
        if kind == 'snell':
            outbound.update(version=6, psk=inbound['psk'], mode='default')
        elif kind == 'naive':
            outbound.update(inbound['users'][0])
            outbound['tls'] = dict(enabled=True, server_name=inbound['tls']['server_name'])
            for quic in (False, True):
                test(dict(outbound, quic=quic), 'naive/h3' if quic else 'naive/h2')
            continue
        elif kind == 'hysteria2':
            outbound.update(password=inbound['users'][0]['password'],
                            bbr_profile=inbound.get('bbr_profile', 'standard'))
            if 'obfs' in inbound:
                outbound['obfs'] = inbound['obfs']
            outbound['tls'] = dict(enabled=True, server_name='www.bing.com', insecure=True)
            if args.disable_chrome_parrot:
                outbound['disable_chrome_parrot'] = True
        elif kind == 'tuic':
            outbound.update({k: inbound['users'][0][k] for k in ('uuid', 'password')})
            outbound.update(congestion_control='bbr', tls=dict(enabled=True, server_name='www.bing.com', insecure=True, alpn=['h3']))
        elif kind == 'vmess':
            outbound.update(uuid=inbound['users'][0]['uuid'], security='auto', transport=inbound['transport'])
        else:
            continue
        for attempt in range(args.repeat):
            test(outbound, kind + (f'/{attempt + 1}' if args.repeat > 1 else ''))
finally:
    lib.Cleanup()
    report = root / 'build/vps-protocol-results.json'
    report.write_text(json.dumps(results, indent=2))
if any(x['result'] != 'PASS' for x in results):
    raise SystemExit(1)
