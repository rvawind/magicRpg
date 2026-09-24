#ifndef AREA_DATA

#define AREA_DATA
/*
    区域数据/状态模块（通用框架）

    提供房间类型/状态枚举、hashtable 存储和通用查询/设置接口。
    提供配置接口：AreaSetBossroom / AreaAddEnter / AddCurseStartArea / RegisterRoomType / SetRoomTypeWeight / InitArea。
    房间类型可扩展：MONSTER/SAFE/BOSS 为系统保留，其余类型由外部注册。
    具体大区域的常量和配置调用放在各自的初始化文件中（如 forest.j）。
*/
library areaData

globals
    private hashtable AreaDataTable = InitHashtable()

    // 房间类型（系统保留）
    constant integer ROOM_TYPE_MONSTER = 0
    constant integer ROOM_TYPE_SAFE = 1
    constant integer ROOM_TYPE_BOSS = 2
    constant integer ROOM_TYPE_ENTRY = 3
    // 扩展类型（各关卡共通）
    constant integer ROOM_TYPE_ELITE = 4
    constant integer ROOM_TYPE_MERCHANT = 5

    // 无上限标记
    constant integer ROOM_MAX_UNLIMITED = -1

    // 房间状态
    constant integer ROOM_STATE_INACTIVE = 0
    constant integer ROOM_STATE_ACTIVE = 1
    constant integer ROOM_STATE_CLEARED = 2
    constant integer ROOM_STATE_CURSED = 3

    // 区域属性子键（parent key = areaId）
    private constant integer HT_RECT = 0
    private constant integer HT_ROOM_TYPE = 1
    private constant integer HT_ROOM_STATE = 2
    private constant integer HT_MONSTER_POOL = 3
    private constant integer HT_MONSTER_CAP = 4
    private constant integer HT_IS_PERIPHERAL = 5
    private constant integer HT_ALIVE_MONSTER = 6
    private constant integer HT_CLEARED_THIS_GAME = 7
    private constant integer HT_NEIGHBOR_COUNT = 100

    // 全局配置子键（parent key = 0）
    private constant integer HT_BOSS_AREA = 200
    private constant integer HT_ENTER_COUNT = 201
    private constant integer HT_CURSE_START_COUNT = 202
    private constant integer HT_TOTAL_ASSIGNABLE = 207
    private constant integer HT_AREA_COUNT = 208
    private constant integer HT_ROOM_TYPE_REG_COUNT = 209

    // 已注册区域ID列表起始子键（parent key = 0）
    private constant integer HT_AREA_LIST = 500
    // 入口列表起始子键
    private constant integer HT_ENTER_LIST = 300
    // 诅咒起始区域列表起始子键
    private constant integer HT_CURSE_START_LIST = 400

    // 已注册房间类型列表起始子键（parent key = 0）
    // 每个类型占3个连续子键：typeId / minCount / maxCount
    private constant integer HT_ROOM_TYPE_LIST = 600

    // 各关卡确定的入口区域ID（parent key = chapterId，子键 0 = areaId）
    private constant integer HT_CHAPTER_ENTER_LIST = 800

    // 出口注册列表（parent key = 0）
    private constant integer HT_AREA_EXIT_COUNT = 730
    // 每个出口占3个连续子键：exitRect / targetRect / sourceAreaId
    private constant integer HT_AREA_EXIT_LIST = 731

        
    // ===== 房间类型注册表内部子键偏移 =====
    // 对于 HT_ROOM_TYPE_LIST + N*3 + offset：
    //   +0 = typeId
    //   +1 = minCount
    //   +2 = maxCount

    // 房间类型权重存储：parent key = typeId，子键固定
    //   HT_RTW_WEIGHT = 权重值
    //   HT_RTW_ASSIGNED = 已分配数量
    private constant integer HT_RTW_WEIGHT = 0
    private constant integer HT_RTW_ASSIGNED = 1
endglobals


// ===== 查询接口 =====

// 根据区域矩形反查区域ID，未找到返回 -1
function GetAreaIdByRect takes rect r returns integer
    if r == null then
        return -1
    endif
    return LoadInteger(AreaDataTable, GetHandleId(r), 0)
endfunction

