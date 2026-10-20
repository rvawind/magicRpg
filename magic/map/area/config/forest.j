#ifndef FOREST_INCLUDED
#define FOREST_INCLUDED
#include "nncou\\magic\\map\\area\\core\\grid.j"
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
    Forest 关卡配置文件（Step 3：7×7 逻辑网格 + 物理槽位池）

    逻辑层：
    - 7×7 = 49 个逻辑房间，logicalId = row * 7 + col，全部永久存在。
    - 邻接由随机 DFS 生成树 + 额外边构成，保证全图连通。
    - 起点从外围 8 个候选（4 角 + 4 边中点）随机选 1 个。
    - BOSS 逻辑房从内部候选 (2,2)/(3,3)/(4,4) 随机选 1 个。

    物理层（WE 中手工摆放，与逻辑坐标完全无关）：
    - 4 种地形 × 每地形 5 个普通物理房 = 20 个槽位；
    - 1 个 BOSS 预留槽位，只绑定 BOSS 逻辑房，不参与普通分配/驱逐。
    - 每个物理房需要 1 个区域矩形；门洞矩形由本文件按房间边缘自动生成。
      （如需手工摆放门洞，可把 MakeDoorRect 替换为对应的 gg_rct 引用。）

    需要的 WE 区域矩形变量（共 21 个）：
      gg_rct_FR_A1 .. gg_rct_FR_A5   // 地形 0
      gg_rct_FR_B1 .. gg_rct_FR_B5   // 地形 1
      gg_rct_FR_C1 .. gg_rct_FR_C5   // 地形 2
      gg_rct_FR_D1 .. gg_rct_FR_D5   // 地形 3
      gg_rct_FR_BOSS                 // BOSS 预留槽

    槽位生命周期：
    - 进入某逻辑房前由 Area_EnsureBound 分配同地形槽位（优先粘性复用）；
    - 无玩家且（CLEARED 或 INACTIVE）时由 areaEnter 定时回收；
    - 槽位池满时只驱逐「无玩家、非 BOSS、非诅咒、CLEARED/INACTIVE」的同地形槽位。
*/
library Forest initializer InitForestConfig requires areaGrid, areaSlot, areaData, areaEnter, areaExit, areaMonsterRoom, ChapterManager, BossSystem, CurseSystem, ChapterTimer, RewardAltar, RewardItem, DebugLogger

globals
    // Forest 关卡 ID（由 RegisterChapter 返回，在 InitForestConfig 中赋值）
    private integer FOREST_CHAPTER_ID = 0

    // 网格尺寸与剪枝概率
    private constant integer FOREST_ROWS = 7
    private constant integer FOREST_COLS = 7
    private constant real FOREST_PRUNE_CHANCE = 0.30

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
endglobals

// ===== 物理层：门洞矩形 =====

// 按房间区域边缘生成门洞矩形（方向使用 areaGrid 的 DIR_* 常量）
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

// 注册一个物理房：区域矩形必填，4 个门洞自动生成
private function RegisterRoomWithAutoDoors takes integer terrain, rect r returns nothing
    if r == null then
        call DebugLogger_Log(LOG_WARN, "[forest] physical room skipped: null region, terrain=" + I2S(terrain))
        return
    endif
    call areaSlot_RegisterPhysicalRoom(terrain, r, MakeDoorRect(r, DIR_UP), MakeDoorRect(r, DIR_DOWN), MakeDoorRect(r, DIR_LEFT), MakeDoorRect(r, DIR_RIGHT))
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

    // 地形 0
    call RegisterRoomWithAutoDoors(TERRAIN_A, gg_rct_FR_A1)
    call RegisterRoomWithAutoDoors(TERRAIN_A, gg_rct_FR_A2)
    call RegisterRoomWithAutoDoors(TERRAIN_A, gg_rct_FR_A3)
    call RegisterRoomWithAutoDoors(TERRAIN_A, gg_rct_FR_A4)
    call RegisterRoomWithAutoDoors(TERRAIN_A, gg_rct_FR_A5)

    // 地形 1
    call RegisterRoomWithAutoDoors(TERRAIN_B, gg_rct_FR_B1)
    call RegisterRoomWithAutoDoors(TERRAIN_B, gg_rct_FR_B2)
    call RegisterRoomWithAutoDoors(TERRAIN_B, gg_rct_FR_B3)
    call RegisterRoomWithAutoDoors(TERRAIN_B, gg_rct_FR_B4)
    call RegisterRoomWithAutoDoors(TERRAIN_B, gg_rct_FR_B5)

    // 地形 2
    call RegisterRoomWithAutoDoors(TERRAIN_C, gg_rct_FR_C1)
    call RegisterRoomWithAutoDoors(TERRAIN_C, gg_rct_FR_C2)
    call RegisterRoomWithAutoDoors(TERRAIN_C, gg_rct_FR_C3)
    call RegisterRoomWithAutoDoors(TERRAIN_C, gg_rct_FR_C4)
    call RegisterRoomWithAutoDoors(TERRAIN_C, gg_rct_FR_C5)

    // 地形 3
    call RegisterRoomWithAutoDoors(TERRAIN_D, gg_rct_FR_D1)
    call RegisterRoomWithAutoDoors(TERRAIN_D, gg_rct_FR_D2)
    call RegisterRoomWithAutoDoors(TERRAIN_D, gg_rct_FR_D3)
    call RegisterRoomWithAutoDoors(TERRAIN_D, gg_rct_FR_D4)
    call RegisterRoomWithAutoDoors(TERRAIN_D, gg_rct_FR_D5)

    // BOSS 预留槽（地形 -1）
    call RegisterRoomWithAutoDoors(-1, gg_rct_FR_BOSS)

    call Slot_SetAcquireHook(function OnSlotAcquire)
    call Slot_SetReleaseHook(function OnSlotRelease)
    call Slot_SetEvictFilter(function CanEvictRoom)

    call DebugLogger_Log(LOG_INFO, "[forest] physical rooms registered: slots=" + I2S(Slot_GetCount()) + " terrains=" + I2S(Slot_GetTerrainTypeCount()))
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

