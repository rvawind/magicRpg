#ifndef CHAPTER_MANAGER_INCLUDED
#define CHAPTER_MANAGER_INCLUDED
#include "nncou\\debug.j"
#include "nncou\\magic\\map\\area\\core\\grid.j"
#include "nncou\\magic\\map\\area\\core\\slot.j"
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
#include "nncou\\magic\\map\\area\\core\\emergency.j"
#include "nncou\\magic\\map\\timer\\timer.j"
#include "nncou\\magic\\map\\curse\\curse.j"
#include "nncou\\magic\\map\\boss\\boss.j"
#include "nncou\\magic\\map\\ui\\uiPick.j"
#include "nncou\\magic\\map\\reward\\reward.j"
#include "nncou\\magic\\map\\reward\\altar.j"
/*
    关卡管理模块

    负责：
    1. 管理多个关卡的切换
    2. 在关卡切换时统一重置所有子系统，确保关卡间数据不互相干扰
    3. 调用各关卡的初始化回调函数
    4. 章节完成事件

    使用方式：
    - 各关卡配置文件（如 forest.j）在初始化时调用 RegisterChapter + SetChapterInitFunc 注册自身
    - 通过 StartChapter 切换关卡，ChapterManager 自动完成：重置子系统 → 调用init回调 → 启动计时器
    - 关卡配置文件的 init 回调中调用 RegisterArea / RegisterNeighbor / InitArea 等接口

    依赖：areaData, areaEnter, areaExit, areaMonsterRoom, ChapterTimer, CurseSystem, BossSystem
*/
library ChapterManager requires areaGrid, areaSlot, areaData, areaEnter, areaExit, areaMonsterRoom, ChapterTimer, CurseSystem, BossSystem, RewardAltar, RewardItem, UiPick, DebugLogger

globals
    private hashtable ChapterTable = InitHashtable()

    // 章节状态（parent key = 0）
    private constant integer HT_CURRENT_CHAPTER = 0
    private constant integer HT_CHAPTER_COUNT = 1

    // 每个关卡配置（parent key = chapterId）
    private constant integer HT_CHAPTER_NAME = 0
    private constant integer HT_CHAPTER_TIME = 1
    private constant integer HT_CHAPTER_STATE = 2

    // 章节状态常量
    constant integer CHAPTER_STATE_INACTIVE = 0
    constant integer CHAPTER_STATE_ACTIVE = 1
    constant integer CHAPTER_STATE_COMPLETED = 2

    // 各关卡初始化回调触发器（通过 SetChapterInitFunc 注册）
    private trigger array ChapterInitTrig

    // 村落复活/传送点矩形（由外部通过 SetVillageRect 注入，替代直接引用 gg_rct_Village）
    public rect VillageRect = null
endglobals

// ===== 钩子（private，可在 chapter.j 内部覆写）=====
// 注意：库内调用只能引用上方已定义的函数（与长短名无关），故按调用依赖排列顺序。

// 关卡完成时触发：传送所有英雄回村落
private function OnChapterComplete takes integer chapterId returns nothing
    local group g = CreateGroup()
    local unit u
    local integer i = 0
    loop
        exitwhen i >= 12
        set u = udg_Hero[i]
        if u != null then
            call GroupAddUnit(g, u)
        endif
        set i = i + 1
    endloop
    set u = FirstOfGroup(g)
    loop
        exitwhen u == null
        call SetUnitX(u, GetRectCenterX(VillageRect))
        call SetUnitY(u, GetRectCenterY(VillageRect))
        call GroupRemoveUnit(g, u)
        set u = FirstOfGroup(g)
    endloop
    call DestroyGroup(g)
    set g = null
    set u = null
endfunction

// 所有关卡完成时触发
private function OnAllChapterComplete takes nothing returns nothing
endfunction

