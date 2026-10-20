#ifndef AREA_MONSTER_ROOM
#define AREA_MONSTER_ROOM
#include "nncou\\magic\\map\\monster\\group.j"
#include "nncou\\magic\\map\\timer\\timer.j"
#include "nncou\\magic\\map\\reward\\altar.j"
#include "nncou\\debug.j"
/*
    怪物房刷怪模块

    逻辑层：怪物池游标（cursor/remain）、存活数、房间状态按 logicalId 永久保存。
    物理层：进入/离开触发器按槽位常驻；怪物实例在当前绑定的槽位矩形内生成。

    生命周期：
    1. 玩家首次进入怪物房 -> 0.5s 后生成怪物（随机散布）
    2. 怪物总量 > 房间上限时仅刷出上限数量，死亡后补充
    3. 存活计数归零且池耗尽 -> 清空
    4. 玩家全部离场：删除未击杀怪物并回退游标（断点续传）
    5. 怪物不能离开当前槽位矩形
    6. 槽位释放时清理残留怪物/计时器/在场标记

    依赖：areaData, areaEnter, areaExit, areaSlot, MonsterGroup, ChapterTimer, RewardAltar, DebugLogger
*/
library areaMonsterRoom requires areaData, areaEnter, areaExit, areaSlot, MonsterGroup, ChapterTimer, RewardAltar, DebugLogger

globals
    // 逻辑房数据（parent key = logicalId）
    private hashtable RoomTable = InitHashtable()
    // 触发器 -> 槽位（parent key = GetHandleId(trigger)）
    private hashtable RoomTrigTable = InitHashtable()
    // 怪物单位 -> 逻辑房（parent key = GetHandleId(unit)）
    private hashtable RoomUnitTable = InitHashtable()
    // 刷怪计时器 -> 逻辑房（parent key = GetHandleId(timer)）
    private hashtable RoomTimerTable = InitHashtable()

    private constant real ROOM_SPAWN_DELAY = 0.50
    private constant real ROOM_SPAWN_INSET = 128.00
    private constant integer ROOM_DEFAULT_MONSTER_CAP = 10

    // 逻辑房子键（parent key = logicalId）
    private constant integer HT_SPAWN_CURSOR = 50
    private constant integer HT_SPAWN_REMAIN = 51
    private constant integer HT_SPAWN_TIMER = 52
    // 玩家在房间内的标记（子键 = 80 + playerId）
    private constant integer HT_PLAYER_PRESENCE_BASE = 80
    private constant integer HT_PLAYER_COUNT = 81

    // 触发器子键
    private constant integer HT_TRIG_SLOT = 0
    // 单位子键
    private constant integer HT_UNIT_AREA = 0

    // 每槽位常驻触发器
    private constant integer MAX_SLOTS = 64
    private trigger array SlotEnterTrig
    private trigger array SlotLeaveTrig

    // 怪物死亡触发器
    private trigger EnterRoomDeathTrig = null
endglobals

// ===== 内部：刷怪计时器 =====

private function CancelSpawnTimer takes integer areaId returns nothing
    local timer t = LoadTimerHandle(RoomTable, areaId, HT_SPAWN_TIMER)
    if t != null then
        call PauseTimer(t)
        call FlushChildHashtable(RoomTimerTable, GetHandleId(t))
        call DestroyTimer(t)
        call RemoveSavedHandle(RoomTable, areaId, HT_SPAWN_TIMER)
    endif
    set t = null
endfunction

// ===== 钩子 =====

// 房间清空时触发：回返时间 + 生成奖励祭坛 + 刷新门洞特效（封锁 -> 可用）
private function OnRoomCleared takes integer areaId returns nothing
    call ChapterTimer_ReturnTimeOnRoomClear(areaId)
    call RewardAltar_SpawnAltar(areaId, GetRoomType(areaId))
    call RefreshAreaExitState(areaId)
endfunction

