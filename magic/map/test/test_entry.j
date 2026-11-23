#ifndef MAGIC_TEST_ENTRY_INCLUDED
#define MAGIC_TEST_ENTRY_INCLUDED
#include "nncou\\magic\\map\\test\\test_framework.j"
/*
    [testEntry] 本次测试的入口库（只被测试版地图引用）

    只放「本次测试」的用例；通用调度在 test_framework.j。
    收录规则：
        - 用例只读生产代码状态；确需改状态的「行为用例」需在用例名里标注 SETUP；
        - 每个用例对应 测试.md 的一个可自动判定项；
        - 失败不许静默，必须走 testFramework_Expect*。

    通过方式（二选一，见回归 MCP 方案）：
        A) 测试版地图的「自定义代码」多一行：#include "nncou\\magic\\map\\test\\test_entry.j"
        B) 构建工具把本文件编入测试版脚本（不改地图数据，产物另存为测试图）。
*/
library testEntry initializer Init requires testFramework, areaGrid, areaData, areaSlot, areaMonsterRoom, areaEnter, areaExit, areaEmergency, areaReveal, areaGridMap, ChapterManager

// 房间类型/状态常量（data.j 里是库内 private constant，这里用数值+注释）
// ROOM_TYPE_MONSTER=0 / SAFE=1 / ENTRY=3；ROOM_STATE_ACTIVE=1 / CLEARED=2

globals
    private unit tHero = null
    private integer castFromArea = -1
    private integer castDir = -1
    private integer castTarget = -1
    private real castHp = 0.0
    private integer lockedArea = -1
    private integer lockedDir = -1
    private integer lockedTarget = -1
    private integer noNeighborArea = -1
    private integer noNeighborDir = -1
    private boolean noNeighborPathBlocked = false
    private real noNeighborSampleX = 0.0
    private real noNeighborSampleY = 0.0
    private string noNeighborLogs = ""
    private integer revealTotalBefore = -1
endglobals

// ===== 小工具 =====

private function HeroCast takes unit u returns nothing
    // A07E（穿越区域）基于隐藏技能 AAns（Neutral Spell），施法命令串为 neutralspell
    call IssueImmediateOrder(u, "neutralspell")
endfunction

private function BoolToStr takes boolean b returns string
    if b then
        return "1"
    endif
    return "0"
endfunction

private function PlayerAreaId takes nothing returns integer
    return GetAreaIdByRect(GetPlayerCurrentAreaRect(Player(0)))
endfunction

private function FindNeighborDir takes integer areaId, integer excludeArea returns integer
    local integer d = 0
    local integer n
    loop
        exitwhen d >= 4
        set n = Grid_GetNeighbor(areaId, d)
        if n >= 0 and n != excludeArea then
            return d
        endif
        set d = d + 1
    endloop
    return -1
endfunction

private function FindNoNeighborDir takes integer areaId returns integer
    local integer d = 0
    loop
        exitwhen d >= 4
        if Grid_GetNeighbor(areaId, d) < 0 then
            return d
        endif
        set d = d + 1
    endloop
    return -1
endfunction

private function PlaceAtDoor takes unit u, integer areaId, integer dir returns boolean
    local integer slotId = Slot_GetSlotOf(areaId)
    local rect door
    if u == null or slotId < 0 or dir < 0 then
        return false
    endif
    set door = Slot_GetSlotDoor(slotId, dir)
    if door == null then
        return false
    endif
    call SetUnitPosition(u, GetRectCenterX(door), GetRectCenterY(door))
    set door = null
    return true
endfunction

private function DoorCenterX takes integer areaId, integer dir returns real
    local rect door = Slot_GetSlotDoor(Slot_GetSlotOf(areaId), dir)
    if door == null then
        return 0.0
    endif
    return GetRectCenterX(door)
endfunction

private function DoorCenterY takes integer areaId, integer dir returns real
    local rect door = Slot_GetSlotDoor(Slot_GetSlotOf(areaId), dir)
    if door == null then
        return 0.0
    endif
    return GetRectCenterY(door)
endfunction

// 路径阻断采样点：exit.j 以 32 为步长从 min+16 开始采样，取该点判断更可靠
private function DoorSampleX takes integer areaId, integer dir returns real
    local rect door = Slot_GetSlotDoor(Slot_GetSlotOf(areaId), dir)
    if door == null then
        return 0.0
    endif
    return GetRectMinX(door) + 16.0
endfunction

private function DoorSampleY takes integer areaId, integer dir returns real
    local rect door = Slot_GetSlotDoor(Slot_GetSlotOf(areaId), dir)
    if door == null then
        return 0.0
    endif
    return GetRectMinY(door) + 16.0
endfunction

private function UnitInRect takes unit u, rect r returns boolean
    local real x = GetUnitX(u)
    local real y = GetUnitY(u)
    return x >= GetRectMinX(r) and x <= GetRectMaxX(r) and y >= GetRectMinY(r) and y <= GetRectMaxY(r)
