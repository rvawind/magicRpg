#ifndef AREA_EXIT
#define AREA_EXIT
#include "nncou\\debug.j"
/*
    区域出口引导传送模块（通用框架）

    管理区域间连通状态的 3 秒引导传送。
    通过 RegisterAreaExit 注册出口矩形与目标区域的映射。
    具体大区域的注册调用放在各自的初始化文件中（如 forest.j）。

    扩展点（钩子）：
    - CanStartAreaExitChannel    是否允许开始引导
    - ShouldCancelAreaExitChannel 引导中是否应打断（眩晕/死亡等）
    - OnAreaExitChannelStart     开始引导时触发
    - OnAreaExitChannelCancel    引导取消时触发
    - OnAreaExitChannelFinish    传送完成后触发
*/
library areaExit requires areaEnter, DebugLogger
globals
    private hashtable AreaExitTable = InitHashtable()
    private constant real AREA_EXIT_DELAY = 3.00
    // 已清空的怪物房或安全房的快速通道时间
    private constant real AREA_EXIT_DELAY_FAST = 0.50
    private constant real AREA_EXIT_TICK = 0.05
    // TODO: 保护期结束后可移除，用于缓冲单位碰撞体积与中心点不一致
    private constant real AREA_EXIT_GRACE = 0.50
    // 触发器跟踪
    private constant integer HT_EXIT_PARENT = 0
    private constant integer HT_EXIT_BOUND_RECT = 0
    private constant integer HT_EXIT_BOUND_TARGET_RECT = 1
    private constant integer HT_EXIT_BOUND_SOURCE_ID = 2
    private constant integer HT_EXIT_BOUND_TARGET_ID = 3
    private constant integer HT_UNIT_EXIT_TIMER = 10
    private constant integer HT_UNIT_EXIT_RECT = 11
    private constant integer HT_UNIT_EXIT_TARGET_RECT = 12
    private constant integer HT_UNIT_EXIT_ELAPSED = 13
    private constant integer HT_UNIT_EXIT_SOURCE_ID = 14
    private constant integer HT_UNIT_EXIT_TARGET_ID = 15
    private constant integer HT_UNIT_EXIT_EFFECT = 16
    private constant integer HT_UNIT_EXIT_DELAY = 17
    private constant integer HT_EXIT_COUNT = 500
    private constant integer HT_EXIT_ENTER_LIST = 501
    private constant integer HT_EXIT_LEAVE_LIST = 601
    private constant integer HT_EXIT_COOLDOWN = 701
    // 可配置停留时长（parent key = HT_EXIT_PARENT，未配置时回退到下方常量）
    private constant integer HT_EXIT_CONFIG_DELAY = 900
    private constant integer HT_EXIT_CONFIG_DELAY_FAST = 901
    // 每个出口的常驻特效（parent key = HT_EXIT_PARENT，子键 = HT_EXIT_EFFECT_LIST + index）
    private constant integer HT_EXIT_EFFECT_LIST = 801

    // 出口常驻特效模型（可用/封锁）。占位符，可在 WE 中替换
    private constant string EXIT_EFFECT_AVAILABLE = "Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTo.mdl"
    private constant string EXIT_EFFECT_LOCKED = "Abilities\\Spells\\Other\\Doom\\DoomTarget.mdl"

    //触发传送后的短暂时间内不再传送
    private constant real COOLDOWN = 0.3
    // private timer cooldown_Timer = CreateTimer()
endglobals


//设置冷却
private function SetExitCoolDown takes integer uid,real value returns nothing
    call SaveReal(AreaExitTable,uid,HT_EXIT_COOLDOWN,value)
endfunction

//触发传送后的回调冷却
private function t_cd_action takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer uid = LoadInteger(AreaExitTable,GetHandleId(t),0)
    call SetExitCoolDown(uid,0.)
    call FlushChildHashtable(AreaExitTable,GetHandleId(t))
    call DestroyTimer(t)
    set t= null
endfunction

// 读取当前触发器绑定的出口矩形
private function GetExitBoundRect takes nothing returns rect
    return LoadRectHandle(AreaExitTable, GetHandleId(GetTriggeringTrigger()), HT_EXIT_BOUND_RECT)
