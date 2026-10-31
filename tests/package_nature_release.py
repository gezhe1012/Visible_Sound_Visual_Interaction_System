"""Package ONLY a fresh, regression- and routed-timing-passing intro build."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, zipfile

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'doc/nature_intro/evidence'
def read(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--build-log',type=Path,required=True)
    a=ap.parse_args()
    build=read(a.build_log)
    assert 'All requested checks passed.' in build and '[FAIL]' not in build,'Build did not pass'
    assert not re.search(r'USR-8159|USR-8011|USR-8012|\bERROR\b',build),'Unresolved tool/constraint error'
    run=ROOT/'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1'
    bit=run/'HDMI1.4b_Transmitter_v1.0.bit'
    timing=read(run/'HDMI1.4b_Transmitter_v1.0_pr.timing')
    setup=float(re.search(r'SWNS:\s*(-?[\d.]+)ns',timing)[1])
    hold=float(re.search(r'HWNS:\s*(-?[\d.]+)ns',timing)[1])
    assert setup>=0 and hold>=0,'Negative routed timing: do not ship'
    sources=[p for p in (ROOT/'src/user_source').rglob('*') if p.suffix.lower() in ('.v','.vhd','.sdc','.adc')]
    sources.append(ROOT/'src/td_project/HDMI1.4b_Transmitter_v1.0.al')
    assert bit.stat().st_mtime>=max(p.stat().st_mtime for p in sources),'Stale bit'
    names=['nature_regressions_final.txt','nature_controls_final.txt','nature_sdram_contract.txt',
           'nature_legacy_controls.txt','nature_legacy_voice.txt','nature_legacy_science.txt',
           'nature_legacy_waveform.txt','nature_legacy_fft.txt','nature_legacy_ticker.txt',
           'nature_legacy_secondary.txt','nature_legacy_pixel_compat.txt','nature_legacy_logo.txt',
           'nature_legacy_scaler.txt','nature_cdc_connectivity_final.txt','nature_rom_final.txt']
    tests={}
    for name in names:
        body=read(EVIDENCE/name)
        assert not re.search(r'\*\* (?:Fatal|Error)|Traceback|\[FAIL\]',body),name
        passed=[line for line in body.splitlines() if re.search(r'ALL .* TESTS PASSED',line)]
        assert passed,('No pass evidence',name)
        tests[name]=passed
    materials=ROOT/'output/nature_intro_tf'
    manifest=json.loads(read(materials/'manifest.json'))
    assert len(manifest)==4 and all(m['source_file_unchanged'] for m in manifest)
    for m in manifest:
        assert sha(Path(m['source']))==m['source_sha256']
        assert sha(materials/m['bmp'])==m['bmp_sha256']
        assert sha(materials/m['wav'])==m['wav_sha256']
    out=ROOT/'output/nature_intro_release';out.mkdir(parents=True,exist_ok=True)
    target=out/'HDMI_nature_intro.bit';shutil.copy2(bit,target)
    package=out/'nature_intro_materials.zip'
    files=[p for p in materials.iterdir() if p.suffix.upper() in ('.BMP','.WAV','.JSON','.TXT') or p.match('preview_*.png')]
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
        for p in sorted(files):z.write(p,p.name)
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.BMP')])==4
        assert len([n for n in z.namelist() if n.endswith('.WAV')])==4
    area=read(run/'HDMI1.4b_Transmitter_v1.0_phy.area')
    resources={name:int(re.search(r'(?m)^#'+name+r'\s+(\d+)',area)[1]) for name in ('lut','reg','bram','dsp','pll')}
    evidence=dict(base_commit='7b58cea',feature='startup-only nature photo/WAV layers; original six pages preserved',
        setup_wns_ns=setup,hold_wns_ns=hold,sta_coverage_percent=float(re.search(r'STA coverage\s*:\s*([\d.]+)',timing)[1]),
        resources=resources,bit_file=target.name,bit_sha256=sha(target),bit_bytes=target.stat().st_size,
        material_zip=package.name,material_sha256=sha(package),physical_board_verified=False,
        build_log=str(a.build_log),regressions=tests,
        source_sha256={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in sorted(sources)})
    (out/'verification.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS RELEASE: setup={setup:+.3f}ns hold={hold:+.3f}ns, bit SHA256={sha(target)}')
    print(f'PASS MATERIALS: {package}, four BMP packages and four WAVs')
    print('Physical board acceptance remains pending.')

if __name__=='__main__':main()
