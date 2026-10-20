#ifndef REWARD_ALTAR_INCLUDED
#define REWARD_ALTAR_INCLUDED
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\reward\\reward.j"
#include "nncou\\debug.j"
/*
    祭坛模块

    在房间清空后生成祭坛（中立商店），玩家靠近后可购买物品触发奖励流程。
    祭坛随物理槽位绑定：槽位释放时由 forest.j 的释放钩子调用 RemoveArea 清理；
    逻辑房重新绑定槽位时由分配钩子按需重新生成。

    数据表拆分：
    - AltarGlobalTable：全局配置与祭坛列表（parent = 0）
    - AltarTable：每个逻辑房的祭坛单位/等级（parent = areaId）
    - AltarUnitTable：祭坛单位 -> areaId（parent = GetHandleId(unit)）
    避免 areaId 0 与全局键冲突。

    依赖：areaData, RewardItem, DebugLogger
*/
library RewardAltar initializer InitAltar requires areaData, RewardItem, DebugLogger

globals
    private hashtable AltarTable = InitHashtable()
    private hashtable AltarGlobalTable = InitHashtable()
    private hashtable AltarUnitTable = InitHashtable()

    // 全局配置（AltarGlobalTable, parent = 0）
    private constant integer HT_ALTAR_TYPE_ID = 0
    private constant integer HT_ALTAR_COUNT = 1
    private constant integer HT_ALTAR_LIST = 2

    // 每个逻辑房的祭坛数据（AltarTable, parent = areaId）
    private constant integer HT_ALTAR_UNIT = 0
    private constant integer HT_ALTAR_TIER = 1

    // 祭坛单位 -> areaId（AltarUnitTable, parent = GetHandleId(unit)）
    private constant integer HT_ALTAR_AREA = 0

    // 触发奖励流程的物品类型ID
    private constant integer ALTAR_REWARD_ITEM_TYPE_ID = 'I03V'
    private constant integer ALTAR_WEATHER_TYPE = 'LRma'

    // 环境光效不能用哈希表存取，按祭坛列表槽位记录，与 HT_ALTAR_LIST 一一对应
    private weathereffect array AltarWeather

    private trigger AltarSellTrig = null
endglobals

// ===== 内部：移除祭坛 =====

// 移除某逻辑房的祭坛与环境光效，并从跟踪列表压缩删除
private function RemoveAltarInternal takes integer areaId returns nothing
    local unit altar = LoadUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT)
    local integer count = LoadInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT)
    local integer i = 0
    local integer last
    local weathereffect weather
    if altar != null then
        call RemoveSavedInteger(AltarUnitTable, GetHandleId(altar), HT_ALTAR_AREA)
        call RemoveUnit(altar)
        set altar = null
    endif
    loop
        exitwhen i >= count
        if LoadInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + i) == areaId then
            set weather = AltarWeather[i]
            if weather != null then
                call EnableWeatherEffect(weather, false)
                call RemoveWeatherEffect(weather)
            endif
            set last = count - 1
            if i != last then
                call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + i, LoadInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + last))
                set AltarWeather[i] = AltarWeather[last]
            endif
            call RemoveSavedInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + last)
            set AltarWeather[last] = null
            call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT, last)
            exitwhen true
        endif
        set i = i + 1
    endloop
    call FlushChildHashtable(AltarTable, areaId)
    set weather = null
endfunction

// ===== 内部：出售事件处理 =====

private function Trig_AltarSell takes nothing returns nothing
    local unit altar = GetSellingUnit()
    local unit buyer = GetBuyingUnit()
    local item soldItem = GetSoldItem()
    local integer altarId
    local integer areaId
    local integer tier
    local integer pid
    if altar == null or buyer == null or soldItem == null then
        set altar = null
        set buyer = null
        set soldItem = null
        return
    endif
    set altarId = GetHandleId(altar)
    if not HaveSavedInteger(AltarUnitTable, altarId, HT_ALTAR_AREA) then
        call DebugLogger_Log(LOG_TRACE, "[altar] sell event: unit is not a registered altar, skip")
        set altar = null
        set buyer = null
        set soldItem = null
        return
    endif
    set areaId = LoadInteger(AltarUnitTable, altarId, HT_ALTAR_AREA)
    call DebugLogger_Log(LOG_INFO, "[altar] sell event: buyer=" + GetUnitName(buyer) + " soldItemTypeId=" + I2S(GetItemTypeId(soldItem)) + " altarAreaId=" + I2S(areaId))
    if GetItemTypeId(soldItem) != ALTAR_REWARD_ITEM_TYPE_ID then
        call DebugLogger_Log(LOG_INFO, "[altar] sell event: item " + I2S(GetItemTypeId(soldItem)) + " is not reward trigger, skip")
        set altar = null
        set buyer = null
        set soldItem = null
        return
    endif
    call RemoveItem(soldItem)
    set pid = GetPlayerId(GetOwningPlayer(buyer)) + 1
    if RewardItem_IsPlayerClaimed(areaId, pid) then
        call DebugLogger_Log(LOG_INFO, "[altar] area " + GetAreaIdName(areaId) + " pid=" + I2S(pid) + " already claimed, reject")
        call DisplayTextToPlayer(GetOwningPlayer(buyer), 0, 0, "|cffFF0000已领取过该奖励|r")
    else
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
    call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_TYPE_ID, typeId)
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
    [RewardAltar_HasAltar]
    title = "区域是否有祭坛"
    description = "判断${区域ID}当前是否已生成祭坛"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = integer
