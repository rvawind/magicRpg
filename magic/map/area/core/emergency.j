#ifndef AREA_EMERGENCY
#define AREA_EMERGENCY
#include "nncou\\debug.j"
/*
    紧急穿越技能模块（共通技能）

    所有英雄共用的「紧急穿越」技能：未清房时站上方向矩形（出口矩形）使用技能，
    强行激活单条路线，瞬时传送到对应相邻房间，绕过「必须清房」的限制。

    代价机制：
    - 当前生命 >= 30%：扣除当前生命 20%
    - 当前生命 < 30%（濒死）：免费，但进入 10 秒冷却

    依赖：areaData, areaEnter, areaExit, areaSlot, DebugLogger
*/
library areaEmergency initializer InitEmergency requires areaData, areaEnter, areaExit, areaSlot, DebugLogger

globals
    private hashtable EmergencyTable = InitHashtable()
    // 共通技能 ID（占位符，由 WE/GUI 配置）
    private integer EMERGENCY_ABILITY_ID = 0
    // 代价参数
    private constant real EMERGENCY_COST_RATIO = 0.20     // 扣除当前生命比例
    private constant real EMERGENCY_FREE_THRESHOLD = 0.30 // 生命占比低于此值视为濒死
    // 冷却时长（秒）
    private constant real EMERGENCY_COOLDOWN_NORMAL = 3.00 // 正常冷却（占位符，可在 WE 调）
    private constant real EMERGENCY_COOLDOWN_FREE = 10.00  // 濒死免费冷却
    // 玩家冷却数据（parent key = GetPlayerId(player)）
    private constant integer HT_COOLDOWN = 0
    // 施法触发器
    private trigger CastTrig = null
endglobals

// ===== 内部：坐标判定 =====

private function PointInRect takes real x, real y, rect r returns boolean
    return x >= GetRectMinX(r) and x <= GetRectMaxX(r) and y >= GetRectMinY(r) and y <= GetRectMaxY(r)
endfunction

// 查找单位所在位置命中的门洞方向（源房已绑定且该方向网格连通），未找到返回 -1
private function FindDoorDirAtPosition takes integer sourceId, real x, real y returns integer
    local integer slotId = Slot_GetSlotOf(sourceId)
    local integer dir = 0
    local rect door
    if slotId < 0 then
        return -1
    endif
    loop
        exitwhen dir >= 4
        set door = Slot_GetSlotDoor(slotId, dir)
        if door != null and PointInRect(x, y, door) then
            if Grid_GetNeighbor(sourceId, dir) >= 0 then
                set door = null
                return dir
            endif
        endif
        set dir = dir + 1
    endloop
    set door = null
    return -1
endfunction

// 钩子：是否禁止从该房间紧急穿越（可覆写，例如被诅咒的房间封锁退路）
private function ShouldBlockEmergencyTraverse takes integer sourceAreaId returns boolean
    return false
endfunction

// ===== 内部：冷却 =====

private function EmergencyCdExpire takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer pid = LoadInteger(EmergencyTable, GetHandleId(t), 0)
    call SaveReal(EmergencyTable, pid, HT_COOLDOWN, 0.0)
    call FlushChildHashtable(EmergencyTable, GetHandleId(t))
    call DestroyTimer(t)
    set t = null
endfunction

private function SetEmergencyCooldown takes player p, real duration returns nothing
    local integer pid = GetPlayerId(p)
    local timer t
    call SaveReal(EmergencyTable, pid, HT_COOLDOWN, duration)
    if duration > 0.0 then
        set t = CreateTimer()
        call SaveInteger(EmergencyTable, GetHandleId(t), 0, pid)
        call TimerStart(t, duration, false, function EmergencyCdExpire)
        set t = null
    endif
endfunction

// ===== 内部：代价 =====

// 施加代价，返回应进入的冷却时长
private function ApplyEmergencyCost takes unit u returns real
    local real maxLife = GetUnitState(u, UNIT_STATE_MAX_LIFE)
    local real curLife = GetUnitState(u, UNIT_STATE_LIFE)
    local real ratio
    if maxLife <= 0.0 then
        return EMERGENCY_COOLDOWN_FREE
    endif
    set ratio = curLife / maxLife
    if ratio >= EMERGENCY_FREE_THRESHOLD then
        // 场景 A：扣除当前生命 20%
        call SetUnitState(u, UNIT_STATE_LIFE, curLife * (1.0 - EMERGENCY_COST_RATIO))
        return EMERGENCY_COOLDOWN_NORMAL
    endif
    // 场景 B：濒死免费，10 秒冷却
    return EMERGENCY_COOLDOWN_FREE
endfunction

// ===== 内部：施法处理 =====

