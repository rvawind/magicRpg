#ifndef FOREST_INCLUDED
#define FOREST_INCLUDED
#include "nncou\\magic\\map\\area\\core\\grid.j"
#include "nncou\\magic\\map\\area\\config\\ch1Layouts.j"
#include "nncou\\magic\\map\\area\\core\\slot.j"
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
#include "nncou\\magic\\map\\area\\core\\emergency.j"
#include "nncou\\magic\\map\\ui\\uiPick.j"
#include "nncou\\magic\\map\\reward\\reward.j"
#include "nncou\\magic\\map\\reward\\altar.j"
#include "nncou\\magic\\map\\curse\\curse.j"
#include "nncou\\magic\\map\\boss\\boss.j"
#include "nncou\\magic\\map\\timer\\timer.j"
/*
    Forest = 第一章（2026-11-17 起）
    - 布局：5 套固定路径变体（A~E，5×4 稀疏、13~14 房、树形边表），每局随机抽一套；
      可用 Forest_SetForcedLayout(index) 强制指定（测试/调试）。
    - 路径固定：cell 列表 + 显式边表（Grid_BeginManualEdges/AddEdge/EndManualEdges）。
    - 房型随机：出生固定为入口；BOSS 从距出生>=6 的房间随机；商店在距离3~5随机；
      精英在距离5~6随机3~4间；其余普通。N1/N2 由布局结构保证为前两间普通房。
    - 内容随机：怪物组/掉落按现有系统随机；EXP=杀敌奖励、不由本章节配置发放（归杀怪系统/内容层）。
    - 物理层仍用 WE 的 20 个物理房（4 地形 × 5），逻辑房按需绑定。
*/
library Forest initializer InitForestConfig requires ch1Layouts, areaGrid, areaSlot, areaData, areaEnter, areaExit, areaMonsterRoom, ChapterManager, BossSystem, CurseSystem, ChapterTimer, RewardAltar, RewardItem, DebugLogger

globals
    // Forest 关卡 ID（由 RegisterChapter 返回，在 InitForestConfig 中赋值）
    private integer FOREST_CHAPTER_ID = 0

    // 第一章：5×4 稀疏固定布局（5 套变体，路径固定、房型随机）
    private constant integer FOREST_BOUND_ROWS = 5
    private constant integer FOREST_BOUND_COLS = 4
    // 变体选择：-1=每局随机；>=0=强制指定（测试/调试）
    private integer ForestForcedLayout = -1
    // 本次选中的布局与关键房 id（InitForest 计算，Stage2 使用）
    private integer ForestLayoutIndex = 0
    private integer ForestActiveChapterId = -1
    private boolean ForestMonsterGroupsReady = false
    private integer ForestSpawnId = -1
    private integer ForestBossId = -1
    private integer array ForestPickBuf
    private integer ForestPickCount = 0

    // 地形编号（与物理槽位注册顺序一致）
    private constant integer TERRAIN_A = 0
    private constant integer TERRAIN_B = 1
    private constant integer TERRAIN_C = 2
    private constant integer TERRAIN_D = 3

    // 自动生成门洞矩形的尺寸（门洞位于房间边缘内侧，避免被区域守卫拉回）
    private constant real DOOR_HALF_WIDTH = 80.0
    private constant real DOOR_DEPTH = 64.0

    // 物理房间只注册一次（跨关卡保留）
    private boolean PhysicalRoomsRegistered = false

    // 门洞模板：索引 = terrain * 4 + dir，取值为 WE 中画在参考房间里的矩形
    private rect array DoorTemplate

    // 初始化第二阶段用的触发器（懒创建，只用来开一个新线程）
    private trigger ForestStage2Trig = null
endglobals

// ===== 物理层：门洞矩形 =====

// 读取某地形某方向的门洞模板；未配置返回 null
private function GetTerrainDoorTemplate takes integer terrain, integer dir returns rect
    if terrain < 0 or terrain > TERRAIN_D or dir < 0 or dir > 3 then
        return null
    endif
    return DoorTemplate[terrain * 4 + dir]
