#ifndef GRID_MAP_UI_
#define GRID_MAP_UI_
    /*
    ============================================================================
    areaGridMap - Step 4 视觉层：B 版「实体羊皮纸地图」面板（2026-11-17 实机修订版）

    设计参数：UI 设计师 web_proto/ingame_fix_spec.md（1100×568 参考像素）
    - 面板 (221,56) 658×344，左右各 221px 留白；避开右上 HUD(≥56) 与底部控制台(<415)；
    - 纸面单 BACKDROP（烧边 alpha 烘焙）；标题单行居中（16px）；右上「~ 关闭」；
    - 网格按章节配置（当前 Forest 样例 7×7：cell 41×33 / gap 5 / pitch 46×38 / 起点 (260,104)）；
      走廊按实际边表只画格缝（当前样例 58 条）；当前格：朱砂红环 + 蜡封；未领取金印；
    - 右侧：信息卡 (595,100,245,104) + 纸上图例（2×3 + 状态行），删除说明文字/副题/统计/罗盘；
    - 悬停：每格透明 GLUEBUTTON + DzFrameSetScript 事件 2/3 + DzGetTriggerUIEventFrame；
    - 队友：英雄 .Art 图标（EXExecuteScript 读 jass.slk unit Art）钉格角，零新增贴图；
    - 交互参考作者 CreateHeroPickIcon 触发；PlayerMsg.j 仅借鉴通用写法（TEXT Enable=false）。
    - 颜色 = 预烘贴图 + 文字色 + 帧 alpha（BACKDROP 顶点色无效）；文字左对齐手算。
    Depends on: areaData, areaGrid, areaReveal, areaEnter,
                RewardItem, RewardAltar, ChapterManager, DebugLogger
    ============================================================================
    */
library areaGridMap initializer InitGridMap requires areaData, areaGrid, areaReveal, areaEnter, RewardItem, RewardAltar, ChapterManager, DebugLogger

