#ifndef AREA_EXIT
#define AREA_EXIT
#include "nncou\\debug.j"
/*
    区域门洞传送模块（通用框架）

    Step 3 起废弃旧的手动出口注册与 3 秒引导：
    - 连通关系由 areaGrid 的邻接自动决定；
    - 每个物理槽位注册 4 个门洞矩形（只用于方向判定与特效，**不再**监听走进事件）；
    - 传送统一由 emergency.j 的共通技能触发：站进门洞矩形施法；
      源房可通行（安全/入口/BOSS/已清空）时免费，未清空时按紧急穿越扣代价；
    - 未清空房间的连通方向显示橙色/红色封锁特效；无邻居方向只封路径，
      有模板障碍物就克隆，没有就什么都不显示（不再共用红色特效，避免误判成 4 个出口）。

    本模块只负责门洞的视觉与通行状态；TryTraverse 供 emergency.j 复用
    （bypassGate=true 表示允许在未清空时通过，代价由调用方决定）。

    关闭门洞的障碍物（Step 3 补充）：
    - 网格里「没有这条边」的方向，洞口的实体障碍物由本模块管理；
    - 模板来源：每个地形把 4 个门洞缺口所需的障碍物（可破坏物）预先摆在该地形的
      门洞模板矩形（A1/B1/C1/D1 内）里，初始化时读取类型与相对方位，然后删除原件；
    - 绑定时按模板重建到目标房间，方向变为可通行时再删除；
    - 「有邻居但房间未清空」的方向不放置障碍物（否则英雄站不进矩形，紧急穿越失效），
      只显示红色封锁特效；「没有这条边」的方向反过来：只有障碍物（模板存在时），没有特效。
    - 限制：只能读取可破坏物（destructable），纯装饰物（doodad）触发器不可见；
      API 读不到原始角度/缩放，重建统一 0°、1.0 缩放，变体随机。

    依赖：areaData, areaEnter, areaSlot, areaGrid, DebugLogger
*/
library areaExit requires areaData, areaEnter, areaSlot, areaGrid, DebugLogger

globals
    // 每个槽位 4 个方向；槽位上限 64 -> 256（门洞特效/路径快照的索引上限）
    private constant integer MAX_DOOR_TRIGGERS = 256
    private effect array DoorEffect

    // 门洞常驻特效（可用/封锁）。占位符，可在 WE 中替换
    private constant string EXIT_EFFECT_AVAILABLE = "Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTo.mdl"
    private constant string EXIT_EFFECT_LOCKED = "Abilities\\Spells\\Other\\Doom\\DoomTarget.mdl"

    // ===== 关闭门洞的障碍物 =====
    // 模板登记：parent key = terrain * 4 + dir, child 0 = 模板矩形
    private hashtable DecorTemplateRectTable = InitHashtable()
    // 模板数据：parent key = terrain * 4 + dir
    //   child 0 = count；child 1+i*3 = typeId，2+i*3 = dx，3+i*3 = dy（相对门洞矩形中心）
    private hashtable DecorTemplateTable = InitHashtable()
    // 实例数据：parent key = slot * 4 + dir
    //   child 0 = count；child 1+i = destructable
    private hashtable DecorInstTable = InitHashtable()
    private constant integer DECOR_MAX_PER_DIR = 16

    // ===== 无邻居方向的动态路径阻断 =====
    // 阻挡由 SetTerrainPathable 完成；模板障碍物只是可选的手工视觉。
    // 该方向没有模板时不加任何特效：门洞常驻特效里「红火」专指「有路但房间没清空」，
    // 无通路方向复用同一模型会让玩家误以为 4 个方向都能走。
    // 数据：parent key = slot * 4 + dir
    //   child 0 = 采样点数；child 1+i*3 = x，2+i*3 = y，3+i*3 = 原始可通行(0/1)
    private hashtable DoorPathingTable = InitHashtable()
    private constant real DOOR_PATH_SAMPLE_STEP = 32.0
    private constant integer DOOR_PATH_MAX_SAMPLES = 512

    // 枚举回调上下文
    private rect DecorEnumRect = null
    private integer DecorEnumKey = -1
    private boolean DecorEnumStore = false
    private integer DecorRemoved = 0
endglobals

// ===== 关闭门洞的障碍物：注册模板 =====

// 登记某地形某方向的门洞模板矩形（参考房间内，矩形中的可破坏物视为该方向的闭门障碍物）
function RegisterDoorDecorTemplate takes integer terrain, integer dir, rect r returns nothing
    if terrain < 0 or dir < 0 or dir > 3 or r == null then
        return
    endif
    call SaveRectHandle(DecorTemplateRectTable, terrain * 4 + dir, 0, r)
