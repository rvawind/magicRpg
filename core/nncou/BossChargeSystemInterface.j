#ifndef BossChargeSysIncluded
#define BossChargeSysIncluded

#include "nncou\\BossChargeSystem\\BossChargeSystem.j"

/*
    Boss冲锋轨迹系统 — GUI接口层

    将 BossChargeSystem 的 vJass struct API 封装为 GUI 可用的
    integer handle 模式函数。特效参数（模型路径+附着点）直接内联，
    目标类型通过拆分函数名而非 enum 参数表达。

    使用流程：
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
    call SequenceExecute(seq, GetTriggerUnit(), GetSpellTargetUnit(), 5)

    ── 常量参考 ──
    缓动类型(easingType)： 0=匀速  1=平滑(默认)  2=渐快  3=渐慢  4=急刹
    弧方向(arcDirection) ： 1=顺时针/左弧  -1=逆时针/右弧  2=随机左右交替
    冲锋优先级           ： 1=低  5=普通  10=高（同优先级不打断）
    句柄类型             ： Segment=序列句柄  SegHandle=段句柄

    ── 附着点常用值 ──
    origin(脚底) / overhead(头顶) / weapon(武器) / chest(胸口)
    hand,left / hand,right / foot,left / foot,right / head / sprite(特效点)

    依赖：BossChargeSystem（struct 定义 + Runtime）
*/
library BossChargeSys requires BossChargeSystem

globals
    private constant integer MAX_SEGMENT_HANDLES = 999
    private constant integer MAX_SEQUENCE_HANDLES = 999

    // Segment 句柄池
    private BossChargeSegment  array gSegmentPool[MAX_SEGMENT_HANDLES]
    private integer gSegmentCount = 0

    // Sequence 句柄池
    private BossChargeSequence array gSeqPool[MAX_SEQUENCE_HANDLES]
    private integer gSeqCount = 0
endglobals

// ============================================================
// 段创建（7 个，按轨迹类型 + 目标类型拆分）
// ============================================================