globals
    // ===== 网格区（固定面板内区域；cell 尺寸按章节包围盒自适应）=====
    // 当前 7×7 下还原为 cell 41×33 / gap 5 / pitch 46×38
    private constant real GRID_AREA_X = 0.023273      // 32px（v1.5 网格 253,112）
    private constant real GRID_AREA_Y = 0.059155      // 56px
    private constant real GRID_AREA_W = 0.260364      // 358px
    private constant real GRID_AREA_H = 0.291549      // 276px
    private constant real GRID_AREA_W_PX = 358.0
    private constant real GRID_AREA_H_PX = 276.0
    private real GAP_X = 0.004364            // 运行时按 v1.6 公式
    private real GAP_Y = 0.006338            // 运行时按 v1.6 公式
    private real CellW = 0.029818                     // 运行时计算（当前样例 41px）
    private real CellH = 0.034859                     // 运行时计算（当前样例 33px）
    private real PitchX = 0.033455                     // CellW + GAP_X
    private real PitchY = 0.040141                     // CellH + GAP_Y
    private real GridOffX = 0.023273
    private real GridOffY = 0.059155

    // ===== 面板（UI 单位；1px = 0.8/1100 x、1/946.6667 y）=====
    private constant real ROOT_W = 0.478545          // 658px
    private constant real ROOT_H = 0.376056          // 356px（v1.4）
    private constant real ROOT_CENTER_Y = 0.052817   // v1.4：top=56, h=356 → 上移 50px

    // ===== 走廊 =====
    private constant real EDGE_THICK_X = 0.002909   // 4px
    private constant real EDGE_THICK_Y = 0.004225   // 4px
    private constant real EDGE_GROW = 0.001455      // 两端各伸出 2px

    // ===== 右侧列：信息卡 (595,100,245,104) 相对纸面 (374,44) =====
    private constant real RIGHT_X = 0.293818          // 404px（625-221）
    private constant real INFO_Y = 0.059155           // 56px
    private constant real INFO_W = 0.161455           // 222px
    private constant real INFO_H = 0.114085           // 108px
    private constant real INFO_TEXT_X = 0.302545     // +12px
    private constant real INFO_Y_TITLE = 0.067606    // +8px
    private constant real INFO_Y_L0 = 0.090845       // +30px
    private constant real INFO_Y_L1 = 0.124648       // +62px
    private constant real INFO_Y_L2 = 0.147887       // +84px
    private constant real INFO_Y_DEF0 = 0.107746     // +46px（默认两行）
    private constant real INFO_Y_DEF1 = 0.133099     // +70px

    // 图例：标题 (595,218) 相对纸 (374,162)；行区 (595,242)；状态行 y=334
    private constant real LEGEND_TITLE_Y = 0.179577  // 170px（625,226）
    private constant real LEGEND_ROW_Y = 0.207042    // 196px（625,252）
    private constant real LEGEND_ROW_H = 0.035918     // 34px
    private constant real LEGEND_COL_W = 0.080727     // 111px
    private constant real LEGEND_EM_W = 0.016000      // 22px
    private constant real LEGEND_EM_H = 0.023244
    private constant real LEGEND_STATUS_Y = 0.321127 // 304px（625,360）
    private constant real STATUS_EM_W = 0.014545      // 20px
    private constant real STATUS_EM_H = 0.021127

    // 标题/关闭
    private constant real TITLE_X = 0.184727          // 475-221 px
    private constant real TITLE_Y = 0.031690          // 30px（y=86）
    private constant real CLOSE_X = 0.407          // 801-221 px
    private constant real CLOSE_Y = 0.031690

    // 小标记尺寸（x/y 单位不同，分别给宽高）
    private constant real WAX_W = 0.018909            // 26px（v1.4）
    private constant real WAX_H = 0.027465
    private constant real GOLD_W = 0.014545           // 20px（v1.4）
    private constant real GOLD_H = 0.021127
    private constant real TEAM_W = 0.016000            // 22px（v1.4）
    private constant real TEAM_H = 0.023244

    // ===== 贴图（TGA；作者导入；路径固定）=====
    private constant string TEX_PAPER = "ui\\map_paper.blp"
    private constant string TEX_CELL_UNEXPLORED = "ui\\map_cell_unexplored.blp"
    private constant string TEX_CELL_UNKNOWN = "ui\\map_cell_unknown.blp"
    private constant string TEX_CELL_PLAIN = "ui\\map_cell_plain.blp"
    private constant string TEX_CELL_MONSTER = "ui\\map_cell_monster.blp"
    private constant string TEX_CELL_SAFE = "ui\\map_cell_safe.blp"
    private constant string TEX_CELL_BOSS = "ui\\map_cell_boss.blp"
    private constant string TEX_CELL_ENTRY = "ui\\map_cell_entry.blp"
    private constant string TEX_CELL_ELITE = "ui\\map_cell_elite.blp"
    private constant string TEX_CELL_MERCHANT = "ui\\map_cell_merchant.blp"
    private constant string TEX_CELL_MONSTER_CLEARED = "ui\\map_cell_monster_cleared.blp"
    private constant string TEX_CELL_SAFE_CLEARED = "ui\\map_cell_safe_cleared.blp"
    private constant string TEX_CELL_BOSS_CLEARED = "ui\\map_cell_boss_cleared.blp"
    private constant string TEX_CELL_ENTRY_CLEARED = "ui\\map_cell_entry_cleared.blp"
    private constant string TEX_CELL_ELITE_CLEARED = "ui\\map_cell_elite_cleared.blp"
    private constant string TEX_CELL_MERCHANT_CLEARED = "ui\\map_cell_merchant_cleared.blp"
    private constant string TEX_ROAD_H = "ui\\map_road_h.blp"
    private constant string TEX_ROAD_V = "ui\\map_road_v.blp"
    private constant string TEX_TERRAIN_MOUNTAIN = "ui\\map_terrain_mountain.blp"
    private constant string TEX_TERRAIN_TREE = "ui\\map_terrain_tree.blp"
    private constant string TEX_TERRAIN_WATER = "ui\\map_terrain_water.blp"
    private constant string TEX_CUR_RING = "ui\\map_current_ring.blp"
    private constant string TEX_HOVER_RING = "ui\\map_hover_ring.blp"
    private constant string TEX_WAX = "ui\\map_wax_seal.blp"
    private constant string TEX_GOLD = "ui\\map_gold_seal.blp"
    private constant string TEX_CARD_INFO = "ui\\map_card_info.blp"
    private constant string TEX_EM_MONSTER = "ui\\map_em_monster.blp"
    private constant string TEX_EM_SAFE = "ui\\map_em_safe.blp"
    private constant string TEX_EM_BOSS = "ui\\map_em_boss.blp"
    private constant string TEX_EM_ENTRY = "ui\\map_em_entry.blp"
    private constant string TEX_EM_ELITE = "ui\\map_em_elite.blp"
    private constant string TEX_EM_MERCHANT = "ui\\map_em_merchant.blp"
    private constant string TEX_EM_UNKNOWN = "ui\\map_em_unknown_pale.blp"
    private constant string TEX_EM_CHECK = "ui\\map_em_check.blp"
    private constant string TEX_BLANK = "ui\\blank.blp"
    private constant string TEX_CURSED = "ui\\map_cursed_overlay.blp"

    // ===== 颜色 =====
    private constant integer COLOR_DARK = -13425382    // #33251A
    private constant integer COLOR_MUTED = -9743558    // #6B533A
    private constant integer COLOR_L2 = -12176097      // #46351F
    private constant integer COLOR_RED = -7460062      // #8E2B22

    // ===== 字体（fonts.ttf；参数≈px*0.033）=====
    private constant string FONT_PATH = "fonts.ttf"
    private constant real FS_TITLE = 0.66          // 20px
    private constant real FS_INFO_TITLE = 0.46     // 14px
    private constant real FS_INFO_L0 = 0.53        // 16px
    private constant real FS_INFO_L12 = 0.46       // 14px
    private constant real FS_LEGEND_TITLE = 0.59   // 18px
    private constant real FS_LEGEND = 0.46         // 14px
    private constant real FS_STATUS = 0.43         // 13px
    private constant real FS_CLOSE = 0.43          // 13px

    private constant integer ALPHA_FULL = 255
    private constant integer ALPHA_EDGE = 235

    private constant integer KEY_TOGGLE = 192
    private constant integer KEY_EVENT_DOWN = 1
    private constant integer KEY_EVENT_UP = 0

    private constant real INIT_RETRY_INTERVAL = 1.0
    private constant real REFRESH_INTERVAL = 0.5
    private constant integer INIT_MAX_ATTEMPTS = 30
    private constant integer DIAG_MAX_LEN = 300

    // ===== frames =====
    private integer Root = 0
    private integer TitleText = 0
    private integer CloseText = 0
    private integer array CellFrame
    private integer array CursedFrame
    private integer array CursedCache
    private integer array RoadFrame
    private integer RoadCount = 0
    private integer array TerrainFrame
    private integer TerrainCount = 0
    private integer CurRing = 0
    private integer Wax = 0
    private integer GoldSeal = 0
    private integer HoverRing = 0
    private integer array HoverBtn
    private integer InfoCard = 0
    private integer InfoTitle = 0
    private integer array InfoLine
    private integer array InfoDef
    private integer LegendTitle = 0
    private integer array LegendChip
    private integer array LegendEm
    private integer array LegendName
    private integer array StatusChip
    private integer array StatusEm
    private integer array StatusText
    private integer array TeamMark

    // ===== state/caches =====
    private integer array CellTexCache
    private integer LastChapterId = -1
    private integer CurCell = -1
    private integer GoldCell = -1
    private integer HoverCell = -1
    private integer array TeamTypeCache
    private integer array TeamAreaCache
    private string array HeroIconPath
    private integer array HeroIconType

    private boolean uiReady = false
    private boolean uiCreating = false
    private boolean uiVisible = false
    private boolean keyHeld = false
    private integer initAttempts = 0
    private timer refreshTimer = null
    private timer initTimer = null
    private string diag = ""
endglobals

private function Diag takes string s returns nothing
    if StringLength(diag) < DIAG_MAX_LEN then
        set diag = diag + s + ">"
    endif
endfunction

private function CellLeft takes integer col returns real
    return GridOffX + I2R(col) * PitchX
endfunction

private function CellTop takes integer row returns real
    return GridOffY + I2R(row) * PitchY
endfunction

private function CellCenterX takes integer col returns real
    return CellLeft(col) + CellW / 2.0
endfunction

private function CellCenterY takes integer row returns real
    return CellTop(row) + CellH / 2.0
endfunction

private function CellTex takes integer roomType, boolean cleared returns string
    if roomType == 0 then
        if cleared then
            return TEX_CELL_MONSTER_CLEARED
        endif
        return TEX_CELL_MONSTER
    elseif roomType == 1 then
        if cleared then
            return TEX_CELL_SAFE_CLEARED
        endif
        return TEX_CELL_SAFE
    elseif roomType == 2 then
        if cleared then
            return TEX_CELL_BOSS_CLEARED
        endif
        return TEX_CELL_BOSS
    elseif roomType == 3 then
        if cleared then
            return TEX_CELL_ENTRY_CLEARED
        endif
        return TEX_CELL_ENTRY
    elseif roomType == 4 then
        if cleared then
            return TEX_CELL_ELITE_CLEARED
        endif
        return TEX_CELL_ELITE
    elseif roomType == 5 then
        if cleared then
            return TEX_CELL_MERCHANT_CLEARED
        endif
        return TEX_CELL_MERCHANT
    endif
    return TEX_CELL_UNKNOWN