// 完成当前关卡：标记完成、停诅咒/计时器、触发完成钩子
// 须在 OnBossDeathHandler 之前声明（后者调用本函数）
/*
    [CompleteChapter]
    title = "完成当前关卡"
    description = "标记当前关卡为已完成"
    category = TC_FRO
*/
public function CompleteChapter takes nothing returns nothing
    local integer chapterId = LoadInteger(ChapterTable, 0, HT_CURRENT_CHAPTER)
    local integer totalCount = LoadInteger(ChapterTable, 0, HT_CHAPTER_COUNT)
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_STATE, CHAPTER_STATE_COMPLETED)
    // 停止诅咒和计时器
    call CurseSystem_StopCurseSpread()
    call ChapterTimer_PauseChapterTimer()
    // 触发钩子
    call OnChapterComplete(chapterId)
    // 检查是否全部完成
    if chapterId >= totalCount - 1 then
        call OnAllChapterComplete()
    endif
endfunction

// BOSS死亡处理器：完成关卡 + BOSS奖励
// 作为 code 传给 BossSystem_RegisterBossDeathCallback，须在 OnChapterStart 之前声明
private function OnBossDeathHandler takes nothing returns nothing
    // 第二参数是房间类型：ROOM_TYPE_BOSS 映射到最高奖励等级
    call RewardAltar_SpawnAltar(BossSystem_GetBossRoomId(), ROOM_TYPE_BOSS)
    call CompleteChapter()
endfunction

// 关卡开始时触发：注册BOSS死亡回调
private function OnChapterStart takes integer chapterId returns nothing
    call BossSystem_RegisterBossDeathCallback(function OnBossDeathHandler)
endfunction

// 关卡切换前触发，返回false可取消切换
private function CanSwitchChapter takes integer fromId, integer toId returns boolean
    return true
endfunction

// ===== 内部：统一重置所有子系统 =====

// 按依赖逆序重置：先清理依赖其他模块的系统，最后清理基础数据
// 顺序：BossSystem → RewardAltar → RewardItem → MonsterRoom → CurseSystem → AreaExit
//       → AreaEmergency → AreaEnter → AreaData → AreaSlot → AreaGrid
private function ResetAllSubsystems takes nothing returns nothing
    call ResetBossSystem()
    call ResetRewardAltar()
    call ResetRewardItem()
    call ResetMonsterRoom()
    call ResetCurseSystem()
    call ResetAreaExit()
    call ResetAreaEmergency()
    call ResetAreaEnter()
    call ResetAreaData()
    // 逻辑数据清空后再清物理绑定；ResetAreaSlot 需要旧网格尺寸来清理粘性记忆
    call ResetAreaSlot()
    call ResetAreaGrid()
endfunction

// ===== 公开接口 =====

/*
    [ChapterManager_SetVillageRect]
    title = "设置村落矩形"
    description = "设置关卡完成时英雄传送回的${村落矩形}"
    category = TC_FRO
    [[.args]]
    type = rect
*/
public function SetVillageRect takes rect r returns nothing
    set VillageRect = r
endfunction

/*
    [ChapterManager_RegisterChapter]
    title = "注册关卡"
    description = "注册名为${名称}的关卡，基础时间为${秒数}秒"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = string
    [[.args]]
    type = integer
*/
public function RegisterChapter takes string name, integer baseTime returns integer
    local integer chapterId = LoadInteger(ChapterTable, 0, HT_CHAPTER_COUNT)
    call SaveStr(ChapterTable, chapterId, HT_CHAPTER_NAME, name)
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_TIME, baseTime)
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_STATE, CHAPTER_STATE_INACTIVE)
    call SaveInteger(ChapterTable, 0, HT_CHAPTER_COUNT, chapterId + 1)
    return chapterId
endfunction

// 绑定关卡初始化回调函数
// 必须在 RegisterChapter 之后调用，initFunc 中完成区域注册、出口注册、InitArea 等全部初始化工作
public function SetChapterInitFunc takes integer chapterId, code initFunc returns nothing
    set ChapterInitTrig[chapterId] = CreateTrigger()
    call TriggerAddAction(ChapterInitTrig[chapterId], initFunc)
endfunction

