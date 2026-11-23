#ifndef MAGIC_TEST_FRAMEWORK_INCLUDED
#define MAGIC_TEST_FRAMEWORK_INCLUDED
/*
    [testFramework] 回归测试框架（只被**测试版**地图引用，生产图不包含）

    用法（测试入口库）：
        library testEntry requires testFramework
            private function StepX takes nothing returns nothing
                call testFramework_ExpectInt("grid.total", Grid_GetTotal(), 49)
            endfunction
            private function Init takes nothing returns nothing
                call testFramework_AddStep(function StepX, "step-name")
            endfunction
        endlibrary

    行为：
        1) 地图初始化后 BOOT_DELAY 秒自动开始（等 Forest 关卡初始化完成）；
        2) 每 STEP_INTERVAL 秒执行一个测试步骤（顺序执行）；
        3) 断言结果 + 日志累计到报告；
        4) 全部步骤结束后通过 Preload 写报告文件，并 EndGame 结束本局；
        5) 报告路径固定为 save\war3regression.txt（游戏目录下，若不存在则回退 war3regression.txt）。

    约束：
        - 步骤函数必须同步执行（MVP）；异步等待用后续 API 扩展；
        - 只调用生产代码的只读查询接口，不修改游戏状态（后续用例例外需登记）。
*/
library testFramework initializer Init requires DebugLogger, areaGrid, areaData, areaSlot, areaMonsterRoom, ChapterManager

globals
    private constant real BOOT_DELAY = 8.0
    private constant real STEP_INTERVAL = 0.30
    private constant real WAIT_INTERVAL = 0.50
    private constant integer WAIT_TICKS_MAX = 120
    private constant integer FORCE_START_TICK = 12
    // 测试选用的英雄序号（对应 udg_HeroPicked[1..6] 与 ClickHeroPickBtn 的 index）
    private constant integer HERO_INDEX = 1
    private constant integer MAX_STEPS = 64
    private constant integer MAX_REPORT_LINES = 400
    private constant string REPORT_FILE = "save\\war3regression.txt"
    private constant boolean END_GAME_AFTER_TEST = true

    private timer stepTimer = null
    private trigger array stepTrig
    private string array stepName
    private boolean array stepWait
    private integer array stepWaitTicks
    private integer stepCount = 0
    private integer stepIndex = 0
    private integer waitLeft = 0
    private integer checkCount = 0
    private integer failCount = 0
    private integer waitTicks = 0
    private boolean pickSent = false
    private boolean chapterStarted = false
    private boolean testStarted = false
    private boolean subInclusive = true
    private string bootLog = ""
    private unit testHero = null
    private string array reportLines
    private integer reportCount = 0
    private string startupLog = ""
    private boolean finished = false
endglobals

// 游戏（章节/网格）是否已经初始化完成：测试在「地图加载完成后」才真正开始
// B11：不得写死章节规格（旧版写死 49/20/49，换章节直接超时）。
// 就绪 = 网格/槽位已建 + 每个逻辑房都已注册 + 章节已开始且入口已抽签。
private function IsGameReady takes nothing returns boolean
    local integer chapter
    if Grid_GetTotal() <= 0 then
        return false
    endif
    if Slot_GetCount() <= 0 then
        return false
    endif
    if GetAreaCount() != Grid_GetTotal() then
        return false
    endif
    set chapter = ChapterManager_GetCurrentChapter()
    if chapter < 0 then
        return false
    endif
    if GetActiveEnter(chapter) < 0 then
        return false
    endif
    return true
endfunction

// ===== 内部 =====

private function Record takes string line returns nothing
    if reportCount < MAX_REPORT_LINES then
        set reportLines[reportCount] = line
        set reportCount = reportCount + 1
    endif
endfunction

// 心跳文件：排查「卡在某一步/某线程中断」用（游戏目录 Save 下）
private function Heartbeat takes string what returns nothing
    call PreloadGenClear()
    call PreloadGenStart()
    call Preload(what)
    call PreloadGenEnd("save\\war3regression_hb.txt")
endfunction

private function BoolStr takes boolean b returns string
    if b then
        return "1"
    endif
    return "0"
endfunction

private function PassFail takes boolean ok returns string
    if ok then
        return "PASS"
    endif
    return "FAIL"
endfunction

