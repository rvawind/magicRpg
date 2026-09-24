#ifndef REWARD_ALTAR_INCLUDED
#define REWARD_ALTAR_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\reward\\reward.j"
#include "nncou\\debug.j"
/*
    祭坛模块

    在房间清空后生成祭坛（中立商店），玩家靠近后可购买物品触发奖励流程。
    祭坛提供一个固定物品（或数个固定物品区分奖励等级），监听玩家购买事件，
    购买后调用 CreateReward 调起WE侧触发器，由触发器决定后续逻辑。

    使用方式：
    1. 通过 SetAltarUnitTypeId/SetAltarItemTypeId 配置祭坛和物品类型
    2. 清房后调用 SpawnAltar 生成祭坛
    3. 玩家购买物品时触发 CreateReward → WE触发器注册物品并调起UI

    依赖：areaData, RewardItem
*/
library RewardAltar initializer InitAltar requires areaData, RewardItem, DebugLogger

globals
    private hashtable AltarTable = InitHashtable()
    // 全局配置（parent key = 0）
    private constant integer HT_ALTAR_TYPE_ID = 50
    private constant integer HT_ALTAR_TIER = 52
    // 触发奖励流程的出售物品类型ID（祭坛可售卖多个物品，仅购买此物品才触发奖励）
    private constant integer ALTAR_REWARD_ITEM_TYPE_ID = 'I03V'
    // 每个区域的祭坛数据（parent key = areaId）
    private constant integer HT_ALTAR_UNIT = 0
    private constant integer ALTAR_WEATHER_TYPE = 'LRma'
    // 环境光效不能用哈希表存取（JASS 无 Save/LoadWeatherEffectHandle），
    // 改用数组按祭坛列表槽位记录，与 HT_ALTAR_LIST 一一对应
    private weathereffect array AltarWeather
    // 祭坛单位 → areaId 反向索引（parent key = GetHandleId(altarUnit)）
    private constant integer HT_ALTAR_AREA = 0
    // 追踪祭坛列表（parent key = 0）
    private constant integer HT_ALTAR_COUNT = 1
    private constant integer HT_ALTAR_LIST = 2
    // 全局出售事件触发器
    private trigger AltarSellTrig = null
endglobals

// ===== 内部：出售事件处理 =====

private function Trig_AltarSell takes nothing returns nothing
    local unit altar = GetSellingUnit()
    local unit buyer = GetBuyingUnit()
    local item soldItem = GetSoldItem()
    local integer altarId = GetHandleId(altar)
    local integer areaId = LoadInteger(AltarTable, altarId, HT_ALTAR_AREA)
    local integer tier
    local integer pid
    call DebugLogger_Log(LOG_INFO, "[altar] sell event: buyer=" + GetUnitName(buyer) + " soldItemTypeId=" + I2S(GetItemTypeId(soldItem)) + " altarAreaId=" + I2S(areaId))
    if areaId < 0 then
        call DebugLogger_Log(LOG_WARN, "[altar] sell event: altar not bound to any area (areaId=" + I2S(areaId) + "), abort")
        set altar = null
        set buyer = null
        set soldItem = null
        return
    endif
    // 仅当购买奖励触发物品时才处理；祭坛出售的其他物品不触发奖励流程
    if GetItemTypeId(soldItem) != ALTAR_REWARD_ITEM_TYPE_ID then
        call DebugLogger_Log(LOG_INFO, "[altar] sell event: item " + I2S(GetItemTypeId(soldItem)) + " is not reward trigger, skip")
        set altar = null
        set buyer = null
        set soldItem = null
        return
    endif
    // 移除购买的占位物品（仅用于触发购买事件）
    call RemoveItem(soldItem)
    set pid = GetPlayerId(GetOwningPlayer(buyer)) + 1
    // 检查是否已领取
    if RewardItem_IsPlayerClaimed(areaId, pid) then
        call DebugLogger_Log(LOG_INFO, "[altar] area " + GetAreaIdName(areaId) + " pid=" + I2S(pid) + " already claimed, reject")
        call DisplayTextToPlayer(GetOwningPlayer(buyer), 0, 0, "|cffFF0000已领取过该奖励|r")
    else
        // 购买时调起WE侧触发器：传区域ID、奖励等级、玩家ID
        set tier = LoadInteger(AltarTable, areaId, HT_ALTAR_TIER)
        call DebugLogger_Log(LOG_INFO, "[altar] -> CreateReward area=" + GetAreaIdName(areaId) + " tier=" + I2S(tier) + " pid=" + I2S(pid))
        call RewardItem_CreateReward(areaId, tier, pid)
    endif
    set altar = null
    set buyer = null
    set soldItem = null
endfunction

// ===== 公开接口 =====

