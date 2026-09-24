#ifndef UI_PICK_INCLUDED
#define UI_PICK_INCLUDED
#include "nncou\\BlizzardAPI.j"
/*
    多选1 UI框架

    可复用的选择界面，按玩家分组预创建，避免多玩家同时操作冲突。
    每个玩家预创建独立的UI实例，选项数量由调用方动态指定（1-5）。

    使用方式：
    1. 游戏初始化时调用 InitUiPick() 预创建所有玩家的UI
    2. 调用 UiPick_SetChooseTrigger 注册选择回调
    3. 需要时调用 UiPick_Show 弹出界面
    4. 玩家点击后回调触发器触发，通过 GetChoiceIndex/GetChoicePlayer 获取选择

    依赖：BzAPI（Frame API）
*/
library UiPick initializer InitUiPick

globals
    private hashtable UiPickTable = InitHashtable()
    private constant integer MAX_CHOICES = 5
    private constant integer MAX_PLAYERS = 12
    // 每个玩家（parent key = playerId）
    private constant integer HT_UI_FRAME = 0
    private constant integer HT_UI_CHOICE_FRAME = 1
    private constant integer HT_UI_CHOICE_ICON = 10
    private constant integer HT_UI_CHOICE_NAME = 20
    private constant integer HT_UI_CHOICE_DESC = 30
    private constant integer HT_UI_CHOICE_BTN = 40
    private constant integer HT_UI_VISIBLE = 50
    private constant integer HT_UI_ACTIVE_COUNT = 51
    private constant integer HT_UI_TITLE = 52
    // 全局（parent key = 0）
    private constant integer HT_CHOOSE_TRIGGER = 60
    private constant integer HT_CHOOSE_INDEX = 61
    private constant integer HT_CHOOSE_PLAYER = 62
    // UI尺寸常量
    private constant real PANEL_WIDTH = 0.50
    private constant real PANEL_HEIGHT = 0.22
    private constant real CHOICE_WIDTH = 0.09
    private constant real CHOICE_HEIGHT = 0.18
    private constant real CHOICE_GAP = 0.01
    private constant real ICON_SIZE = 0.05
    private constant real BTN_HEIGHT = 0.02
    private constant real TITLE_HEIGHT = 0.02
endglobals

// ===== 公开接口：隐藏（前置于点击处理，供其调用）=====