// 将所有玩家离场时被删除的怪物退回刷怪进度。
// 游标记录的是「累计已刷出数」，离场删除的怪物未被击杀，需要回退同样数量。
private function RewindSpawnCursor takes integer areaId, integer rewindCount returns nothing
    local integer groupId = GetAreaMonsterPool(areaId)
    local integer entries
    local integer cursor
    local integer remain
    local integer pos
    local integer i
    local integer entryCount
    if groupId <= 0 or rewindCount <= 0 then
        return
    endif
    set entries = MonsterGroup_GetGroupEntryCount(groupId)
    if entries <= 0 then
        return
    endif
    set cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
    set remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)
    set pos = 0
    set i = 0
    loop
        exitwhen i >= cursor or i >= entries
        set pos = pos + MonsterGroup_GetEntryMonsterCount(groupId, i)
        set i = i + 1
    endloop
    if cursor < entries then
        set pos = pos + MonsterGroup_GetEntryMonsterCount(groupId, cursor) - remain
    endif
    set pos = pos - rewindCount
    if pos < 0 then
        set pos = 0
    endif
    set i = 0
    loop
        exitwhen i >= entries
        set entryCount = MonsterGroup_GetEntryMonsterCount(groupId, i)
        if pos < entryCount then
            exitwhen true
        endif
        set pos = pos - entryCount
        set i = i + 1
    endloop
    set cursor = i
    if cursor >= entries then
        set cursor = entries
        set remain = 0
    else
        set remain = MonsterGroup_GetEntryMonsterCount(groupId, cursor) - pos
    endif
    call SaveInteger(RoomTable, areaId, HT_SPAWN_CURSOR, cursor)
    call SaveInteger(RoomTable, areaId, HT_SPAWN_REMAIN, remain)
    call DebugLogger_Log(LOG_TRACE, "[room] rewind spawn cursor " + GetAreaIdName(areaId) + " -" + I2S(rewindCount) + " -> cursor=" + I2S(cursor) + "/" + I2S(entries) + " remain=" + I2S(remain))
endfunction

// 房间内玩家数量变化时触发
// oldCount > 0 且 newCount == 0 -> 所有玩家离场：未清空则删除所有怪物并回退游标
// oldCount == 0 且 newCount > 0 -> 玩家进场：由 Trig_PlayerEnterRoom 统一调度
private function OnRoomPlayerCountChanged takes integer areaId, integer oldCount, integer newCount returns nothing
    local rect r
    local group g
    local unit u
    local integer removed = 0
    local integer aliveBefore
    if oldCount > 0 and newCount <= 0 then
        if GetRoomState(areaId) == ROOM_STATE_ACTIVE and not IsAreaClearedThisGame(areaId) then
            set aliveBefore = GetAreaAliveMonsterCount(areaId)
            set r = GetAreaRect(areaId)
            if r == null then
                call DebugLogger_Log(LOG_WARN, "[room] all players left " + GetAreaIdName(areaId) + " but room has no bound rect")
                call SetAreaAliveMonsterCount(areaId, 0)
            else
                set g = CreateGroup()
                call GroupEnumUnitsInRect(g, r, null)
                loop
                    set u = FirstOfGroup(g)
                    exitwhen u == null
                    call GroupRemoveUnit(g, u)
                    if LoadInteger(RoomUnitTable, GetHandleId(u), HT_UNIT_AREA) == areaId then
                        call FlushChildHashtable(RoomUnitTable, GetHandleId(u))
                        call RemoveUnit(u)
                        set removed = removed + 1
                    endif
                endloop
                call DestroyGroup(g)
                set g = null
                set r = null
                call SetAreaAliveMonsterCount(areaId, 0)
                if removed != aliveBefore then
                    call DebugLogger_Log(LOG_WARN, "[room] leave removed " + I2S(removed) + "/" + I2S(aliveBefore) + " monsters in " + GetAreaIdName(areaId) + " (some outside rect or untracked)")
                endif
                call RewindSpawnCursor(areaId, removed)
                call DebugLogger_Log(LOG_INFO, "[room] all players left " + GetAreaIdName(areaId) + " -> remove " + I2S(removed) + " monsters, rewind cursor")
            endif
        endif
    endif
endfunction

// 是否限制怪物在房间内（可覆写）
private function ShouldClampUnitInRoom takes unit u, integer areaId returns boolean
    return true
endfunction

// ===== 内部：随机散布位置 =====

private function GetRandomPointInRect takes rect r returns location
    local real minX = GetRectMinX(r) + ROOM_SPAWN_INSET
    local real maxX = GetRectMaxX(r) - ROOM_SPAWN_INSET
    local real minY = GetRectMinY(r) + ROOM_SPAWN_INSET
    local real maxY = GetRectMaxY(r) - ROOM_SPAWN_INSET
    if minX > maxX then
        set minX = GetRectMinX(r)
        set maxX = GetRectMaxX(r)
    endif
    if minY > maxY then
        set minY = GetRectMinY(r)
        set maxY = GetRectMaxY(r)
    endif
    return Location(GetRandomReal(minX, maxX), GetRandomReal(minY, maxY))
