// Boss冲锋轨迹系统
// 将贝塞尔曲线/极坐标环切/折返等轨迹公式封装为GUI友好参数
// 策划配置语义化参数（弧高/扫描角/半径/缓动），系统自动产出轨迹

#ifndef BossChargeSystemIncluded
#define BossChargeSystemIncluded

#include "japi\\YDWEJapiEffect.j"
#include "japi\\YDWEJapiScript.j"
#include "nncou\\NNCouPoint.j"
#include "nncou\\NNCouMath.j"

library BossChargeSystem initializer Init requires NNCouPoint, NNCouMath

globals
    // ========== 轨迹类型 ==========
    constant integer TRAJ_LINE    = 1   // 直线冲锋
    constant integer TRAJ_ARC     = 2   // 环绕弧线（极坐标）
    constant integer TRAJ_CURVE   = 3   // 贝塞尔弧（弦+法线偏移语义）
    constant integer TRAJ_REBOUND = 4   // 折返冲锋

    // ========== 缓动类型 ==========
    constant integer EASE_LINEAR  = 0   // 匀速 f(u)=u
    constant integer EASE_SMOOTH  = 1   // 平滑 f(u)=u²(3-2u)
    constant integer EASE_IN      = 2   // 渐快 f(u)=u²
    constant integer EASE_OUT     = 3   // 渐慢 f(u)=1-(1-u)²
    constant integer EASE_SHARP   = 4   // 急刹 f(u)=1-(1-u)⁴

    // ========== 目标/圆心类型 ==========
    constant integer TARGET_UNIT    = 1   // 目标单位当前位置
    constant integer TARGET_POINT   = 2   // 指定坐标（执行时通过 setTargetPoint 设置）
    constant integer TARGET_FORWARD = 3   // Boss面朝前方（仅LINE可用）

    constant integer CENTER_TARGET  = 10  // 以目标单位为圆心
    constant integer CENTER_POINT   = 11  // 以指定坐标为圆心
    constant integer CENTER_MID     = 12  // 以Boss→目标中点为圆心

    // ========== 弧方向 ==========
    constant integer ARC_CW          = 1   // 顺时针
    constant integer ARC_CCW         = -1  // 逆时针
    constant integer ARC_LEFT        = 1   // 左弧（CURVE用）
    constant integer ARC_RIGHT       = -1  // 右弧（CURVE用）
    constant integer ARC_RANDOM_ALT  = 2   // 随机左右交替（CURVE用）

    // ========== 冲锋优先级 ==========
    constant integer CHARGE_PRIORITY_LOW    = 1
    constant integer CHARGE_PRIORITY_NORMAL = 5
    constant integer CHARGE_PRIORITY_HIGH   = 10

    // ========== 内部常量 ==========
    private constant real    TIMER_PERIOD     = 0.03    // Timer周期
    private constant integer MAX_SEGMENTS     = 8       // 单序列最多段数

    // ========== Hashtable键 ==========
    private constant integer KEY_CHARGE_RUNTIME = StringHash("BossChargeRT")
    private constant integer KEY_TIMER_RUNTIME  = StringHash("BossChargeTR")
    private constant integer KEY_CALLBACK_CTX  = StringHash("BossChargeCB")

    // ========== 私有全局 ==========
    private hashtable ht = InitHashtable()
    private real gCalcX = 0.
    private real gCalcY = 0.
    private constant integer GHOST_DUMMY_ID = 'ssun'
endglobals

// ============================================================
// 残影马甲 — 编译期 Lua + 库初始化锚点
// ============================================================
<?local slk = require 'slk' ?>
<?
    local obj = slk.unit.ewsp:new 'ssun'
    obj.Name      = "残影马甲[请勿删除]"
    obj.file      = ".mdl"
    obj.abilList  = "Aloc"
    obj.collision = 0.00
    obj.castbsw   = 0.000
    obj.movetp    = ""
    obj.manaN     = 10000
    obj.regenMana = 1000.00
    obj.mana0     = 1000
    obj.HP        = 10000
    obj.regenHP   = 100.00
    obj.regenType = "always"
    obj.fused     = 0
    obj.sight     = 0
    obj.nsight    = 0
    obj.hideOnMinimap = 1
?>
private function Init takes nothing returns nothing
endfunction

// ============================================================
// BossChargeEffectSpec — 特效规格
// 统一描述特效的模型、附着点、偏移、缩放
// ============================================================
struct BossChargeEffectSpec
    string  modelPath
    string  attachPoint
    real    offsetX
    real    offsetY
    real    offsetZ
    real    scale

    static method create takes string path, string attach, real ox, real oy, real oz, real sc returns thistype
        local thistype this = thistype.allocate()
        set this.modelPath   = path
        set this.attachPoint = attach
        set this.offsetX     = ox
        set this.offsetY     = oy
        set this.offsetZ     = oz
        set this.scale       = sc
        return this
    endmethod

    static method createSimple takes string path, string attach returns thistype
        return thistype.create(path, attach, 0., 0., 0., 1.0)
    endmethod

    static method createWorld takes string path, real sc returns thistype
        return thistype.create(path, "", 0., 0., 0., sc)
    endmethod

    method destroy takes nothing returns nothing
        call this.deallocate()
    endmethod
endstruct

