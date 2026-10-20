#ifndef AREA_ENTER
#define AREA_ENTER
#include "nncou\\debug.j"
/*
    区域进出保护模块（通用框架）

    物理层触发器按「槽位」常驻：槽位在 WE 中注册一次，触发器只创建一次，
    逻辑房切换绑定时不需要重建触发器。事件发生时通过槽位反查当前逻辑 ID。

    - 进入：记录玩家当前所在区域矩形（按逻辑 ID 记账由 monster_room 负责）。
    - 离开：无授权时把英雄拉回当前槽位矩形内。
    - 空闲回收：定时扫描已绑定槽位，无玩家且（已清空 或 未激活）时释放物理槽位。

    依赖：areaData, areaSlot, DebugLogger
*/
library areaEnter requires areaData, areaSlot, DebugLogger

globals
    // 玩家跟踪（parent key = GetHandleId(player)）
    private hashtable AreaEnterTable = InitHashtable()
    // 守卫触发器列表（parent key = 0）
    private hashtable GuardTable = InitHashtable()
    // 触发器 -> 槽位（parent key = GetHandleId(trigger)）
    private hashtable GuardTrigTable = InitHashtable()

    private constant real AREA_ENTER_PUSH_INSET = 1.00

    private constant integer HT_PLAYER_AREA_RECT = 10
    private constant integer HT_PLAYER_LEAVE_ALLOWED = 11
    private constant integer HT_PLAYER_CHANNELING = 12

    private constant integer HT_GUARD_COUNT = 0
    private constant integer HT_GUARD_ENTER_LIST = 100
    private constant integer HT_GUARD_LEAVE_LIST = 300
    private constant integer HT_TRIG_SLOT = 0

    private timer IdleSweepTimer = null
    private constant real IDLE_SWEEP_INTERVAL = 1.00
endglobals

// 供其他系统读取：获取玩家当前所在区域矩形
function GetPlayerCurrentAreaRect takes player whichPlayer returns rect
    return LoadRectHandle(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_AREA_RECT)
endfunction

// 供 exit 系统调用：允许玩家下一次合法离开当前区域
function AllowPlayerLeaveAreaOnce takes player whichPlayer returns nothing
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED, true)
endfunction

// 供 monster_room 系统调用：判断玩家当前是否被授权离开当前区域
function IsPlayerLeaveAllowed takes player whichPlayer returns boolean
    return LoadBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED)
endfunction

// 保留接口：旧出口系统曾用于标记引导中状态；瞬时传送不再使用，但避免 GUI 引用报错
function SetPlayerChanneling takes player whichPlayer, boolean flag returns nothing
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_CHANNELING, flag)
endfunction

function SetPlayerCurrentAreaRect takes player whichPlayer, rect areaRect returns nothing
    call SaveRectHandle(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_AREA_RECT, areaRect)
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED, false)
endfunction

private function GetBoundSlotId takes nothing returns integer
    return LoadInteger(GuardTrigTable, GetHandleId(GetTriggeringTrigger()), HT_TRIG_SLOT)
endfunction

private function B2S takes boolean b returns string
    if b then
        return "T"
    endif
    return "F"
endfunction

public function ClampXInRect takes real x, rect r returns real
    local real minX = GetRectMinX(r) + AREA_ENTER_PUSH_INSET
    local real maxX = GetRectMaxX(r) - AREA_ENTER_PUSH_INSET
    if minX > maxX then
        set minX = GetRectMinX(r)
        set maxX = GetRectMaxX(r)
    endif
    if x < minX then
        return minX
    endif
    if x > maxX then
        return maxX
    endif
    return x
endfunction

public function ClampYInRect takes real y, rect r returns real
    local real minY = GetRectMinY(r) + AREA_ENTER_PUSH_INSET
    local real maxY = GetRectMaxY(r) - AREA_ENTER_PUSH_INSET
    if minY > maxY then
        set minY = GetRectMinY(r)
        set maxY = GetRectMaxY(r)
    endif
    if y < minY then
        return minY
    endif
    if y > maxY then
        return maxY
    endif
    return y
endfunction

// ===== 玩家/房间查询 =====