endfunction

private function DoorRectContainsUnit takes integer areaId, integer dir, unit u returns boolean
    local rect r = Slot_GetSlotDoor(Slot_GetSlotOf(areaId), dir)
    local real x
    local real y
    if r == null or u == null then
        return false
    endif
    set x = GetUnitX(u)
    set y = GetUnitY(u)
    return x >= GetRectMinX(r) and x <= GetRectMaxX(r) and y >= GetRectMinY(r) and y <= GetRectMaxY(r)
endfunction

private function FirstMonsterRoom takes nothing returns integer
    local integer i = 0
    local integer n = GetAreaCount()
    local integer id
    local integer fallback = -1
    // 优先选“尚未揭示且有邻居”的怪物房（4.4 需要进入时新增揭示日志）
    loop
        exitwhen i >= n
        set id = GetAreaByIndex(i)   // B11：按存在房间列表取 id，不假设 id==index
        if id >= 0 and GetRoomType(id) == 0 then
            if not areaMonsterRoom_IsRoomCleared(id) then
                if fallback < 0 then
                    set fallback = id
                endif
                if not Reveal_IsRevealed(id) and GetAreaNeighborCount(id) > 0 then
                    return id
                endif
            endif
        endif
        set i = i + 1
    endloop
    return fallback
endfunction

// ===== 4.4 揭示数据层的小工具 =====
private function OrthNeighborCount takes integer areaId returns integer
    local integer d = 0
    local integer c = 0
    loop
        exitwhen d >= 4
        if Grid_GetNeighbor(areaId, d) >= 0 then
            set c = c + 1
        endif
        set d = d + 1
    endloop
    return c
endfunction

private function MissingRevealedNeighbors takes integer areaId returns integer
    local integer d = 0
    local integer n
    local integer miss = 0
    loop
        exitwhen d >= 4
        set n = Grid_GetNeighbor(areaId, d)
        if n >= 0 then
            if not Reveal_IsRevealed(n) then
                set miss = miss + 1
            endif
        endif
        set d = d + 1
    endloop
    return miss
endfunction

// 已绑定房间的中心（未绑定/槽位无效返回 0，调用方先判 Slot_GetSlotOf）
private function AreaCenterX takes integer areaId returns real
    local integer slotId = Slot_GetSlotOf(areaId)
    local rect r
    if slotId < 0 then
        return 0.0
    endif
    set r = Slot_GetSlotRegion(slotId)
    if r == null then
        return 0.0
    endif
    return GetRectCenterX(r)
endfunction

private function AreaCenterY takes integer areaId returns real
    local integer slotId = Slot_GetSlotOf(areaId)
    local rect r
    if slotId < 0 then
        return 0.0
    endif
    set r = Slot_GetSlotRegion(slotId)
    if r == null then
        return 0.0
    endif
    return GetRectCenterY(r)
endfunction

// SETUP 用：把英雄传送到指定点；先授权离开当前房，避免 areaEnter 守卫把英雄拉回去
private function TeleportHeroSafe takes real x, real y returns nothing
    if tHero == null then
        return
    endif
    call AllowPlayerLeaveAreaOnce(Player(0))
    call SetUnitPosition(tHero, x, y)
endfunction

// ===== 用例 1：启动不变量（网格/槽位/区域数量） =====
private function StepStartup takes nothing returns nothing
    // B11：期望值从配置/API 推导，不写死 49/20
    call testFramework_Expect("grid.total", Grid_GetTotal() > 0, I2S(Grid_GetTotal()))
    call testFramework_Expect("slot.count", Slot_GetCount() > 0, I2S(Slot_GetCount()))
    call testFramework_ExpectInt("area.count", GetAreaCount(), Grid_GetTotal())
endfunction

// ===== 用例 2：网格直边对称 =====
private function StepGridSymmetry takes nothing returns nothing
    local integer i = 0
    local integer d = 0
    local integer n = 0
    local integer bad = 0
    local integer id
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)   // B11：存在格列表
        set d = 0
        loop
            exitwhen d >= 4
            set n = Grid_GetNeighbor(id, d)
            if n >= 0 then
                if Grid_GetNeighbor(n, Grid_OppositeDir(d)) != id then
                    set bad = bad + 1
                endif
            endif
            set d = d + 1
        endloop
        set i = i + 1
    endloop
    call testFramework_ExpectInt("grid.neighborSymmetry", bad, 0)
endfunction