// ============================================================
// BossChargeSegment — 单段冲锋配置
// ============================================================
struct BossChargeSegment
    integer trajType
    integer easingType
    real    duration

    // ====== 轨迹参数（语义按 trajType 映射） ======
    // LINE:    param2=distance
    // ARC:     param2=sweepAngle, param3=radius, param4=radiusDelta, param5=direction
    // CURVE:   param2=arcHeight, param3=arcPeakPos, param4=arcAsymmetry, param5=arcDirection
    // REBOUND: param2=overshootRatio, param3=sideAngle, param4=reboundSharpness
    // 注：param1 已废弃，原用于 ARC 圆心类型双重存储，现统一使用 targetType
    integer targetType
    real    param2
    real    param3
    real    param4
    real    param5

    BossChargeEffectSpec effPath
    BossChargeEffectSpec effStart
    BossChargeEffectSpec effEnd
    real                 pathEffectInterval

    // 固定坐标（仅 targetType=TARGET_POINT/CENTER_POINT 时有效）
    real    pointX
    real    pointY

    // 高度（相对地形，fly height）
    boolean hasHeight
    real    heightEnd
    real    heightPeak

    // 残影拖尾（段级配置）
    boolean ghostEnabled
    real    ghostDropInterval
    real    ghostFadeDuration
    integer ghostAlphaStart
    integer ghostAlphaEnd

    static method create takes integer trajType, real duration, integer easing returns thistype
        local thistype this = thistype.allocate()
        set this.trajType   = trajType
        set this.duration   = duration
        set this.easingType = easing
        set this.targetType = TARGET_UNIT
        set this.param2     = 0.
        set this.param3     = 0.
        set this.param4     = 0.
        set this.param5     = 0.
        set this.pointX     = 0.
        set this.pointY     = 0.
        set this.hasHeight  = false
        set this.heightEnd  = 0.
        set this.heightPeak = 0.
        set this.pathEffectInterval = 0.06
        set this.effPath    = 0
        set this.effStart   = 0
        set this.effEnd     = 0
        set this.ghostEnabled      = false
        set this.ghostDropInterval = 0.06
        set this.ghostFadeDuration = 0.75
        set this.ghostAlphaStart   = 77
        set this.ghostAlphaEnd     = 230
        return this
    endmethod

    method setLineParams takes integer targetType, real distance returns thistype
        set this.targetType = targetType
        set this.param2     = distance
        return this
    endmethod

    method setArcParams takes integer centerType, real sweepAngle, real radius, real radiusDelta, integer direction returns thistype
        set this.targetType = centerType
        set this.param2     = sweepAngle
        set this.param3     = radius
        set this.param4     = radiusDelta
        set this.param5     = I2R(direction)
        return this
    endmethod

    method setCurveParams takes integer targetType, real arcHeight, real arcPeakPos, real arcAsymmetry, integer arcDirection returns thistype
        set this.targetType = targetType
        set this.param2     = arcHeight
        set this.param3     = arcPeakPos
        set this.param4     = arcAsymmetry
        set this.param5     = I2R(arcDirection)
        return this
    endmethod

    method setReboundParams takes integer targetType, real overshootRatio, real sideAngle, real reboundSharpness returns thistype
        set this.targetType = targetType
        set this.param2     = overshootRatio
        set this.param3     = sideAngle
        set this.param4     = reboundSharpness
        return this
    endmethod

    method setGhostTrail takes real dropInterval, real fadeDuration, integer alphaStart, integer alphaEnd returns thistype
        set this.ghostEnabled      = true
        set this.ghostDropInterval = dropInterval
        set this.ghostFadeDuration = fadeDuration
        set this.ghostAlphaStart   = alphaStart
        set this.ghostAlphaEnd     = alphaEnd
        return this
    endmethod

    method setPathEffect takes BossChargeEffectSpec spec, real interval returns thistype
        set this.effPath    = spec
        set this.pathEffectInterval = interval
        return this
    endmethod

    method setStartEffect takes BossChargeEffectSpec spec returns thistype
        set this.effStart = spec
        return this
    endmethod

    method setEndEffect takes BossChargeEffectSpec spec returns thistype
        set this.effEnd = spec
        return this
    endmethod

    method setHeight takes real endZ, real peakOffset returns thistype
        set this.hasHeight  = true
        set this.heightEnd  = endZ
        set this.heightPeak = peakOffset
        return this
    endmethod

    method destroy takes nothing returns nothing
        if this.effPath != 0 then
            call this.effPath.destroy()
        endif
        if this.effStart != 0 then
            call this.effStart.destroy()
        endif
        if this.effEnd != 0 then
            call this.effEnd.destroy()
        endif
        call this.deallocate()
    endmethod
endstruct

// ====== 内部：冲锋启动校验（段数 + 优先级检查） ======
private function ValidateChargeLaunch takes BossChargeSequence seq, integer handleId, integer priority returns boolean
    local BossChargeRuntime oldRt
    if seq.segCount <= 0 then
        debug call BJDebugMsg("|cffff0000[冲锋系统]|r 序列没有配置任何段")
        return false
    endif
    if HaveSavedInteger(ht, handleId, KEY_CHARGE_RUNTIME) then
        set oldRt = LoadInteger(ht, handleId, KEY_CHARGE_RUNTIME)
        if oldRt != 0 then
            if oldRt.priority >= priority then
                debug call BJDebugMsg("|cffffcc00[冲锋系统]|r 被高优先级冲锋阻挡 (旧:" + I2S(oldRt.priority) + " ≥ 新:" + I2S(priority) + ")")
                return false
            endif
            call oldRt.finalize()
        endif
    endif
    return true
endfunction

