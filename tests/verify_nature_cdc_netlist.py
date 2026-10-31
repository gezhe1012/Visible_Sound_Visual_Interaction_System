"""Check geometry synchronizer FF connectivity at gate and packed route."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
def norm(s):
    return re.sub(r'\s+','',s.strip().lstrip('\\'))

def audit(file,packed):
    text=file.read_text(encoding='utf-8')
    aliases={norm(a):norm(b) for a,b in re.findall(r'assign\s+(\\[^;=]+)\s*=\s*(\\[^;]+);',text)}
    def canon(s):
        s=norm(s);seen=set()
        while s not in seen:
            seen.add(s)
            if s in aliases:s=aliases[s];continue
            m=re.fullmatch(r'(.+)\[(\d+)\]',s)
            if m and m[1] in aliases:s=aliases[m[1]]+'['+m[2]+']';continue
            break
        return s
    drivers={}
    pattern=r'EG_PHY_[LM]SLICE\s*#\(.*?\);' if packed else r'AL_MAP_SEQ\s*#\(.*?\);'
    for cell in re.findall(pattern,text,re.S):
        d=re.search(r'\.mi\(([^)]+)\)',cell) if packed else re.search(r'\.d\(([^)]+)\)',cell)
        q=re.search(r'\.q\(([^)]+)\)',cell)
        clk=re.search(r'\.clk\(([^)]+)\)',cell)
        if packed and q and clk and 'frame_read_write_m0/intro_meta' in q[1]:
            # TD legally combines the visible&active gate with the first mode
            # FF (REG0_SD=F). Verify the real AND LUT and FF, not a guessed MI.
            assert '.DFFMODE("FF")' in cell and '.REG0_SD("F")' in cell
            assert ".INIT_LUTF0(16'b1111000000000000)" in cell
            assert ".INIT_LUTG0(16'b1111000000000000)" in cell
            c=re.search(r'\.c\(\{([^}]+)\}\)',cell)[1].split(',')[-1]
            source_d=re.search(r'\.d\(\{([^}]+)\}\)',cell)[1].split(',')[-1]
            assert canon(c)=='u_nature_intro_controls/visible'
            assert canon(source_d).startswith('u_nature_intro_controls/active')
            drivers[canon('frame_read_write_m0/intro_meta')]=('<visible AND active>',canon(clk[1]))
        if not(d and q and clk):continue
        ds=d[1].strip().strip('{}').split(',');qs=q[1].strip().strip('{}').split(',')
        if len(ds)!=len(qs):continue
        for index,(source,target) in enumerate(zip(ds,qs)):
            target=canon(target)
            if packed and target.startswith('frame_read_write_m0/'):
                lane=len(qs)-1-index
                if f'.REG{lane}_SD("MI")' not in cell:continue
            drivers[target]=(canon(source),canon(clk[1]))
    prefix='frame_read_write_m0/g_intro_map$u_address/'
    checked=0
    for name,width,source in [('p',2,'photo'),('s',6,'slide')]:
        for bit in range(width):
            first=canon(f'{prefix}{name}0[{bit}]');second=canon(f'{prefix}{name}1[{bit}]')
            expected=canon(f'u_nature_intro_controls/{source}[{bit}]')
            assert first in drivers,(file.name,'missing first',first)
            assert second in drivers,(file.name,'missing second',second)
            assert drivers[first][0]==expected,(file.name,first,drivers[first],expected)
            assert drivers[second][0]==first,(file.name,second,drivers[second],first)
            assert drivers[first][1]==drivers[second][1],(first,second,'different clocks')
            assert 'Sdr_clk' in drivers[first][1] or 'ext_mem_clk' in drivers[first][1]
            checked+=2
    first=canon('frame_read_write_m0/intro_meta');second=canon('frame_read_write_m0/intro_synced')
    assert first in drivers and second in drivers,(file.name,'mode synchronizers absent')
    assert drivers[second][0]==first,(file.name,'mode first-stage bypassed')
    assert drivers[first][1]==drivers[second][1]
    print(f'PASS {file.name}: {checked+2} geometry/mode FFs, independent two-stage paths')

audit(ROOT/'tests/nature_gate_netlist.v',False)
audit(ROOT/'tests/nature_routed_netlist.v',True)
for filename in ['nature_gate_exceptions.txt','nature_routed_exceptions.txt']:
    report=(ROOT/'doc/nature_intro/evidence'/filename).read_text(encoding='utf-8')
    for needle in ['u_nature_intro_controls/slide*','u_nature_intro_controls/photo*','frame_write_toggle_mem','ack_toggle','play_ready']:
        assert needle in report,(filename,'CDC bounds missing',needle)
    assert '20 -datapath_only' in report and '39 -datapath_only' in report
    owned=[line for line in report.splitlines() if 'set_max_delay -from' in line and '-through [get_nets' in line and re.match(r'^\s*\d+',line)]
    assert len(owned)==3,(filename,'Missing bounded bundle')
    for line in owned:
        count,dominated,shadowed,ignored=map(int,re.match(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)',line).groups())
        assert count>0 and count==dominated and shadowed==0 and ignored==0,(filename,'Unbound/overridden CDC constraint',line)
sdc=(ROOT/'src/user_source/constraints_source/timing.sdc').read_text(encoding='utf-8')
assert '-through [get_nets' in sdc
assert 'set_clock_groups -asynchronous' not in '\n'.join(line for line in sdc.splitlines() if not line.lstrip().startswith('#'))
print('ALL NATURE CDC CONNECTIVITY TESTS PASSED: 36 geometry/mode FFs, first-stage bounds present, later stages not excepted')
