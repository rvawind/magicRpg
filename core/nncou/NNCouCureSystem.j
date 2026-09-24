
library NNSystemCurer
globals
    private integer woundBufCount = 0
    private integer array woundBufId[10005] // 影响治疗量的bufId集
    private real array woundBufValue[10005] // 影响治疗量的bufId分别对应的治疗增/减益幅度，乘法叠加
	private constant integer STRING_CURE = StringHash("治疗效率")
	private constant integer STRING_CURD = StringHash("被疗效果")
endglobals

public function AddWoundBuf takes integer bufId ,real value returns nothing
    local integer i = 0
    if(value == 0) then
        return
    endif
    loop
        exitwhen i==woundBufCount
        if(bufId == woundBufId[i]) then
            call BJDebugMsg(I2S(bufId)+GetObjectName(bufId)+"被重复注册")
            return
        endif
    endloop
    set woundBufCount = woundBufCount +1
    set woundBufId[woundBufCount] = bufId
    set woundBufValue[woundBufCount] = value
endfunction

private function GetCureAdd takes unit curer,unit tar returns real
    local real add = 1
    local integer i = 0
    if( HaveSavedReal(YDHT,GetHandleId(curer),STRING_CURE) or HaveSavedReal(YDHT,GetHandleId(tar),STRING_CURD) ) then
        set add = add * (1+LoadReal(YDHT,GetHandleId(curer),STRING_CURE)*0.01)
        set add = add * (1-LoadReal(YDHT,GetHandleId(curer),STRING_CURD)*0.01)
    endif
    loop
        exitwhen i==woundBufCount
        if(GetUnitAbilityLevel(tar,woundBufId[i])>0) then
            set add = add * (1 + woundBufValue[i])
            //call BJDebugMsg(GetObjectName(woundBufId[i])) //显示
        endif
        set i = i +1
    endloop
    return RMaxBJ(add,0)
endfunction

//治疗提供者的治疗效率与被施术者的被疗效果都将影响造成治疗的数值
public function CureUnit takes unit curer,unit tar, real value returns real
    local real add = GetCureAdd(curer,tar)
    call SetUnitState(tar,UNIT_STATE_LIFE,GetUnitState(tar,UNIT_STATE_LIFE)+ value *add)
    return value *add
endfunction

endlibrary