/*
    [UiPick_Hide]
    title = "隐藏多选1界面"
    description = "隐藏${玩家ID}的界面"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function Hide takes integer pid returns nothing
    local integer mainFrame = LoadInteger(UiPickTable, pid, HT_UI_FRAME)
    call DzFrameShow(mainFrame, false)
    call SaveBoolean(UiPickTable, pid, HT_UI_VISIBLE, false)
endfunction

// ===== 内部：点击事件处理 =====
// 注意：作为 code 回调传给 DzFrameSetScriptByCode，必须在 CreatePlayerUi 之前声明

private function Trig_UiChoiceClick takes nothing returns nothing
    local integer clickedFrame = DzGetTriggerUIEventFrame()
    local integer choiceIndex = LoadInteger(UiPickTable, clickedFrame, 0)
    local integer pid = LoadInteger(UiPickTable, clickedFrame, 1)
    local trigger chooseTrig = LoadTriggerHandle(UiPickTable, 0, HT_CHOOSE_TRIGGER)
    // 保存选择上下文
    call SaveInteger(UiPickTable, 0, HT_CHOOSE_INDEX, choiceIndex)
    call SaveInteger(UiPickTable, 0, HT_CHOOSE_PLAYER, pid)
    // 隐藏UI
    call Hide(pid)
    // 执行回调
    if chooseTrig != null then
        call TriggerExecute(chooseTrig)
    endif
    set chooseTrig = null
endfunction

// ===== 内部：创建单个玩家的UI =====

private function CreatePlayerUi takes integer pid returns nothing
    local integer gameUI = DzGetGameUI()
    local integer mainFrame
    local integer titleFrame
    local integer choiceFrame
    local integer iconFrame
    local integer nameFrame
    local integer descFrame
    local integer btnFrame
    local integer i = 0
    local real startX
    local real centerX = 0.40
    local real centerY = 0.30
    // 创建主面板
    set mainFrame = DzCreateFrameByTagName("BACKDROP", "UiPick"+I2S(pid), gameUI, "template", 0)
    call DzFrameSetSize(mainFrame, PANEL_WIDTH, PANEL_HEIGHT)
    call DzFrameSetAbsolutePoint(mainFrame, 0, centerX - PANEL_WIDTH / 2.0, centerY + PANEL_HEIGHT / 2.0)
    call DzFrameSetAlpha(mainFrame, 200)
    call DzFrameShow(mainFrame, false)
    call SaveInteger(UiPickTable, pid, HT_UI_FRAME, mainFrame)
    // 创建标题
    set titleFrame = DzCreateFrameByTagName("TEXT", "UiPickTitle"+I2S(pid), mainFrame, "template", 0)
    call DzFrameSetPoint(titleFrame, 0, mainFrame, 0, 0.0, 0.0)
    call DzFrameSetSize(titleFrame, PANEL_WIDTH, TITLE_HEIGHT)
    call DzFrameSetText(titleFrame, "选择奖励")
    call DzFrameSetFont(titleFrame, "Fonts\\FRIZQT__.TTF", 0.014, 0)
    call DzFrameSetTextAlignment(titleFrame, 1)
    call SaveInteger(UiPickTable, pid, HT_UI_TITLE, titleFrame)
    // 创建各选项卡位
    loop
        exitwhen i >= MAX_CHOICES
        // 选项容器
        set choiceFrame = DzCreateFrameByTagName("BACKDROP", "UiPickC"+I2S(pid)+"_"+I2S(i), mainFrame, "template", 0)
        call DzFrameSetSize(choiceFrame, CHOICE_WIDTH, CHOICE_HEIGHT)
        call DzFrameShow(choiceFrame, false)
        call SaveInteger(UiPickTable, pid, HT_UI_CHOICE_FRAME + i, choiceFrame)
        // 图标
        set iconFrame = DzCreateFrameByTagName("BACKDROP", "UiPickI"+I2S(pid)+"_"+I2S(i), choiceFrame, "template", 0)
        call DzFrameSetSize(iconFrame, ICON_SIZE, ICON_SIZE)
        call DzFrameSetPoint(iconFrame, 0, choiceFrame, 0, (CHOICE_WIDTH - ICON_SIZE) / 2.0, -TITLE_HEIGHT - 0.005)
        call SaveInteger(UiPickTable, pid, HT_UI_CHOICE_ICON + i, iconFrame)
        // 名称
        set nameFrame = DzCreateFrameByTagName("TEXT", "UiPickN"+I2S(pid)+"_"+I2S(i), choiceFrame, "template", 0)
        call DzFrameSetSize(nameFrame, CHOICE_WIDTH, 0.015)
        call DzFrameSetPoint(nameFrame, 0, iconFrame, 2, 0.0, -0.003)
        call DzFrameSetFont(nameFrame, "Fonts\\FRIZQT__.TTF", 0.011, 0)
        call DzFrameSetTextAlignment(nameFrame, 1)
        call SaveInteger(UiPickTable, pid, HT_UI_CHOICE_NAME + i, nameFrame)
        // 描述
        set descFrame = DzCreateFrameByTagName("TEXT", "UiPickD"+I2S(pid)+"_"+I2S(i), choiceFrame, "template", 0)
        call DzFrameSetSize(descFrame, CHOICE_WIDTH, 0.04)
        call DzFrameSetPoint(descFrame, 0, nameFrame, 2, 0.0, -0.003)
        call DzFrameSetFont(descFrame, "Fonts\\FRIZQT__.TTF", 0.009, 0)
        call DzFrameSetTextAlignment(descFrame, 1)
        call SaveInteger(UiPickTable, pid, HT_UI_CHOICE_DESC + i, descFrame)
        // 选择按钮
        set btnFrame = DzCreateFrameByTagName("GLUETEXTBUTTON", "UiPickB"+I2S(pid)+"_"+I2S(i), choiceFrame, "template", 0)
        call DzFrameSetSize(btnFrame, CHOICE_WIDTH * 0.7, BTN_HEIGHT)
        call DzFrameSetPoint(btnFrame, 0, descFrame, 2, (CHOICE_WIDTH * 0.3) / 2.0, -0.005)
        call DzFrameSetText(btnFrame, "选择")
        call DzFrameSetFont(btnFrame, "Fonts\\FRIZQT__.TTF", 0.010, 0)
        call DzFrameSetScriptByCode(btnFrame, 1, function Trig_UiChoiceClick, false)
        // 保存按钮索引映射（按钮frame → index）
        call SaveInteger(UiPickTable, btnFrame, 0, i)
        call SaveInteger(UiPickTable, btnFrame, 1, pid)
        call SaveInteger(UiPickTable, pid, HT_UI_CHOICE_BTN + i, btnFrame)
        set i = i + 1
    endloop
endfunction

// ===== 内部：更新选项位置 =====

private function LayoutChoices takes integer pid, integer count returns nothing
    local integer mainFrame = LoadInteger(UiPickTable, pid, HT_UI_FRAME)
    local integer choiceFrame
    local real totalWidth = I2R(count) * CHOICE_WIDTH + I2R(count - 1) * CHOICE_GAP
    local real startX = (PANEL_WIDTH - totalWidth) / 2.0
    local integer i = 0
    loop
        exitwhen i >= MAX_CHOICES
        set choiceFrame = LoadInteger(UiPickTable, pid, HT_UI_CHOICE_FRAME + i)
        if i < count then
            call DzFrameClearAllPoints(choiceFrame)
            call DzFrameSetPoint(choiceFrame, 0, mainFrame, 0, startX + I2R(i) * (CHOICE_WIDTH + CHOICE_GAP), -TITLE_HEIGHT - 0.005)
            call DzFrameShow(choiceFrame, true)
        else
            call DzFrameShow(choiceFrame, false)
        endif
        set i = i + 1
    endloop
endfunction

// ===== 公开接口 =====

/*
    [UiPick_SetChooseTrigger]
    title = "设置选择回调触发器"
    description = "设置玩家选择物品后的${回调触发器}"
    category = TC_FRO
    [[.args]]
    type = trigger
*/
public function SetChooseTrigger takes trigger t returns nothing
    call SaveTriggerHandle(UiPickTable, 0, HT_CHOOSE_TRIGGER, t)