endfunction

// 把模板门洞按「参考房间中心 -> 目标房间中心」的偏移复制到目标房间
// 模板尺寸保持不变；必须创建新的 rect 句柄（同一句柄不能登记给多个槽位）
private function MakeDoorRectFromTemplate takes rect roomRect, rect refRoom, rect template returns rect
    local real dx = GetRectCenterX(template) - GetRectCenterX(refRoom)
    local real dy = GetRectCenterY(template) - GetRectCenterY(refRoom)
    local real halfW = (GetRectMaxX(template) - GetRectMinX(template)) / 2.0
    local real halfH = (GetRectMaxY(template) - GetRectMinY(template)) / 2.0
    local real cx = GetRectCenterX(roomRect) + dx
    local real cy = GetRectCenterY(roomRect) + dy
    return Rect(cx - halfW, cy - halfH, cx + halfW, cy + halfH)
endfunction

// 按房间区域边缘生成门洞矩形（没有模板时的兜底；方向使用 areaGrid 的 DIR_* 常量）
private function MakeDoorRect takes rect r, integer dir returns rect
    local real minX = GetRectMinX(r)
    local real maxX = GetRectMaxX(r)
    local real minY = GetRectMinY(r)
    local real maxY = GetRectMaxY(r)
    local real cx = (minX + maxX) / 2.0
    local real cy = (minY + maxY) / 2.0
    if dir == DIR_UP then
        return Rect(cx - DOOR_HALF_WIDTH, maxY - DOOR_DEPTH, cx + DOOR_HALF_WIDTH, maxY)
    elseif dir == DIR_DOWN then
        return Rect(cx - DOOR_HALF_WIDTH, minY, cx + DOOR_HALF_WIDTH, minY + DOOR_DEPTH)
    elseif dir == DIR_LEFT then
        return Rect(minX, cy - DOOR_HALF_WIDTH, minX + DOOR_DEPTH, cy + DOOR_HALF_WIDTH)
    endif
    return Rect(maxX - DOOR_DEPTH, cy - DOOR_HALF_WIDTH, maxX, cy + DOOR_HALF_WIDTH)
endfunction

// 登记某地形的 4 个门洞模板：面积内的可破坏物会被 areaExit 读取为「闭门障碍物」模板
// 读取后原件被删除，之后按逻辑房是否有该方向的邻居决定重建或留空
private function RegisterDoorDecorTemplates takes integer terrain returns nothing
    local integer dir = 0
    loop
        exitwhen dir >= 4
        call RegisterDoorDecorTemplate(terrain, dir, GetTerrainDoorTemplate(terrain, dir))
        set dir = dir + 1
    endloop
endfunction

// 注册一个物理房：区域矩形必填
// 门洞优先用该地形的模板（相对参考房间偏移复制）；模板缺失时退回按边缘居中生成
private function RegisterRoomWithDoors takes integer terrain, rect r, rect refRoom returns nothing
    local rect up = GetTerrainDoorTemplate(terrain, DIR_UP)
    local rect down = GetTerrainDoorTemplate(terrain, DIR_DOWN)
    local rect left = GetTerrainDoorTemplate(terrain, DIR_LEFT)
    local rect right = GetTerrainDoorTemplate(terrain, DIR_RIGHT)
    if r == null then
        call DebugLogger_Log(LOG_WARN, "[forest] physical room skipped: null region, terrain=" + I2S(terrain))
        set up = null
        set down = null
        set left = null
        set right = null
        return
    endif
    if up != null and down != null and left != null and right != null and refRoom != null then
        call areaSlot_RegisterPhysicalRoom(terrain, r, MakeDoorRectFromTemplate(r, refRoom, up), MakeDoorRectFromTemplate(r, refRoom, down), MakeDoorRectFromTemplate(r, refRoom, left), MakeDoorRectFromTemplate(r, refRoom, right))
    else
        call DebugLogger_Log(LOG_WARN, "[forest] door template missing for terrain " + I2S(terrain) + ", fallback to centered doors")
        call areaSlot_RegisterPhysicalRoom(terrain, r, MakeDoorRect(r, DIR_UP), MakeDoorRect(r, DIR_DOWN), MakeDoorRect(r, DIR_LEFT), MakeDoorRect(r, DIR_RIGHT))
    endif
    set up = null
    set down = null
    set left = null
    set right = null