endfunction

// ===== 内部：生成单只怪物 =====

private function SpawnSingleMonster takes integer areaId, integer monsterId returns nothing
    local rect r = GetAreaRect(areaId)
    local location loc
    local unit u
    if r == null then
        call DebugLogger_Log(LOG_WARN, "[room] SpawnSingleMonster skipped: no bound rect for " + GetAreaIdName(areaId))
        return
    endif
    if EnterRoomDeathTrig == null then
        call DebugLogger_Log(LOG_WARN, "[room] SpawnSingleMonster skipped: death trigger is null")
        set r = null
        return
    endif
    set loc = GetRandomPointInRect(r)
    set u = CreateUnitAtLoc(Player(PLAYER_NEUTRAL_AGGRESSIVE), monsterId, loc, GetRandomReal(0, 360))
    call RemoveLocation(loc)
    set loc = null
    if u == null then
        call DebugLogger_Log(LOG_WARN, "[room] SpawnSingleMonster failed: CreateUnitAtLoc returned null, monsterId=" + I2S(monsterId))
        set r = null
        return
    endif
    call SaveInteger(RoomUnitTable, GetHandleId(u), HT_UNIT_AREA, areaId)
    call TriggerRegisterUnitEvent(EnterRoomDeathTrig, u, EVENT_UNIT_DEATH)
    call SetAreaAliveMonsterCount(areaId, GetAreaAliveMonsterCount(areaId) + 1)
    call DestroyEffect(AddSpecialEffectTarget("Objects\\Spawnmodels\\NightElf\\EntBirthTarget\\EntBirthTarget.mdl", u, "origin"))
    call DebugLogger_Log(LOG_TRACE, "[room] spawn monster " + I2S(monsterId) + " in " + GetAreaIdName(areaId) + " alive=" + I2S(GetAreaAliveMonsterCount(areaId)))
    set u = null
    set r = null
endfunction

// ===== 内部：怪物死亡触发器 =====

private function Trig_MonsterDeath takes nothing returns nothing
    local unit dying = GetDyingUnit()
    local integer uid
    local integer areaId
    local integer alive
    local integer groupId
    local integer cursor
    local integer remain
    local integer entries
    local integer monsterId
    local integer spawned
    if dying == null then
        return
    endif
    set uid = GetHandleId(dying)
    if not HaveSavedInteger(RoomUnitTable, uid, HT_UNIT_AREA) then
        set dying = null
        return
    endif
    set areaId = LoadInteger(RoomUnitTable, uid, HT_UNIT_AREA)
    call FlushChildHashtable(RoomUnitTable, uid)
    // 房间已解绑（理论不应发生；释放时会先移除怪物）
    if Slot_GetSlotOf(areaId) < 0 then
        set dying = null
        return
    endif
    set alive = GetAreaAliveMonsterCount(areaId) - 1
    if alive < 0 then
        set alive = 0
    endif
    call SetAreaAliveMonsterCount(areaId, alive)

    // 补充刷新：还有未刷完的怪物则继续刷
    if alive < GetAreaMonsterCap(areaId) then
        set groupId = GetAreaMonsterPool(areaId)
        set cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
        set remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)
        set entries = MonsterGroup_GetGroupEntryCount(groupId)
        set spawned = 0
        loop
            exitwhen spawned >= 1 or cursor >= entries
            if remain > 0 then
                set monsterId = MonsterGroup_GetEntryMonsterId(groupId, cursor)
                call SpawnSingleMonster(areaId, monsterId)
                set remain = remain - 1
                set spawned = spawned + 1
            else
                set cursor = cursor + 1
                if cursor < entries then
                    set remain = MonsterGroup_GetEntryMonsterCount(groupId, cursor)
                endif
            endif
        endloop
        call SaveInteger(RoomTable, areaId, HT_SPAWN_CURSOR, cursor)
        call SaveInteger(RoomTable, areaId, HT_SPAWN_REMAIN, remain)
    endif

    // 清空检测：池耗尽且场上无存活怪物
    set alive = GetAreaAliveMonsterCount(areaId)
    set cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
    set remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)
    set groupId = GetAreaMonsterPool(areaId)
    if alive <= 0 and cursor >= MonsterGroup_GetGroupEntryCount(groupId) and remain <= 0 then
        call SetRoomState(areaId, ROOM_STATE_CLEARED)
        call SetAreaClearedThisGame(areaId, true)
        call DebugLogger_Log(LOG_INFO, "[room] room cleared: " + GetAreaIdName(areaId) + " state->CLEARED")
        call OnRoomCleared(areaId)
    endif
    set dying = null
