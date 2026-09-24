#ifndef CURSE_SYSTEM_INCLUDED
#define CURSE_SYSTEM_INCLUDED
/*
    诅咒扩散系统模块

    负责：
    1. 从诅咒起始区域开始扩散
    2. 优先外围区域，沿有向图蔓延
    3. 被诅咒房间内玩家持续受伤

    纯框架+钩子模式：接口和钩子定义在此文件中，具体数值由WE/GUI填入。

    依赖：areaData
*/
library CurseSystem requires areaData

globals
    private hashtable CurseTable = InitHashtable()

    // 区域诅咒状态（parent key = areaId）
    private constant integer HT_IS_CURSED = 0
    private constant integer HT_CURSE_TICK = 1

    // 全局配置（parent key = 0）
    private constant integer HT_CURSE_ACTIVE = 100
    private constant integer HT_CURSE_INTERVAL = 101
    private constant integer HT_DAMAGE_BASE = 102
    private constant integer HT_DAMAGE_SCALE = 103
    private constant integer HT_DAMAGE_MAX = 104
    private constant integer HT_DAMAGE_INTERVAL = 105
    private constant integer HT_CURSED_COUNT = 106
    private constant integer HT_SPREAD_TIMER = 110
    private constant integer HT_DAMAGE_TIMER = 111

    // 诅咒扩散候选队列（parent key = 0，连续存储）
    private constant integer HT_CANDIDATE_LIST = 200
    private constant integer HT_CANDIDATE_COUNT = 199

    private constant real CURSE_DAMAGE_TICK = 1.00
    private integer SpreadCursor = 0

    private trigger DamageTrigger = null
    private unit CurrentDamagedUnit = null
    private real CurrentDamageValue = 0.0
endglobals

// ===== 钩子（private，可在 curse.j 内部覆写）=====

// 区域被诅咒时触发
private function OnAreaCursed takes integer areaId returns nothing
endfunction

// 所有区域被诅咒（全图诅咒）时触发
// BOSS房是唯一安全区，诅咒伤害持续递增迫使玩家进入BOSS房
private function OnAllAreaCursed takes nothing returns nothing
endfunction

// 判断区域是否可被诅咒（可覆写以添加特殊区域判断）
private function CanCurseArea takes integer areaId returns boolean
    if areaId == GetBossArea() then
        return false
    endif
    return not LoadBoolean(CurseTable, areaId, HT_IS_CURSED)
endfunction

// 计算诅咒伤害（可覆写以自定义伤害公式）
private function CalculateCurseDamage takes integer areaId returns real
    local real base = LoadReal(CurseTable, 0, HT_DAMAGE_BASE)
    local real scale = LoadReal(CurseTable, 0, HT_DAMAGE_SCALE)
    local real maxDmg = LoadReal(CurseTable, 0, HT_DAMAGE_MAX)
    local integer tick = LoadInteger(CurseTable, areaId, HT_CURSE_TICK)
    local real dmg = base + scale * I2R(tick)
    if dmg > maxDmg and maxDmg > 0 then
        return maxDmg
    endif
    return dmg
endfunction

// ===== 内部：诅咒单个区域 =====

private function CurseArea takes integer areaId returns nothing
    local integer cursedCount
    call SaveBoolean(CurseTable, areaId, HT_IS_CURSED, true)
    call SaveInteger(CurseTable, areaId, HT_CURSE_TICK, 0)
    call SetRoomState(areaId, ROOM_STATE_CURSED)
    set cursedCount = LoadInteger(CurseTable, 0, HT_CURSED_COUNT) + 1
    call SaveInteger(CurseTable, 0, HT_CURSED_COUNT, cursedCount)
    call OnAreaCursed(areaId)
    // 检查是否全图诅咒
    if cursedCount >= GetAreaCount() - 1 then
        // -1 因为 BOSS 房不诅咒
        call OnAllAreaCursed()
    endif
endfunction

// ===== 内部：构建扩散候选队列 =====

