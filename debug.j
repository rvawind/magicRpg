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

    private integer debug_level = 0
endglobals

public function Log takes integer level, string msg returns nothing
    local string prefix
    if(level<debug_level) then 
        return
    endif
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
    else
        set prefix = "|cff808080[????]|r "
    endif
    call BJDebugMsg(prefix + msg)
endfunction

endlibrary
#endif
