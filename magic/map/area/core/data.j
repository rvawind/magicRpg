#ifndef AREA_DATA
#define AREA_DATA
#include "nncou\\debug.j"
/*
    区域数据/状态模块（通用框架）

    逻辑层：每个逻辑坐标（logicalId = row*cols+col）永久保存房间类型/状态/怪物池/奖励等数据。
    物理层：区域矩形、门洞矩形、触发器、怪物、祭坛等由 areaSlot 按需绑定，与本模块解耦。

    本模块提供：
    - 房间类型/状态枚举与查询接口；
    - 网格邻接查询（委托 areaGrid）；
    - 配置接口：AreaSetBossroom / AreaAddEnter / AreaAddPeripheralEnters /
      AreaAddBossCandidate / RollBossArea / RegisterRoomType / SetRoomTypeWeight / InitAreaWithEnter；
    - 逻辑 ID 的物理绑定入口 Area_EnsureBound（委托 areaSlot）。

    依赖：areaGrid, areaSlot, DebugLogger
*/
library areaData requires areaGrid, areaSlot, DebugLogger

globals
    // 房间数据（parent key = areaId）
    private hashtable AreaDataTable = InitHashtable()
    // 房间类型权重/已分配计数（parent key = typeId）
    private hashtable AreaTypeTable = InitHashtable()

    // 房间类型（系统保留）
    constant integer ROOM_TYPE_MONSTER = 0
    constant integer ROOM_TYPE_SAFE = 1
    constant integer ROOM_TYPE_BOSS = 2
    constant integer ROOM_TYPE_ENTRY = 3
    // 扩展类型（各关卡共通）
    constant integer ROOM_TYPE_ELITE = 4
    constant integer ROOM_TYPE_MERCHANT = 5

    // 尚未分配类型（InitAreaWithEnter 内部哨兵）
    // 不能复用 0，否则无法区分「未分配」与「怪物房」
    constant integer ROOM_TYPE_UNASSIGNED = -1

    // 无上限标记
    constant integer ROOM_MAX_UNLIMITED = -1

    // 房间状态
    constant integer ROOM_STATE_INACTIVE = 0
    constant integer ROOM_STATE_ACTIVE = 1
    constant integer ROOM_STATE_CLEARED = 2
    constant integer ROOM_STATE_CURSED = 3

    // 区域属性子键（parent key = areaId）
    private constant integer HT_ROOM_TYPE = 1
    private constant integer HT_ROOM_STATE = 2
    private constant integer HT_MONSTER_POOL = 3
    private constant integer HT_MONSTER_CAP = 4
    private constant integer HT_IS_PERIPHERAL = 5
    private constant integer HT_ALIVE_MONSTER = 6
    private constant integer HT_CLEARED_THIS_GAME = 7
    private constant integer HT_AREA_TERRAIN = 8

    // 全局配置子键（parent key = 0）
    private constant integer HT_BOSS_AREA = 200
    private constant integer HT_ENTER_COUNT = 201
    private constant integer HT_CURSE_START_COUNT = 202
    private constant integer HT_AREA_COUNT = 208
    private constant integer HT_ROOM_TYPE_REG_COUNT = 209
    private constant integer HT_BOSS_CAND_COUNT = 210

    // 已注册区域ID列表起始子键（parent key = 0）
    private constant integer HT_AREA_LIST = 500
    // 入口候选列表起始子键
    private constant integer HT_ENTER_LIST = 300
    // 诅咒起始区域列表起始子键
    private constant integer HT_CURSE_START_LIST = 400
    // 已注册房间类型列表起始子键（每个类型占3个连续子键：typeId/minCount/maxCount）
    private constant integer HT_ROOM_TYPE_LIST = 600
    // BOSS 候选区域列表起始子键
    private constant integer HT_BOSS_CAND_LIST = 900

    // 各关卡确定的入口区域ID（parent key = chapterId + 800，子键 0 = areaId）
    private constant integer HT_CHAPTER_ENTER_LIST = 800

    // 房间类型权重存储（AreaTypeTable，parent key = typeId）
    private constant integer HT_RTW_WEIGHT = 0
    private constant integer HT_RTW_ASSIGNED = 1
