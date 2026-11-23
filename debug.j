#ifndef DEBUG_LOGGER_INCLUDED
#define DEBUG_LOGGER_INCLUDED

library DebugLogger

globals
    // TRACE 用于高频、诊断性输出，即使 debug_level = 0 也不显示（需要 -1 才可见）
    constant integer LOG_TRACE = -1
    constant integer LOG_DEBUG = 0
    constant integer LOG_INFO = 1
    constant integer LOG_WARN = 2
    constant integer LOG_ERROR = 3
    // 验收期专用等级（临时）：比 ERROR 更高，任何 debug_level 下都会显示，
    // 输出为金色 [KEY]，用于“本次验收明确要查看的关键内容”。
    // 验收通过后：把所有 DebugLogger_LogKey(...) 调用改回 DebugLogger_Log(LOG_INFO, ...) 即可。
    constant integer LOG_KEY = 4

    // 作者验收期要求：debug 等级至少为 1（隐藏 TRACE/DEBUG，保留 INFO 及以上）
    private integer debug_level = 1

    // 可选日志捕获（默认关闭）：测试版地图由测试框架开启，把日志收进回归报告。
    // 生产图永远不会开启，行为与原来一致。
    private boolean sinkEnabled = false
    private boolean traceCapture = false
    private string sinkBuffer = ""
    private integer sinkAppends = 0
    private integer sinkChars = 0
endglobals

// 测试框架开启/关闭日志捕获，并清空缓冲
public function SetSinkEnabled takes boolean enabled returns nothing
    set sinkEnabled = enabled
    set sinkBuffer = ""
    set sinkAppends = 0
    set sinkChars = 0
endfunction

// 可选：连 TRACE 也收进 sink（默认关闭；TRACE 量大，开启会显著增加字符串操作，
// 只在行为用例的短窗口内临时开启，避免把初始化线程推到字节码上限）
public function SetTraceCapture takes boolean enabled returns nothing
    set traceCapture = enabled
endfunction

// 排查用统计：捕获了多少行/字符（缓冲可能被截断）
public function GetSinkStats takes nothing returns string
    return "appends=" + I2S(sinkAppends) + "|chars=" + I2S(sinkChars)
endfunction

// 取出并清空已捕获的日志（供测试框架写入报告）
public function TakeSinkBuffer takes nothing returns string
    local string s = sinkBuffer
    set sinkBuffer = ""
    return s
endfunction

private function SinkAppend takes string msg returns nothing
    if not sinkEnabled then
        return
    endif
    set sinkBuffer = sinkBuffer + msg + "\n"
    set sinkAppends = sinkAppends + 1
    set sinkChars = sinkChars + StringLength(msg) + 1
    // 安全上限：超过 4 万字符时保留最近 2 万字符（正常启动日志远小于此）
    if StringLength(sinkBuffer) > 40000 then
        set sinkBuffer = SubString(sinkBuffer, StringLength(sinkBuffer) - 20000, StringLength(sinkBuffer) - 1)
    endif
endfunction

public function Log takes integer level, string msg returns nothing
    local string prefix
    local string suffix = ""
    if level == LOG_TRACE then
        set prefix = "|cff505050[TRACE]|r "
    elseif level == LOG_DEBUG then
        set prefix = "|cff808080[DEBUG]|r "
    elseif level == LOG_INFO then
        set prefix = "|cff00ccff[INFO]|r "
    elseif level == LOG_WARN then
        set prefix = "|cffffff00[WARN]|r "
    elseif level == LOG_ERROR then
        set prefix = "|cffff3333[ERROR]|r "
    elseif level == LOG_KEY then
        // 验收关键内容：金色 [KEY] 标签 + 整行浅金色正文，确保在聊天区一眼可辨
        set prefix = "|cffffcc00[KEY]|r |cffffe066"
        set suffix = "|r"
    else
        set prefix = "|cff808080[????]|r "
    endif
    // 测试 sink：默认只收 INFO 及以上；需要诊断时才临时连 TRACE 一起收
    if sinkEnabled then
        if level >= debug_level or traceCapture then
            call SinkAppend(prefix + msg + suffix)
        endif
    endif
    if(level<debug_level) then 
        return
    endif
    call BJDebugMsg(prefix + msg + suffix)
endfunction

// 验收期专用：显示“明确需要查看的关键内容”（金色 [KEY]，任何 debug_level 都显示）。
// 验收通过后，把这些调用换回普通日志（LOG_INFO）即可；可 grep “DebugLogger_LogKey(”。
public function LogKey takes string msg returns nothing
    call Log(LOG_KEY, msg)
endfunction

endlibrary
#endif