/*
    [BossChargeSys_CreateSegmentLine]
    title = "[冲锋系统]创建直线冲锋段-冲向目标"
    description = "向执行时的目标单位直线冲锋，距离${总距离}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "最基础的直线冲锋，Boss到目标。建议距离200~800码，时长0.3~1.5秒"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    default = 500.0
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentLine takes real distance, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_LINE, duration, easing)
    call seg.setLineParams(TARGET_UNIT, distance)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentLineForward]
    title = "[冲锋系统]创建直线冲锋段-面朝方向"
    description = "向Boss面朝方向直线冲锋，距离${总距离}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "无视目标位置，向Boss当前面朝方向冲锋"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    default = 500.0
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentLineForward takes real distance, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_LINE, duration, easing)
    call seg.setLineParams(TARGET_FORWARD, distance)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentLineToPoint]
    title = "[冲锋系统]创建直线冲锋段-冲向坐标"
    description = "向固定坐标(${目标X},${目标Y})直线冲锋，距离${总距离}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "冲锋到预设坐标。X/Y必须填写有效世界坐标"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = real
    default = 500.0
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentLineToPoint takes real x, real y, real distance, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_LINE, duration, easing)
    call seg.setLineParams(TARGET_POINT, distance)
    set seg.pointX = x
    set seg.pointY = y
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentArc]
    title = "[冲锋系统]创建环绕弧线段-绕目标"
    description = "以执行时的目标单位为圆心环绕，扫描${总角度}度，半径${初始半径}（变化量${半径增量}），方向${弧方向}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "典型值：绕半圈=180度/半径400/增量0/顺时针；螺旋靠近=360度/半径400/增量-200/顺时针"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = degree
    default = 180.0
    [[.args]]
    type = real
    default = 400.0
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = arcDirection
    default = arcDirectionCW
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentArc takes real sweepAngle, real radius, real radiusDelta, integer direction, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_ARC, duration, easing)
    call seg.setArcParams(CENTER_TARGET, sweepAngle, radius, radiusDelta, direction)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentArcAroundPoint]
    title = "[冲锋系统]创建环绕弧线段-绕坐标"
    description = "以固定坐标(${圆心X},${圆心Y})为圆心环绕，扫描${总角度}度，半径${初始半径}（变化量${半径增量}），方向${弧方向}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "绕固定坐标环绕。圆心X/Y必须填写有效世界坐标"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = degree
    default = 180.0
    [[.args]]
    type = real
    default = 400.0
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = arcDirection
    default = arcDirectionCW
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentArcAroundPoint takes real cx, real cy, real sweepAngle, real radius, real radiusDelta, integer direction, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_ARC, duration, easing)
    call seg.setArcParams(CENTER_POINT, sweepAngle, radius, radiusDelta, direction)
    set seg.pointX = cx
    set seg.pointY = cy
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentArcAroundMid]
    title = "[冲锋系统]创建环绕弧线段-绕中点"
    description = "以Boss到目标单位的中点为圆心环绕，扫描${总角度}度，半径${初始半径}（变化量${半径增量}），方向${弧方向}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "绕Boss→目标中点环绕。典型配置：半圈=180度/半径400/无增量"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = degree
    default = 180.0
    [[.args]]
    type = real
    default = 400.0
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = arcDirection
    default = arcDirectionCW
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentArcAroundMid takes real sweepAngle, real radius, real radiusDelta, integer direction, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_ARC, duration, easing)
    call seg.setArcParams(CENTER_MID, sweepAngle, radius, radiusDelta, direction)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentCurve]
    title = "[冲锋系统]创建贝塞尔弧线段-冲向目标"
    description = "以执行时的目标单位为终点，弧高${弧高}，弧峰位置${峰位比率}，不对称度${不对称度}，弧向${弧方向}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "贝塞尔弧线冲锋。峰位0.5=对称弧，不对称度0=两侧等高，弧高越大弧越弯"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    default = 200.0
    [[.args]]
    type = real
    default = 0.5
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = arcDirection
    default = arcDirectionCW
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentCurve takes real arcHeight, real arcPeakPos, real arcAsymmetry, integer arcDirection, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_CURVE, duration, easing)
    call seg.setCurveParams(TARGET_UNIT, arcHeight, arcPeakPos, arcAsymmetry, arcDirection)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentCurveToPoint]
    title = "[冲锋系统]创建贝塞尔弧线段-冲向坐标"
    description = "以固定坐标(${目标X},${目标Y})为终点，弧高${弧高}，弧峰位置${峰位比率}，不对称度${不对称度}，弧向${弧方向}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "贝塞尔弧线冲锋到固定坐标。X/Y必须填写有效世界坐标。峰位0.5=对称弧"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = real
    default = 200.0
    [[.args]]
    type = real
    default = 0.5
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = arcDirection
    default = arcDirectionCW
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentCurveToPoint takes real x, real y, real arcHeight, real arcPeakPos, real arcAsymmetry, integer arcDirection, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_CURVE, duration, easing)
    call seg.setCurveParams(TARGET_POINT, arcHeight, arcPeakPos, arcAsymmetry, arcDirection)
    set seg.pointX = x
    set seg.pointY = y
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentRebound]
    title = "[冲锋系统]创建折返冲锋段-冲向目标"
    description = "以执行时的目标单位为终点，冲出倍率${倍率}，侧偏角${侧偏角度}，回弹锐度${锐度}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "冲出倍率>1越过目标后折返(1.6=冲过半程折返)，锐度越大折返越急(1.5标准)"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    default = 1.5
    [[.args]]
    type = degree
    default = 0.0
    [[.args]]
    type = real
    default = 1.5
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentRebound takes real overshootRatio, real sideAngle, real reboundSharpness, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_REBOUND, duration, easing)
    call seg.setReboundParams(TARGET_UNIT, overshootRatio, sideAngle, reboundSharpness)
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

/*
    [BossChargeSys_CreateSegmentReboundToPoint]
    title = "[冲锋系统]创建折返冲锋段-冲向坐标"
    description = "以固定坐标(${目标X},${目标Y})为终点，冲出倍率${倍率}，侧偏角${侧偏角度}，回弹锐度${锐度}，持续${时长}秒，缓动${缓动类型}，返回段句柄"
    comment = "折返冲锋到固定坐标。X/Y必须填写有效世界坐标"
    category = TC_NNCCS
    returns = SegHandle
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = real
    default = 1.5
    [[.args]]
    type = degree
    default = 0.0
    [[.args]]
    type = real
    default = 1.5
    [[.args]]
    type = real
    default = 0.6
    [[.args]]
    type = easingType
    default = easingTypeSmoothstep
*/
public function CreateSegmentReboundToPoint takes real x, real y, real overshootRatio, real sideAngle, real reboundSharpness, real duration, integer easing returns integer
    local BossChargeSegment seg = BossChargeSegment.create(TRAJ_REBOUND, duration, easing)
    call seg.setReboundParams(TARGET_POINT, overshootRatio, sideAngle, reboundSharpness)
    set seg.pointX = x
    set seg.pointY = y
    if gSegmentCount >= MAX_SEGMENT_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 段句柄池已满 (" + I2S(MAX_SEGMENT_HANDLES) + ")")
        return -1
    endif
    set gSegmentCount = gSegmentCount + 1
    set gSegmentPool[gSegmentCount] = seg
    return gSegmentCount