// ===== 用例 3：BOSS 候选房合法 =====
private function StepBossArea takes nothing returns nothing
    local integer boss = GetBossArea()
    local integer row
    local integer col
    local integer entryId
    call testFramework_Expect("boss.configured", boss >= 0, I2S(boss))
    if boss >= 0 then
        set row = Grid_GetRow(boss)
        set col = Grid_GetCol(boss)
        set entryId = GetActiveEnter(ChapterManager_GetCurrentChapter())
        if entryId >= 0 then
            call Grid_BuildDistanceField(entryId)
            call testFramework_Expect("boss.candidate", Grid_GetFieldDistance(boss) >= 6, I2S(row) + "," + I2S(col) + " d=" + I2S(Grid_GetFieldDistance(boss)))
        else
            call testFramework_Expect("boss.candidate", false, "no entry")
        endif
    endif
endfunction

// ===== 用例 4：3.3 启动日志 =====
private function StepLogsBasic takes nothing returns nothing
    local string logs = testFramework_GetStartupLog()
    call testFramework_ExpectInt("3.3.slot.registered", testFramework_CountOccurrences(logs, "[slot] registered slot="), Slot_GetCount())
    call testFramework_Expect("3.3.forest.rooms", testFramework_ContainsText(logs, "[forest] physical rooms registered: slots=" + I2S(Slot_GetCount()) + " terrains=" + I2S(Slot_GetTerrainTypeCount())), I2S(StringLength(logs)))
endfunction

private function StepLogsDoneA takes nothing returns nothing
    local string logs = testFramework_GetStartupLog()
    call testFramework_Expect("3.3.grid.edges58", testFramework_ContainsText(logs, "edges=" + I2S(Grid_GetEdgeCount())), I2S(Grid_GetEdgeCount()))
    call testFramework_Expect("3.3.guards.done", testFramework_ContainsText(logs, "[enter] InitAreaGuards done"), "")
endfunction

private function StepLogsDoneB takes nothing returns nothing
    local string logs = testFramework_GetStartupLog()
    call testFramework_Expect("3.3.exits.done", testFramework_ContainsText(logs, "[exit] InitAreaExits done"), "")
    call testFramework_Expect("3.3.boss.done", testFramework_ContainsText(logs, "[boss] InitBossSystem done"), "")
endfunction

private function StepLogsDoneC takes nothing returns nothing
    local string logs = testFramework_GetStartupLog()
    call testFramework_Expect("3.3.forest.done", testFramework_ContainsText(logs, "[forest] InitForest done"), "")
endfunction

private function StepLogsNoWarn takes nothing returns nothing
    local string logs = testFramework_GetStartupLog()
    call testFramework_ExpectInt("3.3.no.warn", testFramework_CountOccurrences(logs, "[WARN]"), 0)
    call testFramework_ExpectInt("3.3.no.error", testFramework_CountOccurrences(logs, "[ERROR]"), 0)
endfunction

// ===== 用例 5：3.4 起点与入口绑定 =====
private function StepEntryRoom takes nothing returns nothing
    local integer chapter = ChapterManager_GetCurrentChapter()
    local integer entryId
    local integer curArea
    local unit hero = testFramework_GetTestHero()
    local string inGroup = "no"
    call testFramework_Expect("3.4.chapter.active", chapter >= 0, I2S(chapter))
    if chapter < 0 then
        return
    endif
    set entryId = GetActiveEnter(chapter)
    call testFramework_Expect("3.4.entry.valid", entryId >= 0, I2S(entryId))
    if entryId < 0 then
        return
    endif
    call testFramework_ExpectInt("3.4.entry.roomType", GetRoomType(entryId), 3)
    call testFramework_Expect("3.4.entry.slotBound", Slot_GetSlotOf(entryId) >= 0, I2S(Slot_GetSlotOf(entryId)))
    set curArea = GetAreaIdByRect(GetPlayerCurrentAreaRect(Player(0)))
    call testFramework_ExpectInt("3.4.player.area", curArea, entryId)
    call testFramework_Expect("3.4.player.inRoom", areaMonsterRoom_IsPlayerInRoom(Player(0), entryId), "")
    if hero != null then
        if IsUnitInGroup(hero, udg_Heros) then
            set inGroup = "yes"
        endif
        call testFramework_Expect("3.4.hero.inEntryRect", UnitInRect(hero, GetAreaRect(entryId)), GetUnitName(hero))
        call testFramework_Expect("3.4.hero.notInVillage", not UnitInRect(hero, gg_rct_Village), R2S(GetUnitX(hero)) + "," + R2S(GetUnitY(hero)))
        call testFramework_Log("3.4.evidence|hero=" + R2S(GetUnitX(hero)) + "," + R2S(GetUnitY(hero)) + "|villageCenter=" + R2S(GetRectCenterX(gg_rct_Village)) + "," + R2S(GetRectCenterY(gg_rct_Village)) + "|entryCenter=" + R2S(GetRectCenterX(GetAreaRect(entryId))) + "," + R2S(GetRectCenterY(GetAreaRect(entryId))) + "|camera=" + R2S(GetCameraTargetPositionX()) + "," + R2S(GetCameraTargetPositionY()) + "|owner=" + I2S(GetConvertedPlayerId(GetOwningPlayer(hero))) + "|inGroup=" + inGroup)
    else
        call testFramework_Expect("3.4.hero.inEntryRect", false, "hero null")
    endif
    set hero = null
