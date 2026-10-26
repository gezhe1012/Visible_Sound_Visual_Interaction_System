"""Deterministic teaching BMPs, matching 24-bit stereo PCM and a FAT32 card image.
Writes ONLY doc/science_kiosk. Never opens a disk device or copies to a TF drive.
"""
from pathlib import Path
import hashlib
import json
import math
import struct
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'doc' / 'science_kiosk'
RATE = 48000
FREQUENCIES = (220, 330, 440, 660)
INCREMENTS = tuple(round(f * 2**32 / RATE) for f in FREQUENCIES)
SINE = tuple(round(32767 * math.sin(i * math.pi / 128)) for i in range(65))
MELODY_MIDI = (60,64,67,69,67,64,62,64,67,69,72,71,67,65,64,62,60)
MELODY_UNITS = (2,1,1,2,2,2,2,2,2,2,2,2,2,1,1,2,4)
MELODY_GAINS = (56,52,60,56,60,52,48,56,60,56,64,54,56,50,54,50,60)
MELODY_INCREMENTS = tuple(round(440*2**((m-69)/12)*2**32/RATE) for m in MELODY_MIDI)
BG, WHITE, MUTED, CYAN, GOLD = '#071521', '#F1F6FA', '#A1B8CC', '#52E3FF', '#FFE66D'
FONT = Path('C:/Windows/Fonts/msyh.ttc')
if not FONT.exists():
    FONT = Path('C:/Windows/Fonts/simhei.ttf')


def font(size):
    return ImageFont.truetype(str(FONT), size)


def label(draw, xy, text, size=30, color=WHITE):
    draw.text(xy, text, font=font(size), fill=color)


def curve(draw, box, kind='sine', cycles=3, amplitude=1, color=CYAN):
    x0, y0, x1, y1 = box
    middle = (y0 + y1) / 2
    height = (y1 - y0) / 2 * amplitude
    draw.line((x0, middle, x1, middle), fill='#2B4359', width=2)
    for x in range(x0, x1 + 1, 80):
        draw.line((x, y0, x, y1), fill='#172D40', width=1)
    points = []
    for x in range(x0, x1 + 1):
        p = (x - x0) / (x1 - x0) * cycles
        if kind == 'square':
            v = 1 if p % 1 < .5 else -1
        elif kind == 'triangle':
            v = 2 / math.pi * math.asin(math.sin(2 * math.pi * p))
        else:
            v = math.sin(2 * math.pi * p)
        points.append((x, middle - height * v))
    draw.line(points, fill=color, width=5)


