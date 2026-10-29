"""Package integrated RTL/IP, run skeletons, voice tests, bit and evidence."""
import hashlib
import argparse
import json
import re
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'doc/live_voice'
parser = argparse.ArgumentParser()
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--noise-reduced', action='store_true')
mode.add_argument('--voice-focus', action='store_true')
args = parser.parse_args()
if args.noise_reduced:
    out = out / 'noise_reduced'
elif args.voice_focus:
    out = out / 'voice_focus'
archive = out / 'INMP441_live_voice_project.zip'
files = set()
for folder in ('src/user_source', 'src/td_project/al_ip', 'complete-hx4s20c-hdmi-project'):
    files.update(p for p in (root / folder).rglob('*') if p.is_file() and p.suffix not in {'.log', '.tmp', '.bak', '.dmp'})
project = root / 'src/td_project/HDMI1.4b_Transmitter_v1.0.al'
files.add(project)
for run in ('syn_1', 'phy_1'):
    for name in ('settings.cfg', 'HDMI1.4b_Transmitter_v1.0.prj'):
        files.add(root / 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs' / run / name)
for p in (root / 'tests').iterdir():
    if p.suffix in {'.sv', '.ps1', '.do', '.tcl', '.py'} or p.name.startswith('voice_baseline_'):
        files.add(p)
files.update(p for p in out.rglob('*') if p.is_file() and p.suffix != '.zip')
for relative in re.findall(r'<File Path="([^"]+)"', project.read_text(encoding='utf-8')):
    target = (project.parent / relative).resolve()
    assert target.exists(), target
    assert target in files, f'Missing project source in package: {relative}'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in sorted(files):
        z.write(p, p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    relative_out = out.relative_to(root).as_posix()
    evidence = json.loads(z.read(f'{relative_out}/build_evidence.json').decode('utf-8-sig'))
    bit = z.read(f'{relative_out}/' + evidence.get('bit_file', 'HDMI_live_voice.bit'))
    assert hashlib.sha256(bit).hexdigest().upper() == evidence['bit_sha256']
print(f'ALL VOICE PACKAGE TESTS PASSED: {len(files)} files, all project references included, CRC and bit SHA256 match, {archive.stat().st_size} bytes')