// 统计矩形内的存活玩家英雄数
// 供空闲回收与槽位驱逐判定使用（比怪物房的离场记账更直接）
function CountPlayersInRect takes rect r returns integer
    local group g
    local unit u
    local integer count = 0
    if r == null then
        return 0
    endif
    set g = CreateGroup()
    call GroupEnumUnitsInRect(g, r, null)
    loop
        set u = FirstOfGroup(g)
        exitwhen u == null
        call GroupRemoveUnit(g, u)
        if IsUnitType(u, UNIT_TYPE_HERO) and GetUnitState(u, UNIT_STATE_LIFE) > 0.0 and GetPlayerSlotState(GetOwningPlayer(u)) == PLAYER_SLOT_STATE_PLAYING then
            set count = count + 1
        endif
    endloop
    call DestroyGroup(g)
    set g = null
    set u = null
    return count
endfunction

// 释放空闲槽位：无玩家且（已清空 或 未激活）时解绑
// BOSS 房、被诅咒房、有玩家房保留；返回是否释放
function ReleaseAreaIfIdle takes integer areaId returns boolean
    local integer slotId
    local integer state
    if areaId < 0 then
        return false
    endif
    if areaId == GetBossArea() then
        return false
    endif
    set slotId = Slot_GetSlotOf(areaId)
    if slotId < 0 then
        return false
    endif
    set state = GetRoomState(areaId)
    if state == ROOM_STATE_CURSED then
        return false
    endif
    if CountPlayersInRect(Slot_GetSlotRegion(slotId)) > 0 then
        return false
    endif
    if state == ROOM_STATE_CLEARED or state == ROOM_STATE_INACTIVE then
        call DebugLogger_Log(LOG_INFO, "[enter] release idle room " + GetAreaIdName(areaId) + " slot=" + I2S(slotId) + " state=" + I2S(state))
        call Slot_Release(areaId)
        return true
    endif
    return false
endfunction

// ===== 事件处理 =====

// 进入区域：记录玩家当前区域矩形
// 只处理英雄，避免召唤物/中立单位改写玩家的区域记录
private function Trig_AreaEnterActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local player p
    local integer slotId
    local integer areaId
    local rect r
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    set slotId = GetBoundSlotId()
    set areaId = Slot_GetLogicalId(slotId)
    if areaId < 0 then
        set u = null
        return
    endif
    set p = GetOwningPlayer(u)
    set r = Slot_GetSlotRegion(slotId)
    call SetPlayerCurrentAreaRect(p, r)
    call DebugLogger_Log(LOG_TRACE, "[enter] " + GetPlayerName(p) + " entered " + GetAreaIdName(areaId) + " slot=" + I2S(slotId))
    set u = null
    set p = null
    set r = null
endfunction

// 离开区域：无授权则拉回当前槽位矩形内
private function Trig_AreaLeaveActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local player p
    local integer slotId
    local integer areaId
    local rect r
    local real x
    local real y
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    set slotId = GetBoundSlotId()
    set areaId = Slot_GetLogicalId(slotId)
    if areaId < 0 then
        set u = null
        return
    endif
    set p = GetOwningPlayer(u)
    set r = Slot_GetSlotRegion(slotId)
    if r == null then
        set u = null
        set p = null
        return
    endif
    // 真实瞬移离场：已授权，或目标房 enter 已先行切换了玩家当前区域
    // （触发器注册顺序可能导致目标 enter 先于源 leave 执行并重置 leave_allowed）
    if LoadBoolean(AreaEnterTable, GetHandleId(p), HT_PLAYER_LEAVE_ALLOWED) or GetPlayerCurrentAreaRect(p) != r then
        call DebugLogger_Log(LOG_TRACE, "[enter] " + GetPlayerName(p) + " allowed to leave " + GetAreaIdName(areaId))
    else
        set x = GetUnitX(u)
        set y = GetUnitY(u)
        set x = ClampXInRect(x, r)
        set y = ClampYInRect(y, r)
        // 必须用 SetUnitPosition：会触发区域进入事件，保证引擎记录与系统记录一致
        call SetUnitPosition(u, x, y)
        call DebugLogger_Log(LOG_TRACE, "[enter] " + GetPlayerName(p) + " clamped back to " + GetAreaIdName(areaId))
    endif
    set u = null
    set p = null
    set r = null
endfunction