def make_page(index):
    image = Image.new('RGB', (1280, 960), BG)
    d = ImageDraw.Draw(image)
    # Top 0..236 and bottom 860..928 are reserved for the existing HDMI OSD.
    label(d, (720, 164), '看得见的声音 / SOUND LAB', 26, MUTED)
    d.line((48, 235, 1232, 235), fill='#29465B', width=2)
    if index == 4:
        label(d, (48, 247), '05 / 当声音成为音乐', 48)
        label(d, (50, 313), '从频率、幅度和音色，到一段动听的旋律', 30, MUTED)
        label(d, (50, 367), '旋律实时生成 · FPGA数字音频合成', 35, GOLD)
        label(d, (50, 427), 'KEY3：时域＋频域分析 · KEY2 下一课', 28, CYAN)
        d.rectangle((48, 476, 1232, 832), fill='#1B354E', outline='#29465B', width=2)
        for y in (550,594,638,682,726):
            d.line((76,y,1204,y), fill='#58758B', width=3)
        # Vector-native staff graphic, matching the supplied simple-note motif.
        for x,y in ((146,682),(308,638),(470,594),(632,638),(794,660),(956,572),(1118,616)):
            d.ellipse((x-24,y-16,x+24,y+16), fill='#76DCD6')
            d.line((x+22,y,x+22,y-126), fill='#76DCD6', width=8)
        points=[(x,788-14*math.sin((x-76)/95)-9*math.sin((x-76)/167)) for x in range(76,1205)]
        d.line(points,fill='#AFA07A',width=5)
        return image
    titles = ('音高与频率', '响度与幅度', '音色与波形', '左右声道')
    subtitles = (
        '听音阶变化，观察同一时间窗口内的波形疏密。',
        '频率保持 440 Hz，比较振幅变化带来的听感差异。',
        '频率保持 440 Hz，比较不同波形的声音特色。',
        '观察 L / R 两条曲线，分辨声音来自哪个声道。',
    )
    label(d, (48, 247), f'0{index+1} / {titles[index]}', 48)
    label(d, (50, 313), subtitles[index], 30, MUTED)
    stages = (
        '220 Hz  →  330 Hz  →  440 Hz  →  660 Hz',
        '相对峰值：1/4  →  1/2  →  1  →  1/2',
        '正弦波  →  三角波  →  方波  →  正弦波',
        '仅左声道  →  仅右声道  →  双声道  →  双声道',
    )
    label(d, (50, 367), stages[index], 35, GOLD)
    label(d, (50, 427), '每秒切换一步 · KEY3 开关实时波形 · KEY2 下一课', 28, CYAN)
    d.rectangle((48, 476, 1232, 832), fill='#0C2030', outline='#29465B', width=2)
    if index == 0:
        label(d, (72, 492), '较低频率 / 较低音', 27, CYAN)
        curve(d, (420, 508, 1194, 610), cycles=3)
        label(d, (72, 663), '较高频率 / 较高音', 27, GOLD)
        curve(d, (420, 671, 1194, 782), cycles=6, color=GOLD)
    elif index == 1:
        for row, amplitude in enumerate((.25, .5, 1)):
            top = 504 + row * 101
            label(d, (76, top+17), ('小幅度 1/4', '中幅度 1/2', '大幅度 1')[row], 27, CYAN)
            curve(d, (420, top, 1194, top+75), cycles=4, amplitude=amplitude)
        label(d, (76, 805), '注意：峰值比例不等于主观响度比例。', 20, MUTED)
    elif index == 2:
        for col, kind in enumerate(('sine', 'triangle', 'square')):
            left = 76 + col * 390
            label(d, (left, 502), ('正弦波', '三角波', '方波')[col], 30, CYAN)
            curve(d, (left, 590, left+340, 744), kind=kind, cycles=2,
                  color=GOLD if col==2 else CYAN)
        label(d, (76, 796), '同频、同峰值；谐波结构不同，音色与听感也不同。', 22, MUTED)
    else:
        label(d, (76, 504), 'L 左声道 / 440 Hz', 29, CYAN)
        curve(d, (420, 512, 1194, 618), cycles=4)
        label(d, (76, 674), 'R 右声道 / 660 Hz', 29, GOLD)
        curve(d, (420, 680, 1194, 790), cycles=6, color=GOLD)
    return image


def sine8(angle):
    i = 64 - (angle & 63) if angle & 64 else angle & 63
    return -SINE[i] if angle & 128 else SINE[i]


def pcm(phase, page, step, position, right, step_samples=RATE):
    a = phase >> 24
    base = sine8(a)
    if page == 2 and step == 1:
        magnitude = 64 - (a & 63) if a & 64 else a & 63
        base = 32767 if magnitude == 64 else magnitude * 512
        if a & 128:
            base = -base
    elif page == 2 and step == 2:
        base = -32767 if a & 128 else 32767
    if page == 1:
        base >>= (2 if step == 0 else 1 if step in (1, 3) else 0)
    if page == 3 and ((step == 0 and right) or (step == 1 and not right)):
        base = 0
    envelope = position if position < 64 else step_samples-1-position if position >= step_samples-64 else 64
    return base * 60 * envelope // 64


def make_audio(page, destination):
    phase_l = phase_r = 0
    data = bytearray()
    if page == 4:
        for value, _, _ in melody_values():
            data.extend((value & 0xffffff).to_bytes(3,'little')*2)
    for n in range(RATE * 8 if page != 4 else 0):
        position, step = n % RATE, n // RATE % 4
        for value in (pcm(phase_l, page, step, position, False), pcm(phase_r, page, step, position, True)):
            data.extend((value & 0xffffff).to_bytes(3, 'little'))
        inc_l = INCREMENTS[step] if page == 0 else INCREMENTS[2]
        inc_r = INCREMENTS[step] if page == 0 else INCREMENTS[3] if page == 3 else INCREMENTS[2]
        phase_l = (phase_l + inc_l) & 0xffffffff
        phase_r = (phase_r + inc_r) & 0xffffffff
    with wave.open(str(destination), 'wb') as wav:
        wav.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(data)