endfunction

// ===== 槽位钩子 =====

// 分配成功：刷新门洞特效；已清空的房间重新绑定时恢复祭坛
private function OnSlotAcquire takes nothing returns nothing
    local integer areaId = Slot_GetLastAcquiredLogical()
    local integer slotId
    local integer roomType
    if areaId < 0 then
        return
    endif
    set slotId = Slot_GetSlotOf(areaId)
    call RefreshSlotDoors(slotId)
    if GetRoomState(areaId) == ROOM_STATE_CLEARED then
        set roomType = GetRoomType(areaId)
        if (roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE) and not RewardAltar_HasAltar(areaId) then
            call RewardAltar_SpawnAltar(areaId, roomType)
            call DebugLogger_Log(LOG_INFO, "[forest] respawn altar for reacquired cleared room " + GetAreaIdName(areaId))
        endif
    endif
    call DebugLogger_Log(LOG_TRACE, "[forest] slot acquire area=" + GetAreaIdName(areaId) + " slot=" + I2S(slotId))
endfunction

// 解绑前：清理门洞特效、祭坛、房间怪物与刷怪计时器
private function OnSlotRelease takes nothing returns nothing
    local integer areaId = Slot_GetLastReleasedLogical()
    local integer slotId
    if areaId < 0 then
        return
    endif
    set slotId = Slot_GetSlotOf(areaId)
    call ClearSlotDoors(slotId)
    call RewardAltar_RemoveArea(areaId)
    call areaMonsterRoom_OnSlotReleased(areaId)
    call DebugLogger_Log(LOG_TRACE, "[forest] slot release area=" + GetAreaIdName(areaId) + " slot=" + I2S(slotId))
endfunction

// 槽位溢出时的驱逐判定：只允许驱逐无玩家、非 BOSS、已清空或未激活的房间
private function CanEvictRoom takes nothing returns boolean
    local integer areaId = Slot_GetEvalLogical()
    local integer state
    if areaId < 0 then
        return false
    endif
    if areaId == GetBossArea() then
        return false
    endif
    set state = GetRoomState(areaId)
    if state != ROOM_STATE_CLEARED and state != ROOM_STATE_INACTIVE then
        return false
    endif
    if CountPlayersInRect(GetAreaRect(areaId)) > 0 then
        return false
    endif
    return true
endfunction

// ===== 物理层：一次性注册 =====