endfunction

// 读取当前触发器绑定的目标区域矩形
private function GetExitBoundTargetRect takes nothing returns rect
    return LoadRectHandle(AreaExitTable, GetHandleId(GetTriggeringTrigger()), HT_EXIT_BOUND_TARGET_RECT)
endfunction

// 读取当前触发器绑定的源区域ID
private function GetBoundSourceAreaId takes nothing returns integer
    return LoadInteger(AreaExitTable, GetHandleId(GetTriggeringTrigger()), HT_EXIT_BOUND_SOURCE_ID)
endfunction

// 读取当前触发器绑定的目标区域ID
private function GetBoundTargetAreaId takes nothing returns integer
    return LoadInteger(AreaExitTable, GetHandleId(GetTriggeringTrigger()), HT_EXIT_BOUND_TARGET_ID)
endfunction

// 判断源区域是否允许通过出口移动：安全区（SAFE/ENTRY）或已清空的怪物房
private function IsSourceTraversable takes integer sourceId returns boolean
    local integer roomType = GetRoomType(sourceId)
    if roomType == ROOM_TYPE_SAFE or roomType == ROOM_TYPE_ENTRY then
        return true
    endif
    return GetRoomState(sourceId) == ROOM_STATE_CLEARED
endfunction

// 根据出口源区域状态决定本次通道时间：
// 安全区或已清空的怪物房 → 快速通道；其余 → 正常通道
private function GetAreaExitDelay takes integer sourceId returns real
    local real fast = LoadReal(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_CONFIG_DELAY_FAST)
    local real normal = LoadReal(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_CONFIG_DELAY)
    if fast <= 0.0 then
        set fast = AREA_EXIT_DELAY_FAST
    endif
    if normal <= 0.0 then
        set normal = AREA_EXIT_DELAY
    endif
    if IsSourceTraversable(sourceId) then
        return fast
    endif
    return normal
endfunction

// 清空单位当前的出口引导状态，并销毁关联计时器（保留冷却数据 HT_EXIT_COOLDOWN）
private function ResetAreaExitState takes unit u returns nothing
    local integer uid = GetHandleId(u)
    local timer t = LoadTimerHandle(AreaExitTable, uid, HT_UNIT_EXIT_TIMER)
    if t != null then
        call FlushChildHashtable(AreaExitTable, GetHandleId(t))
        call DestroyTimer(t)
    endif
    call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_TIMER)
    call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_RECT)
    call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_RECT)
    call RemoveSavedReal(AreaExitTable, uid, HT_UNIT_EXIT_ELAPSED)
    call RemoveSavedInteger(AreaExitTable, uid, HT_UNIT_EXIT_SOURCE_ID)
    call RemoveSavedInteger(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_ID)
    call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_EFFECT)
    call RemoveSavedReal(AreaExitTable, uid, HT_UNIT_EXIT_DELAY)
    set t = null
endfunction

// 钩子：单位进入出口后，是否允许开始引导传送
// 默认闸门：仅安全区（SAFE/ENTRY）或已清空的怪物房允许移动，未清空房间禁止离开
private function CanStartAreaExitChannel takes unit u, rect exitRect, rect targetRect, integer sourceId returns boolean
    return IsSourceTraversable(sourceId)
endfunction

// 钩子：引导进行中是否应当被打断，例如眩晕、禁传送、死亡等
private function ShouldCancelAreaExitChannel takes unit u, rect exitRect, rect targetRect returns boolean
    return false
endfunction

// 钩子：开始引导时触发，在单位脚下绑定施法特效
private function OnAreaExitChannelStart takes unit u, rect exitRect, rect targetRect returns nothing
    call SaveEffectHandle(AreaExitTable, GetHandleId(u), HT_UNIT_EXIT_EFFECT, AddSpecialEffectTarget("Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTo.mdl", u, "origin"))
endfunction

// 钩子：引导被取消时触发，删除施法特效
private function OnAreaExitChannelCancel takes unit u, rect exitRect, rect targetRect returns nothing
    local integer uid = GetHandleId(u)
    local effect e = LoadEffectHandle(AreaExitTable, uid, HT_UNIT_EXIT_EFFECT)
    if e != null then
        call DestroyEffect(e)
        call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_EFFECT)
    endif
    set e = null