def melody_values(unit_samples=12000, attack_shift=2, release_shift=3):
    """Integer oracle: sine DDS, per-note gain, attack/release, phase restart."""
    for note, (inc, units, gain) in enumerate(zip(MELODY_INCREMENTS, MELODY_UNITS, MELODY_GAINS)):
        phase, length = 0, unit_samples*units
        for position in range(length):
            remaining=length-1-position
            env=(position>>attack_shift) if position<(64<<attack_shift) else (remaining>>release_shift) if remaining<(64<<release_shift) else 64
            amplitude=(sine8(phase>>24)*gain*60)>>6
            yield (amplitude*env)>>6, note, position
            phase=(phase+inc)&0xffffffff


def make_card(files):
    total, start, reserved = 131072, 2048, 32
    count = total - start
    fat_sectors = 1000
    while True:
        clusters = count - reserved - 2*fat_sectors
        new = (4*(clusters+2)+511)//512
        if new == fat_sectors:
            break
        fat_sectors = new
    image = bytearray(total*512)
    image[440:444] = b'SCIE'
    image[446:462] = struct.pack('<B3sB3sII', 0, b'\xfe\xff\xff', 0x0c, b'\xfe\xff\xff', start, count)
    image[510:512] = b'\x55\xaa'
    boot = bytearray(512)
    boot[0:11] = b'\xeb\x58\x90SCIENCE '
    struct.pack_into('<HBHBHHBHHHII', boot, 11, 512, 1, reserved, 2, 0, 0, 0xf8, 0, 63, 255, start, count)
    struct.pack_into('<IHHIHH', boot, 36, fat_sectors, 0, 0, 2, 1, 6)
    boot[64] = 0x80
    boot[66] = 0x29
    struct.pack_into('<I', boot, 67, 0x53434945)
    boot[71:82] = b'SEE SOUND  '
    boot[82:90] = b'FAT32   '
    boot[510:512] = b'\x55\xaa'
    image[start*512:(start+1)*512] = boot
    image[(start+6)*512:(start+7)*512] = boot
    fat = bytearray(fat_sectors*512)
    struct.pack_into('<III', fat, 0, 0x0ffffff8, 0xffffffff, 0x0fffffff)
    data_start = start + reserved + 2*fat_sectors
    root = bytearray(512)
    root[0:11] = b'SEE SOUND  '
    root[11] = 8
    cluster = 3
    metadata = []
    for number, (path, short_name) in enumerate(files, 1):
        content = path.read_bytes()
        used = (len(content)+511)//512
        for c in range(cluster, cluster+used):
            struct.pack_into('<I', fat, c*4, c+1 if c < cluster+used-1 else 0x0fffffff)
        lba = data_start + cluster - 2
        image[lba*512:lba*512+len(content)] = content
        entry = number * 32
        root[entry:entry+11] = short_name.encode('ascii')
        root[entry+11] = 0x20
        struct.pack_into('<H', root, entry+20, cluster >> 16)
        struct.pack_into('<HHHI', root, entry+22, 0, (46<<9)|(10<<5)|25, cluster&0xffff, len(content))
        metadata.append({'name': path.name, 'root_name': short_name[:8].rstrip()+'.BMP', 'start_sector': lba, 'bytes': len(content)})
        cluster += used
    image[data_start*512:(data_start+1)*512] = root
    for bank in range(2):
        at = (start+reserved+bank*fat_sectors)*512
        image[at:at+len(fat)] = fat
    info = bytearray(512)
    struct.pack_into('<I', info, 0, 0x41615252)
    struct.pack_into('<IIII', info, 484, 0x61417272, clusters-(cluster-2), cluster, 0)
    struct.pack_into('<I', info, 508, 0xaa550000)
    for sector in (1, 7):
        image[(start+sector)*512:(start+sector+1)*512] = info
    target = OUT/'science_tf_64MiB.img'
    target.write_bytes(image)
    return metadata, hashlib.sha256(image).hexdigest()


