#ifndef AREA_MONSTER_ROOM
#define AREA_MONSTER_ROOM
#include "nncou\\magic\\map\\monster\\group.j"
#include "nncou\\magic\\map\\timer\\timer.j"
#include "nncou\\magic\\map\\reward\\altar.j"
#include "nncou\\debug.j"
/*
    怪物房刷怪模块

    负责怪物房的完整生命周期：
    1. 玩家首次进入 → 0.5s 延迟后生成怪物（随机散布）
    2. 怪物总量 > 房间上限时，仅刷出上限数量，后续怪物在死亡后补充刷新
    3. 计数器追踪存活怪物，归零时触发清空逻辑
    4. 房间内无玩家时怪物无敌+暂停
    5. 怪物不能离开房间（复用 enter.j 拉回逻辑）

    房间与怪物组的绑定通过 areaData 的 SetAreaMonsterPool / GetAreaMonsterPool 实现，
    由配置文件（如 forest.j）调用。

    初始化：InitMonsterRoom() 必须在 InitArea() 之后调用，由配置文件负责。

    依赖：areaData, areaEnter, MonsterGroup
*/
library areaMonsterRoom requires areaData, areaEnter, areaExit, MonsterGroup, ChapterTimer, RewardAltar, DebugLogger

globals
    private hashtable RoomTable = InitHashtable()
    private constant real ROOM_SPAWN_DELAY = 0.50
    private constant real ROOM_SPAWN_INSET = 128.00
    // 房间怪物上限默认值
    private constant integer ROOM_DEFAULT_MONSTER_CAP = 10
    // 每个区域的刷怪进度子键（parent key = areaId）
    // HT_SPAWN_CURSOR: 当前刷到怪物组的第几个条目
    // HT_SPAWN_REMAIN: 当前条目的剩余未刷数量
    private constant integer HT_SPAWN_CURSOR = 50
    private constant integer HT_SPAWN_REMAIN = 51
    // 怪物单位 → 所属区域ID 的反向索引（parent key = GetHandleId(unit)）
    private constant integer HT_UNIT_AREA = 60
    // trigger → areaId 绑定（parent key = GetHandleId(trigger)）
    private constant integer HT_TRIG_AREA = 70
    // 玩家在房间内的标记（parent key = areaId，子键 = 80+playerId）
    private constant integer HT_PLAYER_PRESENCE_BASE = 80
    // 房间内玩家数量（parent key = areaId）
    private constant integer HT_PLAYER_COUNT = 81
    // 怪物死亡触发器（在 InitMonsterRoom 中创建实例）
    private trigger EnterRoomDeathTrig = null
    // 触发器跟踪（parent key = 0）
    private constant integer HT_TRIG_COUNT = 500
    private constant integer HT_TRIG_LIST = 501
endglobals

// ===== 钩子 =====

// 房间清空时触发：回返时间 + 生成奖励祭坛 + 刷新出口特效（封锁 → 可用）
private function OnRoomCleared takes integer areaId returns nothing
    call ChapterTimer_ReturnTimeOnRoomClear(areaId)
    call RewardAltar_SpawnAltar(areaId, GetRoomType(areaId))
    call RefreshAreaExitState(areaId)
endfunction

