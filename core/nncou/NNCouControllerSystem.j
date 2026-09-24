#ifndef YDWEYDWEJapiScriptIncluded 
#include "japi\\YDWEJapiScript.j"
#endif

library NNSystemController requires YDWEAbilityState,YDWEYDWEJapiScript
globals
private integer unitId = 0
private integer array Conroller
private string array ControlOrderIds
private group IncontrollableGroup=CreateGroup()
private integer array BufCC[10005] //无法施法
private integer BufCCCountA = 0 
private integer BufCCCountB = 0 
public integer SKILL_TAG_BOSS = 0
endglobals

public function SpellToUnitSetLevel takes unit target, integer level, integer abllcode, real timeout, boolean isApply returns nothing
	local unit u = null
	local location unitLoc = null
	local location targetLoc = null
	if (isApply) then
		set u = CreateUnit(Player(PLAYER_NEUTRAL_PASSIVE),unitId,GetUnitX(target),GetUnitY(target),0)
	else
		if (GetOwningPlayer(target)!=Player(PLAYER_NEUTRAL_AGGRESSIVE)) then
			set u = CreateUnit(Player(PLAYER_NEUTRAL_AGGRESSIVE),unitId,GetUnitX(target),GetUnitY(target),0)
		else
			set u =CreateUnit(Player(bj_PLAYER_NEUTRAL_EXTRA),unitId,GetUnitX(target),GetUnitY(target),0)
		endif
	endif
	if ( u !=null) then
        call UnitApplyTimedLife(u, 'BHwe', timeout)
		call UnitAddAbility(u,abllcode)
		call SetUnitAbilityLevel(u,abllcode,level)
        set unitLoc = GetUnitLoc(u)
		set targetLoc = GetUnitLoc(target)
		call SetUnitFacingTimed(u, AngleBetweenPoints(unitLoc, targetLoc), .0)
        call RemoveLocation(targetLoc)
        call RemoveLocation(unitLoc)
		
		
		//call BJDebugMsg(YDWEGetObjectPropertyString( YDWE_OBJECT_TYPE_ABILITY, abllcode, "Order"))
		
		
        call IssueTargetOrder(u, YDWEGetObjectPropertyString( YDWE_OBJECT_TYPE_ABILITY, abllcode, "Order"), target) //通过japi获取技能命令 并发布
	endif
	set u = null
	set unitLoc = null
	set targetLoc = null
endfunction

public function SpellToUnit takes unit target, integer abllcode, real timeout, boolean isApply returns nothing
	call SpellToUnitSetLevel(target,1,abllcode,timeout,isApply)
endfunction 


/**

   {
    击晕特效数量 e1 e2 e3 e4 e5 e6 e7 e8
    沉默特效数量 e1 e2 e3 e4 e5 e6 e7 e8
    禁锢...
    缴械...
    }
**/
function NNCouControllerAddEffect takes unit u, effect e, integer cctype returns nothing
    local integer count = 0
    local integer id = 0
    if(cctype==1)then
        set id = StringHash("击晕特效")
    endif
    if(cctype==2)then
        set id = StringHash("沉默特效")
    endif
    if(cctype==3)then
        set id = StringHash("禁锢特效")
    endif
    if(cctype==4)then
        set id = StringHash("缴械特效")
    endif

    set count = LoadInteger(nncouHT,GetHandleId(u),id) +1
    call SaveEffectHandle(nncouHT,GetHandleId(u),id+count,e)
    call SaveInteger(nncouHT,GetHandleId(u),id,count)
endfunction

function FlushUnitControllerEffect takes unit u returns nothing
    local integer cctype =0 
    local integer count = 0
    local integer id = 0
    loop
        exitwhen cctype>3
        if(cctype==1)then
            set id = StringHash("击晕特效")
        endif
        if(cctype==2)then
            set id = StringHash("沉默特效")
        endif
        if(cctype==3)then
            set id = StringHash("禁锢特效")
        endif
        if(cctype==4)then
            set id = StringHash("缴械特效")
        endif
        set count = LoadInteger(nncouHT,GetHandleId(u),id)
        loop
            exitwhen count == 0
            call DestroyEffect(LoadEffectHandle(nncouHT,GetHandleId(u),id+count))
            call RemoveSavedHandle(nncouHT,GetHandleId(u),id+count)
            set count = count - 1
        endloop
        set cctype= cctype +1
    endloop