// 获取区域矩形
function GetAreaRect takes integer areaId returns rect
    return LoadRectHandle(AreaDataTable, areaId, HT_RECT)
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

// 是否外围区域
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

// 获取邻接区域数量（有向边出度）
function GetAreaNeighborCount takes integer areaId returns integer
    return LoadInteger(AreaDataTable, areaId, HT_NEIGHBOR_COUNT)
endfunction

// 获取第 index 个邻接区域ID（0起始）
function GetAreaNeighbor takes integer areaId, integer index returns integer
    return LoadInteger(AreaDataTable, areaId, HT_NEIGHBOR_COUNT + 1 + index)
endfunction

// 获取BOSS房区域ID
function GetBossArea takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_BOSS_AREA)
endfunction

// 获取入口数量
function GetEnterCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
endfunction

// 获取第 index 个入口区域ID（0起始）
function GetEnterArea takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_ENTER_LIST + index)
endfunction

// 获取诅咒起始区域数量
function GetCurseStartCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_CURSE_START_COUNT)
endfunction

// 获取第 index 个诅咒起始区域ID（0起始）
function GetCurseStartArea takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_CURSE_START_LIST + index)
endfunction

// 获取已注册区域总数
function GetAreaCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
endfunction

// 获取第 index 个已注册区域ID（0起始）
function GetAreaByIndex takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_LIST + index)
endfunction

// 获取已注册房间类型数量
function GetRoomTypeRegCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
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
    description = "获取${指定ID}关卡随机确定的入口区域矩形，供GUI传送使用"
    category = TC_FRO
    returns = rect
    [[.args]]
    type = integer
*/
function GetActiveEnterRect takes integer chapterId returns rect
    local integer areaId = LoadInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0)
    if areaId < 0 then
        return null
    endif
    return LoadRectHandle(AreaDataTable, areaId, HT_RECT)
endfunction

// ===== 注册接口 =====

// 注册区域：绑定区域ID与矩形，建立反向查询，初始化默认状态
function RegisterArea takes integer areaId, rect areaRect returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    call SaveRectHandle(AreaDataTable, areaId, HT_RECT, areaRect)
    call SaveInteger(AreaDataTable, GetHandleId(areaRect), 0, areaId)
    call SaveInteger(AreaDataTable, areaId, HT_ROOM_STATE, ROOM_STATE_INACTIVE)
    call SaveBoolean(AreaDataTable, areaId, HT_CLEARED_THIS_GAME, false)
    call SaveInteger(AreaDataTable, areaId, HT_ALIVE_MONSTER, 0)
    call SaveInteger(AreaDataTable, areaId, HT_NEIGHBOR_COUNT, 0)
    call SaveInteger(AreaDataTable, 0, HT_AREA_LIST + count, areaId)
    call SaveInteger(AreaDataTable, 0, HT_AREA_COUNT, count + 1)
endfunction

// 注册有向边：fromArea → toArea
function RegisterNeighbor takes integer fromArea, integer toArea returns nothing
    local integer count = LoadInteger(AreaDataTable, fromArea, HT_NEIGHBOR_COUNT)
    call SaveInteger(AreaDataTable, fromArea, HT_NEIGHBOR_COUNT + 1 + count, toArea)
    call SaveInteger(AreaDataTable, fromArea, HT_NEIGHBOR_COUNT, count + 1)
endfunction

// ===== 配置接口（在 InitArea 之前调用） =====

// 设置BOSS房位置
function AreaSetBossroom takes integer areaId returns nothing
    call SaveInteger(AreaDataTable, 0, HT_BOSS_AREA, areaId)
    call SetRoomType(areaId, ROOM_TYPE_BOSS)
endfunction

// 增加一个入口区域
function AreaAddEnter takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
    call SaveInteger(AreaDataTable, 0, HT_ENTER_LIST + count, areaId)
    call SaveInteger(AreaDataTable, 0, HT_ENTER_COUNT, count + 1)
endfunction

// 从已注册的入口列表中随机确定指定关卡的入口区域
// 必须在所有 AreaAddEnter 之后、InitArea 之前调用
function RollActiveEnter takes integer chapterId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ENTER_COUNT)
    if count <= 0 then
        return
    endif
    call SaveInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0, LoadInteger(AreaDataTable, 0, HT_ENTER_LIST + GetRandomInt(0, count - 1)))
