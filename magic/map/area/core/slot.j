#ifndef AREA_SLOT
#define AREA_SLOT
#include "nncou\\debug.j"
/*
    物理槽位池模块（通用框架）

    逻辑层与物理层分离：逻辑坐标的持久状态由 areaData 以逻辑 ID 存储，
    物理资源（区域矩形 rect、门洞矩形、触发器、怪物单位、特效）由本模块按需实例化与回收。

    槽位生命周期：
    - 分配：玩家即将进入某逻辑坐标 → 从空闲池取槽位 → 创建区域矩形 + 4 个门洞矩形并绑定。
    - 回收：房间内无玩家且（已清空或未激活）→ 销毁矩形 → 槽位标记空闲。
    - 保留：房间内有玩家，或被诅咒（仍需伤害判定），则不回收。

    反向索引约定（避免 0 与默认值歧义）：存储值一律 +1。
      - HT_LOGICAL_SLOT：logicalId → slotId+1（0=未绑定）
      - HT_RECT_LOGICAL：cell rect handle → logicalId+1（0=非区域矩形）

    依赖：areaGrid, DebugLogger
*/
library areaSlot requires areaGrid, DebugLogger

globals
    private hashtable SlotTable = InitHashtable()
    // 槽位总数
    private constant integer SLOT_COUNT = 10
    // 槽位字段（parent key = slotId 0..9）
    private constant integer HT_SLOT_USED = 0
    private constant integer HT_SLOT_LOGICAL = 1
    private constant integer HT_SLOT_RECT = 2
    private constant integer HT_SLOT_DOOR_RECT = 10  // + dir 0..3
    // 反向索引（parent key = logicalId）
    private constant integer HT_LOGICAL_SLOT = 0
    // 反向索引（parent key = GetHandleId(cell rect)）
    private constant integer HT_RECT_LOGICAL = 0

    // 物理映射参数（由 Slot_Init 配置）
    private real OriginX = 0.0
    private real OriginY = 0.0
    private real CellWidth = 512.0
    private real CellHeight = 512.0
    // 门洞半宽（门矩形约 2×DOOR_HALF 深，位于单元格内边界处）
    private constant real DOOR_HALF = 64.0
endglobals

// ===== 内部：矩形构造 =====

// 计算逻辑坐标对应的物理区域矩形（新建，调用方负责 RemoveRect）
private function CreateCellRect takes integer logicalId returns rect
    local integer row = Grid_GetRow(logicalId)
    local integer col = Grid_GetCol(logicalId)
    local real minX = OriginX + col * CellWidth
    local real minY = OriginY + row * CellHeight
    return Rect(minX, minY, minX + CellWidth, minY + CellHeight)
endfunction

// 计算指定方向的门洞矩形（位于单元格内部，靠近该方向边界）
private function CreateDoorRect takes rect cell, integer dir returns rect
    local real minX = GetRectMinX(cell)
    local real maxX = GetRectMaxX(cell)
    local real minY = GetRectMinY(cell)
    local real maxY = GetRectMaxY(cell)
    local real cx = (minX + maxX) / 2.0
    local real cy = (minY + maxY) / 2.0
    if dir == DIR_UP then
        return Rect(cx - DOOR_HALF, minY, cx + DOOR_HALF, minY + 2.0 * DOOR_HALF)
    elseif dir == DIR_DOWN then
        return Rect(cx - DOOR_HALF, maxY - 2.0 * DOOR_HALF, cx + DOOR_HALF, maxY)
    elseif dir == DIR_LEFT then
        return Rect(minX, cy - DOOR_HALF, minX + 2.0 * DOOR_HALF, cy + DOOR_HALF)
    endif
    // DIR_RIGHT
    return Rect(maxX - 2.0 * DOOR_HALF, cy - DOOR_HALF, maxX, cy + DOOR_HALF)
endfunction

// 返回逻辑坐标绑定的槽位 ID，未绑定返回 -1
private function GetBoundSlot takes integer logicalId returns integer
    local integer v = LoadInteger(SlotTable, logicalId, HT_LOGICAL_SLOT)
    if v <= 0 then
        return -1
    endif
    return v - 1
endfunction

// ===== 公开接口 =====

// 配置物理映射参数（网格原点、单元格宽高）
function Slot_Init takes real originX, real originY, real cellWidth, real cellHeight returns nothing
    set OriginX = originX
    set OriginY = originY
    set CellWidth = cellWidth
    set CellHeight = cellHeight
endfunction

// 逻辑坐标是否已绑定物理槽位
function Slot_IsBound takes integer logicalId returns boolean
    return GetBoundSlot(logicalId) >= 0
endfunction