endfunction

// ===== 4.3 网格图 UI：打开/关闭（验证建帧/刷新路径不报错） =====
private function StepGridMapShow takes nothing returns nothing
    local string d = areaGridMap_GetDiag()
    call testFramework_Log("GRIDMAPDIAG|" + d)
    call testFramework_Expect("4.3.gridmap.ready", areaGridMap_IsReady(), "")
    // B 版：Root = 整幅羊皮纸（diag 前缀 paper）。
    call testFramework_Expect("4.3.gridmap.paper", SubString(d, 0, 5) == "paper", SubString(d, 0, 5))
    call areaGridMap_Show()
    call testFramework_Expect("4.3.gridmap.show", areaGridMap_IsVisible(), "")
endfunction

private function StepGridMapHide takes nothing returns nothing
    call areaGridMap_Hide()
    call testFramework_Expect("4.3.gridmap.hide", not areaGridMap_IsVisible(), "")
endfunction

// ===== 3.5/3.6 行为用例的公共前置：拿到测试英雄并授予紧急穿越技能 =====
private function StepHeroReady takes nothing returns nothing
    local unit hero = testFramework_GetTestHero()
    set tHero = hero
    call testFramework_Expect("hero.exists", tHero != null, "")
    if tHero == null then
        return
    endif
    // 模拟右键选英雄流程拿到的英雄没有 A07E（真实局由 GUI 授予，这里测试补齐；
    // 属于 SETUP 行为，记录在报告中可见）
    if GetUnitAbilityLevel(tHero, 'A07E') <= 0 then
        call UnitAddAbility(tHero, 'A07E')
        call SetUnitAbilityLevel(tHero, 'A07E', 1)
        call testFramework_Log("SETUP|grant A07E to hero")
    endif
    call testFramework_Expect("hero.emergency.skill", GetUnitAbilityLevel(tHero, 'A07E') > 0, I2S(GetUnitAbilityLevel(tHero, 'A07E')))
endfunction

// ===== 3.6 安全/入口房免费传送 =====
private function StepFreeSetup takes nothing returns nothing
    local integer chapter = ChapterManager_GetCurrentChapter()
    local integer entryId
    local integer d
    if tHero == null then
        return
    endif
    set entryId = GetActiveEnter(chapter)
    set castFromArea = entryId
    set d = FindNeighborDir(entryId, -1)
    set castDir = d
    call testFramework_Expect("3.6.free.hasNeighbor", d >= 0, I2S(entryId) + " dir=" + I2S(d))
    if d < 0 then
        return
    endif
    set castTarget = Grid_GetNeighbor(entryId, d)
    call testFramework_Expect("3.6.free.place", PlaceAtDoor(tHero, entryId, d), "")
    set castHp = GetUnitState(tHero, UNIT_STATE_LIFE)
    call testFramework_TakeLogs()
    call HeroCast(tHero)
    call testFramework_Log("SETUP|free cast from=" + I2S(entryId) + " dir=" + I2S(d) + " target=" + I2S(castTarget) + " hp=" + R2S(castHp))
endfunction

private function StepFreeCheck takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    local real expectX
    local real expectY
    call testFramework_Expect("3.6.free.log", testFramework_ContainsText(logs, "[emergency] free traverse"), "")
    call testFramework_ExpectInt("3.6.free.area", PlayerAreaId(), castTarget)
    // 落点 = 目标房「通往源房」的门洞中心
    if castTarget >= 0 then
        set expectX = DoorCenterX(castTarget, Grid_OppositeDir(castDir))
        set expectY = DoorCenterY(castTarget, Grid_OppositeDir(castDir))
        call testFramework_ExpectReal("3.6.free.landing", GetUnitX(tHero), expectX, 80.0)
        call testFramework_ExpectReal("3.6.free.landingY", GetUnitY(tHero), expectY, 80.0)
    endif
    call testFramework_ExpectReal("3.6.free.noCost", GetUnitState(tHero, UNIT_STATE_LIFE), castHp, 0.5)
    call testFramework_Expect("3.6.free.noCd", areaEmergency_IsEmergencyActive(Player(0)), "")
    call testFramework_Expect("3.4.1.probe.log", testFramework_ContainsText(logs, "[probe] "), "")
endfunction