private function Finish takes nothing returns nothing
    local integer i = 0
    local string result = "PASS"
    if finished then
        return
    endif
    set finished = true
    if stepTimer != null then
        call PauseTimer(stepTimer)
    endif
    if failCount > 0 then
        set result = "FAIL"
    endif
    call Record("SUMMARY|checks=" + I2S(checkCount) + "|fails=" + I2S(failCount) + "|result=" + result)
    call Record("END")
    call DebugLogger_Log(LOG_INFO, "[test] result=" + result + " checks=" + I2S(checkCount) + " fails=" + I2S(failCount))

    call PreloadGenClear()
    call PreloadGenStart()
    set i = 0
    loop
        exitwhen i >= reportCount
        call Preload(reportLines[i])
        set i = i + 1
    endloop
    call PreloadGenEnd(REPORT_FILE)

    if END_GAME_AFTER_TEST then
        call EndGame(true)
    endif
endfunction

private function OnTick takes nothing returns nothing
    if finished then
        return
    endif
    // 等待步骤：本次 tick 不执行用例，等 N 个 tick 后再继续
    if waitLeft > 0 then
        set waitLeft = waitLeft - 1
        return
    endif
    if stepIndex >= stepCount then
        call Finish()
        return
    endif
    call Record("STEP|" + I2S(stepIndex + 1) + "|" + stepName[stepIndex])
    if stepWait[stepIndex] then
        set waitLeft = stepWaitTicks[stepIndex] - 1
        set stepIndex = stepIndex + 1
        call Heartbeat("HB|wait-step done idx=" + I2S(stepIndex) + " left=" + I2S(waitLeft))
        if stepIndex >= stepCount and waitLeft <= 0 then
            call Finish()
        endif
        return
    endif
    // 先自增再执行：即使某个用例所在线程被字节码上限打断，下一 tick 也会继续下一个用例
    set stepIndex = stepIndex + 1
    call Heartbeat("HB|step idx=" + I2S(stepIndex - 1) + " name=" + stepName[stepIndex - 1])
    call TriggerExecute(stepTrig[stepIndex - 1])
    call Heartbeat("HB|after step idx=" + I2S(stepIndex - 1))
    if stepIndex >= stepCount then
        call Finish()
    endif
endfunction

// 模拟正常玩家流程（不跳过英雄选择）：
//   1) 「签订契约」界面点击英雄头像，实际发送同步数据 "ClickHeroPickBtn" = "玩家ID-英雄序号"；
//      地图自己的触发器会完成全部选英雄逻辑（归属/加入 udg_Heros/初始化英雄系统）。
//   2) 选完英雄后，正常流程调用 ChapterManager_ChapterEnter("Forest", udg_Heros) 进入章节
//      （作者测试用的 "Enter" 聊天指令走的也是这一句）。
// 测试框架照抄这两步，后续用例就能直接用 udg_Hero[1] 做进房/传送测试。
private function SendHeroPickSync takes nothing returns boolean
    if udg_HeroPicked[HERO_INDEX] == null then
        return false
    endif
    call Record("FORCE|simulate hero pick: player=1 index=" + I2S(HERO_INDEX) + " sync ClickHeroPickBtn")
    call DzSyncData("ClickHeroPickBtn", "1-" + I2S(HERO_INDEX))
    return true
endfunction

private function TryStartChapter takes nothing returns boolean
    if udg_Hero[1] == null then
        return false
    endif
    set testHero = udg_Hero[1]
    call Record("FORCE|hero ready: " + GetUnitName(testHero))
    call Record("FORCE|ChapterManager_ChapterEnter(\"Forest\", udg_Heros)")
    call ChapterManager_ChapterEnter("Forest", udg_Heros)
    return true
endfunction

private function CountIn takes string haystack, string needle returns integer
    local integer count = 0
    local integer pos = 0
    local integer nlen = StringLength(needle)
    local integer hlen = StringLength(haystack)
    local boolean matched
    if nlen <= 0 then
        return 0
    endif
    loop
        exitwhen pos + nlen > hlen
        if subInclusive then
            set matched = (SubString(haystack, pos, pos + nlen - 1) == needle)
        else
            set matched = (SubString(haystack, pos, pos + nlen) == needle)
        endif
        if matched then
            set count = count + 1
            set pos = pos + nlen
        else
            set pos = pos + 1
        endif
    endloop
    return count
endfunction

