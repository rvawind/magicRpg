"""
把工程内改动过的 vJass 库与 YDWE 生成的地图脚本拼成单一脚本，供 clijasshelper 做语法/符号校验。

用法（仓库根目录）：
    python tools/precompile_check/build_harness.py
    tools/precompile_check/run.bat

前置：先用 YDWE 保存一次地图，使
    C:/Users/admin/Documents/WE/KKWE_nncouVer1.5.7.1/logs/inputwar3map.j
存在且包含最新生成的 GUI 部分。

库的位置是动态查找的（YDWE 每次重新生成脚本后行号会变，硬编码行号会错位）。
"""
import io
import os
import re

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, 'out')
PROJ = os.path.abspath(os.path.join(BASE, '..', '..'))
SRC = r"C:/Users/admin/Documents/WE/KKWE_nncouVer1.5.7.1/logs/inputwar3map.j"

if not os.path.isdir(OUT):
    os.makedirs(OUT)

with io.open(SRC, 'r', encoding='utf-8', errors='replace') as f:
    lines = f.readlines()


def strip_pp(text):
    out = []
    for ln in text.splitlines(True):
        if re.match(r'^\s*#(include|ifndef|ifdef|else|endif|define)\b', ln):
            continue
        out.append(ln)
    return ''.join(out)


def read_stripped(rel):
    p = os.path.join(PROJ, rel)
    with io.open(p, 'r', encoding='utf-8', errors='replace') as f:
        return strip_pp(f.read())


def find_lib(name):
    start = None
    pat = re.compile(r'^library\s+%s\b' % re.escape(name))
    for i, ln in enumerate(lines):
        if pat.match(ln):
            start = i
            break
    if start is None:
        raise SystemExit('library not found: %s' % name)
    for j in range(start + 1, len(lines)):
        if re.match(r'^endlibrary\b', lines[j]):
            return start, j
    raise SystemExit('endlibrary not found for: %s' % name)


parts = []
prefix = lines[:find_lib('DebugLogger')[0]]
parts.append(''.join(prefix))

# 2) 物理房/门洞模板矩形：地图里还没有时才合成（作者创建后直接使用真实定义）
if not any('gg_rct_FR_A1' in ln for ln in prefix):
    synth = ['\nglobals\n']
    for t in 'ABCD':
        for i in range(1, 6):
            synth.append('    rect gg_rct_FR_%s%d = null\n' % (t, i))
        for d in ('UP', 'DOWN', 'LEFT', 'RIGHT'):
            synth.append('    rect gg_rct_FR_%s_DOOR_%s = null\n' % (t, d))
    synth.append('endglobals\n')
    parts.append(''.join(synth))
    print('note: gg_rct_FR_* not found in map script, synthesized globals')
else:
    print('note: using gg_rct_FR_* definitions from map script')

# 3) 未改动的旧库：直接取地图脚本里的编译结果
for name in ['MonsterGroup', 'ChapterTimer', 'BzAPI', 'UiPick', 'YDWEAbilityState', 'RewardItem']:
    a, b = find_lib(name)
    parts.append(''.join(lines[a:b + 1]))

# 4) 本次改动/重写的库：使用工程内源码
SOURCES = [
    'debug.j',
    'magic/map/area/core/grid.j',
    'magic/map/area/core/slot.j',
    'magic/map/area/core/data.j',
    'magic/map/area/core/enter.j',
    'magic/map/area/core/exit.j',
    'magic/map/area/core/monster_room.j',
    'magic/map/area/core/emergency.j',
    'magic/map/curse/curse.j',
    'magic/map/boss/boss.j',
    'magic/map/reward/altar.j',
    'magic/map/chapter/chapter.j',
    'magic/map/area/config/forest.j',
    'magic/map/area/config/dust.j',
]
for rel in SOURCES:
    parts.append('\n// ===== FILE: %s =====\n' % rel)
    parts.append(read_stripped(rel))

# 5) 后缀：最后一个被替换库（Dust）之后的内容
REPLACED = ['DebugLogger', 'areaGrid', 'areaSlot', 'areaData', 'areaEnter', 'areaExit',
            'RewardAltar', 'areaMonsterRoom', 'areaEmergency', 'CurseSystem',
            'BossSystem', 'ChapterManager', 'Forest', 'Dust']
suffix_start = max(find_lib(name)[1] for name in REPLACED) + 1
parts.append(''.join(lines[suffix_start:]))

out = ''.join(parts)
with io.open(os.path.join(OUT, 'harness.j'), 'w', encoding='utf-8') as f:
    f.write(out)
print('written', len(out.splitlines()), 'lines; suffix starts at source line', suffix_start + 1)
