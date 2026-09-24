#ifndef AREA_INCLUDED
#define AREA_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
#include "nncou\\magic\\map\\ui\\uiPick.j"
#include "nncou\\magic\\map\\reward\\reward.j"
#include "nncou\\magic\\map\\reward\\altar.j"
#endif
/*
    Forest 关卡配置文件

    负责注册 Forest 大区域的所有区域、邻接关系、出口、BOSS 房、入口和诅咒起始区域。
    通过 ChapterManager 统一管理初始化和关卡切换。

    Forest 有向图（24 条边）：
    A → C, N
    C → A, F
    E → N
    F → C, I
    G → H
    H → G, M, I
    I → N, J
    J → H
    K → H, L
    L → M, K
    M → N, H, L
    N → A, G, E

    出口矩形变量：
    - gg_rct_Forest_Exit_A2C    - gg_rct_Forest_Exit_A2N
    - gg_rct_Forest_Exit_C2A    - gg_rct_Forest_Exit_C2F
    - gg_rct_Forest_Exit_E2N
    - gg_rct_Forest_Exit_F2C    - gg_rct_Forest_Exit_F2I
    - gg_rct_Forest_Exit_G2H
    - gg_rct_Forest_Exit_H2G    - gg_rct_Forest_Exit_H2M    - gg_rct_Forest_Exit_H2I
    - gg_rct_Forest_Exit_I2N    - gg_rct_Forest_Exit_I2J
    - gg_rct_Forest_Exit_J2H
    - gg_rct_Forest_Exit_K2H    - gg_rct_Forest_Exit_K2L
    - gg_rct_Forest_Exit_L2M    - gg_rct_Forest_Exit_L2K
    - gg_rct_Forest_Exit_M2N    - gg_rct_Forest_Exit_M2H    - gg_rct_Forest_Exit_M2L
    - gg_rct_Forest_Exit_N2A    - gg_rct_Forest_Exit_N2G    - gg_rct_Forest_Exit_N2E
*/
library Forest initializer InitForestConfig requires ChapterManager, RewardAltar

globals
    // Forest 关卡 ID（由 RegisterChapter 返回，在 InitForestConfig 中赋值）
    private integer FOREST_CHAPTER_ID = 0

    // Forest 区域 ID 常量（A-N 中无 B，D 为 BOSS 房）
    constant integer FOREST_A = 0
    constant integer FOREST_C = 1
    constant integer FOREST_D = 2
    constant integer FOREST_E = 3
    constant integer FOREST_F = 4
    constant integer FOREST_G = 5
    constant integer FOREST_H = 6
    constant integer FOREST_I = 7
    constant integer FOREST_J = 8
    constant integer FOREST_K = 9
    constant integer FOREST_L = 10
    constant integer FOREST_M = 11
    constant integer FOREST_N = 12
endglobals

// Forest 关卡初始化回调，由 ChapterManager.StartChapter 触发
// 负责注册所有区域、邻接关系、出口、入口，并执行房间类型分配和怪物房初始化
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