// 获取逻辑坐标的物理区域矩形（未绑定返回 null）
function Slot_GetRect takes integer logicalId returns rect
    local integer slotId = GetBoundSlot(logicalId)
    if slotId < 0 then
        return null
    endif
    return LoadRectHandle(SlotTable, slotId, HT_SLOT_RECT)
endfunction

// 获取逻辑坐标指定方向的门洞矩形（未绑定返回 null）
function Slot_GetDoorRect takes integer logicalId, integer dir returns rect
    local integer slotId = GetBoundSlot(logicalId)
    if slotId < 0 or dir < 0 or dir > 3 then
        return null
    endif
    return LoadRectHandle(SlotTable, slotId, HT_SLOT_DOOR_RECT + dir)
endfunction

// 由区域矩形反查逻辑 ID（非区域矩形返回 -1）
function Slot_GetLogicalIdByRect takes rect r returns integer
    if r == null then
        return -1
    endif
    return LoadInteger(SlotTable, GetHandleId(r), HT_RECT_LOGICAL) - 1
endfunction

// 释放逻辑坐标的物理槽位：移除区域矩形与门洞矩形，标记槽位空闲
function Slot_Release takes integer logicalId returns nothing
    local integer slotId = GetBoundSlot(logicalId)
    local rect cell
    local rect door
    local integer dir = 0
    if slotId < 0 then
        return
    endif
    set cell = LoadRectHandle(SlotTable, slotId, HT_SLOT_RECT)
    if cell != null then
        call RemoveSavedInteger(SlotTable, GetHandleId(cell), HT_RECT_LOGICAL)
        call RemoveRect(cell)
    endif
    loop
        exitwhen dir >= 4
        set door = LoadRectHandle(SlotTable, slotId, HT_SLOT_DOOR_RECT + dir)
        if door != null then
            call RemoveRect(door)
        endif
        set dir = dir + 1
    endloop
    call RemoveSavedInteger(SlotTable, logicalId, HT_LOGICAL_SLOT)
    call FlushChildHashtable(SlotTable, slotId)
    set cell = null
    set door = null
endfunction

// 分配（或复用）逻辑坐标的物理槽位，返回区域矩形
// 已绑定则直接返回；无空闲槽位时兜底回收最早绑定的槽位（实践中不应发生）
function Slot_Acquire takes integer logicalId returns rect
    local integer slotId = GetBoundSlot(logicalId)
    local integer i = 0
    local rect cell
    local integer dir
    local rect door
    if not Grid_IsValidId(logicalId) then
        return null
    endif
    if slotId >= 0 then
        return LoadRectHandle(SlotTable, slotId, HT_SLOT_RECT)
    endif
    // 查找空闲槽位
    set i = 0
    loop
        exitwhen i >= SLOT_COUNT
        if not LoadBoolean(SlotTable, i, HT_SLOT_USED) then
            set slotId = i
            exitwhen true
        endif
        set i = i + 1
    endloop
    // 无空闲 → 兜底：回收第一个已绑定槽位
    if slotId < 0 then
        set i = 0
        loop
            exitwhen i >= SLOT_COUNT
            if LoadBoolean(SlotTable, i, HT_SLOT_USED) then
                call Slot_Release(LoadInteger(SlotTable, i, HT_SLOT_LOGICAL))
                set slotId = i
                exitwhen true
            endif
            set i = i + 1
        endloop
    endif
    if slotId < 0 then
        return null
    endif
    // 绑定并创建矩形
    set cell = CreateCellRect(logicalId)
    call SaveBoolean(SlotTable, slotId, HT_SLOT_USED, true)
    call SaveInteger(SlotTable, slotId, HT_SLOT_LOGICAL, logicalId)
    call SaveRectHandle(SlotTable, slotId, HT_SLOT_RECT, cell)
    call SaveInteger(SlotTable, GetHandleId(cell), HT_RECT_LOGICAL, logicalId + 1)
    call SaveInteger(SlotTable, logicalId, HT_LOGICAL_SLOT, slotId + 1)
    set dir = 0
    loop
        exitwhen dir >= 4
        set door = CreateDoorRect(cell, dir)
        call SaveRectHandle(SlotTable, slotId, HT_SLOT_DOOR_RECT + dir, door)
        set dir = dir + 1
    endloop
    set cell = null
    set door = null
    return LoadRectHandle(SlotTable, slotId, HT_SLOT_RECT)
endfunction

// 重置槽位池：释放所有已绑定槽位
function ResetAreaSlot takes nothing returns nothing
    local integer i = 0
    loop
        exitwhen i >= SLOT_COUNT
        if LoadBoolean(SlotTable, i, HT_SLOT_USED) then
            call Slot_Release(LoadInteger(SlotTable, i, HT_SLOT_LOGICAL))
        endif
        set i = i + 1
    endloop
endfunction

endlibrary
#endif