endfunction

private function EmTex takes integer roomType returns string
    if roomType == 0 then
        return TEX_EM_MONSTER
    elseif roomType == 1 then
        return TEX_EM_SAFE
    elseif roomType == 2 then
        return TEX_EM_BOSS
    elseif roomType == 3 then
        return TEX_EM_ENTRY
    elseif roomType == 4 then
        return TEX_EM_ELITE
    elseif roomType == 5 then
        return TEX_EM_MERCHANT
    endif
    return TEX_EM_UNKNOWN
endfunction

private function RoomTypeName takes integer roomType returns string
    if roomType == 0 then
        return "简单作战"
    elseif roomType == 1 then
        return "安全"
    elseif roomType == 2 then
        return "BOSS"
    elseif roomType == 3 then
        return "入口"
    elseif roomType == 4 then
        return "精英"
    elseif roomType == 5 then
        return "商人"
    endif
    return "未知"
endfunction

private function ChapterDisplayName takes integer chapterId returns string
    local string nm = ChapterManager_GetChapterName(chapterId)
    local string suffix
    if nm == "Forest" then
        return "森林"
    endif
    if StringLength(nm) >= 6 and SubString(nm, 0, 6) == "Forest" then
        set suffix = SubString(nm, 6, StringLength(nm))
        return "森林" + suffix
    endif
    return nm
endfunction

private function ChapterDisplayIndex takes integer chapterId returns integer
    local string nm = ChapterManager_GetChapterName(chapterId)
    local string suffix
    if nm == "Forest" then
        return 1
    endif
    if StringLength(nm) >= 6 and SubString(nm, 0, 6) == "Forest" then
        set suffix = SubString(nm, 6, StringLength(nm))
        return 1 + S2I(suffix)
    endif
    return chapterId
endfunction

private function UpdateTitle takes integer chapterId returns nothing
    if TitleText == 0 then
        return
    endif
    if chapterId < 0 then
        call DzFrameSetText(TitleText, "关卡地图")
    else
        call DzFrameSetText(TitleText, "第 " + I2S(ChapterDisplayIndex(chapterId)) + " 章 · " + ChapterDisplayName(chapterId))
    endif
endfunction

private function HeroIcon takes integer playerId returns string
    local unit u
    local integer tid
    if playerId < 1 or playerId > 4 then
        return ""
    endif
    set u = udg_Hero[playerId]
    if u == null then
        return ""
    endif
    set tid = GetUnitTypeId(u)
    if HeroIconType[playerId] != tid then
        set HeroIconType[playerId] = tid
        set HeroIconPath[playerId] = EXExecuteScript("(require'jass.slk').unit[" + I2S(tid) + "].Art")
    endif
    set u = null
    return HeroIconPath[playerId]
endfunction

private function AreaOfUnit takes unit u returns integer
    local integer i = 0
    local integer id
    local rect r
    local real x = GetUnitX(u)
    local real y = GetUnitY(u)
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if id >= 0 then
            set r = GetAreaRect(id)
            if r != null then
                if RectContainsCoords(r, x, y) then
                    return id
                endif
            endif
        endif
        set i = i + 1
    endloop
    return -1
endfunction

// ===== 信息卡默认/悬停 =====
private function ShowInfoDefault takes nothing returns nothing
    local integer i = 0
    loop
        exitwhen i >= 3
        if InfoLine[i] != 0 then
            call DzFrameShow(InfoLine[i], false)
        endif
        set i = i + 1
    endloop
    if InfoDef[0] != 0 then
        call DzFrameSetText(InfoDef[0], "将鼠标移到房间上")
        call DzFrameClearAllPoints(InfoDef[0])
        call DzFrameSetPoint(InfoDef[0], 0, Root, 0, INFO_TEXT_X, -INFO_Y_DEF0)
        call DzFrameShow(InfoDef[0], true)
    endif
    if InfoDef[1] != 0 then
        call DzFrameSetText(InfoDef[1], "红纹=已侵蚀")
        call DzFrameClearAllPoints(InfoDef[1])
        call DzFrameSetPoint(InfoDef[1], 0, Root, 0, INFO_TEXT_X, -INFO_Y_DEF1)
        call DzFrameShow(InfoDef[1], true)
    endif
endfunction

private function HoverIndexFromFrame takes integer f returns integer
    local integer i = 0
    local integer id
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if HoverBtn[id] == f then
            return id
        endif
        set i = i + 1
    endloop
    return -1
endfunction

private function RefreshHover takes integer areaId returns nothing
    local integer row
    local integer col
    local integer roomType
    local integer state
    local integer p
    local integer here
    local string s1
    local string s2
    local string s3
    local integer i = 0
    if areaId < 0 then
        if HoverRing != 0 then
            call DzFrameShow(HoverRing, false)
        endif
        set HoverCell = -1
        call ShowInfoDefault()
        return
    endif
    set row = Grid_GetRow(areaId)
    set col = Grid_GetCol(areaId)
    if HoverRing != 0 then
        call DzFrameClearAllPoints(HoverRing)
        call DzFrameSetPoint(HoverRing, 0, Root, 0, CellLeft(col) - 0.001455, -(CellTop(row) - 0.001455))
        call DzFrameSetSize(HoverRing, CellW + 0.004364, CellH + 0.006338)
        call DzFrameShow(HoverRing, true)
    endif
    if InfoDef[0] != 0 then
        call DzFrameShow(InfoDef[0], false)
    endif
    if InfoDef[1] != 0 then
        call DzFrameShow(InfoDef[1], false)
    endif
    loop
        exitwhen i >= 3
        if InfoLine[i] != 0 then
            call DzFrameShow(InfoLine[i], true)
        endif
        set i = i + 1
    endloop
    if not Reveal_IsRevealed(areaId) then
        set s1 = "第" + I2S(row + 1) + "行·第" + I2S(col + 1) + "列（未探索）"
        set s2 = "房型未知"
        set s3 = ""
    else
        set roomType = GetRoomType(areaId)
        set state = GetRoomState(areaId)
        set s1 = "第" + I2S(row + 1) + "行·第" + I2S(col + 1) + "列·" + RoomTypeName(roomType)
        if state == 2 then
            set s2 = "已清"
        else
            set s2 = "未清"
        endif
        if AreaIsCursed(areaId) then
            set s2 = s2 + "·已侵蚀"
        endif
        if RewardAltar_HasAltar(areaId) and not RewardItem_IsPlayerClaimed(areaId, GetConvertedPlayerId(GetLocalPlayer())) then
            set s2 = s2 + "·有奖励"
        else
            set s2 = s2 + "·无奖励"
        endif
        set here = 0
        set p = 1
        loop
            exitwhen p > 4
            if udg_Hero[p] != null and AreaOfUnit(udg_Hero[p]) == areaId then
                set here = here + 1
            endif
            set p = p + 1
        endloop
        if here <= 0 then
            set s3 = "无自己与队友"
        elseif here == 1 then
            set s3 = "自己/队友在此"
        else
            set s3 = "多人聚集在此"
        endif
    endif
    if InfoLine[0] != 0 then
        call DzFrameSetText(InfoLine[0], s1)
    endif
    if InfoLine[1] != 0 then
        call DzFrameSetText(InfoLine[1], s2)
    endif
    if InfoLine[2] != 0 then
        call DzFrameSetText(InfoLine[2], s3)
    endif
