

library NNCouEffect requires YDWEJapiEffect,YDWETimerSystem
	globals
		private hashtable ht = InitHashtable()
	endglobals

	/*
		使单位逐渐变为透明
	*/
	private function FadeOut takes nothing returns nothing
		local timer t = GetExpiredTimer()
		local integer i = GetHandleId(t)
		local unit u = LoadUnitHandle(ht,i,1)
		local real currentTransparency = LoadReal(ht, i, 2)
		local real fadeStep = LoadReal(ht, i, 3)
		// 更新透明度
		set currentTransparency = currentTransparency - fadeStep


		// 如果达到或超过目标透明度
		if currentTransparency <= 0 then
			set currentTransparency = 0
			call SetUnitVertexColor(u, 255, 255, 255,0)
			call FlushChildHashtable(ht, i)
			call DestroyTimer(t)
		else
			call SetUnitVertexColor(u, 255, 255, 255, R2I(currentTransparency))
			call SaveReal(ht, i, 2, currentTransparency)
		endif
		
		set u = null
		set t = null
	endfunction
	
	/*
		使单位逐渐变为完全不透明
	*/
	private function FadeIn takes nothing returns nothing
		local timer t = GetExpiredTimer()
		local integer id = GetHandleId(t)
		local unit u = LoadUnitHandle(ht, id, 1)
		local real currentTransparency = LoadReal(ht, id, 2)
		local real fadeStep = LoadReal(ht, id, 3)
		
		set currentTransparency = currentTransparency + fadeStep
		
		if currentTransparency >= 255 then
			set currentTransparency = 255
			// 设置最终透明度
			call SetUnitVertexColor(u, 255, 255, 255, 255)
			call FlushChildHashtable(ht, id)
			call PauseTimer(t)
			call DestroyTimer(t)
		else
			// 设置当前透明度
			call SetUnitVertexColor(u, 255, 255, 255, R2I(currentTransparency))
			call SaveReal(ht, id, 2, currentTransparency)
		endif
		
		set u = null
		set t = null
	endfunction


	//使单位在指定时间内变为完全不透明
	public function SetUnitFadeIn takes unit whichunit,real time,real timeout ,integer currentTransparency returns nothing
		local timer t = CreateTimer()
		local integer id = GetHandleId(t)
		local real startTransparency = I2R(currentTransparency)         // 起始透明度
		local real fadeSteps = time / timeout                   		// 总步数
		local real fadeStep = (255. - startTransparency) / (time / timeout)   // 每步增加的透明度
		
		// 保存数据到哈希表
		call SaveUnitHandle(ht, id, 1, whichunit)
		call SaveReal(ht, id, 2, startTransparency)     // 当前透明度
		call SaveReal(ht, id, 3, fadeStep)              // 每步增加量
		set t = null
	endfunction


	//使单位在指定时间内变为透明
	public function SetUnitFadeout takes unit whichunit,real time,real timeout returns nothing
		local timer t = CreateTimer()
		local integer i = GetHandleId(t)
		local real currentTransparency = 255
		local real fadeStep = currentTransparency / (time / timeout)
		call TimerStart(t,timeout,true,function FadeOut)
		call SaveUnitHandle(ht,i,1,whichunit)
		call SaveReal(ht,i,2,currentTransparency)
		call SaveReal(ht,i,3,fadeStep)
		set t = null
	endfunction
endlibrary