endfunction

// ===== 查询 =====

// 源房间是否允许通过门洞移动：安全区/入口区/BOSS 中转房，或已清空的房间
// BOSS 中转房本身不刷怪，等价于安全房
function IsSourceTraversable takes integer sourceId returns boolean
    local integer roomType = GetRoomType(sourceId)
    if roomType == ROOM_TYPE_SAFE or roomType == ROOM_TYPE_ENTRY or roomType == ROOM_TYPE_BOSS then
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

// 枚举回调：读取模板障碍物后删除原件（Store=false 时只删除）
private function Trig_EnumDoorDecor takes nothing returns nothing
    local destructable d = GetEnumDestructable()
    local integer n
    if d == null then
        return
    endif
    if DecorEnumStore then
        set n = LoadInteger(DecorTemplateTable, DecorEnumKey, 0)
        if n < DECOR_MAX_PER_DIR then
            call SaveInteger(DecorTemplateTable, DecorEnumKey, 1 + n * 3, GetDestructableTypeId(d))
            call SaveReal(DecorTemplateTable, DecorEnumKey, 2 + n * 3, GetDestructableX(d) - GetRectCenterX(DecorEnumRect))
            call SaveReal(DecorTemplateTable, DecorEnumKey, 3 + n * 3, GetDestructableY(d) - GetRectCenterY(DecorEnumRect))
            call SaveInteger(DecorTemplateTable, DecorEnumKey, 0, n + 1)
        else
            call DebugLogger_Log(LOG_WARN, "[exit] door decor overflow: key=" + I2S(DecorEnumKey) + " max=" + I2S(DECOR_MAX_PER_DIR))
        endif
    endif
    set DecorRemoved = DecorRemoved + 1
    call RemoveDestructable(d)
    set d = null
endfunction

/*
    读取门洞模板中的障碍物并删除原件，同时清空所有物理房门洞内的手工障碍物。
    必须在 InitAreaExits 建触发器之前调用（由 InitAreaExits 自动调用）。
    同一张地图内重复初始化时，模板已捕获则跳过读取（原件已删除，避免覆盖数据）。
*/
function CaptureDoorDecor takes nothing returns nothing
    local integer terrain = 0
    local integer terrainCount = Slot_GetTerrainTypeCount()
    local integer slotCount = Slot_GetCount()
    local integer dir
    local integer key
    local integer slotId
    local rect r

    set DecorRemoved = 0
    loop
        exitwhen terrain >= terrainCount
        set dir = 0
        loop
            exitwhen dir >= 4
            set key = terrain * 4 + dir
            set r = LoadRectHandle(DecorTemplateRectTable, key, 0)
            if r != null and LoadInteger(DecorTemplateTable, key, 0) <= 0 then
                set DecorEnumRect = r
                set DecorEnumKey = key
                set DecorEnumStore = true
                call EnumDestructablesInRect(r, null, function Trig_EnumDoorDecor)
                if LoadInteger(DecorTemplateTable, key, 0) > 0 then
                    call DebugLogger_Log(LOG_INFO, "[exit] door decor template terrain=" + I2S(terrain) + " dir=" + I2S(dir) + " count=" + I2S(LoadInteger(DecorTemplateTable, key, 0)))
                endif
            endif
            set dir = dir + 1
        endloop
        set terrain = terrain + 1
    endloop

    // 所有物理房的 4 个门洞内不保留手工障碍物：之后的障碍物一律由模板重建
    set DecorEnumStore = false
    set slotId = 0
    loop
        exitwhen slotId >= slotCount
        set dir = 0
        loop
            exitwhen dir >= 4
            set r = Slot_GetSlotDoor(slotId, dir)
            if r != null then
                set DecorEnumRect = r
                call EnumDestructablesInRect(r, null, function Trig_EnumDoorDecor)
            endif
            // 上一关重建的实例句柄全部作废
            call FlushChildHashtable(DecorInstTable, slotId * 4 + dir)
            set dir = dir + 1
        endloop
        set slotId = slotId + 1
    endloop

    call DebugLogger_Log(LOG_INFO, "[exit] CaptureDoorDecor done: removed=" + I2S(DecorRemoved))
    set DecorEnumRect = null
    set DecorEnumKey = -1
    set r = null
endfunction