endfunction

// ============================================================
// 段特效配置（3 个，内联 modelPath + attachPoint，无需 EffectHandle）
// ============================================================

/*
    [BossChargeSys_SegmentSetPathEffect]
    title = "[冲锋系统]设置段路径拖尾特效"
    description = "在${段句柄}的路径上生成特效：模型${模型路径}，挂载于${附着点}，间隔${间隔}秒"
    comment = "拖尾特效沿路径定时生成。附着点常用：origin(脚底)/overhead(头顶)/weapon(武器)/chest(胸口)"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
    [[.args]]
    type = modelfile
    [[.args]]
    type = string
    default = origin
    [[.args]]
    type = real
    default = 0.06
*/
public function SegmentSetPathEffect takes integer segHandle, string modelPath, string attachPoint, real interval returns nothing
    if segHandle > 0 and segHandle <= gSegmentCount then
        call gSegmentPool[segHandle].setPathEffect(BossChargeEffectSpec.createSimple(modelPath, attachPoint), interval)
    endif
endfunction

/*
    [BossChargeSys_SegmentSetStartEffect]
    title = "[冲锋系统]设置段起始爆发特效"
    description = "在${段句柄}开始时爆发一次特效：模型${模型路径}，挂载于${附着点}"
    comment = "段开始时爆发一次。附着点常用：origin/overhead/weapon/chest"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
    [[.args]]
    type = modelfile
    [[.args]]
    type = string
    default = origin
*/
public function SegmentSetStartEffect takes integer segHandle, string modelPath, string attachPoint returns nothing
    if segHandle > 0 and segHandle <= gSegmentCount then
        call gSegmentPool[segHandle].setStartEffect(BossChargeEffectSpec.createSimple(modelPath, attachPoint))
    endif
endfunction

/*
    [BossChargeSys_SegmentSetEndEffect]
    title = "[冲锋系统]设置段结束爆发特效"
    description = "在${段句柄}结束时爆发一次特效：模型${模型路径}，挂载于${附着点}"
    comment = "段结束时爆发一次。附着点常用：origin/overhead/weapon/chest"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
    [[.args]]
    type = modelfile
    [[.args]]
    type = string
    default = origin
*/
public function SegmentSetEndEffect takes integer segHandle, string modelPath, string attachPoint returns nothing
    if segHandle > 0 and segHandle <= gSegmentCount then
        call gSegmentPool[segHandle].setEndEffect(BossChargeEffectSpec.createSimple(modelPath, attachPoint))
    endif
endfunction

/*
    [BossChargeSys_DestroySequence]
    title = "[冲锋系统]销毁序列句柄"
    description = "释放${序列句柄}及其所有段、段特效、全局特效。请确保冲锋已结束再调用，冲锋进行中调用将导致崩溃。停止冲锋请使用[取消Boss冲锋]"
    comment = "仅用于清理未执行或已结束的序列。停止冲锋请用取消冲锋函数"
    category = TC_NNCCS
    [[.args]]
    type = Segment
*/
public function DestroySequence takes integer hnd returns nothing
    if hnd > 0 and hnd <= gSeqCount and gSeqPool[hnd] != 0 then
        call gSeqPool[hnd].destroy()
        if hnd == gSeqCount then
            set gSeqPool[hnd] = 0
            set gSeqCount = gSeqCount - 1
        else
            set gSeqPool[hnd] = gSeqPool[gSeqCount]
            set gSeqPool[gSeqCount] = 0
            set gSeqCount = gSeqCount - 1
        endif
    endif
endfunction

// ============================================================
// 序列创建
// ============================================================