endfunction

// 钩子：引导完成并成功传送后触发，删除施法特效并播放落地特效
private function OnAreaExitChannelFinish takes unit u, rect exitRect, rect targetRect returns nothing
    local integer uid = GetHandleId(u)
    local effect e = LoadEffectHandle(AreaExitTable, uid, HT_UNIT_EXIT_EFFECT)
    if e != null then
        call DestroyEffect(e)
        call RemoveSavedHandle(AreaExitTable, uid, HT_UNIT_EXIT_EFFECT)
    endif
    call DestroyEffect(AddSpecialEffectTarget("Abilities\\Spells\\Human\\MassTeleport\\MassTeleportTarget.mdl", u, "origin"))
    set e = null
endfunction

// 主动取消单位当前的出口引导，并触发取消钩子
private function CancelAreaExitChannel takes unit u returns nothing
    local integer uid = GetHandleId(u)
    local rect exitRect = LoadRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_RECT)
    local rect targetRect = LoadRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_RECT)
    local integer sourceId = LoadInteger(AreaExitTable, uid, HT_UNIT_EXIT_SOURCE_ID)
    local integer targetId = LoadInteger(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_ID)
    call OnAreaExitChannelCancel(u, exitRect, targetRect)
    call ResetAreaExitState(u)
    call DebugLogger_Log(LOG_DEBUG, "[exit] channel cancelled: " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
    set exitRect = null
    set targetRect = null
endfunction

// 引导计时器：周期检查打断条件，到时后执行传送
private function AreaExitDelayActions takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer tid = GetHandleId(t)
    local unit u = LoadUnitHandle(AreaExitTable, tid, 0)
    local integer uid = GetHandleId(u)
    local rect exitRect = LoadRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_RECT)
    local rect targetRect = LoadRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_RECT)
    local integer sourceId = LoadInteger(AreaExitTable, uid, HT_UNIT_EXIT_SOURCE_ID)
    local integer targetId = LoadInteger(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_ID)
    local real elapsed = LoadReal(AreaExitTable, uid, HT_UNIT_EXIT_ELAPSED)
    local real delay = LoadReal(AreaExitTable, uid, HT_UNIT_EXIT_DELAY)
    local player p
    if ShouldCancelAreaExitChannel(u, exitRect, targetRect) then
        call CancelAreaExitChannel(u)
    else
        set elapsed = elapsed + AREA_EXIT_TICK
        if elapsed >= delay then
            set p = GetOwningPlayer(u)
            // 先设置冷却再传送，SetUnitPosition 同步触发事件时冷却已生效，阻止新通道启动
            call SetExitCoolDown(uid, COOLDOWN)
            call OnAreaExitChannelFinish(u, exitRect, targetRect)
            call ResetAreaExitState(u)
            // 传送前授权离开（SetUnitPosition 同步触发离开旧区域事件时守卫会放行）
            call AllowPlayerLeaveAreaOnce(p)
            call SetUnitPosition(u, GetRectCenterX(targetRect), GetRectCenterY(targetRect))
            // Trig_AreaEnterActions 会调用 SetPlayerCurrentAreaRect 记录新区域并重置 leave_allowed
            // 启动冷却计时器，到期后清除冷却标记
            set t = CreateTimer()
            call SaveInteger(AreaExitTable, GetHandleId(t), 0, uid)
            call TimerStart(t, COOLDOWN, false, function t_cd_action)
            call DebugLogger_Log(LOG_DEBUG, "[exit] teleport complete: " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
            set p = null
        else
            call SaveReal(AreaExitTable, uid, HT_UNIT_EXIT_ELAPSED, elapsed)
        endif
    endif
    set t = null
    set u = null
    set exitRect = null
    set targetRect = null
endfunction

// 进入出口时开启引导
private function Trig_AreaExitEnterActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local integer uid = GetHandleId(u)
    local player p = GetOwningPlayer(u)
    local rect exitRect = GetExitBoundRect()
    local rect targetRect = GetExitBoundTargetRect()
    local integer sourceId = GetBoundSourceAreaId()
    local integer targetId = GetBoundTargetAreaId()
    local timer t
    // 仅玩家英雄可触发出口引导，怪物等非英雄单位不传送也不开启通道
    if not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        set p = null
        set exitRect = null
        set targetRect = null
        return
    endif
    if LoadReal(AreaExitTable, uid, HT_EXIT_COOLDOWN) > 0 then
        call DebugLogger_Log(LOG_DEBUG, "[exit] cooldown active, skip: " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
    elseif not CanStartAreaExitChannel(u, exitRect, targetRect, sourceId) then
        call DebugLogger_Log(LOG_DEBUG, "[exit] channel blocked: " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
    else
        call SaveRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_RECT, exitRect)
        call SaveRectHandle(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_RECT, targetRect)
        call SaveInteger(AreaExitTable, uid, HT_UNIT_EXIT_SOURCE_ID, sourceId)
        call SaveInteger(AreaExitTable, uid, HT_UNIT_EXIT_TARGET_ID, targetId)
        call SaveReal(AreaExitTable, uid, HT_UNIT_EXIT_ELAPSED, 0.0)
        call SaveReal(AreaExitTable, uid, HT_UNIT_EXIT_DELAY, GetAreaExitDelay(sourceId))
        set t = CreateTimer()
        call SaveUnitHandle(AreaExitTable, GetHandleId(t), 0, u)
        call SaveTimerHandle(AreaExitTable, uid, HT_UNIT_EXIT_TIMER, t)
        call TimerStart(t, AREA_EXIT_TICK, true, function AreaExitDelayActions)
        call OnAreaExitChannelStart(u, exitRect, targetRect)
        call DebugLogger_Log(LOG_DEBUG, "[exit] channel started: " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId))
        set t = null
    endif
    set u = null
    set p = null
    set exitRect = null
    set targetRect = null
endfunction

// 离开当前出口时立即取消对应的引导
private function Trig_AreaExitLeaveActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local integer uid = GetHandleId(u)
    // 怪物等非英雄单位不会开启通道，离开时无需处理
    if not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    // 仅在存在活跃通道时取消（传送完成后 ResetAreaExitState 已清除数据，此时无需再取消）
    if LoadTimerHandle(AreaExitTable, uid, HT_UNIT_EXIT_TIMER) != null then
        call CancelAreaExitChannel(u)
        call DebugLogger_Log(LOG_DEBUG, "[exit] unit left exit rect, channel cancelled")
    endif
    set u = null
endfunction

// 刷新单个出口的常驻特效：可用（传送门）或封锁（红色标记）
private function ApplyExitEffect takes integer index returns nothing
    local integer sourceId = GetAreaExitSourceId(index)
    local rect exitRect = GetAreaExitRect(index)
    local effect old = LoadEffectHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_EFFECT_LIST + index)
    local real x
    local real y
    if old != null then
        call DestroyEffect(old)
    endif
    set x = GetRectCenterX(exitRect)
    set y = GetRectCenterY(exitRect)
    if IsSourceTraversable(sourceId) then
        call SaveEffectHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_EFFECT_LIST + index, AddSpecialEffect(EXIT_EFFECT_AVAILABLE, x, y))
    else
        call SaveEffectHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_EFFECT_LIST + index, AddSpecialEffect(EXIT_EFFECT_LOCKED, x, y))
    endif
    set exitRect = null
    set old = null