endfunction

// 初始化刷怪游标（首次进入时调用）
private function InitSpawnCursor takes integer areaId returns nothing
    local integer groupId = GetAreaMonsterPool(areaId)
    if groupId <= 0 then
        return
    endif
    call SaveInteger(RoomTable, areaId, HT_SPAWN_CURSOR, 0)
    call SaveInteger(RoomTable, areaId, HT_SPAWN_REMAIN, MonsterGroup_GetEntryMonsterCount(groupId, 0))
endfunction

// ===== 内部：延迟刷怪回调 =====

private function Trig_SpawnDelay takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer tid = GetHandleId(t)
    local integer areaId
    local integer groupId
    local integer cap
    local integer entries
    local integer cursor
    local integer remain
    local integer monsterId
    local integer spawned = 0

    // 计时器 -> 逻辑房索引缺失：直接清理
    if not HaveSavedInteger(RoomTimerTable, tid, 0) then
        call FlushChildHashtable(RoomTimerTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif
    set areaId = LoadInteger(RoomTimerTable, tid, 0)
    // 定时器已到期：先清除逻辑房上的计时器句柄，避免取消逻辑误杀已到期计时器
    call RemoveSavedHandle(RoomTable, areaId, HT_SPAWN_TIMER)

    set groupId = GetAreaMonsterPool(areaId)
    set cap = GetAreaMonsterCap(areaId)
    set entries = MonsterGroup_GetGroupEntryCount(groupId)
    set cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
    set remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)

    if groupId <= 0 or entries <= 0 then
        call DebugLogger_Log(LOG_WARN, "[room] SpawnDelay abort: area " + GetAreaIdName(areaId) + " groupId=" + I2S(groupId) + " entries=" + I2S(entries) + " (no pool or empty group)")
        call FlushChildHashtable(RoomTimerTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif
    // 槽位已解绑（例如房间在延迟期间被释放）：放弃刷怪
    if Slot_GetSlotOf(areaId) < 0 then
        call DebugLogger_Log(LOG_TRACE, "[room] SpawnDelay abort: room unbound " + GetAreaIdName(areaId))
        call FlushChildHashtable(RoomTimerTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif
    // 延迟期间玩家已全部离场：放弃刷怪（离场时通常会取消计时器，这里是兜底）
    if LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT) <= 0 then
        call DebugLogger_Log(LOG_TRACE, "[room] SpawnDelay abort: no players in " + GetAreaIdName(areaId))
        call FlushChildHashtable(RoomTimerTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif
    if GetRoomState(areaId) == ROOM_STATE_CLEARED or IsAreaClearedThisGame(areaId) then
        call DebugLogger_Log(LOG_TRACE, "[room] SpawnDelay abort: room already cleared " + GetAreaIdName(areaId))
        call FlushChildHashtable(RoomTimerTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif

    loop
        exitwhen spawned >= cap or cursor >= entries
        if remain > 0 then
            set monsterId = MonsterGroup_GetEntryMonsterId(groupId, cursor)
            call SpawnSingleMonster(areaId, monsterId)
            set remain = remain - 1
            set spawned = spawned + 1
        else
            set cursor = cursor + 1
            if cursor < entries then
                set remain = MonsterGroup_GetEntryMonsterCount(groupId, cursor)
            endif
        endif
    endloop
    call SaveInteger(RoomTable, areaId, HT_SPAWN_CURSOR, cursor)
    call SaveInteger(RoomTable, areaId, HT_SPAWN_REMAIN, remain)
    call SetRoomState(areaId, ROOM_STATE_ACTIVE)
    call DebugLogger_Log(LOG_TRACE, "[room] SpawnDelay area " + GetAreaIdName(areaId) + " spawned=" + I2S(spawned) + "/" + I2S(cap) + " cursor=" + I2S(cursor) + "/" + I2S(entries) + " remain=" + I2S(remain) + " state->ACTIVE")
    if spawned <= 0 and not IsAreaClearedThisGame(areaId) and LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT) > 0 then
        call DebugLogger_Log(LOG_WARN, "[room] spawn produced 0 monsters: " + GetAreaIdName(areaId) + " cursor=" + I2S(cursor) + "/" + I2S(entries) + " remain=" + I2S(remain) + " alive=" + I2S(GetAreaAliveMonsterCount(areaId)) + " (pool exhausted or cursor not rewound)")
    endif
    call FlushChildHashtable(RoomTimerTable, tid)
    call DestroyTimer(t)
    set t = null
endfunction

// 调度延迟刷怪（同一房间同时只允许一个计时器）
private function ScheduleSpawn takes integer areaId returns nothing
    local timer t
    if LoadTimerHandle(RoomTable, areaId, HT_SPAWN_TIMER) != null then
        return
    endif
    set t = CreateTimer()
    call SaveInteger(RoomTimerTable, GetHandleId(t), 0, areaId)
    call SaveTimerHandle(RoomTable, areaId, HT_SPAWN_TIMER, t)
    call TimerStart(t, ROOM_SPAWN_DELAY, false, function Trig_SpawnDelay)
    set t = null
endfunction

// ===== 内部：玩家/怪物进入离开 =====

private function Trig_PlayerEnterRoom takes nothing returns nothing
    local unit u = GetEnteringUnit()
    local integer slotId
    local integer areaId
    local integer pid
    local integer oldCount
    local integer newCount
    local integer roomType
    if u == null then
        return
    endif
    set slotId = LoadInteger(RoomTrigTable, GetHandleId(GetTriggeringTrigger()), HT_TRIG_SLOT)
    set areaId = Slot_GetLogicalId(slotId)
    if IsUnitType(u, UNIT_TYPE_HERO) then
        call DebugLogger_Log(LOG_TRACE, "[room] RAW enter " + GetAreaIdName(areaId) + " unit=" + GetUnitName(u) + " isHero=T owner=" + I2S(GetPlayerId(GetOwningPlayer(u))))
    else
        call DebugLogger_Log(LOG_TRACE, "[room] RAW enter " + GetAreaIdName(areaId) + " unit=" + GetUnitName(u) + " isHero=F owner=" + I2S(GetPlayerId(GetOwningPlayer(u))))
    endif
    if areaId < 0 or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    set pid = GetPlayerId(GetOwningPlayer(u))
    if LoadBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid) then
        call DebugLogger_Log(LOG_TRACE, "[room] " + GetAreaIdName(areaId) + " skip: player already marked present")
        set u = null
        return
    endif
    call SaveBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid, true)
    set oldCount = LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT)
    set newCount = oldCount + 1
    call SaveInteger(RoomTable, areaId, HT_PLAYER_COUNT, newCount)
    if oldCount <= 0 then
        call DebugLogger_Log(LOG_TRACE, "[room] player enter " + GetAreaIdName(areaId) + " count->" + I2S(newCount))
    endif
    call OnRoomPlayerCountChanged(areaId, oldCount, newCount)

    // 所有房间都记录在场人数（槽位驱逐/回收判定需要）；只有怪物/精英房调度刷怪
    set roomType = GetRoomType(areaId)
    if roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE then
        if GetAreaMonsterPool(areaId) > 0 and not IsAreaClearedThisGame(areaId) then
            if GetRoomState(areaId) == ROOM_STATE_INACTIVE then
                call InitSpawnCursor(areaId)
                call ScheduleSpawn(areaId)
                call DebugLogger_Log(LOG_TRACE, "[room] player enter " + GetAreaIdName(areaId) + " state=INACTIVE pool=" + I2S(GetAreaMonsterPool(areaId)) + " -> schedule spawn")
            elseif GetRoomState(areaId) == ROOM_STATE_ACTIVE and GetAreaAliveMonsterCount(areaId) <= 0 then
                call ScheduleSpawn(areaId)
                call DebugLogger_Log(LOG_TRACE, "[room] player enter " + GetAreaIdName(areaId) + " state=ACTIVE alive=0 -> resume spawn from cursor")
            else
                call DebugLogger_Log(LOG_TRACE, "[room] player enter " + GetAreaIdName(areaId) + " state=" + I2S(GetRoomState(areaId)) + " -> no spawn")
            endif
        else
            call DebugLogger_Log(LOG_TRACE, "[room] player enter " + GetAreaIdName(areaId) + " pool=0 or cleared -> no spawn")
        endif
    endif
    set u = null