/*
    [BossChargeSys_CreateSequence]
    title = "[冲锋系统]创建冲锋序列"
    description = "创建一个空的冲锋序列，最多容纳8段，返回序列句柄"
    category = TC_NNCCS
    returns = Segment
*/
public function CreateSequence takes nothing returns integer
    local BossChargeSequence seq
    local integer i = 1
    // 扫池：清理 pendingCleanup 标记的序列（回调已执行完毕，安全销毁）
    loop
        exitwhen i > gSeqCount
        if gSeqPool[i] != 0 and gSeqPool[i].pendingCleanup then
            call DestroySequence(i)
            set i = i - 1  // DestroySequence 会交换末位元素到当前位置，重新检查
        endif
        set i = i + 1
    endloop
    // 扫孔：复用已清空的槽位
    set i = 1
    loop
        exitwhen i > gSeqCount
        if gSeqPool[i] == 0 then
            set seq = BossChargeSequence.create()
            set gSeqPool[i] = seq
            return i
        endif
        set i = i + 1
    endloop
    // 无孔则追加
    if gSeqCount >= MAX_SEQUENCE_HANDLES then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 序列句柄池已满 (" + I2S(MAX_SEQUENCE_HANDLES) + ")")
        return -1
    endif
    set gSeqCount = gSeqCount + 1
    set seq = BossChargeSequence.create()
    set gSeqPool[gSeqCount] = seq
    return gSeqCount
endfunction

// ============================================================
// 序列组装
// ============================================================

/*
    [BossChargeSys_SequenceAddSegment]
    title = "[冲锋系统]向序列添加段"
    description = "向${序列句柄}中追加${段句柄}"
    comment = "段按添加顺序依次执行，最多8段"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = SegHandle
*/
public function SequenceAddSegment takes integer seqHandle, integer segHandle returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount and segHandle > 0 and segHandle <= gSegmentCount then
        call gSeqPool[seqHandle].addSegment(gSegmentPool[segHandle])
    endif
endfunction

/*
    [BossChargeSys_SequenceSetGlobalAura]
    title = "[冲锋系统]设置序列全局光环特效"
    description = "冲锋${序列句柄}全程在Boss身上持续显示特效：模型${模型路径}，挂载于${附着点}"
    comment = "Boss冲锋全程显示的光环特效"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = modelfile
    [[.args]]
    type = string
    default = origin
*/
public function SequenceSetGlobalAura takes integer seqHandle, string modelPath, string attachPoint returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setGlobalAura(BossChargeEffectSpec.createSimple(modelPath, attachPoint))
    endif
endfunction

/*
    [BossChargeSys_SequenceSetGlobalGround]
    title = "[冲锋系统]设置序列全局地面特效"
    description = "冲锋${序列句柄}全程每0.15秒在Boss位置生成特效：模型${模型路径}，挂载于${附着点}"
    comment = "每0.15秒在Boss脚底生成的行走痕迹"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = modelfile
    [[.args]]
    type = string
    default = origin
*/
public function SequenceSetGlobalGround takes integer seqHandle, string modelPath, string attachPoint returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setGlobalGround(BossChargeEffectSpec.createSimple(modelPath, attachPoint))
    endif
endfunction

/*
    [BossChargeSys_SequenceSetTargetPoint]
    title = "[冲锋系统]设置序列固定目标点"
    description = "当${序列句柄}中某段使用*ToPoint变体时，以坐标(${X坐标},${Y坐标})作为目标"
    comment = "供 *ToPoint 类段使用，覆盖执行时的目标单位"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = real
    [[.args]]
    type = real
*/
public function SequenceSetTargetPoint takes integer seqHandle, real x, real y returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setTargetPoint(x, y)
    endif
endfunction

/*
    [BossChargeSys_SequenceSetCenterPoint]
    title = "[冲锋系统]设置序列固定圆心点"
    description = "当${序列句柄}中某段使用*AroundPoint变体时，以坐标(${X坐标},${Y坐标})作为圆心"
    comment = "供 *AroundPoint 类段使用，覆盖执行时的目标单位圆心"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = real
    [[.args]]
    type = real
*/
public function SequenceSetCenterPoint takes integer seqHandle, real x, real y returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setCenterPoint(x, y)
    endif
endfunction

/*
    [BossChargeSys_SequenceSetOnSegDone]
    title = "[冲锋系统]设置序列每段完成回调"
    description = "当${序列句柄}的每一段冲锋结束时触发${回调触发器}"
    comment = "每段结束时触发，可用于在段间插入技能或对话"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = trigger
*/
public function SequenceSetOnSegDone takes integer seqHandle, trigger cb returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setOnSegDoneCallback(cb)
    endif
endfunction

/*
    [BossChargeSys_SequenceSetOnDone]
    title = "[冲锋系统]设置序列完成回调"
    description = "当${序列句柄}的全部冲锋完成（或被强制取消）时触发${回调触发器}"
    comment = "全部段完成或强制取消时触发"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = trigger
*/
public function SequenceSetOnDone takes integer seqHandle, trigger cb returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setOnDoneCallback(cb)
    endif
