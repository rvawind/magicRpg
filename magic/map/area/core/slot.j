#ifndef AREA_SLOT
#define AREA_SLOT
#include "nncou\\debug.j"
/*
    物理槽位池模块（通用框架）

    逻辑层与物理层分离：
    - 逻辑坐标（logicalId）的持久状态由 areaData 永久保存；
    - 物理资源（区域矩形、4 个门洞矩形、触发器、怪物、祭坛、特效）由本模块按需绑定与解绑。

    物理房间是 WE 中手工摆放的固定矩形，注册后永不销毁。
    槽位按地形分组（推荐 4 种地形 × 每地形 5 个 = 20 个，另加 1 个 BOSS 预留槽）。
    逻辑房只记住自己属于哪种地形；绑定时从同地形的空闲槽位中选，
    优先复用上次使用的物理房（粘性绑定）。

    槽位生命周期（与设计文档一致）：
    - 分配：玩家即将进入某逻辑坐标 -> 取同地形空闲槽位 -> 绑定。
    - 回收：房内无玩家 且（已清空 或 未激活） -> 解绑（由 areaEnter 的 ReleaseAreaIfIdle 驱动）。
    - 保留：房内有玩家，或被诅咒 -> 不回收。
    - 溢出：同地形无空闲槽位时，允许驱逐“无玩家且可驱逐”的槽位（由外部过滤器判定），
      这是“ACTIVE 保留”策略在槽位池满时的兜底，不改变逻辑房数据。

    反向索引全部使用独立 hashtable，避免 handleId 与槽位/逻辑 ID 冲突。

    依赖：areaGrid, DebugLogger
*/
library areaSlot requires areaGrid, DebugLogger

globals
    // 槽位属性（parent key = slotId）
    private hashtable SlotTable = InitHashtable()
    // 全局数据（parent key = 0）
    private hashtable SlotGlobalTable = InitHashtable()
    // 逻辑 ID 反向索引（parent key = logicalId）
    private hashtable SlotLogicalTable = InitHashtable()
    // 矩形反向索引（parent key = GetHandleId(rect)）
    private hashtable SlotRectTable = InitHashtable()

    // 槽位上限（数组与索引保护）
    private constant integer MAX_SLOTS = 64

    // 全局键（SlotGlobalTable, parent = 0）
    private constant integer HT_SLOT_COUNT = 0
    private constant integer HT_TERRAIN_TYPE_COUNT = 1
    private constant integer HT_BOSS_SLOT = 2
    private constant integer HT_CLOCK = 3

    // 槽位属性键（SlotTable, parent = slotId）
    private constant integer HT_SLOT_USED = 0
    private constant integer HT_SLOT_LOGICAL = 1
    private constant integer HT_SLOT_TERRAIN = 2
    private constant integer HT_SLOT_REGION = 3
    private constant integer HT_SLOT_LAST_USED = 4
    private constant integer HT_SLOT_IS_BOSS = 5
    private constant integer HT_SLOT_DOOR = 10  // + dir 0..3

    // 逻辑反向索引键（SlotLogicalTable, parent = logicalId）
    private constant integer HT_LOGICAL_SLOT = 0
    private constant integer HT_LOGICAL_LAST_SLOT = 1

    // 矩形反向索引键（SlotRectTable, parent = GetHandleId(rect)）
    private constant integer HT_RECT_SLOT = 0
    private constant integer HT_RECT_KIND = 1   // 0 = 区域矩形, 1 = 门洞矩形
    private constant integer HT_RECT_DIR = 2

    // 钩子
    private trigger AcquireHookTrig = null
    private trigger ReleaseHookTrig = null
    private trigger EvictFilterCond = null

    // 钩子上下文
    private integer EvalLogical = -1
    private integer LastAcquiredLogical = -1
    private integer LastReleasedLogical = -1
    private integer Clock = 0
endglobals

// ===== 查询接口 =====

function Slot_GetCount takes nothing returns integer
    return LoadInteger(SlotGlobalTable, 0, HT_SLOT_COUNT)
endfunction

// 已注册的地形种类数（地形编号应为 0 .. n-1）
function Slot_GetTerrainTypeCount takes nothing returns integer
    return LoadInteger(SlotGlobalTable, 0, HT_TERRAIN_TYPE_COUNT)
endfunction

function Slot_GetSlotRegion takes integer slotId returns rect
    if slotId < 0 then
        return null
    endif
    return LoadRectHandle(SlotTable, slotId, HT_SLOT_REGION)
endfunction