endfunction

// 增加一个诅咒起始区域
function AddCurseStartArea takes integer areaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_CURSE_START_COUNT)
    call SaveInteger(AreaDataTable, 0, HT_CURSE_START_LIST + count, areaId)
    call SaveBoolean(AreaDataTable, areaId, HT_IS_PERIPHERAL, true)
    call SaveInteger(AreaDataTable, 0, HT_CURSE_START_COUNT, count + 1)
endfunction

// 注册房间类型及上下限（maxCount=-1 表示无上限）
// 怪物房(ROOM_TYPE_MONSTER)无需注册，自动作为兜底类型
function RegisterRoomType takes integer typeId, integer minCount, integer maxCount returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 0, typeId)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 1, minCount)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + count * 3 + 2, maxCount)
    call SaveInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT, count + 1)
endfunction

// 设置某房间类型的权重（不设置则默认为0，不参与随机分配）
function SetRoomTypeWeight takes integer typeId, integer weight returns nothing
    call SaveInteger(AreaDataTable, typeId, HT_RTW_WEIGHT, weight)
endfunction

// ===== 区域出口注册（配置接口，在 InitArea 之前调用） =====

// 注册出口矩形与目标区域矩形的映射
// sourceAreaId 为出口所在的源区域ID，由调用者根据出口矩形命名确定
function RegisterAreaExit takes rect exitRect, rect targetRect, integer sourceAreaId returns nothing
    local integer count = LoadInteger(AreaDataTable, 0, HT_AREA_EXIT_COUNT)

    call SaveRectHandle(AreaDataTable, 0, HT_AREA_EXIT_LIST + count * 3, exitRect)
    call SaveRectHandle(AreaDataTable, 0, HT_AREA_EXIT_LIST + count * 3 + 1, targetRect)
    call SaveInteger(AreaDataTable, 0, HT_AREA_EXIT_LIST + count * 3 + 2, sourceAreaId)
    call SaveInteger(AreaDataTable, 0, HT_AREA_EXIT_COUNT, count + 1)
endfunction

// 获取已注册的出口数量
function GetAreaExitCount takes nothing returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_EXIT_COUNT)
endfunction

// 获取第 index 个出口的出口矩形
function GetAreaExitRect takes integer index returns rect
    return LoadRectHandle(AreaDataTable, 0, HT_AREA_EXIT_LIST + index * 3)
endfunction

// 获取第 index 个出口的目标区域矩形
function GetAreaExitTargetRect takes integer index returns rect
    return LoadRectHandle(AreaDataTable, 0, HT_AREA_EXIT_LIST + index * 3 + 1)
endfunction

// 获取第 index 个出口的源区域ID
function GetAreaExitSourceId takes integer index returns integer
    return LoadInteger(AreaDataTable, 0, HT_AREA_EXIT_LIST + index * 3 + 2)
endfunction

// 将区域ID转换为字母名称（仅用于调试输出）
// Forest 映射：0=A, 1=C, 2=D, 3=E, 4=F, 5=G, 6=H, 7=I, 8=J, 9=K, 10=L, 11=M, 12=N
function GetAreaIdName takes integer areaId returns string
    if areaId < 0 then
        return "?"
    endif
    if areaId < 13 then
        return SubString("ACDEFGHIJKLMN", areaId, areaId + 1)
    endif
    return I2S(areaId)
endfunction

// ===== 初始化接口 =====

// 获取某类型已分配数量
private function GetAssignedCount takes integer typeId returns integer
    return LoadInteger(AreaDataTable, typeId, HT_RTW_ASSIGNED)
endfunction

// 增加某类型已分配数量
private function IncAssignedCount takes integer typeId returns nothing
    call SaveInteger(AreaDataTable, typeId, HT_RTW_ASSIGNED, LoadInteger(AreaDataTable, typeId, HT_RTW_ASSIGNED) + 1)
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

// 获取某类型的注册下限
private function GetRegisteredMin takes integer typeId returns integer
    local integer count = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    loop
        exitwhen i >= count
        if LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0) == typeId then
            return LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 1)
        endif
        set i = i + 1
    endloop
    return 0
endfunction