private function InitForestPhysicalRooms takes nothing returns nothing
    if PhysicalRoomsRegistered then
        return
    endif
    set PhysicalRoomsRegistered = true

    // 门洞模板：每种地形 4 个，画在该地形的第 1 个房间（A1/B1/C1/D1）内
    set DoorTemplate[TERRAIN_A * 4 + DIR_UP] = gg_rct_FR_A_DOOR_UP
    set DoorTemplate[TERRAIN_A * 4 + DIR_DOWN] = gg_rct_FR_A_DOOR_DOWN
    set DoorTemplate[TERRAIN_A * 4 + DIR_LEFT] = gg_rct_FR_A_DOOR_LEFT
    set DoorTemplate[TERRAIN_A * 4 + DIR_RIGHT] = gg_rct_FR_A_DOOR_RIGHT
    set DoorTemplate[TERRAIN_B * 4 + DIR_UP] = gg_rct_FR_B_DOOR_UP
    set DoorTemplate[TERRAIN_B * 4 + DIR_DOWN] = gg_rct_FR_B_DOOR_DOWN
    set DoorTemplate[TERRAIN_B * 4 + DIR_LEFT] = gg_rct_FR_B_DOOR_LEFT
    set DoorTemplate[TERRAIN_B * 4 + DIR_RIGHT] = gg_rct_FR_B_DOOR_RIGHT
    set DoorTemplate[TERRAIN_C * 4 + DIR_UP] = gg_rct_FR_C_DOOR_UP
    set DoorTemplate[TERRAIN_C * 4 + DIR_DOWN] = gg_rct_FR_C_DOOR_DOWN
    set DoorTemplate[TERRAIN_C * 4 + DIR_LEFT] = gg_rct_FR_C_DOOR_LEFT
    set DoorTemplate[TERRAIN_C * 4 + DIR_RIGHT] = gg_rct_FR_C_DOOR_RIGHT
    set DoorTemplate[TERRAIN_D * 4 + DIR_UP] = gg_rct_FR_D_DOOR_UP
    set DoorTemplate[TERRAIN_D * 4 + DIR_DOWN] = gg_rct_FR_D_DOOR_DOWN
    set DoorTemplate[TERRAIN_D * 4 + DIR_LEFT] = gg_rct_FR_D_DOOR_LEFT
    set DoorTemplate[TERRAIN_D * 4 + DIR_RIGHT] = gg_rct_FR_D_DOOR_RIGHT

    // 登记门洞模板（供 areaExit 读取闭门障碍物；在 InitAreaExits 时捕获）
    call RegisterDoorDecorTemplates(TERRAIN_A)
    call RegisterDoorDecorTemplates(TERRAIN_B)
    call RegisterDoorDecorTemplates(TERRAIN_C)
    call RegisterDoorDecorTemplates(TERRAIN_D)

    // 地形 0（参考房间 A1）
    call RegisterRoomWithDoors(TERRAIN_A, gg_rct_FR_A1, gg_rct_FR_A1)
    call RegisterRoomWithDoors(TERRAIN_A, gg_rct_FR_A2, gg_rct_FR_A1)
    call RegisterRoomWithDoors(TERRAIN_A, gg_rct_FR_A3, gg_rct_FR_A1)
    call RegisterRoomWithDoors(TERRAIN_A, gg_rct_FR_A4, gg_rct_FR_A1)
    call RegisterRoomWithDoors(TERRAIN_A, gg_rct_FR_A5, gg_rct_FR_A1)

    // 地形 1（参考房间 B1）
    call RegisterRoomWithDoors(TERRAIN_B, gg_rct_FR_B1, gg_rct_FR_B1)
    call RegisterRoomWithDoors(TERRAIN_B, gg_rct_FR_B2, gg_rct_FR_B1)
    call RegisterRoomWithDoors(TERRAIN_B, gg_rct_FR_B3, gg_rct_FR_B1)
    call RegisterRoomWithDoors(TERRAIN_B, gg_rct_FR_B4, gg_rct_FR_B1)
    call RegisterRoomWithDoors(TERRAIN_B, gg_rct_FR_B5, gg_rct_FR_B1)

    // 地形 2（参考房间 C1）
    call RegisterRoomWithDoors(TERRAIN_C, gg_rct_FR_C1, gg_rct_FR_C1)
    call RegisterRoomWithDoors(TERRAIN_C, gg_rct_FR_C2, gg_rct_FR_C1)
    call RegisterRoomWithDoors(TERRAIN_C, gg_rct_FR_C3, gg_rct_FR_C1)
    call RegisterRoomWithDoors(TERRAIN_C, gg_rct_FR_C4, gg_rct_FR_C1)
    call RegisterRoomWithDoors(TERRAIN_C, gg_rct_FR_C5, gg_rct_FR_C1)

    // 地形 3（参考房间 D1）
    call RegisterRoomWithDoors(TERRAIN_D, gg_rct_FR_D1, gg_rct_FR_D1)
    call RegisterRoomWithDoors(TERRAIN_D, gg_rct_FR_D2, gg_rct_FR_D1)
    call RegisterRoomWithDoors(TERRAIN_D, gg_rct_FR_D3, gg_rct_FR_D1)
    call RegisterRoomWithDoors(TERRAIN_D, gg_rct_FR_D4, gg_rct_FR_D1)
    call RegisterRoomWithDoors(TERRAIN_D, gg_rct_FR_D5, gg_rct_FR_D1)

    call Slot_SetAcquireHook(function OnSlotAcquire)
    call Slot_SetReleaseHook(function OnSlotRelease)
    call Slot_SetEvictFilter(function CanEvictRoom)

    call DebugLogger_LogKey("[forest] physical rooms registered: slots=" + I2S(Slot_GetCount()) + " terrains=" + I2S(Slot_GetTerrainTypeCount()))