// ===== 4.4 揭示：入口房进入即揭示（3x3 + 只走直边） =====
private function StepRevealEntry takes nothing returns nothing
    local integer chapter = ChapterManager_GetCurrentChapter()
    local integer entryId
    local integer row
    local integer col
    local integer diag = -1
    local integer i
    local integer farId
    local integer farDist
    local integer dr
    local integer dc
    local integer id
    local string logs = testFramework_GetStartupLog()
    if chapter < 0 then
        return
    endif
    set entryId = GetActiveEnter(chapter)
    call testFramework_Expect("4.4.entry.center", Reveal_IsRevealed(entryId), I2S(entryId))
    call testFramework_ExpectInt("4.4.entry.neighbors", MissingRevealedNeighbors(entryId), 0)
    call testFramework_ExpectInt("4.4.entry.total", Reveal_GetTotal(), 1 + OrthNeighborCount(entryId))
    call testFramework_Expect("4.4.entry.log", testFramework_ContainsText(logs, "[reveal] 3x3 center=("), I2S(StringLength(logs)))
    set row = Grid_GetRow(entryId)
    set col = Grid_GetCol(entryId)
    // B11：不写死 7 列/24 号房；对角格与远格都按坐标/API 计算（稀疏地图缺格则跳过该格）
    set diag = Grid_GetIdIfPresent(row + 1, col + 1)
    if diag < 0 then
        set diag = Grid_GetIdIfPresent(row + 1, col - 1)
    endif
    if diag < 0 then
        set diag = Grid_GetIdIfPresent(row - 1, col + 1)
    endif
    if diag < 0 then
        set diag = Grid_GetIdIfPresent(row - 1, col - 1)
    endif
    call testFramework_Expect("4.4.entry.diagonal", diag < 0 or not Reveal_IsRevealed(diag), I2S(diag))
    // 远格：取与入口行/列曼哈顿距离最大的存在格（≥2 才在 3x3 窗口外）
    set i = 0
    set farId = -1
    set farDist = 0
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)   // B11：存在格列表
        set dr = Grid_GetRow(id) - row
        if dr < 0 then
            set dr = -dr
        endif
        set dc = Grid_GetCol(id) - col
        if dc < 0 then
            set dc = -dc
        endif
        if dr + dc > farDist then
            set farDist = dr + dc
            set farId = id
        endif
        set i = i + 1
    endloop
    call testFramework_Expect("4.4.window.far", farId < 0 or farDist < 2 or not Reveal_IsRevealed(farId), I2S(farId) + "/" + I2S(farDist))
endfunction

// ===== 3.5 未清房时紧急穿越（付费） =====
private function StepLockedSetup takes nothing returns nothing
    local integer area
    local integer slotId
    call testFramework_Mark("locked: begin")
    set area = FirstMonsterRoom()
    set lockedArea = area
    call testFramework_Mark("locked: monsterRoom=" + I2S(area))
    call testFramework_Expect("3.5.locked.roomFound", area >= 0, I2S(area))
    if area < 0 then
        return
    endif
    call testFramework_Expect("3.5.locked.roomUncleared", not areaMonsterRoom_IsRoomCleared(area), I2S(GetRoomState(area)))
    call testFramework_Mark("locked: before bound")
    set slotId = Area_EnsureBound(area)
    call testFramework_Mark("locked: bound slot=" + I2S(slotId))
    call testFramework_Expect("3.5.locked.bound", slotId >= 0, I2S(slotId))
    if slotId < 0 then
        return
    endif
    if tHero != null then
        call testFramework_Mark("locked: before unit pos")
        call TeleportHeroSafe(AreaCenterX(area), AreaCenterY(area))
        call testFramework_Mark("locked: after unit pos")
    endif
    call testFramework_Mark("locked: end")
endfunction

// ===== 4.4 揭示：进入未清空的怪物房也立即揭示（不依赖清房） =====
private function StepRevealMove takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    if lockedArea < 0 then
        return
    endif
    call testFramework_Expect("4.4.monster.center", Reveal_IsRevealed(lockedArea), I2S(lockedArea))
    call testFramework_ExpectInt("4.4.monster.neighbors", MissingRevealedNeighbors(lockedArea), 0)
    call testFramework_Expect("4.4.monster.log", testFramework_ContainsText(logs, "[reveal] 3x3 center=("), I2S(StringLength(logs)))
endfunction

private function StepLockedSetup2 takes nothing returns nothing
    local integer d
    if tHero == null or lockedArea < 0 then
        return
    endif
    call testFramework_ExpectInt("3.5.locked.playerArea", PlayerAreaId(), lockedArea)
    set d = FindNeighborDir(lockedArea, -1)
    set lockedDir = d
    call testFramework_Expect("3.5.locked.hasNeighbor", d >= 0, I2S(lockedArea) + " dir=" + I2S(d))
    if d < 0 then
        return
    endif
    set lockedTarget = Grid_GetNeighbor(lockedArea, d)
    call testFramework_Expect("3.5.locked.place", PlaceAtDoor(tHero, lockedArea, d), "")
    set castHp = GetUnitState(tHero, UNIT_STATE_LIFE)
    call testFramework_TakeLogs()
    call HeroCast(tHero)
    call testFramework_Log("SETUP|locked cast from=" + I2S(lockedArea) + " dir=" + I2S(d) + " target=" + I2S(lockedTarget) + " hp=" + R2S(castHp))
