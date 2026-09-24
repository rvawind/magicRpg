#ifndef REWARD_ITEM_INCLUDED
#define REWARD_ITEM_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\ui\\uiPick.j"
#include "japi\\YDWEAbilityState.j"
#include "nncou\\debug.j"
/*
    奖励物品模块

    仅作为WE触发器的中转口，不主动调起UI。
    流程：
    1. 玩家击败房间怪物 → 生成祭坛
    2. 玩家购买祭坛物品 → 监听购买事件
    3. 购买事件调用 CreateReward → 仅调起WE侧的触发器
    4. WE触发器内：根据玩家属性创建物品 → 调用 RegisterRewardItem 注册
    5. WE触发器内：调用 ShowRewardForPlayer 将物品数据传回UI模块

    依赖：areaData, UiPick
*/
library RewardItem initializer InitRewardItem requires areaData, UiPick, DebugLogger

globals
    private hashtable RewardTable = InitHashtable()
    // 每个区域的奖励数据（parent key = areaId）
    private constant integer HT_REWARD_TIER = 0
    private constant integer HT_REWARD_COUNT = 1
    private constant integer HT_REWARD_ITEM = 10
    private constant integer HT_REWARD_ITEM_ICON = 20
    private constant integer HT_REWARD_ITEM_NAME = 30
    private constant integer HT_REWARD_ITEM_DESC = 40
    private constant integer HT_PLAYER_CLAIMED = 50
    // 全局（parent key = 0）
    private constant integer HT_CREATE_TRIGGER = 60
    private constant integer HT_CHOOSE_TRIGGER = 61
    private constant integer HT_CURRENT_AREA = 62
    private constant integer HT_CURRENT_TIER = 63
    private constant integer HT_CURRENT_PLAYER = 64
    // 每个玩家当前交互的奖励区域（parent key = playerId）
    private constant integer HT_PLAYER_REWARD_AREA = 80
    private constant integer HT_REWARD_LIST_COUNT = 70
    private constant integer HT_REWARD_LIST = 71
    private constant integer MAX_REWARD_ITEMS = 5
endglobals

// ===== 公开接口 =====

/*
    [RewardItem_SetRewardCreateTrigger]
    title = "设置物品创建触发器"
    description = "设置WE的${触发器}，在创建奖励时执行，触发器内通过 GetRewardAreaId/GetRewardTier 获取上下文"
    category = TC_MAGIC
    [[.args]]
    type = trigger
*/
public function SetRewardCreateTrigger takes trigger t returns nothing
    call SaveTriggerHandle(RewardTable, 0, HT_CREATE_TRIGGER, t)
    call DebugLogger_Log(LOG_INFO, "[reward] SetRewardCreateTrigger: t=" + I2S(GetHandleId(t)) + " (0=null) savedTo HT_CREATE_TRIGGER")
endfunction

/*
    [RewardItem_SetRewardOnChooseTrigger]
    title = "设置选择后触发器"
    description = "设置玩家选择物品后的${回调触发器}"
    category = TC_MAGIC
    [[.args]]
    type = trigger
*/
public function SetRewardOnChooseTrigger takes trigger t returns nothing
    call SaveTriggerHandle(RewardTable, 0, HT_CHOOSE_TRIGGER, t)
    call DebugLogger_Log(LOG_INFO, "[reward] SetRewardOnChooseTrigger: t=" + I2S(GetHandleId(t)) + " (0=null) savedTo HT_CHOOSE_TRIGGER")
endfunction

/*
    [RewardItem_GetRewardAreaId]
    title = "获取奖励区域ID"
    description = "在物品创建触发器内调用，获取当前奖励的区域ID"
    category = TC_MAGIC
    returns = integer
*/
public function GetRewardAreaId takes nothing returns integer
    return LoadInteger(RewardTable, 0, HT_CURRENT_AREA)
endfunction

/*
    [RewardItem_GetRewardTier]
    title = "获取奖励等级"
    description = "在物品创建触发器内调用，获取当前奖励等级（1=普通 2=精英 3=BOSS）"
    category = TC_MAGIC
    returns = integer
*/
public function GetRewardTier takes nothing returns integer
    return LoadInteger(RewardTable, 0, HT_CURRENT_TIER)