endglobals


// ===== 查询接口 =====

// 由区域矩形反查逻辑 ID（未绑定返回 -1）
function GetAreaIdByRect takes rect r returns integer
    return Slot_GetLogicalIdByRegionRect(r)
endfunction

// 获取逻辑房间当前绑定的区域矩形（未绑定返回 null）
function GetAreaRect takes integer areaId returns rect
    return Slot_GetRect(areaId)
endfunction

// 获取房间类型
function GetRoomType takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_ROOM_TYPE)
endfunction

// 设置房间类型
function SetRoomType takes integer areaId, integer roomType returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_ROOM_TYPE, roomType)
endfunction

// 获取房间状态
function GetRoomState takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_ROOM_STATE)
endfunction

// 设置房间状态
function SetRoomState takes integer areaId, integer roomState returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_ROOM_STATE, roomState)
endfunction

// 获取怪物池ID
function GetAreaMonsterPool takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_MONSTER_POOL)
endfunction

// 设置怪物池ID
function SetAreaMonsterPool takes integer areaId, integer poolId returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_MONSTER_POOL, poolId)
endfunction

// 获取怪物上限
function GetAreaMonsterCap takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_MONSTER_CAP)
endfunction

// 设置怪物上限
function SetAreaMonsterCap takes integer areaId, integer cap returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_MONSTER_CAP, cap)
endfunction

// 是否外围区域（注册时按网格坐标自动标记，可被 SetAreaPeripheral 覆盖）
function IsAreaPeripheral takes integer areaId returns boolean
    return LoadBoolean(AreaDataTable, areaId, HT_IS_PERIPHERAL)
endfunction

// 设置外围标记
function SetAreaPeripheral takes integer areaId, boolean flag returns nothing
    call SaveBoolean(AreaDataTable, areaId, HT_IS_PERIPHERAL, flag)
endfunction

// 获取存活怪物数
function GetAreaAliveMonsterCount takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_ALIVE_MONSTER)
endfunction

// 设置存活怪物数
function SetAreaAliveMonsterCount takes integer areaId, integer count returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_ALIVE_MONSTER, count)
endfunction

// 本局是否已清空（同一房间不可重复清空）
function IsAreaClearedThisGame takes integer areaId returns boolean
    return LoadBoolean(AreaDataTable, areaId, HT_CLEARED_THIS_GAME)
endfunction

// 标记本局已清空
function SetAreaClearedThisGame takes integer areaId, boolean flag returns nothing
    call SaveBoolean(AreaDataTable, areaId, HT_CLEARED_THIS_GAME, flag)
endfunction

// 获取房间地形编号（0..n-1），未分配返回 -1
function GetAreaTerrain takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_AREA_TERRAIN)
endfunction

// 设置房间地形编号
function SetAreaTerrain takes integer areaId, integer terrain returns nothing
    call SaveInteger(AreaDataTable, areaId, HT_AREA_TERRAIN, terrain)
endfunction

// 邻接区域数量（网格出度）
function GetAreaNeighborCount takes integer areaId returns integer
    local integer count = 0
    local integer dir = 0
    if not Grid_IsValidId(areaId) then
        return 0
    endif
    loop
        exitwhen dir >= 4
        if Grid_GetNeighbor(areaId, dir) >= 0 then
            set count = count + 1
        endif
        set dir = dir + 1
    endloop
    return count
endfunction

// 第 index 个邻接区域ID（按上/下/左/右顺序，越界返回 -1）
function GetAreaNeighbor takes integer areaId, integer index returns integer
    local integer seen = 0
    local integer dir = 0
    local integer nbr
    if index < 0 or not Grid_IsValidId(areaId) then
        return -1
    endif
    loop
        exitwhen dir >= 4
        set nbr = Grid_GetNeighbor(areaId, dir)
        if nbr >= 0 then
            if seen == index then
                return nbr
            endif
            set seen = seen + 1
        endif
        set dir = dir + 1
    endloop
    return -1