endfunction

// 判断离开事件是否为真实离场（而不是走上出口矩形被守卫拉回）
private function IsRealRoomLeave takes player p, integer slotId returns boolean
    local rect r = Slot_GetSlotRegion(slotId)
    if IsPlayerLeaveAllowed(p) then
        return true
    endif
    if r == null then
        return true
    endif
    return GetPlayerCurrentAreaRect(p) != r
endfunction

private function Trig_PlayerLeaveRoom takes nothing returns nothing
    local unit u = GetLeavingUnit()
    local integer slotId
    local integer areaId
    local integer pid
    local integer oldCount
    local integer newCount
    local rect r
    local real x
    local real y
    if u == null then
        return
    endif
    set slotId = LoadInteger(RoomTrigTable, GetHandleId(GetTriggeringTrigger()), HT_TRIG_SLOT)
    set areaId = Slot_GetLogicalId(slotId)
    if areaId < 0 then
        set u = null
        return
    endif

    // 非英雄：只处理本房间的怪物，拉回槽位矩形内
    if not IsUnitType(u, UNIT_TYPE_HERO) then
        if HaveSavedInteger(RoomUnitTable, GetHandleId(u), HT_UNIT_AREA) and LoadInteger(RoomUnitTable, GetHandleId(u), HT_UNIT_AREA) == areaId then
            if ShouldClampUnitInRoom(u, areaId) then
                set r = Slot_GetSlotRegion(slotId)
                if r != null then
                    set x = areaEnter_ClampXInRect(GetUnitX(u), r)
                    set y = areaEnter_ClampYInRect(GetUnitY(u), r)
                    call SetUnitX(u, x)
                    call SetUnitY(u, y)
                    call IssueImmediateOrder(u, "stop")
                endif
            endif
        endif
        set u = null
        set r = null
        return
    endif

    if not IsRealRoomLeave(GetOwningPlayer(u), slotId) then
        call DebugLogger_Log(LOG_TRACE, "[room] leave ignored (clamped back): unit=" + GetUnitName(u))
        set u = null
        return
    endif
    set pid = GetPlayerId(GetOwningPlayer(u))
    if not LoadBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid) then
        set u = null
        return
    endif
    call SaveBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid, false)
    set oldCount = LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT)
    set newCount = oldCount - 1
    if newCount < 0 then
        set newCount = 0
    endif
    call SaveInteger(RoomTable, areaId, HT_PLAYER_COUNT, newCount)
    call DebugLogger_Log(LOG_INFO, "[room] player leave " + GetAreaIdName(areaId) + " count->" + I2S(newCount))
    call OnRoomPlayerCountChanged(areaId, oldCount, newCount)
    if newCount <= 0 then
        call CancelSpawnTimer(areaId)
    endif
    set u = null
    set r = null
