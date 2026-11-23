#ifndef MAGIC_TEST_ENTRY_CHAPTER_SWITCH_INCLUDED
#define MAGIC_TEST_ENTRY_CHAPTER_SWITCH_INCLUDED
#include "nncou\\magic\\map\\test\\test_framework.j"
/*
    [testEntryChapterSwitch] 独立章节切换测试入口（只进测试图，不跑 UI/Step4 基线）
    - 构建：build_test_harness.py 设 TEST_ONLY_ENTRY=chapter_switch（只含 test_framework + 本文件）
    - 流程：开局 Forest → 每步 CompleteChapter → wait → NextChapter（独立 step）→ wait → 校验重建
    - 5 个临时章各强制不同布局（A~E），全程一局内完成，不重开地图、不 RestartChapter
*/
library testEntryChapterSwitch initializer Init requires testFramework, ChapterManager, areaGrid, areaSlot, areaData, BossSystem, CurseSystem, areaGridMap, Forest, DebugLogger

globals
    private integer SwForestId = -1
    private integer SwBaseCount = -1
    private integer SwSlot0Handle = 0
    private integer SwExpectedLayout = 0
    private integer SwTargetId = -1
    private integer SwLastOldId = -1
endglobals

private function SwInitChapter takes nothing returns nothing
    call Forest_SetForcedLayout(SwExpectedLayout)
    call Forest_InitForestChapter(SwTargetId)
endfunction

// 布局房数/边数期望（A~E）
private function SwExpectedCells takes integer layout returns integer
    if layout == 1 or layout == 3 then
        return 14
    endif
    return 13
endfunction

private function StepSwSetup takes nothing returns nothing
    local integer i = 0
    set SwForestId = ChapterManager_GetCurrentChapter()
    set SwBaseCount = ChapterManager_GetChapterCount()
    call testFramework_Expect("SW.setup.forestLast", SwForestId == SwBaseCount - 1, I2S(SwForestId) + "/" + I2S(SwBaseCount))
    call testFramework_Expect("SW.setup.name", ChapterManager_GetChapterName(SwForestId) == "Forest", ChapterManager_GetChapterName(SwForestId))
    call testFramework_ExpectInt("SW.setup.slots", Slot_GetCount(), 20)
    set SwSlot0Handle = GetHandleId(Slot_GetSlotRegion(0))
    // 注册 5 个临时章（同 Forest 逻辑、不同 id/布局）
    loop
        exitwhen i >= 5
        call ChapterManager_RegisterChapter("TestCh" + I2S(i + 2), 600)
        set i = i + 1
    endloop
    set i = 0
    loop
        exitwhen i >= 5
        call ChapterManager_SetChapterInitFunc(SwBaseCount + i, function SwInitChapter)
        set i = i + 1
    endloop
    call testFramework_ExpectInt("SW.setup.count", ChapterManager_GetChapterCount(), SwBaseCount + 5)
    call areaGridMap_Show()
endfunction

private function StepSwComplete takes nothing returns nothing
    set SwLastOldId = ChapterManager_GetCurrentChapter()
    call ChapterManager_CompleteChapter()
    call testFramework_ExpectInt("SW.complete.state", ChapterManager_GetChapterState(SwLastOldId), 2)
    call testFramework_Expect("SW.complete.inactive", not ChapterManager_IsChapterActive(SwLastOldId), I2S(ChapterManager_GetChapterState(SwLastOldId)))
endfunction

private function StepSwNext takes nothing returns nothing
    set SwTargetId = SwLastOldId + 1
    set SwExpectedLayout = SwTargetId - SwBaseCount
    call ChapterManager_NextChapter()
    call testFramework_ExpectInt("SW.next.current", ChapterManager_GetCurrentChapter(), SwTargetId)
    call testFramework_Expect("SW.next.active", ChapterManager_IsChapterActive(SwTargetId), I2S(ChapterManager_GetChapterState(SwTargetId)))
    call testFramework_ExpectInt("SW.next.oldState", ChapterManager_GetChapterState(SwLastOldId), 2)
    call areaGridMap_Show()
    call DisplayTextToPlayer(GetLocalPlayer(), 0.0, 0.0, "[SW] chapter=" + ChapterManager_GetChapterName(SwTargetId) + " layout=" + I2S(SwExpectedLayout))
    call testFramework_Log("[SW] chapter=" + ChapterManager_GetChapterName(SwTargetId) + " layout=" + I2S(SwExpectedLayout) + " diag=" + areaGridMap_GetDiag())
endfunction

private function StepSwValidate takes nothing returns nothing
    local integer total = Grid_GetTotal()
    local integer expected = SwExpectedCells(SwExpectedLayout)
    local integer entryId = GetActiveEnter(ChapterManager_GetCurrentChapter())
    local integer bossId = GetBossArea()
    local string logs = testFramework_TakeLogs()
    call testFramework_ExpectInt("SW.layout.index", Forest_GetLayoutIndex(), SwExpectedLayout)
    call testFramework_ExpectInt("SW.layout.cells", total, expected)
    call testFramework_ExpectInt("SW.layout.edges", Grid_GetEdgeCount(), expected - 1)
    call testFramework_ExpectInt("SW.layout.areas", GetAreaCount(), total)
    call testFramework_Expect("SW.layout.entry", entryId >= 0, I2S(entryId))
    call testFramework_Expect("SW.layout.boss", bossId >= 0, I2S(bossId))
    if entryId >= 0 and bossId >= 0 then
        call Grid_BuildDistanceField(entryId)
        call testFramework_Expect("SW.layout.bossDist", Grid_GetFieldDistance(bossId) >= 6, I2S(Grid_GetFieldDistance(bossId)))
    endif
    call testFramework_ExpectInt("SW.layout.slots", Slot_GetCount(), 20)
    call testFramework_Expect("SW.layout.slotPersist", GetHandleId(Slot_GetSlotRegion(0)) == SwSlot0Handle, I2S(GetHandleId(Slot_GetSlotRegion(0))))
    call testFramework_ExpectInt("SW.layout.noWarn", testFramework_CountOccurrences(logs, "[WARN]") + testFramework_CountOccurrences(logs, "[ERROR]"), 0)
    call testFramework_Log("[SW] validate diag=" + areaGridMap_GetDiag())
    // 等 RebuildUi 完成后再打开面板，作为切章后的可见证据
    call areaGridMap_Show()
endfunction

private function Init takes nothing returns nothing
    local integer i = 0
    call testFramework_AddStep(function StepSwSetup, "SW.setup")
    loop
        exitwhen i >= 5
        call testFramework_AddStep(function StepSwComplete, "SW.complete" + I2S(i + 1))
        call testFramework_AddWaitStep(4, "SW.wait-complete" + I2S(i + 1))
        call testFramework_AddStep(function StepSwNext, "SW.next" + I2S(i + 1))
        call testFramework_AddWaitStep(6, "SW.wait-next" + I2S(i + 1))
        call testFramework_AddStep(function StepSwValidate, "SW.validate" + I2S(i + 1))
        set i = i + 1
    endloop
endfunction

endlibrary
#endif
