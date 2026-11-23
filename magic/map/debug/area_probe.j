#ifndef AREA_PROBE_INCLUDED
#define AREA_PROBE_INCLUDED
#include "nncou\\debug.j"
#include "nncou\\magic\\map\\area\\core\\data.j"
#include "nncou\\magic\\map\\area\\core\\enter.j"
#include "nncou\\magic\\map\\area\\core\\exit.j"
#include "nncou\\magic\\map\\area\\core\\monster_room.j"
/*
    区域调试探针（Step 3 验收用）

    - Area2String(areaId)：当前房间坐标、类型/状态、物理槽位、剩余怪物、
      上下左右 4 个出口的目标坐标或封锁状态（带颜色，用于聊天显示）。
    - 英雄进入逻辑房时自动把颜色版发给该玩家，并把纯文本版写进日志。
    - 纯只读：不绑定槽位、不改房间状态、不刷怪。

    关闭方式：把 PROBE_ENABLED 改成 false（Step 4 正式 UI 接入后）。
    依赖 areaEnter 的 AddAreaEnterCallback：追加在 BOSS 主回调之后执行，
    不会因为关卡切换时 BossSystem 重新 SetAreaEnterCallback 而丢失。
*/
library areaProbe initializer InitAreaProbe requires areaData, areaSlot, areaEnter, areaExit, areaMonsterRoom, MonsterGroup, DebugLogger

globals
    // 验收期开关；关闭后不注册回调、不输出任何内容
    private constant boolean PROBE_ENABLED = true

    private constant string COLOR_TITLE = "|cffffcc00"   // 金：标签
    private constant string COLOR_COORD = "|cffffffff"   // 白：坐标
    private constant string COLOR_DIM = "|cff9a9a9a"     // 灰：次要信息
    private constant string COLOR_OPEN = "|cff40ff40"    // 绿：可通行
    private constant string COLOR_LOCK = "|cffffa500"    // 橙：有邻居但未清空
    private constant string COLOR_SEAL = "|cffff4040"    // 红：无出口 / 错误
    private constant string COLOR_LIVE = "|cffff8080"    // 红：场上怪物
    private constant string COLOR_PENDING = "|cffb0b0ff" // 蓝灰：待刷怪物
    private constant string COLOR_END = "|r"

    private boolean ProbeRegistered = false
endglobals

// 按开关决定是否上色；纯文本版用于日志
private function Paint takes boolean colored, string color, string text returns string
    if colored then
        return color + text + COLOR_END
    endif
    return text
endfunction

private function TerrainLetter takes integer terrain returns string
    if terrain == 0 then
        return "A"
    elseif terrain == 1 then
        return "B"
    elseif terrain == 2 then
        return "C"
    elseif terrain == 3 then
        return "D"
    endif
    return "?"
endfunction

private function RoomTypeName takes integer roomType returns string
    if roomType == ROOM_TYPE_MONSTER then
        return "怪物"
    elseif roomType == ROOM_TYPE_SAFE then
        return "安全"
    elseif roomType == ROOM_TYPE_BOSS then
        return "BOSS"
    elseif roomType == ROOM_TYPE_ENTRY then
        return "入口"
    elseif roomType == ROOM_TYPE_ELITE then
        return "精英"
    elseif roomType == ROOM_TYPE_MERCHANT then
        return "商人"
    endif
    return "未分配"
endfunction

private function RoomTypeColor takes integer roomType returns string
    if roomType == ROOM_TYPE_MONSTER then
        return "|cffff6868"
    elseif roomType == ROOM_TYPE_SAFE then
        return "|cff6cff6c"
    elseif roomType == ROOM_TYPE_BOSS then
        return "|cffd070ff"
    elseif roomType == ROOM_TYPE_ENTRY then
        return "|cff66ccff"
    elseif roomType == ROOM_TYPE_ELITE then
        return "|cffffa040"
    elseif roomType == ROOM_TYPE_MERCHANT then
        return "|cffffe066"
    endif
    return COLOR_DIM
endfunction

private function RoomStateName takes integer roomState returns string
    if roomState == ROOM_STATE_INACTIVE then
        return "未激活"
    elseif roomState == ROOM_STATE_ACTIVE then
        return "进行中"
    elseif roomState == ROOM_STATE_CLEARED then
        return "已清空"
    endif
    return "?"
endfunction

private function RoomStateColor takes integer roomState returns string
    if roomState == ROOM_STATE_INACTIVE then
        return COLOR_DIM
    elseif roomState == ROOM_STATE_ACTIVE then
        return "|cffffd24a"
    elseif roomState == ROOM_STATE_CLEARED then
        return "|cff5cff5c"
    endif
    return COLOR_DIM