endfunction

// ===== 怪物组 =====

// 创建并注册 Forest 的怪物组
// 难度档位：1=普通（出现在 ROOM_TYPE_MONSTER），2=困难（出现在 ROOM_TYPE_ELITE）
// 每个组的 minLv/maxLv 决定它在哪些难度档位的房间中可被抽中
function InitForestMonsterGroups takes nothing returns nothing
    local integer gForestGoblin
    local integer gForestGoblinStalker
    local integer gForestGoblinCurer
    local integer gForestTrollWarrior

    set gForestGoblin   = MonsterGroup_CreateMonsterGroup("哥布林小队",   1, 1) // 10哥布林 4哥布林战士 2哥布林精英 总战力：3.6
    call MonsterGroup_AddMonsterToGroup(gForestGoblin, 'o000', 10)
    call MonsterGroup_AddMonsterToGroup(gForestGoblin, 'o001', 4)
    call MonsterGroup_AddMonsterToGroup(gForestGoblin, 'o004', 2)

    set gForestGoblinStalker = MonsterGroup_CreateMonsterGroup("哥布林训狼小队", 1, 1) // 7哥布林 4巨魔训狼者 2哥布林精英 总战力：3.7
    call MonsterGroup_AddMonsterToGroup(gForestGoblinStalker, 'o000', 7)
    call MonsterGroup_AddMonsterToGroup(gForestGoblinStalker, 'o002', 5)
    call MonsterGroup_AddMonsterToGroup(gForestGoblinStalker, 'o004', 2)

    set gForestGoblinCurer   = MonsterGroup_CreateMonsterGroup("哥布林混合小队",   1, 2) // 5哥布林 3哥布林战士 6巨魔巫医 2哥布林精英 总战力：4.6
    call MonsterGroup_AddMonsterToGroup(gForestGoblinCurer, 'o000', 5)
    call MonsterGroup_AddMonsterToGroup(gForestGoblinCurer, 'o001', 3)
    call MonsterGroup_AddMonsterToGroup(gForestGoblinCurer, 'o003', 6)
    call MonsterGroup_AddMonsterToGroup(gForestGoblinCurer, 'o004', 2)

    set gForestTrollWarrior = MonsterGroup_CreateMonsterGroup("巨魔战士小队", 1, 2) // 4巨魔训狼者 4哥布林精英 总战力：4.4
    call MonsterGroup_AddMonsterToGroup(gForestTrollWarrior, 'o002', 4)
    call MonsterGroup_AddMonsterToGroup(gForestTrollWarrior, 'o004', 3)

    // local integer gForestTreeSpirit   = MonsterGroup_CreateMonsterGroup("3树精", 2, 2) // 3树精 总战力：7.5
    // call MonsterGroup_AddMonsterToGroup(gForestTreeSpirit, 'o005', 3)
endfunction

// ===== 关卡初始化 =====

// 初始化第二阶段：入口抽签 → 房间类型 → 守卫/出口 → 怪物房 → 各子系统
// 单独成一个触发器动作，由 InitForest 用 TriggerExecute 调用：
// TriggerExecute 会开一个新线程，重置 JASS 单线程字节码预算，同时保持调用是同步的（顺序不变）。
// 网格坐标方向（用于显式边表：从 a 指向 b 的 4 向方向）
private function ForestDirBetween takes integer r1, integer c1, integer r2, integer c2 returns integer
    if r2 == r1 then
        if c2 > c1 then
            return DIR_RIGHT
        endif
        return DIR_LEFT
    endif
    if r2 > r1 then
        return DIR_DOWN
    endif
    return DIR_UP