// 清除某槽位某方向的障碍物实例（index = slot * 4 + dir）
private function ClearDoorDecorAt takes integer index returns nothing
    local integer n = LoadInteger(DecorInstTable, index, 0)
    local integer i = 0
    local destructable d
    loop
        exitwhen i >= n
        set d = LoadDestructableHandle(DecorInstTable, index, 1 + i)
        if d != null then
            call RemoveDestructable(d)
            set d = null
        endif
        set i = i + 1
    endloop
    call FlushChildHashtable(DecorInstTable, index)
endfunction

// 按地形模板在槽位的某方向重建闭门障碍物
private function CreateSlotDoorDecor takes integer slotId, integer dir, integer terrain returns nothing
    local integer tkey
    local integer ikey
    local integer n
    local integer i
    local integer created = 0
    local integer typeId
    local real dx
    local real dy
    local real cx
    local real cy
    local rect door
    local destructable d
    if slotId < 0 or dir < 0 or dir > 3 or terrain < 0 then
        return
    endif
    set tkey = terrain * 4 + dir
    set n = LoadInteger(DecorTemplateTable, tkey, 0)
    if n <= 0 then
        return
    endif
    set door = Slot_GetSlotDoor(slotId, dir)
    if door == null then
        set door = null
        return
    endif
    set cx = GetRectCenterX(door)
    set cy = GetRectCenterY(door)
    set ikey = slotId * 4 + dir
    set i = 0
    loop
        exitwhen i >= n
        set typeId = LoadInteger(DecorTemplateTable, tkey, 1 + i * 3)
        set dx = LoadReal(DecorTemplateTable, tkey, 2 + i * 3)
        set dy = LoadReal(DecorTemplateTable, tkey, 3 + i * 3)
        // 原始角度/缩放/变体读不到：统一 0° / 1.0；先随机变体，失败再退回 0
        set d = CreateDestructable(typeId, cx + dx, cy + dy, 0.0, 1.0, GetRandomInt(0, 9))
        if d == null then
            set d = CreateDestructable(typeId, cx + dx, cy + dy, 0.0, 1.0, 0)
        endif
        if d != null then
            // 障碍物只用于阻挡与观感，禁止被玩家破坏
            call SetDestructableInvulnerable(d, true)
            call SaveDestructableHandle(DecorInstTable, ikey, 1 + i, d)
            set created = created + 1
        endif
        set i = i + 1
    endloop
    call SaveInteger(DecorInstTable, ikey, 0, created)
    if created < n then
        call DebugLogger_Log(LOG_WARN, "[exit] door decor create failed: slot=" + I2S(slotId) + " dir=" + I2S(dir) + " created=" + I2S(created) + "/" + I2S(n))
    endif
    set door = null
    set d = null
endfunction

// ===== 无邻居方向：动态路径阻断 =====

// 采样门洞矩形并记录原始可通行状态（必须在删除模板障碍物之后、生成门洞障碍物之前调用）
private function CaptureDoorPathingAt takes integer index, rect r returns nothing
    local real minX = GetRectMinX(r) + DOOR_PATH_SAMPLE_STEP / 2.0
    local real maxX = GetRectMaxX(r) - DOOR_PATH_SAMPLE_STEP / 2.0
    local real minY = GetRectMinY(r) + DOOR_PATH_SAMPLE_STEP / 2.0
    local real maxY = GetRectMaxY(r) - DOOR_PATH_SAMPLE_STEP / 2.0
    local real x
    local real y
    local integer n = 0
    // 矩形比采样间距还小时只取中心点
    if minX > maxX then
        set minX = GetRectCenterX(r)
        set maxX = minX
    endif
    if minY > maxY then
        set minY = GetRectCenterY(r)
        set maxY = minY
    endif
    call FlushChildHashtable(DoorPathingTable, index)
    set y = minY
    loop
        exitwhen y > maxY or n >= DOOR_PATH_MAX_SAMPLES
        set x = minX
        loop
            exitwhen x > maxX or n >= DOOR_PATH_MAX_SAMPLES
            call SaveReal(DoorPathingTable, index, 1 + n * 3, x)
            call SaveReal(DoorPathingTable, index, 2 + n * 3, y)
            // IsTerrainPathable 返回 true = 路径关闭 = 不可通行（与函数名相反）；
            // 这里存"是否可通行"，恢复时直接作为 SetTerrainPathable 的 flag（true = 通行）
            if IsTerrainPathable(x, y, PATHING_TYPE_WALKABILITY) then
                call SaveInteger(DoorPathingTable, index, 3 + n * 3, 0)
            else
                call SaveInteger(DoorPathingTable, index, 3 + n * 3, 1)
            endif
            set n = n + 1
            set x = x + DOOR_PATH_SAMPLE_STEP
        endloop
        set y = y + DOOR_PATH_SAMPLE_STEP
    endloop
    call SaveInteger(DoorPathingTable, index, 0, n)
