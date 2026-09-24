library CheckSync initializer CheckSync___Init

    globals
        integer CheckSync___Max_P= 16
        hashtable CheckSync___HT= InitHashtable()
        integer CheckSync___KEY_SYNC= StringHash("CheckSync")
    endglobals


    function CheckSync___Sync takes nothing returns nothing
        local integer i= GetPlayerId(DzGetTriggerSyncPlayer()) + 1
        call SaveInteger(CheckSync___HT, CheckSync___KEY_SYNC, i, S2I(DzGetTriggerSyncData()))
    endfunction
    function CheckSync___Check takes nothing returns nothing
        local integer n= 0
        local integer m= 0
        local integer pn= 0
        local integer i= 1
        local integer now= 0
        local player p= null
        local integer max= CheckSync___Max_P
        local timer t= GetExpiredTimer()
        local integer h= GetHandleId(t)
        local integer last= LoadInteger(CheckSync___HT, h, 0)
        // 判断
        set i=1
        loop
            exitwhen i > max
            set p=Player(i - 1)
            set now=LoadInteger(CheckSync___HT, CheckSync___KEY_SYNC, i) // 获取玩家被同步的值
            if GetPlayerSlotState(p) != PLAYER_SLOT_STATE_EMPTY and GetPlayerController(p) == MAP_CONTROL_USER then
                set m=m + 1
                if now != last then
                    set n=n + 1
                endif
                if GetPlayerSlotState(p) == PLAYER_SLOT_STATE_PLAYING and GetPlayerController(p) == MAP_CONTROL_USER then
                    set pn=pn + 1
                endif
            endif
            set i=i + 1
        endloop
        set i=1
        loop
            exitwhen i > max
            set p=Player(i - 1)
            set now=LoadInteger(CheckSync___HT, CheckSync___KEY_SYNC, i)
            // 在线玩家数量>1时才检测
            if m > 1 and pn > 1 and GetPlayerSlotState(p) == PLAYER_SLOT_STATE_PLAYING and GetPlayerController(p) == MAP_CONTROL_USER then
                if n >= m - 1 then
                    // 异次元玩家的视角
                    set n=n + 1
                    call DisplayTextToPlayer(GetLocalPlayer(), 0, 0, "你终于成功进入异次元了！！！")
                else
                    // 其他玩家的视角
                    if now != last then
                        call DisplayTextToForce(GetPlayersAll(), GetPlayerName(p) + " 已成功进入异次元！！")
                    endif
                endif
            else
            endif
            set i=i + 1
        endloop
        call DestroyTimer(t)
        call FlushChildHashtable(CheckSync___HT, h)
        set p=null
        set t=null
    endfunction
    function CheckSync___Timed takes nothing returns nothing
        local integer i= 1
        local integer max= CheckSync___Max_P
        local timer t= CreateTimer()
        local integer h= GetHandleId(t)
        local integer last= GetRandomInt(1, 999999)
        //set last = last + h
        loop
            exitwhen i > max
            if Player(i - 1) == GetLocalPlayer() then
                call DzSyncData("CheckSync", I2S(last))
            endif
            set i=i + 1
        endloop
        call SaveInteger(CheckSync___HT, h, 0, last)
        call TimerStart(t, 0.5, false, function CheckSync___Check) //0.5秒后判断该同步数据
        set t=null
    endfunction
    function CheckSync___Init takes nothing returns nothing
        local trigger t= CreateTrigger()
        call TriggerAddAction(t, function CheckSync___Sync) //数据同步时，为玩家同步随机数
        call DzTriggerRegisterSyncData(t, "CheckSync", false)
        call TimerStart(CreateTimer(), 1, true, function CheckSync___Timed) // 每秒同步一个数据
        set t=null
    endfunction
endlibrary