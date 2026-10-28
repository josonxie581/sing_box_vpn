"""Install only the fixed routing controller. Never install or restart the VPN."""
import ast
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid

FILES = {'vpn_policy.py', 'vpn_runtime.py', 'vpn_routes_service.py', 'shaowei-vpn-routes.service'}
LIB = Path('/usr/local/lib/shaowei-vpn')
UNIT = Path('/etc/systemd/system/shaowei-vpn-routes.service')
STATE = Path('/var/lib/shaowei-vpn')
CONFIG = Path('/root/sing-box/config.json')


def decode_bundle(payload):
    if not isinstance(payload, dict) or set(payload) - {'files', 'sha256', 'dry_run'}:
        raise ValueError('部署包格式无效')
    if not isinstance(payload.get('dry_run', False), bool):
        raise ValueError('部署选项无效')
    if not isinstance(payload.get('files'), dict) or set(payload['files']) != FILES or not isinstance(payload.get('sha256'), dict) or set(payload['sha256']) != FILES:
        raise ValueError('部署包文件列表无效')
    decoded = {}
    for name in FILES:
        value, digest = payload['files'][name], payload['sha256'][name]
        if not isinstance(value, str) or not isinstance(digest, str) or not re.fullmatch('[a-f0-9]{64}', digest):
            raise ValueError('部署包校验信息无效')
        try:
            raw = base64.b64decode(value, validate=True)
        except Exception:
            raise ValueError('部署包编码无效') from None
        if len(raw) > 100000 or hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError('部署包完整性校验失败')
        if name.endswith('.py'):
            ast.parse(raw.decode('utf-8'))
        decoded[name] = raw
    if sum(map(len, decoded.values())) > 180000:
        raise ValueError('部署包过长')
    return decoded


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=30, **kwargs)


def trace(config, residential):
    args = ['url = "https://www.cloudflare.com/cdn-cgi/trace"', 'silent', 'show-error', 'ipv4', 'connect-timeout = 8', 'max-time = 15']
    if residential:
        upstream = next(o for o in config['outbounds'] if o.get('tag') == 'au-residential-ai')
        if upstream.get('type') != 'socks':
            raise ValueError('住宅出口必须是已配置的 SOCKS5 代理')
        args.append('proxy = '+json.dumps('socks5h://'+upstream['server']+':'+str(upstream['server_port'])))
        if upstream.get('username'):
            args.append('proxy-user = '+json.dumps(upstream['username']+':'+upstream.get('password', '')))
    else:
        args.append('noproxy = "*"')
    response = run(['/usr/bin/curl', '-q', '--config', '-'], input='\n'.join(args)+'\n')
    fields = dict(line.split('=', 1) for line in response.stdout.splitlines() if '=' in line)
    try:
        address = ipaddress.ip_address(fields['ip'])
        if address.version != 4 or not address.is_global or not re.fullmatch('[A-Z]{2}', fields.get('loc', '')):
            raise ValueError()
    except (KeyError, ValueError):
        raise ValueError('出口地址探测失败，未更改代理配置') from None
    return {'ip': str(address), 'label': ('住宅代理' if residential else 'VPS 直连')+'（'+fields['loc']+'）'}


def check_target(config):
    tags = {item.get('tag') for item in config.get('outbounds', [])}
    if not {'direct', 'au-residential-ai'}.issubset(tags):
        raise ValueError('请先在 VPS 配置 direct 与 au-residential-ai 两个出口，再部署控制服务')
    if next(item for item in config['outbounds'] if item.get('tag') == 'direct').get('type') != 'direct':
        raise ValueError('direct 出口必须配置为 VPS 直连')
    vmess = next((i for i in config.get('inbounds', []) if i.get('type') == 'vmess'), None)
    if not vmess or vmess.get('tls', {}).get('enabled') or vmess.get('transport', {}).get('type') != 'ws':
        raise ValueError('当前控制服务需要 /root/sing-box 下的非 TLS VMess WS 入口作为验证通道')


def atomic_bytes(path, raw, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('控制服务路径不允许符号链接')
    temp = path.with_name('.'+path.name+'-'+uuid.uuid4().hex)
    try:
        with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode), 'wb') as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        temp.chmod(mode)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def service_status():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(4); client.connect('/run/shaowei-vpn/control.sock')
        client.sendall(b'{"action":"status"}\n')
        with client.makefile('rb') as stream:
            data = json.loads(stream.readline(131073))
    if not data.get('ok'):
        raise ValueError('控制服务启动验证失败')
    return data['result']


def check_environment():
    if not hasattr(os, 'geteuid') or os.geteuid() != 0:
        raise ValueError('部署控制服务需要 Linux VPS 的 root 管理账号')
    if not Path('/run/systemd/system').exists() or not shutil.which('curl'):
        raise ValueError('服务器需要 systemd、Python 3 和 curl')