endfunction

function NNCIsUnitCC takes unit u, integer typeId returns boolean
	local integer i = 1
	loop
		exitwhen i > BufCC[ typeId*1000 ]
		if( GetUnitAbilityLevel(u, BufCC[i+typeId*1000]) > 0 ) then
			return true
		endif
		set i = i + 1
	endloop
	return false
endfunction

function NNCAddBufCC takes integer typeId , integer id returns nothing
	local integer i = 1
	loop
		exitwhen i > BufCC[ typeId*1000 ]
		if( BufCC[i + typeId*1000] == id ) then
            call BJDebugMsg(I2S(id)+GetObjectName(id)+"被重复注册")
			return
		endif
		set i = i + 1
	endloop
	set BufCC[i + typeId*1000] = id
	set BufCC[typeId*1000] = BufCC[typeId*1000] +1
endfunction

function NNCUnitRemoveBufCC takes unit u, integer typeId returns nothing
	local integer i = 1
	loop
		exitwhen i > BufCC[ typeId*1000 ]
		if( GetUnitAbilityLevel(u, BufCC[i+typeId*1000]) > 0 ) then
			call UnitRemoveAbility( u,BufCC[i+typeId*1000] )
		endif
		set i = i + 1
	endloop
    call FlushUnitControllerEffect(u)
endfunction

function NNCSetControllerUnitId takes integer id returns nothing
    set unitId = id
endfunction
function NNCSetControlAbility takes integer typeId,integer abilityId returns nothing
    set Conroller[typeId] = abilityId
endfunction
function NNCSetControlAbilityOrder takes integer typeId,string order returns nothing
    set ControlOrderIds[typeId] = order
endfunction
function NNCInitControlAbilityOrder takes nothing returns nothing
    set ControlOrderIds[1]="thunderbolt"
    set ControlOrderIds[2]="soulburn"
    set ControlOrderIds[3]="ensnare"
    set ControlOrderIds[4]="drunkenhaze"
endfunction

/**
@params
unit tar 目标单位组
int controlType 控制类型（暂定为眩晕，沉默[灵魂燃烧]，禁锢，缴械，失控）
real time 持续时间
bool bossControl 是否强控制（对BOSS有效）（默认否）
bool tolerance 受到韧性影响（默认是）
bool isDestroyGroup 是否摧毁单位组（默认否）
**/
function NNCControlGroup takes group g, integer typeId, real time, boolean bossControl, boolean tolerance ,boolean isDestroyGroup returns nothing
    local unit u =null
    local unit ut = null
    local real toleranceVal = 0.00
    local group g2 = null
    local location unitLoc = null
	local location target = null
    if(CountUnitsInGroup(g)>0) then
		set g2 = CreateGroup()
        call GroupAddGroup(g,g2)
        set u = FirstOfGroup(g2)
		if (GetOwningPlayer(u)!=Player(PLAYER_NEUTRAL_AGGRESSIVE)) then
			set u = CreateUnit(Player(PLAYER_NEUTRAL_AGGRESSIVE),unitId,GetUnitX(u),GetUnitY(u),0)
		else
			set u =CreateUnit(Player(bj_PLAYER_NEUTRAL_EXTRA),unitId,GetUnitX(u),GetUnitY(u),0)
		endif
        call UnitApplyTimedLife(u, 'BHwe', 1.50)
        call UnitAddAbility(u,Conroller[typeId])
        if(tolerance) then 
            call SaveBoolean(YDHT,GetHandleId(u),StringHash("是否受到韧性影响"),true)
        endif
        loop
            set ut = FirstOfGroup(g2)
            exitwhen ut == null
            if(GetUnitAbilityLevel(u,NNSystemController_SKILL_TAG_BOSS)==0) then
                if (tolerance) then
                    set toleranceVal = LoadReal(nncouHT,GetHandleId(ut),StringHash("韧性"))
                    set toleranceVal = RMinBJ(99.0,toleranceVal)
                    set toleranceVal = RMaxBJ(0.,toleranceVal)
                    set toleranceVal = 1 - toleranceVal / 100
                    set time = time * toleranceVal
                endif
                if(time>0) then
                    set unitLoc = GetUnitLoc(ut)
                    set target = GetUnitLoc(u)
                    call SetUnitFacingTimed(u, AngleBetweenPoints(target, unitLoc), .0)
                    call RemoveLocation(target)
                    call RemoveLocation(unitLoc)
                    call YDWESetUnitAbilityDataReal(u, Conroller[typeId], 1, 102, time) //102:持续时间
                    call YDWESetUnitAbilityDataReal(u, Conroller[typeId], 1, 103, time) //103:持续时间
                    
                    // call BJDebugMsg(R2S(time))
                    call IssueTargetOrder(u, ControlOrderIds[typeId], ut)
                endif
            endif
            call GroupRemoveUnit(g2,ut)
        endloop
        call DestroyGroup(g2)
    endif
    if(isDestroyGroup) then
        call DestroyGroup(g)
    endif
    set u=null
    set g2=null
    set unitLoc=null
	set target = null
