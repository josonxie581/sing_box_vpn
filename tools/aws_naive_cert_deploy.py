#!/usr/bin/python3
"""Certbot deploy hook for the authorized dev-tokyo Naive service.

Install root-owned under /etc/letsencrypt/renewal-hooks/deploy/.
Private keys remain on the VPS, readable only by root and the proxy account.
"""
import grp
import os
from pathlib import Path
import signal
import subprocess
import tempfile

DOMAIN = 'aws.voxinks.com'
LINEAGE = Path('/etc/letsencrypt/live') / DOMAIN
BASE = Path('/etc/sing-box-certs') / DOMAIN
WORK = Path('/home/ubuntu/sing-box')


def main():
    if os.environ.get('RENEWED_LINEAGE', str(LINEAGE)) != str(LINEAGE):
        return
    if os.geteuid() != 0:
        raise SystemExit('Run this certificate deployment hook as root')
    cert, key = LINEAGE / 'fullchain.pem', LINEAGE / 'privkey.pem'
    subprocess.run(['openssl', 'verify', '-purpose', 'sslserver', '-verify_hostname', DOMAIN,
                    '-untrusted', str(cert), str(cert)], check=True, stdout=subprocess.DEVNULL)
    public_cert = subprocess.check_output(['openssl', 'x509', '-in', str(cert), '-noout', '-pubkey'])
    public_key = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-passin', 'pass:', '-pubout'])
    if public_cert != public_key:
        raise SystemExit('Certificate/key mismatch')
    group = grp.getgrnam('ubuntu').gr_gid
    BASE.mkdir(parents=True, exist_ok=True)
    os.chown(BASE, 0, group)
    os.chmod(BASE, 0o750)
    generation = Path(tempfile.mkdtemp(prefix='cert-', dir=BASE))
    os.chown(generation, 0, group)
    os.chmod(generation, 0o750)
    for source in (cert, key):
        target = generation / source.name
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(source.read_bytes())
        os.chown(target, 0, group)
        os.chmod(target, 0o640)
    current = BASE / 'current'
    previous = current.resolve() if current.exists() else None
    staged = BASE / f'.current-{os.getpid()}'
    staged.symlink_to(generation)
    os.replace(staged, current)
    try:
        # Never execute the user-owned proxy binary with root privileges.
        subprocess.run(['runuser', '-u', 'ubuntu', '--', str(WORK / 'sing-box'),
                        'check', '-c', str(WORK / 'config.json')], cwd=WORK, check=True)
    except Exception:
        if previous:
            staged.symlink_to(previous)
            os.replace(staged, current)
        else:
            current.unlink()
        raise
    count = 0
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if (process / 'exe').resolve() == WORK / 'sing-box' and (process / 'cwd').resolve() == WORK:
                os.kill(int(process.name), signal.SIGHUP)
                count += 1
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    print(f'Certificate deployed; reloaded {count} matching sing-box process(es)')


if __name__ == '__main__':
    main()