/*
    [ChapterManager_SetChapterTime]
    title = "设置关卡时间"
    description = "设置${指定ID}关卡的基础时间为${秒数}秒"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function SetChapterTime takes integer chapterId, integer seconds returns nothing
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_TIME, seconds)
endfunction

/*
    [ChapterManager_StartChapter]
    title = "开始关卡"
    description = "开始${指定ID}的关卡"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function StartChapter takes integer chapterId returns nothing
    local integer current = LoadInteger(ChapterTable, 0, HT_CURRENT_CHAPTER)
    local integer baseTime
    if not CanSwitchChapter(current, chapterId) then
        return
    endif
    // 重置所有子系统，清空上一关卡的运行时状态
    call ResetAllSubsystems()
    // 调用新关卡的初始化回调（注册区域、邻接、出口、BOSS、入口、InitArea 等）
    if ChapterInitTrig[chapterId] != null then
        call TriggerExecute(ChapterInitTrig[chapterId])
    endif
    // 设置当前章节
    call SaveInteger(ChapterTable, 0, HT_CURRENT_CHAPTER, chapterId)
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_STATE, CHAPTER_STATE_ACTIVE)
    // 配置并启动计时器
    set baseTime = LoadInteger(ChapterTable, chapterId, HT_CHAPTER_TIME)
    call ChapterTimer_SetChapterTimerBaseTime(baseTime)
    call ChapterTimer_StartChapterTimer()
    // 触发钩子
    call OnChapterStart(chapterId)
endfunction

/*
    [ChapterManager_GetCurrentChapter]
    title = "获取当前关卡"
    description = "获取当前进行的关卡ID"
    category = TC_FRO
    returns = integer
*/
public function GetCurrentChapter takes nothing returns integer
    return LoadInteger(ChapterTable, 0, HT_CURRENT_CHAPTER)
endfunction

/*
    [ChapterManager_GetChapterState]
    title = "获取关卡状态"
    description = "获取${指定ID}关卡的状态"
    category = TC_FRO
    returns = integer
    [[.args]]
    type = integer
*/
public function GetChapterState takes integer chapterId returns integer
    return LoadInteger(ChapterTable, chapterId, HT_CHAPTER_STATE)
endfunction

/*
    [ChapterManager_IsChapterActive]
    title = "关卡是否进行中"
    description = "判断${指定ID}关卡是否正在进行中"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = integer
*/
public function IsChapterActive takes integer chapterId returns boolean
    return LoadInteger(ChapterTable, chapterId, HT_CHAPTER_STATE) == CHAPTER_STATE_ACTIVE
endfunction

/*
    [ChapterManager_GetChapterName]
    title = "获取关卡名称"
    description = "获取${指定ID}关卡的名称"
    category = TC_FRO
    returns = string
    [[.args]]
    type = integer
*/
public function GetChapterName takes integer chapterId returns string
    return LoadStr(ChapterTable, chapterId, HT_CHAPTER_NAME)
endfunction

/*
    [ChapterManager_NextChapter]
    title = "切换到下一关"
    description = "切换到下一个关卡"
    category = TC_FRO
*/
public function NextChapter takes nothing returns nothing
    local integer current = LoadInteger(ChapterTable, 0, HT_CURRENT_CHAPTER)
    local integer totalCount = LoadInteger(ChapterTable, 0, HT_CHAPTER_COUNT)
    local integer next = current + 1
    if next >= totalCount then
        return
    endif
    call StartChapter(next)
endfunction

/*
    [RestartChapter]
    title = "重启当前关卡"
    description = "重新开始当前关卡"
    category = TC_FRO
*/
public function RestartChapter takes nothing returns nothing
    local integer chapterId = LoadInteger(ChapterTable, 0, HT_CURRENT_CHAPTER)
    call SaveInteger(ChapterTable, chapterId, HT_CHAPTER_STATE, CHAPTER_STATE_INACTIVE)
    // StartChapter 内部会先 ResetAllSubsystems 再调用 init 回调
    call StartChapter(chapterId)
