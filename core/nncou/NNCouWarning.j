
#include "YDWETimerSystem.j"

library NNCouWarning requires YDWEJapiEffect,YDWETimerSystem
	globals
		private string warningModelRange = "effect\\yujingquan.mdl"
		private string warningModelRect = "effect\\YuJing_ZhiXian.mdl"
		private effect lastCreateWarning = null
	endglobals
        
	public function SetWarningModelRange takes string path returns nothing
		set warningModelRange = path
	endfunction
	
	public function SetWarningModelRect takes string path returns nothing
		set warningModelRect = path
	endfunction
// 圆形预警圈
// 半径，坐标xy，持续时间
	public function WarningRange takes real radius,real x,real y,real time returns effect
		set lastCreateWarning = AddSpecialEffect(warningModelRange,x,y)
		call EXSetEffectSize(lastCreateWarning, radius/192 )
		if(time>0) then
			call YDWETimerDestroyEffect(time,lastCreateWarning)
			call EXSetEffectSpeed(lastCreateWarning, 1./time )
		endif
		//call BJDebugMsg("("+R2S(x)+","+R2S(y)+")")
        //call BJDebugMsg("radius:"+R2S(radius)+",扩大倍率："+R2S(RMinBJ(3., radius/192 )))
        //call BJDebugMsg("time:"+R2S(time))
		return lastCreateWarning
	endfunction
// 矩形预警圈
// 起点坐标xy，方向（角度），长度，宽度，时间
    public function WarningRect takes real x,real y,real degree,real length,real width,real time returns effect
        set lastCreateWarning = AddSpecialEffect(warningModelRect,x,y)
        call EXEffectMatScale(lastCreateWarning, RMinBJ( 3. , length/380 ) , RMinBJ(3., width/80 ) ,1. )
        call EXEffectMatRotateZ(lastCreateWarning,degree)
        if(time>0) then
			call YDWETimerDestroyEffect(time,lastCreateWarning)
			call EXSetEffectSpeed(lastCreateWarning, 1./time )
		endif
        //call BJDebugMsg("length:"+R2S(length)+",扩大倍率："+R2S(RMinBJ(3., length/380 )))
        //call BJDebugMsg("width:"+R2S(width)+",扩大倍率："+R2S(RMinBJ(3., width/80 )))
		return lastCreateWarning
	endfunction
endlibrary
