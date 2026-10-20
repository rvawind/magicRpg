#ifndef DUST_INCLUDED
#define DUST_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
/*
    Dust 关卡配置文件

    负责注册 Dust 大区域的所有区域、邻接关系、出口、BOSS 房、入口和诅咒起始区域。
    通过 ChapterManager 统一管理初始化和关卡切换。

    Dust 有向图：
    待定

    出口矩形变量：
    待定
*/
library Dust initializer InitDustConfig requires ChapterManager

globals
    // Dust 关卡 ID（由 RegisterChapter 返回，在 InitDustConfig 中赋值）
    private integer DUST_CHAPTER_ID = 0
endglobals

// Dust 关卡初始化回调，由 ChapterManager.StartChapter 触发
// TODO: 待填充具体的区域注册、邻接、出口、入口等配置
function InitDust takes nothing returns nothing
    // TODO: Step 3 起 Dust 也使用「逻辑网格 + 物理槽位」模型：
    // 1) 在 WE 中摆放 Dust 的物理房，并用 areaSlot_RegisterPhysicalRoom 注册（每个关卡一套物理房）；
    // 2) Grid_Init(rows, cols) / Grid_SetPruneChance / Grid_BuildEdges；
    // 3) 循环 RegisterArea(i) 注册全部逻辑房；
    // 4) AreaAddEnter / AreaAddPeripheralEnters 配置起点；
    // 5) AreaAddBossCandidate + RollBossArea；
    // 6) RegisterRoomType + SetRoomTypeWeight；
    // 7) RollActiveEnter(DUST_CHAPTER_ID) + InitAreaWithEnter(DUST_CHAPTER_ID)；
    // 8) InitAreaGuards / InitAreaExits / InitMonsterRoom。
endfunction

// Dust 关卡配置注册：在游戏初始化时调用
// 注册 Dust 关卡到 ChapterManager，绑定 InitDust 作为初始化回调
function InitDustConfig takes nothing returns nothing
    set DUST_CHAPTER_ID = ChapterManager_RegisterChapter("Dust", 600)
    call ChapterManager_SetChapterInitFunc(DUST_CHAPTER_ID, function InitDust)
endfunction

endlibrary
#endif