/*
    [RewardAltar_SetAltarUnitTypeId]
    title = "设置祭坛单位类型"
    description = "设置祭坛的单位类型ID为${类型ID}"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function SetAltarUnitTypeId takes integer typeId returns nothing
    call SaveInteger(AltarTable, 0, HT_ALTAR_TYPE_ID, typeId)
endfunction

/*
    [RewardAltar_GetSellTriggerHandle]
    title = "获取祭坛出售事件触发器ID"
    description = "返回祭坛出售事件触发器的handleId，若为0则说明InitAltar未执行（RewardAltar库未被初始化）"
    category = TC_FRO
    returns = integer
*/
public function GetSellTriggerHandle takes nothing returns integer
    if AltarSellTrig == null then
        return 0
    endif
    return GetHandleId(AltarSellTrig)
endfunction

/*
    [RewardAltar_SpawnAltar]
    title = "生成祭坛"
    description = "在${区域ID}中心生成奖励等级为${等级}的祭坛"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function SpawnAltar takes integer areaId, integer rewardTier returns nothing
    local integer altarTypeId = LoadInteger(AltarTable, 0, HT_ALTAR_TYPE_ID)
    local rect r = GetAreaRect(areaId)
    local integer tier
    local real cx
    local real cy
    local unit altar
    local weathereffect weather
    local integer count
    // 将房间类型映射为奖励等级：MONSTER(0)→1, ELITE(4)→2, BOSS(2)→3
    if rewardTier == 2 then
        set tier = 3
    elseif rewardTier == 4 then
        set tier = 2
    else
        set tier = 1
    endif
    set cx = (GetRectMinX(r) + GetRectMaxX(r)) / 2.0
    set cy = (GetRectMinY(r) + GetRectMaxY(r)) / 2.0
    if altarTypeId == 0 then
        set r = null
        return
    endif
    // 创建祭坛单位（中立被动）
    set altar = CreateUnit(Player(PLAYER_NEUTRAL_PASSIVE), altarTypeId, cx, cy, 270.0)
    // 保存祭坛数据
    call SaveUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT, altar)
    call SaveInteger(AltarTable, GetHandleId(altar), HT_ALTAR_AREA, areaId)
    call SaveInteger(AltarTable, areaId, HT_ALTAR_TIER, tier)
    // 生成月光环境特效并记录，供重置时清除（用数组按列表槽位记录）
    set count = LoadInteger(AltarTable, 0, HT_ALTAR_COUNT)
    set weather = AddWeatherEffect(r, ALTAR_WEATHER_TYPE)
    call EnableWeatherEffect(weather, true)
    set AltarWeather[count] = weather
    // 追踪祭坛用于清理
    call SaveInteger(AltarTable, 0, HT_ALTAR_LIST + count, areaId)
    call SaveInteger(AltarTable, 0, HT_ALTAR_COUNT, count + 1)
    set altar = null
    set weather = null
    set r = null
endfunction

// ===== 初始化 =====

private function InitAltar takes nothing returns nothing
    set AltarSellTrig = CreateTrigger()
    call TriggerRegisterAnyUnitEventBJ(AltarSellTrig, EVENT_PLAYER_UNIT_SELL_ITEM)
    call TriggerAddAction(AltarSellTrig, function Trig_AltarSell)
    call DebugLogger_Log(LOG_INFO, "[altar] InitAltar done: sell trigger registered, handleId=" + I2S(GetHandleId(AltarSellTrig)))
endfunction

// 重置祭坛系统：移除本关产生的所有祭坛单位与天气特效，清空运行时数据
// 注意：AltarSellTrig 是跨关卡常驻的全局出售监听触发器，由 library initializer 创建，
// 关卡切换时不应销毁；HT_ALTAR_TYPE_ID 为关卡配置，亦应保留。
// 供 ChapterManager 在关卡切换时调用
function ResetRewardAltar takes nothing returns nothing
    local integer count = LoadInteger(AltarTable, 0, HT_ALTAR_COUNT)
    local integer i = 0
    local integer areaId
    local unit altar
    local weathereffect weather
    loop
        exitwhen i >= count
        set areaId = LoadInteger(AltarTable, 0, HT_ALTAR_LIST + i)
        set altar = LoadUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT)
        if altar != null then
            call RemoveUnit(altar)
        endif
        set weather = AltarWeather[i]
        if weather != null then
            call EnableWeatherEffect(weather, false)
            call RemoveWeatherEffect(weather)
            set AltarWeather[i] = null
        endif
        call FlushChildHashtable(AltarTable, areaId)
        set i = i + 1
    endloop
    // 仅清理运行时跟踪列表（HT_ALTAR_COUNT / HT_ALTAR_LIST + i），保留 HT_ALTAR_TYPE_ID 配置
    set i = 0
    loop
        exitwhen i >= count
        call RemoveSavedInteger(AltarTable, 0, HT_ALTAR_LIST + i)
        set i = i + 1
    endloop
    call SaveInteger(AltarTable, 0, HT_ALTAR_COUNT, 0)
    set altar = null
    set weather = null
endfunction

endlibrary
#endif