endfunction

// ===== 公开接口 =====

/*
    [areaMonsterRoom_SetAreaMonsterGroup]
    title = "设置区域怪物组"
    description = "将${指定ID}的怪物组绑定到${指定ID}的区域"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function SetAreaMonsterGroup takes integer areaId, integer groupId returns nothing
    call SetAreaMonsterPool(areaId, groupId)
endfunction

/*
    [areaMonsterRoom_SetRoomMonsterCap]
    title = "设置区域怪物上限"
    description = "设置${指定ID}的区域同时存在的怪物上限为${数量}"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function SetRoomMonsterCap takes integer areaId, integer cap returns nothing
    call SetAreaMonsterCap(areaId, cap)
endfunction

/*
    [areaMonsterRoom_RoomGetAliveCount]
    title = "获取房间存活怪物数"
    description = "获取${指定ID}的区域内当前存活怪物数量"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = integer
*/
public function RoomGetAliveCount takes integer areaId returns integer
    return GetAreaAliveMonsterCount(areaId)
endfunction

/*
    [areaMonsterRoom_IsRoomCleared]
    title = "房间是否已清空"
    description = "判断${指定ID}的区域是否已清空"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = integer
*/
public function IsRoomCleared takes integer areaId returns boolean
    return GetRoomState(areaId) == ROOM_STATE_CLEARED
endfunction

/*
    [areaMonsterRoom_IsPlayerInRoom]
    title = "玩家是否在房间内"
    description = "判断${指定玩家}是否在${指定ID}的区域内"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = player
    [[.args]]
    type = integer
*/
public function IsPlayerInRoom takes player p, integer areaId returns boolean
    return LoadBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + GetPlayerId(p))
