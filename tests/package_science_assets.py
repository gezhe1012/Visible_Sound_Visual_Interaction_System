"""Package project-local teaching assets only; never opens disk devices."""
from pathlib import Path
import zipfile

root=Path(__file__).resolve().parents[1]/'doc'/'science_kiosk'
target=root/'science_materials.zip'
files=[]
for folder in ('bmp','audio','preview'):
    files.extend(sorted((root/folder).glob('*')))
files.extend(root/name for name in ('README.md','第五页音乐扩展说明.md','manifest.json'))
assert len(list((root/'bmp').glob('*.bmp')))==5
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as archive:
    for file in files:
        archive.write(file,file.relative_to(root))
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert len([name for name in archive.namelist() if name.endswith('.bmp')])==5
    assert len([name for name in archive.namelist() if name.endswith('.wav')])==5
print(f'PASS five-page materials ZIP: {target}, {target.stat().st_size} bytes')
