"""Render actual RTL raster outputs; not a replacement UI mockup."""
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
output=root/'doc'/'ticker_theme'/'preview'
output.mkdir(parents=True,exist_ok=True)
strips=Image.new('RGB',(640,220),'#071521')
for page in range(5):
    image=Image.open(root/'tests'/f'ticker_page_{page}.ppm').convert('RGB')
    image.save(output/f'page_{page+1}.png')
    strips.paste(image.crop((0,430,640,464)),(0,page*44+5))
strips.save(output/'five_captions.png')
frames=[]
for file in sorted((root/'tests').glob('ticker_anim_*.ppm')):
    strip=Image.open(file).convert('RGB')
    frames.append(strip.resize((1280,68),Image.Resampling.NEAREST))
assert len(frames)==100
frames[0].save(output/'footer_motion.gif',save_all=True,append_images=frames[1:],duration=134,loop=0,optimize=True,disposal=2)
print('PASS ticker previews: five complete pages, five-caption contact, 100-frame RTL motion GIF')
