
library NNCouPushSystem requires NNCouPoint


globals
private real G = 1300
private real timerRiseTimeOut = 0.03
private timer array tRise[10]
private integer array tCount[10]
private boolean array tOn[10]
private group array tRiseGroup[10]
private integer vRiseHT = StringHash("升空速度")
private integer tRiseHT = StringHash("滞空时间")
private integer HTAdrs = StringHash("NNCouPushSystem_RiseTimer")
endglobals


#define FLY_HEIGHT StringHash("飞行高度")

function GetUnitFlyHeightEx takes unit u returns real
    if(HaveSavedReal(nncouHT,GetHandleId(u),FLY_HEIGHT)) then
        return LoadReal(nncouHT,GetHandleId(u),FLY_HEIGHT)
    endif
    return GetUnitFlyHeight(u)
endfunction 

function SetUnitFlyHeightEx takes unit u ,real val,real v returns nothing
    if(v<1 or v >10000) then
        call SaveReal(nncouHT,GetHandleId(u),FLY_HEIGHT,val)
    else
        //debug //call BJ//debugMsg("设置高度速率不为0")
    endif
    call SetUnitFlyHeight(u,val,0)
endfunction
        
#define GetUnitFlyHeight GetUnitFlyHeightEx
#define SetUnitFlyHeight SetUnitFlyHeightEx

private function RiseUnitGroupAction takes nothing returns nothing
    local integer i = GetHandleId( GetEnumUnit())
    local real tNew = LoadReal(nncouHT,i,HTAdrs+2) - timerRiseTimeOut
    local real hNew = .0
    local real v = 0
    local real hDelta = .0
    local real hOld = .0

    local integer id = LoadInteger(nncouHT,i,HTAdrs)
    // //call BJ//debugMsg(GetUnitName(GetEnumUnit())+"剩余滞空时间："+R2S(tNew))
    if  (tNew > 0) then
        set v = LoadReal(nncouHT,i,HTAdrs+1)
        set hDelta = v * timerRiseTimeOut
        set hOld = GetUnitFlyHeight(GetEnumUnit())
        set hNew = hOld + hDelta
        set v  = v - G * timerRiseTimeOut
        // //call BJ//debugMsg("当前高度"+R2S(hOld))
        // //call BJ//debugMsg("下一次高度"+R2S(hNew))
        call SetUnitFlyHeight(GetEnumUnit(),hNew,0)
        call SaveReal(nncouHT,i,HTAdrs+1,v)
        call SaveReal(nncouHT,i,HTAdrs+2,tNew)
    else
        call GroupRemoveUnit(tRiseGroup[id],GetEnumUnit())
        call RemoveSavedInteger(nncouHT,i,HTAdrs)
        set tCount[id] = tCount[id] - 1
        call SetUnitFlyHeight(GetEnumUnit(), 0, 0)
        // //call BJ//debugMsg(GetUnitName(GetEnumUnit())+"的击飞流程结束")
        // //call BJ//debugMsg(I2S(id)+"击飞组的剩余被击飞数量为"+I2S(tCount[id]))
    endif

endfunction

function RiseUnitTimerAction takes nothing returns nothing
    local integer id = -1
    ////call BJ//debugMsg("计时器到期")
    loop 
        set id = id +1
        if tRise[id] == GetExpiredTimer() then
            exitwhen true
        endif
        exitwhen id>9
    endloop
    
    ////call BJ//debugMsg("到期的计时器"+I2S(id))
    call ForGroup(tRiseGroup[id],function RiseUnitGroupAction)
endfunction