private function BuildCandidateList takes nothing returns nothing
    local integer total = GetAreaCount()
    local integer curseStartCount = GetCurseStartCount()
    local integer i = 0
    local integer j = 0
    local integer areaId
    local integer candidateCount = 0
    call SaveInteger(CurseTable, 0, HT_CANDIDATE_COUNT, 0)
    // 第一轮：先添加外围的诅咒起始区域
    set i = 0
    loop
        exitwhen i >= curseStartCount
        set areaId = GetCurseStartArea(i)
        if CanCurseArea(areaId) then
            call SaveInteger(CurseTable, 0, HT_CANDIDATE_LIST + candidateCount, areaId)
            set candidateCount = candidateCount + 1
        endif
        set i = i + 1
    endloop
    // 第二轮：添加诅咒起始区域的邻接区域
    set i = 0
    loop
        exitwhen i >= curseStartCount
        set areaId = GetCurseStartArea(i)
        set j = 0
        loop
            exitwhen j >= GetAreaNeighborCount(areaId)
            set areaId = GetAreaNeighbor(areaId, j)
            if CanCurseArea(areaId) then
                // 检查是否已在候选列表中
                // 简化处理：允许重复添加，CurseArea 会跳过已诅咒区域
                call SaveInteger(CurseTable, 0, HT_CANDIDATE_LIST + candidateCount, areaId)
                set candidateCount = candidateCount + 1
            endif
            set j = j + 1
        endloop
        set i = i + 1
    endloop
    // 第三轮：添加所有剩余区域（按注册顺序）
    set i = 0
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        if CanCurseArea(areaId) then
            call SaveInteger(CurseTable, 0, HT_CANDIDATE_LIST + candidateCount, areaId)
            set candidateCount = candidateCount + 1
        endif
        set i = i + 1
    endloop
    call SaveInteger(CurseTable, 0, HT_CANDIDATE_COUNT, candidateCount)
endfunction

// ===== 公开接口（提前声明，供内部函数调用）=====

public function StopCurseSpread takes nothing returns nothing
    local timer t
    call SaveBoolean(CurseTable, 0, HT_CURSE_ACTIVE, false)
    set t = LoadTimerHandle(CurseTable, 0, HT_SPREAD_TIMER)
    if t != null then
        call PauseTimer(t)
        call DestroyTimer(t)
        call SaveTimerHandle(CurseTable, 0, HT_SPREAD_TIMER, null)
    endif
    set t = LoadTimerHandle(CurseTable, 0, HT_DAMAGE_TIMER)
    if t != null then
        call PauseTimer(t)
        call DestroyTimer(t)
        call SaveTimerHandle(CurseTable, 0, HT_DAMAGE_TIMER, null)
    endif
    set t = null
endfunction

// ===== 内部：扩散回调 =====

private function Trig_CurseSpread takes nothing returns nothing
    local integer candidateCount = LoadInteger(CurseTable, 0, HT_CANDIDATE_COUNT)
    local integer areaId
    // 从候选队列中找到下一个可诅咒的区域
    loop
        exitwhen SpreadCursor >= candidateCount
        set areaId = LoadInteger(CurseTable, 0, HT_CANDIDATE_LIST + SpreadCursor)
        set SpreadCursor = SpreadCursor + 1
        if CanCurseArea(areaId) then
            call CurseArea(areaId)
            return
        endif
    endloop
    // 没有更多区域可诅咒，停止扩散
    call StopCurseSpread()
endfunction

// ===== 内部：伤害回调 =====

private function Trig_CurseDamage takes nothing returns nothing
    local integer total = GetAreaCount()
    local integer i = 0
    local integer areaId
    local rect r
    local group g = CreateGroup()
    local unit u
    local real dmg
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        if LoadBoolean(CurseTable, areaId, HT_IS_CURSED) then
            // 递增 tick
            call SaveInteger(CurseTable, areaId, HT_CURSE_TICK, LoadInteger(CurseTable, areaId, HT_CURSE_TICK) + 1)
            // 对区域内英雄造成伤害
            set r = GetAreaRect(areaId)
            call GroupEnumUnitsInRect(g, r, null)
            loop
                set u = FirstOfGroup(g)
                exitwhen u == null
                call GroupRemoveUnit(g, u)
                if IsUnitType(u, UNIT_TYPE_HERO) and GetUnitState(u, UNIT_STATE_LIFE) > 0 then
                    set dmg = CalculateCurseDamage(areaId)
                    set CurrentDamagedUnit = u
                    set CurrentDamageValue = dmg
                    if DamageTrigger != null then
                        call TriggerExecute(DamageTrigger)
                    endif
                endif
            endloop
        endif
        set i = i + 1
    endloop
    call DestroyGroup(g)
    set g = null
endfunction

// ===== 公开接口 =====

/*
    [CurseSystem_SetCurseDamageTrigger]
    title = "设置诅咒伤害触发器"
    description = "设置诅咒伤害时执行的${触发器}，触发器内可通过自定义脚本调用 CurseSystem_GetCurseDamagedUnit 和 CurseSystem_GetCurseDamageValue 获取受伤单位和伤害值"
    category = TC_FRO
    [[.args]]
    type = trigger
*/
public function SetCurseDamageTrigger takes trigger t returns nothing
    set DamageTrigger = t
endfunction