// 定时回收空闲槽位
private function Trig_IdleSweep takes nothing returns nothing
    local integer i = 0
    local integer count = Slot_GetCount()
    local integer areaId
    loop
        exitwhen i >= count
        set areaId = Slot_GetLogicalId(i)
        if areaId >= 0 then
            call ReleaseAreaIfIdle(areaId)
        endif
        set i = i + 1
    endloop
endfunction

// ===== 初始化 / 重置 =====

// 重置区域进出保护：销毁槽位触发器与空闲扫描定时器，清空玩家跟踪数据
// 注意：JASS 不允许前向引用，本函数必须定义在 InitAreaGuards 之前
function ResetAreaEnter takes nothing returns nothing
    local integer count = LoadInteger(GuardTable, 0, HT_GUARD_COUNT)
    local integer i = 0
    local trigger t
    loop
        exitwhen i >= count
        set t = LoadTriggerHandle(GuardTable, 0, HT_GUARD_ENTER_LIST + i)
        if t != null then
            call FlushChildHashtable(GuardTrigTable, GetHandleId(t))
            call DestroyTrigger(t)
        endif
        set t = LoadTriggerHandle(GuardTable, 0, HT_GUARD_LEAVE_LIST + i)
        if t != null then
            call FlushChildHashtable(GuardTrigTable, GetHandleId(t))
            call DestroyTrigger(t)
        endif
        call RemoveSavedHandle(GuardTable, 0, HT_GUARD_ENTER_LIST + i)
        call RemoveSavedHandle(GuardTable, 0, HT_GUARD_LEAVE_LIST + i)
        set i = i + 1
    endloop
    call SaveInteger(GuardTable, 0, HT_GUARD_COUNT, 0)
    if IdleSweepTimer != null then
        call PauseTimer(IdleSweepTimer)
        call DestroyTimer(IdleSweepTimer)
        set IdleSweepTimer = null
    endif
    set i = 0
    loop
        exitwhen i >= bj_MAX_PLAYERS
        call FlushChildHashtable(AreaEnterTable, GetHandleId(Player(i)))
        set i = i + 1
    endloop
    set t = null
    call DebugLogger_Log(LOG_TRACE, "[enter] ResetAreaEnter done")
endfunction

// 为每个已注册物理槽位创建常驻进出监听触发器
function InitAreaGuards takes nothing returns nothing
    local integer count = Slot_GetCount()
    local integer i = 0
    local rect areaRect
    local trigger enter
    local trigger leave
    if LoadInteger(GuardTable, 0, HT_GUARD_COUNT) > 0 then
        call ResetAreaEnter()
    endif
    loop
        exitwhen i >= count
        set areaRect = Slot_GetSlotRegion(i)
        if areaRect != null then
            set enter = CreateTrigger()
            set leave = CreateTrigger()
            call SaveInteger(GuardTrigTable, GetHandleId(enter), HT_TRIG_SLOT, i)
            call SaveInteger(GuardTrigTable, GetHandleId(leave), HT_TRIG_SLOT, i)
            call TriggerRegisterEnterRectSimple(enter, areaRect)
            call TriggerRegisterLeaveRectSimple(leave, areaRect)
            call TriggerAddAction(enter, function Trig_AreaEnterActions)
            call TriggerAddAction(leave, function Trig_AreaLeaveActions)
            call SaveTriggerHandle(GuardTable, 0, HT_GUARD_ENTER_LIST + i, enter)
            call SaveTriggerHandle(GuardTable, 0, HT_GUARD_LEAVE_LIST + i, leave)
            call DebugLogger_Log(LOG_TRACE, "[enter] guard slot=" + I2S(i) + " center=(" + R2S(GetRectCenterX(areaRect)) + "," + R2S(GetRectCenterY(areaRect)) + ")")
        endif
        set i = i + 1
    endloop
    call SaveInteger(GuardTable, 0, HT_GUARD_COUNT, count)
    if IdleSweepTimer == null then
        set IdleSweepTimer = CreateTimer()
        call TimerStart(IdleSweepTimer, IDLE_SWEEP_INTERVAL, true, function Trig_IdleSweep)
    endif
    call DebugLogger_Log(LOG_INFO, "[enter] InitAreaGuards done: slots=" + I2S(count))
    set areaRect = null
    set enter = null
    set leave = null
endfunction

endlibrary
#endif