private function RiseUnit takes unit u,real time returns nothing
    local integer i = GetHandleId(u)
    local real tOld = LoadReal(nncouHT,i,HTAdrs+2)
    local real tNew = tOld +time
    local real hTarget = 0.125 * G * tNew *tNew
    local real hOld = GetUnitFlyHeight(u)
    local real v = 0.5*(tNew-2*hOld / G / tNew)  *G
    local integer timerId = -1
    if(GetUnitAbilityLevel(u,NNSystemController_SKILL_TAG_BOSS)>0)then
        ////debug //call BJ//debugMsg("单位"+GetUnitName(u)+"不能被击飞")
        return
    endif
    if LoadInteger(nncouHT,i,HTAdrs)==0 then
        //寻找空闲计时器
        loop
            set timerId = timerId + 1
            exitwhen timerId > 9
            
            if(tCount[timerId]<10)then

                //判断计时器是否已经启动
                if ( tOn[timerId] == false ) then
                    set tOn[timerId] = true
                    set tRise[timerId] = CreateTimer()
                    set tRiseGroup[timerId] = CreateGroup()
                    //debug //call BJ//debugMsg("启动计时器" + I2S(timerId) +"号")
                    call TimerStart(tRise[timerId],timerRiseTimeOut,true,function RiseUnitTimerAction)
                endif
                
                //找到了，退出
                exitwhen true
            endif
        endloop
    else
        set timerId = LoadInteger(nncouHT,i,HTAdrs)
    endif

    if (timerId<10)  then
        ////call BJ//debugMsg("使用计时器" + I2S(timerId) +"号 进行击飞流程")
        ////call BJ//debugMsg("总滞空时间："+R2S(tNew))
        ////call BJ//debugMsg("初始速度："+R2S(v))
        ////call BJ//debugMsg("目标最高高度："+R2S(hTarget))
        call UnitAddAbility(u,'Arav')
        call UnitRemoveAbility(u,'Arav')
        set tCount[timerId] = tCount[timerId]+1
        call GroupAddUnit(tRiseGroup[timerId],u)
        call SaveInteger(nncouHT,i,HTAdrs,timerId)
        call SaveReal(nncouHT,i,HTAdrs+1,v)
        call SaveReal(nncouHT,i,HTAdrs+2,tNew)
    else
        //call BJ//debugMsg("没有可用的计时器")
        //return false
    endif
endfunction




/*

击退和击飞是否能同时？ 不能

那么击退和击飞共用计时器？ 是

固定一个定值作为击飞的陨落速度？ 是

将计时器绑定在单位身上以方便获取？ 应当但可能导致卡顿

增加一个整数，以作为这次冲锋是否会被下一次冲锋替代

*/
function PushTimerByDegree takes nothing returns nothing
    local timer t = GetExpiredTimer()
    local integer i = GetHandleId(t)
    local integer times = LoadInteger( YDHT, i ,1) //最大运行次数
    local real speed = LoadReal( YDHT , i , 1)//单次移动距离，通过周期得出
    local real degree = LoadReal( YDHT , i ,2)
    local string str_effect = LoadStr( YDHT , i, 3)
    local unit u = LoadUnitHandle( YDHT , i ,4)
	local boolean isIgnoreLandform = LoadBoolean( YDHT, i ,5)
    local real r1= 0
    local real r2= 0
    
    //从单位获取高度

    //local real high = GetUnitFlyHeight(u)
    //local real speed_high = LoadReal(YDHT, GetHandleId(u) , StringHash("Z轴速度"))
    //local real highest = GetUnitDefaultFlyHeight(u) //单位常规高度
    if(HaveSavedInteger(YDHT,i,1)==false) then
        ////call BJ//debugMsg(I2S(times))
        call DestroyTimer(t)
        return
    endif
    if (( times <= 0 ) /*and (( high <= highest )or (high<1))  */ ) then

        call FlushChildHashtable(YDHT,i)
        call DestroyEffect( AddSpecialEffect( str_effect , GetUnitX(u), GetUnitY(u)))
        // call SetUnitFlyHeight(u,highest,0)
        // call SaveReal(YDHT, GetHandleId(u) , StringHash("Z轴速度"),0)
        call RemoveSavedHandle( YDHT, GetHandleId(u) , StringHash("位移计时器"))
        ////debug //call BJ//debugMsg("击退结束")
        call DestroyTimer(t)
        return
	endif
	/*
	if (times <=0 ) then
		////call BJ//debugMsg("highest: "+R2S(highest))
		
		////call BJ//debugMsg("high:    "+R2S(high))
		
    endif
	*/
    if( times > 0 )then
        call SaveInteger( YDHT, i, 1, times-1)
        if(speed>=0) then
            ////call BJ//debugMsg(I2S(times))
            ////call BJ//debugMsg(R2S(degree))
            set r1= GetUnitX(u) + speed * CosBJ(degree)
            set r2= GetUnitY(u) + speed * SinBJ(degree)
            if ((isIgnoreLandform == true) or (NNCIsWalkAble(r1,r2))) then
                call SetUnitX(u, r1 )
                call SetUnitY(u, r2 )
            endif
        endif
    endif

    /*
    if (high > highest) then
        set speed_high = speed_high + G
        set high = RMaxBJ( high + speed_high ,highest)
        ////call BJ//debugMsg(R2S(high))
        call SetUnitFlyHeight( u , high , 0) 
		call SaveReal(YDHT,GetHandleId(u),StringHash("Z轴速度"),speed_high)
        //call SetUnitPosition(u, GetUnitX(u) , GetUnitY(u) )
    endif
        */
    set u = null
    set str_effect = ""
    set t = null
