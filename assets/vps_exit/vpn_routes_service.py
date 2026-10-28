#!/usr/bin/python3
"""Private root controller: fixed operations, fixed files, peer-checked Unix socket."""
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import socket
import socketserver
import struct
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager

import vpn_runtime
from vpn_policy import build, infer, normalize

CONFIG = Path('/root/sing-box/config.json')
STATE = Path('/var/lib/shaowei-vpn')
SOCKET = Path('/run/shaowei-vpn/control.sock')
MAX_REQUEST = 32768
TERMINAL = {'succeeded', 'unchanged', 'failed'}


def revision(raw):
    return hashlib.sha256(raw).hexdigest()


def atomic(path, data):
    path = Path(path)
    temp = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    try:
        with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return copy.deepcopy(default)


class Manager:
    def __init__(self, config=CONFIG, state=STATE, runtime=vpn_runtime):
        self.config, self.state, self.runtime = Path(config), Path(state), runtime
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)

    @contextmanager
    def locked(self, wait=False):
        with open(self.state / 'apply.lock', 'a') as stream:
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
            except BlockingIOError:
                raise ValueError('已有操作正在执行，请稍后刷新') from None
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    def current(self):
        raw = self.config.read_bytes()
        config = json.loads(raw)
        saved = read_json(self.state / 'active.json')
        if saved and saved.get('revision') == revision(raw):
            return raw, config, saved['policy'], False
        policy, unknown = infer(config)
        return raw, config, policy, unknown

    def latest_job(self):
        latest = read_json(self.state / 'latest.json')
        if not latest:
            return None
        item = read_json(self.state / ('job-' + latest['id'] + '.json'))
        if item and item.get('state') not in TERMINAL and time.time() - item.get('created', 0) > 600:
            # A crashed controller must not leave the UI permanently busy.
            item = {**item, 'state': 'failed', 'message': '上次操作未完成，请刷新后核对生效配置'}
        return {key: item.get(key) for key in ('id', 'state', 'message', 'created', 'finished', 'checks')} if item else None

    def status(self):
        raw, config, policy, unknown = self.current()
        history = read_json(self.state / 'history.json', [])
        return {
            'revision': revision(raw), 'policy': policy, 'external_rules': unknown,
            'job': self.latest_job(), 'can_rollback': bool(read_json(self.state / 'previous.json')),
            'history': history[-8:][::-1],
            'exits': self.runtime.exit_metadata(),
        }

    def validate(self, payload, expected):
        raw, config, _, unknown = self.current()
        if expected != revision(raw):
            raise ValueError('配置已更新，请先刷新当前规则后再保存')
        if unknown:
            raise ValueError('检测到后台不支持的外部规则，已阻止覆盖；请先通过 SSH 核对')
        policy = normalize(payload)
        candidate = build(config, policy)
        self.runtime.validate(candidate)
        return {'valid': True, 'policy': policy, 'revision': expected, 'unchanged': candidate == config}

    def start(self, payload, expected, actor, rollback=False, spawn=True):
        if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
            raise ValueError('请先读取当前生效规则')
        if not isinstance(actor, str) or not 1 <= len(actor) <= 80:
            raise ValueError('管理员身份无效')
        with self.locked():
            job = self.latest_job()
            if job and job['state'] not in TERMINAL:
                raise ValueError('已有操作正在执行，请稍后刷新')
            if rollback:
                previous = read_json(self.state / 'previous.json')
                if not previous:
                    raise ValueError('暂无可回滚的上一版规则')
                payload = previous['policy']
            checked = self.validate(payload, expected)
            job_id = uuid.uuid4().hex
            job = {'id': job_id, 'state': 'queued', 'created': time.time(), 'actor': actor, 'policy': checked['policy'], 'expected_revision': expected, 'rollback': rollback, 'message': '正在校验并应用规则…'}
            atomic(self.state / ('job-' + job_id + '.json'), job)
            atomic(self.state / 'latest.json', {'id': job_id})
            if spawn:
                subprocess.Popen(['/usr/bin/python3', str(Path(__file__).resolve()), '--worker', job_id], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
            return {'accepted': True, 'job': {'id': job_id, 'state': 'queued'}, 'unchanged': checked['unchanged']}

    def execute(self, job_id):
        if not re.fullmatch('[0-9a-f]{32}', job_id):
            raise ValueError('Invalid job')
        path = self.state / ('job-' + job_id + '.json')
        with self.locked(wait=True):
            job = read_json(path)
            if not job or job['state'] != 'queued':
                return
            job.update(state='running', message='正在验证出口，失败会自动恢复原配置…')
            atomic(path, job)
            try:
                raw, config, old_policy, unknown = self.current()
                if unknown or revision(raw) != job['expected_revision']:
                    raise ValueError('配置已更新，本次操作未应用，请刷新后重试')
                candidate = build(config, job['policy'])
                self.runtime.validate(candidate)
                # Verify in a separate local process before touching the live listener.
                if candidate != config:
                    self.runtime.probe(candidate, policy=job['policy'])
                result = self.runtime.replace_config(raw, candidate, job['policy'])
                active_raw = self.config.read_bytes()
                if json.loads(active_raw) != candidate:
                    raise RuntimeError('Active configuration differs')
                if not result['unchanged']:
                    atomic(self.state / 'previous.json', {'policy': old_policy})
                atomic(self.state / 'active.json', {'policy': job['policy'], 'revision': revision(active_raw)})
                job.update(state='unchanged' if result['unchanged'] else 'succeeded', finished=time.time(), checks=[{'name': t['name'], 'passed': t['passed'], **({key: t[key] for key in ('http', 'exit_ip', 'country') if key in t})} for t in result['tests']], message='当前规则已生效，无需重启' if result['unchanged'] else '规则已生效，出口验证通过')
            except ValueError as error:
                job.update(state='failed', finished=time.time(), message=str(error))
            except Exception:
                job.update(state='failed', finished=time.time(), message='操作未完成，请刷新核对当前规则；原有设置已尽力保留')
            atomic(path, job)
            history = read_json(self.state / 'history.json', [])
            history.append({key: job.get(key) for key in ('id', 'state', 'finished', 'actor', 'message')})
            atomic(self.state / 'history.json', history[-40:])

    def dispatch(self, data):
        if not isinstance(data, dict) or set(data) - {'action', 'actor', 'policy', 'expected_revision'}:
            raise ValueError('不支持的请求字段')
        action = data.get('action')
        if action == 'status':
            return self.status()
        if action == 'validate':
            return self.validate(data.get('policy'), data.get('expected_revision'))
        if action in ('apply', 'rollback'):
            return self.start(data.get('policy'), data.get('expected_revision'), data.get('actor'), rollback=action == 'rollback')
        raise ValueError('不支持的操作')


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            _, uid, _ = struct.unpack('3i', self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i')))
            if uid not in (0, pwd.getpwnam('sitepub').pw_uid):
                raise ValueError('拒绝访问')
            self.request.settimeout(5)
            raw = self.rfile.readline(MAX_REQUEST + 1)
            if len(raw) > MAX_REQUEST or not raw.endswith(b'\n'):
                raise ValueError('请求过长或格式无效')
            result = {'ok': True, 'result': self.server.manager.dispatch(json.loads(raw))}
        except ValueError as error:
            result = {'ok': False, 'error': str(error)}
        except Exception:
            result = {'ok': False, 'error': 'VPS 规则服务暂不可用，请稍后重试'}
        try:
            self.wfile.write((json.dumps(result, ensure_ascii=False) + '\n').encode())
        except OSError:
            pass


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def main():
    os.umask(0o077)
    manager = Manager()
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        manager.execute(sys.argv[2])
        return
    if len(sys.argv) != 1:
        raise SystemExit('Invalid arguments')
    SOCKET.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    SOCKET.unlink(missing_ok=True)
    with Server(str(SOCKET), Handler) as server:
        server.manager = manager
        os.chown(SOCKET, 0, pwd.getpwnam('sitepub').pw_gid)
        os.chmod(SOCKET, 0o660)
        server.serve_forever()


if __name__ == '__main__':
    main()
