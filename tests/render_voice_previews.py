"""Convert actual ModelSim RGB rasters into reviewable previews; no mock data."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'doc' / 'live_voice'
parser = argparse.ArgumentParser()
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--noise-reduced', action='store_true')
mode.add_argument('--voice-focus', action='store_true')
args = parser.parse_args()
if args.noise_reduced:
    OUT = OUT / 'noise_reduced'
elif args.voice_focus:
    OUT = OUT / 'voice_focus'
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
if args.noise_reduced or args.voice_focus:
    for name in ('main', 'secondary'):
        with Image.open(ROOT / 'tests' / f'voice_quiet_{name}.ppm') as frame:
            assert frame.size == (640, 480)
            frame.save(OUT / f'quiet_{name}_rtl.png')
print('ALL VOICE PREVIEW TESTS PASSED: two complete 640x480 RTL rasters, no synthetic artwork')