private function Trig_EmergencyCast takes nothing returns nothing
    local unit u
    local player p
    local integer pid
    local integer sourceAreaId
    local rect curRect
    local integer dir
    local real cd
    // 仅处理共通紧急穿越技能
    if GetSpellAbilityId() != EMERGENCY_ABILITY_ID then
        // 诊断：确认施法事件已触发，以及实际技能ID与配置期望值是否一致
        call DebugLogger_Log(LOG_TRACE, "[emergency] spell ignored: cast=" + I2S(GetSpellAbilityId()) + " (" + GetObjectName(GetSpellAbilityId()) + ") expected=" + I2S(EMERGENCY_ABILITY_ID) + " (" + GetObjectName(EMERGENCY_ABILITY_ID) + ")")
        return
    endif
    set u = GetTriggerUnit()
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    set p = GetOwningPlayer(u)
    set pid = GetPlayerId(p)
    // 冷却检查
    if LoadReal(EmergencyTable, pid, HT_COOLDOWN) > 0.0 then
        call DebugLogger_Log(LOG_TRACE, "[emergency] cooldown active, skip pid=" + I2S(pid))
        set u = null
        set p = null
        return
    endif
    // 定位玩家当前区域
    set curRect = GetPlayerCurrentAreaRect(p)
    set sourceAreaId = GetAreaIdByRect(curRect)
    if sourceAreaId < 0 then
        set curRect = null
        set u = null
        set p = null
        return
    endif
    // 诅咒等封锁检查
    if ShouldBlockEmergencyTraverse(sourceAreaId) then
        call DebugLogger_Log(LOG_TRACE, "[emergency] blocked, source=" + GetAreaIdName(sourceAreaId))
        set curRect = null
        set u = null
        set p = null
        return
    endif
    // 查找脚下门洞方向
    set dir = FindDoorDirAtPosition(sourceAreaId, GetUnitX(u), GetUnitY(u))
    if dir < 0 then
        call DebugLogger_Log(LOG_TRACE, "[emergency] no door rect at position, source=" + GetAreaIdName(sourceAreaId))
        set curRect = null
        set u = null
        set p = null
        return
    endif
    // 先尝试传送；成功后才扣代价并进入冷却（目标槽位分配失败时不惩罚玩家）
    if TryTraverse(u, sourceAreaId, dir, true) then
        set cd = ApplyEmergencyCost(u)
        call SetEmergencyCooldown(p, cd)
        call DebugLogger_Log(LOG_INFO, "[emergency] traverse " + GetAreaIdName(sourceAreaId) + " dir=" + I2S(dir) + " -> " + GetAreaIdName(Grid_GetNeighbor(sourceAreaId, dir)) + " cd=" + R2S(cd))
    else
        call DebugLogger_Log(LOG_TRACE, "[emergency] traverse failed, source=" + GetAreaIdName(sourceAreaId) + " dir=" + I2S(dir))
    endif
    set curRect = null
    set u = null
    set p = null
endfunction

// ===== 公开接口 =====

/*
    [areaEmergency_SetEmergencyAbilityId]
    title = "设置紧急穿越技能ID"
    description = "设置共通紧急穿越技能的${技能ID}"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function SetEmergencyAbilityId takes integer abilityId returns nothing
    set EMERGENCY_ABILITY_ID = abilityId
    call DebugLogger_Log(LOG_INFO, "[emergency] ability id set to " + I2S(abilityId) + " (" + GetObjectName(abilityId) + ")")
endfunction

/*
    [areaEmergency_IsEmergencyActive]
    title = "紧急穿越是否可用"
    description = "判断${指定玩家}的紧急穿越技能当前是否可用（冷却已结束）"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = player
*/
public function IsEmergencyActive takes player p returns boolean
    return LoadReal(EmergencyTable, GetPlayerId(p), HT_COOLDOWN) <= 0.0
endfunction

// ===== 初始化 =====

private function InitEmergency takes nothing returns nothing
    set CastTrig = CreateTrigger()
    call TriggerRegisterAnyUnitEventBJ(CastTrig, EVENT_PLAYER_UNIT_SPELL_EFFECT)
    call TriggerAddAction(CastTrig, function Trig_EmergencyCast)
    call DebugLogger_Log(LOG_TRACE, "[emergency] InitEmergency done: cast trigger registered")
endfunction

// 重置紧急穿越系统：清除所有玩家的冷却数据
// 供 ChapterManager 在关卡切换时调用
function ResetAreaEmergency takes nothing returns nothing
    local integer i = 0
    loop
        exitwhen i >= bj_MAX_PLAYERS
        call FlushChildHashtable(EmergencyTable, i)
        set i = i + 1
    endloop
endfunction

endlibrary
#endif