endfunction

// 刷新指定源区域所有出口的常驻特效
// 供 monster_room.j 在房间清空后调用，将封锁特效切换为可用特效
function RefreshAreaExitState takes integer areaId returns nothing
    local integer count = GetAreaExitCount()
    local integer i = 0
    loop
        exitwhen i >= count
        if GetAreaExitSourceId(i) == areaId then
            call ApplyExitEffect(i)
        endif
        set i = i + 1
    endloop
endfunction

// 配置正常通道停留时长（秒），未调用时回退到默认 AREA_EXIT_DELAY
function SetAreaExitDelay takes real delay returns nothing
    call SaveReal(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_CONFIG_DELAY, delay)
endfunction

// 配置已清空/安全房的快速通道停留时长（秒），未调用时回退到默认 AREA_EXIT_DELAY_FAST
function SetAreaExitFastDelay takes real delay returns nothing
    call SaveReal(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_CONFIG_DELAY_FAST, delay)
endfunction

// 从 data.j 读取已注册的出口数据，为每个出口创建进入/离开事件触发器
function InitAreaExits takes nothing returns nothing
    local integer count = GetAreaExitCount()
    local integer i = 0
    local rect exitRect
    local rect targetRect
    local integer sourceId
    local integer targetId
    local trigger enter
    local trigger leave
    loop
        exitwhen i >= count
        set exitRect = GetAreaExitRect(i)
        set targetRect = GetAreaExitTargetRect(i)
        set sourceId = GetAreaExitSourceId(i)
        set targetId = GetAreaIdByRect(targetRect)
        set enter = CreateTrigger()
        set leave = CreateTrigger()
        call SaveRectHandle(AreaExitTable, GetHandleId(enter), HT_EXIT_BOUND_RECT, exitRect)
        call SaveRectHandle(AreaExitTable, GetHandleId(enter), HT_EXIT_BOUND_TARGET_RECT, targetRect)
        call SaveInteger(AreaExitTable, GetHandleId(enter), HT_EXIT_BOUND_SOURCE_ID, sourceId)
        call SaveInteger(AreaExitTable, GetHandleId(enter), HT_EXIT_BOUND_TARGET_ID, targetId)
        call SaveRectHandle(AreaExitTable, GetHandleId(leave), HT_EXIT_BOUND_RECT, exitRect)
        call SaveRectHandle(AreaExitTable, GetHandleId(leave), HT_EXIT_BOUND_TARGET_RECT, targetRect)
        call SaveInteger(AreaExitTable, GetHandleId(leave), HT_EXIT_BOUND_SOURCE_ID, sourceId)
        call SaveInteger(AreaExitTable, GetHandleId(leave), HT_EXIT_BOUND_TARGET_ID, targetId)
        call TriggerRegisterEnterRectSimple(enter, exitRect)
        call TriggerRegisterLeaveRectSimple(leave, exitRect)
        call TriggerAddAction(enter, function Trig_AreaExitEnterActions)
        call TriggerAddAction(leave, function Trig_AreaExitLeaveActions)
        call DebugLogger_Log(LOG_DEBUG, "[exit] InitAreaExits #" + I2S(i) + " " + GetAreaIdName(sourceId) + "->" + GetAreaIdName(targetId) + " enterHId=" + I2S(GetHandleId(enter)))
        call SaveTriggerHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_ENTER_LIST + i, enter)
        call SaveTriggerHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_LEAVE_LIST + i, leave)
        call SaveInteger(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_COUNT, i + 1)
        // 建立出口常驻特效（初始状态：安全区/已清空 → 可用，否则 → 封锁）
        call ApplyExitEffect(i)
        set i = i + 1
    endloop
    set exitRect = null
    set targetRect = null
    set enter = null
    set leave = null
endfunction

// 重置区域出口系统：销毁所有出口触发器，取消所有进行中的引导传送，清空数据
// 供 ChapterManager 在关卡切换时调用
function ResetAreaExit takes nothing returns nothing
    local integer count = LoadInteger(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_COUNT)
    local integer i = 0
    local trigger t
    local effect e
    loop
        exitwhen i >= count
        set t = LoadTriggerHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_ENTER_LIST + i)
        if t != null then
            call DestroyTrigger(t)
        endif
        set t = LoadTriggerHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_LEAVE_LIST + i)
        if t != null then
            call DestroyTrigger(t)
        endif
        set e = LoadEffectHandle(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_EFFECT_LIST + i)
        if e != null then
            call DestroyEffect(e)
        endif
        set i = i + 1
    endloop
    call SaveInteger(AreaExitTable, HT_EXIT_PARENT, HT_EXIT_COUNT, 0)
    call DebugLogger_Log(LOG_DEBUG, "[exit] ResetAreaExit done, destroyed " + I2S(count) + " exit pairs")
    set t = null
    set e = null
endfunction

endlibrary
#endif