// ============================================================
// BossChargeSequence — 完整冲锋序列
// ============================================================
struct BossChargeSequence
    BossChargeSegment array segments[MAX_SEGMENTS]
    integer segCount

    BossChargeEffectSpec globalAura
    BossChargeEffectSpec globalGround

    real    targetPointX
    real    targetPointY
    boolean hasTargetPoint
    real    centerPointX
    real    centerPointY
    boolean hasCenterPoint

    trigger onSegDoneCallback
    trigger onDoneCallback

    boolean autoDestroy           // 执行完成后自动清理
    boolean pendingCleanup        // 已执行完回调，等待下一次 Create 时扫池销毁

    // 冲锋朝向
    boolean facingEnabled
    real    facingOffsetZ
    real    facingPitchX
    real    facingRollY

    static method create takes nothing returns thistype
        local thistype this = thistype.allocate()
        set this.segCount       = 0
        set this.globalAura     = 0
        set this.globalGround   = 0
        set this.hasTargetPoint = false
        set this.hasCenterPoint = false
        set this.onSegDoneCallback = null
        set this.onDoneCallback   = null
        set this.autoDestroy    = false
        set this.pendingCleanup = false
        set this.facingEnabled  = false
        set this.facingOffsetZ  = 0.
        set this.facingPitchX   = 0.
        set this.facingRollY    = 0.
        return this
    endmethod

    method addSegment takes BossChargeSegment seg returns thistype
        if this.segCount < MAX_SEGMENTS then
            set this.segments[this.segCount] = seg
            set this.segCount = this.segCount + 1
        else
            debug call BJDebugMsg("|cffff0000[冲锋系统]|r 序列段数已满 (最大:" + I2S(MAX_SEGMENTS) + ")，第" + I2S(this.segCount + 1) + "段被忽略")
        endif
        return this
    endmethod

    method setGlobalAura takes BossChargeEffectSpec spec returns thistype
        set this.globalAura = spec
        return this
    endmethod

    method setGlobalGround takes BossChargeEffectSpec spec returns thistype
        set this.globalGround = spec
        return this
    endmethod

    method setTargetPoint takes real x, real y returns thistype
        set this.targetPointX  = x
        set this.targetPointY  = y
        set this.hasTargetPoint = true
        return this
    endmethod

    method setCenterPoint takes real x, real y returns thistype
        set this.centerPointX  = x
        set this.centerPointY  = y
        set this.hasCenterPoint = true
        return this
    endmethod

    method setOnSegDoneCallback takes trigger cb returns thistype
        set this.onSegDoneCallback = cb
        return this
    endmethod

    method setOnDoneCallback takes trigger cb returns thistype
        set this.onDoneCallback = cb
        return this
    endmethod

    method setFacing takes boolean enable, real offsetZ returns thistype
        set this.facingEnabled = enable
        set this.facingOffsetZ = offsetZ
        return this
    endmethod

    method setFacingAdjust takes real pitchX, real rollY returns thistype
        set this.facingPitchX = pitchX
        set this.facingRollY  = rollY
        return this
    endmethod

    method setAutoDestroy takes boolean enable returns thistype
        set this.autoDestroy = enable
        return this
    endmethod

    method execute takes unit boss, unit target, integer priority returns nothing
        local BossChargeRuntime newRt
        if not ValidateChargeLaunch(this, GetHandleId(boss), priority) then
            return
        endif
        set newRt = BossChargeRuntime.create(this, boss, target, priority)
        call newRt.launch()
    endmethod

    method destroy takes nothing returns nothing
        local integer i = 0
        loop
            exitwhen i >= this.segCount
            if this.segments[i] != 0 then
                call this.segments[i].destroy()
            endif
            set i = i + 1
        endloop
        if this.globalAura != 0 then
            call this.globalAura.destroy()
        endif
        if this.globalGround != 0 then
            call this.globalGround.destroy()
        endif
        call this.deallocate()
    endmethod
endstruct

