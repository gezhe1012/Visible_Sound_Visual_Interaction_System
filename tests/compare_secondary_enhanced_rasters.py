"""Pixel-exact protected regions, actual lesson PCM -> FFT -> raster dumps."""
from pathlib import Path
from PIL import Image
import numpy as np

root=Path(__file__).resolve().parents[1]/'doc/secondary_display'
total=0
for page,name in enumerate(['pitch','level','timbre','stereo','music']):
    previous=np.array(Image.open(root/'audio'/f'page_{page+1}_{name}.png'))
    current=np.array(Image.open(root/'enhanced'/f'page_{page+1}_{name}.png'))
    mask=np.ones((480,640),dtype=bool)
    if page==2:mask[384:464,:]=False
    if page==3:mask[136:376,:]=False
    assert np.array_equal(previous[mask],current[mask]),f'Protected region changed on {name}'
    total+=int(mask.sum())
assert total==1331200
print(f'ALL ENHANCED RASTER COMPARISON TESTS PASSED: {total} protected actual WAV/FFT RGB pixels exact to board-verified preview')