def main():
    for sub in ('bmp', 'audio', 'preview'):
        (OUT/sub).mkdir(parents=True, exist_ok=True)
    sizes = ((640,480), (800,600), (1024,768), (1280,960), (960,720))
    names = ('01_pitch', '02_level', '03_timbre', '04_stereo', '05_melody')
    pages, files = [], []
    for i, name in enumerate(names):
        page = make_page(i)
        path = OUT/'bmp'/f'{name}.bmp'
        page.resize(sizes[i], Image.Resampling.LANCZOS).save(path)
        preview = page.resize((640,480), Image.Resampling.LANCZOS)
        preview.save(OUT/'preview'/f'{name}.png')
        pages.append(preview)
        # Name field: pad basename to eight characters, then BMP extension.
        basename = ('01PITCH','02LEVEL','03TIMBR','04STEREO','05MELODY')[i]
        files.append((path, f'{basename:<8}BMP'))
        make_audio(i, OUT/'audio'/f'{name}_48k_24bit_stereo.wav')
        # Independent load-time bilinear oracle: source rows are BMP bottom-up.
        source = np.asarray(Image.open(path).convert('RGB'), dtype=np.int32)[::-1]
        height, width = source.shape[:2]
        nx, ny = np.arange(640)*(width-1), np.arange(480)*(height-1)
        x0, y0 = nx//639, ny//479
        x1, y1 = np.minimum(x0+1,width-1), np.minimum(y0+1,height-1)
        fx, fy = (nx%639)*256//639, (ny%479)*256//479
        a = source[y0[:,None],x0[None,:]]
        b = source[y0[:,None],x1[None,:]]
        c = source[y1[:,None],x0[None,:]]
        d = source[y1[:,None],x1[None,:]]
        h0 = (a*(256-fx[None,:,None])+b*fx[None,:,None]+128)>>8
        h1 = (c*(256-fx[None,:,None])+d*fx[None,:,None]+128)>>8
        result = (h0*(256-fy[:,None,None])+h1*fy[:,None,None]+128)>>8
        (ROOT/'tests'/f'science_image_{i}.hex').write_text(
            '\n'.join(f'{r:02x}{g:02x}{b:02x}' for r,g,b in result.reshape(-1,3))+'\n', encoding='ascii')
    contact = Image.new('RGB', (1280,1440),BG)
    for i,page in enumerate(pages):
        contact.paste(page, ((i%2)*640,(i//2)*480))
    contact.save(OUT/'preview'/'overview.png')
    entries, digest = make_card(files)
    manifest = {'sample_rate': RATE, 'sample_bits': 24, 'channels': 2, 'audio_seconds': 8,
                'samples_per_step': RATE, 'phase_increments': INCREMENTS,
                'images': entries, 'card_sha256': digest,
                'melody': {'midi': MELODY_MIDI, 'eighth_note_units': MELODY_UNITS,
                           'gain_q6': MELODY_GAINS,'phase_increments': MELODY_INCREMENTS,
                           'unit_samples': 12000,'total_samples': sum(MELODY_UNITS)*12000,
                           'playback': 'once on entry, silence after completion'}}
    (OUT/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    vectors=[]
    for page in range(4):
        pl=pr=0
        for n in range(4*512):
            step, position=n//512,n%512
            left=pcm(pl,page,step,position,False,512)&0xffffff
            right=pcm(pr,page,step,position,True,512)&0xffffff
            vectors.append(f'{left:06x}{right:06x}')
            il=INCREMENTS[step] if page==0 else INCREMENTS[2]
            ir=INCREMENTS[step] if page==0 else INCREMENTS[3] if page==3 else INCREMENTS[2]
            pl=(pl+il)&0xffffffff; pr=(pr+ir)&0xffffffff
    (ROOT/'tests'/'science_audio_vectors.hex').write_text('\n'.join(vectors)+'\n',encoding='ascii')
    music=[f'{v&0xffffff:06x}{v&0xffffff:06x}' for v,_,_ in melody_values(128,0,0)]
    (ROOT/'tests'/'melody_audio_vectors.hex').write_text('\n'.join(music)+'\n',encoding='ascii')
    full_music=[f'{v&0xffffff:06x}{v&0xffffff:06x}' for v,_,_ in melody_values()]
    (ROOT/'tests'/'melody_full_vectors.hex').write_text('\n'.join(full_music)+'\n',encoding='ascii')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