endfunction

// 获取BOSS房区域ID（未设置返回 -1）
function GetBossArea takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_BOSS_AREA)
endfunction

// 获取入口候选数量
function GetEnterCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
endfunction

// 获取第 index 个入口候选区域ID
function GetEnterArea takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_ENTER_LIST + index)
endfunction

// 获取诅咒起始区域数量
function GetCurseStartCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_CURSE_START_COUNT)
endfunction

// 获取第 index 个诅咒起始区域ID
function GetCurseStartArea takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_CURSE_START_LIST + index)
endfunction

// 获取已注册区域总数
function GetAreaCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
endfunction

// 获取第 index 个已注册区域ID
function GetAreaByIndex takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_LIST + index)
endfunction

// 获取已注册房间类型数量
function GetRoomTypeRegCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
endfunction

// 将逻辑 ID 转换为调试名称：(row,col)
// 注意：JASS 不允许前向引用，本函数必须定义在所有调用者之前
function GetAreaIdName takes integer areaId returns string
    if Grid_IsValidId(areaId) then
        return "(" + I2S(Grid_GetRow(areaId)) + "," + I2S(Grid_GetCol(areaId)) + ")"
    endif
    if areaId < 0 then
        return "?"
    endif
    return I2S(areaId)
endfunction

// 确保逻辑房已绑定物理槽位；返回槽位ID，失败返回 -1
// BOSS 房使用预留槽位，其余按地形从槽位池分配
function Area_EnsureBound takes integer areaId returns integer
    local integer slotId
    local integer terrain
    if not Grid_IsValidId(areaId) then
        return -1
    endif
    set slotId = Slot_GetSlotOf(areaId)
    if slotId >= 0 then
        return slotId
    endif
    if areaId == GetBossArea() then
        return Slot_AcquireBoss(areaId)
    endif
    set terrain = GetAreaTerrain(areaId)
    if terrain < 0 then
        set terrain = 0
        call DebugLogger_Log(LOG_WARN, "[area] terrain unassigned for " + GetAreaIdName(areaId) + ", fallback to 0")
    endif
    return Slot_Acquire(areaId, terrain)
endfunction

/*
    [Area_GetActiveEnter]
    title = "获取指定关卡入口区域ID"
    description = "获取${指定ID}关卡随机确定的入口区域ID"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = integer
*/
function GetActiveEnter takes integer chapterId returns integer
    return LoadInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0)
endfunction

/*
    [Area_GetActiveEnterRect]
    title = "获取指定关卡入口区域矩形"
    description = "获取${指定ID}关卡随机确定的入口区域矩形，供GUI传送使用；若尚未绑定会自动分配物理槽位"
    category = TC_FRO
    returns = rect
    [[.args]]
    type = integer
*/
function GetActiveEnterRect takes integer chapterId returns rect
    local integer areaId = GetActiveEnter(chapterId)
    if areaId < 0 then
        return null
    endif
    if Area_EnsureBound(areaId) < 0 then
        return null
    endif
    return Slot_GetRect(areaId)
endfunction

// ===== 注册接口 =====