// 等待游戏真正开始（章节初始化完成），再进入测试步骤
private function OnWait takes nothing returns nothing
    local integer tick = waitTicks + 1
    set waitTicks = tick
    if finished or testStarted then
        return
    endif
    if tick <= 2 or (tick - (tick / 10) * 10 == 0) then
        call Heartbeat("HB|wait t=" + R2S(tick * WAIT_INTERVAL) + "|grid=" + I2S(Grid_GetTotal()) + "|slots=" + I2S(Slot_GetCount()) + "|areas=" + I2S(GetAreaCount()) + "|heroPicked=" + I2S(GetHandleId(udg_HeroPicked[HERO_INDEX])) + "|hero=" + I2S(GetHandleId(udg_Hero[1])))
    endif
    if IsGameReady() then
        set testStarted = true
        set startupLog = DebugLogger_TakeSinkBuffer()
        call Record("LOGS|startup chars=" + I2S(StringLength(startupLog)))
        call Record("SINK|" + DebugLogger_GetSinkStats() + "|buffer=" + I2S(StringLength(startupLog)))
        // 额外输出一份原始启动日志，便于排查（游戏目录 Save 下）
        call PreloadGenClear()
        call PreloadGenStart()
        call Preload(startupLog)
        call PreloadGenEnd("save\\war3regression_log.txt")
        call Record("WAIT|ready after " + R2S(tick * WAIT_INTERVAL) + "s grid=" + I2S(Grid_GetTotal()) + " slots=" + I2S(Slot_GetCount()) + " areas=" + I2S(GetAreaCount()) + " hero=" + I2S(GetHandleId(udg_Hero[1])))
        // 把镜头对准英雄，方便人工观察测试过程（只影响本地玩家，不影响逻辑）
        if testHero != null then
            call SetCameraPosition(GetUnitX(testHero), GetUnitY(testHero))
            call Record("CAM|hero=" + R2S(GetUnitX(testHero)) + "," + R2S(GetUnitY(testHero)) + "|camera=" + R2S(GetCameraTargetPositionX()) + "," + R2S(GetCameraTargetPositionY()))
        endif
        call PauseTimer(stepTimer)
        call TimerStart(stepTimer, STEP_INTERVAL, true, function OnTick)
        return
    endif
    if tick >= FORCE_START_TICK then
        if not pickSent then
            set pickSent = SendHeroPickSync()
            call Heartbeat("HB|pickAttempt tick=" + I2S(tick) + "|sent=" + BoolStr(pickSent) + "|hero=" + I2S(GetHandleId(udg_Hero[1])))
        elseif not chapterStarted then
            set chapterStarted = TryStartChapter()
            call Heartbeat("HB|chapterAttempt tick=" + I2S(tick) + "|started=" + BoolStr(chapterStarted) + "|grid=" + I2S(Grid_GetTotal()))
        endif
    endif
    if tick >= WAIT_TICKS_MAX then
        set failCount = failCount + 1
        call Record("TIMEOUT|game not ready after " + R2S(tick * WAIT_INTERVAL) + "s grid=" + I2S(Grid_GetTotal()) + " slots=" + I2S(Slot_GetCount()) + " areas=" + I2S(GetAreaCount()) + " hero=" + I2S(GetHandleId(udg_Hero[1])) + " heroDisplay=" + I2S(GetHandleId(udg_HeroPicked[HERO_INDEX])))
        call Finish()
        return
    endif
    if tick - (tick / 10) * 10 == 0 then
        call Record("WAIT|t=" + R2S(tick * WAIT_INTERVAL) + "s grid=" + I2S(Grid_GetTotal()) + " hero=" + I2S(GetHandleId(udg_Hero[1])))
    endif
endfunction

private function OnBoot takes nothing returns nothing
    call Record("RUN|boot DELAY=" + R2S(BOOT_DELAY) + " steps=" + I2S(stepCount))
    // 判定 JASS SubString 的 end 参数语义（0 基，含/不含 end），后续匹配只做一种比较以省字节码
    set subInclusive = (SubString("abcd", 0, 1) == "ab")
    // 把地图初始化阶段的日志与章节初始化日志分开（方便 3.3 断言只看章节初始化）
    set bootLog = DebugLogger_TakeSinkBuffer()
    call Record("BOOTLOG|chars=" + I2S(StringLength(bootLog)) + "|probe=" + SubString("abcd", 0, 1))
    call PreloadGenClear()
    call PreloadGenStart()
    call Preload(bootLog)
    call PreloadGenEnd("save\\war3regression_bootlog.txt")
    call Heartbeat("HB|boot done t=" + R2S(BOOT_DELAY) + " steps=" + I2S(stepCount) + "|grid=" + I2S(Grid_GetTotal()))
    if stepCount <= 0 then
        call Record("ERR|no steps registered")
        call Finish()
        return
    endif
    if IsGameReady() then
        call Record("WAIT|game already ready at boot")
        call TimerStart(stepTimer, STEP_INTERVAL, true, function OnTick)
    else
        call Record("WAIT|waiting for game start (grid/slot/area init)")
        call TimerStart(stepTimer, WAIT_INTERVAL, true, function OnWait)
    endif
endfunction

private function Init takes nothing returns nothing
    set stepTimer = CreateTimer()
    // 开启日志捕获（只在测试版地图里；生产图不会执行这里）
    call DebugLogger_SetSinkEnabled(true)
    call TimerStart(stepTimer, BOOT_DELAY, false, function OnBoot)