endfunction

private function StepLockedCheck takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    call testFramework_Expect("3.5.locked.log", testFramework_ContainsText(logs, "[emergency] traverse "), "")
    call testFramework_Expect("3.5.locked.cd3", testFramework_ContainsText(logs, "cd=3.000"), "")
    call testFramework_ExpectInt("3.5.locked.area", PlayerAreaId(), lockedTarget)
    call testFramework_ExpectReal("3.5.locked.costHp", GetUnitState(tHero, UNIT_STATE_LIFE), castHp * 0.8, 10.0)
    call testFramework_Expect("3.5.locked.cdActive", not areaEmergency_IsEmergencyActive(Player(0)), "")
    // 3.8：未清房离开后房间保持未清空（不清空怪物/不回收）
    call testFramework_Expect("3.8.source.uncleared", not areaMonsterRoom_IsRoomCleared(lockedArea), I2S(lockedArea))
endfunction

// 等紧急穿越冷却结束（3 秒）
private function StepWaitCd takes nothing returns nothing
    call testFramework_Log("WAIT|cd 3s")
endfunction

// ===== 3.5 濒死免费（cd=10） =====
private function StepLowHpSetup takes nothing returns nothing
    local integer d
    if tHero == null or lockedArea < 0 then
        return
    endif
    // 离开期间未清空房可能被回收槽位，回来前重新绑定
    call Area_EnsureBound(lockedArea)
    call TeleportHeroSafe(AreaCenterX(lockedArea), AreaCenterY(lockedArea))
    call SetUnitState(tHero, UNIT_STATE_LIFE, GetUnitState(tHero, UNIT_STATE_MAX_LIFE) * 0.2)
    call testFramework_TakeLogs()
    call testFramework_Log("SETUP|low hp return to room=" + I2S(lockedArea) + " slot=" + I2S(Slot_GetSlotOf(lockedArea)) + " hp=" + R2S(GetUnitState(tHero, UNIT_STATE_LIFE)))
endfunction

private function StepLowHpSetup2 takes nothing returns nothing
    local integer d
    if tHero == null or lockedArea < 0 then
        return
    endif
    call testFramework_ExpectInt("3.5.lowhp.playerArea", PlayerAreaId(), lockedArea)
    set d = FindNeighborDir(lockedArea, -1)
    set lockedDir = d
    set lockedTarget = Grid_GetNeighbor(lockedArea, d)
    if d < 0 then
        return
    endif
    call testFramework_Expect("3.5.lowhp.place", PlaceAtDoor(tHero, lockedArea, d), "")
    set castHp = GetUnitState(tHero, UNIT_STATE_LIFE)
    set revealTotalBefore = Reveal_GetTotal()
    call testFramework_TakeLogs()
    call HeroCast(tHero)
endfunction

private function StepLowHpCheck takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    call testFramework_Expect("3.5.lowhp.log", testFramework_ContainsText(logs, "[emergency] traverse "), "")
    call testFramework_Expect("3.5.lowhp.cd10", testFramework_ContainsText(logs, "cd=10.000"), "")
    // 濒死应为免费：不扣 20% 生命（允许自然回复，只断言“没有掉 20%”）
    call testFramework_Expect("3.5.lowhp.noExtraCost", GetUnitState(tHero, UNIT_STATE_LIFE) >= castHp - 1.0, R2S(GetUnitState(tHero, UNIT_STATE_LIFE)) + " vs " + R2S(castHp))
    call testFramework_ExpectInt("3.5.lowhp.area", PlayerAreaId(), lockedTarget)
endfunction

// ===== 4.4 幂等 / 4.7 揭示挂在逻辑房上（槽位回收后仍保留） =====
private function StepRevealPersist takes nothing returns nothing
    call testFramework_ExpectInt("4.4.idempotent.total", Reveal_GetTotal(), revealTotalBefore)
    call testFramework_Expect("4.7.slotrecycle.kept", Reveal_IsRevealed(lockedArea), I2S(Slot_GetSlotOf(lockedArea)))
endfunction