// 房间内玩家数量变化时触发
// oldCount > 0 且 newCount == 0 → 所有玩家离场：未清空则删除所有怪物（保留游标，断点续刷）
// oldCount == 0 且 newCount > 0 → 玩家进场：断点续刷（由 Trig_PlayerEnterRoom 统一调度）
private function OnRoomPlayerCountChanged takes integer areaId, integer oldCount, integer newCount returns nothing
    local rect r
    local group g
    local unit u
    if oldCount > 0 and newCount <= 0 then
        // 所有玩家离场：若房间仍处于激活（未清空），删除所有怪物，保留刷怪游标
        if GetRoomState(areaId) == ROOM_STATE_ACTIVE and not IsAreaClearedThisGame(areaId) then
            set r = GetAreaRect(areaId)
            set g = CreateGroup()
            call GroupEnumUnitsInRect(g, r, null)
            loop
                set u = FirstOfGroup(g)
                exitwhen u == null
                call GroupRemoveUnit(g, u)
                if LoadInteger(RoomTable, GetHandleId(u), HT_UNIT_AREA) == areaId then
                    call FlushChildHashtable(RoomTable, GetHandleId(u))
                    call RemoveUnit(u)
                endif
            endloop
            call DestroyGroup(g)
            set g = null
            set r = null
            call SetAreaAliveMonsterCount(areaId, 0)
        endif
    elseif oldCount <= 0 and newCount > 0 then
        // 玩家进场：断点续刷逻辑集中在 Trig_PlayerEnterRoom 中处理
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
    local location loc = GetRandomPointInRect(r)
    local unit u = CreateUnitAtLoc(Player(PLAYER_NEUTRAL_AGGRESSIVE), monsterId, loc, GetRandomReal(0, 360))
    // 记录怪物所属区域，用于死亡事件回调
    call SaveInteger(RoomTable, GetHandleId(u), HT_UNIT_AREA, areaId)
    // 注册死亡事件
    call TriggerRegisterUnitEvent(EnterRoomDeathTrig, u, EVENT_UNIT_DEATH)
    call SetAreaAliveMonsterCount(areaId, GetAreaAliveMonsterCount(areaId) + 1)
    // 生成特效：无动画特效，创建后立即销毁排泄
    call DestroyEffect(AddSpecialEffectTarget("Objects\\Spawnmodels\\NightElf\\EntBirthTarget\\EntBirthTarget.mdl", u, "origin"))
    call DebugLogger_Log(LOG_DEBUG, "[room] spawn monster " + I2S(monsterId) + " in " + GetAreaIdName(areaId) + " alive=" + I2S(GetAreaAliveMonsterCount(areaId)))
    call RemoveLocation(loc)
    set loc = null
    set u = null
    set r = null
endfunction

// ===== 内部：怪物死亡触发器 =====

private function Trig_MonsterDeath takes nothing returns nothing
    local unit dying = GetDyingUnit()
    local integer uid = GetHandleId(dying)
    local integer areaId = LoadInteger(RoomTable, uid, HT_UNIT_AREA)
    local integer alive
    local integer cap
    local integer groupId
    local integer cursor
    local integer remain
    local integer entries
    local integer monsterId
    local integer spawned
    if areaId < 0 then
        set dying = null
        return
    endif
    // 清除单位索引
    call FlushChildHashtable(RoomTable, uid)
    // 更新存活计数
    set alive = GetAreaAliveMonsterCount(areaId) - 1
    call SetAreaAliveMonsterCount(areaId, alive)
    // 补充刷新：如果还有未刷完的怪物，继续刷
    if alive < GetAreaMonsterCap(areaId) then
        set groupId = GetAreaMonsterPool(areaId)
        set cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
        set remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)
        set entries = MonsterGroup_GetGroupEntryCount(groupId)
        // 需要补充的数量
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
    // 清空检测：怪物池已耗尽（游标遍历完）且场上无存活怪物 → 清空
    // 清空判定 = totalSpawned(游标) 已达怪物组总量 且 alive == 0
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

// 初始化刷怪游标（首次进入时调用）：游标指向怪物组第一个条目
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
    local integer areaId = LoadInteger(RoomTable, tid, 0)
    local integer groupId = GetAreaMonsterPool(areaId)
    local integer cap = GetAreaMonsterCap(areaId)
    local integer entries = MonsterGroup_GetGroupEntryCount(groupId)
    local integer cursor = LoadInteger(RoomTable, areaId, HT_SPAWN_CURSOR)
    local integer remain = LoadInteger(RoomTable, areaId, HT_SPAWN_REMAIN)
    local integer monsterId
    local integer spawned = 0
    if groupId <= 0 or entries <= 0 then
        call DebugLogger_Log(LOG_WARN, "[room] SpawnDelay abort: area " + GetAreaIdName(areaId) + " groupId=" + I2S(groupId) + " entries=" + I2S(entries) + " (no pool or empty group)")
        call FlushChildHashtable(RoomTable, tid)
        call DestroyTimer(t)
        set t = null
        return
    endif
    // 从当前游标续刷到 cap（首次进入时游标已由 InitSpawnCursor 初始化）
    // 首批刷怪：刷满到 cap
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
    // 保存刷怪进度
    call SaveInteger(RoomTable, areaId, HT_SPAWN_CURSOR, cursor)
    call SaveInteger(RoomTable, areaId, HT_SPAWN_REMAIN, remain)
    call SetRoomState(areaId, ROOM_STATE_ACTIVE)
    call DebugLogger_Log(LOG_INFO, "[room] SpawnDelay area " + GetAreaIdName(areaId) + " spawned=" + I2S(spawned) + "/" + I2S(cap) + " cursor=" + I2S(cursor) + "/" + I2S(entries) + " remain=" + I2S(remain) + " state->ACTIVE")
    // 清理计时器
    call FlushChildHashtable(RoomTable, tid)
    call DestroyTimer(t)
    set t = null
