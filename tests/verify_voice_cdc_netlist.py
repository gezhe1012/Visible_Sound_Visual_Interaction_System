"""Check actual packed synchronizer wiring, including two FFs sharing a slice."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / 'tests/voice_routed_netlist.v').read_text(encoding='utf-8')
prefix = 'frame_read_write_m0/frame_fifo_read_m0/'
drivers = {}
for cell in re.findall(r'EG_PHY_[LM]SLICE\s*#\(.*?\);', text, re.S):
    mi = re.search(r'\.mi\(\{([^}]+)\}\)', cell)
    q = re.search(r'\.q\(\{([^}]+)\}\)', cell)
    clock = re.search(r'\.clk\(([^)]+)\)', cell)
    if not (mi and q and clock):
        continue
    inputs = [s.strip().lstrip('\\') for s in mi[1].split(',')]
    outputs = [s.strip().lstrip('\\') for s in q[1].split(',')]
    for index, (source, target) in enumerate(zip(inputs, outputs)):
        if target.startswith(prefix + 'read_req_d'):
            lane = len(outputs) - 1 - index
            assert f'.REG{lane}_SD("MI")' in cell
            assert '.DFFMODE("FF")' in cell
            assert target not in drivers
            drivers[target] = (source, clock[1].strip().lstrip('\\'))
for index in range(3):
    target = prefix + f'read_req_d{index}'
    expected = 'video_timing_data_m0/read_req' if index == 0 else prefix + f'read_req_d{index-1}'
    assert target in drivers, target
    assert drivers[target][0] == expected, (target, drivers[target])
    assert drivers[target][1] == 'U3/u2_ram/u1_init_ref/Sdr_clk'
    print(f'PASS routed CDC FF: {expected} -> {target}')
sdc = (root / 'src/user_source/constraints_source/timing.sdc').read_text(encoding='utf-8')
assert 'read_req_d0_reg*.d' in sdc
assert not re.search(r'get_pins[^\n]*read_req_d[12]', sdc)
print('ALL VOICE CDC CONNECTIVITY TESTS PASSED: three physical memory-clock flip-flops, held video request at first D, no combinational shortcut, later stages not excepted')