*/
public function HasAltar takes integer areaId returns boolean
    local unit altar = LoadUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT)
    local boolean alive = altar != null and GetUnitTypeId(altar) != 0
    set altar = null
    return alive
endfunction

/*
    [RewardAltar_RemoveArea]
    title = "移除区域祭坛"
    description = "移除${区域ID}的祭坛与环境光效（槽位释放时由钩子调用）"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function RemoveArea takes integer areaId returns nothing
    call RemoveAltarInternal(areaId)
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
    local integer altarTypeId = LoadInteger(AltarGlobalTable, 0, HT_ALTAR_TYPE_ID)
    local rect r
    local integer tier
    local real cx
    local real cy
    local unit altar
    local weathereffect weather
    local integer count
    // 房间类型映射奖励等级：MONSTER(0)->1, ELITE(4)->2, BOSS(2)->3
    if rewardTier == 2 then
        set tier = 3
    elseif rewardTier == 4 then
        set tier = 2
    else
        set tier = 1
    endif
    if altarTypeId == 0 then
        call DebugLogger_Log(LOG_WARN, "[altar] SpawnAltar skipped: altar unit type not configured")
        return
    endif
    set r = GetAreaRect(areaId)
    if r == null then
        call DebugLogger_Log(LOG_WARN, "[altar] SpawnAltar skipped: no bound rect for " + GetAreaIdName(areaId))
        return
    endif
    // 防御：同一逻辑房已有祭坛时先清理，避免重复单位/天气
    if HasAltar(areaId) then
        call RemoveAltarInternal(areaId)
    endif
    set cx = (GetRectMinX(r) + GetRectMaxX(r)) / 2.0
    set cy = (GetRectMinY(r) + GetRectMaxY(r)) / 2.0
    set altar = CreateUnit(Player(PLAYER_NEUTRAL_PASSIVE), altarTypeId, cx, cy, 270.0)
    if altar == null then
        call DebugLogger_Log(LOG_WARN, "[altar] SpawnAltar failed: CreateUnit returned null, typeId=" + I2S(altarTypeId))
        set r = null
        return
    endif
    call SaveUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT, altar)
    call SaveInteger(AltarUnitTable, GetHandleId(altar), HT_ALTAR_AREA, areaId)
    call SaveInteger(AltarTable, areaId, HT_ALTAR_TIER, tier)
    set count = LoadInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT)
    set weather = AddWeatherEffect(r, ALTAR_WEATHER_TYPE)
    call EnableWeatherEffect(weather, true)
    set AltarWeather[count] = weather
    call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + count, areaId)
    call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT, count + 1)
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
// 注意：AltarSellTrig 与 HT_ALTAR_TYPE_ID 跨关卡保留
function ResetRewardAltar takes nothing returns nothing
    local integer count = LoadInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT)
    local integer i = 0
    local integer areaId
    local unit altar
    local weathereffect weather
    loop
        exitwhen i >= count
        set areaId = LoadInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + i)
        set altar = LoadUnitHandle(AltarTable, areaId, HT_ALTAR_UNIT)
        if altar != null then
            call RemoveSavedInteger(AltarUnitTable, GetHandleId(altar), HT_ALTAR_AREA)
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
    set i = 0
    loop
        exitwhen i >= count
        call RemoveSavedInteger(AltarGlobalTable, 0, HT_ALTAR_LIST + i)
        set i = i + 1
    endloop
    call SaveInteger(AltarGlobalTable, 0, HT_ALTAR_COUNT, 0)
    set altar = null
    set weather = null
endfunction

endlibrary
#endif
