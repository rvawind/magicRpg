library RushSystem 
globals
    private hashtable ht = InitHashtable()
    private integer array countBase // 默认出怪数量
    private integer array typeBase //默认出怪种类（波数） 
    private real array bornX //出生点X
    private real array bornY //出生点Y
    private real array face //出生面向
    private boolean array isCountExtra
    private boolean array isBossRound //是否Boss波次
    private real timeout = 0.8 // 单波出怪间隔
    private integer array bossType //对应的BOSS类型
    private constant integer HASH_TAB = StringHash("TAB")
    
    private integer enemyPlayer = 5//怪物拥有者编号
endglobals

private function init takes nothing returns nothing
endfunction

public function AddRushAbility takes integer count,integer abilType returns nothing
    local integer tabNum =  LoadInteger(ht,count,HASH_TAB) +1
    call SaveInteger(ht,count,HASH_TAB + tabNum,abilType)
    call SaveInteger(ht,count,HASH_TAB,tabNum)
endfunction

//声明该波次中，从第start怪物开始到end-1的怪物之间，怪物的类型为type
//end必须大于start，start必须大于等于1
public function SetRushMonsterEx takes integer count,integer start,integer end, integer unitType returns nothing
    local integer i 
    set i = start
    if start<1 or end<=start then
        call BJDebugMsg("设置波次怪物错误")
        return
    endif
    set isCountExtra[count] = true
    loop
        exitwhen i >= end
        call SaveInteger(ht,count,i,unitType)
        set i = i+1 
    endloop
endfunction

//设置怪物类型
public function SetTypeBase takes integer rushCount , integer unitType returns nothing
    set typeBase[rushCount] = unitType
endfunction

//设置刷怪数量
public function SetCountBase takes integer rushCount , integer value returns nothing
    set countBase[rushCount] = value
endfunction

//设置boss
public function SetBoss takes integer roundId, integer unitType returns nothing
    set bossType[roundId] = unitType
    set isBossRound[roundId] = true
endfunction

private function CreateBoss takes integer roundId,integer playerId returns nothing 
endfunction

//
private function RushTimerNormal takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer i = GetHandleId(t)
    local unit u = null
    local integer count = LoadInteger(ht,i,0)
    local integer roundId = LoadInteger(ht,i,1)
    local integer playerId = LoadInteger(ht,i,2)
    local boolean isBoss = LoadBoolean(ht,i,0)
    local integer skillNum = LoadInteger(ht,roundId,HASH_TAB)
    if(count>0)then
        call SaveInteger(ht,i,0,count-1)
        //创建一个当前波数的怪物给对应玩家
        set u =  CreateUnit(Player(enemyPlayer),typeBase[roundId],bornX[playerId],bornY[playerId],face[playerId])
        loop
            exitwhen skillNum> 0
            call UnitAddAbility(u,LoadInteger(ht,roundId,HASH_TAB+skillNum))
            set skillNum = skillNum -1
        endloop
    else
        if(isBoss)then
            call CreateBoss(roundId,playerId)
        endif
        call FlushChildHashtable(ht,i)
        call DestroyTimer(t)
    endif
    set t = null
    set u = null
endfunction

private function RushTimerNormalEx takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer i = GetHandleId(t)
    local unit u = null
    local integer count = LoadInteger(ht,i,0)
    local integer roundId = LoadInteger(ht,i,1)
    local integer playerId = LoadInteger(ht,i,2)
    local boolean isBoss = LoadBoolean(ht,i,0)
    local integer skillNum = LoadInteger(ht,roundId,HASH_TAB)

    if(HaveSavedInteger(ht,roundId,count)) then
        call SaveInteger(ht,i,0,count+1)
        set u =  CreateUnit(Player(enemyPlayer),LoadInteger(ht,roundId,count),bornX[playerId],bornY[playerId],face[playerId])
        loop
            exitwhen skillNum> 0
            call UnitAddAbility(u,LoadInteger(ht,roundId,HASH_TAB+skillNum))
            set skillNum = skillNum -1
        endloop
    else
        if(isBoss)then
            call CreateBoss(roundId,playerId)
        endif
        call FlushChildHashtable(ht,i)
        call DestroyTimer(t)
    endif

    set t = null
    set u = null
endfunction


private function Rush takes integer playerId,integer roundId returns nothing
    local timer t = CreateTimer()
    local integer i = GetHandleId(t)
    local integer num = 1

    if(isCountExtra[roundId]==false)  then
        if(countBase[roundId]==0) then
            //设置默认刷怪数量
            call SaveInteger(ht,i,0,countBase[0])
        else
            //对刷怪的数量进行调整
            call SaveInteger(ht,i,0,countBase[roundId])
        endif
        call TimerStart(t,timeout,true,function RushTimerNormal) 
    else
        //设置刷怪顺序由1开始
        call SaveInteger(ht,i,0,1)
        call TimerStart(t,timeout,true,function RushTimerNormalEx)
    endif
    if(isBossRound[roundId]) then
        call SaveBoolean(ht,i,0,true)
    endif
    call SaveInteger(ht,i,1,roundId)
    call SaveInteger(ht,i,2,playerId)
endfunction



endlibrary