function Slot_GetSlotDoor takes integer slotId, integer dir returns rect
    if slotId < 0 or dir < 0 or dir > 3 then
        return null
    endif
    return LoadRectHandle(SlotTable, slotId, HT_SLOT_DOOR + dir)
endfunction

function Slot_GetSlotTerrain takes integer slotId returns integer
    return LoadInteger(SlotTable, slotId, HT_SLOT_TERRAIN)
endfunction

function Slot_IsBossSlot takes integer slotId returns boolean
    return LoadBoolean(SlotTable, slotId, HT_SLOT_IS_BOSS)
endfunction

// 槽位当前绑定的逻辑 ID，未绑定返回 -1
function Slot_GetLogicalId takes integer slotId returns integer
    if not LoadBoolean(SlotTable, slotId, HT_SLOT_USED) then
        return -1
    endif
    return LoadInteger(SlotTable, slotId, HT_SLOT_LOGICAL)
endfunction

// 逻辑 ID 当前绑定的槽位，未绑定返回 -1
function Slot_GetSlotOf takes integer logicalId returns integer
    local integer v
    if logicalId < 0 then
        return -1
    endif
    set v = LoadInteger(SlotLogicalTable, logicalId, HT_LOGICAL_SLOT)
    if v <= 0 then
        return -1
    endif
    return v - 1
endfunction

function Slot_IsBound takes integer logicalId returns boolean
    return Slot_GetSlotOf(logicalId) >= 0
endfunction

// 逻辑 ID 绑定的区域矩形，未绑定返回 null
function Slot_GetRect takes integer logicalId returns rect
    local integer slotId = Slot_GetSlotOf(logicalId)
    if slotId < 0 then
        return null
    endif
    return Slot_GetSlotRegion(slotId)
endfunction

// 逻辑 ID 绑定的指定方向门洞矩形，未绑定或无该门返回 null
function Slot_GetDoorRect takes integer logicalId, integer dir returns rect
    local integer slotId = Slot_GetSlotOf(logicalId)
    if slotId < 0 then
        return null
    endif
    return Slot_GetSlotDoor(slotId, dir)
endfunction

// 由区域矩形反查槽位（非区域矩形返回 -1）
function Slot_GetSlotByRegionRect takes rect r returns integer
    local integer v
    if r == null then
        return -1
    endif
    if LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_KIND) != 0 then
        return -1
    endif
    set v = LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_SLOT)
    if v <= 0 then
        return -1
    endif
    return v - 1
endfunction

// 由区域矩形反查逻辑 ID（未绑定或非区域矩形返回 -1）
function Slot_GetLogicalIdByRegionRect takes rect r returns integer
    local integer slotId = Slot_GetSlotByRegionRect(r)
    if slotId < 0 then
        return -1
    endif
    return Slot_GetLogicalId(slotId)
endfunction

// 由门洞矩形反查槽位（非门洞矩形返回 -1）
function Slot_GetSlotByDoorRect takes rect r returns integer
    local integer v
    if r == null then
        return -1
    endif
    if LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_KIND) != 1 then
        return -1
    endif
    set v = LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_SLOT)
    if v <= 0 then
        return -1
    endif
    return v - 1
endfunction

// 由门洞矩形反查方向（非门洞矩形返回 -1）
function Slot_GetDirByDoorRect takes rect r returns integer
    if r == null then
        return -1
    endif
    if LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_KIND) != 1 then
        return -1
    endif
    return LoadInteger(SlotRectTable, GetHandleId(r), HT_RECT_DIR)
endfunction

// 钩子上下文读取
function Slot_GetEvalLogical takes nothing returns integer
    return EvalLogical
endfunction

function Slot_GetLastAcquiredLogical takes nothing returns integer
    return LastAcquiredLogical
endfunction

function Slot_GetLastReleasedLogical takes nothing returns integer
    return LastReleasedLogical
endfunction

// ===== 钩子注册 =====

// 分配成功后执行（参数通过 Slot_GetLastAcquiredLogical 读取）
function Slot_SetAcquireHook takes code c returns nothing
    if AcquireHookTrig != null then
        call DestroyTrigger(AcquireHookTrig)
    endif
    set AcquireHookTrig = CreateTrigger()
    call TriggerAddAction(AcquireHookTrig, c)
endfunction

// 解绑前执行（参数通过 Slot_GetLastReleasedLogical 读取）
function Slot_SetReleaseHook takes code c returns nothing
    if ReleaseHookTrig != null then
        call DestroyTrigger(ReleaseHookTrig)
    endif
    set ReleaseHookTrig = CreateTrigger()
    call TriggerAddAction(ReleaseHookTrig, c)
endfunction