// ============================================================
// BossChargeRuntime — 运行时状态（绑定Timer）
// ============================================================
struct BossChargeRuntime
    readonly BossChargeSequence seq
    readonly unit    boss
    readonly unit    target
    readonly integer priority
    private  integer currentSeg
    private  real    elapsed
    private  real    startX
    private  real    startY
    private  real    lastX
    private  real    lastY
    private  real    pathEffectTimer
    private  timer   tmr
    private  effect  auraEffect
    private  effect  groundEffect
    private  real    groundTimer
    private  effect  pathTrailEffect   // 路径拖尾特效（下次生成前销毁）

    // effect 载体支持
    private  boolean isEffectCharge
    private  effect  chargeEff
    private  real    effectFacing

    // 高度（fly height）
    private  real    currentZ

    // 缓存：ARC_RANDOM_ALT 段开始时的随机方向
    private  integer cachedCurveDir

    // 残影池
    private  unit    array ghosts[80]
    private  real    array ghostAge[80]
    private  real    array ghostFadeDuration[80]
    private  integer array ghostAlphaStart[80]
    private  integer array ghostAlphaEnd[80]
    private  integer ghostCount
    private  real    ghostDropTimer
    private  boolean chargeDone

    static method create takes BossChargeSequence seq, unit boss, unit target, integer priority returns thistype
        local thistype this = thistype.allocate()
        set this.seq      = seq
        set this.boss     = boss
        set this.target   = target
        set this.priority = priority
        set this.currentSeg = 0
        set this.elapsed   = 0.
        set this.startX    = GetUnitX(boss)
        set this.startY    = GetUnitY(boss)
        set this.lastX     = this.startX
        set this.lastY     = this.startY
        set this.pathEffectTimer = 0.
        set this.groundTimer    = 0.
        set this.tmr       = CreateTimer()
        set this.auraEffect  = null
        set this.groundEffect = null
        set this.pathTrailEffect = null
        set this.isEffectCharge = false
        set this.chargeEff   = null
        set this.effectFacing = 0.
        set this.currentZ    = GetUnitFlyHeight(boss)
        set this.cachedCurveDir = 0
        set this.ghostCount     = 0
        set this.ghostDropTimer = 0.
        set this.chargeDone     = false
        return this
    endmethod

    static method createEffect takes BossChargeSequence seq, effect eff, real facing, unit target, integer priority returns thistype
        local thistype this = thistype.allocate()
        set this.seq      = seq
        set this.boss     = null
        set this.target   = target
        set this.priority = priority
        set this.currentSeg = 0
        set this.elapsed   = 0.
        set this.startX    = EXGetEffectX(eff)
        set this.startY    = EXGetEffectY(eff)
        set this.lastX     = this.startX
        set this.lastY     = this.startY
        set this.pathEffectTimer = 0.
        set this.groundTimer    = 0.
        set this.tmr       = CreateTimer()
        set this.auraEffect  = null
        set this.groundEffect = null
        set this.pathTrailEffect = null
        set this.isEffectCharge = true
        set this.chargeEff   = eff
        set this.effectFacing = facing
        set this.currentZ    = 0.
        set this.cachedCurveDir = 0
        set this.ghostCount     = 0
        set this.ghostDropTimer = 0.
        set this.chargeDone     = false
        return this
    endmethod

    // ================================================================
    // 缓动函数
    // ================================================================
    private static method applyEasing takes real u, integer easingType returns real
        local real t
        if easingType == EASE_LINEAR then
            return u
        elseif easingType == EASE_SMOOTH then
            return u * u * (3.0 - 2.0 * u)
        elseif easingType == EASE_IN then
            return u * u
        elseif easingType == EASE_OUT then
            set t = 1.0 - u
            return 1.0 - t * t
        elseif easingType == EASE_SHARP then
            set t = 1.0 - u
            return 1.0 - t * t * t * t
        endif
        return u
    endmethod

    // ================================================================
    // 残影
    // ================================================================
    private method spawnGhost takes nothing returns nothing
        local unit g
        local string modelPath
        local BossChargeSegment curSeg
        if this.ghostCount >= 80 or this.isEffectCharge then
            return
        endif
        set curSeg = this.seq.segments[this.currentSeg]
        if curSeg == 0 or not curSeg.ghostEnabled then
            return
        endif
        set g = CreateUnit(GetOwningPlayer(this.boss), GHOST_DUMMY_ID, GetUnitX(this.boss), GetUnitY(this.boss), GetUnitFacing(this.boss))
        set modelPath = YDWEGetObjectPropertyString(YDWE_OBJECT_TYPE_UNIT, GetUnitTypeId(this.boss), "file")
        if modelPath != null and modelPath != "" then
            call DzSetUnitModel(g, modelPath)
        endif
        call SetUnitVertexColor(g, 255, 255, 255, curSeg.ghostAlphaStart)
        call PauseUnit(g, true)
        set this.ghosts[this.ghostCount]          = g
        set this.ghostAge[this.ghostCount]        = 0.
        set this.ghostFadeDuration[this.ghostCount] = curSeg.ghostFadeDuration
        set this.ghostAlphaStart[this.ghostCount] = curSeg.ghostAlphaStart
        set this.ghostAlphaEnd[this.ghostCount]   = curSeg.ghostAlphaEnd
        set this.ghostCount = this.ghostCount + 1
        set g = null
    endmethod

    private method updateGhosts takes nothing returns nothing
        local integer i = 0
        local integer alpha
        loop
            exitwhen i >= this.ghostCount
            set this.ghostAge[i] = this.ghostAge[i] + TIMER_PERIOD
            if this.ghostAge[i] >= this.ghostFadeDuration[i] then
                call RemoveUnit(this.ghosts[i])
                set this.ghosts[i]          = this.ghosts[this.ghostCount - 1]
                set this.ghostAge[i]        = this.ghostAge[this.ghostCount - 1]
                set this.ghostFadeDuration[i] = this.ghostFadeDuration[this.ghostCount - 1]
                set this.ghostAlphaStart[i] = this.ghostAlphaStart[this.ghostCount - 1]
                set this.ghostAlphaEnd[i]   = this.ghostAlphaEnd[this.ghostCount - 1]
                set this.ghostCount = this.ghostCount - 1
                set i = i - 1
            else
                set alpha = this.ghostAlphaStart[i] + R2I((this.ghostAlphaEnd[i] - this.ghostAlphaStart[i]) * (this.ghostAge[i] / this.ghostFadeDuration[i]))
                call SetUnitVertexColor(this.ghosts[i], 255, 255, 255, alpha)
            endif
            set i = i + 1
        endloop
    endmethod

    // 根据 targetType/centerType 解析世界坐标
    // 段级坐标优先，未设置时回退到序列级坐标（策划统一配置）
    private method resolveTarget takes integer ttype, BossChargeSegment seg returns nothing
        if ttype == TARGET_UNIT or ttype == CENTER_TARGET then
            set gCalcX = GetUnitX(this.target)
            set gCalcY = GetUnitY(this.target)
        elseif ttype == TARGET_POINT then
            if seg.pointX != 0. or seg.pointY != 0. then
                set gCalcX = seg.pointX
                set gCalcY = seg.pointY
            elseif this.seq.hasTargetPoint then
                set gCalcX = this.seq.targetPointX
                set gCalcY = this.seq.targetPointY
            else
                set gCalcX = 0.
                set gCalcY = 0.
            endif
        elseif ttype == CENTER_POINT then
            if seg.pointX != 0. or seg.pointY != 0. then
                set gCalcX = seg.pointX
                set gCalcY = seg.pointY
            elseif this.seq.hasCenterPoint then
                set gCalcX = this.seq.centerPointX
                set gCalcY = this.seq.centerPointY
            else
                set gCalcX = 0.
                set gCalcY = 0.
            endif
        elseif ttype == CENTER_MID then
            set gCalcX = (this.startX + GetUnitX(this.target)) / 2.0
            set gCalcY = (this.startY + GetUnitY(this.target)) / 2.0
        endif
    endmethod

    // 局部偏移旋转到世界坐标
    private method rotateOffset takes real ox, real oy returns nothing
        local real facing
        local real cosF
        local real sinF
        if this.isEffectCharge then
            set facing = this.effectFacing * bj_DEGTORAD
        else
            set facing = GetUnitFacing(this.boss) * bj_DEGTORAD
        endif
        set cosF = Cos(facing)
        set sinF = Sin(facing)
        set gCalcX = gCalcX + ox * cosF - oy * sinF
        set gCalcY = gCalcY + ox * sinF + oy * cosF
    endmethod

    // 在世界坐标生成特效
    private method spawnWorldEffect takes BossChargeEffectSpec spec, real x, real y returns effect
        local effect e = null
        if spec == 0 then
            return null
        endif
        set gCalcX = x
        set gCalcY = y
        if spec.offsetX != 0. or spec.offsetY != 0. then
            call this.rotateOffset(spec.offsetX, spec.offsetY)
        endif
        set e = AddSpecialEffect(spec.modelPath, gCalcX, gCalcY)
        if e != null then
            if spec.offsetZ != 0. then
                call EXSetEffectZ(e, spec.offsetZ + NNCGetZByXY(gCalcX, gCalcY))
            endif
            if spec.scale != 1.0 then
                call EXSetEffectSize(e, spec.scale)
            endif
        endif
        return e
    endmethod

    // 在Boss身上挂载特效（附着点+XYZ偏移）
    // 优先：有XY偏移→世界坐标创建；仅有附着点且非Effect→AddSpecialEffectTarget；否则→脚底
    private method spawnAttachedEffect takes BossChargeEffectSpec spec returns effect
        local real bx
        local real by
        if spec == 0 then
            return null
        endif
        if this.isEffectCharge then
            set bx = EXGetEffectX(this.chargeEff)
            set by = EXGetEffectY(this.chargeEff)
        else
            set bx = GetUnitX(this.boss)
            set by = GetUnitY(this.boss)
        endif
        if spec.offsetX != 0. or spec.offsetY != 0. then
            set gCalcX = bx
            set gCalcY = by
            call this.rotateOffset(spec.offsetX, spec.offsetY)
            return AddSpecialEffect(spec.modelPath, gCalcX, gCalcY)
        endif
        if StringLength(spec.attachPoint) > 0 then
            if not this.isEffectCharge then
                return AddSpecialEffectTarget(spec.modelPath, this.boss, spec.attachPoint)
            endif
        endif
        return AddSpecialEffect(spec.modelPath, bx, by)
    endmethod

    // ================================================================
    // 位置计算
    // ================================================================

    private method computeLine takes BossChargeSegment seg, real u returns nothing
        local real tx
        local real ty
        local real dir
        local real dist
        call this.resolveTarget(seg.targetType, seg)
        set tx = gCalcX
        set ty = gCalcY
        if seg.targetType == TARGET_FORWARD then
            if this.isEffectCharge then
                set dir = this.effectFacing
            else
                set dir = GetUnitFacing(this.boss)
            endif
            set dist = seg.param2
            set gCalcX = this.startX + dist * CosBJ(dir) * u
            set gCalcY = this.startY + dist * SinBJ(dir) * u
        else
            set gCalcX = this.startX + (tx - this.startX) * u
            set gCalcY = this.startY + (ty - this.startY) * u
        endif
    endmethod

    private method computeArc takes BossChargeSegment seg, real u returns nothing
        local real cx
        local real cy
        local real sweepAngle  = seg.param2
        local real radius      = seg.param3
        local real radiusDelta = seg.param4
        local integer direction = R2I(seg.param5)
        local real theta0
        local real theta
        local real r
        if direction == ARC_RANDOM_ALT then
            set direction = this.cachedCurveDir
        endif
        call this.resolveTarget(seg.targetType, seg)
        set cx = gCalcX
        set cy = gCalcY
        set theta0 = Atan2(this.startY - cy, this.startX - cx) * bj_RADTODEG
        set theta  = theta0 + I2R(direction) * sweepAngle * u
        set r      = radius + radiusDelta * u
        set gCalcX = cx + r * CosBJ(theta)
        set gCalcY = cy + r * SinBJ(theta)
    endmethod

    private method computeCurve takes BossChargeSegment seg, real u returns nothing
        local real tx
        local real ty
        local real cx
        local real cy
        local real chordLen
        local real nx
        local real ny
        local real arcHeight    = seg.param2
        local real arcPeakPos   = seg.param3
        local real arcAsymmetry = seg.param4
        local integer arcDir    = R2I(seg.param5)
        local integer dirSign
        local real h1
        local real h2
        local real p1x
        local real p1y
        local real p2x
        local real p2y
        call this.resolveTarget(seg.targetType, seg)
        set tx = gCalcX
        set ty = gCalcY
        set cx = tx - this.startX
        set cy = ty - this.startY
        set chordLen = SquareRoot(cx * cx + cy * cy)
        if chordLen < 1.0 then
            set gCalcX = this.startX
            set gCalcY = this.startY
            return
        endif
        set nx = -cy / chordLen
        set ny =  cx / chordLen
        if arcDir == ARC_RANDOM_ALT then
            set dirSign = this.cachedCurveDir
        else
            set dirSign = arcDir
        endif
        set h1 = arcHeight * (1.0 - arcAsymmetry) * (1.0 - arcPeakPos) * I2R(dirSign)
        set h2 = arcHeight * (1.0 + arcAsymmetry) * arcPeakPos        * I2R(dirSign)
        set p1x = this.startX + cx * 0.3 + nx * h1
        set p1y = this.startY + cy * 0.3 + ny * h1
        set p2x = this.startX + cx * 0.7 + nx * h2
        set p2y = this.startY + cy * 0.7 + ny * h2
        set gCalcX = NNCBezierCubic(u, this.startX, p1x, p2x, tx)
        set gCalcY = NNCBezierCubic(u, this.startY, p1y, p2y, ty)
    endmethod

    private method computeRebound takes BossChargeSegment seg, real u returns nothing
        local real tx
        local real ty
        local real cx
        local real cy
        local real chordLen
        local real overshootRatio = seg.param2
        local real sideAngle      = seg.param3
        local real sharpness      = seg.param4
        local real overshootDist
        local real nx
        local real ny
        local real h
        local real progress
        call this.resolveTarget(seg.targetType, seg)
        set tx = gCalcX
        set ty = gCalcY
        set cx = tx - this.startX
        set cy = ty - this.startY
        set chordLen = SquareRoot(cx * cx + cy * cy)
        if chordLen < 1.0 then
            set gCalcX = this.startX
            set gCalcY = this.startY
            return
        endif
        set overshootDist = chordLen * (overshootRatio - 1.0)
        set nx = -(cy * CosBJ(sideAngle) + cx * SinBJ(sideAngle)) / chordLen
        set ny =  (cx * CosBJ(sideAngle) - cy * SinBJ(sideAngle)) / chordLen
        set h = overshootDist * Sin(u * bj_PI) * Pow(u * (1.0 - u), sharpness)
        set progress = u + h / chordLen
        set gCalcX = this.startX + cx * progress + nx * h
        set gCalcY = this.startY + cy * progress + ny * h
    endmethod

    private method computePosition takes BossChargeSegment seg, real u returns nothing
        if seg.trajType == TRAJ_LINE then
            call this.computeLine(seg, u)
        elseif seg.trajType == TRAJ_ARC then
            call this.computeArc(seg, u)
        elseif seg.trajType == TRAJ_CURVE then
            call this.computeCurve(seg, u)
        elseif seg.trajType == TRAJ_REBOUND then
            call this.computeRebound(seg, u)
        endif
    endmethod

    // ================================================================
    // 段切换
    // ================================================================

    // 将载体(boss/effect)和目标信息保存到 hashtable 上下文，执行回调，然后清理
    private method fireContextCallback takes trigger cb returns nothing
        if this.isEffectCharge then
            call SaveEffectHandle(ht, KEY_CALLBACK_CTX, 0, this.chargeEff)
            call SaveUnitHandle(ht, KEY_CALLBACK_CTX, 1, null)
        else
            call SaveUnitHandle(ht, KEY_CALLBACK_CTX, 0, this.boss)
            call SaveEffectHandle(ht, KEY_CALLBACK_CTX, 1, null)
        endif
        call SaveUnitHandle(ht, KEY_CALLBACK_CTX, 2, this.target)
        call SaveBoolean(ht, KEY_CALLBACK_CTX, 3, this.isEffectCharge)
        call TriggerExecute(cb)
        call RemoveSavedHandle(ht, KEY_CALLBACK_CTX, 0)
        call RemoveSavedHandle(ht, KEY_CALLBACK_CTX, 1)
        call RemoveSavedHandle(ht, KEY_CALLBACK_CTX, 2)
        call RemoveSavedInteger(ht, KEY_CALLBACK_CTX, 3)
    endmethod

    private method advanceSegment takes nothing returns boolean
        local BossChargeSegment oldSeg = this.seq.segments[this.currentSeg]
        local BossChargeSegment newSeg
        if oldSeg.effEnd != 0 then
            if this.isEffectCharge then
                call this.spawnWorldEffect(oldSeg.effEnd, EXGetEffectX(this.chargeEff), EXGetEffectY(this.chargeEff))
            else
                call this.spawnWorldEffect(oldSeg.effEnd, GetUnitX(this.boss), GetUnitY(this.boss))
            endif
        endif
        if this.seq.onSegDoneCallback != null then
            call SaveInteger(ht, KEY_CALLBACK_CTX, 4, this.currentSeg + 1)
            call this.fireContextCallback(this.seq.onSegDoneCallback)
            call RemoveSavedInteger(ht, KEY_CALLBACK_CTX, 4)
        endif
        set this.currentSeg = this.currentSeg + 1
        if this.currentSeg >= this.seq.segCount then
            return false
        endif
        if oldSeg.hasHeight then
            set this.currentZ = oldSeg.heightEnd
        endif
        set this.elapsed = 0.
        if this.isEffectCharge then
            set this.startX  = EXGetEffectX(this.chargeEff)
            set this.startY  = EXGetEffectY(this.chargeEff)
        else
            set this.startX  = GetUnitX(this.boss)
            set this.startY  = GetUnitY(this.boss)
        endif
        set this.lastX   = this.startX
        set this.lastY   = this.startY
        set this.pathEffectTimer = 0.
        set this.ghostDropTimer  = 0.
        set newSeg = this.seq.segments[this.currentSeg]
        if (newSeg.trajType == TRAJ_CURVE or newSeg.trajType == TRAJ_ARC) and R2I(newSeg.param5) == ARC_RANDOM_ALT then
            if GetRandomInt(0, 1) == 0 then
                set this.cachedCurveDir = 1
            else
                set this.cachedCurveDir = -1
            endif
        endif
        if newSeg.effStart != 0 then
            call this.spawnAttachedEffect(newSeg.effStart)
        endif
        return true
    endmethod

    // ================================================================
    // Timer回调
    // ================================================================
    private static method onTimerTick takes nothing returns nothing
        local timer t = GetExpiredTimer()
        local integer tid = GetHandleId(t)
        local thistype this = LoadInteger(ht, tid, KEY_TIMER_RUNTIME)
        local BossChargeSegment seg
        local real s
        local real u
        local real newX
        local real newY
        if this == 0 then
            call PauseTimer(t)
            call DestroyTimer(t)
            set t = null
            return
        endif
        if not this.isEffectCharge then
            if IsUnitType(this.boss, UNIT_TYPE_DEAD) then
                call this.finalize()
                set t = null
                return
            endif
        endif
        set seg = this.seq.segments[this.currentSeg]
        if seg == 0 then
            call this.finalize()
            set t = null
            return
        endif
        if this.chargeDone then
            call this.updateGhosts()
            if this.ghostCount == 0 then
                call this.finalize()
            endif
            set t = null
            return
        endif
        set this.elapsed = this.elapsed + TIMER_PERIOD
        if this.elapsed >= seg.duration then
            if not this.advanceSegment() then
                if this.ghostCount > 0 then
                    set this.chargeDone = true
                else
                    call this.finalize()
                endif
                set t = null
                return
            endif
            set seg = this.seq.segments[this.currentSeg]
            if seg == 0 then
                call this.finalize()
                set t = null
                return
            endif
        endif
        if seg.duration > 0. then
            set s = this.elapsed / seg.duration
        else
            set s = 1.0
        endif
        set u = thistype.applyEasing(s, seg.easingType)
        call this.computePosition(seg, u)
        set newX = gCalcX
        set newY = gCalcY
        set this.pathEffectTimer = this.pathEffectTimer + TIMER_PERIOD
        if seg.effPath != 0 and this.pathEffectTimer >= seg.pathEffectInterval then
            if this.pathTrailEffect != null then
                call DestroyEffect(this.pathTrailEffect)
            endif
            set this.pathTrailEffect = this.spawnWorldEffect(seg.effPath, newX, newY)
            set this.pathEffectTimer = 0.
        endif
        if this.seq.globalGround != 0 then
            set this.groundTimer = this.groundTimer + TIMER_PERIOD
            if this.groundTimer >= 0.15 then
                if this.groundEffect != null then
                    call DestroyEffect(this.groundEffect)
                endif
                set this.groundEffect = this.spawnWorldEffect(this.seq.globalGround, newX, newY)
                set this.groundTimer = 0.
            endif
        endif
        if this.isEffectCharge then
            call EXSetEffectXY(this.chargeEff, newX, newY)
            set this.effectFacing = Atan2(newY - this.lastY, newX - this.lastX) * bj_RADTODEG
        else
            if NNCIsWalkAble(newX, newY) then
                call SetUnitX(this.boss, newX)
                call SetUnitY(this.boss, newY)
            endif
        endif
        if seg.hasHeight then
            set s = this.currentZ + (seg.heightEnd - this.currentZ) * u + seg.heightPeak * 4. * u * (1. - u)
            if this.isEffectCharge then
                call EXSetEffectZ(this.chargeEff, NNCGetZByXY(newX, newY) + s)
            else
                call SetUnitFlyHeight(this.boss, s, 0.)
            endif
        endif
        if this.seq.facingEnabled and (newX != this.lastX or newY != this.lastY) then
            set s = Atan2(newY - this.lastY, newX - this.lastX) * bj_RADTODEG + this.seq.facingOffsetZ
            if this.isEffectCharge then
                call EXEffectMatRotateZ(this.chargeEff, s)
                if this.seq.facingPitchX != 0. then
                    call EXEffectMatRotateX(this.chargeEff, this.seq.facingPitchX)
                endif
                if this.seq.facingRollY != 0. then
                    call EXEffectMatRotateY(this.chargeEff, this.seq.facingRollY)
                endif
            else
                call SetUnitFacing(this.boss, s)
            endif
        endif
        // 残影生成 + 更新
        if seg.ghostEnabled and not this.chargeDone then
            set this.ghostDropTimer = this.ghostDropTimer + TIMER_PERIOD
            if this.ghostDropTimer >= seg.ghostDropInterval then
                call this.spawnGhost()
                set this.ghostDropTimer = this.ghostDropTimer - seg.ghostDropInterval
            endif
        endif
        call this.updateGhosts()
        set this.lastX = newX
        set this.lastY = newY
        set t = null
    endmethod

    // ================================================================
    // 启动 & 清理
    // ================================================================
    method launch takes nothing returns nothing
        local integer tid = GetHandleId(this.tmr)
        local BossChargeSegment firstSeg
        if this.isEffectCharge then
            call SaveInteger(ht, GetHandleId(this.chargeEff), KEY_CHARGE_RUNTIME, this)
        else
            call SaveInteger(ht, GetHandleId(this.boss), KEY_CHARGE_RUNTIME, this)
        endif
        call SaveInteger(ht, tid, KEY_TIMER_RUNTIME, this)
        if this.seq.globalAura != 0 then
            set this.auraEffect = this.spawnAttachedEffect(this.seq.globalAura)
        endif
        set firstSeg = this.seq.segments[0]
        if firstSeg != 0 and (firstSeg.trajType == TRAJ_CURVE or firstSeg.trajType == TRAJ_ARC) and R2I(firstSeg.param5) == ARC_RANDOM_ALT then
            if GetRandomInt(0, 1) == 0 then
                set this.cachedCurveDir = 1
            else
                set this.cachedCurveDir = -1
            endif
        endif
        if firstSeg != 0 and firstSeg.effStart != 0 then
            call this.spawnAttachedEffect(firstSeg.effStart)
        endif
        call TimerStart(this.tmr, TIMER_PERIOD, true, function thistype.onTimerTick)
    endmethod

    method finalize takes nothing returns nothing
        local integer unitId
        local BossChargeSegment lastSeg
        if this.currentSeg < this.seq.segCount then
            set lastSeg = this.seq.segments[this.currentSeg]
            if lastSeg != 0 and lastSeg.effEnd != 0 then
                if this.isEffectCharge then
                    call this.spawnWorldEffect(lastSeg.effEnd, EXGetEffectX(this.chargeEff), EXGetEffectY(this.chargeEff))
                else
                    call this.spawnWorldEffect(lastSeg.effEnd, GetUnitX(this.boss), GetUnitY(this.boss))
                endif
            endif
        endif
        if this.auraEffect != null then
            call DestroyEffect(this.auraEffect)
        endif
        if this.groundEffect != null then
            call DestroyEffect(this.groundEffect)
        endif
        if this.pathTrailEffect != null then
            call DestroyEffect(this.pathTrailEffect)
        endif
        if this.seq.onDoneCallback != null then
            call this.fireContextCallback(this.seq.onDoneCallback)
        endif
        if this.seq.autoDestroy then
            set this.seq.pendingCleanup = true
        endif
        // 清理所有存活的残影
        loop
            exitwhen this.ghostCount <= 0
            set this.ghostCount = this.ghostCount - 1
            call RemoveUnit(this.ghosts[this.ghostCount])
        endloop
        if this.isEffectCharge then
            set unitId = GetHandleId(this.chargeEff)
        else
            set unitId = GetHandleId(this.boss)
        endif
        call RemoveSavedInteger(ht, unitId, KEY_CHARGE_RUNTIME)
        call RemoveSavedInteger(ht, GetHandleId(this.tmr), KEY_TIMER_RUNTIME)
        call PauseTimer(this.tmr)
        call DestroyTimer(this.tmr)
        set this.tmr = null
        call this.destroy()
    endmethod

    method destroy takes nothing returns nothing
        set this.boss   = null
        set this.target = null
        set this.seq    = 0
        call this.deallocate()
    endmethod
