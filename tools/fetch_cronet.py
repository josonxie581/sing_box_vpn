"""Stage the runtime from the pinned, SHA-256 verified official Windows release."""
from pathlib import Path
import hashlib
import urllib.request
import zipfile
import argparse
import json

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--version', default=(root / 'sing-box-version.txt').read_text().strip())
args = parser.parse_args()
version = args.version.removeprefix('v')
asset_name = f'sing-box-{version}-windows-amd64.zip'
archive = root / 'build/singbox-core' / asset_name
url = f'https://github.com/SagerNet/sing-box/releases/download/v{version}/{asset_name}'
if version == '1.14.4':
    digest = '99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df'
else:
    request = urllib.request.Request(f'https://api.github.com/repos/SagerNet/sing-box/releases/tags/v{version}',
        headers={'User-Agent': 'Gsou-runtime-builder'})
    with urllib.request.urlopen(request) as response:
        release = json.load(response)
    asset = next(a for a in release['assets'] if a['name'] == asset_name)
    checksum = asset.get('digest') or ''
    if not checksum.startswith('sha256:'):
        raise RuntimeError('Release has no SHA-256 digest; refusing unverified runtime')
    digest = checksum.removeprefix('sha256:')
archive.parent.mkdir(parents=True, exist_ok=True)
if not archive.exists():
    urllib.request.urlretrieve(url, archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
    raise RuntimeError('Official archive SHA-256 mismatch; runtime not installed')
with zipfile.ZipFile(archive) as z:
    names = [n for n in z.namelist() if n.endswith('/libcronet.dll')]
    if len(names) != 1:
        raise RuntimeError('Expected exactly one Cronet DLL')
    target = root / 'windows/libcronet.dll'
    target.write_bytes(z.read(names[0]))
    print(f'Verified and installed: {target}')