endfunction

private function OnCellEnter takes nothing returns nothing
    local integer idx = HoverIndexFromFrame(DzGetTriggerUIEventFrame())
    if idx < 0 then
        return
    endif
    set HoverCell = idx
    call RefreshHover(idx)
endfunction

private function OnCellLeave takes nothing returns nothing
    local integer idx = HoverIndexFromFrame(DzGetTriggerUIEventFrame())
    if idx < 0 then
        return
    endif
    if HoverCell == idx then
        call RefreshHover(-1)
    endif
endfunction

private function CreateTexFrame takes string name, integer parent, string tex, real w, real h returns integer
    local integer f = DzCreateFrameByTagName("BACKDROP", name, parent, "template", 0)
    if f == 0 then
        return 0
    endif
    call DzFrameSetTexture(f, tex, 0)
    call DzFrameSetSize(f, w, h)
    call DzFrameSetAlpha(f, ALPHA_FULL)
    return f
endfunction

private function CreateTextFrame takes string name, integer parent, string text, real w, real h, real fs, integer color returns integer
    local integer f = DzCreateFrameByTagName("TEXT", name, parent, "template", 0)
    if f == 0 then
        return 0
    endif
    call DzFrameSetSize(f, w, h)
    call DzFrameSetFont(f, FONT_PATH, fs, 0)
    call DzFrameSetTextColor(f, color)
    call DzFrameSetText(f, text)
    call DzFrameSetEnable(f, false)
    return f
endfunction

// 诊断：把 UI 在"当前窗口分辨率"下的实际像素矩形打进日志，供截图核对使用
// （替代从截图猜面板位置；见 magic/UI设计规范.md §10.1）
private function LogRects takes nothing returns nothing
    local integer w = DzGetWindowWidth()
    local integer h = DzGetWindowHeight()
    local integer rootL
    local integer rootT
    local integer rootW = R2I(ROOT_W * w / 0.8)
    local integer rootH = R2I(ROOT_H * h / 0.6)
    set rootL = w / 2 - rootW / 2
    set rootT = h / 2 - R2I(ROOT_CENTER_Y * h / 0.6) - rootH / 2
    call DebugLogger_Log(LOG_INFO, "[gridmap] rects win=" + I2S(w) + "x" + I2S(h) + " root=" + I2S(rootL) + "," + I2S(rootT) + "," + I2S(rootW) + "," + I2S(rootH) + " grid=" + I2S(rootL + R2I(GRID_AREA_X * w / 0.8)) + "," + I2S(rootT + R2I(GRID_AREA_Y * h / 0.6)) + "," + I2S(R2I(GRID_AREA_W * w / 0.8)) + "," + I2S(R2I(GRID_AREA_H * h / 0.6)) + " info=" + I2S(rootL + R2I(RIGHT_X * w / 0.8)) + "," + I2S(rootT + R2I(INFO_Y * h / 0.6)) + "," + I2S(R2I(INFO_W * w / 0.8)) + "," + I2S(R2I(INFO_H * h / 0.6)) + " safe=" + I2S(rootL + 32 * w / 1100) + "," + I2S(rootT + 25 * h / 568) + "," + I2S(rootL + 626 * w / 1100) + "," + I2S(rootT + 331 * h / 568))
endfunction