endstruct

// ============================================================
// 公开API（GUI可调用）
// ============================================================
public function BossChargeCancel takes unit boss returns nothing
    local integer unitId = GetHandleId(boss)
    local BossChargeRuntime rt
    if HaveSavedInteger(ht, unitId, KEY_CHARGE_RUNTIME) then
        set rt = LoadInteger(ht, unitId, KEY_CHARGE_RUNTIME)
        if rt != 0 then
            call rt.finalize()
        endif
    endif
endfunction

public function BossChargeIsCharging takes unit boss returns boolean
    return HaveSavedInteger(ht, GetHandleId(boss), KEY_CHARGE_RUNTIME)
endfunction

public function BossChargeGetPriority takes unit boss returns integer
    local integer unitId = GetHandleId(boss)
    local BossChargeRuntime rt
    if HaveSavedInteger(ht, unitId, KEY_CHARGE_RUNTIME) then
        set rt = LoadInteger(ht, unitId, KEY_CHARGE_RUNTIME)
        if rt != 0 then
            return rt.priority
        endif
    endif
    return -1
endfunction

// ============================================================
// Effect 载体冲锋 & 回调上下文
// ============================================================
public function BossChargeSequenceExecuteEffect takes BossChargeSequence seq, effect eff, real facing, unit target, integer priority returns nothing
    local BossChargeRuntime newRt
    if not ValidateChargeLaunch(seq, GetHandleId(eff), priority) then
        return
    endif
    set newRt = BossChargeRuntime.createEffect(seq, eff, facing, target, priority)
    call newRt.launch()