endfunction

// 调度延迟刷怪（0.5s 后执行 Trig_SpawnDelay），从当前游标续刷到上限
private function ScheduleSpawn takes integer areaId returns nothing
    local timer t = CreateTimer()
    call SaveInteger(RoomTable, GetHandleId(t), 0, areaId)
    call TimerStart(t, ROOM_SPAWN_DELAY, false, function Trig_SpawnDelay)
    set t = null
endfunction

// ===== 内部：怪物离开房间时拉回 =====

private function Trig_MonsterLeaveRoom takes nothing returns nothing
    local unit u = GetLeavingUnit()
    local integer areaId
    local rect r
    local real x
    local real y
    if u == null then
        set u = null
        return
    endif
    set areaId = LoadInteger(RoomTable, GetHandleId(u), HT_UNIT_AREA)
    if areaId < 0 then
        set u = null
        return
    endif
    if not ShouldClampUnitInRoom(u, areaId) then
        set u = null
        return
    endif
    // 使用 areaEnter 的 Clamp 函数拉回
    set r = GetAreaRect(areaId)
    // 调用 areaEnter 库的 public 函数，需带库前缀
    set x = areaEnter_ClampXInRect(GetUnitX(u), r)
    set y = areaEnter_ClampYInRect(GetUnitY(u), r)
    call SetUnitX(u, x)
    call SetUnitY(u, y)
    //发布stop指令，让单位刷新仇恨
    call IssueImmediateOrder(u, "stop")
    set u = null
    set r = null
endfunction

// ===== 内部：玩家进入怪物房触发（玩家跟踪） =====

private function Trig_PlayerEnterRoom takes nothing returns nothing
    local unit u = GetEnteringUnit()
    local integer areaId
    local integer pid
    local integer oldCount
    local integer newCount
    // 诊断：在任何过滤之前打印，确认触发器是否真的触发 + 单位是否被识别为英雄
    set areaId = LoadInteger(RoomTable, GetHandleId(GetTriggeringTrigger()), HT_TRIG_AREA)
    if IsUnitType(u, UNIT_TYPE_HERO) then
        call DebugLogger_Log(LOG_INFO, "[room] RAW enter " + GetAreaIdName(areaId) + " unit=" + GetUnitName(u) + " isHero=T owner=" + I2S(GetPlayerId(GetOwningPlayer(u))))
    else
        call DebugLogger_Log(LOG_INFO, "[room] RAW enter " + GetAreaIdName(areaId) + " unit=" + GetUnitName(u) + " isHero=F owner=" + I2S(GetPlayerId(GetOwningPlayer(u))))
    endif
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    if areaId < 0 then
        set u = null
        return
    endif
    set pid = GetPlayerId(GetOwningPlayer(u))
    // 避免重复标记（玩家在同一区域内触发多次进入事件）
    if LoadBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid) then
        call DebugLogger_Log(LOG_INFO, "[room] " + GetAreaIdName(areaId) + " skip: player already marked present")
        set u = null
        return
    endif
    call SaveBoolean(RoomTable, areaId, HT_PLAYER_PRESENCE_BASE + pid, true)
    set oldCount = LoadInteger(RoomTable, areaId, HT_PLAYER_COUNT)
    set newCount = oldCount + 1
    call SaveInteger(RoomTable, areaId, HT_PLAYER_COUNT, newCount)
    call OnRoomPlayerCountChanged(areaId, oldCount, newCount)
    // 首次进入（未激活）：初始化游标后调度延迟刷怪
    if GetRoomState(areaId) == ROOM_STATE_INACTIVE and GetAreaMonsterPool(areaId) > 0 then
        call InitSpawnCursor(areaId)
        call ScheduleSpawn(areaId)
        call DebugLogger_Log(LOG_INFO, "[room] player enter " + GetAreaIdName(areaId) + " state=INACTIVE pool=" + I2S(GetAreaMonsterPool(areaId)) + " -> schedule spawn")
    elseif GetRoomState(areaId) == ROOM_STATE_ACTIVE and not IsAreaClearedThisGame(areaId) and GetAreaAliveMonsterCount(areaId) <= 0 then
        // 断点续刷：游标已保存，从断点继续
        call ScheduleSpawn(areaId)
        call DebugLogger_Log(LOG_INFO, "[room] player enter " + GetAreaIdName(areaId) + " state=ACTIVE alive=0 -> resume spawn from cursor")
    else
        call DebugLogger_Log(LOG_INFO, "[room] player enter " + GetAreaIdName(areaId) + " state=" + I2S(GetRoomState(areaId)) + " pool=" + I2S(GetAreaMonsterPool(areaId)) + " -> no spawn")
    endif
    set u = null