// 衰减权重分配：根据剩余配额动态计算各类型的有效权重
// 有效权重 = 原始权重 × (maxCount - assignedCount) / maxCount
// maxCount=-1 时有效权重 = 原始权重（不衰减）
private function RollRoomTypeByWeight takes nothing returns integer
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer totalWeight = LoadInteger(AreaDataTable, ROOM_TYPE_MONSTER, HT_RTW_WEIGHT)
    local real monsterEffective
    local integer i = 0
    local integer typeId
    local integer weight
    local integer assigned
    local integer maxCount
    local real effective
    local real roll
    local real accumulated

    // 计算怪物房有效权重（不衰减）
    if GetAssignedCount(ROOM_TYPE_MONSTER) >= GetRegisteredMax(ROOM_TYPE_MONSTER) and GetRegisteredMax(ROOM_TYPE_MONSTER) >= 0 then
        set monsterEffective = 0.0
    else
        set monsterEffective = I2R(totalWeight)
    endif
    set totalWeight = 0
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        set weight = LoadInteger(AreaDataTable, typeId, HT_RTW_WEIGHT)
        set assigned = GetAssignedCount(typeId)
        set maxCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 2)

        if assigned >= maxCount and maxCount >= 0 then
            set effective = 0.0
        elseif maxCount == ROOM_MAX_UNLIMITED then
            set effective = I2R(weight)
        else
            set effective = I2R(weight) * I2R(maxCount - assigned) / I2R(maxCount)
        endif

        set i = i + 1
    endloop

    // 累加所有有效权重得到总权重
    set totalWeight = R2I(monsterEffective)
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        set weight = LoadInteger(AreaDataTable, typeId, HT_RTW_WEIGHT)
        set assigned = GetAssignedCount(typeId)
        set maxCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 2)

        if assigned >= maxCount and maxCount >= 0 then
            set totalWeight = totalWeight + 0
        elseif maxCount == ROOM_MAX_UNLIMITED then
            set totalWeight = totalWeight + weight
        else
            set totalWeight = totalWeight + R2I(I2R(weight) * I2R(maxCount - assigned) / I2R(maxCount))
        endif

        set i = i + 1
    endloop

    if totalWeight <= 0 and monsterEffective <= 0.0 then
        return ROOM_TYPE_MONSTER
    endif

    // 随机落点
    set roll = GetRandomReal(0.0, monsterEffective + I2R(totalWeight))
    if roll < monsterEffective then
        call IncAssignedCount(ROOM_TYPE_MONSTER)
        return ROOM_TYPE_MONSTER
    endif

    // 遍历已注册类型，找到落点
    set accumulated = monsterEffective
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        set weight = LoadInteger(AreaDataTable, typeId, HT_RTW_WEIGHT)
        set assigned = GetAssignedCount(typeId)
        set maxCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 2)

        if assigned >= maxCount and maxCount >= 0 then
            set effective = 0.0
        elseif maxCount == ROOM_MAX_UNLIMITED then
            set effective = I2R(weight)
        else
            set effective = I2R(weight) * I2R(maxCount - assigned) / I2R(maxCount)
        endif

        set accumulated = accumulated + effective
        if roll < accumulated then
            call IncAssignedCount(typeId)
            return typeId
        endif

        set i = i + 1
    endloop

    // 兜底：返回怪物房
    call IncAssignedCount(ROOM_TYPE_MONSTER)
    return ROOM_TYPE_MONSTER
endfunction