endfunction

public function BossChargeGetCallbackBossUnit takes nothing returns unit
    if not HaveSavedHandle(ht, KEY_CALLBACK_CTX, 0) then
        return null
    endif
    if LoadBoolean(ht, KEY_CALLBACK_CTX, 3) then
        return null
    endif
    return LoadUnitHandle(ht, KEY_CALLBACK_CTX, 0)
endfunction

public function BossChargeGetCallbackBossEffect takes nothing returns effect
    if not HaveSavedHandle(ht, KEY_CALLBACK_CTX, 0) then
        return null
    endif
    if not LoadBoolean(ht, KEY_CALLBACK_CTX, 3) then
        return null
    endif
    return LoadEffectHandle(ht, KEY_CALLBACK_CTX, 0)
endfunction

public function BossChargeGetCallbackTargetUnit takes nothing returns unit
    if not HaveSavedHandle(ht, KEY_CALLBACK_CTX, 0) then
        return null
    endif
    return LoadUnitHandle(ht, KEY_CALLBACK_CTX, 2)
endfunction

public function BossChargeGetCallbackSegmentIndex takes nothing returns integer
    if HaveSavedInteger(ht, KEY_CALLBACK_CTX, 4) then
        return LoadInteger(ht, KEY_CALLBACK_CTX, 4)
    endif
    return -1
endfunction

endlibrary

#endif //BossChargeSystemIncluded
