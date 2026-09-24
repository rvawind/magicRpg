#ifndef AREA_ENTER
#define AREA_ENTER
#include "nncou\\debug.j"
/*
    区域进出保护模块（通用框架）

    按玩家记录当前所在区域矩形，拦截非法离开。
    配合 areaData 使用，通过 RegisterAreaGuard 注册需要保护的区域。
    具体大区域的注册调用放在各自的初始化文件中（如 forest.j）。
*/
library areaEnter requires areaData, DebugLogger

globals
    private hashtable AreaEnterTable = InitHashtable()
    private constant real AREA_ENTER_PUSH_INSET = 1.00
    // 触发器跟踪
    private constant integer HT_GUARD_PARENT = 0
    private constant integer HT_TRIGGER_BOUND_RECT = 0
    private constant integer HT_PLAYER_AREA_RECT = 10
    private constant integer HT_PLAYER_LEAVE_ALLOWED = 11
    private constant integer HT_PLAYER_CHANNELING = 12
    private constant integer HT_CLAMPING = 13
    private constant integer HT_GUARD_COUNT = 500
    private constant integer HT_GUARD_ENTER_LIST = 501
    private constant integer HT_GUARD_LEAVE_LIST = 601
endglobals

// 供其他系统读取：获取玩家当前所在区域
function GetPlayerCurrentAreaRect takes player whichPlayer returns rect
    return LoadRectHandle(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_AREA_RECT)
endfunction

// 供 exit 系统调用：允许玩家下一次合法离开当前区域
function AllowPlayerLeaveAreaOnce takes player whichPlayer returns nothing
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED, true)
endfunction

// 供 monster_room 系统调用：判断玩家当前是否被授权离开当前区域
// 用于区分真实传送离场（出口传送/紧急穿越已调用 AllowPlayerLeaveAreaOnce）与走上出口矩形被守卫拉回
function IsPlayerLeaveAllowed takes player whichPlayer returns boolean
    return LoadBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED)
endfunction

// 供 exit 系统调用：标记/取消标记玩家正在出口引导中，引导期间跳过区域保护拉回
function SetPlayerChanneling takes player whichPlayer, boolean flag returns nothing
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_CHANNELING, flag)
endfunction

function SetPlayerCurrentAreaRect takes player whichPlayer, rect areaRect returns nothing
    call SaveRectHandle(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_AREA_RECT, areaRect)
    call SaveBoolean(AreaEnterTable, GetHandleId(whichPlayer), HT_PLAYER_LEAVE_ALLOWED, false)
endfunction

private function GetBoundAreaRect takes nothing returns rect
    return LoadRectHandle(AreaEnterTable, GetHandleId(GetTriggeringTrigger()), HT_TRIGGER_BOUND_RECT)
endfunction

private function B2S takes boolean b returns string
    if b then
        return "T"
    endif
    return "F"
endfunction

public function ClampXInRect takes real x, rect r returns real
    local real minX = GetRectMinX(r) + AREA_ENTER_PUSH_INSET
    local real maxX = GetRectMaxX(r) - AREA_ENTER_PUSH_INSET
    if minX > maxX then
        set minX = GetRectMinX(r)
        set maxX = GetRectMaxX(r)
    endif
    if x < minX then
        return minX
    endif
    if x > maxX then
        return maxX
    endif
    return x
endfunction

public function ClampYInRect takes real y, rect r returns real
    local real minY = GetRectMinY(r) + AREA_ENTER_PUSH_INSET
    local real maxY = GetRectMaxY(r) - AREA_ENTER_PUSH_INSET
    if minY > maxY then
        set minY = GetRectMinY(r)
        set maxY = GetRectMaxY(r)
    endif
    if y < minY then
        return minY
    endif
    if y > maxY then
        return maxY
    endif
    return y
endfunction

