/*
    词条名：可以根据词条名找到该词条
    等级：提供不同的数值
    数据：被获取后储存于物品上。
    非数值型词条：应有指定的逆天自定义值
    词条起始等级：方便词条库随机时能随出该词条


*/

library ExtraAttr initializer init 
    globals
        private trigger trigGetItem =CreateTrigger()
        private trigger trigLossItem =CreateTrigger()
        private integer array attrsNormal[300]
        private integer count
        private ExtraAttrPool normal =ExtraAttrPool.create()
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

        static method createIntAttr takes string str returns thistype
            local thistype this = thistype.allocate()
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        static method createRealAttr takes string str returns thistype
            local thistype this = thistype.allocate()
            set isReal = 1
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        static method createUniqueAttr takes string str,string description returns thistype
            local thistype this = thistype.allocate()
            set unique = 1
            set name = str
            set attrhash = StringHash(str)
            return this
        endmethod

        static method GetExtraAttrFromItem takes item it returns ExtraAttr
            return LoadInteger(ht,GetHandleId(it),ExtraAttr.typekey)
        endmethod

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

        method toStringByItem takes item it returns string
            local integer lv = LoadInteger(YDHT,GetHandleId(it),StringHash("物品稀有度"))
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
        method setManyValInt takes integer val1,integer val2,integer val3 returns ExtraAttr
            set val[1]=val1
            set val[2]=val2
            set val[3]=val3
            return this
        endmethod
        method setManyValReal takes real val1,real val2,real val3 returns ExtraAttr
            set valReal[1]=val1
            set valReal[2]=val2
            set valReal[3]=val3
            return this
        endmethod

        method setValInt  takes  integer lv,integer value returns nothing
            set val[lv] = value
        endmethod

        method setValReal  takes  integer lv,real value returns nothing
            set valReal[lv] = value
        endmethod
        method addActionUnique takes unit u returns nothing
            call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)+1)
        endmethod
        method loseActionUnique takes unit u returns nothing
            call SaveInteger(YDHT,GetHandleId(u),attrhash,LoadInteger(YDHT,GetHandleId(u),attrhash)-1)
        endmethod
    endstruct

    struct ExtraAttrPool

        integer count =0
        ExtraAttr array attrs[40]
        method addAttr takes ExtraAttr ea returns nothing
            set count = count +1
            set attrs[count] = ea
        endmethod

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

        method setValInt takes integer id, integer lv,integer value returns nothing
            call attrs[id].setValInt(lv,value)
        endmethod
        method setValReal takes integer id, integer lv,real value returns nothing
            call attrs[id].setValReal(lv,value)
        endmethod
        method getAttr takes nothing returns ExtraAttr
            return attrs[GetRandomInt(1,count)]
        endmethod
    endstruct

    private function addAction takes nothing returns nothing
        local unit u = GetTriggerUnit()
        local item it = GetManipulatedItem()
        local ExtraAttr attr = ExtraAttr.GetExtraAttrFromItem(it)
        debug call BJDebugMsg(I2S(attr))
        if(attr.unique==1) then
            call attr.addActionUnique(u)
        endif
        set it = null
    endfunction
    
    private function lostAction takes nothing returns nothing
        local unit u = GetTriggerUnit()
        local item it = GetManipulatedItem()
        local ExtraAttr attr = ExtraAttr.GetExtraAttrFromItem(it)
        debug call BJDebugMsg(I2S(attr))
        if(attr.unique==1) then
            call attr.loseActionUnique(u)
        endif
        set it = null
    endfunction

    public function ItemAddExtraAttrFromPool takes item it ,ExtraAttrPool pool returns nothing
        local integer lv = LoadInteger(YDHT,GetHandleId(it),StringHash("物品稀有度"))
        call ExtraAttr.ItemAddAttrsVal(it,pool.getAttr(),lv)
    endfunction
    
    public function ItemAddExtraAttrNormal takes item it returns nothing
        local integer lv = LoadInteger(YDHT,GetHandleId(it),StringHash("物品稀有度"))
        call ExtraAttr.ItemAddAttrsVal(it,normal.getAttr(),lv)
    endfunction


    /*
        等级2 3 4 法术加成
        等级2 3 4 闪避
        等级3 唯一 闪避回血
    */
    private function init takes nothing returns nothing
        local integer Sy=0
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
        call normal.addAttr(ExtraAttr.createRealAttr("经验效率").setManyValReal(10,20,30))

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