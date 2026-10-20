#ifndef AREA_EXIT
#define AREA_EXIT
#include "nncou\\debug.j"
/*
    区域门洞传送模块（通用框架）

    Step 3 起废弃旧的手动出口注册与 3 秒引导：
    - 连通关系由 areaGrid 的邻接自动决定；
    - 每个物理槽位注册 4 个门洞矩形；
    - 玩家英雄走进「已连通方向」的门洞时瞬时传送到目标逻辑房；
    - 只有安全房/入口房或已清空的房间可以通行，未清空房间的门显示封锁特效。

    门洞触发器按槽位常驻，事件发生时通过槽位反查当前逻辑 ID。
    TryTraverse 也供 emergency.j 复用（bypassGate=true 绕过清房限制）。

    依赖：areaData, areaEnter, areaSlot, areaGrid, DebugLogger
*/
library areaExit requires areaData, areaEnter, areaSlot, areaGrid, DebugLogger

globals
    // 触发器 -> 槽位/方向（parent key = GetHandleId(trigger)）
    private hashtable ExitTrigTable = InitHashtable()
    private constant integer HT_TRIG_SLOT = 0
    private constant integer HT_TRIG_DIR = 1

    // 每个槽位最多 4 个方向；槽位上限 64 -> 256
    private constant integer MAX_DOOR_TRIGGERS = 256
    private trigger array DoorEnterTrig
    private effect array DoorEffect

    // 门洞常驻特效（可用/封锁）。占位符，可在 WE 中替换
    private constant string EXIT_EFFECT_AVAILABLE = "Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTo.mdl"
    private constant string EXIT_EFFECT_LOCKED = "Abilities\\Spells\\Other\\Doom\\DoomTarget.mdl"
endglobals

// ===== 查询 =====

// 源房间是否允许通过门洞移动：安全区/入口区，或已清空的房间
function IsSourceTraversable takes integer sourceId returns boolean
    local integer roomType = GetRoomType(sourceId)
    if roomType == ROOM_TYPE_SAFE or roomType == ROOM_TYPE_ENTRY then
        return true
    endif
    return GetRoomState(sourceId) == ROOM_STATE_CLEARED
endfunction

// ===== 门洞特效 =====

private function DestroyDoorEffect takes integer index returns nothing
    if index >= 0 and index < MAX_DOOR_TRIGGERS then
        if DoorEffect[index] != null then
            call DestroyEffect(DoorEffect[index])
            set DoorEffect[index] = null
        endif
    endif
endfunction

// 刷新某槽位的门洞特效（绑定变化或房间状态变化后调用）
function RefreshSlotDoors takes integer slotId returns nothing
    local integer logicalId
    local integer dir
    local rect door
    local real x
    local real y
    if slotId < 0 then
        return
    endif
    set dir = 0
    loop
        exitwhen dir >= 4
        call DestroyDoorEffect(slotId * 4 + dir)
        set dir = dir + 1
    endloop

    set logicalId = Slot_GetLogicalId(slotId)
    if logicalId < 0 then
        return
    endif

    set dir = 0
    loop
        exitwhen dir >= 4
        // 只给网格中真实连通的方向显示门洞
        if Grid_GetNeighbor(logicalId, dir) >= 0 then
            set door = Slot_GetSlotDoor(slotId, dir)
            if door != null then
                set x = GetRectCenterX(door)
                set y = GetRectCenterY(door)
                if IsSourceTraversable(logicalId) then
                    set DoorEffect[slotId * 4 + dir] = AddSpecialEffect(EXIT_EFFECT_AVAILABLE, x, y)
                else
                    set DoorEffect[slotId * 4 + dir] = AddSpecialEffect(EXIT_EFFECT_LOCKED, x, y)
                endif
            endif
        endif
        set dir = dir + 1
    endloop
    set door = null
endfunction

// 清除某槽位的门洞特效（槽位释放后调用）
function ClearSlotDoors takes integer slotId returns nothing
    local integer dir = 0
    if slotId < 0 then
        return
    endif
    loop
        exitwhen dir >= 4
        call DestroyDoorEffect(slotId * 4 + dir)
        set dir = dir + 1
    endloop
endfunction

// 房间状态变化后刷新其已绑定槽位的门洞特效
function RefreshAreaExitState takes integer areaId returns nothing
    local integer slotId = Slot_GetSlotOf(areaId)
    if slotId >= 0 then
        call RefreshSlotDoors(slotId)
    endif
endfunction

// ===== 共享传送 =====

