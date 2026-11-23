"""生成「带测试库」的完整地图脚本编译产物（spike 原型）。

用法（仓库根目录）：
    python tools/regression/build_test_harness.py

流程：
    1) 复用预编译工具 build_harness.py 生成生产 harness.j（= 作者地图脚本结构 + 本地源码）；
    2) 把 magic/map/test/*.j 的预处理行剥掉后追加到脚本末尾；
    3) 用同一套 clijasshelper 等价编译，输出 out/harness_test_out.j；
    4) 校验产物里包含 testFramework/testEntry 及它们的 initializer 调用。

说明：
    - 只用于生成「测试版地图」的 war3map.j，不影响生产构建；
    - 测试库通过 `initializer Init` 自动在 mapa init 阶段启动（8 秒后开始跑用例）。
"""
import os
import re
import subprocess
import sys

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(PROJ, 'tools', 'precompile_check', 'out')
JH = os.path.join(OUT, 'jh')
KKWE_BIN = r'C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1\bin'
TEST_FILES = [
    'magic/map/test/test_framework.j',
    'magic/map/test/test_entry.j',
]
# 可选测试入口（env TEST_EXTRA_ENTRY=chapter_switch / ...），用于追加独立测试批次
EXTRA_TEST_FILES = {
    'chapter_switch': 'magic/map/test/test_entry_chapter_switch.j',
}
EXTRA_TEST_FILES_LIST = [v for k, v in EXTRA_TEST_FILES.items()]
_only_entry = os.environ.get('TEST_ONLY_ENTRY', '').strip()
if _only_entry:
    if _only_entry not in EXTRA_TEST_FILES:
        print('unknown TEST_ONLY_ENTRY:', _only_entry)
        sys.exit(2)
    TEST_FILES = ['magic/map/test/test_framework.j', EXTRA_TEST_FILES[_only_entry]]
    _extra_entry = ''
else:
    _extra_entry = os.environ.get('TEST_EXTRA_ENTRY', '').strip()
if _extra_entry:
    if _extra_entry not in EXTRA_TEST_FILES:
        print('unknown TEST_EXTRA_ENTRY:', _extra_entry)
        sys.exit(2)
    TEST_FILES.append(EXTRA_TEST_FILES[_extra_entry])


def strip_pp(text):
    keep = []
    for ln in text.splitlines(True):
        s = ln.lstrip('\ufeff')
        if re.match(r'^\s*#(include|ifndef|ifdef|else|endif|define)\b', s):
            continue
        keep.append(s)
    return ''.join(keep)


def run(cmd, cwd=None, env=None, shell=False):
    p = subprocess.run(cmd, cwd=cwd, env=env, shell=shell)
    if p.returncode != 0:
        print('FAILED:', cmd, 'exit=', p.returncode)
        sys.exit(p.returncode)


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    # 1) 生产 harness
    env = dict(os.environ)
    env['PATH'] = KKWE_BIN + os.pathsep + env.get('PATH', '')
    run([sys.executable, 'tools/precompile_check/build_harness.py'], cwd=PROJ, env=env)

    harness_path = os.path.join(OUT, 'harness.j')
    harness = open(harness_path, 'r', encoding='utf-8', errors='replace').read()

    parts = [harness, '\n// ===== TEST FILES (build_test_harness.py) =====\n']
    for rel in TEST_FILES:
        path = os.path.join(PROJ, *rel.split('/'))
        parts.append('\n// ===== FILE: %s =====\n' % rel)
        parts.append(strip_pp(open(path, 'r', encoding='utf-8', errors='replace').read()))
    forced = os.environ.get('TEST_FORCED_LAYOUT', '').strip()
    if forced != '':
        if not re.match(r'^[0-4]$', forced):
            print('bad TEST_FORCED_LAYOUT:', forced)
            sys.exit(2)
        parts.append('\n// ===== TEST FORCED LAYOUT =====\n')
        parts.append('library testForceLayout initializer Init requires Forest\n')
        parts.append('private function Init takes nothing returns nothing\n')
        parts.append('    call Forest_SetForcedLayout(%s)\n' % forced)
        parts.append('endfunction\nendlibrary\n')
    test_script = ''.join(parts)

    merged = os.path.join(OUT, 'harness_test.j')
    out_script = os.path.join(OUT, 'harness_test_out.j')
    open(merged, 'w', encoding='utf-8').write(test_script)
    print('written', merged, len(test_script.splitlines()), 'lines')

    # 2) 等价编译（clijasshelper）
    # JassHelper 用 GetTempFileName 写临时文件；某些运行环境（如由 DSH MCP 服务
    # 启动、temp 目录不可写的受限进程）会导致 "Get temporary filename Failed"。
    # 这里显式把 TMP/TEMP 指到工作区内的临时目录，保证任何调用方都能编译。
    tmpdir = os.path.join(OUT, 'tmp')
    os.makedirs(tmpdir, exist_ok=True)
    env['TMP'] = tmpdir
    env['TEMP'] = tmpdir
    cmd = [os.path.join(JH, 'clijasshelper.exe'), '--scriptonly',
           'common.j', 'blizzard.j', merged, out_script]
    log_path = os.path.join(OUT, 'test_compile.log')
    with open(log_path, 'w', encoding='utf-8', errors='replace') as log:
        p = subprocess.run(cmd, cwd=JH, env=env, stdout=log, stderr=subprocess.STDOUT)
        log.write('EXIT=%d\n' % p.returncode)
    log_tail = open(log_path, 'r', encoding='utf-8-sig', errors='replace').read().splitlines()[-8:]
    print('\n'.join(log_tail))
    if p.returncode != 0:
        print('TEST COMPILE FAILED')
        sys.exit(1)

    # 3) 校验：库符号与 initializer 调用都在
    #    注意 JassHelper 对 library 内函数的命名可能是 testFramework_Init /
    #    testFramework__Init / testFramework___Init 等，不能写死下划线数量，
    #    用正则找 ExecuteFunc("testFramework...Init") 即可。
    compiled = open(out_script, 'r', encoding='utf-8', errors='replace').read()
    ok = True
    for lib in ('testFramework', 'testEntry'):
        if ('LIBRARY_' + lib) in compiled:
            print('OK   LIBRARY_' + lib)
        else:
            print('MISS LIBRARY_' + lib)
            ok = False
        m = re.search(r'ExecuteFunc\("(' + lib + r'[A-Za-z0-9_]*Init)"\)', compiled)
        if m:
            print('OK   initializer call -> ' + m.group(1))
        else:
            print('MISS initializer call for ' + lib)
            ok = False
    if not ok:
        print('test library symbols missing in compiled script')
        sys.exit(1)
    print('SUCCESS: test harness compiled ->', out_script)


if __name__ == '__main__':
    main()