endfunction

/*
    [RewardItem_GetRewardPlayerId]
    title = "获取购买玩家ID"
    description = "在物品创建触发器内调用，获取当前购买奖励的玩家ID"
    category = TC_MAGIC
    returns = integer
*/
public function GetRewardPlayerId takes nothing returns integer
    return LoadInteger(RewardTable, 0, HT_CURRENT_PLAYER)
endfunction

/*
    [RewardItem_RegisterRewardItem]
    title = "注册奖励物品"
    description = "在物品创建触发器内调用，注册第${索引}个奖励物品，自动提取图标/名称/描述"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = item
*/
public function RegisterRewardItem takes integer index, item it returns nothing
    local integer areaId = LoadInteger(RewardTable, 0, HT_CURRENT_AREA)
    local integer itemCode = GetItemTypeId(it)
    local string icon = EXGetItemDataString(itemCode, 1)
    local string name = GetItemName(it)
    local string desc = EXGetItemDataString(itemCode, 3)
    local integer count
    if areaId < 0 or index < 0 or index >= MAX_REWARD_ITEMS then
        call DebugLogger_Log(LOG_WARN, "[reward] RegisterRewardItem rejected: areaId=" + I2S(areaId) + " index=" + I2S(index) + " (area<0 或 index 越界)")
        return
    endif
    // 保存物品数据
    call SaveItemHandle(RewardTable, areaId, HT_REWARD_ITEM + index, it)
    call SaveStr(RewardTable, areaId, HT_REWARD_ITEM_ICON + index, icon)
    call SaveStr(RewardTable, areaId, HT_REWARD_ITEM_NAME + index, name)
    call SaveStr(RewardTable, areaId, HT_REWARD_ITEM_DESC + index, desc)
    set count = LoadInteger(RewardTable, areaId, HT_REWARD_COUNT)
    if index >= count then
        call SaveInteger(RewardTable, areaId, HT_REWARD_COUNT, index + 1)
    endif
    call DebugLogger_Log(LOG_INFO, "[reward] RegisterRewardItem area=" + GetAreaIdName(areaId) + " idx=" + I2S(index) + " item=" + I2S(itemCode) + " name=" + name + " countNow=" + I2S(LoadInteger(RewardTable, areaId, HT_REWARD_COUNT)))
endfunction

