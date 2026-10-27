"""Format actual RTL raster dumps; no invented audio-feature visualization."""
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'doc/secondary_display/phase1'
OUT.mkdir(parents=True,exist_ok=True)
for number in range(5):
    frame=Image.open(ROOT/f'tests/secondary_link_frame_{number}.ppm').convert('RGB')
    assert frame.size==(640,480)
    frame.save(OUT/f'link_page_{number+1}.png')
print('PASS: five actual RTL interface-test rasters converted, not final spectrogram previews')