endfunction

/*
    [BossChargeSys_SequenceSetAutoDestroy]
    title = "[冲锋系统]设置序列自动清理"
    description = "标记${序列句柄}为自动销毁：冲锋完成后自动释放序列及所有段，无需手动调用DestroySequence。清理在onDone回调执行后进行"
    comment = "适用于动态创建的序列，无需单独写清理触发器"
    category = TC_NNCCS
    [[.args]]
    type = Segment
*/
public function SequenceSetAutoDestroy takes integer seqHandle returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount and gSeqPool[seqHandle] != 0 then
        call gSeqPool[seqHandle].setAutoDestroy(true)
    endif
endfunction

// ============================================================
// 执行
// ============================================================

/*
    [BossChargeSys_SequenceExecute]
    title = "[冲锋系统]执行冲锋序列"
    description = "按${序列句柄}配置：${Boss单位}对${目标单位}执行冲锋，优先级${优先级}。高优先级打断低优先级"
    comment = "启动冲锋。优先级：1=低 5=普通 10=高，同优先级不打断"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = unit
    default = GetTriggerUnit
    [[.args]]
    type = unit
    default = GetSpellTargetUnit
    [[.args]]
    type = integer
    default = 5
*/
public function SequenceExecute takes integer seqHandle, unit boss, unit target, integer priority returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].execute(boss, target, priority)
    endif
endfunction

// ============================================================
// Effect 载体冲锋
// ============================================================

/*
    [BossChargeSys_SequenceExecuteEffect]
    title = "[冲锋系统]执行冲锋序列(Effect载体)"
    description = "按${序列句柄}配置：${特效}以${面向单位}朝向为参考，对${目标单位}执行冲锋，优先级${优先级}。Effect不受地形阻挡"
    comment = "Effect冲锋跳过地形检测和死亡检查，适合弹幕/投射物类效果。面向单位仅用于确定初始朝向"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = effect
    [[.args]]
    type = unit
    [[.args]]
    type = unit
    [[.args]]
    type = integer
    default = 5
*/
public function SequenceExecuteEffect takes integer seqHandle, effect eff, unit facingRef, unit target, integer priority returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call BossChargeSystem_BossChargeSequenceExecuteEffect(gSeqPool[seqHandle], eff, GetUnitFacing(facingRef), target, priority)
    endif
endfunction

// ============================================================
// 回调上下文查询（在 onSegDone / onDone 回调中使用）
// ============================================================

/*
    [BossChargeSys_GetCallbackBossUnit]
    title = "[冲锋系统]获取回调中的冲锋单位"
    description = "在段完成回调或序列完成回调中，获取正在冲锋的单位。Effect冲锋时返回空"
    category = TC_NNCCS
    returns = unit
*/
public function GetCallbackBossUnit takes nothing returns unit
    return BossChargeSystem_BossChargeGetCallbackBossUnit()
endfunction

/*
    [BossChargeSys_GetCallbackBossEffect]
    title = "[冲锋系统]获取回调中的冲锋Effect"
    description = "在段完成回调或序列完成回调中，获取正在冲锋的Effect。单位冲锋时返回空"
    category = TC_NNCCS
    returns = effect
*/
public function GetCallbackBossEffect takes nothing returns effect
    return BossChargeSystem_BossChargeGetCallbackBossEffect()
endfunction

/*
    [BossChargeSys_GetCallbackTargetUnit]
    title = "[冲锋系统]获取回调中的目标单位"
    description = "在段完成回调或序列完成回调中，获取本次冲锋的目标单位"
    category = TC_NNCCS
    returns = unit
*/
public function GetCallbackTargetUnit takes nothing returns unit
    return BossChargeSystem_BossChargeGetCallbackTargetUnit()
endfunction

/*
    [BossChargeSys_GetCallbackSegmentIndex]
    title = "[冲锋系统]获取回调中的段序号"
    description = "在段完成回调(onSegDone)中，返回刚完成的是第几段（从1开始）。不在回调中返回-1"
    comment = "仅在 onSegDone 回调中有效，返回1-based段序号"
    category = TC_NNCCS
    returns = integer
*/
public function GetCallbackSegmentIndex takes nothing returns integer
    return BossChargeSystem_BossChargeGetCallbackSegmentIndex()
endfunction

