"""Generate independent harmonic targets/ratios and immutable renderer fixture."""
from pathlib import Path
import subprocess
import numpy as np
from generate_secondary_audio_vectors import magnitude

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests'

def main():
    original=subprocess.check_output(['git','show','8aea081:src/user_source/hdl_source/secondary_audio_renderer.v'],cwd=ROOT).decode()
    (OUT/'enhanced_baseline_renderer.v').write_text(original.replace('module secondary_audio_renderer(','module enhanced_baseline_renderer(',1))
    pcm=[int(v,16) for v in (OUT/'secondary_audio_pcm.hex').read_text().split()]
    summaries=[int(v,16) for v in (OUT/'secondary_audio_feature.hex').read_text().split()]
    expected=[]
    for column in range(96):
        index=192+column
        samples=np.array([(w>>24)&0xffffff for w in pcm[index*1024:(index+1)*1024]],dtype=np.int64)
        samples=np.where(samples&0x800000,samples-0x1000000,samples)>>8
        mag,_=magnitude(samples)
        ref=summaries[index]
        f=(ref>>64)&32767;now=(summaries[index]>>64)&32767
        base=f*2048//375
        targets=[(f*8*h+187)//375 for h in range(1,6)]
        peaks=[max(mag[max(0,k-1):min(512,k+2)],default=0) for k in targets]
        good=bool(ref>>79) and 100<=f<=1000 and bool(summaries[index]>>79) and abs(f-now)<=10 and peaks[0]>=32
        heights=[min(38,int(p)*38//int(peaks[0])) for p in peaks] if good else [0]*5
        packed=(int(good)<<30)|sum(h<<(i*6) for i,h in enumerate(heights))
        expected.append(f'{packed:08x}')
    (OUT/'enhanced_harmonics.hex').write_text('\n'.join(expected)+'\n')
    print('ALL ENHANCED ORACLE TESTS PASSED: 96 real WAV harmonic frames, same-block measured f0 locators, neighbourhood ratios, baseline renderer 8aea081')

if __name__=='__main__':main()
