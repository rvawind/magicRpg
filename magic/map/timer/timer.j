#ifndef CHAPTER_TIMER_INCLUDED
#define CHAPTER_TIMER_INCLUDED
/*
    关卡计时模块

    负责：
    1. 关卡倒计时时间管理
    2. 清房返还时间
    3. 时间结束后触发事件（BOSS走廊开启）

    纯框架+钩子模式：接口和钩子定义在此文件中，具体数值由WE/GUI填入。

    依赖：CurseSystem（计时结束触发诅咒扩散）
*/
library ChapterTimer requires CurseSystem

globals
    private hashtable TimerTable = InitHashtable()
    private timer ChapterClock = CreateTimer()

    private constant integer HT_BASE_TIME = 0
    private constant integer HT_TIME_RETURN_BASE = 1
    private constant integer HT_TIME_RETURN_SCALE = 2
    private constant integer HT_REMAINING_TIME = 3
    private constant integer HT_TIMER_ACTIVE = 4
    private constant integer HT_TIME_EXPIRED = 5

    private constant real TIMER_TICK_INTERVAL = 1.00
endglobals

private function OnChapterTimerExpired takes nothing returns nothing
    call CurseSystem_StartCurseSpread()
endfunction

private function OnChapterTimerTick takes real remainingTime returns nothing
endfunction

private function OnTimeReturned takes integer areaId, real amount returns nothing
endfunction

private function CanReturnTime takes integer areaId returns boolean
    return not LoadBoolean(TimerTable, 0, HT_TIME_EXPIRED)
endfunction

private function Trig_TimerTick takes nothing returns nothing
    local real remaining = LoadReal(TimerTable, 0, HT_REMAINING_TIME)
    set remaining = remaining - TIMER_TICK_INTERVAL
    call SaveReal(TimerTable, 0, HT_REMAINING_TIME, remaining)
    call OnChapterTimerTick(remaining)
    if remaining <= 0.0 then
        call SaveReal(TimerTable, 0, HT_REMAINING_TIME, 0.0)
        call SaveBoolean(TimerTable, 0, HT_TIME_EXPIRED, true)
        call SaveBoolean(TimerTable, 0, HT_TIMER_ACTIVE, false)
        call PauseTimer(ChapterClock)
        call OnChapterTimerExpired()
    endif
endfunction

/*
    [ChapterTimer_SetChapterTimerBaseTime]
    title = "设置基础时间"
    description = "设置关卡基础时间为${秒数}秒"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function SetChapterTimerBaseTime takes integer seconds returns nothing
    call SaveInteger(TimerTable, 0, HT_BASE_TIME, seconds)
    call SaveReal(TimerTable, 0, HT_REMAINING_TIME, I2R(seconds))
endfunction

/*
    [ChapterTimer_SetChapterTimerReturnParams]
    title = "设置返还参数"
    description = "设置清房返还基础值为${基础}，系数为${系数}"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = real
*/
public function SetChapterTimerReturnParams takes integer baseValue, real scale returns nothing
    call SaveInteger(TimerTable, 0, HT_TIME_RETURN_BASE, baseValue)
    call SaveReal(TimerTable, 0, HT_TIME_RETURN_SCALE, scale)
endfunction

/*
    [ChapterTimer_StartChapterTimer]
    title = "启动计时器"
    description = "启动关卡倒计时，玩家可开始探索"
    category = TC_FRO
*/
public function StartChapterTimer takes nothing returns nothing
    call SaveBoolean(TimerTable, 0, HT_TIMER_ACTIVE, true)
    call SaveBoolean(TimerTable, 0, HT_TIME_EXPIRED, false)
    call TimerStart(ChapterClock, TIMER_TICK_INTERVAL, true, function Trig_TimerTick)
endfunction

/*
    [ChapterTimer_PauseChapterTimer]
    title = "暂停计时器"
    description = "暂停关卡倒计时"
    category = TC_FRO
*/
public function PauseChapterTimer takes nothing returns nothing
    call SaveBoolean(TimerTable, 0, HT_TIMER_ACTIVE, false)
    call PauseTimer(ChapterClock)
endfunction

/*
    [ChapterTimer_ResumeChapterTimer]
    title = "恢复计时器"
    description = "恢复关卡倒计时"
    category = TC_FRO
*/
public function ResumeChapterTimer takes nothing returns nothing
    call SaveBoolean(TimerTable, 0, HT_TIMER_ACTIVE, true)
    call ResumeTimer(ChapterClock)
endfunction

/*
    [ChapterTimer_ReturnTimeOnRoomClear]
    title = "清房返还时间"
    description = "清空${指定ID}的房间后返还时间"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function ReturnTimeOnRoomClear takes integer areaId returns nothing
    local integer base = LoadInteger(TimerTable, 0, HT_TIME_RETURN_BASE)
    local real scale = LoadReal(TimerTable, 0, HT_TIME_RETURN_SCALE)
    local real remaining
    if not CanReturnTime(areaId) then
        return
    endif
    set remaining = LoadReal(TimerTable, 0, HT_REMAINING_TIME) + I2R(base) * scale
    call SaveReal(TimerTable, 0, HT_REMAINING_TIME, remaining)
    call OnTimeReturned(areaId, I2R(base) * scale)
endfunction

/*
    [ChapterTimer_GetChapterTimerRemaining]
    title = "获取剩余时间"
    description = "获取当前剩余时间（秒）"
    category = TC_FRO
    returns = integer
*/
public function GetChapterTimerRemaining takes nothing returns integer
    return R2I(LoadReal(TimerTable, 0, HT_REMAINING_TIME))
endfunction

/*
    [ChapterTimer_IsChapterTimerExpired]
    title = "时间是否已结束"
    description = "判断关卡时间是否已结束"
    category = TC_FRO
    returns = boolean
*/
public function IsChapterTimerExpired takes nothing returns boolean
    return LoadBoolean(TimerTable, 0, HT_TIME_EXPIRED)
endfunction

/*
    [ChapterTimer_AddChapterTime]
    title = "添加时间"
    description = "为倒计时添加${秒数}秒"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function AddChapterTime takes integer seconds returns nothing
    local real remaining = LoadReal(TimerTable, 0, HT_REMAINING_TIME) + I2R(seconds)
    call SaveReal(TimerTable, 0, HT_REMAINING_TIME, remaining)
endfunction

/*
    [ChapterTimer_SetChapterTimerRemaining]
    title = "设置剩余时间"
    description = "设置剩余时间为${秒数}秒"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function SetChapterTimerRemaining takes integer seconds returns nothing
    call SaveReal(TimerTable, 0, HT_REMAINING_TIME, I2R(seconds))
endfunction

endlibrary
#endif
