/*
    词条名：可以根据词条名找到该词条
    等级：提供不同的数值
    数据：被获取后储存于物品上。
    非数值型词条：应有指定的逆天自定义值
    词条起始等级：方便词条库随机时能随出该词条


*/

library ExtraAttr initializer init  needs NNCouInterface 
    globals
        private trigger trigGetItem =CreateTrigger()
        private trigger trigLossItem =CreateTrigger()
        private integer array attrsNormal[300]
        private integer count
        private ExtraAttrPool normal
        private integer keyItemLvHash = StringHash("词条等级")
    endglobals


    struct ExtraAttr 
        string name
        string description
        integer unique
        integer isReal
        integer array val[4]
        integer attrhash
        real array valReal[4]
        static integer typekey = StringHash("ExtraAttr") 

        // 创建一个整数型词条模板：设置名称与 hash 并返回新实例
        // 用途：用于创建非实数（整数）型的通用词条。
        static method createIntAttr takes string str returns thistype
            local thistype this = thistype.allocate()
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        // 创建一个实数型词条模板：标记为实数类型并返回新实例
        // 用途：用于创建保存浮点数数值的词条（例如加成、速度等）。
        static method createRealAttr takes string str returns thistype
            local thistype this = thistype.allocate()
            set isReal = 1
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        // 创建一个唯一词条（unique）：用于只能存在一次或计数的特殊词条
        // 参数 description 可用于保存该唯一词条的文本说明。
        static method createUniqueAttr takes string str,string description returns thistype
            local thistype this = thistype.allocate()
            set unique = 1
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        endmethod

        // 从全局哈希表读取并返回绑定到物品 `it` 上的 ExtraAttr（通过 typekey 存储）
        // 注意：返回值来自 hashtable，若未绑定则返回 0/null。
        static method GetExtraAttrFromItem takes item it returns ExtraAttr
            return LoadInteger(ht,GetHandleId(it),ExtraAttr.typekey)
        endmethod

        // 将词条 `a` 的值应用/保存到物品 `it` 上，并把词条实例引用保存到全局 ht
        // - 保存 ExtraAttr 引用以便后续通过物品恢复词条
        // - 根据词条类型（实数/整数/唯一）将数值累加到 YDHT 对应的键上
        static method ItemAddAttrsVal takes item it,ExtraAttr a,integer lv returns nothing
            call SaveInteger(ht,GetHandleId(it),ExtraAttr.typekey,a)
            if(a.isReal==1)then
                call SaveReal(YDHT,GetHandleId(it),a.attrhash,LoadReal(YDHT,GetHandleId(it),a.attrhash)+a.valReal[lv])
                return
            endif
            if(a.isReal==0 and a.unique==0)then
                call SaveInteger(YDHT,GetHandleId(it),a.attrhash,LoadInteger(YDHT,GetHandleId(it),a.attrhash)+a.val[lv])
                return
            endif
        endmethod

        // 返回该词条在指定物品上的可显示文本
        // 会根据物品稀有度读取对应等级值，唯一词条返回 description 字段
        method toStringByItem takes item it returns string
            local integer lv = LoadInteger(YDHT,GetHandleId(it),keyItemLvHash)
            if(unique>0)then
                return description
            else
                if(isReal>0)then
                    return name + "+" + R2S(valReal[lv-1])
                else
                    return name + "+" + I2S(val[lv-1])
                endif
            endif
        endmethod
        // 批量设置整数型词条的三个等级值，返回自身以支持链式调用
        method setManyValInt takes integer val1,integer val2,integer val3 returns ExtraAttr
            set val[1]=val1
            set val[2]=val2
            set val[3]=val3
            return this
        endmethod
        // 批量设置实数型词条的三个等级值，返回自身以支持链式调用
        method setManyValReal takes real val1,real val2,real val3 returns ExtraAttr
            set valReal[1]=val1
            set valReal[2]=val2
            set valReal[3]=val3
            return this
        endmethod

        // 设置整数型词条在指定等级 `lv` 的值
        method setValInt  takes  integer lv,integer value returns nothing
            set val[lv] = value
        endmethod

        // 设置实数型词条在指定等级 `lv` 的值
        method setValReal  takes  integer lv,real value returns nothing
            set valReal[lv] = value
        endmethod
        // 对单位 `u` 增加该唯一词条的计数（用于唯一效果计数管理）
        method addActionUnique takes unit u returns nothing
            call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)+1)
        endmethod
        // 对单位 `u` 减少该唯一词条的计数（在物品丢失或移除时调用）
        method loseActionUnique takes unit u returns nothing
            call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)-1)
        endmethod
        
        // 将词条的数值（按等级 lv）应用到单位 `u` 上（累加）
        method addExtraAttr takes unit u,integer lv returns nothing
            if(isReal==0)then
                call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)+val[lv-1])
            else
                call SaveReal(YDHT,GetHandleId(u),attrhash,LoadReal(YDHT,GetHandleId(u),attrhash)+valReal[lv-1])
            endif
        endmethod
        // 从单位 `u` 上移除/减少该词条的数值（按等级 lv）
        method reduceExtraAttr takes unit u,integer lv returns nothing
            if(isReal==0)then
                call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)-val[lv-1])
            else
                call SaveReal(YDHT,GetHandleId(u),attrhash,LoadReal(YDHT,GetHandleId(u),attrhash)-valReal[lv-1])
            endif
        endmethod
        
    endstruct

    struct ExtraAttrPool

        integer count =0
        ExtraAttr array attrs[40]
        // 将词条 `ea` 添加到当前池末尾
        method addAttr takes ExtraAttr ea returns nothing
            set count = count +1
            set attrs[count] = ea
        endmethod

        // 将另一个词条池 `poolB` 的词条合并到当前池中，避免重复
        // 实现：先把当前池的 attrhash 存入临时哈希，再遍历 poolB，仅将不存在的词条添加
        method addAttrsByPool takes ExtraAttrPool poolB returns nothing
            local integer i = 0
            local integer j = 0
            local integer key1 = StringHash("ExtraAttrPool")
            //遍历数组A，将数组A结构转化为哈希结构
            loop
                set i = i +1
                exitwhen i > count
                call SaveInteger(ht,key1,attrs[i].attrhash,1)
            endloop
            //遍历数组B，查询是否存在基于数组A转化的哈希内
            set i = 0
            loop
                set i = i +1
                exitwhen i > poolB.count
                if(HaveSavedInteger(ht,key1,poolB.attrs[i].attrhash) ==false) then
                    call addAttr(poolB.attrs[i])
                endif
            endloop
        endmethod

        // 设置池中第 `id` 个词条在等级 `lv` 的整数值
        method setValInt takes integer id, integer lv,integer value returns nothing
            call attrs[id].setValInt(lv,value)
        endmethod
        // 设置池中第 `id` 个词条在等级 `lv` 的实数值
        method setValReal takes integer id, integer lv,real value returns nothing
            call attrs[id].setValReal(lv,value)
        endmethod
        // 随机从池中选择并返回一个词条实例
        method getAttr takes nothing returns ExtraAttr
            return attrs[GetRandomInt(1,count)]
        endmethod
    endstruct

    // 当单位捡起物品时触发：将物品绑定的 ExtraAttr 应用到单位上
    // - 若词条为唯一类型，增加单位的唯一计数
    // - 否则按物品稀有度读取等级并将数值应用到单位
    private function addAction takes nothing returns nothing
        local unit u = GetTriggerUnit()
        local item it = GetManipulatedItem()
        local ExtraAttr attr = ExtraAttr.GetExtraAttrFromItem(it)
        debug call BJDebugMsg(I2S(attr))
        if(attr == 0 ) then
        set it = null
        set u =null
            return
        endif
        if(attr.unique==1) then
            call attr.addActionUnique(u)
        else
            call attr.addExtraAttr(u,LoadInteger(YDHT,GetHandleId(it),keyItemLvHash))
        endif
        set it = null
        set u =null
    endfunction
    
    // 当单位失去/丢弃物品时触发：撤销物品对应的词条效果
    // - 若为唯一词条，减少计数；否则按物品稀有度减少数值
    private function lostAction takes nothing returns nothing
        local unit u = GetTriggerUnit()
        local item it = GetManipulatedItem()
        local timer t = CreateTimer()
        local ExtraAttr attr = ExtraAttr.GetExtraAttrFromItem(it)
        if(attr == 0 ) then
            set it = null
            set u =null
            return
        endif
        if(attr.unique==1) then
            call attr.loseActionUnique(u)
        else
            call attr.reduceExtraAttr(u,LoadInteger(YDHT,GetHandleId(it),keyItemLvHash))
        endif
        // 若物品被删除，则延时销毁词条实例以排泄内存泄漏
        call SaveInteger(ht,GetHandleId(t),0,attr) 
        call SaveInteger(ht,GetHandleId(t),1,GetHandleId(it))
        call SaveItemHandle(ht,GetHandleId(t),2,it)
        call TimerStart(t,0.03,false,function timerAction)
        set t = null
        set it = null
        set u =null
    endfunction
    private function timerAction takes nothing returns nothing
        local timer t = GetExpiredTimer()
        local integer itAdrs = LoadInteger(ht,GetHandleId(t),1)
        local item it = LoadItemHandle(ht,GetHandleId(t),2)
        local ExtraAttr attr = LoadInteger(ht,GetHandleId(t),0)
        if(it == null ) then
            // 若物品被删除，则延时销毁词条实例以排泄内存泄漏
            call attr.destroy()
            call FlushChildHashtable(ht,itAdrs)
        endif
        call FlushChildHashtable(ht,GetHandleId(t))
        call DestroyTimer(t)
        set it = null
        set attr = null
        set t = null
    endfunction
    // 从指定词条池随机抽取一个词条并将其应用到物品 `it` 上
    public function ItemAddExtraAttrFromPool takes item it ,ExtraAttrPool pool returns nothing
        local integer lv = LoadInteger(YDHT,GetHandleId(it),keyItemLvHash)
        call ExtraAttr.ItemAddAttrsVal(it,pool.getAttr(),lv)
    endfunction
    
    // 从默认的 normal 词条池随机抽取并应用到物品 `it`
    public function ItemAddExtraAttrNormal takes item it returns nothing
        local integer lv = LoadInteger(YDHT,GetHandleId(it),keyItemLvHash)
        call ExtraAttr.ItemAddAttrsVal(it,normal.getAttr(),lv)
    endfunction


    /*
        等级2 3 4 法术加成
        等级2 3 4 闪避
        等级3 唯一 闪避回血
    */
    // 模块初始化：创建默认词条池、填充内置词条并注册物品拾取/丢失触发器
    private function init takes nothing returns nothing
        local integer Sy=0
        set  normal=ExtraAttrPool.create()
        call normal.addAttr(ExtraAttr.createRealAttr("法术加成").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createIntAttr("全属性").setManyValInt(15,30,45))
        call normal.addAttr(ExtraAttr.createRealAttr("闪避").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("移动速度").setManyValReal(20,50,80))
        call normal.addAttr(ExtraAttr.createRealAttr("攻击力").setManyValReal(50,100,150))
        call normal.addAttr(ExtraAttr.createRealAttr("护甲").setManyValReal(10,20,30))
        call normal.addAttr(ExtraAttr.createRealAttr("生命上限").setManyValReal(200,500,1000))
        call normal.addAttr(ExtraAttr.createRealAttr("魔法上限").setManyValReal(200,500,1000))
        call normal.addAttr(ExtraAttr.createRealAttr("攻击吸血").setManyValReal(5,8,11))
        call normal.addAttr(ExtraAttr.createRealAttr("伤害减免").setManyValReal(8,11,15))
        call normal.addAttr(ExtraAttr.createIntAttr("力量成长").setManyValInt(10,15,20))
        call normal.addAttr(ExtraAttr.createIntAttr("敏捷成长").setManyValInt(10,15,20))
        call normal.addAttr(ExtraAttr.createIntAttr("智力成长").setManyValInt(10,15,20))
        call normal.addAttr(ExtraAttr.createIntAttr("主属性成长").setManyValInt(10,15,20))
        call normal.addAttr(ExtraAttr.createIntAttr("全属性成长").setManyValInt(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("每秒回固定").setManyValReal(20,30,40))
        call normal.addAttr(ExtraAttr.createRealAttr("每秒回蓝固定").setManyValReal(20,30,40))
        call normal.addAttr(ExtraAttr.createIntAttr("力量").setManyValInt(20,50,100))
        call normal.addAttr(ExtraAttr.createIntAttr("敏捷").setManyValInt(20,50,100))
        call normal.addAttr(ExtraAttr.createIntAttr("智力").setManyValInt(20,50,100))
        call normal.addAttr(ExtraAttr.createIntAttr("主属性").setManyValInt(20,50,100))
        call normal.addAttr(ExtraAttr.createRealAttr("攻击速度").setManyValReal(20,40,80))
        call normal.addAttr(ExtraAttr.createRealAttr("伤害加成").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("物理加成").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("法术抗性").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("暴击抗性").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("冷却减免").setManyValReal(10,15,20))
        call normal.addAttr(ExtraAttr.createRealAttr("护甲穿透").setManyValReal(20,40,60))
        call normal.addAttr(ExtraAttr.createRealAttr("经验增幅").setManyValReal(10,20,30))

        //call normal.addAttr(ExtraAttr.createUniqueAttr("闪避回血","闪避伤害时，治疗自身5%最大生命值"))

		loop
			exitwhen Sy == 16
			call TriggerRegisterPlayerUnitEvent(trigGetItem, Player(Sy), ConvertPlayerUnitEvent(49), null)
			call TriggerRegisterPlayerUnitEvent(trigLossItem, Player(Sy), ConvertPlayerUnitEvent(48), null)
			set Sy = Sy + 1
		endloop
		call TriggerAddAction(trigGetItem,function addAction)
		call TriggerAddAction(trigLossItem,function lostAction)
    endfunction

endlibrary