/*
    [RewardItem_CreateReward]
    title = "创建奖励"
    description = "为${区域ID}创建${等级}的奖励，购买玩家ID为${玩家ID}，仅调起WE侧触发器"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function CreateReward takes integer areaId, integer rewardTier, integer playerId returns nothing
    local trigger createTrig = LoadTriggerHandle(RewardTable, 0, HT_CREATE_TRIGGER)
    local integer count
    call DebugLogger_Log(LOG_INFO, "[reward] CreateReward area=" + GetAreaIdName(areaId) + " tier=" + I2S(rewardTier) + " pid=" + I2S(playerId) + " createTrig=" + I2S(GetHandleId(createTrig)))
    // 保存当前上下文（供WE触发器内读取）
    call SaveInteger(RewardTable, 0, HT_CURRENT_AREA, areaId)
    call SaveInteger(RewardTable, 0, HT_CURRENT_TIER, rewardTier)
    call SaveInteger(RewardTable, 0, HT_CURRENT_PLAYER, playerId)
    call SaveInteger(RewardTable, areaId, HT_REWARD_TIER, rewardTier)
    call SaveInteger(RewardTable, areaId, HT_REWARD_COUNT, 0)
    // 追踪该区域用于清理
    set count = LoadInteger(RewardTable, 0, HT_REWARD_LIST_COUNT)
    call SaveInteger(RewardTable, 0, HT_REWARD_LIST + count, areaId)
    call SaveInteger(RewardTable, 0, HT_REWARD_LIST_COUNT, count + 1)
    // 仅调起WE侧触发器，由触发器内注册物品并调用ShowRewardForPlayer
    if createTrig != null then
        call TriggerExecute(createTrig)
        call DebugLogger_Log(LOG_INFO, "[reward] CreateReward: TriggerExecute done, registeredCount=" + I2S(LoadInteger(RewardTable, areaId, HT_REWARD_COUNT)))
    else
        call DebugLogger_Log(LOG_WARN, "[reward] CreateReward: createTrig is NULL! SetRewardCreateTrigger 未注册，WE侧物品创建触发器不会执行")
    endif
    set createTrig = null
endfunction

/*
    [RewardItem_IsPlayerClaimed]
    title = "玩家是否已领取"
    description = "判断${玩家ID}在${区域ID}是否已领取奖励"
    category = TC_MAGIC
    returns = boolean
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function IsPlayerClaimed takes integer areaId, integer playerId returns boolean
    return LoadBoolean(RewardTable, areaId, HT_PLAYER_CLAIMED + playerId)
endfunction

/*
    [RewardItem_ShowRewardForPlayer]
    title = "为玩家显示奖励UI"
    description = "WE触发器内注册完物品后调用，为${玩家ID}显示${区域ID}的奖励选择UI"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function ShowRewardForPlayer takes integer areaId, integer playerId returns nothing
    local integer count = LoadInteger(RewardTable, areaId, HT_REWARD_COUNT)
    local integer i = 0
    local string icon
    local string name
    local string desc
    call DebugLogger_Log(LOG_INFO, "[reward] ShowRewardForPlayer area=" + GetAreaIdName(areaId) + " pid=" + I2S(playerId) + " count=" + I2S(count))
    if count <= 0 then
        call DebugLogger_Log(LOG_WARN, "[reward] ShowRewardForPlayer: count=0, WE触发器未注册任何候选物品，UI不弹")
        return
    endif
    if LoadBoolean(RewardTable, areaId, HT_PLAYER_CLAIMED + playerId) then
        call DebugLogger_Log(LOG_INFO, "[reward] ShowRewardForPlayer: pid=" + I2S(playerId) + " already claimed, skip UI")
        return
    endif
    // 保存该玩家当前交互的奖励区域
    call SaveInteger(RewardTable, playerId, HT_PLAYER_REWARD_AREA, areaId)
    loop
        exitwhen i >= count
        set icon = LoadStr(RewardTable, areaId, HT_REWARD_ITEM_ICON + i)
        set name = LoadStr(RewardTable, areaId, HT_REWARD_ITEM_NAME + i)
        set desc = LoadStr(RewardTable, areaId, HT_REWARD_ITEM_DESC + i)
        call UiPick_SetChoiceContent(playerId, i, icon, name, desc)
        set i = i + 1
    endloop
    call UiPick_Show(playerId, count)
    call DebugLogger_Log(LOG_INFO, "[reward] ShowRewardForPlayer: UiPick_Show called for pid=" + I2S(playerId))
endfunction

/*
    [RewardItem_OnPlayerChoose]
    title = "玩家选择回调"
    description = "由UiPick在玩家点击选择后调用，给予对应物品"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function OnPlayerChoose takes integer playerId, integer choiceIndex returns nothing
    local integer areaId = LoadInteger(RewardTable, playerId, HT_PLAYER_REWARD_AREA)
    local item it = LoadItemHandle(RewardTable, areaId, HT_REWARD_ITEM + choiceIndex)
    local unit hero
    local trigger chooseTrig
    call DebugLogger_Log(LOG_INFO, "[reward] OnPlayerChoose pid=" + I2S(playerId) + " choice=" + I2S(choiceIndex) + " area=" + GetAreaIdName(areaId))
    if areaId < 0 then
        call DebugLogger_Log(LOG_WARN, "[reward] OnPlayerChoose: areaId<0, 玩家无当前交互奖励区域，放弃")
        set it = null
        return
    endif
    // 标记已领取
    call SaveBoolean(RewardTable, areaId, HT_PLAYER_CLAIMED + playerId, true)
    // 给予英雄物品
    set hero = udg_Hero[playerId]
    if hero != null and it != null then
        call UnitAddItem(hero, it)
        call DebugLogger_Log(LOG_INFO, "[reward] OnPlayerChoose: 给予英雄物品 (hero=" + GetUnitName(hero) + ")")
    else
        call DebugLogger_Log(LOG_WARN, "[reward] OnPlayerChoose: hero=" + I2S(GetHandleId(hero)) + " item=" + I2S(GetHandleId(it)) + " 至少一个为null，物品未发放（检查 udg_Hero[" + I2S(playerId) + "]）")
    endif
    // 执行选择后回调
    set chooseTrig = LoadTriggerHandle(RewardTable, 0, HT_CHOOSE_TRIGGER)
    if chooseTrig != null then
        call TriggerExecute(chooseTrig)
    else
        call DebugLogger_Log(LOG_INFO, "[reward] OnPlayerChoose: chooseTrig 为 NULL（未注册选择后触发器，若有收尾逻辑需 SetRewardOnChooseTrigger）")
    endif
    set it = null
    set hero = null
    set chooseTrig = null
endfunction

// ===== 初始化 =====

// UiPick 选择回调：作为 code 传给 TriggerAddAction，须在 InitRewardItem 之前声明
private function Trig_UiPickChosen takes nothing returns nothing
    local integer pid = UiPick_GetChoicePlayer()
    local integer index = UiPick_GetChoiceIndex()
    call OnPlayerChoose(pid, index)
endfunction

private function InitRewardItem takes nothing returns nothing
    // 注册UiPick的选择回调
    local trigger pickTrig = CreateTrigger()
    call TriggerAddAction(pickTrig, function Trig_UiPickChosen)
    call UiPick_SetChooseTrigger(pickTrig)
    set pickTrig = null
endfunction

// 重置奖励系统：清除所有奖励数据
// 供 ChapterManager 在关卡切换时调用
function ResetRewardItem takes nothing returns nothing
    local integer listCount = LoadInteger(RewardTable, 0, HT_REWARD_LIST_COUNT)
    local integer i = 0
    local integer areaId
    local integer j
    local integer count
    local item it
    local trigger createTrigBefore = LoadTriggerHandle(RewardTable, 0, HT_CREATE_TRIGGER)
    call DebugLogger_Log(LOG_INFO, "[reward] ResetRewardItem BEGIN: listCount=" + I2S(listCount) + " createTrig(before)=" + I2S(GetHandleId(createTrigBefore)))
    loop
        exitwhen i >= listCount
        set areaId = LoadInteger(RewardTable, 0, HT_REWARD_LIST + i)
        set count = LoadInteger(RewardTable, areaId, HT_REWARD_COUNT)
        set j = 0
        loop
            exitwhen j >= count
            set it = LoadItemHandle(RewardTable, areaId, HT_REWARD_ITEM + j)
            if it != null then
                call RemoveItem(it)
            endif
            set j = j + 1
        endloop
        call FlushChildHashtable(RewardTable, areaId)
        set i = i + 1
    endloop
    // 清理每个玩家级数据（HT_PLAYER_REWARD_AREA 存于 parent=playerId，玩家ID 为 1-based）
    // 注意：从 1 开始遍历，绝不能 FlushChildHashtable(RewardTable, 0)，否则会清掉
    //       HT_CREATE_TRIGGER / HT_CHOOSE_TRIGGER 等存于 parent=0 的跨关卡常驻数据
    set i = 1
    loop
        exitwhen i >= bj_MAX_PLAYERS
        call FlushChildHashtable(RewardTable, i)
        set i = i + 1
    endloop
    // 仅清理运行时跟踪列表，保留 HT_CREATE_TRIGGER / HT_CHOOSE_TRIGGER
    // （WE 侧注册的触发器句柄，跨关卡常驻，关卡切换不应清除）
    set i = 0
    loop
        exitwhen i >= listCount
        call RemoveSavedInteger(RewardTable, 0, HT_REWARD_LIST + i)
        set i = i + 1
    endloop
    call SaveInteger(RewardTable, 0, HT_REWARD_LIST_COUNT, 0)
    call DebugLogger_Log(LOG_INFO, "[reward] ResetRewardItem END: createTrig(after)=" + I2S(GetHandleId(LoadTriggerHandle(RewardTable, 0, HT_CREATE_TRIGGER))) + " chooseTrig(after)=" + I2S(GetHandleId(LoadTriggerHandle(RewardTable, 0, HT_CHOOSE_TRIGGER))))
    set it = null
    set createTrigBefore = null
endfunction

endlibrary
#endif