endfunction

private function DirName takes integer dir returns string
    if dir == DIR_UP then
        return "上"
    elseif dir == DIR_DOWN then
        return "下"
    elseif dir == DIR_LEFT then
        return "左"
    endif
    return "右"
endfunction

// 组装一行房间信息。colored=false 时不含颜色代码（写日志用）。
private function BuildAreaString takes integer areaId, boolean colored returns string
    local string s
    local string typeName
    local string stateName
    local string typeColor
    local string stateColor
    local integer roomType
    local integer roomState
    local integer slotId
    local integer alive
    local integer pending
    local integer poolTotal
    local integer dir
    local integer neighbor

    if not Grid_IsValidId(areaId) then
        return Paint(colored, COLOR_SEAL, "[房] 无效区域 " + GetAreaIdName(areaId))
    endif

    set roomType = GetRoomType(areaId)
    set roomState = GetRoomState(areaId)
    set slotId = Slot_GetSlotOf(areaId)
    set alive = GetAreaAliveMonsterCount(areaId)
    set pending = RoomGetUnspawnedCount(areaId)
    // 本房怪物池总量：用来区分「待刷 7」是只刷了一部分，还是整组本来就只有 7 只
    if roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE then
        set poolTotal = GetGroupTotalCount(GetAreaMonsterPool(areaId))
    else
        set poolTotal = 0
    endif
    set typeName = RoomTypeName(roomType)
    set stateName = RoomStateName(roomState)
    set typeColor = RoomTypeColor(roomType)
    set stateColor = RoomStateColor(roomState)

    set s = Paint(colored, COLOR_TITLE, "[房]") + " " + Paint(colored, COLOR_COORD, GetAreaIdName(areaId))
    set s = s + " " + Paint(colored, typeColor, typeName) + "·" + Paint(colored, stateColor, stateName)

    if slotId >= 0 then
        set s = s + " " + Paint(colored, COLOR_DIM, "槽" + I2S(slotId) + TerrainLetter(Slot_GetSlotTerrain(slotId)))
    else
        set s = s + " " + Paint(colored, COLOR_SEAL, "未绑定")
    endif

    // 只有刷怪房或仍有怪物时才显示数量，避免安全房噪音
    if roomType == ROOM_TYPE_MONSTER or roomType == ROOM_TYPE_ELITE or alive > 0 or pending > 0 then
        set s = s + " | " + Paint(colored, COLOR_LIVE, "场上" + I2S(alive)) + " " + Paint(colored, COLOR_PENDING, "待刷" + I2S(pending) + "/池" + I2S(poolTotal))
    endif

    // 4 个方向：无法通行 / 有邻居但未清空 / 可通行
    set s = s + " |"
    set dir = 0
    loop
        exitwhen dir >= 4
        set neighbor = Grid_GetNeighbor(areaId, dir)
        if neighbor < 0 then
            set s = s + " " + Paint(colored, COLOR_SEAL, DirName(dir) + "×")
        elseif IsSourceTraversable(areaId) then
            set s = s + " " + Paint(colored, COLOR_OPEN, DirName(dir) + GetAreaIdName(neighbor))
        else
            set s = s + " " + Paint(colored, COLOR_LOCK, DirName(dir) + GetAreaIdName(neighbor) + "锁")
        endif
        set dir = dir + 1
    endloop

    return s
endfunction

// 带颜色的房间信息（聊天显示用）
function Area2String takes integer areaId returns string
    return BuildAreaString(areaId, true)
endfunction

// 纯文本房间信息（日志用，避免颜色代码写进日志）
function Area2StringPlain takes integer areaId returns string
    return BuildAreaString(areaId, false)
endfunction

private function Trig_AreaProbeEnter takes nothing returns nothing
    local integer areaId = GetAreaEnterCallbackArea()
    local unit u = GetAreaEnterCallbackUnit()
    local player p
    if u == null then
        return
    endif
    set p = GetOwningPlayer(u)
    call DisplayTextToPlayer(p, 0, 0, Area2String(areaId))
    call DebugLogger_Log(LOG_INFO, "[probe] " + GetPlayerName(p) + " " + Area2StringPlain(areaId))
    set u = null
    set p = null
endfunction

private function InitAreaProbe takes nothing returns nothing
    if not PROBE_ENABLED then
        return
    endif
    if ProbeRegistered then
        return
    endif
    set ProbeRegistered = true
    call AddAreaEnterCallback(function Trig_AreaProbeEnter)
    call DebugLogger_Log(LOG_INFO, "[probe] Area2String entry hook registered")
endfunction

endlibrary
#endif