private function CreateUi takes nothing returns nothing
    local integer i = 0
    local integer dir
    local integer n
    local integer f
    local integer row
    local integer col
    local integer id
    local integer cellCount
    local integer boundRows
    local integer boundCols
    local integer colIdx
    local integer rowIdx
    local real cx
    local real cy
    local real px
    local real py
    local string emTex
    local real gapPx
    local real cellPx
    local real tmpPx
    local real gridW
    local real gridH

    set uiCreating = true
    if Grid_GetTotal() <= 0 then
        set uiCreating = false
        return
    endif
    set boundRows = Grid_GetBoundingRows()
    set boundCols = Grid_GetBoundingCols()
    if boundRows <= 0 or boundCols <= 0 then
        set uiCreating = false
        return
    endif
    // v1.6：节点小、道路主视觉；按包围盒计算 G/cell 并在网格区居中
    if boundRows > boundCols then
        set n = boundRows
    else
        set n = boundCols
    endif
    if n <= 5 then
        set gapPx = 16.0
    elseif n == 6 then
        set gapPx = 14.0
    else
        set gapPx = 12.0
    endif
    set cellPx = (GRID_AREA_W_PX - I2R(boundCols - 1) * gapPx) / I2R(boundCols)
    set tmpPx = (GRID_AREA_H_PX - I2R(boundRows - 1) * gapPx) / I2R(boundRows)
    if tmpPx < cellPx then
        set cellPx = tmpPx
    endif
    if cellPx > 42.0 then
        set cellPx = 42.0
    endif
    if n <= 5 and cellPx > 36.0 then
        set cellPx = 36.0
    endif
    if cellPx < 30.0 then
        set cellPx = 30.0
    endif
    set CellW = cellPx * 0.8 / 1100.0
    set CellH = cellPx / 946.6667
    set GAP_X = gapPx * 0.8 / 1100.0
    set GAP_Y = gapPx / 946.6667
    set PitchX = CellW + GAP_X
    set PitchY = CellH + GAP_Y
    set gridW = I2R(boundCols) * CellW + I2R(boundCols - 1) * GAP_X
    set gridH = I2R(boundRows) * CellH + I2R(boundRows - 1) * GAP_Y
    set GridOffX = GRID_AREA_X + (GRID_AREA_W - gridW) / 2.0
    set GridOffY = GRID_AREA_Y + (GRID_AREA_H - gridH) / 2.0

    set Root = CreateTexFrame("GridMapPaper", DzGetGameUI(), TEX_PAPER, ROOT_W, ROOT_H)
    if Root == 0 then
        set uiCreating = false
        return
    endif
    call DzFrameSetPoint(Root, 4, DzGetGameUI(), 4, 0.0, ROOT_CENTER_Y)
    call Diag("paper")

    // 标题（单行居中手算）+ 关闭提示
    set TitleText = CreateTextFrame("GridTitle", Root, "关卡地图", 0.24, 0.034, FS_TITLE, COLOR_DARK)
    if TitleText != 0 then
        call DzFrameSetPoint(TitleText, 0, Root, 0, TITLE_X, -TITLE_Y)
    endif
    set CloseText = CreateTextFrame("GridClose", Root, "~ 关闭", 0.09, 0.028, FS_CLOSE, COLOR_MUTED)
    if CloseText != 0 then
        call DzFrameSetPoint(CloseText, 0, Root, 0, CLOSE_X, -CLOSE_Y)
    endif

    // 格底（B11：遍历存在格列表，稀疏图不画幽灵格）
    set cellCount = Grid_GetTotal()
    set i = 0
    loop
        exitwhen i >= cellCount
        set id = Grid_GetCellByIndex(i)
        if id >= 0 then
            set row = Grid_GetRow(id)
            set col = Grid_GetCol(id)
            set f = CreateTexFrame("GridCell" + I2S(id), Root, TEX_CELL_UNEXPLORED, CellW, CellH)
            if f != 0 then
                call DzFrameSetPoint(f, 0, Root, 0, CellLeft(col), -CellTop(row))
                call DzFrameShow(f, false)
            endif
            set CellFrame[id] = f
            set CellTexCache[id] = -1
            // 诅咒覆盖层：独立于房型/生命周期，仅“已揭示且 IsAreaCursed”显示
            set f = CreateTexFrame("GridCursed" + I2S(id), Root, TEX_CURSED, CellW, CellH)
            if f != 0 then
                call DzFrameSetPoint(f, 0, Root, 0, CellLeft(col), -CellTop(row))
                call DzFrameShow(f, false)
            endif
            set CursedFrame[id] = f
            set CursedCache[id] = -1
        endif
        set i = i + 1
    endloop
    call Diag("cells" + I2S(cellCount))

    // 道路（v1.6：节点之后再建，z 在节点之上、徽记之下；每真实边 1 帧）
    set RoadCount = 0
    set i = 0
    loop
        exitwhen i >= cellCount
        set id = Grid_GetCellByIndex(i)
        set row = Grid_GetRow(id)
        set col = Grid_GetCol(id)
        set dir = 0
        loop
            exitwhen dir >= 4
            set n = Grid_GetNeighbor(id, dir)
            if n >= 0 and (dir == DIR_RIGHT or dir == DIR_DOWN) then
                if dir == DIR_RIGHT then
                    set f = CreateTexFrame("GridRoad" + I2S(RoadCount), Root, TEX_ROAD_H, (GAP_X + 0.00727), 8.0 / 946.6667)
                    set cx = CellLeft(col) + CellW + GAP_X / 2.0
                    set cy = CellTop(row) + CellH / 2.0
                else
                    set f = CreateTexFrame("GridRoad" + I2S(RoadCount), Root, TEX_ROAD_V, 8.0 * 0.8 / 1100.0, (GAP_Y + 0.01056))
                    set cx = CellLeft(col) + CellW / 2.0
                    set cy = CellTop(row) + CellH + GAP_Y / 2.0
                endif
                if f != 0 then
                    call DzFrameSetPoint(f, 4, Root, 4, cx - ROOT_W / 2.0, ROOT_H / 2.0 - cy)
                    set RoadFrame[RoadCount] = f
                    set RoadCount = RoadCount + 1
                endif
            endif
            set dir = dir + 1
        endloop
        set i = i + 1
    endloop
    call Diag("roads" + I2S(RoadCount))

    // 稀疏缺格地形 glyph（包围盒内不存在的 cell）
    set TerrainCount = 0
    set row = 0
    loop
        exitwhen row >= boundRows
        set col = 0
        loop
            exitwhen col >= boundCols
            if Grid_GetIdIfPresent(row, col) < 0 then
                if GetRandomInt(0, 2) == 0 then
                    set f = CreateTexFrame("GridTerrain" + I2S(TerrainCount), Root, TEX_TERRAIN_MOUNTAIN, CellW, CellH)
                elseif GetRandomInt(0, 1) == 0 then
                    set f = CreateTexFrame("GridTerrain" + I2S(TerrainCount), Root, TEX_TERRAIN_TREE, CellW, CellH)
                else
                    set f = CreateTexFrame("GridTerrain" + I2S(TerrainCount), Root, TEX_TERRAIN_WATER, CellW, CellH)
                endif
                if f != 0 then
                    call DzFrameSetPoint(f, 0, Root, 0, CellLeft(col), -CellTop(row))
                    set TerrainFrame[TerrainCount] = f
                    set TerrainCount = TerrainCount + 1
                endif
            endif
            set col = col + 1
        endloop
        set row = row + 1
    endloop
    call Diag("terrain" + I2S(TerrainCount))

    // 当前位置：红环 + 蜡封
    set CurRing = CreateTexFrame("GridCurRing", Root, TEX_CUR_RING, CellW + 0.004364, CellH + 0.006338)
    if CurRing != 0 then
        call DzFrameShow(CurRing, false)
    endif
    set Wax = CreateTexFrame("GridWax", Root, TEX_WAX, WAX_W, WAX_H)
    if Wax != 0 then
        call DzFrameShow(Wax, false)
    endif
    set GoldSeal = CreateTexFrame("GridGold", Root, TEX_GOLD, GOLD_W, GOLD_H)
    if GoldSeal != 0 then
        call DzFrameShow(GoldSeal, false)
    endif

    // 队友标记（最多 3 个）
    set i = 0
    loop
        exitwhen i >= 3
        set f = CreateTexFrame("GridTeamMark" + I2S(i), Root, TEX_BLANK, TEAM_W, TEAM_H)
        if f != 0 then
            call DzFrameShow(f, false)
        endif
        set TeamMark[i] = f
        set TeamTypeCache[i] = 0
        set TeamAreaCache[i] = -1
        set i = i + 1
    endloop
    call Diag("current")

    // 悬停金环 + 每格透明按钮（只为存在格建按钮）
    set HoverRing = CreateTexFrame("GridHover", Root, TEX_HOVER_RING, CellW + 0.004364, CellH + 0.006338)
    if HoverRing != 0 then
        call DzFrameShow(HoverRing, false)
    endif
    set i = 0
    loop
        exitwhen i >= cellCount
        set id = Grid_GetCellByIndex(i)
        set row = Grid_GetRow(id)
        set col = Grid_GetCol(id)
        set f = DzCreateFrameByTagName("GLUEBUTTON", "GridHoverBtn" + I2S(id), Root, "template", 0)
        if f != 0 then
            call DzFrameSetTexture(f, TEX_BLANK, 0)
            call DzFrameSetAlpha(f, 1)
            call DzFrameSetSize(f, CellW, CellH)
            call DzFrameSetPoint(f, 0, Root, 0, CellLeft(col), -CellTop(row))
            call DzFrameShow(f, false)
            call DzFrameSetScriptByCode(f, 2, function OnCellEnter, false)
            call DzFrameSetScriptByCode(f, 3, function OnCellLeave, false)
        endif
        set HoverBtn[id] = f
        set i = i + 1
    endloop
    call Diag("buttons")

    // 信息卡
    set InfoCard = CreateTexFrame("GridInfoCard", Root, TEX_CARD_INFO, INFO_W, INFO_H)
    if InfoCard != 0 then
        call DzFrameSetPoint(InfoCard, 0, Root, 0, RIGHT_X, -INFO_Y)
    endif
    set InfoTitle = CreateTextFrame("GridInfoTitle", Root, "房间信息", 0.14, 0.026, FS_INFO_TITLE, COLOR_MUTED)
    if InfoTitle != 0 then
        call DzFrameSetPoint(InfoTitle, 0, Root, 0, INFO_TEXT_X, -INFO_Y_TITLE)
    endif
    set i = 0
    loop
        exitwhen i >= 3
        if i == 0 then
            set f = CreateTextFrame("GridInfoL0", Root, "", 0.144, 0.030, FS_INFO_L0, COLOR_DARK)
            set py = INFO_Y_L0
        elseif i == 1 then
            set f = CreateTextFrame("GridInfoL1", Root, "", 0.144, 0.026, FS_INFO_L12, COLOR_L2)
            set py = INFO_Y_L1
        else
            set f = CreateTextFrame("GridInfoL2", Root, "", 0.144, 0.026, FS_INFO_L12, COLOR_L2)
            set py = INFO_Y_L2
        endif
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, INFO_TEXT_X, -py)
            call DzFrameShow(f, false)
        endif
        set InfoLine[i] = f
        set i = i + 1
    endloop
    set i = 0
    loop
        exitwhen i >= 2
        if i == 0 then
            set f = CreateTextFrame("GridInfoD0", Root, "将鼠标移到房间上", 0.144, 0.026, FS_INFO_L12, COLOR_L2)
            set py = INFO_Y_DEF0
        else
            set f = CreateTextFrame("GridInfoD1", Root, "查看该房已知信息", 0.144, 0.026, FS_INFO_L12, COLOR_L2)
            set py = INFO_Y_DEF1
        endif
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, INFO_TEXT_X, -py)
            call DzFrameShow(f, false)
        endif
        set InfoDef[i] = f
        set i = i + 1
    endloop

    // 图例（纸上直接绘制：2×3 + 状态行）
    set LegendTitle = CreateTextFrame("GridLegendTitle", Root, "图例", 0.10, 0.026, FS_LEGEND_TITLE, COLOR_DARK)
    if LegendTitle != 0 then
        call DzFrameSetPoint(LegendTitle, 0, Root, 0, RIGHT_X, -LEGEND_TITLE_Y)
    endif
    set i = 0
    loop
        exitwhen i >= 6
        set colIdx = i - (i / 2) * 2
        set rowIdx = i / 2
        if colIdx == 0 then
            set px = RIGHT_X
            if rowIdx == 0 then
                set n = 0
            elseif rowIdx == 1 then
                set n = 3
            else
                set n = 2
            endif
        else
            set px = RIGHT_X + LEGEND_COL_W
            if rowIdx == 0 then
                set n = 1
            elseif rowIdx == 1 then
                set n = 4
            else
                set n = 5
            endif
        endif
        set py = LEGEND_ROW_Y + I2R(rowIdx) * LEGEND_ROW_H
        // 可读性：图例项加迷你格底（与地图上真实格子一致），避免“字/图标与纸底色接近”
        set f = CreateTexFrame("GridLegendChip" + I2S(i), Root, TEX_CELL_PLAIN, 0.018909, 0.025345)
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px - 0.001455, -py)
        endif
        set LegendChip[i] = f
        set f = CreateTexFrame("GridLegendEm" + I2S(i), Root, EmTex(n), LEGEND_EM_W, LEGEND_EM_H)
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px, -py)
        endif
        set LegendEm[i] = f
        set f = CreateTextFrame("GridLegendName" + I2S(i), Root, RoomTypeName(n), 0.06, 0.024, FS_LEGEND, COLOR_DARK)
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px + 0.020364, -py)
        endif
        set LegendName[i] = f
        set i = i + 1
    endloop
    // 状态行：未探索 / 已清 / 未领取（x 偏移 0/82/164px）
    set i = 0
    loop
        exitwhen i >= 3
        if i == 0 then
            set px = RIGHT_X
            set f = CreateTexFrame("GridStatusChip0", Root, TEX_CELL_UNEXPLORED, 0.016000, 0.021127)
        elseif i == 1 then
            set px = RIGHT_X + 0.050909
            set f = CreateTexFrame("GridStatusChip1", Root, TEX_CELL_PLAIN, 0.016000, 0.021127)
        else
            set px = RIGHT_X + 0.101818
            set f = CreateTexFrame("GridStatusChip2", Root, TEX_CELL_PLAIN, 0.016000, 0.021127)
        endif
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px - 0.001455, -LEGEND_STATUS_Y)
        endif
        set StatusChip[i] = f
        if i == 0 then
            set f = CreateTexFrame("GridStatusEm0", Root, TEX_EM_UNKNOWN, STATUS_EM_W, STATUS_EM_H)
            set emTex = "未探"
        elseif i == 1 then
            set f = CreateTexFrame("GridStatusEm1", Root, TEX_EM_CHECK, STATUS_EM_W, STATUS_EM_H)
            set emTex = "已清"
        else
            set f = CreateTexFrame("GridStatusEm2", Root, TEX_GOLD, STATUS_EM_W, STATUS_EM_H)
            set emTex = "未领"
        endif
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px, -LEGEND_STATUS_Y)
        endif
        set StatusEm[i] = f
        set f = CreateTextFrame("GridStatusTx" + I2S(i), Root, emTex, 0.05, 0.024, FS_STATUS, COLOR_DARK)
        if f != 0 then
            call DzFrameSetPoint(f, 0, Root, 0, px + 0.017455, -LEGEND_STATUS_Y)
        endif
        set StatusText[i] = f
        set i = i + 1
    endloop

    call Diag("side")
    set uiReady = true
    set uiCreating = false
    set LastChapterId = ChapterManager_GetCurrentChapter()
    call UpdateTitle(LastChapterId)
    call ShowInfoDefault()
    call DebugLogger_Log(LOG_INFO, "[gridmap] B ingame UI ready: roads=" + I2S(RoadCount) + " terrain=" + I2S(TerrainCount))
    call LogRects()