endfunction

// ===== 内部：玩家离开怪物房触发 =====

private function Trig_PlayerLeaveRoom takes nothing returns nothing
    local unit u = GetLeavingUnit()
    local integer areaId
    local integer pid
    local integer oldCount
    local integer newCount
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    // 未被授权离开（例如仅走上出口矩形被守卫拉回）不算真实离场，跳过，避免误删怪物/误改在场计数
    if not IsPlayerLeaveAllowed(GetOwningPlayer(u)) then
        set u = null
        return
    endif
    set areaId = LoadInteger(RoomTable, GetHandleId(GetTriggeringTrigger()), HT_TRIG_AREA)
    if areaId < 0 then
        set u = null
        return
    endif
    set pid = GetPlayerId(GetOwningPlayer(u))
    // 避免重复清除（玩家未标记为在场）
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
    call OnRoomPlayerCountChanged(areaId, oldCount, newCount)
    set u = null
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

// ===== 初始化 =====

// 房间类型 → 章节内难度档位
// MONSTER → 1（普通），ELITE → 2（困难），其余不刷怪
private function GetRoomDifficulty takes integer roomType returns integer
    if roomType == ROOM_TYPE_ELITE then
        return 2
    endif
    return 1
endfunction

// 初始化怪物房系统：创建死亡触发器并为所有怪物房注册进入/离开事件
// 每个怪物房根据房间类型映射到难度档位，再从 MonsterGroup 池中随机抽组绑定
// 必须在 InitArea() 之后调用，由配置文件负责
function InitMonsterRoom takes nothing returns nothing
    local integer i = 0
    local integer total = GetAreaCount()
    local integer areaId
    local integer roomType
    local integer difficulty
    local integer groupId
    local trigger enterTrig
    local trigger leaveTrig
    local integer trigCount = 0
    // 创建怪物死亡触发器
    set EnterRoomDeathTrig = CreateTrigger()
    call TriggerAddAction(EnterRoomDeathTrig, function Trig_MonsterDeath)
    // 为所有怪物房注册进入/离开事件，并按难度随机绑定怪物组
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        set roomType = GetRoomType(areaId)
        if roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE then
            // 按房间难度随机抽组；若池中无匹配组则跳过此区域
            set difficulty = GetRoomDifficulty(roomType)
            set groupId = GetRandomGroupByDifficulty(difficulty)
            if groupId <= 0 then
                call DebugLogger_Log(LOG_WARN, "[room] InitMonsterRoom: no group for difficulty=" + I2S(difficulty) + " area " + GetAreaIdName(areaId) + " will NOT spawn (no enter trigger)")
            else
                call SetAreaMonsterPool(areaId, groupId)
                // 设置默认怪物上限
                if GetAreaMonsterCap(areaId) <= 0 then
                    call SetAreaMonsterCap(areaId, ROOM_DEFAULT_MONSTER_CAP)
                endif
                call DebugLogger_Log(LOG_INFO, "[room] InitMonsterRoom bound area " + GetAreaIdName(areaId) + " type=" + I2S(roomType) + " groupId=" + I2S(groupId) + " cap=" + I2S(GetAreaMonsterCap(areaId)))
                // 创建玩家进入触发器
                set enterTrig = CreateTrigger()
                call TriggerRegisterEnterRectSimple(enterTrig, GetAreaRect(areaId))
                call TriggerAddAction(enterTrig, function Trig_PlayerEnterRoom)
                call SaveInteger(RoomTable, GetHandleId(enterTrig), HT_TRIG_AREA, areaId)
                // 创建玩家离开触发器
                set leaveTrig = CreateTrigger()
                call TriggerRegisterLeaveRectSimple(leaveTrig, GetAreaRect(areaId))
                call TriggerAddAction(leaveTrig, function Trig_PlayerLeaveRoom)
                call SaveInteger(RoomTable, GetHandleId(leaveTrig), HT_TRIG_AREA, areaId)
                // 追踪触发器用于清理
                call SaveTriggerHandle(RoomTable, 0, HT_TRIG_LIST + trigCount, enterTrig)
                set trigCount = trigCount + 1
                call SaveTriggerHandle(RoomTable, 0, HT_TRIG_LIST + trigCount, leaveTrig)
                set trigCount = trigCount + 1
            endif
        endif
        set i = i + 1
    endloop
    call SaveInteger(RoomTable, 0, HT_TRIG_COUNT, trigCount)
    call DebugLogger_Log(LOG_INFO, "[room] InitMonsterRoom done: created " + I2S(trigCount) + " enter/leave triggers (" + I2S(trigCount / 2) + " rooms bound)")
    set enterTrig = null
    set leaveTrig = null
