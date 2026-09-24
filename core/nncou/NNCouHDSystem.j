
library NNCouHDSystem
globals
hashtable nncouHT = InitHashtable()
endglobals
function NNCGetHd takes unit u,integer abilityId returns real
return LoadReal(nncouHT,GetHandleId(u),StringHash("hd"+I2S(abilityId)))
endfunction
function NNCSetHd takes unit u,integer abilityId,real value returns nothing
call SaveReal(nncouHT,GetHandleId(u),StringHash("hd"+I2S(abilityId)),RMaxBJ(0,value))
//call BJDebugMsg("护盾:"+I2S(abilityId)+"剩余盾量为："+R2S(GetHd(u,abilityId)))
endfunction
function NNCReduceHd takes unit u,integer abilityId,real value returns nothing
//call BJDebugMsg("收到伤害："+R2S(value))
call NNCSetHd(u,abilityId,NNCGetHd(u,abilityId)-value)
//call BJDebugMsg("护盾:"+I2S(abilityId)+"剩余盾量为："+R2S(GetHd(u,abilityId)))
endfunction
endlibrary
