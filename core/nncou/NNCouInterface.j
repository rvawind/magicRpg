
#ifndef NNCouInterfaceIncluded
#define NNCouInterfaceIncluded

#include "japi\\YDWEAbilityState.j"

#include "japi\\YDWEJapiEffect.j"

#include "japi\\YDWEJapiScript.j"
#include "nncou\\NNCouHDSystem.j"
#include "nncou\\NNCouPoint.j"
#include "nncou\\NNCouString.j"
#include "nncou\\NNCouControllerSystem.j"
#include "nncou\\NNCouMission.j"
#include "nncou\\NNCouWarning.j"
#include "nncou\\NNCouPushSystem.j"
#include "nncou\\NNCouCureSystem.j"
#include "nncou\\NNCouEnumRect.j"


library NNCouInterface requires NNSystemController,NNCouHDSystem,NNCouPoint,NNCouString,NNCouMission,NNCouWarning,NNCouPushSystem,NNSystemCurer,NNCouEnumRect

//String
function NNCoufind takes string src,string ch returns integer
    return NNCFind(src,ch)
endfunction
function NNCouGetLastIndex takes string src,string ch returns integer
    return NNCGetLastIndex(src,ch)
endfunction
function NNCouGetZByXY takes real x,real y returns real
	return NNCGetZByXY(x,y)
endfunction
function NNCouSplit takes string src,string ch,string key1 returns integer
	return NNCSplit(src,ch,key1)
endfunction
function NNCouLoadSpiltString takes string key1 ,integer key2 returns string
    return NNCLoadSpiltString(key1,key2)
endfunction

//WalkAble
function NNCouIsWalkAble takes real x,real y returns boolean
	return NNCIsWalkAble(x,y)
endfunction

//Controller
function NNCouSetControllerUnitId takes integer id returns nothing
	call NNCSetControllerUnitId(id)
endfunction
function NNCouSetControlAbility takes integer typeId,integer abilityId returns nothing
	call NNCSetControlAbility(typeId,abilityId)
endfunction
function NNCouSetControlAbilityOrder takes integer typeId,string order returns nothing
	call NNCSetControlAbilityOrder(typeId,order)
endfunction
function NNCouInitControlAbilityOrder takes nothing returns nothing
	call NNCInitControlAbilityOrder()
endfunction
function NNCouControlGroup takes group g, integer typeId, real time, boolean bossControl, boolean tolerance ,boolean isDestroyGroup returns nothing
	call NNCControlGroup(g,typeId,time,bossControl,tolerance,isDestroyGroup)
endfunction
function NNCouControlUnit takes unit tar, integer typeId, real time, boolean bossControl, boolean tolerance returns nothing
	call NNCControlUnit(tar,typeId,time,bossControl,tolerance)
endfunction
function NNCouSetUnitIncontrollable takes unit u,real time,integer typeId,unit tar,real x,real y returns nothing
	call NNCSetUnitIncontrollable(u,time,typeId,tar,x,y)
endfunction
function NNCouSpellToUnit takes unit target, integer skillcode, real timeout, boolean isApply returns nothing
	call NNSystemController_SpellToUnit(target,skillcode,timeout,isApply)
endfunction
function NNCouSpellToUnitLevel takes unit target, integer level, integer skillcode, real timeout, boolean isApply returns nothing
	call NNSystemController_SpellToUnitSetLevel(target,level,skillcode,timeout,isApply)
endfunction


function NNCouIsUnitCC takes unit u, integer typeId returns boolean
	return NNCIsUnitCC(u,typeId)
endfunction

function NNCouUnitRemoveBufCC takes unit u, integer typeId  returns nothing
	call NNCUnitRemoveBufCC(u,typeId)
endfunction

function NNCouAddBufCC takes integer typeId, integer buffCode returns nothing
	call NNCAddBufCC(typeId,buffCode)
endfunction