endfunction

// 第一章固定布局的随机房型：
// 出生=ENTRY，BOSS=BOSS；商店在距离3~5随机；精英在距离5~6随机3~4个；其余普通。
private function AssignForestFixedTypes takes nothing returns nothing
    local integer i = 0
    local integer id
    local integer dist
    local integer eliteCount
    local integer shopId = -1
    local integer elitesPicked = 0
    local integer j
    // 全部先置普通/入口/BOSS
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if id == ForestSpawnId then
            call SetRoomType(id, ROOM_TYPE_ENTRY)
        elseif id == ForestBossId then
            call SetRoomType(id, ROOM_TYPE_BOSS)
        else
            call SetRoomType(id, ROOM_TYPE_MONSTER)
        endif
        set i = i + 1
    endloop
    // 商店：距离 3~5 的随机一间
    call Grid_BuildDistanceField(ForestSpawnId)
    set ForestPickCount = 0
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        set dist = Grid_GetFieldDistance(id)
        if id != ForestSpawnId and id != ForestBossId and dist >= 3 and dist <= 5 then
            set ForestPickBuf[ForestPickCount] = id
            set ForestPickCount = ForestPickCount + 1
        endif
        set i = i + 1
    endloop
    if ForestPickCount > 0 then
        set shopId = ForestPickBuf[GetRandomInt(0, ForestPickCount - 1)]
        call SetRoomType(shopId, ROOM_TYPE_MERCHANT)
    endif
    // 精英：距离 5~6 的随机 3~4 间
    set ForestPickCount = 0
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        set dist = Grid_GetFieldDistance(id)
        if id != ForestSpawnId and id != ForestBossId and id != shopId and dist >= 5 and dist <= 6 then
            set ForestPickBuf[ForestPickCount] = id
            set ForestPickCount = ForestPickCount + 1
        endif
        set i = i + 1
    endloop
    if ForestPickCount > 0 then
        set eliteCount = GetRandomInt(3, 4)
        if eliteCount > ForestPickCount then
            set eliteCount = ForestPickCount
        endif
        set i = ForestPickCount - 1
        loop
            exitwhen i <= 0
            set j = GetRandomInt(0, i)
            set id = ForestPickBuf[i]
            set ForestPickBuf[i] = ForestPickBuf[j]
            set ForestPickBuf[j] = id
            set i = i - 1
        endloop
        loop
            exitwhen elitesPicked >= eliteCount
            call SetRoomType(ForestPickBuf[elitesPicked], ROOM_TYPE_ELITE)
            set elitesPicked = elitesPicked + 1
        endloop
    endif
endfunction

// 测试/调试：强制指定布局 index（-1=随机）
public function SetForcedLayout takes integer index returns nothing
    set ForestForcedLayout = index
endfunction