// 注册逻辑区域（只注册逻辑 ID，不再绑定矩形）
// 矩形/门洞由 areaSlot_RegisterPhysicalRoom 在物理层注册
function RegisterArea takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    local integer row
    local integer col
    if not Grid_IsValidId(areaId) then
        call DebugLogger_Log(LOG_WARN, "[area] RegisterArea skipped: invalid id " + I2S(areaId) + " (grid total=" + I2S(Grid_GetTotal()) + ")")
        return
    endif
    // 注意：逻辑 ID 0 与全局配置共用 parent key 0，不能整表清空
    // （全局键为 200+，逐房键为 1..8，此处逐房重建即可）
    if areaId != 0 then
        call FlushChildHashtable(AreaDataTable, areaId)
    endif
    set row = Grid_GetRow(areaId)
    set col = Grid_GetCol(areaId)
    call SaveInteger(AreaDataTable, areaId, HT_ROOM_TYPE, ROOM_TYPE_UNASSIGNED)
    call SaveInteger(AreaDataTable, areaId, HT_ROOM_STATE, ROOM_STATE_INACTIVE)
    call SaveBoolean(AreaDataTable, areaId, HT_CLEARED_THIS_GAME, false)
    call SaveInteger(AreaDataTable, areaId, HT_ALIVE_MONSTER, 0)
    call SaveInteger(AreaDataTable, areaId, HT_AREA_TERRAIN, -1)
    call SaveBoolean(AreaDataTable, areaId, HT_IS_PERIPHERAL, row == 0 or row == Grid_GetRows() - 1 or col == 0 or col == Grid_GetCols() - 1)
    call SaveInteger(AreaDataTable, 0, HT_AREA_LIST + count, areaId)
    call SaveInteger(AreaDataTable, 0, HT_AREA_COUNT, count + 1)
endfunction

// ===== 配置接口（在 InitAreaWithEnter 之前调用） =====

// 设置BOSS房位置
function AreaSetBossroom takes integer areaId returns nothing
    call SaveInteger(AreaDataTable, 0, HT_BOSS_AREA, areaId)
    call SetRoomType(areaId, ROOM_TYPE_BOSS)
endfunction

// 增加一个入口候选区域（自动去重）
function AreaAddEnter takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
    local integer i = 0
    if not Grid_IsValidId(areaId) then
        return
    endif
    loop
        exitwhen i >= count
        if LoadInteger(AreaDataTable, 0, HT_ENTER_LIST + i) == areaId then
            return
        endif
        set i = i + 1
    endloop
    call SaveInteger(AreaDataTable, 0, HT_ENTER_LIST + count, areaId)
    call SaveInteger(AreaDataTable, 0, HT_ENTER_COUNT, count + 1)
endfunction

// 按网格尺寸自动注册外围 8 个起点候选：
//   4 角 + 4 边中点（边中点取 cols/2、rows/2 整数除法）
function AreaAddPeripheralEnters takes nothing returns nothing
    local integer rows = Grid_GetRows()
    local integer cols = Grid_GetCols()
    if rows <= 0 or cols <= 0 then
        return
    endif
    call AreaAddEnter(Grid_GetId(0, 0))
    call AreaAddEnter(Grid_GetId(0, cols - 1))
    call AreaAddEnter(Grid_GetId(rows - 1, 0))
    call AreaAddEnter(Grid_GetId(rows - 1, cols - 1))
    call AreaAddEnter(Grid_GetId(0, cols / 2))
    call AreaAddEnter(Grid_GetId(rows / 2, 0))
    call AreaAddEnter(Grid_GetId(rows / 2, cols - 1))
    call AreaAddEnter(Grid_GetId(rows - 1, cols / 2))
endfunction

// 增加一个 BOSS 候选区域（自动去重）
function AreaAddBossCandidate takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_BOSS_CAND_COUNT)
    local integer i = 0
    if not Grid_IsValidId(areaId) then
        return
    endif
    loop
        exitwhen i >= count
        if LoadInteger(AreaDataTable, 0, HT_BOSS_CAND_LIST + i) == areaId then
            return
        endif
        set i = i + 1
    endloop
    call SaveInteger(AreaDataTable, 0, HT_BOSS_CAND_LIST + count, areaId)
    call SaveInteger(AreaDataTable, 0, HT_BOSS_CAND_COUNT, count + 1)
endfunction

// 从候选列表随机确定 BOSS 房
function RollBossArea takes nothing returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_BOSS_CAND_COUNT)
    if count <= 0 then
        call DebugLogger_Log(LOG_WARN, "[area] RollBossArea skipped: no boss candidates")
        return
    endif
    call AreaSetBossroom(LoadInteger(AreaDataTable, 0, HT_BOSS_CAND_LIST + GetRandomInt(0, count - 1)))