endfunction

// 门洞原始路径状态只在「第一次需要封锁该方向」时采样：
// 初始化线程里逐点采样 80 个门洞会超过 JASS 单线程字节码上限（约 30 万条），
// 线程会被中止，导致后续触发器都建不出来。分散到各槽位首次绑定时开销可忽略。
// 必须在 CreateSlotDoorDecor 之前调用，否则快照会把障碍物自身的阻挡当成原始状态。
private function EnsureDoorPathingCaptured takes integer index returns nothing
    local integer slotId
    local rect door
    if LoadInteger(DoorPathingTable, index, 0) > 0 then
        return
    endif
    set slotId = index / 4
    set door = Slot_GetSlotDoor(slotId, index - slotId * 4)
    if door != null then
        call CaptureDoorPathingAt(index, door)
    else
        call DebugLogger_Log(LOG_WARN, "[exit] pathing capture skipped: no door rect slot=" + I2S(slotId) + " dir=" + I2S(index - slotId * 4))
    endif
    set door = null
endfunction

// blocked=true：把门洞区域改为不可通行（SetTerrainPathable flag=false）；
// blocked=false：恢复采样时记录的原始状态（flag=true 表示恢复通行，与 IsTerrainPathable 的极性相反）
private function SetDoorPathingBlocked takes integer index, boolean blocked returns nothing
    local integer n = LoadInteger(DoorPathingTable, index, 0)
    local integer i = 0
    local real x
    local real y
    local boolean orig
    loop
        exitwhen i >= n
        set x = LoadReal(DoorPathingTable, index, 1 + i * 3)
        set y = LoadReal(DoorPathingTable, index, 2 + i * 3)
        if blocked then
            call SetTerrainPathable(x, y, PATHING_TYPE_WALKABILITY, false)
        else
            set orig = LoadInteger(DoorPathingTable, index, 3 + i * 3) != 0
            call SetTerrainPathable(x, y, PATHING_TYPE_WALKABILITY, orig)
        endif
        set i = i + 1
    endloop
endfunction

// 刷新某槽位的门洞特效与闭门障碍物（绑定变化或房间状态变化后调用）
function RefreshSlotDoors takes integer slotId returns nothing
    local integer logicalId
    local integer terrain
    local integer dir
    local integer decorCount
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
        call ClearDoorDecorAt(slotId * 4 + dir)
        // 先恢复原始地形，再按当前绑定重新判定
        call SetDoorPathingBlocked(slotId * 4 + dir, false)
        set dir = dir + 1
    endloop

    set logicalId = Slot_GetLogicalId(slotId)
    if logicalId < 0 then
        return
    endif

    set terrain = Slot_GetSlotTerrain(slotId)
    set dir = 0
    loop
        exitwhen dir >= 4
        if Grid_GetNeighbor(logicalId, dir) >= 0 then
            // 网格中真实连通：显示门洞特效（可通行 / 未清空封锁）
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
        else
            // 网格里没有这条边：只做动态路径阻断
            // 有模板障碍物才克隆上去；没有模板就什么都不加（不要再用「未清空」同款红火，
            // 否则玩家分不清「清完能走」和「根本没有路」）。
            // 先快照原始路径（此时门洞里还没有克隆障碍物），再生成障碍物并阻断
            call EnsureDoorPathingCaptured(slotId * 4 + dir)
            set decorCount = LoadInteger(DecorTemplateTable, terrain * 4 + dir, 0)
            if decorCount > 0 then
                call CreateSlotDoorDecor(slotId, dir, terrain)
            endif
            call SetDoorPathingBlocked(slotId * 4 + dir, true)
        endif
        set dir = dir + 1
    endloop
    set door = null
endfunction

// 清除某槽位的门洞特效与障碍物（槽位释放后调用）
function ClearSlotDoors takes integer slotId returns nothing
    local integer dir = 0
    if slotId < 0 then
        return
    endif
    loop
        exitwhen dir >= 4
        call DestroyDoorEffect(slotId * 4 + dir)
        call ClearDoorDecorAt(slotId * 4 + dir)
        call SetDoorPathingBlocked(slotId * 4 + dir, false)
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
    bypassGate = false：要求源房间可通行（安全/入口/已清空），保留给未来的
                       传送阵房等自动传送场景；
    bypassGate = true：允许在未清空时穿越，代价由调用方（emergency.j）决定。
    Step 3.6 起「走进门洞」不再触发传送，本函数只由共通技能调用。
    落点在目标房「通往源房」的门洞中心（不是房间中心）。
    返回是否成功传送。
