#ifndef YDWEYDWEJapiScriptIncluded 
#include "japi/YDWEJapiScript.j"
#endif


// 用于为波次提供对应波次的怪物组以及从怪物组中提取怪物
library MonsterPool needs NNCouString,YDWEYDWEJapiScript

    globals
        private string EXTRA_TAG = ""
        private string BOSS_TAG = ""
        private MonsterPool array pool[99] 
        private integer monsterPoolCount = 0
    endglobals
    /*
        关卡组成					
        怪物波次	怪物池	怪物波次最迟出场时间	波次难度	关卡难度
                        
        怪物波次				
        1	每关怪物由2波以上怪物组成，一般为2-4波			
        2	当剩余怪物数值和小于该波次数值的30%时，如无特殊，刷新下一波的怪物			
        3	若怪物出场关卡与当前关卡的差大于3时，精英率调整为30%，大于5时，调整为100			
                        
        怪物波次最迟出场时间				
            若超时，忽略当前数值和，直接刷新下一波怪物。			
                        
        波次难度				
            第一波次难度为当前关卡难度的0.8			
            第2、3波为当前关卡难度的1.0			
            第四波为当前关卡难度的1.2			
                        
        关卡难度				
            每一关的标准关卡难度，需在初始化时设置完成			
            用于计算当前关卡出怪的数量与搭配			
                        
        单人模式				
            所有怪物下调30%血量，攻击力			
                        
        强化等级				
            HP参数	1.2		
            ATK参数	1.1		
            敌人生命变更为1.2^(lv+1)倍，攻击力提升1.1^(lv+1)倍			
                        
        全局难度				
            全局难度的提升会让关卡与强化等级的曲线更为陡峭			

    
    */

    /*
        仅包含怪物基本信息
    */
    struct Monster
        integer id = 0
        integer difficulty = 0
        integer monsterType = 0 // 0:normal 1:extra 2:boss
        integer isMelee = 1 // 1:近战 0:远程
        static method create takes integer id, integer difficulty, integer monsterType, integer isMelee returns Monster
            local Monster m = Monster.allocate()
            set m.id = id
            set m.difficulty = difficulty
            set m.monsterType = monsterType
            set m.isMelee = isMelee
            return m
        endmethod
    endstruct

    struct MonsterPool
        private integer minLv = 0 // 最低出场关卡限制
        private integer maxlv = 99 //最高出场关卡限制
        private Monster array mon[7] // 怪物类型
        private integer count = 0 // 怪物种类数
        private integer array weight[7]
        private integer hasMelee = 0 // 是否包含近战怪物 1:包含 0:不包含
        private integer hasRanged = 0 // 是否包含远程怪物 1:包含 0:不包含
        private integer totalDift
        private integer avgDift = 0
        static method create takes integer minLv, integer maxLv returns MonsterPool
            local MonsterPool mg = MonsterPool.allocate()
            set mg.minLv = minLv
            set mg.maxlv = maxLv
            return mg
        endmethod
        method addMonster takes Monster monster, integer weight returns nothing
            if this.count >= 7 then
                return
            endif
            set this.mon[this.count] = monster
            set this.weight[this.count] = weight
            set this.count = this.count + 1
            if monster.isMelee == 1 then
                set this.hasMelee = 1
            else
                set this.hasRanged = 1
            endif
            set totalDift = totalDift + monster.difficulty
            set avgDift = totalDift / count
            debug call BJDebugMsg("添加怪物到怪物池，怪物ID为：" + I2S(monster.id) + "，当前怪物池平均难度为：" + I2S(avgDift))
        endmethod

        // 根据怪物类型随机获取一个怪物,一般不能获取Boss类型的怪物
        method getMonsterByMonsterLevel takes integer monsterType returns Monster
            local integer totalWeight = 0
            local integer i = 0
            local integer randWeight = 0
            local integer cumulativeWeight = 0
            loop 
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType then
                    set totalWeight = totalWeight + this.weight[i]
                endif
                set i = i + 1
            endloop
            if totalWeight <= 0 then
                return -1
            endif
            set randWeight = GetRandomInt(1, totalWeight)
            set i = 0
            loop
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType then
                    set cumulativeWeight = cumulativeWeight + this.weight[i]
                    if randWeight <= cumulativeWeight then
                        return this.mon[i]
                    endif
                endif
                set i = i + 1
            endloop
            return -1
        endmethod
        static method checkLv takes MonsterPool mg, integer level returns boolean
            if level < mg.minLv then
                return false
            endif
            if level > mg.maxlv then
                return false
            endif
            return true 
        endmethod
        // 获取指定类型的近战怪物
        method getMeleeMonsterByType takes integer monsterType returns Monster
            local integer totalWeight = 0
            local integer i = 0
            local integer randWeight = 0
            local integer cumulativeWeight = 0
            if(hasMelee == 0)then
                return -1
            endif
            loop 
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType and this.mon[i].isMelee == 1 then
                    set totalWeight = totalWeight + this.weight[i]
                endif
                set i = i + 1
            endloop
            if totalWeight <= 0 then
                return -1
            endif
            set randWeight = GetRandomInt(1, totalWeight)
            set i = 0
            loop
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType and this.mon[i].isMelee == 1 then
                    set cumulativeWeight = cumulativeWeight + this.weight[i]
                    if randWeight <= cumulativeWeight then
                        return this.mon[i]
                    endif
                endif
                set i = i + 1
            endloop
            return -1
        endmethod

        //获取指定类型的远程怪物
        method getRangeMonsterByType takes integer monsterType returns Monster
            local integer totalWeight = 0
            local integer i = 0
            local integer randWeight = 0
            local integer cumulativeWeight = 0
            if(hasRanged == 0)then
                return -1
            endif
            loop 
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType and this.mon[i].isMelee == 0 then
                    set totalWeight = totalWeight + this.weight[i]
                endif
                set i = i + 1
            endloop
            if totalWeight <= 0 then
                return -1
            endif
            set randWeight = GetRandomInt(1, totalWeight)
            set i = 0
            loop
                exitwhen i >= this.count
                if this.mon[i].monsterType == monsterType and this.mon[i].isMelee == 0 then
                    set cumulativeWeight = cumulativeWeight + this.weight[i]
                    if randWeight <= cumulativeWeight then
                        return this.mon[i]
                    endif
                endif
                set i = i + 1
            endloop
            return -1
        endmethod
    endstruct


    /*
        [MonsterPool_GetMonsterPoolByDifficulty]
        title = "根据难度获取怪物池(随机)"
        description = "根据${难度}获取随机怪物池 "
        category = TC_FRO
        returns = integer
        [[.args]]
        type = integer
    */
    public function GetMonsterPoolByDifficulty takes integer difficulty returns integer
        local integer i = 1
        local integer suitableCount = 0
        local integer chosenPool = -1
        // JASS 不保证局部数组语法跨编译器可用，使用蓄水池抽样选取随机元素
        loop
            exitwhen i > monsterPoolCount
            if (MonsterPool.checkLv(pool[i], difficulty)) then
                set suitableCount = suitableCount + 1
                if GetRandomInt(1, suitableCount) == 1 then
                    set chosenPool = i
                endif
            endif
            set i = i + 1
        endloop
        if suitableCount == 0 then
            debug call BJDebugMsg("没有找到合适的怪物池，难度值：" + I2S(difficulty))
            return -1
        endif
        return chosenPool
    endfunction
    
    /*
        [MonsterPool_CreateMonsterPool]
        title = "创建怪物池"
        description = "创建一个怪物池，允许难度下限为：${min}，允许难度上限为：${max} "
        category = TC_FRO
        returns = integer
        [[.args]]
        type = integer
        [[.args]]
        type = integer
    */
    public function CreateMonsterPool takes integer min,integer max returns integer
        local MonsterPool mg = MonsterPool.create(min,max)
        set monsterPoolCount = monsterPoolCount + 1
        set pool[monsterPoolCount] = mg
        return monsterPoolCount
    endfunction

    
    /*
        [MonsterPool_AddMonsterToPoolByPoolId]
        title = "添加怪物到池中"
        description = "将${指定ID}的怪物添加到${指定ID}的怪物池中，难度值为：${difficulty} "
        category = TC_FRO
        [[.args]]
        type = integer
        [[.args]]
        type = integer
        [[.args]]
        type = integer
    */
    public function AddMonsterToPoolByPoolId takes integer monsterId, integer mgId, integer difficulty returns nothing
        local Monster m = 0
        local integer isExtra =0
        local integer isMelee = 0
        local string abilList = YDWEGetObjectPropertyString( YDWE_OBJECT_TYPE_UNIT, monsterId, "abilList")
        if(NNCFind(abilList,EXTRA_TAG)==1)then
            set isExtra = 1 
        endif
        if(NNCFind(abilList,BOSS_TAG)==1)then
            set isExtra = 2
        endif
        if(YDWEGetObjectPropertyReal( YDWE_OBJECT_TYPE_UNIT, monsterId, "rangeN1")>300) then
            set isMelee = 1
        endif
        set m = Monster.create(monsterId,difficulty,isExtra,isMelee)
        call pool[mgId].addMonster(m,100)
        set m = 0
    endfunction


    /*
        [MonsterPool_GetMonsterFromPool]
        title = "从怪物池中获取怪物"
        description = "从${指定ID}号怪物池中获取${指定类型}的怪物 "
        comment = "0:normal 1:extra 2:boss"
        category = TC_FRO
        returns = unitcode
        [[.args]]
        type = integer
        [[.args]]
        type = integer
        default = 0
    */
    public function GetMonsterFromPool takes integer mgId, integer monsterType returns integer
        local integer monsterId = pool[mgId].getMonsterByMonsterLevel(monsterType).id
        debug call BJDebugMsg("从怪物池中获取怪物，怪物ID为：" + I2S(monsterId))
        return monsterId
    endfunction



endlibrary