endfunction

/*
    [areaMonsterRoom_GetRoomPlayerCount]
    title = "获取房间内玩家数"
    description = "获取${指定ID}区域内当前玩家数量"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = integer
*/
public function GetRoomPlayerCount takes integer areaId returns integer
    return LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT)
endfunction

/*
    [areaMonsterRoom_GetRandomRoomTag]
    title = "随机获取房间标签"
    description = "根据${区域ID}所绑定的怪物组，随机返回其中一个标签，供祭坛抽取奖励时作为依据；无组或无标签返回空串"
    category = TC_FRO
    returns = string
    [[.args]]
    type = integer
*/
public function GetRandomRoomTag takes integer areaId returns string
    local integer groupId = GetAreaMonsterPool(areaId)
    local integer tagCount
    if groupId <= 0 then
        return ""
    endif
    set tagCount = MonsterGroup_GetGroupTagCount(groupId)
    if tagCount <= 0 then
        return ""
    endif
    return MonsterGroup_GetGroupTag(groupId, GetRandomInt(0, tagCount - 1))
endfunction

// 槽位释放钩子（由 forest.j 的 Slot_SetReleaseHook 调用）：
// 取消刷怪计时器，移除残留怪物，清空在场计数
public function OnSlotReleased takes integer areaId returns nothing
    local integer slotId = Slot_GetSlotOf(areaId)
    local rect r
    local group g
    local unit u
    local integer removed = 0
    local integer i = 0
    call CancelSpawnTimer(areaId)
    if slotId >= 0 then
        set r = Slot_GetSlotRegion(slotId)
        if r != null then
            set g = CreateGroup()
            call GroupEnumUnitsInRect(g, r, null)
            loop
                set u = FirstOfGroup(g)
                exitwhen u == null
                call GroupRemoveUnit(g, u)
                if LoadInteger(RoomUnitTable, GetHandleId(u), HT_UNIT_AREA) == areaId then
                    call FlushChildHashtable(RoomUnitTable, GetHandleId(u))
                    call RemoveUnit(u)
                    set removed = removed + 1
                endif
            endloop
            call DestroyGroup(g)
            set g = null
        endif
        set r = null
    endif
    call SetAreaAliveMonsterCount(areaId, 0)
    if removed > 0 then
        call RewindSpawnCursor(areaId, removed)
    endif
    set i = 0
    loop
        exitwhen i >= bj_MAX_PLAYERS
        call SaveBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + i, false)
        set i = i + 1
    endloop
    call SaveInteger(RoomTable, areaId, HT_PLAYER_COUNT, 0)
    call DebugLogger_Log(LOG_TRACE, "[room] OnSlotReleased " + GetAreaIdName(areaId) + " slot=" + I2S(slotId) + " removed=" + I2S(removed))
    set u = null
endfunction

// ===== 初始化 =====

// 房间类型 -> 章节内难度档位：MONSTER -> 1，ELITE -> 2
private function GetRoomDifficulty takes integer roomType returns integer
    if roomType == ROOM_TYPE_ELITE then
        return 2
    endif
    return 1
endfunction