*/
function TryTraverse takes unit u, integer sourceId, integer dir, boolean bypassGate returns boolean
    local integer targetId
    local integer targetSlot
    local rect targetRect
    local rect targetDoor
    local player p
    local real x
    local real y
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

    // 落点：目标房中「通往源房」的门洞中心（即刚穿过的那条通道的另一端），
    // 而不是房间中心——从 (0,0) 向下进 (1,0)，就落在 (1,0) 的上门洞里。
    // 门洞矩形缺失时退回房间中心（不变量被破坏，打 WARN）。
    set targetDoor = Slot_GetSlotDoor(targetSlot, Grid_OppositeDir(dir))
    if targetDoor != null then
        set x = GetRectCenterX(targetDoor)
        set y = GetRectCenterY(targetDoor)
    else
        set x = GetRectCenterX(targetRect)
        set y = GetRectCenterY(targetRect)
        call DebugLogger_Log(LOG_WARN, "[exit] arrival door missing, fallback to rect center " + GetAreaIdName(targetId) + " dir=" + I2S(Grid_OppositeDir(dir)) + " slot=" + I2S(targetSlot))
    endif

    set p = GetOwningPlayer(u)
    // 先授权离开：SetUnitPosition 同步触发源房 leave 守卫，守卫必须放行
    call AllowPlayerLeaveAreaOnce(p)
    call SetUnitPosition(u, x, y)
    call DestroyEffect(AddSpecialEffectTarget("Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTarget.mdl", u, "origin"))
    if bypassGate then
        call DebugLogger_LogKey("[exit] emergency teleport " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId) + " slot=" + I2S(targetSlot))
    else
        call DebugLogger_LogKey("[exit] teleport " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId) + " slot=" + I2S(targetSlot))
    endif

    // 源房若已清空/未激活且无玩家，立即释放（ACTIVE/CURSED 保留）
    call ReleaseAreaIfIdle(sourceId)

    set p = null
    set targetRect = null
    set targetDoor = null
    return true
endfunction

// ===== 初始化 / 重置 =====

// 初始化门洞系统：捕获闭门障碍物模板，并为已绑定槽位刷新门洞特效。
// Step 3.6 起不再为门洞创建「走进即传送」触发器——传送统一由技能触发，
// 门洞矩形只用于判定施法时朝向哪个方向（FindDoorDirAtPosition）。
function InitAreaExits takes nothing returns nothing
    local integer slotCount = Slot_GetCount()
    local integer slotId = 0
    // 先读取并清空模板/门洞里的手工障碍物，后续按门洞状态重建
    call CaptureDoorDecor()
    // 门洞原始路径状态不在这里采样：80 个门洞逐点采样会撑爆单线程字节码上限，
    // 改为各方向首次需要封锁时懒采样（EnsureDoorPathingCaptured）
    loop
        exitwhen slotId >= slotCount
        if Slot_GetLogicalId(slotId) >= 0 then
            call RefreshSlotDoors(slotId)
        endif
        set slotId = slotId + 1
    endloop
    call DebugLogger_LogKey("[exit] InitAreaExits done: slots=" + I2S(slotCount))
endfunction

// 重置门洞系统：清空常驻特效、闭门障碍物实例与路径快照
function ResetAreaExit takes nothing returns nothing
    local integer slotCount = Slot_GetCount()
    local integer i = 0
    local integer limit = slotCount * 4
    if limit > MAX_DOOR_TRIGGERS then
        set limit = MAX_DOOR_TRIGGERS
    endif
    loop
        exitwhen i >= limit
        call DestroyDoorEffect(i)
        call ClearDoorDecorAt(i)
        call SetDoorPathingBlocked(i, false)
        // 下一关清理/重建障碍物后会重新懒采样，旧快照不再有效
        call FlushChildHashtable(DoorPathingTable, i)
        set i = i + 1
    endloop
    call DebugLogger_Log(LOG_TRACE, "[exit] ResetAreaExit done: slots=" + I2S(slotCount))
endfunction

// ===== 兼容占位（旧接口） =====

// 旧接口：Step 3 起传送为瞬时，保留空实现避免 GUI/旧配置编译失败
function SetAreaExitDelay takes real delay returns nothing
endfunction

function SetAreaExitFastDelay takes real delay returns nothing
endfunction

endlibrary
#endif