// 初始化所有区域：根据已配置的BOSS房、入口、权重，动态分配其余房间类型
// 必须在 RegisterArea / AreaSetBossroom / AreaAddEnter / RegisterRoomType / SetRoomTypeWeight 之后调用
// chapterId 用于确定本次游戏的激活入口区域（由 RollActiveEnter 预先随机选定）；
// 仅激活入口会被标记为 ROOM_TYPE_ENTRY（安全房），其余候选入口与其他区域一样正常参与分配
function InitAreaWithEnter takes integer chapterId returns nothing
    local integer total = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    local integer bossArea = LoadInteger(AreaDataTable, 0, HT_BOSS_AREA)
    local integer activeEnter = LoadInteger(AreaDataTable, chapterId + HT_CHAPTER_ENTER_LIST, 0)
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    local integer j = 0
    local integer k = 0
    local integer areaId
    local integer typeId
    local integer minCount
    local integer assigned

    // 默认怪物房权重
    if LoadInteger(AreaDataTable, ROOM_TYPE_MONSTER, HT_RTW_WEIGHT) == 0 then
        call SetRoomTypeWeight(ROOM_TYPE_MONSTER, 700)
    endif

    // 重置所有已分配计数
    call SaveInteger(AreaDataTable, ROOM_TYPE_MONSTER, HT_RTW_ASSIGNED, 0)
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        call SaveInteger(AreaDataTable, typeId, HT_RTW_ASSIGNED, 0)
        set i = i + 1
    endloop

    // 第一步：先标记激活入口为 ENTRY（安全房），跳过 BOSS 房
    // 注意：仅激活入口是安全房，其余候选入口参与正常分配
    if activeEnter >= 0 and activeEnter != bossArea then
        call SetRoomType(activeEnter, ROOM_TYPE_ENTRY)
    endif

    // 第二步：遍历所有区域，先保证每种已注册类型的 minCount
    // 跳过 BOSS 房与已分配类型的区域（含激活入口）
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
            if areaId == bossArea or GetRoomType(areaId) != 0 then
                set k = k + 1
            else
                call SetRoomType(areaId, typeId)
                call IncAssignedCount(typeId)
                set assigned = assigned + 1
                set k = k + 1
            endif
        endloop
        set i = i + 1
    endloop

    // 第三步：剩余未分配区域按衰减权重随机分配
    set k = 0
    loop
        exitwhen k >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + k)

        if areaId == bossArea or GetRoomType(areaId) != 0 then
            set k = k + 1
        else
            call SetRoomType(areaId, RollRoomTypeByWeight())
            set k = k + 1
        endif
    endloop

    // 第四步：激活入口的直接邻居中的 ELITE 降级为 MONSTER
    // 保证玩家从激活入口出发的第一跳不会被困难房包围
    if activeEnter >= 0 then
        set j = 0
        loop
            exitwhen j >= LoadInteger(AreaDataTable, activeEnter, HT_NEIGHBOR_COUNT)
            set typeId = LoadInteger(AreaDataTable, activeEnter, HT_NEIGHBOR_COUNT + 1 + j)
            if typeId != bossArea and GetRoomType(typeId) == ROOM_TYPE_ELITE then
                call SetRoomType(typeId, ROOM_TYPE_MONSTER)
            endif
            set j = j + 1
        endloop
    endif
endfunction

// 重置区域数据：清空所有已注册区域、全局配置和权重数据
// 供 ChapterManager 在关卡切换时调用，确保新旧关卡数据不互相干扰
function ResetAreaData takes nothing returns nothing
    local integer total = LoadInteger(AreaDataTable, 0, HT_AREA_COUNT)
    local integer typeCount = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_REG_COUNT)
    local integer i = 0
    local integer areaId
    local integer typeId

    // 清理每个已注册区域的数据（parent key = areaId）
    set i = 0
    loop
        exitwhen i >= total
        set areaId = LoadInteger(AreaDataTable, 0, HT_AREA_LIST + i)
        call FlushChildHashtable(AreaDataTable, areaId)
        set i = i + 1
    endloop

    // 清理已注册房间类型的权重数据（parent key = typeId）
    // 怪物房权重
    call FlushChildHashtable(AreaDataTable, ROOM_TYPE_MONSTER)
    set i = 0
    loop
        exitwhen i >= typeCount
        set typeId = LoadInteger(AreaDataTable, 0, HT_ROOM_TYPE_LIST + i * 3 + 0)
        call FlushChildHashtable(AreaDataTable, typeId)
        set i = i + 1
    endloop

    // 清理全局配置（parent key = 0）
    call FlushChildHashtable(AreaDataTable, 0)

    // 清理各关卡入口缓存（parent key = chapterId + HT_CHAPTER_ENTER_LIST）
    // chapterId 从 0 开始，最多清理到当前已注册关卡数
    set i = 0
    loop
        exitwhen i >= total
        call FlushChildHashtable(AreaDataTable, i + HT_CHAPTER_ENTER_LIST)
        set i = i + 1
    endloop
endfunction

endlibrary


#endif