endfunction

/**
@params
unit tar 目标单位
int controlType 控制类型（暂定为眩晕，沉默[灵魂燃烧]，禁锢，缴械，失控）
real time 持续时间
bool bossControl 是否强控制（对BOSS有效）（默认否）
bool tolerance 受到韧性影响（默认是）
**/
function NNCControlUnit takes unit tar, integer typeId, real time, boolean bossControl, boolean tolerance returns nothing
    local unit u =null
    local real toleranceVal = 0.00
    local location unitLoc = null
    local location target = null
    
    if(GetUnitAbilityLevel(u,NNSystemController_SKILL_TAG_BOSS)>0) then
        //debug call BJDebugMsg("单位不能被击退")
        return
    endif
    if (tolerance) then
        set toleranceVal = LoadReal(nncouHT,GetHandleId(tar),StringHash("韧性"))
        set toleranceVal = RMinBJ(99.0,toleranceVal)
        set toleranceVal = RMaxBJ(0,toleranceVal)
        set toleranceVal = 1 - toleranceVal / 100
        set time = time * toleranceVal
    endif
    if(time >0) then
		if (GetOwningPlayer(tar)!=Player(PLAYER_NEUTRAL_AGGRESSIVE)) then
			set u = CreateUnit(Player(PLAYER_NEUTRAL_AGGRESSIVE),unitId,GetUnitX(tar),GetUnitY(tar),0)
		else
			set u =CreateUnit(Player(bj_PLAYER_NEUTRAL_EXTRA),unitId,GetUnitX(tar),GetUnitY(tar),0)
		endif
        call UnitApplyTimedLife(u, 'BHwe', 0.50)
        set unitLoc = GetUnitLoc(tar)
        set target = GetUnitLoc(u)
		call SetUnitFacingTimed(u, AngleBetweenPoints(target, unitLoc), .0)
        call RemoveLocation(unitLoc)
        call RemoveLocation(target)
        call UnitAddAbility(u,Conroller[typeId])
        call YDWESetUnitAbilityDataReal(u, Conroller[typeId], 1, 102, time) //102:持续时间
        call YDWESetUnitAbilityDataReal(u, Conroller[typeId], 1, 103, time) //103:持续时间
        
        debug call BJDebugMsg(R2S(time))

        call IssueTargetOrder(u, ControlOrderIds[typeId], tar)
    endif
    set u =null
    set unitLoc = null
    set target = null