private function InitForestStage2 takes nothing returns nothing
    // 5) 随机确定本关入口（排除 BOSS 房，并满足入口→BOSS 最小图距离）
    call AreaSetEntryBossMinDistance(0)
    call RollActiveEnter(ForestActiveChapterId)

    // 6) 房间类型权重配置
    call RegisterRoomType(ROOM_TYPE_MONSTER, 30, ROOM_MAX_UNLIMITED)
    call SetRoomTypeWeight(ROOM_TYPE_MONSTER, 700)
    call RegisterRoomType(ROOM_TYPE_SAFE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_SAFE, 200)
    call RegisterRoomType(ROOM_TYPE_ELITE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_ELITE, 100)

    // 7) 先按通用流程分配地形/基础类型，再按第一章约束覆盖随机房型
    call InitAreaWithEnter(ForestActiveChapterId)
    call AssignForestFixedTypes()

    // 8) 物理槽位常驻触发器（必须在物理房注册之后）
    //    BOSS 中转房不预绑定：它和普通逻辑房一样，玩家接近时才分配物理槽位
    call InitAreaGuards()
    call InitAreaExits()

    // 9) 怪物组与怪物房（必须在 InitAreaWithEnter 之后）
    //    怪物组表只增不减：只在本局第一次初始化时建，跨章复用
    if not ForestMonsterGroupsReady then
        set ForestMonsterGroupsReady = true
        call InitForestMonsterGroups()
    endif
    call InitMonsterRoom()

    /*
        怪物清单：
        o000 : 哥布林（普通怪物）难度：0.1
        o001 : 哥布林战士（普通怪物） 难度：0.3
        o002 : 巨魔训狼者（普通怪物） 难度：0.4 特殊：本体0.1，出现时召唤1只狼
        o003 : 巨魔巫医（普通怪物） 难度：0.3 特殊：本体0.1，使用治疗技能，为队友提供百分比生命回复。
        o004 : 哥布林精英（精英怪物） 难度：0.7 俗称熊地精，头大无脑，但体型是普通哥布林的6-8倍，攻击力和生命值也成倍增加，具有高威胁度。
        o005 : 树精（精英怪物） 难度：2.5 特殊：1.会周期性对玩家脚下制造延迟的范围伤害。2.会向一条直线射出藤曼，对沿途单位造成伤害并控制。3.持续吸取该房间玩家的生命和魔法值为自己补充。4.第一次因火焰进入元素异常时，取消3技能效果。受到1.5倍的火焰伤害。
    */

    // 紧急穿越共通技能ID（须与 WE 物体编辑器中配置的技能原始ID一致）
    call areaEmergency_SetEmergencyAbilityId('A07E')

    // 初始化BOSS系统（按逻辑 ID 监听进入 BOSS 中转房）
    call BossSystem_InitBossSystem()
    call BossSystem_SetBossTypeId('nBO1')  // 占位符，在WE中配置实际BOSS单位ID

    // 计时器回返参数：基础15秒 × 1.0系数
    call ChapterTimer_SetChapterTimerReturnParams(15, 1.0)

    // 诅咒配置：每10秒扩散一个区域，基础伤害10，递增系数2，上限100，每1秒伤害一次
    call CurseSystem_SetCurseSpreadInterval(10.0)
    call CurseSystem_SetCurseDamageParams(10.0, 2.0, 100.0, 1.0)

    // 祭坛配置（单位类型ID在WE中配置，商店上架物品由物体编辑器配置）
    call RewardAltar_SetAltarUnitTypeId('n000')  // 祭坛单位类型ID

    call DebugLogger_LogKey("[forest] InitForest done: chapter=" + I2S(ForestActiveChapterId) + " enter=" + GetAreaIdName(GetActiveEnter(FOREST_CHAPTER_ID)) + " boss=" + GetAreaIdName(GetBossArea()) + " slots=" + I2S(Slot_GetCount()))
endfunction