endfunction

// ===== 公开 API（跨库调用需 testFramework_ 前缀） =====

public function Log takes string msg returns nothing
    call Record("LOG|" + msg)
    call DebugLogger_Log(LOG_INFO, "[test] " + msg)
endfunction

public function AddStep takes code c, string name returns nothing
    if stepCount >= MAX_STEPS then
        call Log("ERR|too many steps (max " + I2S(MAX_STEPS) + ")")
        return
    endif
    set stepTrig[stepCount] = CreateTrigger()
    call TriggerAddAction(stepTrig[stepCount], c)
    set stepName[stepCount] = name
    set stepCount = stepCount + 1
    call DebugLogger_Log(LOG_TRACE, "[test] step registered: " + name)
endfunction

// 等待步骤：占一个 step 位，等待 ticks 个 tick（0.3s 一个）后再继续
public function AddWaitStep takes integer ticks, string name returns nothing
    if stepCount >= MAX_STEPS then
        call Log("ERR|too many steps (max " + I2S(MAX_STEPS) + ")")
        return
    endif
    set stepWait[stepCount] = true
    set stepWaitTicks[stepCount] = ticks
    set stepName[stepCount] = name
    set stepCount = stepCount + 1
endfunction

// 取出并清空测试期间的 DebugLogger 输出（行为用例做日志断言/诊断用）
public function TakeLogs takes nothing returns string
    return DebugLogger_TakeSinkBuffer()
endfunction

// 临时把 TRACE 也收进 sink（行为用例短窗口内使用）
public function SetTraceCapture takes boolean enabled returns nothing
    call DebugLogger_SetTraceCapture(enabled)
endfunction

// 写一条心跳标记（排查「卡死/挂起」用；游戏目录 Save\war3regression_hb.txt）
public function Mark takes string what returns nothing
    call Heartbeat("HB|" + what)
endfunction

public function Expect takes string name, boolean ok, string evidence returns nothing
    set checkCount = checkCount + 1
    if not ok then
        set failCount = failCount + 1
    endif
    call Record("CHECK|" + name + "|" + PassFail(ok) + "|" + evidence)
    if ok then
        call DebugLogger_Log(LOG_TRACE, "[test] PASS " + name + " (" + evidence + ")")
    else
        call DebugLogger_Log(LOG_WARN, "[test] FAIL " + name + " (" + evidence + ")")
    endif
endfunction

public function ExpectInt takes string name, integer actual, integer expected returns nothing
    call Expect(name, actual == expected, I2S(actual) + " vs " + I2S(expected))
endfunction

// 实数比较（带容差），用于位置/血量等断言
public function ExpectReal takes string name, real actual, real expected, real tolerance returns nothing
    call Expect(name, (actual >= expected - tolerance) and (actual <= expected + tolerance), R2S(actual) + " vs " + R2S(expected) + " tol=" + R2S(tolerance))
endfunction

public function StepCount takes nothing returns integer
    return stepCount
endfunction

// 供后续用例使用：强制进章节时创建的测试英雄（可能为 null）
public function GetTestHero takes nothing returns unit
    return testHero
endfunction

// 启动日志（章节初始化期间捕获的 DebugLogger 输出，含级别前缀）
public function GetStartupLog takes nothing returns string
    return startupLog
endfunction

// JASS 没有 StringFind，手写子串计数（SubString 的 end 为包含式）
public function CountOccurrences takes string haystack, string needle returns integer
    local integer count = 0
    local integer pos = 0
    local integer nlen = StringLength(needle)
    local integer hlen = StringLength(haystack)
    local boolean matched
    if nlen <= 0 then
        return 0
    endif
    loop
        exitwhen pos + nlen > hlen
        if subInclusive then
            set matched = (SubString(haystack, pos, pos + nlen - 1) == needle)
        else
            set matched = (SubString(haystack, pos, pos + nlen) == needle)
        endif
        if matched then
            set count = count + 1
            set pos = pos + nlen
        else
            set pos = pos + 1
        endif
    endloop
    return count
endfunction

public function ContainsText takes string haystack, string needle returns boolean
    local integer pos = 0
    local integer nlen = StringLength(needle)
    local integer hlen = StringLength(haystack)
    local boolean matched
    if nlen <= 0 then
        return false
    endif
    loop
        exitwhen pos + nlen > hlen
        if subInclusive then
            set matched = (SubString(haystack, pos, pos + nlen - 1) == needle)
        else
            set matched = (SubString(haystack, pos, pos + nlen) == needle)
        endif
        if matched then
            return true
        endif
        set pos = pos + 1
    endloop
    return false
endfunction

endlibrary
#endif

