
#include "YDWETriggerEvent.j"
#include "nncou\\NNCouInterface.j"

library DmgSyc initializer InitDmgSyc requires YDWETriggerEvent ,NNCouInterface,YDWEEventDamageData
    globals
        private boolean isDelayZero = false
        private trigger trigProcess = null
        private trigger trigBase = CreateTrigger()
        public unit dmgUnit = null
        public unit dmgSrc = null
        public real damage = 0.
        public integer dmgType = 0
        public boolean isMelee = false
        public boolean isAttack = false
        public boolean isRange = false //暂定，未使用
        //伤害类型
        private constant integer DMG_PHYPICS = 1
        private constant integer DMG_MAGIC = 2
        private constant integer DMG_TRUE = 3
        //JAPI地址
    	private constant integer EVENT_DAMAGE_DATA_VAILD       = 0
    	private constant integer EVENT_DAMAGE_DATA_IS_PHYSICAL = 1
    	private constant integer EVENT_DAMAGE_DATA_IS_ATTACK   = 2
    	private constant integer EVENT_DAMAGE_DATA_IS_RANGED   = 3
    	private constant integer EVENT_DAMAGE_DATA_DAMAGE_TYPE = 4
    	private constant integer EVENT_DAMAGE_DATA_WEAPON_TYPE = 5
    	private constant integer EVENT_DAMAGE_DATA_ATTACK_TYPE = 6
    endglobals

    //初始化
    public function SetT takes trigger trig returns nothing
        set trigProcess = trig
    endfunction
    
    //判断伤害类型是否一致Int
    public function CompareDamageType takes integer dType returns boolean
        //call BJDebugMsg(I2S(dmgType)+"..."+I2S(dType))
        return dmgType == dType
    endfunction

    //转换伤害类型
    private function ConventDamageType2Int takes damagetype damageType  returns integer
        local integer dType = 0
        if (damageType == DAMAGE_TYPE_UNKNOWN or damageType == DAMAGE_TYPE_UNIVERSAL)  then
            set dType = DMG_TRUE
        else
            if ( damageType == DAMAGE_TYPE_NORMAL or damageType == DAMAGE_TYPE_ENHANCED or damageType ==DAMAGE_TYPE_DEMOLITION or /*
            */ damageType == DAMAGE_TYPE_SLOW_POISON or damageType ==DAMAGE_TYPE_POISON or damageType ==DAMAGE_TYPE_DISEASE or damageType ==DAMAGE_TYPE_ACID) then
                set dType = DMG_PHYPICS
            else
                set dType = DMG_MAGIC
            endif
        endif
        return dType
    endfunction

    //0秒计时器处理反击
    private function DelayTimerAction takes nothing returns nothing
        local integer i = GetHandleId(GetExpiredTimer())
        set dmgSrc = LoadUnitHandle(nncouHT,i,1)
        set dmgUnit = LoadUnitHandle(nncouHT,i,2)
        set damage = LoadReal(nncouHT,i,3)
        set dmgType = LoadInteger(nncouHT,i,4)
        set isAttack = LoadBoolean(nncouHT,i,5)
        set isMelee = LoadBoolean(nncouHT,i,6)
        set isRange = LoadBoolean(nncouHT,i,7)
        set isDelayZero = true
        //call BJDebugMsg("ExecuteDelay:" + GetUnitName(dmgUnit))
        call TriggerExecute(trigProcess)
        call DestroyTimer(GetExpiredTimer())
    endfunction

    private function DmgSycDelayTimer takes unit src, unit tri, real damage, integer damageType, boolean isAttack, boolean isMelee, boolean isRange returns nothing
        local timer t = CreateTimer()
        local integer i = GetHandleId(t)
        call TimerStart(t,0,false,function DelayTimerAction)
        call SaveUnitHandle(nncouHT,i,1,src)
        call SaveUnitHandle(nncouHT,i,2,tri)
        call SaveReal(nncouHT,i,3,damage)
        call SaveInteger(nncouHT,i,4,damageType)
        call SaveBoolean(nncouHT,i,5,isAttack)
        call SaveBoolean(nncouHT,i,6,isMelee)
        call SaveBoolean(nncouHT,i,7,isRange)
        set t = null
    endfunction

    public function Release takes nothing returns nothing
        //call BJDebugMsg("release")
        set dmgUnit = null
        set dmgSrc = null
        set isRange = false
        //set isDelayZero = false
        // set atkTypeBase = null
        // set dmgTypeBase = null
        set dmgType = 0
    endfunction
    
    //===========================================================================
    //实体
    //===========================================================================
    private function Trig_DmgSystemActions takes nothing returns nothing
        local damagetype dmgTypeBase
        local integer dmgTypeInt = EXGetEventDamageData(EVENT_DAMAGE_DATA_DAMAGE_TYPE)
        if trigProcess == null then
            return
        endif

        //如果当前事件没结束就被再次触发，自动将其扔给0秒计时器
        /*
        if (dmgUnit != null) then
            // 正在运行，未进行排泄
            if((isDelayZero == false)) then
                call BJDebugMsg("Delay")
                call DmgSycDelayTimer(GetEventDamageSource(),GetTriggerUnit(),GetEventDamage(),dmgType,isAttack,isMelee,isRange)
                return
            endif
        else
            call DisplayTimedTextToPlayer(Player(0),0,0,60,"dmgUnit:null，伤害事件已结束")
        endif
        */
        //if isDelayZero == false then
        
            set dmgUnit = GetTriggerUnit()
            set dmgSrc = GetEventDamageSource()
            set damage = GetEventDamage()
            if(damage<0.1 or dmgTypeInt == -1)then
                return
            endif
            if( dmgType == 0 ) then
                // 普通攻击的处理
                set isAttack = true
                if( YDWEDistanceBetweenUnits(dmgSrc,dmgUnit)<200) then
                    set isMelee = true
                endif
                set dmgTypeBase = ConvertDamageType(dmgTypeInt)
                set dmgType = ConventDamageType2Int(dmgTypeBase)
            endif
        //else
        //    set isDelayZero = false
        //endif
        if( dmgUnit == null) then
            //call BJDebugMsg("return")
            call Release()
            return
        endif
        
        //call BJDebugMsg("Execute")
        call TriggerExecute(trigProcess)
        call Release()
    endfunction
    
    //===========================================================================
    private function InitDmgSyc takes nothing returns nothing
        call YDWESyStemAnyUnitDamagedRegistTrigger(trigBase)
        call TriggerAddAction(trigBase, function Trig_DmgSystemActions)
    endfunction
    
    //范围伤害
    public function DamageGroup takes unit src, group g, real amount, boolean attack, boolean ranged, attacktype attackType, damagetype damageType returns nothing
        local unit ut = null
        local group gt = CreateGroup()
        call GroupAddGroup(gt,g)
        loop
            set ut = FirstOfGroup(gt)
            exitwhen ut == null
            set isRange = true
            call UnitDamageTarget(src,ut,amount,attack,ranged,attackType,damageType,null)
            call GroupRemoveUnit(gt,ut)
        endloop
        call DestroyGroup(gt)
        set gt=null
    endfunction
    


    //===========================================================================
    //设置伤害类型等数据
    //===========================================================================


    function UnitDamageTargetHook takes unit whichUnit, widget target, real amount, boolean attack, boolean ranged, attacktype attackType, damagetype damageType, weapontype weaponType returns nothing
        set dmgType = ConventDamageType2Int(damageType)
        set isMelee = ranged
        set isAttack = attack
    endfunction
endlibrary
    