endfunction

// 从入口候选列表中随机确定指定关卡的入口区域（排除 BOSS 房）
function RollActiveEnter takes integer chapterId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
    local integer bossArea = LoadInteger(AreaDataTable, 0, HT_BOSS_AREA)
    local integer attempt = 0
    local integer pick
    if count <= 0 then
        return
    endif
    loop
        set pick = LoadInteger(AreaDataTable, 0, HT_ENTER_LIST + GetRandomInt(0, count - 1))
        if pick != bossArea or attempt >= count then
            call SaveInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0, pick)
            return
        endif
        set attempt = attempt + 1
    endloop
endfunction

// 增加一个诅咒起始区域（Step 5 前保留兼容；外围判定已可自动推导）
function AddCurseStartArea takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_CURSE_START_COUNT)
    call SaveInteger(AreaDataTable, 0, HT_CURSE_START_LIST + count, areaId)
    call SaveBoolean(AreaDataTable, areaId, HT_IS_PERIPHERAL, true)
    call SaveInteger(AreaDataTable, 0, HT_CURSE_START_COUNT, count + 1)
endfunction

// 注册房间类型及上下限（maxCount=-1 表示无上限）
// 怪物房建议显式注册为 (30, -1)，以免 minCount 阶段尚未分配时被权重逻辑误判
function RegisterRoomType takes integer typeId, integer minCount, integer maxCount returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 0, typeId)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 1, minCount)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 2, maxCount)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT, count + 1)
endfunction

// 设置某房间类型的权重（不设置则默认为0，不参与随机分配）
function SetRoomTypeWeight takes integer typeId, integer weight returns nothing
    call SaveInteger(AreaTypeTable, typeId, HT_RTW_WEIGHT, weight)
endfunction

// ===== 初始化接口 =====

// 获取某类型已分配数量
private function GetAssignedCount takes integer typeId returns integer
    return LoadInteger(AreaTypeTable, typeId, HT_RTW_ASSIGNED)
endfunction

// 增加某类型已分配数量
private function IncAssignedCount takes integer typeId returns nothing
    call SaveInteger(AreaTypeTable, typeId, HT_RTW_ASSIGNED, LoadInteger(AreaTypeTable, typeId, HT_RTW_ASSIGNED) + 1)
endfunction

// 某类型是否已注册
private function IsRoomTypeRegistered takes integer typeId returns boolean
    local integer count = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    loop
        exitwhen i >= count
        if LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0) == typeId then
            return true
        endif
        set i = i + 1
    endloop
    return false
endfunction

// 获取某类型的注册上限（-1=无上限，未注册返回0）
private function GetRegisteredMax takes integer typeId returns integer
    local integer count = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    loop
        exitwhen i >= count
        if LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0) == typeId then
            return LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 2)
        endif
        set i = i + 1
    endloop
    return 0
endfunction

// 计算某类型的有效权重（衰减公式：weight × (max - assigned) / max）
private function GetEffectiveWeight takes integer typeId returns real
    local integer weight = LoadInteger(AreaTypeTable, typeId, HT_RTW_WEIGHT)
    local integer assigned = GetAssignedCount(typeId)
    local integer maxCount = GetRegisteredMax(typeId)
    if not IsRoomTypeRegistered(typeId) then
        // 未注册类型按无上限处理（怪物房默认兜底）
        return I2R(weight)
    endif
    if maxCount >= 0 and assigned >= maxCount then
        return 0.0
    endif
    if maxCount == ROOM_MAX_UNLIMITED then
        return I2R(weight)
    endif
    if maxCount <= 0 then
        return 0.0
    endif
    return I2R(weight) * I2R(maxCount - assigned) / I2R(maxCount)
endfunction