// ===== 3.5 断边方向封死（无邻居不传送 + 路径阻断） =====
private function StepNoNeighborSetup takes nothing returns nothing
    local integer d
    if tHero == null or lockedArea < 0 then
        return
    endif
    call ResetAreaEmergency()
    call testFramework_SetTraceCapture(true)
    call Area_EnsureBound(lockedArea)
    call TeleportHeroSafe(AreaCenterX(lockedArea), AreaCenterY(lockedArea))
    set noNeighborArea = lockedArea
    set d = FindNoNeighborDir(lockedArea)
    set noNeighborDir = d
    call testFramework_Expect("3.5.noneighbor_dir.found", d >= 0, I2S(lockedArea) + " dir=" + I2S(d))
    // 绑定/刷新门洞是在 EnsureBound 里同步完成的，立刻采样路径状态，避免等待期间槽位被回收导致状态还原
    if d >= 0 then
        set noNeighborSampleX = DoorSampleX(lockedArea, d)
        set noNeighborSampleY = DoorSampleY(lockedArea, d)
        set noNeighborPathBlocked = not IsTerrainPathable(noNeighborSampleX, noNeighborSampleY, PATHING_TYPE_WALKABILITY)
    endif
    set noNeighborLogs = testFramework_TakeLogs()
    call testFramework_SetTraceCapture(false)
    call testFramework_Log("PATHDBG|slot=" + I2S(Slot_GetSlotOf(lockedArea)) + "|sample=" + R2S(noNeighborSampleX) + "," + R2S(noNeighborSampleY) + "|blocked=" + BoolToStr(noNeighborPathBlocked) + "|logs=" + I2S(StringLength(noNeighborLogs)) + "|pathing=" + I2S(testFramework_CountOccurrences(noNeighborLogs, "pathing")) + "|decor=" + I2S(testFramework_CountOccurrences(noNeighborLogs, "door decor")))
    call testFramework_TakeLogs()
    call testFramework_Log("SETUP|noneighbor area=" + I2S(lockedArea) + " dir=" + I2S(d))
endfunction

private function StepNoNeighborSetup2 takes nothing returns nothing
    if tHero == null or noNeighborArea < 0 or noNeighborDir < 0 then
        return
    endif
    call testFramework_ExpectInt("3.5.noneighbor.playerArea", PlayerAreaId(), noNeighborArea)
    call PlaceAtDoor(tHero, noNeighborArea, noNeighborDir)
    call testFramework_TakeLogs()
    call HeroCast(tHero)
endfunction

private function StepNoNeighborCheck takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    call testFramework_ExpectInt("3.5.noneighbor.noTeleport", PlayerAreaId(), noNeighborArea)
    call testFramework_ExpectInt("3.5.noneighbor.noFreeLog", testFramework_CountOccurrences(logs, "[emergency] free traverse"), 0)
    call testFramework_ExpectInt("3.5.noneighbor.noPaidLog", testFramework_CountOccurrences(logs, "[emergency] traverse "), 0)
endfunction

// 用「走」来验证封死方向：从房中心向门洞发移动命令，等 2 秒后英雄不应站进门洞矩形
private function StepNoNeighborWalkSetup takes nothing returns nothing
    if tHero == null or noNeighborArea < 0 or noNeighborDir < 0 then
        return
    endif
    call TeleportHeroSafe(AreaCenterX(noNeighborArea), AreaCenterY(noNeighborArea))
    call IssuePointOrder(tHero, "move", noNeighborSampleX, noNeighborSampleY)
    call testFramework_Log("SETUP|walk toward blocked door area=" + I2S(noNeighborArea) + " dir=" + I2S(noNeighborDir) + " target=" + R2S(noNeighborSampleX) + "," + R2S(noNeighborSampleY))
endfunction

private function StepNoNeighborWalkCheck takes nothing returns nothing
    call testFramework_ExpectInt("3.5.noneighbor.walk.stayInRoom", PlayerAreaId(), noNeighborArea)
    call testFramework_Expect("3.5.noneighbor.walk.notInDoor", not DoorRectContainsUnit(noNeighborArea, noNeighborDir, tHero), R2S(GetUnitX(tHero)) + "," + R2S(GetUnitY(tHero)))
endfunction

// ===== 3.6 清房后免费传送 =====
private function StepClearedSetup takes nothing returns nothing
    local integer d
    if tHero == null or lockedArea < 0 then
        return
    endif
    call ResetAreaEmergency()
    // SETUP：把房间标记为已清空（真实流程是清光怪物；这里直接置状态以覆盖免费传送分支）
    call SetRoomState(lockedArea, 2)
    call RefreshAreaExitState(lockedArea)
    call Area_EnsureBound(lockedArea)
    call TeleportHeroSafe(AreaCenterX(lockedArea), AreaCenterY(lockedArea))
    set d = FindNeighborDir(lockedArea, -1)
    set lockedDir = d
    set lockedTarget = Grid_GetNeighbor(lockedArea, d)
    call testFramework_Log("SETUP|cleared room=" + I2S(lockedArea) + " state=" + I2S(GetRoomState(lockedArea)) + " dir=" + I2S(d))
    call testFramework_TakeLogs()
    call testFramework_Log("SETUP|cleared cast")
endfunction