// Forest 关卡初始化回调，由 ChapterManager.StartChapter 触发
// 分两段线程执行，避免初始化单线程超过 JASS 字节码上限：
//   第一段：物理房注册 + 网格生成 + 逻辑房注册 + BOSS 抽签
//   第二段：InitForestStage2（TriggerExecute 新线程）
private function InitForestBody takes nothing returns nothing
    local integer i = 0

    // 物理房注册只做一次；之后每次进入关卡只重建逻辑数据
    call InitForestPhysicalRooms()

    // 出生点
    call ChapterManager_SetVillageRect(gg_rct_Village)

    // 1) 选一套固定路径布局（A~E），建立稀疏网格与显式边表
    if ForestForcedLayout >= 0 and ForestForcedLayout < ch1Layouts_GetLayoutCount() then
        set ForestLayoutIndex = ForestForcedLayout
    else
        set ForestLayoutIndex = GetRandomInt(0, ch1Layouts_GetLayoutCount() - 1)
    endif
    call Grid_InitBounds(FOREST_BOUND_ROWS, FOREST_BOUND_COLS)
    set i = 0
    loop
        exitwhen i >= ch1Layouts_GetLayoutCellCount(ForestLayoutIndex)
        call Grid_AddCell(ch1Layouts_GetLayoutCellRow(ForestLayoutIndex, i), ch1Layouts_GetLayoutCellCol(ForestLayoutIndex, i))
        set i = i + 1
    endloop
    call Grid_BeginManualEdges()
    set i = 0
    loop
        exitwhen i >= ch1Layouts_GetLayoutEdgeCount(ForestLayoutIndex)
        call Grid_AddEdge(Grid_GetIdIfPresent(ch1Layouts_GetLayoutEdgeARow(ForestLayoutIndex, i), ch1Layouts_GetLayoutEdgeACol(ForestLayoutIndex, i)), ForestDirBetween(ch1Layouts_GetLayoutEdgeARow(ForestLayoutIndex, i), ch1Layouts_GetLayoutEdgeACol(ForestLayoutIndex, i), ch1Layouts_GetLayoutEdgeBRow(ForestLayoutIndex, i), ch1Layouts_GetLayoutEdgeBCol(ForestLayoutIndex, i)))
        set i = i + 1
    endloop
    call Grid_EndManualEdges()

    // 2) 注册全部逻辑房间（B11：遍历存在格列表）
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        call RegisterArea(Grid_GetCellByIndex(i))
        set i = i + 1
    endloop

    // 3) 出生房 = 布局中的 spawn cell；只把它作为入口候选
    set i = 0
    loop
        exitwhen i >= ch1Layouts_GetLayoutCellCount(ForestLayoutIndex)
        if ch1Layouts_GetLayoutCellType(ForestLayoutIndex, i) == 0 then
            set ForestSpawnId = Grid_GetIdIfPresent(ch1Layouts_GetLayoutCellRow(ForestLayoutIndex, i), ch1Layouts_GetLayoutCellCol(ForestLayoutIndex, i))
        endif
        set i = i + 1
    endloop
    call AreaAddEnter(ForestSpawnId)

    // 4) BOSS = 距出生 ≥6 的随机房间（布局保证至少一个）
    call Grid_BuildDistanceField(ForestSpawnId)
    set ForestPickCount = 0
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        if Grid_GetFieldDistance(Grid_GetCellByIndex(i)) >= 6 then
            set ForestPickBuf[ForestPickCount] = Grid_GetCellByIndex(i)
            set ForestPickCount = ForestPickCount + 1
        endif
        set i = i + 1
    endloop
    if ForestPickCount > 0 then
        set ForestBossId = ForestPickBuf[GetRandomInt(0, ForestPickCount - 1)]
    else
        set ForestBossId = Grid_GetCellByIndex(Grid_GetTotal() - 1)
    endif
    call AreaSetBossroom(ForestBossId)
    set ForestPickCount = 0

    // 5) 其余初始化在独立线程里继续（TriggerExecute 同步执行，顺序不变）
    if ForestStage2Trig == null then
        set ForestStage2Trig = CreateTrigger()
        call TriggerAddAction(ForestStage2Trig, function InitForestStage2)
    endif
    call TriggerExecute(ForestStage2Trig)
endfunction

// 生产入口：签名保持不变
function InitForest takes nothing returns nothing
    set ForestActiveChapterId = FOREST_CHAPTER_ID
    call InitForestBody()
endfunction

// 测试/未来章节复用入口：把本章数据写到指定 chapterId 下
public function InitForestChapter takes integer chapterId returns nothing
    set ForestActiveChapterId = chapterId
    call InitForestBody()
endfunction

// 本局实际使用的布局编号（0..4）
public function GetLayoutIndex takes nothing returns integer
    return ForestLayoutIndex
endfunction

// Forest 关卡配置注册：在游戏初始化时调用
// 注册 Forest 关卡到 ChapterManager，绑定 InitForest 作为初始化回调
function InitForestConfig takes nothing returns nothing
    set FOREST_CHAPTER_ID = ChapterManager_RegisterChapter("Forest", 600)
    call ChapterManager_SetChapterInitFunc(FOREST_CHAPTER_ID, function InitForest)
endfunction

endlibrary
#endif