endfunction

private function ApplyVisible takes boolean vis returns nothing
    local integer i = 0
    local integer id
    if not uiReady then
        return
    endif
    set uiVisible = vis
    call DzFrameShow(Root, vis)
    if TitleText != 0 then
        call DzFrameShow(TitleText, vis)
    endif
    if CloseText != 0 then
        call DzFrameShow(CloseText, vis)
    endif
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if CellFrame[id] != 0 then
            call DzFrameShow(CellFrame[id], vis)
        endif
        if CursedFrame[id] != 0 then
            call DzFrameShow(CursedFrame[id], vis and CursedCache[id] == 1)
        endif
        if HoverBtn[id] != 0 then
            call DzFrameShow(HoverBtn[id], vis)
        endif
        set i = i + 1
    endloop
    set i = 0
    loop
        exitwhen i >= RoadCount
        call DzFrameShow(RoadFrame[i], vis)
        set i = i + 1
    endloop
    set i = 0
    loop
        exitwhen i >= TerrainCount
        call DzFrameShow(TerrainFrame[i], vis)
        set i = i + 1
    endloop
    if InfoCard != 0 then
        call DzFrameShow(InfoCard, vis)
    endif
    if InfoTitle != 0 then
        call DzFrameShow(InfoTitle, vis)
    endif
    if LegendTitle != 0 then
        call DzFrameShow(LegendTitle, vis)
    endif
    set i = 0
    loop
        exitwhen i >= 6
        if LegendChip[i] != 0 then
            call DzFrameShow(LegendChip[i], vis)
        endif
        if LegendEm[i] != 0 then
            call DzFrameShow(LegendEm[i], vis)
        endif
        if LegendName[i] != 0 then
            call DzFrameShow(LegendName[i], vis)
        endif
        set i = i + 1
    endloop
    set i = 0
    loop
        exitwhen i >= 3
        if StatusChip[i] != 0 then
            call DzFrameShow(StatusChip[i], vis)
        endif
        if StatusEm[i] != 0 then
            call DzFrameShow(StatusEm[i], vis)
        endif
        if StatusText[i] != 0 then
            call DzFrameShow(StatusText[i], vis)
        endif
        set i = i + 1
    endloop
    if not vis then
        if CurRing != 0 then
            call DzFrameShow(CurRing, false)
        endif
        if Wax != 0 then
            call DzFrameShow(Wax, false)
        endif
        if GoldSeal != 0 then
            call DzFrameShow(GoldSeal, false)
        endif
        if HoverRing != 0 then
            call DzFrameShow(HoverRing, false)
        endif
        set i = 0
        loop
            exitwhen i >= 3
            if TeamMark[i] != 0 then
                call DzFrameShow(TeamMark[i], false)
            endif
            if InfoLine[i] != 0 then
                call DzFrameShow(InfoLine[i], false)
            endif
            set i = i + 1
        endloop
        if InfoDef[0] != 0 then
            call DzFrameShow(InfoDef[0], false)
        endif
        if InfoDef[1] != 0 then
            call DzFrameShow(InfoDef[1], false)
        endif
        set CurCell = -1
        set GoldCell = -1
        set HoverCell = -1
        set i = 0
        loop
            exitwhen i >= 3
            set TeamAreaCache[i] = -1
            set i = i + 1
        endloop
        set i = 0
        loop
            exitwhen i >= Grid_GetMaxId()
            set CellTexCache[i] = -1
            set i = i + 1
        endloop
    else
        call ShowInfoDefault()
    endif
