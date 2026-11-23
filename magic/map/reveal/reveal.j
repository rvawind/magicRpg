#ifndef AREA_REVEAL_INCLUDED
#define AREA_REVEAL_INCLUDED
#include "nncou\\debug.j"
/*
    信息揭示模块（Step 4：数据层）

    规则（2026-10-27 敲定）：
    - 揭示状态挂在**逻辑房**上（areaId），物理槽位回收/重新绑定不影响；
    - 进入任意房间（进入回调）即揭示：中心格 + **有直边的正交邻居**（3×3 窗口）；
      对角格不揭示，窗口外不揭示；不依赖清房/死亡等事件；
    - 幂等：重复进入已揭示的格不重复计数、不刷屏（新增 0 时不出日志）；
    - BOSS 中转房在公布前按普通格处理（本层不额外区分）。

    视觉层（线框层 / 内容层图标）需要资源交接后再接，本文件只做数据层 + 日志。

    依赖：areaData, areaGrid, areaEnter, DebugLogger
*/
library areaReveal initializer InitReveal requires areaData, areaGrid, areaEnter, DebugLogger

globals
    private hashtable RevealTable = InitHashtable()
    private constant integer HT_REVEALED = 0
    private integer RevealedTotal = 0
endglobals

// 揭示单格，返回是否新增
private function RevealCell takes integer areaId returns boolean
    if not Grid_IsValidId(areaId) then
        return false
    endif
    if LoadInteger(RevealTable, areaId, HT_REVEALED) != 0 then
        return false
    endif
    call SaveInteger(RevealTable, areaId, HT_REVEALED, 1)
    set RevealedTotal = RevealedTotal + 1
    return true
endfunction

/*
    [Reveal_3x3]
    揭示 areaId 及其 4 个有直边的正交邻居，返回新增格数。
    只有真正新增时才写 INFO 日志（幂等，避免重复进入刷屏）。
*/
function Reveal_3x3 takes integer areaId returns integer
    local integer d = 0
    local integer n
    local integer added = 0
    if not Grid_IsValidId(areaId) then
        return 0
    endif
    if RevealCell(areaId) then
        set added = added + 1
    endif
    loop
        exitwhen d >= 4
        set n = Grid_GetNeighbor(areaId, d)
        if n >= 0 then
            if RevealCell(n) then
                set added = added + 1
            endif
        endif
        set d = d + 1
    endloop
    if added > 0 then
        call DebugLogger_LogKey("[reveal] 3x3 center=(" + I2S(Grid_GetRow(areaId)) + "," + I2S(Grid_GetCol(areaId)) + ") revealed=" + I2S(added))
    endif
    return added
endfunction

// 进入房间回调：进入即揭示（追加回调，不会被 BOSS 主回调顶掉）
private function OnAreaEnterReveal takes nothing returns nothing
    local integer areaId = GetAreaEnterCallbackArea()
    if areaId < 0 then
        return
    endif
    call Reveal_3x3(areaId)
endfunction

// ===== 查询 / 重置 =====

function Reveal_IsRevealed takes integer areaId returns boolean
    if not Grid_IsValidId(areaId) then
        return false
    endif
    return LoadInteger(RevealTable, areaId, HT_REVEALED) != 0
endfunction

function Reveal_GetTotal takes nothing returns integer
    return RevealedTotal
endfunction

// 关卡切换时清空（由 ChapterManager 的 ResetAllSubsystems 调用）
// 注意：不要用 FlushParentHashtable（实测清空后该表 Save/Load 会失效），逐 parent 清子表。
function Reveal_Reset takes nothing returns nothing
    local integer maxId = Grid_GetMaxId()
    local integer i = 0
    loop
        exitwhen i >= maxId
        call FlushChildHashtable(RevealTable, i)
        set i = i + 1
    endloop
    set RevealedTotal = 0
    call DebugLogger_LogKey("[reveal] ResetReveal done")
endfunction

private function InitReveal takes nothing returns nothing
    call AddAreaEnterCallback(function OnAreaEnterReveal)
    call DebugLogger_Log(LOG_TRACE, "[reveal] InitReveal done: enter hook registered")
endfunction

endlibrary
#endif
