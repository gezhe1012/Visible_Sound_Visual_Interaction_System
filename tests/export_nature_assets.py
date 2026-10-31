"""Reproducible intro assets; original BMPs are read-only inputs.

The first BMP pixels are losslessly copied; foregrounds are bilinearly resized
offline for the SDRAM burst contract. A sector-aligned RIFF/WAV is appended after
the pixels, and a small application manifest lives in the BMP header gap.
This preserves the existing contiguous-sector scanner and needs no FAT parser.
"""
from pathlib import Path
import argparse, hashlib, json, math, struct, wave
from array import array
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAMES = ['OIP-C (1).bmp', 'OIP-C.bmp', '下载 (1).bmp', '下载.bmp']
MELODIES = [[72,76,79,76,74,72,67,72], [67,71,74,79,78,74,71,67],
            [69,72,76,79,76,74,72,69], [65,69,72,77,76,72,69,65]]

def melody(notes):
    # Eight seconds; an original gentle major/pentatonic arpeggio, not a recording.
    out = array('h')
    for n in range(48000 * 8):
        t = n / 48000
        pos = t % 1.0
        freq = 440 * 2 ** ((notes[min(int(t), 7)] - 69) / 12)
        attack = min(pos / .012, 1.0)
        release = min((1-pos) / .08, 1.0)
        envelope = attack * release * math.exp(-pos * 2.2)
        value = (.68*math.sin(2*math.pi*freq*t) + .21*math.sin(4*math.pi*freq*t)
                 + .07*math.sin(6*math.pi*freq*t)) * envelope
        # A quiet lower fifth provides harmonic movement without clipping.
        value += .08*math.sin(2*math.pi*freq*.5*t)*attack*release
        out.append(round(max(-1, min(1, value)) * 10000))
    return out.tobytes()

def riff(pcm):
    fmt = struct.pack('<4sIHHIIHH', b'fmt ', 16, 1, 1, 48000, 96000, 2, 16)
    junk = struct.pack('<4sI', b'JUNK', 460) + bytes(460)
    body = b'WAVE' + fmt + junk + struct.pack('<4sI', b'data', len(pcm)) + pcm
    assert body[496:500] == b'data' and len(body) == 504 + len(pcm)
    return b'RIFF' + struct.pack('<I', len(body)) + body

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=ROOT/'output'/'nature_intro_tf')
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records=[]
    for index, name in enumerate(NAMES):
        source = ROOT/'bmp_640x480_fit'/name
        raw=source.read_bytes()
        offset=struct.unpack_from('<I',raw,10)[0]
        width,height=struct.unpack_from('<ii',raw,18)
        assert width==640 and abs(height)==480
        assert struct.unpack_from('<H',raw,28)[0]==24 and struct.unpack_from('<I',raw,30)[0]==0
        pcm=melody(MELODIES[index]); wav=riff(pcm)
        pixels=raw[offset:offset+921600]
        if index>0:
            # The vendor SDRAM accepts aligned BL4 transfers, not arbitrary
            # addresses for each word. Pre-scale the card so HDL reads each
            # output group as four consecutive words, without changing that IP.
            card=Image.open(source).convert('RGB').resize((512,384),Image.Resampling.BILINEAR)
            canvas=Image.new('RGB',(640,480),(0,0,0));canvas.paste(card,(0,0))
            stored=canvas.transpose(Image.Transpose.FLIP_TOP_BOTTOM) if height>0 else canvas
            pixels=stored.tobytes('raw','BGR')
        header=bytearray(raw[:54]);struct.pack_into('<I',header,10,128)
        gap=bytearray(74);gap[:8]=b'ANLINTRO';gap[8]=index
        relative=(128+len(pixels)+511)//512
        struct.pack_into('<II',gap,10,relative,len(pcm)//2)
        packed=header+gap+pixels
        packed+=bytes(relative*512-len(packed));packed+=wav
        packed+=bytes((-len(packed))%512)
        struct.pack_into('<I',packed,2,len(packed))
        bmp_path=args.output/f'INTRO{index+1}.BMP'
        wav_path=args.output/f'INTRO{index+1}.WAV'
        bmp_path.write_bytes(packed);wav_path.write_bytes(wav)
        with wave.open(str(wav_path),'rb') as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(1,2,48000,384000)
            assert w.readframes(384000)==pcm
        assert packed[128:128+921600]==pixels
        assert packed[relative*512:relative*512+len(wav)]==wav
        records.append(dict(photo=index,source=str(source),source_sha256=hashlib.sha256(raw).hexdigest(),
            bmp=bmp_path.name,bmp_sha256=hashlib.sha256(packed).hexdigest(),wav=wav_path.name,
            wav_sha256=hashlib.sha256(wav).hexdigest(),wav_relative_sector=relative,
            sample_rate=48000,samples=384000,source_file_unchanged=source.read_bytes()==raw,
            pixel_data_unchanged=index==0,foreground_roi=None if index==0 else [0,0,512,384],
            foreground_resize=None if index==0 else 'offline bilinear, aspect preserved, SDRAM BL4 safe'))
    (args.output/'manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS: four BL4-safe BMP packages and four real 48kHz PCM WAVs; original source files unchanged: {args.output}')

if __name__=='__main__': main()