endfunction

/*
    [UiPick_Show]
    title = "显示多选1界面"
    description = "为${玩家ID}显示${数量}个选项的界面"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function Show takes integer pid, integer count returns nothing
    local integer mainFrame = LoadInteger(UiPickTable, pid, HT_UI_FRAME)
    if count < 1 then
        set count = 1
    endif
    if count > MAX_CHOICES then
        set count = MAX_CHOICES
    endif
    call SaveInteger(UiPickTable, pid, HT_UI_ACTIVE_COUNT, count)
    call LayoutChoices(pid, count)
    call DzFrameShow(mainFrame, true)
    call SaveBoolean(UiPickTable, pid, HT_UI_VISIBLE, true)
endfunction

/*
    [UiPick_SetChoiceContent]
    title = "设置选项内容"
    description = "设置${玩家ID}的第${索引}个选项的图标、名称和描述"
    category = TC_FRO
    [[.args]]
    type = integer
    [[.args]]
    type = integer
    [[.args]]
    type = string
    [[.args]]
    type = string
    [[.args]]
    type = string
*/
public function SetChoiceContent takes integer pid, integer index, string icon, string name, string desc returns nothing
    local integer iconFrame = LoadInteger(UiPickTable, pid, HT_UI_CHOICE_ICON + index)
    local integer nameFrame = LoadInteger(UiPickTable, pid, HT_UI_CHOICE_NAME + index)
    local integer descFrame = LoadInteger(UiPickTable, pid, HT_UI_CHOICE_DESC + index)
    if iconFrame != 0 then
        call DzFrameSetTexture(iconFrame, icon, 0)
    endif
    if nameFrame != 0 then
        call DzFrameSetText(nameFrame, name)
    endif
    if descFrame != 0 then
        call DzFrameSetText(descFrame, desc)
    endif
endfunction

/*
    [UiPick_GetChoiceIndex]
    title = "获取选择索引"
    description = "在回调触发器内调用，获取玩家点击了第几个选项（0-based）"
    category = TC_FRO
    returns = integer
*/
public function GetChoiceIndex takes nothing returns integer
    return LoadInteger(UiPickTable, 0, HT_CHOOSE_INDEX)
endfunction

/*
    [UiPick_GetChoicePlayer]
    title = "获取选择玩家"
    description = "在回调触发器内调用，获取是哪个玩家做的选择"
    category = TC_FRO
    returns = integer
*/
public function GetChoicePlayer takes nothing returns integer
    return LoadInteger(UiPickTable, 0, HT_CHOOSE_PLAYER)
endfunction

/*
    [UiPick_IsVisible]
    title = "界面是否可见"
    description = "判断${玩家ID}的界面是否可见"
    category = TC_FRO
    returns = boolean
    [[.args]]
    type = integer
*/
public function IsVisible takes integer pid returns boolean
    return LoadBoolean(UiPickTable, pid, HT_UI_VISIBLE)
endfunction

// ===== 初始化 =====

private function InitUiPick takes nothing returns nothing
    local integer i = 0
    loop
        exitwhen i >= MAX_PLAYERS
        call CreatePlayerUi(i)
        set i = i + 1
    endloop
endfunction

endlibrary
#endif
