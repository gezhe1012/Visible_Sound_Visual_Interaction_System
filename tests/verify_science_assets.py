"""Independent checks of the card filesystem, contiguous BMPs and audio lessons."""
from pathlib import Path
import hashlib, json, struct, wave
import numpy as np
from PIL import Image

root=Path(__file__).resolve().parents[1]/'doc'/'science_kiosk'
manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
card=(root/'science_tf_64MiB.img').read_bytes()
assert len(card)==64*1024*1024 and card[510:512]==b'\x55\xaa'
start,total=struct.unpack_from('<II',card,454)
bpb=card[start*512:(start+1)*512]
bps,spc,reserved,fats=struct.unpack_from('<HBHB',bpb,11)
fat_sectors=struct.unpack_from('<I',bpb,36)[0]
assert bps==512 and spc==1 and fats==2 and total+start==len(card)//512
fat_start=(start+reserved)*512
data_start=start+reserved+2*fat_sectors
assert card[fat_start:fat_start+fat_sectors*512]==card[fat_start+fat_sectors*512:fat_start+2*fat_sectors*512]
directory=card[data_start*512:(data_start+1)*512]
for n,entry in enumerate(manifest['images'],1):
    record=directory[n*32:(n+1)*32]
    cluster=(struct.unpack_from('<H',record,20)[0]<<16)|struct.unpack_from('<H',record,26)[0]
    size=struct.unpack_from('<I',record,28)[0]
    lba=data_start+cluster-2
    assert lba==entry['start_sector'] and lba<131072
    payload=card[lba*512:lba*512+size]
    assert payload==(root/'bmp'/entry['name']).read_bytes()
    assert payload[:2]==b'BM' and struct.unpack_from('<H',payload,28)[0]==24
    assert struct.unpack_from('<I',payload,30)[0]==0
    width,height=struct.unpack_from('<ii',payload,18)
    assert 1<=width<=2048 and 1<=height<=2048 and width*3%4==0
    for offset in range((size+511)//512):
        link=struct.unpack_from('<I',card,fat_start+4*(cluster+offset))[0]&0x0fffffff
        assert link==(cluster+offset+1 if offset<(size+511)//512-1 else 0x0fffffff)
    assert Image.open(root/'bmp'/entry['name']).mode=='RGB'
print('PASS FAT32: four ordered, contiguous, header-verified BMPs; identical FAT copies and source payloads')

def load_audio(name):
    with wave.open(str(name),'rb') as wav:
        assert wav.getparams()[:4]==(2,3,48000,384000)
        data=np.frombuffer(wav.readframes(wav.getnframes()),dtype=np.uint8).reshape(-1,2,3).astype(np.int32)
    values=data[:,:,0]|(data[:,:,1]<<8)|(data[:,:,2]<<16)
    return np.where(values&0x800000,values-0x1000000,values)

def spectrum(a):
    return abs(np.fft.rfft(a))

def peak(a):
    return int(np.argmax(spectrum(a)[1:])+1)

names=('01_pitch','02_level','03_timbre','04_stereo')
audio=[load_audio(root/'audio'/f'{name}_48k_24bit_stereo.wav') for name in names]
for a in audio:
    assert abs(a).max()<=1966020 and (a[0]==0).all()
assert np.array_equal(audio[0][:,0],audio[0][:,1])
assert [peak(audio[0][i*48000:(i+1)*48000,0]) for i in range(4)]==[220,330,440,660]
rms=np.array([np.sqrt(np.mean(audio[1][i*48000:(i+1)*48000,0].astype(float)**2)) for i in range(4)])
assert np.allclose(rms/rms[2],[.25,.5,1,.5],atol=.001)
harmonics=[]
for i in range(3):
    s=spectrum(audio[2][i*48000:(i+1)*48000,0])
    assert np.argmax(s)==440
    harmonics.append(s[1320]/s[440])
assert harmonics[0]<.01 and .09<harmonics[1]<.13 and .30<harmonics[2]<.36
assert not audio[3][:48000,1].any() and not audio[3][48000:96000,0].any()
assert peak(audio[3][96000:144000,0])==440 and peak(audio[3][96000:144000,1])==660
assert hashlib.sha256(card).hexdigest()==manifest['card_sha256']
print('PASS WAV: 48K/24-bit/stereo, pitch FFT peaks, 1:2:4 amplitude ratios, sine/triangle/square harmonics and L/R routing')
print('ALL SCIENCE ASSET TESTS PASSED')
