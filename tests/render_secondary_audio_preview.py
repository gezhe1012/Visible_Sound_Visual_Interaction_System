"""Only convert actual FPGA FFT/renderer raster dumps, no painted UI pixels."""
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'doc/secondary_display/audio';OUT.mkdir(parents=True,exist_ok=True)
names=['pitch','level','timbre','stereo','music']
sheet=Image.new('RGB',(1280,1512),'#071622');draw=ImageDraw.Draw(sheet)
for page,name in enumerate(names):
    im=Image.open(ROOT/f'tests/secondary_audio_page_{page}.ppm').convert('RGB');assert im.size==(640,480)
    im.save(OUT/f'page_{page+1}_{name}.png')
    ox,oy=(page%2)*640,(page//2)*504
    draw.text((ox+24,oy+5),f'{page+1} / {name.upper()} - REAL FFT / RTL RASTER',fill='#5bdac6')
    sheet.paste(im,(ox,oy+24))
sheet.save(OUT/'five_pages.png')
print('PASS: five actual FFT-based RTL raster previews converted')