// 按衰减权重随机分配一个类型
// 有效权重 = 原始权重 × (maxCount - assignedCount) / maxCount（无上限不衰减）
private function RollRoomTypeByWeight takes nothing returns integer
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local real monsterEffective = GetEffectiveWeight(ROOM_TYPE_MONSTER)
    local real totalWeight = monsterEffective
    local real roll
    local real accumulated
    local integer i = 0
    local integer typeId
    local real effective

    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        if typeId != ROOM_TYPE_MONSTER then
            set totalWeight = totalWeight + GetEffectiveWeight(typeId)
        endif
        set i = i + 1
    endloop

    if totalWeight <= 0.0 then
        call IncAssignedCount(ROOM_TYPE_MONSTER)
        return ROOM_TYPE_MONSTER
    endif

    set roll = GetRandomReal(0.0, totalWeight)
    if roll < monsterEffective then
        call IncAssignedCount(ROOM_TYPE_MONSTER)
        return ROOM_TYPE_MONSTER
    endif

    set accumulated = monsterEffective
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        if typeId != ROOM_TYPE_MONSTER then
            set effective = GetEffectiveWeight(typeId)
            set accumulated = accumulated + effective
            if roll < accumulated then
                call IncAssignedCount(typeId)
                return typeId
            endif
        endif
        set i = i + 1
    endloop

    // 浮点误差兜底
    call IncAssignedCount(ROOM_TYPE_MONSTER)
    return ROOM_TYPE_MONSTER
endfunction

// 初始化所有区域：保证 minCount -> 衰减权重分配剩余 -> 随机地形
// 必须在 RegisterArea / RollBossArea / RollActiveEnter / RegisterRoomType / SetRoomTypeWeight 之后调用
// chapterId 用于读取本次游戏的激活入口；仅激活入口是 ROOM_TYPE_ENTRY，其余入口候选正常参与分配
function InitAreaWithEnter takes integer chapterId returns nothing
    local integer total = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    local integer bossArea = LoadInteger(AreaDataTable, 0, HT_BOSS_AREA)
    local integer activeEnter = LoadInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0)
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer terrainCount = Slot_GetTerrainTypeCount()
    local integer i = 0
    local integer k = 0
    local integer j = 0
    local integer areaId
    local integer typeId
    local integer minCount
    local integer assigned
    local integer nMonster = 0
    local integer nSafe = 0
    local integer nElite = 0
    local integer nBoss = 0
    local integer nEntry = 0
    local integer nOther = 0

    if total <= 0 then
        call DebugLogger_Log(LOG_WARN, "[area] InitAreaWithEnter skipped: no areas registered")
        return
    endif
    if LoadInteger(AreaTypeTable, ROOM_TYPE_MONSTER, HT_RTW_WEIGHT) == 0 then
        call SetRoomTypeWeight(ROOM_TYPE_MONSTER, 700)
    endif
    if terrainCount <= 0 then
        set terrainCount = 1
        call DebugLogger_Log(LOG_WARN, "[area] no physical rooms registered; all rooms fallback to terrain 0")
    endif

    // 重置已分配计数
    call SaveInteger(AreaTypeTable, ROOM_TYPE_MONSTER, HT_RTW_ASSIGNED, 0)
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        call SaveInteger(AreaTypeTable, typeId, HT_RTW_ASSIGNED, 0)
        set i = i + 1
    endloop

    // 第一步：所有区域先置为 UNASSIGNED，仅保留 BOSS 与激活入口
    set k = 0
    loop
        exitwhen k >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)
        if areaId == bossArea then
            call SetRoomType(areaId, ROOM_TYPE_BOSS)
        elseif areaId == activeEnter then
            call SetRoomType(areaId, ROOM_TYPE_ENTRY)
        else
            call SetRoomType(areaId, ROOM_TYPE_UNASSIGNED)
        endif
        set k = k + 1
    endloop

    // 第二步：保证每种已注册类型的 minCount
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        set minCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 1)
        set assigned = 0
        set k = 0
        loop
            exitwhen assigned >= minCount or k >= total
            set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)
            if GetRoomType(areaId) == ROOM_TYPE_UNASSIGNED then
                call SetRoomType(areaId, typeId)
                call IncAssignedCount(typeId)
                set assigned = assigned + 1
            endif
            set k = k + 1
        endloop
        set i = i + 1
    endloop

    // 第三步：剩余区域按衰减权重分配
    set k = 0
    loop
        exitwhen k >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)
        if GetRoomType(areaId) == ROOM_TYPE_UNASSIGNED then
            call SetRoomType(areaId, RollRoomTypeByWeight())
        endif
        set k = k + 1
    endloop

    // 第四步：随机分配地形（0 .. terrainCount-1）
    set k = 0
    loop
        exitwhen k >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)
        if GetAreaTerrain(areaId) < 0 then
            call SetAreaTerrain(areaId, GetRandomInt(0, terrainCount - 1))
        endif
        set k = k + 1
    endloop

    // 第五步：激活入口的直接邻居中的 ELITE 降级为 MONSTER
    if activeEnter >= 0 then
        set j = 0
        loop
            exitwhen j >= 4
            set typeId = Grid_GetNeighbor(activeEnter, j)
            if typeId >= 0 and typeId != bossArea and GetRoomType(typeId) == ROOM_TYPE_ELITE then
                call SetRoomType(typeId, ROOM_TYPE_MONSTER)
            endif
            set j = j + 1
        endloop
    endif

    // 统计并输出分布
    set k = 0
    loop
        exitwhen k >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)
        set typeId = GetRoomType(areaId)
        if typeId == ROOM_TYPE_MONSTER then
            set nMonster = nMonster + 1
        elseif typeId == ROOM_TYPE_SAFE then
            set nSafe = nSafe + 1
        elseif typeId == ROOM_TYPE_ELITE then
            set nElite = nElite + 1
        elseif typeId == ROOM_TYPE_BOSS then
            set nBoss = nBoss + 1
        elseif typeId == ROOM_TYPE_ENTRY then
            set nEntry = nEntry + 1
        else
            set nOther = nOther + 1
        endif
        set k = k + 1
    endloop
    call DebugLogger_Log(LOG_INFO, "[area] distribution total=" + I2S(total) + " monster=" + I2S(nMonster) + " safe=" + I2S(nSafe) + " elite=" + I2S(nElite) + " boss=" + I2S(nBoss) + " entry=" + I2S(nEntry) + " other=" + I2S(nOther) + " terrains=" + I2S(terrainCount))
    call DebugLogger_Log(LOG_INFO, "[area] active enter=" + GetAreaIdName(activeEnter) + " boss=" + GetAreaIdName(bossArea))