endfunction

// 重置怪物房系统：杀死所有房间内怪物，销毁所有触发器，清空数据
// 供 ChapterManager 在关卡切换时调用
function ResetMonsterRoom takes nothing returns nothing
    local integer i = 0
    local integer total = GetAreaCount()
    local integer areaId
    local integer trigCount = LoadInteger(RoomTable, 0, HT_TRIG_COUNT)
    local integer handleId
    local trigger trig
    local rect r
    local group g
    local unit u
    // 杀死并移除所有房间内怪物，并清理单位级数据
    loop
        exitwhen i >= total
        set areaId = GetAreaByIndex(i)
        if GetAreaAliveMonsterCount(areaId) > 0 then
            set r = GetAreaRect(areaId)
            set g = CreateGroup()
            call GroupEnumUnitsInRect(g, r, null)
            loop
                set u = FirstOfGroup(g)
                exitwhen u == null
                call GroupRemoveUnit(g, u)
                set handleId = GetHandleId(u)
                if LoadInteger(RoomTable, handleId, HT_UNIT_AREA) == areaId then
                    call KillUnit(u)
                    call FlushChildHashtable(RoomTable, handleId)
                endif
            endloop
            call DestroyGroup(g)
            set g = null
            set r = null
        endif
        // 清理区域级数据
        call FlushChildHashtable(RoomTable, areaId)
        set i = i + 1
    endloop
    // 销毁所有追踪的进入/离开触发器，并清理触发器级数据
    set i = 0
    loop
        exitwhen i >= trigCount
        set trig = LoadTriggerHandle(RoomTable, 0, HT_TRIG_LIST + i)
        if trig != null then
            set handleId = GetHandleId(trig)
            call DestroyTrigger(trig)
            call FlushChildHashtable(RoomTable, handleId)
        endif
        set i = i + 1
    endloop
    // 销毁死亡触发器
    if EnterRoomDeathTrig != null then
        call DestroyTrigger(EnterRoomDeathTrig)
        set EnterRoomDeathTrig = null
    endif
    // 清空全局跟踪列表（不使用 FlushParentHashtable，避免 hashtable 失效）
    call FlushChildHashtable(RoomTable, 0)
    set trig = null
    set u = null
endfunction

endlibrary
#endif