// 初始化怪物房系统：创建死亡触发器、为逻辑房绑定怪物组、为槽位创建常驻进出触发器
// 必须在 InitAreaWithEnter 之后、InitAreaGuards/InitAreaExits 之后调用
function InitMonsterRoom takes nothing returns nothing
    local integer i = 0
    local integer total = GetAreaCount()
    local integer slotCount = Slot_GetCount()
    local integer areaId
    local integer roomType
    local integer difficulty
    local integer groupId
    local rect r
    local trigger enterTrig
    local trigger leaveTrig
    local integer bound = 0
    // 重建死亡触发器（跨关卡安全）
    if EnterRoomDeathTrig != null then
        call DestroyTrigger(EnterRoomDeathTrig)
    endif
    set EnterRoomDeathTrig = CreateTrigger()
    call TriggerAddAction(EnterRoomDeathTrig, function Trig_MonsterDeath)

    // 按难度随机绑定怪物组
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        set roomType = GetRoomType(areaId)
        if roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE then
            set difficulty = GetRoomDifficulty(roomType)
            set groupId = GetRandomGroupByDifficulty(difficulty)
            if groupId <= 0 then
                call DebugLogger_Log(LOG_WARN, "[room] InitMonsterRoom: no group for difficulty=" + I2S(difficulty) + " area " + GetAreaIdName(areaId) + " will NOT spawn")
            else
                call SetAreaMonsterPool(areaId, groupId)
                if GetAreaMonsterCap(areaId) <= 0 then
                    call SetAreaMonsterCap(areaId, ROOM_DEFAULT_MONSTER_CAP)
                endif
                set bound = bound + 1
                call DebugLogger_Log(LOG_TRACE, "[room] bound area " + GetAreaIdName(areaId) + " type=" + I2S(roomType) + " groupId=" + I2S(groupId) + " cap=" + I2S(GetAreaMonsterCap(areaId)))
            endif
        endif
        set i = i + 1
    endloop

    // 为每个槽位创建常驻进出触发器（事件发生时反查逻辑 ID）
    set i = 0
    loop
        exitwhen i >= slotCount or i >= MAX_SLOTS
        set r = Slot_GetSlotRegion(i)
        if r != null then
            set enterTrig = CreateTrigger()
            call SaveInteger(RoomTrigTable, GetHandleId(enterTrig), HT_TRIG_SLOT, i)
            call TriggerRegisterEnterRectSimple(enterTrig, r)
            call TriggerAddAction(enterTrig, function Trig_PlayerEnterRoom)
            set SlotEnterTrig[i] = enterTrig

            set leaveTrig = CreateTrigger()
            call SaveInteger(RoomTrigTable, GetHandleId(leaveTrig), HT_TRIG_SLOT, i)
            call TriggerRegisterLeaveRectSimple(leaveTrig, r)
            call TriggerAddAction(leaveTrig, function Trig_PlayerLeaveRoom)
            set SlotLeaveTrig[i] = leaveTrig
        endif
        set i = i + 1
    endloop

    call DebugLogger_Log(LOG_INFO, "[room] InitMonsterRoom done: slots=" + I2S(slotCount) + " monsterRooms=" + I2S(bound))
    set r = null
    set enterTrig = null
    set leaveTrig = null
endfunction

// 重置怪物房系统：销毁死亡/进出触发器，移除所有怪物，清空逻辑房数据
// 供 ChapterManager 在关卡切换时调用（必须在 ResetAreaData / ResetAreaSlot 之前）
function ResetMonsterRoom takes nothing returns nothing
    local integer i = 0
    local integer total = GetAreaCount()
    local integer slotCount = Slot_GetCount()
    local integer areaId
    local integer handleId
    local trigger trig
    local rect r
    local group g
    local unit u

    // 先销毁死亡触发器，避免移除怪物时触发死亡回调
    if EnterRoomDeathTrig != null then
        call DestroyTrigger(EnterRoomDeathTrig)
        set EnterRoomDeathTrig = null
    endif

    // 移除所有绑定房间内的怪物（只移除本系统登记的）
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        call CancelSpawnTimer(areaId)
        set r = GetAreaRect(areaId)
        if r != null then
            set g = CreateGroup()
            call GroupEnumUnitsInRect(g, r, null)
            loop
                set u = FirstOfGroup(g)
                exitwhen u == null
                call GroupRemoveUnit(g, u)
                set handleId = GetHandleId(u)
                if LoadInteger(RoomUnitTable, handleId, HT_UNIT_AREA) == areaId then
                    call FlushChildHashtable(RoomUnitTable, handleId)
                    call RemoveUnit(u)
                endif
            endloop
            call DestroyGroup(g)
            set g = null
        endif
        set r = null
        call FlushChildHashtable(RoomTable, areaId)
        set i = i + 1
    endloop

    // 销毁槽位进出触发器
    set i = 0
    loop
        exitwhen i >= slotCount or i >= MAX_SLOTS
        set trig = SlotEnterTrig[i]
        if trig != null then
            call FlushChildHashtable(RoomTrigTable, GetHandleId(trig))
            call DestroyTrigger(trig)
            set SlotEnterTrig[i] = null
        endif
        set trig = SlotLeaveTrig[i]
        if trig != null then
            call FlushChildHashtable(RoomTrigTable, GetHandleId(trig))
            call DestroyTrigger(trig)
            set SlotLeaveTrig[i] = null
        endif
        set i = i + 1
    endloop

    call DebugLogger_Log(LOG_TRACE, "[room] ResetMonsterRoom done: slots=" + I2S(slotCount))
    set trig = null
    set u = null
endfunction

endlibrary
#endif