function InitForest takes nothing returns nothing

    
    // 出生点
    call ChapterManager_SetVillageRect(gg_rct_Village)
    
    // 注册区域
    call RegisterArea(FOREST_A, gg_rct_Forest_A)
    call RegisterArea(FOREST_C, gg_rct_Forest_C)
    call RegisterArea(FOREST_D, gg_rct_Forest_D)
    call RegisterArea(FOREST_E, gg_rct_Forest_E)
    call RegisterArea(FOREST_F, gg_rct_Forest_F)
    call RegisterArea(FOREST_G, gg_rct_Forest_G)
    call RegisterArea(FOREST_H, gg_rct_Forest_H)
    call RegisterArea(FOREST_I, gg_rct_Forest_I)
    call RegisterArea(FOREST_J, gg_rct_Forest_J)
    call RegisterArea(FOREST_K, gg_rct_Forest_K)
    call RegisterArea(FOREST_L, gg_rct_Forest_L)
    call RegisterArea(FOREST_M, gg_rct_Forest_M)
    call RegisterArea(FOREST_N, gg_rct_Forest_N)

    // 注册邻接关系（有向边）
    call RegisterNeighbor(FOREST_A, FOREST_C)
    call RegisterNeighbor(FOREST_A, FOREST_N)
    call RegisterNeighbor(FOREST_C, FOREST_A)
    call RegisterNeighbor(FOREST_C, FOREST_F)
    call RegisterNeighbor(FOREST_E, FOREST_N)
    call RegisterNeighbor(FOREST_F, FOREST_C)
    call RegisterNeighbor(FOREST_F, FOREST_I)
    call RegisterNeighbor(FOREST_G, FOREST_H)
    call RegisterNeighbor(FOREST_H, FOREST_G)
    call RegisterNeighbor(FOREST_H, FOREST_M)
    call RegisterNeighbor(FOREST_H, FOREST_I)
    call RegisterNeighbor(FOREST_I, FOREST_N)
    call RegisterNeighbor(FOREST_I, FOREST_J)
    call RegisterNeighbor(FOREST_J, FOREST_H)
    call RegisterNeighbor(FOREST_K, FOREST_H)
    call RegisterNeighbor(FOREST_K, FOREST_L)
    call RegisterNeighbor(FOREST_L, FOREST_M)
    call RegisterNeighbor(FOREST_L, FOREST_K)
    call RegisterNeighbor(FOREST_M, FOREST_N)
    call RegisterNeighbor(FOREST_M, FOREST_H)
    call RegisterNeighbor(FOREST_M, FOREST_L)
    call RegisterNeighbor(FOREST_N, FOREST_A)
    call RegisterNeighbor(FOREST_N, FOREST_G)
    call RegisterNeighbor(FOREST_N, FOREST_E)

    // 注册出口
    call RegisterAreaExit(gg_rct_Forest_Exit_A2C, gg_rct_Forest_C, FOREST_A)
    call RegisterAreaExit(gg_rct_Forest_Exit_A2N, gg_rct_Forest_N, FOREST_A)
    call RegisterAreaExit(gg_rct_Forest_Exit_C2A, gg_rct_Forest_A, FOREST_C)
    call RegisterAreaExit(gg_rct_Forest_Exit_C2F, gg_rct_Forest_F, FOREST_C)
    call RegisterAreaExit(gg_rct_Forest_Exit_E2N, gg_rct_Forest_N, FOREST_E)
    call RegisterAreaExit(gg_rct_Forest_Exit_F2C, gg_rct_Forest_C, FOREST_F)
    call RegisterAreaExit(gg_rct_Forest_Exit_F2I, gg_rct_Forest_I, FOREST_F)
    call RegisterAreaExit(gg_rct_Forest_Exit_G2H, gg_rct_Forest_H, FOREST_G)
    call RegisterAreaExit(gg_rct_Forest_Exit_H2G, gg_rct_Forest_G, FOREST_H)
    call RegisterAreaExit(gg_rct_Forest_Exit_H2M, gg_rct_Forest_M, FOREST_H)
    call RegisterAreaExit(gg_rct_Forest_Exit_H2I, gg_rct_Forest_I, FOREST_H)
    call RegisterAreaExit(gg_rct_Forest_Exit_I2N, gg_rct_Forest_N, FOREST_I)
    call RegisterAreaExit(gg_rct_Forest_Exit_I2J, gg_rct_Forest_J, FOREST_I)
    call RegisterAreaExit(gg_rct_Forest_Exit_J2H, gg_rct_Forest_H, FOREST_J)
    call RegisterAreaExit(gg_rct_Forest_Exit_K2H, gg_rct_Forest_H, FOREST_K)
    call RegisterAreaExit(gg_rct_Forest_Exit_K2L, gg_rct_Forest_L, FOREST_K)
    call RegisterAreaExit(gg_rct_Forest_Exit_L2M, gg_rct_Forest_M, FOREST_L)
    call RegisterAreaExit(gg_rct_Forest_Exit_L2K, gg_rct_Forest_K, FOREST_L)
    call RegisterAreaExit(gg_rct_Forest_Exit_M2N, gg_rct_Forest_N, FOREST_M)
    call RegisterAreaExit(gg_rct_Forest_Exit_M2H, gg_rct_Forest_H, FOREST_M)
    call RegisterAreaExit(gg_rct_Forest_Exit_M2L, gg_rct_Forest_L, FOREST_M)
    call RegisterAreaExit(gg_rct_Forest_Exit_N2A, gg_rct_Forest_A, FOREST_N)
    call RegisterAreaExit(gg_rct_Forest_Exit_N2G, gg_rct_Forest_G, FOREST_N)
    call RegisterAreaExit(gg_rct_Forest_Exit_N2E, gg_rct_Forest_E, FOREST_N)

    // 入口区域（H, K, I, E）
    call AreaAddEnter(FOREST_H)
    call AreaAddEnter(FOREST_K)
    call AreaAddEnter(FOREST_I)
    call AreaAddEnter(FOREST_E)

    // 随机确定本次游戏的入口（使用 Forest 的 chapterId）
    call RollActiveEnter(FOREST_CHAPTER_ID)

    // BOSS房标记
    call AreaSetBossroom(FOREST_D)

    // 诅咒起始区域（远离BOSS房的外围区域）
    call AddCurseStartArea(FOREST_A)
    call AddCurseStartArea(FOREST_C)
    call AddCurseStartArea(FOREST_E)

    // 房间类型权重配置
    call RegisterRoomType(ROOM_TYPE_MONSTER, 5, 8)
    call SetRoomTypeWeight(ROOM_TYPE_MONSTER, 700)
    call RegisterRoomType(ROOM_TYPE_SAFE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_SAFE, 200)
    call RegisterRoomType(ROOM_TYPE_ELITE, 1, 2)
    call SetRoomTypeWeight(ROOM_TYPE_ELITE, 100)

    // 执行房间类型分配（仅本次激活入口为安全房，其余候选入口正常分配）
    call InitAreaWithEnter(FOREST_CHAPTER_ID)

    // 创建区域进出保护和出口触发器（必须在 InitArea 之后，所有数据注册完成之后）
    call InitAreaGuards()
    call InitAreaExits()

    // 创建并注册怪物组（必须在 InitMonsterRoom 之前，否则池为空导致各怪物房无法绑定组）
    call InitForestMonsterGroups()

    // 初始化怪物房系统（必须在 InitArea 之后）
    // 怪物组按难度档位在 InitMonsterRoom 中随机绑定到各怪物房
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

    // 初始化BOSS系统
    call BossSystem_InitBossSystem()
    call BossSystem_SetBossTypeId('nBO1')  // 占位符，在WE中配置实际BOSS单位ID

    // 计时器回返参数：基础15秒 × 1.0系数
    call ChapterTimer_SetChapterTimerReturnParams(15, 1.0)

    // 诅咒配置：每10秒扩散一个区域，基础伤害10，递增系数2，上限100，每1秒伤害一次
    call CurseSystem_SetCurseSpreadInterval(10.0)
    call CurseSystem_SetCurseDamageParams(10.0, 2.0, 100.0, 1.0)

    // 祭坛配置（单位类型ID在WE中配置，商店上架物品由物体编辑器配置）
    call RewardAltar_SetAltarUnitTypeId('n000')  // 祭坛单位类型ID

endfunction

// Forest 关卡配置注册：在游戏初始化时调用
// 注册 Forest 关卡到 ChapterManager，绑定 InitForest 作为初始化回调
function InitForestConfig takes nothing returns nothing
    set FOREST_CHAPTER_ID = ChapterManager_RegisterChapter("Forest", 600)
    call ChapterManager_SetChapterInitFunc(FOREST_CHAPTER_ID, function InitForest)
endfunction

endlibrary
