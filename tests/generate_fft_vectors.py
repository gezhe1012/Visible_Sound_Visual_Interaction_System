"""Independent integer FFT oracle plus NumPy FFT cross-check. No external IP.
Only generates ignored test vectors. --check-tables verifies the HDL constants.
"""
from pathlib import Path
import math
import re
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests'
N = 1024
TW = [(round(32767*math.cos(2*math.pi*k/N)), round(-32767*math.sin(2*math.pi*k/N))) for k in range(N//2)]
WIN = [round(32767*(.5-.5*math.cos(2*math.pi*k/N))) for k in range(N)]


def clip(v):
    return max(-32768, min(32767, v))


def fixed_fft(samples):
    data = [(0, 0)] * N
    for i, sample in enumerate(samples):
        rev = int(f'{i:010b}'[::-1], 2)
        data[rev] = (int(sample)*WIN[i] >> 15, 0)
    half = 1
    while half < N:
        for base in range(0, N, half*2):
            for j in range(half):
                ar, ai = data[base+j]
                br, bi = data[base+j+half]
                wr, wi = TW[j*N//(2*half)]
                tr = (br*wr-bi*wi) >> 15
                ti = (br*wi+bi*wr) >> 15
                data[base+j] = (clip((ar+tr) >> 1), clip((ai+ti) >> 1))
                data[base+j+half] = (clip((ar-tr) >> 1), clip((ai-ti) >> 1))
        half *= 2
    return data


def height(v):
    if v < 4:
        return 0
    exponent = v.bit_length()-1
    fraction = (v << 3) >> exponent
    return max(0, min(66, (exponent-2)*6+((fraction-8)*6 >> 3)))


def bands(data):
    mag = [abs(r)+abs(i) for r, i in data[:512]]
    out, pos = [], 0
    for size in [1]*32+[2]*32+[4]*32+[9]*32:
        out.append(height(max(mag[pos:pos+size])))
        pos += size
    assert pos == 512
    return out


def word(r, i):
    return f'{r & 65535:04x}{i & 65535:04x}'


def main():
    if '--tables' in sys.argv:
        print('// Q1.15 FFT twiddles and periodic Hann; generated constants.')
        print('module fft1024_tables(input clk,input [8:0] twiddle_address,input [9:0] window_address,')
        print('    output reg [31:0] twiddle_q,output reg [15:0] window_q);')
        print('reg [31:0] twiddle_rom[0:511];\nreg [15:0] window_rom[0:1023];\ninitial begin')
        for k, (r, i) in enumerate(TW):
            print(f"    twiddle_rom[{k}]=32'h{word(r,i)};")
        for k, value in enumerate(WIN):
            print(f"    window_rom[{k}]=16'h{value:04x};")
        print('end\nalways @(posedge clk) begin\n    twiddle_q<=twiddle_rom[twiddle_address];')
        print('    window_q<=window_rom[window_address];\nend\nendmodule')
        return
    # Verify source ROM values independently; no simulation-relative ROM paths.
    text = (ROOT/'src/user_source/hdl_source/fft1024_tables.v').read_text()
    assert re.findall(r"twiddle_rom\[\d+\]=32'h([0-9a-f]+)", text) == [word(*v) for v in TW]
    assert re.findall(r"window_rom\[\d+\]=16'h([0-9a-f]+)", text) == [f'{v:04x}' for v in WIN]
    x = np.arange(N)
    sine = lambda k, amp=16000: np.rint(amp*np.sin(2*np.pi*k*x/N)).astype(int)
    rng = np.random.default_rng(1024)
    cases = [
        ('silence', np.zeros(N, int), np.zeros(N, int)),
        ('bin10_bin14', sine(10), sine(14, 8000)),
        ('440_660_off_bin', sine(440*N/48000), sine(660*N/48000)),
        ('square_triangle', np.where(x%128<64, 24000, -24000), np.rint(24000*(2/np.pi)*np.arcsin(np.sin(2*np.pi*8*x/N))).astype(int)),
        ('full_scale_DC', np.full(N, 32767), np.full(N, -32768)),
        ('random_full_scale', rng.integers(-32768, 32768, N), rng.integers(-32768, 32768, N)),
        ('impulse_Nyquist', np.where(x==512, 32767, 0), np.where(x%2, -32768, 32767)),
        ('left_only', sine(5, 32767), np.zeros(N, int)),
    ]
    inputs, results, heights = [], [], []
    for name, left, right in cases:
        inputs += [word(int(a), int(b)) for a, b in zip(left, right)]
        for channel in (left, right):
            fixed = fixed_fft(channel)
            ideal = np.fft.fft(np.array(channel)*np.array(WIN)/32768)/N
            error = np.array([complex(r, i) for r, i in fixed])-ideal
            assert np.sqrt(np.mean(np.abs(error)**2)) < 4, (name, np.max(np.abs(error)))
            results += [word(*v) for v in fixed]
            heights += [f'{v:02x}' for v in bands(fixed)]
        print(f'PASS oracle: {name}, all 2048 complex bins + 256 heights')
    for name, values in [('input', inputs), ('complex', results), ('height', heights)]:
        (OUT/f'fft_{name}.hex').write_text('\n'.join(values)+'\n')
    print('ALL FFT ORACLE TESTS PASSED: ROMs, 8 stereo blocks, NumPy agreement')


if __name__ == '__main__':
    main()