/*
    尝试从 sourceId 沿 dir 方向传送到邻居。
    bypassGate = false：普通门洞，要求源房间可通行（安全/入口/已清空）；
    bypassGate = true：紧急穿越，绕过清房限制。
    返回是否成功传送。
*/
function TryTraverse takes unit u, integer sourceId, integer dir, boolean bypassGate returns boolean
    local integer targetId
    local integer targetSlot
    local rect targetRect
    local player p
    if u == null then
        return false
    endif
    if not IsUnitType(u, UNIT_TYPE_HERO) then
        return false
    endif
    set targetId = Grid_GetNeighbor(sourceId, dir)
    if targetId < 0 then
        call DebugLogger_Log(LOG_TRACE, "[exit] no neighbor " + GetAreaIdName(sourceId) + " dir=" + I2S(dir))
        return false
    endif
    if not bypassGate and not IsSourceTraversable(sourceId) then
        call DebugLogger_Log(LOG_TRACE, "[exit] blocked (room not cleared) " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
        return false
    endif

    set targetSlot = Area_EnsureBound(targetId)
    if targetSlot < 0 then
        call DebugLogger_Log(LOG_WARN, "[exit] traverse failed: cannot bind target " + GetAreaIdName(targetId) + " from " + GetAreaIdName(sourceId))
        return false
    endif
    set targetRect = Slot_GetSlotRegion(targetSlot)
    if targetRect == null then
        call DebugLogger_Log(LOG_WARN, "[exit] traverse failed: target rect null " + GetAreaIdName(targetId))
        return false
    endif

    set p = GetOwningPlayer(u)
    // 先授权离开：SetUnitPosition 同步触发源房 leave 守卫，守卫必须放行
    call AllowPlayerLeaveAreaOnce(p)
    call SetUnitPosition(u, GetRectCenterX(targetRect), GetRectCenterY(targetRect))
    call DestroyEffect(AddSpecialEffectTarget("Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTarget.mdl", u, "origin"))
    if bypassGate then
        call DebugLogger_Log(LOG_INFO, "[exit] emergency teleport " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId) + " slot=" + I2S(targetSlot))
    else
        call DebugLogger_Log(LOG_INFO, "[exit] teleport " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId) + " slot=" + I2S(targetSlot))
    endif

    // 源房若已清空/未激活且无玩家，立即释放（ACTIVE/CURSED 保留）
    call ReleaseAreaIfIdle(sourceId)

    set p = null
    set targetRect = null
    return true
endfunction

// ===== 门洞事件 =====

private function Trig_DoorEnter takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local integer tid = GetHandleId(GetTriggeringTrigger())
    local integer slotId = LoadInteger(ExitTrigTable, tid, HT_TRIG_SLOT)
    local integer dir = LoadInteger(ExitTrigTable, tid, HT_TRIG_DIR)
    local integer sourceId = Slot_GetLogicalId(slotId)
    if u == null then
        return
    endif
    if sourceId < 0 then
        set u = null
        return
    endif
    call TryTraverse(u, sourceId, dir, false)
    set u = null
endfunction

// ===== 初始化 / 重置 =====

// 为每个槽位的 4 个门洞创建常驻进入触发器（门洞矩形为 null 则跳过）
function InitAreaExits takes nothing returns nothing
    local integer slotCount = Slot_GetCount()
    local integer slotId = 0
    local integer dir
    local integer index
    local rect door
    local trigger t
    loop
        exitwhen slotId >= slotCount
        set dir = 0
        loop
            exitwhen dir >= 4
            set index = slotId * 4 + dir
            if index < MAX_DOOR_TRIGGERS then
                set door = Slot_GetSlotDoor(slotId, dir)
                if door != null and DoorEnterTrig[index] == null then
                    set t = CreateTrigger()
                    call SaveInteger(ExitTrigTable, GetHandleId(t), HT_TRIG_SLOT, slotId)
                    call SaveInteger(ExitTrigTable, GetHandleId(t), HT_TRIG_DIR, dir)
                    call TriggerRegisterEnterRectSimple(t, door)
                    call TriggerAddAction(t, function Trig_DoorEnter)
                    set DoorEnterTrig[index] = t
                endif
            endif
            set dir = dir + 1
        endloop
        if Slot_GetLogicalId(slotId) >= 0 then
            call RefreshSlotDoors(slotId)
        endif
        set slotId = slotId + 1
    endloop
    call DebugLogger_Log(LOG_INFO, "[exit] InitAreaExits done: slots=" + I2S(slotCount))
    set door = null
    set t = null
endfunction

// 重置门洞系统：销毁所有门洞触发器与常驻特效
function ResetAreaExit takes nothing returns nothing
    local integer slotCount = Slot_GetCount()
    local integer i = 0
    local integer limit = slotCount * 4
    local trigger t
    if limit > MAX_DOOR_TRIGGERS then
        set limit = MAX_DOOR_TRIGGERS
    endif
    loop
        exitwhen i >= limit
        set t = DoorEnterTrig[i]
        if t != null then
            call FlushChildHashtable(ExitTrigTable, GetHandleId(t))
            call DestroyTrigger(t)
            set DoorEnterTrig[i] = null
        endif
        call DestroyDoorEffect(i)
        set i = i + 1
    endloop
    call DebugLogger_Log(LOG_TRACE, "[exit] ResetAreaExit done: slots=" + I2S(slotCount))
    set t = null
endfunction

// ===== 兼容占位（旧接口） =====

// 旧接口：Step 3 起传送为瞬时，保留空实现避免 GUI/旧配置编译失败
function SetAreaExitDelay takes real delay returns nothing
endfunction

function SetAreaExitFastDelay takes real delay returns nothing
endfunction

endlibrary
#endif