def install(payload):
    files = decode_bundle(payload)
    check_environment()
    before = CONFIG.read_bytes(); config = json.loads(before)
    check_target(config)
    run(['/root/sing-box/sing-box', 'check', '-c', 'config.json'], cwd='/root/sing-box')
    exits = {'direct': trace(config, False), 'au': trace(config, True)}
    if exits['direct']['ip'] == exits['au']['ip']:
        raise ValueError('两个出口地址相同，请先检查住宅代理配置')
    if payload.get('dry_run'):
        return {'dry_run': True, 'installed': False, 'policy_preserved': CONFIG.read_bytes() == before, 'exits': exits}
    import fcntl
    import pwd
    if LIB.is_symlink() or STATE.is_symlink():
        raise ValueError('控制服务目录无效')
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with open(STATE/'apply.lock', 'a') as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('服务器正在应用规则，请完成后再升级控制服务') from None
        try:
            if CONFIG.read_bytes() != before:
                raise ValueError('代理配置已被更新，本次部署已取消')
            if UNIT.exists() and 'KillMode=process' not in UNIT.read_text():
                raise ValueError('现有控制服务需要先核对升级方式，以免影响代理进程')
            try:
                pwd.getpwnam('sitepub')
            except KeyError:
                run(['/usr/sbin/useradd', '--system', '--no-create-home', '--home-dir', '/nonexistent', '--shell', '/usr/sbin/nologin', 'sitepub'])
            LIB.mkdir(mode=0o755, parents=True, exist_ok=True)
            targets = {LIB/name: raw for name, raw in files.items() if name.endswith('.py')}
            targets[UNIT] = files['shaowei-vpn-routes.service']
            targets[STATE/'exits.json'] = json.dumps(exits).encode()
            originals = {p: p.read_bytes() if p.exists() else None for p in targets}
            old_active = UNIT.exists() and subprocess.run(['systemctl', 'is-active', '--quiet', 'shaowei-vpn-routes.service']).returncode == 0
            old_enabled = UNIT.exists() and subprocess.run(['systemctl', 'is-enabled', '--quiet', 'shaowei-vpn-routes.service']).returncode == 0
            backup = STATE/'install-backups'/uuid.uuid4().hex
            backup.mkdir(mode=0o700, parents=True)
            for number, (path, raw) in enumerate(originals.items()):
                if raw is not None:
                    atomic_bytes(backup/str(number), raw, 0o600)
            try:
                for path, raw in targets.items():
                    atomic_bytes(path, raw, 0o600 if path.name == 'exits.json' else 0o644)
                run(['systemd-analyze', 'verify', str(UNIT)])
                run(['systemctl', 'daemon-reload'])
                run(['systemctl', 'enable', 'shaowei-vpn-routes.service'])
                run(['systemctl', 'restart', 'shaowei-vpn-routes.service'])
                for attempt in range(30):
                    try:
                        status = service_status(); break
                    except (OSError, ValueError):
                        if attempt == 29: raise
                        time.sleep(.2)
                if CONFIG.read_bytes() != before:
                    raise ValueError('检测到并行修改，请核对代理配置')
            except Exception:
                subprocess.run(['systemctl', 'stop', 'shaowei-vpn-routes.service'], capture_output=True, timeout=20)
                if not old_enabled:
                    subprocess.run(['systemctl', 'disable', 'shaowei-vpn-routes.service'], capture_output=True, timeout=20)
                for path, raw in originals.items():
                    if raw is None: path.unlink(missing_ok=True)
                    else: atomic_bytes(path, raw, 0o600 if path.name == 'exits.json' else 0o644)
                run(['systemctl', 'daemon-reload'])
                if old_active:
                    run(['systemctl', 'restart', 'shaowei-vpn-routes.service'])
                raise ValueError('部署失败，已恢复控制服务文件；代理配置未修改') from None
            return {'installed': True, 'version': 1, 'policy_preserved': True, 'exits': status['exits']}
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


if __name__ == '__main__':
    os.umask(0o077)
    # Complete the bounded controller transaction even if the SSH UI disconnects.
    if hasattr(signal, 'SIGHUP'):
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
    try:
        raw = sys.stdin.buffer.read(262145)
        if len(raw) > 262144:
            raise ValueError('部署包过长')
        result = install(json.loads(raw))
        print(json.dumps({'ok': True, 'result': result}, ensure_ascii=False))
    except ValueError as error:
        print(json.dumps({'ok': False, 'error': str(error)}, ensure_ascii=False))
        sys.exit(1)
    except Exception:
        print(json.dumps({'ok': False, 'error': '部署未完成，请检查服务器环境与管理权限；未主动修改代理配置'}, ensure_ascii=False))
        sys.exit(1)