endfunction

// 切章重建：销毁旧 Root（含全部子帧），按当前章节 cell/边/地形重新建 UI
private function RebuildUi takes nothing returns nothing
    local boolean wasVisible = uiVisible
    if Root != 0 then
        call DzFrameShow(Root, false)
        call DzDestroyFrame(Root)
        set Root = 0
    endif
    set uiReady = false
    set uiCreating = false
    set uiVisible = false
    set CurCell = -1
    set GoldCell = -1
    set HoverCell = -1
    set RoadCount = 0
    set TerrainCount = 0
    call CreateUi()
    if uiReady then
        // 切章前面板是打开的就保持打开（默认 false 时仍是关闭）
        call ApplyVisible(wasVisible)
        call Diag("rebuild")
    endif
endfunction

private function RefreshUi takes nothing returns nothing
    local integer i
    local integer pid
    local integer chapter
    local integer currentId = -1
    local integer goldId = -1
    local integer roomType
    local integer state
    local integer tex
    local rect pr
    local string s
    local integer p
    local integer teamIdx
    local integer f
    local integer e
    local integer r
    local integer id

    if not uiReady then
        return
    endif
    if Grid_GetRows() <= 0 then
        return
    endif
    set pid = GetConvertedPlayerId(GetLocalPlayer())
    set chapter = ChapterManager_GetCurrentChapter()
    if LastChapterId >= 0 and chapter != LastChapterId then
        call RebuildUi()
        return
    endif
    set pr = GetPlayerCurrentAreaRect(GetLocalPlayer())
    if pr != null then
        set currentId = GetAreaIdByRect(pr)
    endif
    call UpdateTitle(chapter)

    // 格贴图（B11：存在格列表）
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if CellFrame[id] != 0 then
            if not Reveal_IsRevealed(id) then
                set tex = 1
            else
                set roomType = GetRoomType(id)
                set state = GetRoomState(id)
                if roomType < 0 or roomType > 5 then
                    set tex = 2
                elseif state == 2 then
                    set tex = 200 + roomType
                else
                    set tex = 100 + roomType
                endif
            endif
            if CellTexCache[id] != tex then
                set CellTexCache[id] = tex
                if tex == 1 then
                    call DzFrameSetTexture(CellFrame[id], TEX_CELL_UNEXPLORED, 0)
                elseif tex == 2 then
                    call DzFrameSetTexture(CellFrame[id], TEX_CELL_UNKNOWN, 0)
                elseif tex >= 200 then
                    call DzFrameSetTexture(CellFrame[id], CellTex(tex - 200, true), 0)
                else
                    call DzFrameSetTexture(CellFrame[id], CellTex(tex - 100, false), 0)
                endif
            endif
            // 诅咒覆盖层（只对已揭示房间；变化驱动）
            if CursedFrame[id] != 0 then
                if Reveal_IsRevealed(id) and AreaIsCursed(id) then
                    if CursedCache[id] != 1 then
                        set CursedCache[id] = 1
                        call DzFrameShow(CursedFrame[id], true)
                    endif
                else
                    if CursedCache[id] != 0 then
                        set CursedCache[id] = 0
                        call DzFrameShow(CursedFrame[id], false)
                    endif
                endif
            endif
        endif
        set i = i + 1
    endloop

    // 当前位置（红环 + 蜡封）
    if currentId != CurCell then
        set CurCell = currentId
        if currentId < 0 then
            call DzFrameShow(CurRing, false)
            call DzFrameShow(Wax, false)
        else
            set r = Grid_GetRow(currentId)
            set e = Grid_GetCol(currentId)
            call DzFrameClearAllPoints(CurRing)
            call DzFrameSetPoint(CurRing, 4, Root, 4, CellCenterX(e) - ROOT_W / 2.0, ROOT_H / 2.0 - CellCenterY(r))
            call DzFrameSetSize(CurRing, CellW + 0.004364, CellH + 0.006338)
            call DzFrameShow(CurRing, true)
            call DzFrameClearAllPoints(Wax)
            call DzFrameSetPoint(Wax, 0, Root, 0, CellLeft(e) + CellW - 0.008, -(CellTop(r) - 0.011617))
            call DzFrameSetSize(Wax, WAX_W, WAX_H)
            call DzFrameShow(Wax, true)
            if HoverCell < 0 then
                call ShowInfoDefault()
            endif
        endif
    endif

    // 未领取金印（B11：存在格列表）
    set i = 0
    loop
        exitwhen i >= Grid_GetTotal()
        set id = Grid_GetCellByIndex(i)
        if goldId < 0 then
            if RewardAltar_HasAltar(id) and not RewardItem_IsPlayerClaimed(id, pid) then
                set goldId = id
            endif
        endif
        set i = i + 1
    endloop
    if goldId != GoldCell then
        set GoldCell = goldId
        if goldId < 0 then
            call DzFrameShow(GoldSeal, false)
        else
            set r = Grid_GetRow(goldId)
            set e = Grid_GetCol(goldId)
            call DzFrameClearAllPoints(GoldSeal)
            call DzFrameSetPoint(GoldSeal, 0, Root, 0, CellLeft(e) + CellW - GOLD_W - 0.002909, -(CellTop(r) + CellH - GOLD_H - 0.004225))
            call DzFrameSetSize(GoldSeal, GOLD_W, GOLD_H)
            call DzFrameShow(GoldSeal, true)
        endif
    endif

    // 队友头像标记（只画在地图上，不写文字列表）
    set p = 1
    set teamIdx = 0
    loop
        exitwhen p > 4
        if p != pid and udg_Hero[p] != null then
            set s = HeroIcon(p)
            set i = AreaOfUnit(udg_Hero[p])
            if i >= 0 then
                if teamIdx < 3 then
                    set f = TeamMark[teamIdx]
                    if f != 0 then
                        if TeamTypeCache[teamIdx] != GetUnitTypeId(udg_Hero[p]) then
                            set TeamTypeCache[teamIdx] = GetUnitTypeId(udg_Hero[p])
                            call DzFrameSetTexture(f, s, 0)
                        endif
                        if TeamAreaCache[teamIdx] != i then
                            set TeamAreaCache[teamIdx] = i
                            set e = Grid_GetCol(i)
                            set r = Grid_GetRow(i)
                            call DzFrameClearAllPoints(f)
                            call DzFrameSetPoint(f, 0, Root, 0, CellLeft(e) + CellW - 0.011636, -(CellTop(r) + 0.008453))
                        endif
                        call DzFrameShow(f, true)
                    endif
                    set teamIdx = teamIdx + 1
                endif
            endif
        endif
        set p = p + 1
    endloop
    loop
        exitwhen teamIdx >= 3
        if TeamMark[teamIdx] != 0 then
            call DzFrameShow(TeamMark[teamIdx], false)
        endif
        set teamIdx = teamIdx + 1
    endloop

    // 悬停态刷新
    if HoverCell >= 0 then
        call RefreshHover(HoverCell)
    endif
