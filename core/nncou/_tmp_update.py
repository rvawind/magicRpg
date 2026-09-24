import re

with open('BossChargeSystemInterface.j', 'r', encoding='utf-8') as f:
    content = f.read()

# Helper: insert default after each type = line
def add_defaults(block_text, defaults):
    lines = block_text.split('\n')
    result = []
    arg_idx = 0
    for line in lines:
        result.append(line)
        stripped = line.strip()
        if stripped.startswith('type = ') and arg_idx < len(defaults):
            d = defaults[arg_idx]
            if d:
                indent = line[:len(line) - len(line.lstrip())]
                result.append(f'{indent}default = {d}')
            arg_idx += 1
    return '\n'.join(result)

def add_comment(block_text, comment):
    return block_text.replace('    category =', f'    comment = "{comment}"\n    category =')

def replace_doc_block(content, func_name, defaults, comment):
    pattern = re.compile(
        r'(/\*\n\s*\[' + re.escape(func_name) + r'\].*?\*/)',
        re.DOTALL
    )
    match = pattern.search(content)
    if not match:
        print(f'  NOT FOUND: {func_name}')
        return content
    old_block = match.group(1)
    new_block = old_block
    if defaults:
        new_block = add_defaults(new_block, defaults)
    if comment:
        new_block = add_comment(new_block, comment)
    return content.replace(old_block, new_block)

# ── Module doc: update step names + add example ──
old_mod = '''    使用流程：
    1. BossChargeCreateSegment*      — 按轨迹+目标类型创建段 → SegHandle
    2. BossChargeSegmentSet*Effect   — 段挂载特效（可选）
    3. BossChargeCreateSequence      — 创建序列 → Segment
    4. BossChargeSequenceAddSegment  — 段加入序列
    5. BossChargeSequenceSet*        — 全局光环/回调等（可选）
    6. BossChargeSequenceExecute     — 启动冲锋'''

new_mod = '''    使用流程：
    1. CreateSegment*      — 按轨迹+目标类型创建段 → SegHandle
    2. SegmentSet*Effect   — 段挂载特效（可选）
    3. CreateSequence      — 创建序列 → Segment
    4. SequenceAddSegment  — 段加入序列
    5. SequenceSet*        — 全局光环/回调等（可选）
    6. SequenceExecute     — 启动冲锋

    ── 简易示例（弧线→折返两段冲锋）──
    Set seg1 = CreateSegmentArc(180, 400, 0, 1, 0.6, 1)
    call SegmentSetPathEffect(seg1, "Slash.mdl", "weapon", 0.06)
    Set seg2 = CreateSegmentRebound(1.5, 0, 1.5, 0.5, 4)
    Set seq  = CreateSequence()
    call SequenceAddSegment(seq, seg1)
    call SequenceAddSegment(seq, seg2)
    call SequenceExecute(seq, GetTriggerUnit(), GetSpellTargetUnit(), 5)'''

content = content.replace(old_mod, new_mod)

# ── Segment Creation ──
content = replace_doc_block(content, 'BossChargeSys_CreateSegmentLine',
    defaults=['500.0', '0.6', 'easingTypeSmoothstep'],
    comment='最基础的直线冲锋，Boss到目标。建议距离200~800码，时长0.3~1.5秒')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentLineForward',
    defaults=['500.0', '0.6', 'easingTypeSmoothstep'],
    comment='无视目标位置，向Boss当前面朝方向冲锋')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentLineToPoint',
    defaults=[None, None, '500.0', '0.6', 'easingTypeSmoothstep'],
    comment='冲锋到预设坐标。X/Y必须填写有效世界坐标')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentArc',
    defaults=['180.0', '400.0', '0.0', 'arcDirectionCW', '0.6', 'easingTypeSmoothstep'],
    comment='绕目标单位环绕。典型配置：半圈=180度/半径400/无增量，螺旋靠近=半径增量-200')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentArcAroundPoint',
    defaults=[None, None, '180.0', '400.0', '0.0', 'arcDirectionCW', '0.6', 'easingTypeSmoothstep'],
    comment='绕固定坐标环绕。圆心X/Y必须填写有效世界坐标')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentCurve',
    defaults=['200.0', '0.5', '0.0', 'arcDirectionCW', '0.6', 'easingTypeSmoothstep'],
    comment='贝塞尔弧线冲锋。峰位0.5=对称弧，不对称度0=两侧等高，弧高越大弧越弯')

content = replace_doc_block(content, 'BossChargeSys_CreateSegmentRebound',
    defaults=['1.5', '0.0', '1.5', '0.6', 'easingTypeSmoothstep'],
    comment='冲出并折返。倍率>1越过目标后折返(1.5过半折返)，锐度越大折返越急')

# ── Segment Effects ──
content = replace_doc_block(content, 'BossChargeSys_SegmentSetPathEffect',
    defaults=[None, None, 'origin', '0.06'],
    comment='拖尾特效沿路径定时生成。附着点常用：origin(脚底)/overhead(头顶)/weapon(武器)/chest(胸口)')

content = replace_doc_block(content, 'BossChargeSys_SegmentSetStartEffect',
    defaults=[None, None, 'origin'],
    comment='段开始时爆发一次。附着点常用：origin/overhead/weapon/chest')

content = replace_doc_block(content, 'BossChargeSys_SegmentSetEndEffect',
    defaults=[None, None, 'origin'],
    comment='段结束时爆发一次。附着点常用：origin/overhead/weapon/chest')

# ── Sequence ──
content = replace_doc_block(content, 'BossChargeSys_SequenceAddSegment',
    defaults=[None, None],
    comment='段按添加顺序依次执行，最多8段')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetGlobalAura',
    defaults=[None, None, 'origin'],
    comment='Boss冲锋全程显示的光环特效')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetGlobalGround',
    defaults=[None, None, 'origin'],
    comment='每0.15秒在Boss脚底生成的行走痕迹')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetTargetPoint',
    defaults=[None, None, None],
    comment='供 *ToPoint 类段使用，覆盖执行时的目标单位')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetCenterPoint',
    defaults=[None, None, None],
    comment='供 *AroundPoint 类段使用，覆盖执行时的目标单位圆心')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetOnSegDone',
    defaults=[None, None],
    comment='每段结束时触发，可用于在段间插入技能或对话')

content = replace_doc_block(content, 'BossChargeSys_SequenceSetOnDone',
    defaults=[None, None],
    comment='全部段完成或强制取消时触发')

content = replace_doc_block(content, 'BossChargeSys_SequenceExecute',
    defaults=[None, 'GetTriggerUnit()', 'GetSpellTargetUnit()', '5'],
    comment='启动冲锋。优先级：1=低 5=普通 10=高，同优先级不打断')

# ── Destroy ──
content = replace_doc_block(content, 'BossChargeSys_DestroySegment',
    defaults=[None],
    comment='已加入序列的段会随序列自动清理，无需单独销毁')

content = replace_doc_block(content, 'BossChargeSys_DestroySequence',
    defaults=[None],
    comment='销毁序列及其全部段和特效，不会中断正在进行的冲锋')

with open('BossChargeSystemInterface.j', 'w', encoding='utf-8') as f:
    f.write(content)

print("Interface file updated.")