endfunction
// hook IssueTargetOrder(a,b,c) 
function UnitIncontrollable takes nothing returns nothing
    local timer t =GetExpiredTimer()
    local integer i = GetHandleId(t)
    local unit u= LoadUnitHandle(nncouHT,i,0)
    local integer typeId= LoadInteger(nncouHT,i,0)
    local real time = LoadReal(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"time"))
    set time = time-.01
    if (time<=.0) then
    call FlushChildHashtable(nncouHT,i)
    call DestroyTimer(t)
    call RemoveSavedHandle(nncouHT,GetHandleId(u),StringHash("Incontrollable"))
    call GroupRemoveUnit(IncontrollableGroup,u)
    endif
    call SaveReal(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"time"),time)
    set t = null
    set u = null
endfunction
function UnitIncontrollableAction takes nothing returns nothing
    local unit u= GetTriggerUnit()
    local integer i = GetHandleId(u)
    local integer typeId= LoadInteger(nncouHT,i,StringHash("Incontrollable"+"typeId"))
    local real x=.0
    local real y=.0
    local unit tar= null
    if (typeId==1)then
    call IssueImmediateOrder(GetTriggerUnit(), "stop")
	//call BJDebugMsg("stop")
    else 
    if (typeId==2) then
        set x = LoadReal(nncouHT,i,StringHash("Incontrollable"+"x"))
        set y = LoadReal(nncouHT,i,StringHash("Incontrollable"+"y"))
        call IssuePointOrder(GetTriggerUnit(), "move", x, y)
        else 
            if (typeId==3) then
                set tar = LoadUnitHandle(nncouHT,i,StringHash("Incontrollable"+"target"))
                call IssueTargetOrder(GetTriggerUnit(), "attack", tar)
                set tar = null
            endif
        endif
    endif
    set u=null
endfunction
/**
@params
unit tar 目标单位
real time 持续时间
int typeId 控制类型（暂定为静止，移动，嘲讽）
unit tar 命令发布目标（如果有）
real x，y命令发布目标（如果有）
**/
function NNCSetUnitIncontrollable takes unit u,real time,integer typeId,unit tar,real x,real y returns nothing
    local timer t =null
    call SaveReal(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"time"),time)
    call SaveInteger(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"typeId"),typeId)
    call SaveUnitHandle(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"target"),tar)
    call SaveReal(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"x"),x)
    call SaveReal(nncouHT,GetHandleId(u),StringHash("Incontrollable"+"y"),y)
    if (LoadTimerHandle(nncouHT,GetHandleId(u),StringHash("Incontrollable"))==null) then
        set t=CreateTimer()
        call TimerStart(t,0.01,true,function UnitIncontrollable)
        call SaveTimerHandle(nncouHT,GetHandleId(u),StringHash("Incontrollable"),t)
    else
        set t = LoadTimerHandle(nncouHT,GetHandleId(u),StringHash("Incontrollable"))
    endif
    call SaveUnitHandle(nncouHT,GetHandleId(t),0,u)
    call SaveInteger(nncouHT,GetHandleId(t),0,typeId)
    call SaveReal(nncouHT,GetHandleId(t),0,.0)//随机改变方向间隔
    set t = null
endfunction
function isUnitInIncontrollableGroup takes nothing returns boolean
    if (IsUnitInGroup(GetTriggerUnit(),IncontrollableGroup)) then
    return true
    endif
    return false
endfunction
function NNCInit_Incontrollable takes nothing returns nothing
    local trigger t = CreateTrigger()
    call TriggerRegisterAnyUnitEventBJ(t, EVENT_PLAYER_UNIT_ISSUED_TARGET_ORDER)
    call TriggerRegisterAnyUnitEventBJ(t, EVENT_PLAYER_UNIT_ISSUED_POINT_ORDER)
    call TriggerRegisterAnyUnitEventBJ(t, EVENT_PLAYER_UNIT_ISSUED_ORDER)
    call TriggerAddCondition(t, Condition(function isUnitInIncontrollableGroup))
    call TriggerAddAction(t,function UnitIncontrollableAction)
endfunction

endlibrary