//Hd
function NNCouGetHd takes unit u,integer abilityId returns real
return NNCouGetHd(u,abilityId)
endfunction
function NNCouSetHd takes unit u,integer abilityId,real value returns nothing
call NNCouSetHd(u,abilityId,value)
endfunction
function NNCouReduceHd takes unit u,integer abilityId,real value returns nothing
call NNCReduceHd(u,abilityId,value)
endfunction

//Mission
	function NNCouSetTitle takes string name,string title returns nothing
    	call NNCouMission_setTitle(name,title)
	endfunction
    
	function NNCouSetDescribe takes string name,integer id,string describe returns nothing
    	call NNCouMission_setDescribe(name,id,describe)
	endfunction

    function NNCouSetValueHandle takes string name,integer id,integer key1 returns nothing
        call NNCouMission_setValueHandle(name,id,key1)
    endfunction
    function NNCouSetCount takes string name,integer count returns nothing
        call NNCouMission_setCount(name,count)
    endfunction
	function NNCouSetTitleColor takes string str returns nothing
		call NNCouMission_setTitleColor(str)
	endfunction

    function NNCouCreate takes string name,integer count,integer flag returns nothing
        call NNCouMission_create(name,count,flag)
    endfunction
	
    function NNCouGetValueHandle takes string name,integer id returns integer
        return NNCouMission_getValueHandle(name,id)
    endfunction

    function NNCouGetCount takes string name returns integer
        return NNCouMission_getCount(name)
    endfunction
    function NNCouGetValue takes player p,string name,integer id returns integer
        return NNCouMission_getValue(p,name,id)
    endfunction

    function NNCouGetTitle takes string name,boolean isColor returns string
        return NNCouMission_getTitle(name,isColor)
    endfunction

    function NNCouGetDescribe takes string name,integer id returns string
        return NNCouMission_getDescribe(name,id)
    endfunction
	
	
	//Warning
	function NNCouSetWarningModelRange takes string path returns nothing
		call NNCouWarning_SetWarningModelRange(path)
	endfunction
	function NNCouSetWarningModelRect takes string path returns nothing
		call NNCouWarning_SetWarningModelRect(path)
	endfunction
	function NNCouWarningRange takes real x,real y,real radius,real time returns effect
		return NNCouWarning_WarningRange(radius,x,y,time)
	endfunction
	function NNCouWarningRect takes real x,real y,real degree,real length,real width,real time returns effect
		return NNCouWarning_WarningRect(x,y,degree,length,width,time)
	endfunction
	
	//PushSystem
	function NNCouPushActionUnit takes unit u,real degree,real distance,real time,real high,real timeout,integer z,string str_effect,boolean isIgnoreLandform returns nothing 
		call NNCPushActionUnit(time,degree,distance,timeout,high,u,str_effect,isIgnoreLandform,z)
	endfunction
	function NNCouSetYDTimerZ takes timer t,integer z returns nothing
		call NNCSetYDTimerZ(t,z)
	endfunction
	
	//Cure
	function NNCouAddWoundBuf takes integer bufId,real value returns nothing
		call NNSystemCurer_AddWoundBuf(bufId,value)
	endfunction

	function NNCouCureUnit takes unit curer,unit tar, real value returns real
		return NNSystemCurer_CureUnit(curer,tar,value)
	endfunction

	//EnumRect
	function NNCou_EnumRectUnitByXY takes real x0,real y0,real x1,real y1,real width,real length returns group
		return NNCouEnumRect_EnumRectUnitByXY(x0,y0,x1,y1,width,length)
	endfunction
	
	function NNCou_EnumRectUnitByCenterAngle takes real x1,real y1,real angle,real width,real length returns group
		return NNCouEnumRect_EnumRectUnitByCenterAngle(x1,y1,angle,width,length)
	endfunction
	
	function NNCou_EnumRectUnitByBeginAngle takes real x0,real y0,real angle,real width,real length returns group
		return NNCouEnumRect_EnumRectUnitByBeginAngle(x0,y0,angle,width,length)
	endfunction
	
endlibrary

#endif //NNCouInterfaceIncluded