// 槽位溢出时的驱逐过滤器：返回 true 表示该逻辑房可被驱逐
function Slot_SetEvictFilter takes code c returns nothing
    if EvictFilterCond != null then
        call DestroyTrigger(EvictFilterCond)
    endif
    set EvictFilterCond = CreateTrigger()
    call TriggerAddCondition(EvictFilterCond, Condition(c))
endfunction

private function FireAcquireHook takes integer logicalId returns nothing
    set LastAcquiredLogical = logicalId
    if AcquireHookTrig != null then
        call TriggerExecute(AcquireHookTrig)
    endif
endfunction

private function FireReleaseHook takes integer logicalId returns nothing
    set LastReleasedLogical = logicalId
    if ReleaseHookTrig != null then
        call TriggerExecute(ReleaseHookTrig)
    endif
endfunction

private function CanEvictLogical takes integer logicalId returns boolean
    if EvictFilterCond == null then
        return false
    endif
    set EvalLogical = logicalId
    return TriggerEvaluate(EvictFilterCond)
endfunction

// ===== 内部：绑定 =====

private function TouchSlot takes integer slotId returns nothing
    set Clock = Clock + 1
    call SaveInteger(SlotTable, slotId, HT_SLOT_LAST_USED, Clock)
endfunction

private function BindSlot takes integer slotId, integer logicalId returns nothing
    call SaveBoolean(SlotTable, slotId, HT_SLOT_USED, true)
    call SaveInteger(SlotTable, slotId, HT_SLOT_LOGICAL, logicalId)
    call SaveInteger(SlotLogicalTable, logicalId, HT_LOGICAL_SLOT, slotId + 1)
    call SaveInteger(SlotLogicalTable, logicalId, HT_LOGICAL_LAST_SLOT, slotId + 1)
    call TouchSlot(slotId)
endfunction

private function UnbindSlot takes integer slotId returns nothing
    local integer logicalId = LoadInteger(SlotTable, slotId, HT_SLOT_LOGICAL)
    if logicalId >= 0 then
        call RemoveSavedInteger(SlotLogicalTable, logicalId, HT_LOGICAL_SLOT)
        // 保留 HT_LOGICAL_LAST_SLOT 作为粘性绑定记忆
    endif
    call SaveBoolean(SlotTable, slotId, HT_SLOT_USED, false)
    call SaveInteger(SlotTable, slotId, HT_SLOT_LOGICAL, -1)
endfunction

private function FindFreeSlot takes integer terrain returns integer
    local integer i = 0
    local integer count = Slot_GetCount()
    loop
        exitwhen i >= count
        if not LoadBoolean(SlotTable, i, HT_SLOT_USED) and not LoadBoolean(SlotTable, i, HT_SLOT_IS_BOSS) and LoadInteger(SlotTable, i, HT_SLOT_TERRAIN) == terrain then
            return i
        endif
        set i = i + 1
    endloop
    return -1
endfunction

// 在同地形中寻找最久未使用且允许驱逐的槽位
private function FindEvictSlot takes integer terrain returns integer
    local integer i = 0
    local integer count = Slot_GetCount()
    local integer best = -1
    local integer bestUsed = 0
    local integer used
    local integer logicalId
    loop
        exitwhen i >= count
        if LoadBoolean(SlotTable, i, HT_SLOT_USED) and not LoadBoolean(SlotTable, i, HT_SLOT_IS_BOSS) and LoadInteger(SlotTable, i, HT_SLOT_TERRAIN) == terrain then
            set logicalId = LoadInteger(SlotTable, i, HT_SLOT_LOGICAL)
            if logicalId >= 0 and CanEvictLogical(logicalId) then
                set used = LoadInteger(SlotTable, i, HT_SLOT_LAST_USED)
                if best < 0 or used < bestUsed then
                    set best = i
                    set bestUsed = used
                endif
            endif
        endif
        set i = i + 1
    endloop
    return best
endfunction

// ===== 公开：注册物理房间 =====