// Forest 关卡初始化回调，由 ChapterManager.StartChapter 触发
function InitForest takes nothing returns nothing
    local integer i = 0

    // 物理房注册只做一次；之后每次进入关卡只重建逻辑数据
    call InitForestPhysicalRooms()

    // 出生点
    call ChapterManager_SetVillageRect(gg_rct_Village)

    // 1) 逻辑网格：7×7，随机生成树 + 额外边
    call Grid_Init(FOREST_ROWS, FOREST_COLS)
    call Grid_SetPruneChance(FOREST_PRUNE_CHANCE)
    call Grid_BuildEdges()

    // 2) 注册全部逻辑房间（49 个）
    loop
        exitwhen i >= Grid_GetTotal()
        call RegisterArea(i)
        set i = i + 1
    endloop

    // 3) 起点候选：外围 8 个（4 角 + 4 边中点）
    call AreaAddPeripheralEnters()

    // 4) BOSS 候选：内部坐标（避免开局贴着外围入口）
    call AreaAddBossCandidate(Grid_GetId(2, 2))
    call AreaAddBossCandidate(Grid_GetId(3, 3))
    call AreaAddBossCandidate(Grid_GetId(4, 4))
    call RollBossArea()

    // 5) 随机确定本关入口（排除 BOSS 房）
    call RollActiveEnter(FOREST_CHAPTER_ID)

    // 6) 房间类型权重配置
    call RegisterRoomType(ROOM_TYPE_MONSTER, 30, ROOM_MAX_UNLIMITED)
    call SetRoomTypeWeight(ROOM_TYPE_MONSTER, 700)
    call RegisterRoomType(ROOM_TYPE_SAFE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_SAFE, 200)
    call RegisterRoomType(ROOM_TYPE_ELITE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_ELITE, 100)

    // 7) 执行房间类型/地形分配（仅本次激活入口为入口房）
    call InitAreaWithEnter(FOREST_CHAPTER_ID)

    // 8) 预绑定 BOSS 逻辑房到预留槽位
    if Area_EnsureBound(GetBossArea()) < 0 then
        call DebugLogger_Log(LOG_WARN, "[forest] cannot bind boss area " + GetAreaIdName(GetBossArea()))
    endif

    // 9) 物理槽位常驻触发器（必须在物理房注册之后）
    call InitAreaGuards()
    call InitAreaExits()

    // 10) 怪物组与怪物房（必须在 InitAreaWithEnter 之后）
    call InitForestMonsterGroups()
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

    // 初始化BOSS系统（BOSS 槽位已在第 8 步绑定）
    call BossSystem_InitBossSystem()
    call BossSystem_SetBossTypeId('nBO1')  // 占位符，在WE中配置实际BOSS单位ID

    // 计时器回返参数：基础15秒 × 1.0系数
    call ChapterTimer_SetChapterTimerReturnParams(15, 1.0)

    // 诅咒配置：每10秒扩散一个区域，基础伤害10，递增系数2，上限100，每1秒伤害一次
    call CurseSystem_SetCurseSpreadInterval(10.0)
    call CurseSystem_SetCurseDamageParams(10.0, 2.0, 100.0, 1.0)

    // 祭坛配置（单位类型ID在WE中配置，商店上架物品由物体编辑器配置）
    call RewardAltar_SetAltarUnitTypeId('n000')  // 祭坛单位类型ID

    call DebugLogger_Log(LOG_INFO, "[forest] InitForest done: chapter=" + I2S(FOREST_CHAPTER_ID) + " enter=" + GetAreaIdName(GetActiveEnter(FOREST_CHAPTER_ID)) + " boss=" + GetAreaIdName(GetBossArea()) + " slots=" + I2S(Slot_GetCount()))
endfunction

// Forest 关卡配置注册：在游戏初始化时调用
// 注册 Forest 关卡到 ChapterManager，绑定 InitForest 作为初始化回调
function InitForestConfig takes nothing returns nothing
    set FOREST_CHAPTER_ID = ChapterManager_RegisterChapter("Forest", 600)
    call ChapterManager_SetChapterInitFunc(FOREST_CHAPTER_ID, function InitForest)
endfunction

endlibrary
#endif