/*
    [CurseSystem_GetCurseDamagedUnit]
    title = "获取诅咒伤害单位"
    description = "在诅咒伤害触发器内调用，获取当前被诅咒伤害的单位"
    category = TC_FRO
    returns = unit
*/
public function GetCurseDamagedUnit takes nothing returns unit
    return CurrentDamagedUnit
endfunction

/*
    [CurseSystem_GetCurseDamageValue]
    title = "获取诅咒伤害值"
    description = "在诅咒伤害触发器内调用，获取当前诅咒伤害值"
    category = TC_FRO
    returns = real
*/
public function GetCurseDamageValue takes nothing returns real
    return CurrentDamageValue
endfunction

/*
    [CurseSystem_SetCurseSpreadInterval]
    title = "设置诅咒扩散间隔"
    description = "设置诅咒每隔${秒数}秒扩散一个区域"
    category = TC_FRO
    [[.args]]
    type = real
*/
public function SetCurseSpreadInterval takes real seconds returns nothing
    call SaveReal(CurseTable, 0, HT_CURSE_INTERVAL, seconds)
endfunction

/*
    [CurseSystem_SetCurseDamageParams]
    title = "设置诅咒伤害参数"
    description = "设置诅咒基础伤害${基础}，递增系数${系数}，上限${上限}，间隔${秒数}秒"
    category = TC_FRO
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = real
    [[.args]]
    type = real
*/
public function SetCurseDamageParams takes real base, real scale, real maxDamage, real interval returns nothing
    call SaveReal(CurseTable, 0, HT_DAMAGE_BASE, base)
    call SaveReal(CurseTable, 0, HT_DAMAGE_SCALE, scale)
    call SaveReal(CurseTable, 0, HT_DAMAGE_MAX, maxDamage)
    call SaveReal(CurseTable, 0, HT_DAMAGE_INTERVAL, interval)
endfunction

/*
    [CurseSystem_StartCurseSpread]
    title = "启动诅咒扩散"
    description = "时间结束后启动诅咒扩散系统"
    category = TC_FRO
*/
public function StartCurseSpread takes nothing returns nothing
    local real interval = LoadReal(CurseTable, 0, HT_CURSE_INTERVAL)
    local real dmgInterval = LoadReal(CurseTable, 0, HT_DAMAGE_INTERVAL)
    local timer spreadT
    local timer dmgT
    if LoadBoolean(CurseTable, 0, HT_CURSE_ACTIVE) then
        return
    endif
    call SaveBoolean(CurseTable, 0, HT_CURSE_ACTIVE, true)
    set SpreadCursor = 0
    // 构建扩散候选队列
    call BuildCandidateList()
    // 诅咒所有起始区域
    // 启动扩散计时器
    if interval > 0.0 then
        set spreadT = CreateTimer()
        call SaveTimerHandle(CurseTable, 0, HT_SPREAD_TIMER, spreadT)
        call TimerStart(spreadT, interval, true, function Trig_CurseSpread)
        set spreadT = null
    endif
    // 启动伤害计时器
    if dmgInterval > 0.0 then
        set dmgT = CreateTimer()
        call SaveTimerHandle(CurseTable, 0, HT_DAMAGE_TIMER, dmgT)
        call TimerStart(dmgT, dmgInterval, true, function Trig_CurseDamage)
        set dmgT = null
    endif
endfunction

/*
    [CurseSystem_IsAreaCursed]
    title = "区域是否被诅咒"
    description = "判断${指定ID}的区域是否已被诅咒"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = integer
*/
public function IsAreaCursed takes integer areaId returns boolean
    return LoadBoolean(CurseTable, areaId, HT_IS_CURSED)
endfunction

/*
    [CurseSystem_GetCursedAreaCount]
    title = "获取已诅咒区域数"
    description = "获取已被诅咒的区域数量"
    category = TC_FRO
    returns = integer
*/
public function GetCursedAreaCount takes nothing returns integer
    return LoadInteger(CurseTable, 0, HT_CURSED_COUNT)
endfunction

/*
    [CurseSystem_ForceCurseArea]
    title = "强制诅咒区域"
    description = "强制诅咒${指定ID}的区域（跳过扩散顺序）"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function ForceCurseArea takes integer areaId returns nothing
    if CanCurseArea(areaId) then
        call CurseArea(areaId)
    endif
endfunction

// 重置诅咒系统：停止扩散和伤害，清空所有诅咒状态和配置数据
// 供 ChapterManager 在关卡切换时调用
function ResetCurseSystem takes nothing returns nothing
    call StopCurseSpread()
    set SpreadCursor = 0
    set DamageTrigger = null
    set CurrentDamagedUnit = null
    set CurrentDamageValue = 0.0
endfunction

endlibrary
#endif
