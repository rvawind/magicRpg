#ifndef AREA_INCLUDED
#define AREA_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
#endif
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
    // TODO: 注册区域
    // call RegisterArea(DUST_A, gg_rct_Dust_A)

    // TODO: 注册邻接关系

    // TODO: 注册区域保护

    // TODO: 注册出口

    // TODO: 入口区域
    // call AreaAddEnter(DUST_A)
    // call RollActiveEnter(DUST_CHAPTER_ID)

    // TODO: 诅咒起始区域

    // TODO: 房间类型权重配置

    // 执行房间类型分配（仅本次激活入口为安全房，其余候选入口正常分配）
    // call InitAreaWithEnter(DUST_CHAPTER_ID)

    // 初始化怪物房系统（必须在 InitArea 之后）
    // call InitMonsterRoom()
endfunction

// Dust 关卡配置注册：在游戏初始化时调用
// 注册 Dust 关卡到 ChapterManager，绑定 InitDust 作为初始化回调
function InitDustConfig takes nothing returns nothing
    set DUST_CHAPTER_ID = ChapterManager_RegisterChapter("Dust", 600)
    call ChapterManager_SetChapterInitFunc(DUST_CHAPTER_ID, function InitDust)
endfunction

endlibrary
