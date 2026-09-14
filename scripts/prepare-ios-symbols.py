#!/usr/bin/env python3
"""Attach authentic, UUID-matched upstream WebRTC symbols before archive export."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

VERSION = '153.0.0'
SHA256 = '147c6d00a747bd58dc865f44afd8866bc18d9000c3b7fb51b0c5884cb7f68214'
URL = f'https://github.com/stasel/WebRTC/releases/download/{VERSION}/WebRTC-M153-dSYM.zip'
ROOT = Path(__file__).resolve().parents[1]

def uuids(path):
    output = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    return set(re.findall(r'UUID: ([A-Fa-f0-9-]+)', output))

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    binary = args.archive / 'Products/Applications/Drillbit.app/Frameworks/WebRTC.framework/WebRTC'
    expected = uuids(binary)
    if not expected:
        raise SystemExit('No WebRTC UUID found; refusing to attach unverified symbols.')
    cache = ROOT / '.local/webrtc-symbols'
    cache.mkdir(parents=True, exist_ok=True)
    bundle = cache / 'WebRTC-M153-dSYM.zip'
    if not bundle.exists():
        partial = bundle.with_suffix('.download')
        urllib.request.urlretrieve(URL, partial)
        if digest(partial) != SHA256:
            raise SystemExit('Upstream symbol checksum mismatch.')
        partial.replace(bundle)
    if digest(bundle) != SHA256:
        raise SystemExit('Cached symbol checksum mismatch; remove the incomplete cache and retry.')
    with tempfile.TemporaryDirectory(dir=cache) as tmp:
        with zipfile.ZipFile(bundle) as archive:
            for member in archive.infolist():
                destination = (Path(tmp) / member.filename).resolve()
                if not destination.is_relative_to(Path(tmp).resolve()):
                    raise SystemExit('Unsafe ZIP path.')
            archive.extractall(tmp)
        for candidate in Path(tmp).rglob('*.dSYM'):
            dwarf = candidate / 'Contents/Resources/DWARF/WebRTC'
            if dwarf.is_file() and uuids(dwarf) == expected:
                target = args.archive / 'dSYMs/WebRTC.framework.dSYM'
                shutil.copytree(candidate, target, dirs_exist_ok=True)
                assert uuids(target / 'Contents/Resources/DWARF/WebRTC') == expected
                print('Attached verified WebRTC symbols: ' + ', '.join(sorted(expected)))
                return
    raise SystemExit('No matching symbols in pinned release. Update binary and symbols together.')

if __name__ == '__main__':
    main()