endfunction


/*
    持续时间
    击退方向
    距离
    间隔
    高度
    单位
    过程特效
    是否无视地形
    优先度
*/
function NNCPushActionUnit takes real time,real degree,real distance,real timeout,real high,unit u,string str_effect ,boolean isIgnoreLandform ,integer z returns nothing 
    local integer times  = 0
    local real speed = 0
    
    //local real speed_h = 0
    
    local timer t = null
    local integer i = 0

    if(GetUnitAbilityLevel(u,NNSystemController_SKILL_TAG_BOSS)>0) then
        ////debug //call BJ//debugMsg("单位不能被击退")
        return
    endif
    //清空上次计时器保存内容
    if(HaveSavedHandle(YDHT,GetHandleId(u),StringHash("位移计时器")) == true) then
        set t = LoadTimerHandle(YDHT,GetHandleId(u),StringHash("位移计时器"))
        
        if(LoadInteger(YDHT,GetHandleId(t),StringHash("位移优先度"))>z)then
            //击退力度小于原来冲锋计时器的优先级
            //不作任何处理
            //debug //call BJ//debugMsg("不进行处理")
            return
        endif
        call FlushChildHashtable(YDHT,GetHandleId(LoadTimerHandle(YDHT,GetHandleId(u),StringHash("位移计时器"))))
		call PauseTimer(LoadTimerHandle(YDHT,GetHandleId(u),StringHash("位移计时器")))
    endif
    //保存当次计时器
    set t = CreateTimer()
    set i = GetHandleId(t) 
    call TimerStart(t,timeout,true,function PushTimerByDegree)
	
	set times  = R2I(time / timeout)
    if(times <= 0) then
        return
    endif
	set speed = distance / I2R(times)

    ////call BJ//debugMsg("单位："+GetUnitName(u))
	////call BJ//debugMsg("总位移距离："+R2S(distance))
	////call BJ//debugMsg("位移次数："+R2S(times))
	////call BJ//debugMsg("单次位移距离："+R2S(speed))

    if(high>0) then
        call RiseUnit(u,time)
    endif
    //初始z轴速度 = z轴速度降低到0所需的次数 * 每次降低的值 * -1
	//set speed_h = (time / timeout ) /2 * G * -1 
	////call BJ//debugMsg("z轴初速度"+R2S(speed_h))
	
    call SaveInteger(YDHT,i,1,times)
    call SaveReal(YDHT,i,1,speed)
    call SaveReal(YDHT,i,2,degree)
    call SaveStr(YDHT,i,3,str_effect)
    call SaveUnitHandle(YDHT,i,4,u)
	call SaveBoolean(YDHT,i,5,isIgnoreLandform)
    
    //设置该次击退优先级，一般为1
    call SaveInteger(YDHT,i,StringHash("位移优先度"),z)
    
    //call SaveReal(YDHT,GetHandleId(u),StringHash("Z轴速度"),RMaxBJ(LoadReal(YDHT, GetHandleId(u) , StringHash("Z轴速度")),0)+speed_h)
    
    call SaveTimerHandle(YDHT,GetHandleId(u),StringHash("位移计时器"),t)
    
    set t = null
    
endfunction

function NNCSetYDTimerZ takes timer t,integer z returns nothing
	call SaveInteger(YDHT,GetHandleId(t),StringHash("位移优先度"),z)
endfunction


endlibrary
