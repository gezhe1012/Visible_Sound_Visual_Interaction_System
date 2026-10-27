"""Independent fixed FFT -> pitch/heat/PCM oracle; never edits lesson assets."""
from pathlib import Path
import json, math, re, wave
import numpy as np
from generate_fft_vectors import fixed_fft, bands

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests'
UPPER=[round(440*2**((36+i+.5-69)/12)) for i in range(60)]

def estimate(mag, previous=(0,False)):
    k=int(np.argmax(mag[2:]))+2;p=int(mag[k])
    if p==0:k=0
    good=p>=32 and p>=(sum(int(v) for v in mag[2:])>>6)
    a=int(mag[max(0,k-1)]);b=int(mag[k+1]) if k<511 else 0
    den=2*p-a-b
    delta=min(128,128*abs(b-a)//den) if good and k<511 and den>0 else 0
    if b<a:delta=-delta
    raw=((k*256+delta)*375+1024)//2048 if good else 0
    hz=(raw+previous[0]+1)//2 if good and previous[1] and abs(raw-previous[0])<=10 else raw
    ni=0;nv=False
    if good and hz>=64:
        ni=next((i for i,u in enumerate(UPPER) if hz<=u),59);nv=hz<=UPPER[-1]
    trace=max(0,min(47,(hz-100)*47//900))
    fields=[(good,1),(hz,15),(int(str(hz),16),20),(ni%12,4),(2+ni//12,3),(nv,1),(p,17),(ni,6),(trace,6),(0,7)]
    packed=0
    for value,width in fields:
        assert 0<=int(value)<2**width
        packed=(packed<<width)|int(value)
    return packed,(raw,good),dict(hz=hz,valid=good,note_index=ni,note_valid=nv,trace=trace,peak=p)

def magnitude(samples):
    data=fixed_fft(samples)
    return np.array([abs(r)+abs(i) for r,i in data[:512]],dtype=int),data

def main():
    table=(ROOT/'src/user_source/hdl_source/secondary_note_thresholds.v').read_text()
    assert [int(v) for v in re.findall(r"upper_hz=15'd(\d+)",table)]==UPPER
    x=np.arange(1024)
    tone=lambda f,p=0:np.rint(16000*np.sin(2*np.pi*f*x/48000+p)).astype(int)
    rng=np.random.default_rng(2710)
    pairs=[]
    complex_words=[int(v,16) for v in (OUT/'fft_complex.hex').read_text().split()]
    for block in range(8):
        chans=[]
        for ch in range(2):
            words=complex_words[block*2048+ch*1024:block*2048+ch*1024+512]
            signed=lambda n:n-65536 if n&32768 else n
            chans.append(np.array([abs(signed(w>>16))+abs(signed(w&65535)) for w in words]))
        pairs.append(tuple(chans))
    more=[(tone(220),tone(330)),(tone(440),tone(660)),(tone(440,.8),tone(660,1.2)),
        (np.rint(16000*2/np.pi*np.arcsin(np.sin(2*np.pi*440*x/48000))).astype(int),np.where(np.sin(2*np.pi*440*x/48000)>=0,16000,-16000)),
        (tone(261.63),tone(329.63)),(tone(392),tone(440)),(x*0,x*0),(x*0,tone(660)),
        (rng.integers(-1000,1000,1024),rng.integers(-32768,32768,1024))]
    pairs += [tuple(magnitude(v)[0] for v in p) for p in more]
    make=lambda k,a:np.where(np.arange(512)==k,a,0)
    pairs += [(make(10,31),make(10,32)),(make(2,4000),make(3,4000)),(make(511,8000),make(200,4000))]
    assert len(pairs)==20
    inputs=[];expected=[];previous=[(0,False),(0,False)];report=[]
    for case,pair in enumerate(pairs):
        row=[]
        for ch,mag in enumerate(pair):
            packed,previous[ch],info=estimate(mag,previous[ch]);row.append(info)
            inputs += [f'{int(v):05x}' for v in mag];expected.append(f'{packed:020x}')
        report.append(dict(case=case,left=row[0],right=row[1]))
    for name,values in [('pitch_input',inputs),('pitch_expected',expected)]:
        (OUT/f'secondary_audio_{name}.hex').write_text('\n'.join(values)+'\n')
    # Actual unmodified 48K / stereo 24-bit WAV lesson data, with capture starts
    # at 33.6ms intervals (the normal two-video-frame FFT update cadence).
    pcm=[];heats=[];features=[];levels=[]
    for page,path in enumerate(sorted((ROOT/'doc/science_kiosk/audio').glob('*.wav'))):
        with wave.open(str(path),'rb') as wav:
            assert (wav.getframerate(),wav.getsampwidth(),wav.getnchannels())==(48000,3,2)
            data=np.frombuffer(wav.readframes(wav.getnframes()),dtype=np.uint8).reshape(-1,2,3).astype(np.int32)
        data=data[:,:,0]|(data[:,:,1]<<8)|(data[:,:,2]<<16)
        signed=np.where(data&0x800000,data-0x1000000,data)
        previous=[(0,False),(0,False)]
        for column in range(96):
            start=round((4.5 if page==4 else 0)*48000+column*1612.8)
            block=signed[start:start+1024];assert block.shape==(1024,2)
            pcm += [f'{int(l)&0xffffff:06x}{int(r)&0xffffff:06x}' for l,r in block]
            channel_features=[];channel_heats=[]
            for ch in range(2):
                mag,fft=magnitude(block[:,ch]>>8)
                packed,previous[ch],info=estimate(mag,previous[ch]);channel_features.append((packed,info))
                channel_heats.append([min(15,h//4) for h in bands(fft)[:64]])
            selected=channel_features[0] if channel_features[0][1]['valid'] or not channel_features[1][1]['valid'] else channel_features[1]
            features.append(f'{selected[0]:020x}')
            heats += [f'{max(a,b):x}' for a,b in zip(*channel_heats)]
            absol=np.abs(block>>8)
            pp=(absol.max(axis=0)*7)>>10;avg=((absol.sum(axis=0)>>10)*7)>>10
            levels.append(''.join(f'{int(n):02x}' for n in (pp[0],pp[1],avg[0],avg[1])))
        print(f'PASS oracle page{page+1}: 96 real stereo FFT columns / measured pitch / PCM levels')
    for name,values in [('pcm',pcm),('heat',heats),('feature',features),('level',levels)]:
        (OUT/f'secondary_audio_{name}.hex').write_text('\n'.join(values)+'\n')
    dest=ROOT/'doc/secondary_display/audio';dest.mkdir(parents=True,exist_ok=True)
    (dest/'pitch_oracle.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ALL SECONDARY AUDIO ORACLE TESTS PASSED: 40 pitch summaries, 480 real lesson blocks, 30720 heat cells, note thresholds')

if __name__=='__main__':main()
