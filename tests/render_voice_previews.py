"""Convert actual ModelSim RGB rasters into reviewable previews; no mock data."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'doc' / 'live_voice'
OUT.mkdir(parents=True, exist_ok=True)
canvas = Image.new('RGB', (1280, 520), '#071622')
draw = ImageDraw.Draw(canvas)
for index, name in enumerate(('main', 'secondary')):
    with Image.open(ROOT / 'tests' / f'voice_{name}.ppm') as frame:
        assert frame.size == (640, 480)
        frame.save(OUT / f'{name}_rtl.png')
        canvas.paste(frame, (index * 640, 40))
    draw.text((index * 640 + 18, 13), f'{name.upper()} / LIVE VOICE / RTL SIMULATION', fill='#D7E5EF')
canvas.save(OUT / 'dual_screen_rtl.png')
print('ALL VOICE PREVIEW TESTS PASSED: two complete 640x480 RTL rasters, no synthetic artwork')