/*
    [areaSlot_RegisterPhysicalRoom]
    title = "注册物理房间"
    description = "注册地形为${地形}的固定物理房间；区域${区域矩形}，四个门洞${上}/${下}/${左}/${右}（无门可传null）；地形传 -1 表示 BOSS 预留槽"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = integer
    [[.args]]
    type = rect
    [[.args]]
    type = rect
    [[.args]]
    type = rect
    [[.args]]
    type = rect
    [[.args]]
    type = rect
*/
public function RegisterPhysicalRoom takes integer terrain, rect r, rect doorUp, rect doorDown, rect doorLeft, rect doorRight returns integer
    local integer slotId = Slot_GetCount()
    local integer terrainCount
    if r == null then
        call DebugLogger_Log(LOG_WARN, "[slot] RegisterPhysicalRoom skipped: null region")
        return -1
    endif
    if slotId >= MAX_SLOTS then
        call DebugLogger_Log(LOG_WARN, "[slot] RegisterPhysicalRoom skipped: slot limit " + I2S(MAX_SLOTS))
        return -1
    endif

    call SaveBoolean(SlotTable, slotId, HT_SLOT_USED, false)
    call SaveInteger(SlotTable, slotId, HT_SLOT_LOGICAL, -1)
    call SaveInteger(SlotTable, slotId, HT_SLOT_TERRAIN, terrain)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_REGION, r)
    call SaveInteger(SlotTable, slotId, HT_SLOT_LAST_USED, 0)
    call SaveBoolean(SlotTable, slotId, HT_SLOT_IS_BOSS, terrain < 0)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_DOOR + DIR_UP, doorUp)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_DOOR + DIR_DOWN, doorDown)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_DOOR + DIR_LEFT, doorLeft)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_DOOR + DIR_RIGHT, doorRight)

    call SaveInteger(SlotRectTable, GetHandleId(r), HT_RECT_SLOT, slotId + 1)
    call SaveInteger(SlotRectTable, GetHandleId(r), HT_RECT_KIND, 0)
    if doorUp != null then
        call SaveInteger(SlotRectTable, GetHandleId(doorUp), HT_RECT_SLOT, slotId + 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorUp), HT_RECT_KIND, 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorUp), HT_RECT_DIR, DIR_UP)
    endif
    if doorDown != null then
        call SaveInteger(SlotRectTable, GetHandleId(doorDown), HT_RECT_SLOT, slotId + 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorDown), HT_RECT_KIND, 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorDown), HT_RECT_DIR, DIR_DOWN)
    endif
    if doorLeft != null then
        call SaveInteger(SlotRectTable, GetHandleId(doorLeft), HT_RECT_SLOT, slotId + 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorLeft), HT_RECT_KIND, 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorLeft), HT_RECT_DIR, DIR_LEFT)
    endif
    if doorRight != null then
        call SaveInteger(SlotRectTable, GetHandleId(doorRight), HT_RECT_SLOT, slotId + 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorRight), HT_RECT_KIND, 1)
        call SaveInteger(SlotRectTable, GetHandleId(doorRight), HT_RECT_DIR, DIR_RIGHT)
    endif

    call SaveInteger(SlotGlobalTable, 0, HT_SLOT_COUNT, slotId + 1)
    if terrain >= 0 then
        set terrainCount = LoadInteger(SlotGlobalTable, 0, HT_TERRAIN_TYPE_COUNT)
        if terrain + 1 > terrainCount then
            call SaveInteger(SlotGlobalTable, 0, HT_TERRAIN_TYPE_COUNT, terrain + 1)
        endif
    else
        if LoadInteger(SlotGlobalTable, 0, HT_BOSS_SLOT) <= 0 then
            call SaveInteger(SlotGlobalTable, 0, HT_BOSS_SLOT, slotId + 1)
        endif
    endif

    call DebugLogger_Log(LOG_INFO, "[slot] registered slot=" + I2S(slotId) + " terrain=" + I2S(terrain) + " region=(" + R2S(GetRectCenterX(r)) + "," + R2S(GetRectCenterY(r)) + ")")
    return slotId
endfunction

// ===== 公开：分配 / 释放 =====

// 释放逻辑房的物理绑定（不销毁手工矩形；先触发释放钩子做内容清理）
function Slot_Release takes integer logicalId returns nothing
    local integer slotId = Slot_GetSlotOf(logicalId)
    if slotId < 0 then
        return
    endif
    call FireReleaseHook(logicalId)
    call UnbindSlot(slotId)
    call DebugLogger_Log(LOG_INFO, "[slot] released logical=" + I2S(logicalId) + " slot=" + I2S(slotId) + " terrain=" + I2S(LoadInteger(SlotTable, slotId, HT_SLOT_TERRAIN)))
endfunction

