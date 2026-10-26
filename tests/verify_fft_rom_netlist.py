"""Verify all FFT coefficients in the real synthesized EG_PHY_BRAM INIT bits.
Run export_fft_netlist.tcl with TD first. This is not a post-route simulation.
"""
from pathlib import Path
import re
from generate_fft_vectors import TW, WIN


def main():
    text = (Path(__file__).parent/'fft_gate_netlist.v').read_text()
    pattern = (r'// address_offset=0;data_offset=(\d+);depth=(\d+);width=(\d+);[^\n]*working_width=(\d+);[^\n]*\n'
               r'\s*// u_audio_fft1024/tables/(ramread[01])[^\n]*\n\s*EG_PHY_BRAM #\((.*?)\)\)')
    found = re.findall(pattern, text, re.S)
    assert len(found) == 4, f'Expected four coefficient BRAMs, found {len(found)}'
    count = 0
    for offset, depth, width, physical_width, name, parameters in found:
        offset, depth, width, physical_width = map(int, (offset, depth, width, physical_width))
        assert physical_width in (9, 18)
        data, parity = 0, 0
        for key, value in re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9A-F]+)\)", parameters):
            data |= int(value, 16) << (256*int(key, 16))
        for key, value in re.findall(r"\.INITP_([0-9A-F]{2})\(256'h([0-9A-F]+)\)", parameters):
            parity |= int(value, 16) << (256*int(key, 16))
        source = [((r & 65535) << 16) | (i & 65535) for r, i in TW] if name == 'ramread0' else WIN
        assert len(source) == depth
        lanes = physical_width//9
        for address, expected in enumerate(source):
            actual = 0
            for lane in range(lanes):
                slot = address*lanes+lane
                actual |= (((data >> (slot*8)) & 255) | (((parity >> slot) & 1) << 8)) << (lane*9)
            mask = (1 << width)-1
            assert actual & mask == (expected >> offset) & mask, (name, offset, address, actual, expected)
        print(f'PASS synthesized {name}: {depth} coefficients, bits {offset}..{offset+width-1}')
        count += depth
    assert count == 3072
    print('ALL SYNTHESIZED FFT ROM TESTS PASSED: all 512 complex twiddles and 1024 Hann coefficients preserved')


if __name__ == '__main__':
    main()