private function StepClearedSetup2 takes nothing returns nothing
    if tHero == null or lockedArea < 0 or lockedDir < 0 then
        return
    endif
    call testFramework_ExpectInt("3.6.cleared.playerArea", PlayerAreaId(), lockedArea)
    call testFramework_Expect("3.6.cleared.traversable", IsSourceTraversable(lockedArea), I2S(GetRoomState(lockedArea)))
    call PlaceAtDoor(tHero, lockedArea, lockedDir)
    set castHp = GetUnitState(tHero, UNIT_STATE_LIFE)
    call testFramework_TakeLogs()
    call HeroCast(tHero)
endfunction

private function StepClearedCheck takes nothing returns nothing
    local string logs = testFramework_TakeLogs()
    call testFramework_Expect("3.6.cleared.freeLog", testFramework_ContainsText(logs, "[emergency] free traverse"), "")
    call testFramework_ExpectInt("3.6.cleared.area", PlayerAreaId(), lockedTarget)
    call testFramework_ExpectReal("3.6.cleared.noCost", GetUnitState(tHero, UNIT_STATE_LIFE), castHp, 8.0)
    call testFramework_Expect("3.6.cleared.noCd", areaEmergency_IsEmergencyActive(Player(0)), "")
endfunction

// ===== 3.10 BOSS 中转房不刷怪 =====
private function StepBossRoomCheck takes nothing returns nothing
    local integer boss = GetBossArea()
    call testFramework_Expect("3.10.boss.exists", boss >= 0, I2S(boss))
    if boss < 0 then
        return
    endif
    call testFramework_ExpectInt("3.10.boss.alive", areaMonsterRoom_RoomGetAliveCount(boss), 0)
    call testFramework_ExpectInt("3.10.boss.unspawned", RoomGetUnspawnedCount(boss), 0)
endfunction

private function Init takes nothing returns nothing
    call testFramework_AddStep(function StepStartup, "startup-invariants")
    call testFramework_AddStep(function StepGridSymmetry, "grid-neighbor-symmetry")
    call testFramework_AddStep(function StepBossArea, "boss-area-candidate")
    call testFramework_AddStep(function StepLogsBasic, "3.3-startup-logs")
    call testFramework_AddStep(function StepLogsDoneA, "3.3-done-logs-a")
    call testFramework_AddStep(function StepLogsDoneB, "3.3-done-logs-b")
    call testFramework_AddStep(function StepLogsDoneC, "3.3-done-logs-c")
    call testFramework_AddStep(function StepLogsNoWarn, "3.3-no-warn-error")
    call testFramework_AddStep(function StepEntryRoom, "3.4-entry-room")
    call testFramework_AddStep(function StepRevealEntry, "4.4-reveal-entry")
    call testFramework_AddStep(function StepGridMapShow, "4.3-gridmap-show")
    call testFramework_AddWaitStep(20, "4.3-gridmap-visible-for-screenshots")
    call testFramework_AddStep(function StepGridMapHide, "4.3-gridmap-hide")
    call testFramework_AddStep(function StepHeroReady, "hero-ready")
    call testFramework_AddStep(function StepFreeSetup, "3.6-free-setup")
    call testFramework_AddStep(function StepFreeCheck, "3.6-free-check")
    call testFramework_AddStep(function StepLockedSetup, "3.5-locked-setup")
    call testFramework_AddStep(function StepRevealMove, "4.4-reveal-move")
    call testFramework_AddStep(function StepLockedSetup2, "3.5-locked-setup2")
    call testFramework_AddStep(function StepLockedCheck, "3.5-locked-check")
    call testFramework_AddWaitStep(12, "3.5-wait-cd")
    call testFramework_AddStep(function StepWaitCd, "3.5-wait-cd-end")
    call testFramework_AddStep(function StepLowHpSetup, "3.5-lowhp-setup")
    call testFramework_AddStep(function StepLowHpSetup2, "3.5-lowhp-setup2")
    call testFramework_AddStep(function StepLowHpCheck, "3.5-lowhp-check")
    call testFramework_AddStep(function StepRevealPersist, "4.4-4.7-reveal-persist")
    call testFramework_AddStep(function StepNoNeighborSetup, "3.5-noneighbor-setup")
    call testFramework_AddStep(function StepNoNeighborSetup2, "3.5-noneighbor-setup2")
    call testFramework_AddStep(function StepNoNeighborCheck, "3.5-noneighbor-check")
    call testFramework_AddStep(function StepNoNeighborWalkSetup, "3.5-noneighbor-walk-setup")
    call testFramework_AddWaitStep(7, "3.5-noneighbor-walk-wait")
    call testFramework_AddStep(function StepNoNeighborWalkCheck, "3.5-noneighbor-walk-check")
    call testFramework_AddStep(function StepClearedSetup, "3.6-cleared-setup")
    call testFramework_AddStep(function StepClearedSetup2, "3.6-cleared-setup2")
    call testFramework_AddStep(function StepClearedCheck, "3.6-cleared-check")
    call testFramework_AddStep(function StepBossRoomCheck, "3.10-boss-room")
endfunction

endlibrary
#endif