// ============================================================
// 段高度配置
// ============================================================

/*
    [BossChargeSys_SegmentSetHeight]
    title = "[冲锋系统]设置段高度变化"
    description = "为${段句柄}设置高度变化：段结束时达到高度${终点高度}，拱形偏移${偏移量}。起点高度自动继承上一段或单位当前高度"
    comment = "拱形偏移=0为线性升降，>0向上拱(跳跃)，<0向下凹(俯冲)。单位需拥有Amrf技能才能调整高度"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = real
    default = 0.0
*/
public function SegmentSetHeight takes integer segHandle, real endZ, real peakOffset returns nothing
    if segHandle > 0 and segHandle <= gSegmentCount then
        call gSegmentPool[segHandle].setHeight(endZ, peakOffset)
    endif
endfunction

// ============================================================
// 冲锋朝向
// ============================================================

/*
    [BossChargeSys_SequenceSetFacing]
    title = "[冲锋系统]设置序列冲锋朝向"
    description = "当${序列句柄}执行时，开启/关闭${朝向开关}冲锋朝向，Z轴偏移${偏移角度}度。开启后Boss或Effect始终面向移动方向"
    comment = "1=开启 0=关闭。偏移用于调整资产默认朝向(如刀波需转90度)。Effect用EXEffectMatRotateZ，单位用SetUnitFacing"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = integer
    default = 1
    [[.args]]
    type = degree
    default = 0.0
*/
public function SequenceSetFacing takes integer seqHandle, integer enable, real offsetZ returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setFacing(enable != 0, offsetZ)
    endif
endfunction

/*
    [BossChargeSys_SequenceSetFacingAdjust]
    title = "[冲锋系统]设置序列朝向修正"
    description = "为${序列句柄}修正美术资产规格：X轴旋转${仰角}度（平放→竖立），Y轴旋转${翻滚}度（侧翻修正）"
    comment = "仅Effect载体会应用X/Y旋转。单位不受影响。此函数用于处理规格不规范的模型"
    category = TC_NNCCS
    [[.args]]
    type = Segment
    [[.args]]
    type = real
    default = 0.0
    [[.args]]
    type = real
    default = 0.0
*/
public function SequenceSetFacingAdjust takes integer seqHandle, real pitchX, real rollY returns nothing
    if seqHandle > 0 and seqHandle <= gSeqCount then
        call gSeqPool[seqHandle].setFacingAdjust(pitchX, rollY)
    endif
endfunction

// ============================================================
// 资源销毁
// ============================================================

/*
    [BossChargeSys_SegmentSetGhostTrail]
    title = "[冲锋系统]设置段残影拖尾"
    description = "${段句柄}冲锋时每${掉落间隔}秒在路径上生成残影，${淡出时长}秒内从透明度${起始}到${终止}（0全透~255不透明）"
    comment = "残影为Boss同模型马甲，段结束后自然淡出。仅单位冲锋生效"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
    [[.args]]
    type = real
    default = 0.06
    [[.args]]
    type = real
    default = 0.75
    [[.args]]
    type = integer
    default = 77
    [[.args]]
    type = integer
    default = 230
*/
public function SegmentSetGhostTrail takes integer segHandle, real dropInterval, real fadeDuration, integer alphaStart, integer alphaEnd returns nothing
    if segHandle > 0 and segHandle <= gSegmentCount then
        call gSegmentPool[segHandle].setGhostTrail(dropInterval, fadeDuration, alphaStart, alphaEnd)
    endif
endfunction

/*
    [BossChargeSys_DestroySegment]
    title = "[冲锋系统]销毁段句柄"
    description = "释放${段句柄}占用的资源。已加入序列的段会随序列自动清理，仅用于清理孤立段"
    comment = "已加入序列的段会随序列自动清理，无需单独销毁"
    category = TC_NNCCS
    [[.args]]
    type = SegHandle
*/
public function DestroySegment takes integer hnd returns nothing
    if hnd > 0 and hnd <= gSegmentCount and gSegmentPool[hnd] != 0 then
        call gSegmentPool[hnd].destroy()
        if hnd == gSegmentCount then
            set gSegmentPool[hnd] = 0
            set gSegmentCount = gSegmentCount - 1
        else
            set gSegmentPool[hnd] = gSegmentPool[gSegmentCount]
            set gSegmentPool[gSegmentCount] = 0
            set gSegmentCount = gSegmentCount - 1
        endif
    endif
endfunction

endlibrary

#endif //BossChargeSysIncluded