// 为逻辑房分配同地形槽位；已绑定则直接返回
function Slot_Acquire takes integer logicalId, integer terrain returns integer
    local integer slotId = Slot_GetSlotOf(logicalId)
    local integer sticky
    local integer count = Slot_GetCount()
    if slotId >= 0 then
        call TouchSlot(slotId)
        return slotId
    endif
    if count <= 0 then
        call DebugLogger_Log(LOG_WARN, "[slot] acquire failed: no physical rooms registered (logical=" + I2S(logicalId) + ")")
        return -1
    endif
    if terrain < 0 then
        set terrain = 0
    endif

    // 1) 粘性：优先上次使用的物理房（仍空闲且地形一致）
    set sticky = LoadInteger(SlotLogicalTable, logicalId, HT_LOGICAL_LAST_SLOT) - 1
    if sticky >= 0 and sticky < count then
        if not LoadBoolean(SlotTable, sticky, HT_SLOT_USED) and not LoadBoolean(SlotTable, sticky, HT_SLOT_IS_BOSS) and LoadInteger(SlotTable, sticky, HT_SLOT_TERRAIN) == terrain then
            set slotId = sticky
        endif
    endif

    // 2) 同地形空闲槽位
    if slotId < 0 then
        set slotId = FindFreeSlot(terrain)
    endif

    // 3) 同地形溢出驱逐（ACTIVE 保留策略的兜底）
    if slotId < 0 then
        set slotId = FindEvictSlot(terrain)
        if slotId >= 0 then
            call DebugLogger_Log(LOG_INFO, "[slot] overflow: evict logical=" + I2S(LoadInteger(SlotTable, slotId, HT_SLOT_LOGICAL)) + " from slot=" + I2S(slotId) + " for logical=" + I2S(logicalId) + " terrain=" + I2S(terrain))
            call Slot_Release(LoadInteger(SlotTable, slotId, HT_SLOT_LOGICAL))
        endif
    endif

    if slotId < 0 then
        call DebugLogger_Log(LOG_WARN, "[slot] acquire failed: terrain " + I2S(terrain) + " exhausted (logical=" + I2S(logicalId) + ", slots=" + I2S(count) + ")")
        return -1
    endif

    call BindSlot(slotId, logicalId)
    call FireAcquireHook(logicalId)
    call DebugLogger_Log(LOG_TRACE, "[slot] acquired logical=" + I2S(logicalId) + " slot=" + I2S(slotId) + " terrain=" + I2S(terrain))
    return slotId
endfunction

// 为 BOSS 逻辑房分配预留槽位
function Slot_AcquireBoss takes integer logicalId returns integer
    local integer v = LoadInteger(SlotGlobalTable, 0, HT_BOSS_SLOT)
    local integer slotId
    local integer old
    if v <= 0 then
        call DebugLogger_Log(LOG_WARN, "[slot] no boss slot registered, fallback to terrain 0 (logical=" + I2S(logicalId) + ")")
        return Slot_Acquire(logicalId, 0)
    endif
    set slotId = v - 1
    if LoadBoolean(SlotTable, slotId, HT_SLOT_USED) then
        set old = LoadInteger(SlotTable, slotId, HT_SLOT_LOGICAL)
        if old == logicalId then
            return slotId
        endif
        call Slot_Release(old)
    endif
    call BindSlot(slotId, logicalId)
    call FireAcquireHook(logicalId)
    call DebugLogger_Log(LOG_TRACE, "[slot] acquired boss logical=" + I2S(logicalId) + " slot=" + I2S(slotId))
    return slotId
endfunction

// ===== 重置 =====

// 关卡切换：清空所有绑定与粘性记忆，保留物理房间注册
function ResetAreaSlot takes nothing returns nothing
    local integer i = 0
    local integer count = Slot_GetCount()
    local integer total = Grid_GetTotal()
    local integer logicalId
    loop
        exitwhen i >= count
        if LoadBoolean(SlotTable, i, HT_SLOT_USED) then
            set logicalId = LoadInteger(SlotTable, i, HT_SLOT_LOGICAL)
            if logicalId >= 0 then
                call RemoveSavedInteger(SlotLogicalTable, logicalId, HT_LOGICAL_SLOT)
            endif
            call SaveBoolean(SlotTable, i, HT_SLOT_USED, false)
            call SaveInteger(SlotTable, i, HT_SLOT_LOGICAL, -1)
        endif
        call SaveInteger(SlotTable, i, HT_SLOT_LAST_USED, 0)
        set i = i + 1
    endloop
    // 清理粘性记忆
    set i = 0
    loop
        exitwhen i >= total
        call FlushChildHashtable(SlotLogicalTable, i)
        set i = i + 1
    endloop
    call SaveInteger(SlotGlobalTable, 0, HT_CLOCK, 0)
    set Clock = 0
    set EvalLogical = -1
    set LastAcquiredLogical = -1
    set LastReleasedLogical = -1
    call DebugLogger_Log(LOG_TRACE, "[slot] ResetAreaSlot done: cleared " + I2S(count) + " bindings")
endfunction

endlibrary
#endif