endfunction

private function OnRefreshTick takes nothing returns nothing
    if uiVisible then
        call RefreshUi()
    endif
endfunction

private function OnInitTick takes nothing returns nothing
    if uiReady or uiCreating then
        call DestroyTimer(initTimer)
        set initTimer = null
        return
    endif
    if Grid_GetRows() > 0 then
        call CreateUi()
        if uiReady then
            call ApplyVisible(false)
            call DestroyTimer(initTimer)
            set initTimer = null
        endif
    else
        set initAttempts = initAttempts + 1
        if initAttempts >= INIT_MAX_ATTEMPTS then
            call Diag("defer")
            call DestroyTimer(initTimer)
            set initTimer = null
        endif
    endif
endfunction

private function OnToggleKeyDown takes nothing returns nothing
    if DzGetTriggerKeyPlayer() != GetLocalPlayer() then
        return
    endif
    if keyHeld then
        return
    endif
    set keyHeld = true
    if uiReady then
        if uiVisible then
            call ApplyVisible(false)
        else
            call ApplyVisible(true)
        endif
    endif
endfunction

private function OnToggleKeyUp takes nothing returns nothing
    if DzGetTriggerKeyPlayer() != GetLocalPlayer() then
        return
    endif
    set keyHeld = false
endfunction

private function InitGridMap takes nothing returns nothing
    local trigger tDown = CreateTrigger()
    local trigger tUp = CreateTrigger()
    call TriggerAddAction(tDown, function OnToggleKeyDown)
    call TriggerAddAction(tUp, function OnToggleKeyUp)
    call DzTriggerRegisterKeyEventTrg(tDown, KEY_EVENT_DOWN, KEY_TOGGLE)
    call DzTriggerRegisterKeyEventTrg(tUp, KEY_EVENT_UP, KEY_TOGGLE)
    set initTimer = CreateTimer()
    call TimerStart(initTimer, INIT_RETRY_INTERVAL, true, function OnInitTick)
    set refreshTimer = CreateTimer()
    call TimerStart(refreshTimer, REFRESH_INTERVAL, true, function OnRefreshTick)
endfunction

public function Toggle takes nothing returns nothing
    if not uiReady then
        return
    endif
    if uiVisible then
        call ApplyVisible(false)
    else
        call ApplyVisible(true)
    endif
endfunction

public function Show takes nothing returns nothing
    if uiReady then
        call ApplyVisible(true)
    endif
endfunction

public function Hide takes nothing returns nothing
    if uiReady then
        call ApplyVisible(false)
    endif
endfunction

public function IsVisible takes nothing returns boolean
    return uiVisible
endfunction

public function IsReady takes nothing returns boolean
    return uiReady
endfunction

public function GetDiag takes nothing returns string
    local integer ready = 0
    local integer creating = 0
    if uiReady then
        set ready = 1
    endif
    if uiCreating then
        set creating = 1
    endif
    return diag + "|att=" + I2S(initAttempts) + "|ready=" + I2S(ready) + "|creating=" + I2S(creating)
endfunction

endlibrary
#endif