endfunction

// 重置区域数据：清空所有已注册区域、全局配置和权重数据
// 供 ChapterManager 在关卡切换时调用，确保新旧关卡数据不互相干扰
function ResetAreaData takes nothing returns nothing
    local integer total = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    local integer areaId
    local integer typeId

    // 先清理房间类型权重数据（读取类型列表前不能清空 parent key 0）
    // 独立表避免与 areaId 冲突
    call FlushChildHashtable(AreaTypeTable, ROOM_TYPE_MONSTER)
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        call FlushChildHashtable(AreaTypeTable, typeId)
        set i = i + 1
    endloop

    // 清理每个已注册区域的数据（parent key = areaId）
    // areaId = 0 与全局配置共用 parent key 0，跳过；其逐房键会随全局清理一并删除
    set i = 0
    loop
        exitwhen i >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + i)
        if areaId != 0 then
            call FlushChildHashtable(AreaDataTable, areaId)
        endif
        set i = i + 1
    endloop

    // 清理全局配置（parent key = 0）
    call FlushChildHashtable(AreaDataTable, 0)

    // 清理各关卡入口缓存（parent key = chapterId + HT_CHAPTER_ENTER_LIST）
    set i = 0
    loop
        exitwhen i >= total
        call FlushChildHashtable(AreaDataTable, i + HT_CHAPTER_ENTER_LIST)
        set i = i + 1
    endloop
endfunction

endlibrary
#endif