// 进入区域时，按单位记录当前区域，并清除离开许可
private function Trig_AreaEnterActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local player p = GetOwningPlayer(u)
    local rect r = GetBoundAreaRect()
    call SetPlayerCurrentAreaRect(p, r)
    call DebugLogger_Log(LOG_DEBUG, "[enter] " + GetPlayerName(p) + " entered " + GetAreaIdName(GetAreaIdByRect(r)))
    set u = null
    set p = null
    set r = null
endfunction

// 离开区域时，若单位不存在离开许可，则强制拉回到当前区域内最近点
private function Trig_AreaLeaveActions takes nothing returns nothing
    local unit u = GetTriggerUnit()
    local player p = GetOwningPlayer(u)
    local rect r = GetBoundAreaRect()
    local real x
    local real y
    if LoadBoolean(AreaEnterTable, GetHandleId(p), HT_PLAYER_LEAVE_ALLOWED) then
        call DebugLogger_Log(LOG_DEBUG, "[enter] " + GetPlayerName(p) + " allowed to leave " + GetAreaIdName(GetAreaIdByRect(r)))
    else
        set x = GetUnitX(u)
        set y = GetUnitY(u)
        set x = ClampXInRect(x, r)
        set y = ClampYInRect(y, r)
        call SetUnitX(u, x)
        call SetUnitY(u, y)
        call DebugLogger_Log(LOG_DEBUG, "[enter] " + GetPlayerName(p) + " clamped back to " + GetAreaIdName(GetAreaIdByRect(r)))
    endif
    set u = null
    set p = null
    set r = null
endfunction

// 遍历所有已注册区域，为每个区域创建进出监听触发器
function InitAreaGuards takes nothing returns nothing
    local integer count = GetAreaCount()
    local integer i = 0
    local integer areaId
    local rect areaRect
    local trigger enter
    local trigger leave
    loop
        exitwhen i >= count
        set areaId = GetAreaByIndex(i)
        set areaRect = GetAreaRect(areaId)
        set enter = CreateTrigger()
        set leave = CreateTrigger()
        call SaveRectHandle(AreaEnterTable, GetHandleId(enter), HT_TRIGGER_BOUND_RECT, areaRect)
        call SaveRectHandle(AreaEnterTable, GetHandleId(leave), HT_TRIGGER_BOUND_RECT, areaRect)
        call TriggerRegisterEnterRectSimple(enter, areaRect)
        call TriggerRegisterLeaveRectSimple(leave, areaRect)
        call TriggerAddAction(enter, function Trig_AreaEnterActions)
        call TriggerAddAction(leave, function Trig_AreaLeaveActions)
        call DebugLogger_Log(LOG_DEBUG, "[enter] InitAreaGuards #" + I2S(i) + " " + GetAreaIdName(areaId))
        call SaveTriggerHandle(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_ENTER_LIST + i, enter)
        call SaveTriggerHandle(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_LEAVE_LIST + i, leave)
        call SaveInteger(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_COUNT, i + 1)
        set i = i + 1
    endloop
    set areaRect = null
    set enter = null
    set leave = null
endfunction

// 重置区域进出保护：销毁所有已注册的保护触发器，清空玩家跟踪数据
// 供 ChapterManager 在关卡切换时调用
function ResetAreaEnter takes nothing returns nothing
    local integer count = LoadInteger(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_COUNT)
    local integer i = 0
    local trigger t
    // 销毁所有进入触发器
    loop
        exitwhen i >= count
        set t = LoadTriggerHandle(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_ENTER_LIST + i)
        if t != null then
            call DestroyTrigger(t)
        endif
        set i = i + 1
    endloop
    // 销毁所有离开触发器
    set i = 0
    loop
        exitwhen i >= count
        set t = LoadTriggerHandle(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_LEAVE_LIST + i)
        if t != null then
            call DestroyTrigger(t)
        endif
        set i = i + 1
    endloop
    // 重置计数器，旧数据由重新注册时覆盖
    call SaveInteger(AreaEnterTable, HT_GUARD_PARENT, HT_GUARD_COUNT, 0)
    set t = null
endfunction

endlibrary
#endif