endfunction

/*
    [ChapterManager_GetChapterCount]
    title = "获取关卡总数"
    description = "获取已注册的关卡数量"
    category = TC_FRO
    returns = integer
*/
public function GetChapterCount takes nothing returns integer
    return LoadInteger(ChapterTable, 0, HT_CHAPTER_COUNT)
endfunction

private function FindChapterIdByName takes string name returns integer
    local integer count = LoadInteger(ChapterTable, 0, HT_CHAPTER_COUNT)
    local integer i = 0
    loop
        exitwhen i >= count
        if LoadStr(ChapterTable, i, HT_CHAPTER_NAME) == name then
            return i
        endif
        set i = i + 1
    endloop
    return -1
endfunction

/*
    [ChapterManager_ChapterEnter]
    title = "关卡开启"
    description = "开启${关卡名}关卡，将${英雄单位组}中的英雄传送到关卡入口中央"
    category = TC_FRO
    [[.args]]
    type = string
    [[.args]]
    type = group
*/
public function ChapterEnter takes string chapterName, group heroGroup returns nothing
    local integer chapterId = FindChapterIdByName(chapterName)
    local rect enterRect
    local real cx
    local real cy
    local group tempGroup
    local unit u
    if chapterId < 0 then
        call DebugLogger_Log(LOG_ERROR, "[chapter] ChapterEnter: chapter not found: " + chapterName)
        return
    endif
    call DebugLogger_Log(LOG_INFO, "[chapter] ChapterEnter: starting chapter " + chapterName + " id=" + I2S(chapterId))
    call StartChapter(chapterId)
    set enterRect = GetActiveEnterRect(chapterId)
    if enterRect == null then
        call DebugLogger_Log(LOG_ERROR, "[chapter] ChapterEnter: enterRect is null after StartChapter")
        return
    endif
    call DebugLogger_Log(LOG_INFO, "[chapter] ChapterEnter: enterRect bounds X=" + R2S(GetRectMinX(enterRect)) + ".." + R2S(GetRectMaxX(enterRect)) + " Y=" + R2S(GetRectMinY(enterRect)) + ".." + R2S(GetRectMaxY(enterRect)))
    set cx = (GetRectMinX(enterRect) + GetRectMaxX(enterRect)) / 2.0
    set cy = (GetRectMinY(enterRect) + GetRectMaxY(enterRect)) / 2.0
    set tempGroup = CreateGroup()
    call GroupAddGroup(heroGroup, tempGroup)
    set u = FirstOfGroup(tempGroup)
    loop
        exitwhen u == null
        call DebugLogger_Log(LOG_INFO, "[chapter] ChapterEnter: teleporting " + GetUnitName(u) + " to (" + R2S(cx) + "," + R2S(cy) + ")")
        // 先授权离开原位置（跨关卡时可能仍在上一关的槽位矩形内）
        call AllowPlayerLeaveAreaOnce(GetOwningPlayer(u))
        // 用 SetUnitPosition：会触发区域进入事件，入口房的 guard 会自动记录当前区域
        call SetUnitPosition(u, cx, cy)
        // 即使进入事件未触发（例如坐标刚好未跨入矩形），也保证系统记录正确
        call SetPlayerCurrentAreaRect(GetOwningPlayer(u), enterRect)
        call DebugLogger_Log(LOG_INFO, "[chapter] ChapterEnter: " + GetUnitName(u) + " actual pos=(" + R2S(GetUnitX(u)) + "," + R2S(GetUnitY(u)) + ")")
        call GroupRemoveUnit(tempGroup, u)
        set u = FirstOfGroup(tempGroup)
    endloop
    call DestroyGroup(tempGroup)
    // 计时器已在 StartChapter 中启动
    set enterRect = null
    set tempGroup = null
    set u = null
endfunction

endlibrary
#include "nncou\\magic\\map\\area\\config\\forest.j"
#include "nncou\\magic\\map\\area\\config\\dust.j"
#endif
