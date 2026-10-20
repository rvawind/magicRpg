<?local slk = require 'slk' ?>


library FuncItemSystem initializer Init
	
#define ITEM_SYSTEM_TEXT_TIP          0x2D0B95E0  	//物品说明
#define ITEM_SYSTEM_TIP_EX            0xDF540809    //物品描述

#define ITEM_SYSTEM_FULL_ATTRIBUTE 0x353BD8A6     	//全属性
#define ITEM_SYSTEM_VIOLENT_ATTACK 0x7AFB5C07     	//暴击伤害
#define ITEM_SYSTEM_STRIKE_CHANCE 0x33D20D36      	//暴击几率
#define ITEM_SYSTEM_CYCLIC_PROPERTIES 0x28ECE0C5  	//属性
#define ITEM_SYSTEM_STRIKE_PROPERTY 0x944BBB75   	//杀敌属性
#define ITEM_SYSTEM_ATTACK_ATTRIBUTES 0xC5205E20 	//普攻属性
#define ITEM_SYSTEM_AGGRESSIVITY 0x301CC1D8       	//攻击力
#define ITEM_SYSTEM_ARMOR 0x40536706              	//护甲
#define ITEM_SYSTEM_VALUE_OF_LIFE HPMAX            	//生命上限

#define ITEM_SYSTEM_VALUE_OF_MANA MPMAX             //魔法上限
#define ITEM_SYSTEM_BLOOD_SUCKING 0x030F8459      	//攻击吸血
#define ITEM_SYSTEM_DAMAGE_RESISTANCE 0x5AF44D77  	//伤害减免
#define ITEM_SYSTEM_STR_GROW STR_GROW //力量成长
#define ITEM_SYSTEM_AGI_GROW AGI_GROW //敏捷成长
#define ITEM_SYSTEM_INT_GROW INT_GROW //智力成长
#define ITEM_SYSTEM_PRIMARY_GROW PRIMARY_GROW //主属性成长
#define ITEM_SYSTEM_ALL_GROW ALL_GROW //全属性成长
	globals
		//0x数字为字符串的哈希值，所以
        //也可用下面这种写法，只是会比上面的写法耗费更多一点的资源
        private integer CIRCULATING_BLOOD = StringHash("每秒回百分比")  //每秒回血
        private integer CIRCULATING_BLOOD1 = StringHash("每秒回损失")  //每秒回血
        private integer CIRCULATING_BLOOD2 = StringHash("每秒回固定")  //每秒回血
        private integer CIRCULATING_Mana = StringHash("每秒回蓝百分比")  //每秒回血
        private integer CIRCULATING_Mana1 = StringHash("每秒回蓝损失")  //每秒回血
        private integer CIRCULATING_Mana2 = StringHash("每秒回蓝固定")  //每秒回血
        private integer STR_ATTRIBUTE = StringHash("力量")  //力量
        private integer AGI_ATTRIBUTE = StringHash("敏捷")  //敏捷    
        private integer INT_ATTRIBUTE = StringHash("智力")  //智力
        private integer MAIN_ATTRIBUTE = StringHash("主属性")  //主属性
        private integer ATK_SPEED = StringHash("攻击速度")  //攻击速度
        private integer DAMAGE_ADDEX = StringHash("伤害加成")  //伤害加成
        private integer PHYCICS_REDUCE = StringHash("物理抗性")  //物理抗性
        private integer PHYCICS_ADDEX = StringHash("物理加成")  //物理加成
        private integer MAGIC_REDUCE = StringHash("法术抗性")  //法术抗性
        private integer MAGIC_ADDEX = StringHash("法术加成")  //法术加成
        private integer STRIKE_REDUCE = StringHash("暴击抗性")  //暴击抗性
        private integer COOLDOWN = StringHash("冷却减免")  //冷却减免
        private integer PHYCICS_IGNORE = StringHash("护甲穿透")  //护甲穿透
        private integer EXP_ADD = StringHash("经验增幅")  //经验增幅
        private integer ATTACK_INTERVAL = StringHash("攻击间隔")  //攻击间隔
        private integer COOLDOWN_UPLIMIT = StringHash("冷却上限")  //冷却上限
        private integer DMG_REDUCE_UPLIMIT = StringHash("减伤上限")  //减伤上限
        
        private integer HPMAX = StringHash("生命上限")
        private integer MPMAX = StringHash("魔法上限")
        private integer STRIKE = StringHash("暴击")
        private integer DMG_REMIX = StringHash("伤害修正")
        private integer MOVE_SPEED = StringHash("移动速度")
        
        private integer RANGED_ATK_EX = StringHash("远程攻击伤害")
        private integer MELEE_ATK_EX = StringHash("近战攻击伤害")
        
        
        private integer MAGIC_BULLET_MAX = StringHash("魔弹上限")
        private integer MAGIC_BULLET_VAL = StringHash("魔弹数量")
        
        private integer POW_MAX = StringHash("气力上限")
        private integer POW_VAL = StringHash("气力值")
        
        private integer STR_GROW = StringHash("力量成长")
        private integer AGI_GROW = StringHash("敏捷成长")
        private integer INT_GROW = StringHash("智力成长")
        private integer PRIMARY_GROW = StringHash("主属性成长")
        private integer ALL_GROW = StringHash("全属性成长")
        
        private integer ATTACK_STRIKE = StringHash("攻击暴伤")
        private integer SKILL_STRIKE = StringHash("技能暴伤")
        
        private integer PRIMARY = StringHash("主属性")
        private integer CARDSKILLS = StringHash("对应技能")
        private integer CARDITEMS = StringHash("对应物品")


		public hashtable Skill = InitHashtable()
		public hashtable Item = InitHashtable()
		private trigger array trg
	endglobals


private function ItemIsCard takes integer itemid returns boolean
    //使用JAPI，根据物品是否能量提升，及物品等级不为0，返回true/false
    if(((YDWEGetObjectPropertyString( YDWE_OBJECT_TYPE_ITEM, itemid, "class")) == "PowerUp") \
            and (YDWEGetObjectPropertyInteger( YDWE_OBJECT_TYPE_ITEM, itemid, "Level")) != 0) then
        return true
    endif
    return false
endfunction
    
private function InCard takes nothing returns nothing
    

    <?
        local count = 0
        local orderStrings = {}
        
        orderStrings[0] = "absorb"
        orderStrings[1] = "acidbomb"
        orderStrings[2] = "acolyteharvest"
        orderStrings[3] = "whirlwind"
        orderStrings[4] = "ambush"
        orderStrings[5] = "ancestralspirit"
        orderStrings[6] = "ancestralspirittarget"
        orderStrings[7] = "animatedead"
        orderStrings[8] = "antimagicshell"
        orderStrings[9] = "webon"
        orderStrings[10] = "weboff"
        orderStrings[11] = "web"
        orderStrings[12] = "attributemodskill"
        orderStrings[13] = "auraunholy"
        orderStrings[14] = "auravampiric"
        orderStrings[15] = "autodispel"
        orderStrings[16] = "autodispeloff"
        orderStrings[17] = "autodispelon"
        orderStrings[18] = "autoentangle"
        orderStrings[19] = "autoentangleinstant"
        orderStrings[20] = "wateryminion"
        orderStrings[21] = "waterelemental"
        orderStrings[22] = "avatar"
        orderStrings[23] = "avengerform"
        orderStrings[24] = "awaken"
        orderStrings[25] = "banish"
        orderStrings[26] = "barkskin"
        orderStrings[27] = "barkskinoff"
        orderStrings[28] = "barkskinon"
        orderStrings[29] = "battleroar"
        orderStrings[30] = "battlestations"
        orderStrings[31] = "bearform"
        orderStrings[32] = "berserk"
        orderStrings[33] = "blackarrow"
        orderStrings[34] = "blackarrowoff"
        orderStrings[35] = "blackarrowon"
        orderStrings[36] = "blight"
        orderStrings[37] = "blink"
        orderStrings[38] = "blizzard"
        orderStrings[39] = "bloodlust"
        orderStrings[40] = "bloodlustoff"
        
    for id, obj in pairs(slk.item) do
        local ubertip = obj.ubertip
        local Desc = obj.description
        local TipEx = Desc or ''
        local Tip = ubertip or ''
        local Class = obj.class or ''
        local Level = obj.level or 0
        local name = obj.Name or ''
        local TipS = obj.Tip or ''
        local Art = obj.Art or ''
        if id >= 'I000' then
        if id <= 'I999' then
        if Class=="PowerUp" then
            if Level >0 then
                local ActiveStr = string.find(Tip, "主动-") or string.find(Tip, "使用该技能")
                
                if ActiveStr ~= nil then
                    t_skill = slk.ability.ANcl:new(TipEx..id)
                        
                        t_skill.Name = name
                        t_skill.Tip = TipS
                        t_skill.ubertip = TipEx
                        t_skill.Art = Art
                        t_skill.editorSuffix = "卡片-主动"
                        t_skill.dataA1 = 0
                        t_skill.dataB1 = 0
                        t_skill.dataC1 = 1
                        t_skill.dataD1 = 0
                        t_skill.dataE1 = 0
                        t_skill.dataF1 = orderStrings[count]
                        t_skill.order = orderStrings[count]
                        t_skill.Buttonpos = 0
                        t_skill.Buttonpos2 = 0
                        t_skill.Cool1 = 2
                        t_skill.race = commoner
                        t_skill.hero = 0
                        t_skill.levels = 1
                        
                        if t_skill:get_id() ~= '' then
                        ?>
                            
                            call SaveInteger(YDHT,'<?=id?>',CARDSKILLS,'<?= t_skill:get_id() ?>')
                            call SaveInteger(YDHT,'<?= t_skill:get_id() ?>',CARDITEMS,'<?=id?>')
                            
                        <?
                            count = count +1
                            --print(id)
                            --print(t_skill:get_id())
                        else
                            print(id.."ERROR")
                        end
                        
                    print(id.."\""..name.."\"..True.."..t_skill:get_id())
                    table.insert(slk.ability,t_skill)
                end
                if ActiveStr == nil then
                    --print(id..name.."..nil")
                    t_skill = slk.ability.ACbh:new(TipEx..id)
                        t_skill.Name = name
                        t_skill.Tip = TipS
                        t_skill.ubertip = TipEx
                        t_skill.editorSuffix = "卡片-被动"
                        t_skill.Art = Art
                        t_skill.dataA = 0
                        t_skill.race = commoner
                        t_skill.Buttonpos = 0
                        t_skill.Buttonpos2 = 0
                        if t_skill:get_id() ~= '' then
                        ?>
                            
                            call SaveInteger(YDHT,'<?=id?>',CARDSKILLS,'<?= t_skill:get_id() ?>')
                            call SaveInteger(YDHT,'<?= t_skill:get_id() ?>',CARDITEMS,'<?=id?>')
                            
                        <?
                            --print(t_skill:get_id())
                        else
                            print(id.."ERROR")
                        end
                    table.insert(slk.ability,t_skill)
                end
            end
        end
        end
        end
    end?>
    call BJDebugMsg("...注册卡片完成")
endfunction
    
private function InUnit takes nothing returns nothing
    
    <?
        local num = 0
        for id, obj in pairs(slk.unit) do
            local Primary = obj.Primary or ''
            local name = obj.name or ''
            --print(num)
    ?>
            <?if Primary == "STR" then?>
                call SaveInteger(YDHT,'<?=id?>',PRIMARY,1)
                <?print(id..name)
                num= num +1?>
            <?end?>
            
            <?if Primary == "AGI" then?>
                call SaveInteger(YDHT,'<?=id?>',PRIMARY,2)
                <?print(id..name)
                num= num +1?>
            <?end?>
            
            <?if Primary == "INT" then?>
                call SaveInteger(YDHT,'<?=id?>',PRIMARY,3)
                <?print(id..name)
                num= num +1?>
            <?end?>
    <?end?>
    call BJDebugMsg("注册单位完成")
    
endfunction
                
                    
    
private function InItem takes nothing returns nothing
		/*
		物品描述例子：
		攻击力+10000
		护甲+100
		生命值+100000
		全属性+3000
		暴击+5.5倍
		暴击几率+5%
		吸血+1%
		伤害减免+20%
		每秒属性+100
		每秒回血+1%
		杀敌属性+50
		普攻属性+10
		以上为一段描述的文本内容例子
		其中类型为实数的，是可以使用小数点的，在描述数值的时候可以使用整数，也可以使用实数。
		而如果类型为整数的话，那么默认是只会捕捉到里面整数，如果出现实数，那么只会捕捉小数点前面的那些整数。
		*/
                    /* 正则表达式
					" *" = " "可以出现N次
                    "%d" = 任意数字字符
                    "%." = "."，意味实数
                    "+"  = "+"前的字符出现尽可能多次。例如："%d+" 意味
                    "[]" = 里面取的字符其中一个成立
                    
                    PS：%d作为一个字符，+、*等不视为字符
                    */				
		<?
			for id, obj in pairs(slk.item) do
				local ubertip = obj.ubertip
                local Desc = obj.description
                local TipEx = Desc or ''
				local Tip = ubertip or ''
                local Class = obj.class or ''
                local Level = obj.level or 0
                local name = obj.Name or ''
                local TipS = obj.Tip or ''
                local Art = obj.Art or ''
				local GJL = string.match(Tip,"攻击力 *%+? *([%d%.]+)")--实数
				local HJ = string.match(Tip,"护甲 *%+? *([%d%.]+)")--实数
				local SMZ = string.match(Tip,"生命上限 *%+? *([%d%.]+)")--实数
				local MFZ = string.match(Tip,"魔法上限 *%+? *([%d%.]+)")--实数
				local QSX = string.match(Tip,"全属性.(%d+)")--整数
				local BJ = string.match(Tip,"暴击伤害 *%+? *([%d%.]+)")--实数
				local BJGL = string.match(Tip,"暴击几率 *%+? *([%d%.]+)")--实数
				local XiXue = string.match(Tip,"攻击吸血 *%+? *([%d%.]+)")--实数
				local JianShang = string.match(Tip,"伤害减免 *%+? *([%d%.]+)")--实数
				local Meimiaoshuxing = string.match(Tip,"每秒属性.(%d+)")--整数
				local Meimiaohuixue = string.match(Tip,"每秒回血% *%+? *([%d%.]+)")--实数
				local Shadishuxing = string.match(Tip,"杀敌属性.(%d+)")--整数
				local Pugongshuxing = string.match(Tip,"普攻属性.(%d+)")--整数
                
				local Liliangchengzhang = string.match(Tip,"力量成长.(%d+)")--整数
				local Minjiechengzhang = string.match(Tip,"敏捷成长.(%d+)")--整数
				local Zhilichengzhang = string.match(Tip,"智力成长.(%d+)")--整数
				local Quanshuxingchengzhang = string.match(Tip,"全属性成长.(%d+)")--整数
				local Zhushuxingchengzhang = string.match(Tip,"主属性成长.(%d+)")--整数
                
				local STR = string.match(Tip,"力量.(%d+)")--整数
				local AGI = string.match(Tip,"敏捷.(%d+)")--整数
				local INT = string.match(Tip,"智力.(%d+)")--整数
				local ZSX = string.match(Tip,"主属性.(%d+)")--整数
				local GJSD = string.match(Tip,"攻击速度 *%+? *([%d%.]+)")--实数
				local SHJC = string.match(Tip,"伤害加成 *%+? *([%d%.]+)")--实数
				local WLKX = string.match(Tip,"物理抗性 *%+? *([%d%.]+)")--实数
				local WLJC = string.match(Tip,"物理加成 *%+? *([%d%.]+)")--实数
				local FSKX = string.match(Tip,"法术抗性 *%+? *([%d%.]+)")--实数
				local FSJC = string.match(Tip,"法术加成 *%+? *([%d%.]+)")--实数
				local BJKX = string.match(Tip,"暴击抗性 *%+? *([%d%.]+)")--实数
				local LQJM = string.match(Tip,"冷却减免 *%+? *([%d%.]+)")--实数
				local HJCT = string.match(Tip,"护甲穿透 *%+? *([%d%.]+)")--实数
				local JYXL = string.match(Tip,"经验效率 *%+? *([%d%.]+)")--实数
				local GJJG = string.match(Tip,"攻击间隔 *%-? *([%d%.]+)")--实数
				local LQSX = string.match(Tip,"冷却上限 *%+? *([%d%.]+)")--实数
				local JSSX = string.match(Tip,"减伤上限 *%+? *([%d%.]+)")--实数
				local FLHFGD = string.match(Tip,"法力回复 *%+? *([%d%.]+)")--实数
                
				local BJ = string.match(Tip,"暴击.(%d+)")--整数
				local MDSX = string.match(Tip,"魔弹上限.(%d+)")--整数
				local QLSX = string.match(Tip,"气力上限.(%d+)")--整数
				local SHXZ = string.match(Tip,"伤害修正 *%+? *([%d%.]+)")--实数
				local YDSD = string.match(Tip,"移动速度 *%+? *([%d%.]+)")--实数
                local YCGJ = string.match(Tip,"远程攻击伤害 *%+? *([%d%.]+)")--实数
                local JZGJ = string.match(Tip,"近战攻击伤害 *%+? *([%d%.]+)")--实数
                
                
        
		?>
            //物品提示扩展
			<?if Tip ~= '' then?>
                call SaveStr(Item,'<?=id?>',ITEM_SYSTEM_TEXT_TIP,"<?=Tip?>")
			<?end?>
            //物品说明
			<?if Tip ~= '' then?>
                call SaveStr(Item,'<?=id?>',ITEM_SYSTEM_TIP_EX,"<?=TipEx?>")
			<?end?>
        
        
        
        
            //将物品的属性写入 key1为物品ID ，key2 为属性项的哈希表ITEM
			<?if BJ ~= nil then?>
                call SaveInteger(Item,'<?=id?>',STRIKE,<?=BJ?>)
			<?end?>
			<?if MDSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',MAGIC_BULLET_MAX,<?=MDSX?>)
			<?end?>
			<?if QLSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',POW_MAX,<?=QLSX?>)
			<?end?>
			<?if SHXZ ~= nil then?>
                call SaveReal(Item,'<?=id?>',DMG_REMIX,<?=SHXZ?>)
			<?end?>
			<?if YDSD ~= nil then?>
                call SaveReal(Item,'<?=id?>',MOVE_SPEED,<?=YDSD?>)
			<?end?>
            
            
			<?if STR ~= nil then?>
                call SaveInteger(Item,'<?=id?>',STR_ATTRIBUTE,<?=STR?>)
			<?end?>
			<?if AGI ~= nil then?>
                call SaveInteger(Item,'<?=id?>',AGI_ATTRIBUTE,<?=AGI?>)
			<?end?>
			<?if INT ~= nil then?>
                call SaveInteger(Item,'<?=id?>',INT_ATTRIBUTE,<?=INT?>)
			<?end?>
			<?if ZSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',MAIN_ATTRIBUTE,<?=ZSX?>)
			<?end?>
			<?if GJSD ~= nil then?>
                call SaveReal(Item,'<?=id?>',ATK_SPEED,<?=GJSD?>)
			<?end?>
			<?if SHJC ~= nil then?>
                call SaveReal(Item,'<?=id?>',DAMAGE_ADDEX,<?=SHJC?>)
			<?end?>
			<?if WLKX ~= nil then?>
                call SaveReal(Item,'<?=id?>',PHYCICS_REDUCE,<?=WLKX?>)
			<?end?>
			<?if WLJC ~= nil then?>
                call SaveReal(Item,'<?=id?>',PHYCICS_ADDEX,<?=WLJC?>)
			<?end?>
			<?if FSKX ~= nil then?>
                call SaveReal(Item,'<?=id?>',MAGIC_REDUCE,<?=FSKX?>)
			<?end?>
			<?if FSJC ~= nil then?>
                call SaveReal(Item,'<?=id?>',MAGIC_ADDEX,<?=FSJC?>)
			<?end?>
			<?if BJKX ~= nil then?>
                call SaveReal(Item,'<?=id?>',STRIKE_REDUCE,<?=BJKX?>)
			<?end?>
			<?if LQJM ~= nil then?>
                call SaveReal(Item,'<?=id?>',COOLDOWN,<?=LQJM?>)
			<?end?>
			<?if HJCT ~= nil then?>
                call SaveReal(Item,'<?=id?>',PHYCICS_IGNORE,<?=HJCT?>)
			<?end?>
			<?if JYXL ~= nil then?>
                call SaveReal(Item,'<?=id?>',EXP_ADD,<?=JYXL?>)
			<?end?>
			<?if GJJG ~= nil then?>
                call SaveReal(Item,'<?=id?>',ATTACK_INTERVAL,<?=GJJG?>)
			<?end?>
			<?if LQSX ~= nil then?>
                call SaveReal(Item,'<?=id?>',COOLDOWN_UPLIMIT,<?=LQSX?>)
			<?end?>
			<?if JSSX ~= nil then?>
                call SaveReal(Item,'<?=id?>',DMG_REDUCE_UPLIMIT,<?=JSSX?>)
			<?end?>
			<?if GJL ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_AGGRESSIVITY,<?=GJL?>)
			<?end?>
			<?if HJ ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_ARMOR,<?=HJ?>)
			<?end?>
			<?if SMZ ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_VALUE_OF_LIFE,<?=SMZ?>)
			<?end?>
			<?if MFZ ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_VALUE_OF_MANA,<?=MFZ?>)
			<?end?>
			<?if QSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_FULL_ATTRIBUTE,<?=QSX?>)
			<?end?>
			<?if BJ ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_VIOLENT_ATTACK,<?=BJ?>)
			<?end?>
			<?if BJGL ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_STRIKE_CHANCE,<?=BJGL?>)
			<?end?>
			<?if XiXue ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_BLOOD_SUCKING,<?=XiXue?>)
			<?end?>
			<?if JianShang ~= nil then?>
                call SaveReal(Item,'<?=id?>',ITEM_SYSTEM_DAMAGE_RESISTANCE,<?=JianShang?>)
			<?end?>
			<?if Meimiaoshuxing ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_CYCLIC_PROPERTIES,<?=Meimiaoshuxing?>)
			<?end?>
			<?if Meimiaohuixue ~= nil then?>
                call SaveReal(Item,'<?=id?>',CIRCULATING_BLOOD,<?=Meimiaohuixue?>)
			<?end?>
			<?if Shadishuxing ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_STRIKE_PROPERTY,<?=Shadishuxing?>)
			<?end?>
			<?if Pugongshuxing ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_ATTACK_ATTRIBUTES,<?=Pugongshuxing?>)
			<?end?>
			<?if Liliangchengzhang ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_STR_GROW,<?=Liliangchengzhang?>)
			<?end?>
			<?if Minjiechengzhang ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_AGI_GROW,<?=Minjiechengzhang?>)
			<?end?>
			<?if Zhilichengzhang ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_INT_GROW,<?=Zhilichengzhang?>)
			<?end?>
			<?if Zhushuxingchengzhang ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_PRIMARY_GROW,<?=Zhushuxingchengzhang?>)
			<?end?>
			<?if Quanshuxingchengzhang ~= nil then?>
                call SaveInteger(Item,'<?=id?>',ITEM_SYSTEM_ALL_GROW,<?=Quanshuxingchengzhang?>)
			<?end?>
            
            
			<?if FLHFGD ~= nil then?>
                call SaveReal(Item,'<?=id?>',CIRCULATING_Mana2,<?=FLHFGD?>)
			<?end?>
			<?if YCGJ ~= nil then?>
                call SaveReal(Item,'<?=id?>',RANGED_ATK_EX,<?=YCGJ?>)
			<?end?>
			<?if JZGJ ~= nil then?>
                call SaveReal(Item,'<?=id?>',MELEE_ATK_EX,<?=JZGJ?>)
			<?end?>
        
		<?end?> //结束for循环
        call BJDebugMsg("注册物品完成")
	endfunction

    
    private function YDWEId2S takes integer value returns string
    local string charMap=bj_AllString
    local string result = ""
    local integer remainingValue = value
    local integer charValue
    local integer byteno
    set byteno = 0
    loop
        set charValue = ModuloInteger(remainingValue, 256)
        set remainingValue = remainingValue / 256
        set result = SubString(charMap, charValue, charValue + 1) + result
        set byteno = byteno + 1
        exitwhen byteno == 4
    endloop
    return result
endfunction


	private function trg0Ac takes nothing returns nothing
		///获得物品触发器，攻击力 护甲 生命值 获得之后直接添加，其他的给操作物品单位绑定值、
        local unit u = GetManipulatingUnit()
        local item it = GetManipulatedItem()
		local real GJL = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_AGGRESSIVITY)
		local real HJ = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_ARMOR)
		local real SMZ = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_VALUE_OF_LIFE)
		local real MP = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_VALUE_OF_MANA)
		local integer QSX = LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_FULL_ATTRIBUTE)
		local integer STR = LoadInteger(Item,GetItemTypeId(it),STR_ATTRIBUTE)
		local integer AGI = LoadInteger(Item,GetItemTypeId(it),AGI_ATTRIBUTE)
		local integer INT = LoadInteger(Item,GetItemTypeId(it),INT_ATTRIBUTE)
        local integer ZSX = LoadInteger(Item,GetItemTypeId(it),MAIN_ATTRIBUTE)
        local real GJSD = LoadReal(Item,GetItemTypeId(it),ATK_SPEED)
        local real GJJG = LoadReal(Item,GetItemTypeId(it),ATTACK_INTERVAL)
        local real YDSD = LoadReal(Item,GetItemTypeId(it),MOVE_SPEED)
        local real FLHFGD = LoadReal(Item,GetItemTypeId(it),CIRCULATING_Mana2)
        
        
        /*
			<?if BJ ~= nil then?>
                call SaveInteger(Item,'<?=id?>',STRIKE,<?=BJ?>)
			<?end?>
			<?if MDSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',MAGIC_BULLET_MAX,<?=MDSX?>)
			<?end?>
			<?if QLSX ~= nil then?>
                call SaveInteger(Item,'<?=id?>',POW_MAX,<?=QLSX?>)
			<?end?>
			<?if SHXZ ~= nil then?>
                call SaveReal(Item,'<?=id?>',DMG_REMIX,<?=SHXZ?>)
			<?end?>
            
*/
        
		/// 力量
		if STR != 0 then
			call SetHeroStr(u,GetHeroStr(u,false) + STR,true)
		endif
		/// 敏捷
		if AGI != 0 then
			call SetHeroAgi(u,GetHeroAgi(u,false) + AGI,true)
		endif
		/// 智力
		if INT != 0 then
			call SetHeroInt(u,GetHeroInt(u,false) + INT,true)
		endif
		/// 主属性
		if ZSX != 0 then
            if LoadInteger(YDHT,GetUnitTypeId(u),StringHash("主属性"))==1 then
			    call SetHeroStr(u,GetHeroStr(u,false) + ZSX,true)
                call BJDebugMsg("主属性：力量"+I2S(ZSX))
            else
                if LoadInteger(YDHT,GetUnitTypeId(u),StringHash("主属性"))==2 then
                    call SetHeroAgi(u,GetHeroAgi(u,false) + ZSX,true)
                call BJDebugMsg("主属性：敏捷"+I2S(ZSX))
                else
                    call SetHeroInt(u,GetHeroInt(u,false) + ZSX,true)
                call BJDebugMsg("主属性：智力"+I2S(ZSX))
                endif
            endif
            if LoadInteger(YDHT,GetUnitTypeId(u),StringHash("主属性"))==0 then
                call BJDebugMsg("WARNING:英雄主属性未定义")
            endif
		endif
		/// 攻击速度
		if GJSD != 0. then
			call SetUnitState(u,ConvertUnitState(0x51),(GetUnitState(u,ConvertUnitState(0x51)) + GJSD / 100 ))
		endif
		/// 攻击间隔
		if GJJG != 0. then
			call SetUnitState(u,ConvertUnitState(0x51),(GetUnitState(u,ConvertUnitState(0x25)) - GJJG / 100 ))
		endif
        /// 移动速度
        if YDSD != 0. then
            // 在英雄选择时为英雄添加技能'A02P'
            call EXSetAbilityDataReal(EXGetUnitAbility(u, 'A02P'), GetConvertedPlayerId( GetOwningPlayer( u)), 108, EXGetAbilityDataReal(EXGetUnitAbility(u, 'A02P'), GetConvertedPlayerId( GetOwningPlayer( u)), 108)+YDSD)
			call SetUnitAbilityLevel(u,'A02P',8)
            call SetUnitAbilityLevel(u,'A02P',GetConvertedPlayerId( GetOwningPlayer(u)))
            call BJDebugMsg("MovLv:"+I2S(GetUnitAbilityLevel(u,'A02P')))
		endif
		/// 攻击力
		if GJL != 0. then
			call SetUnitState(u,ConvertUnitState(0x12),(GetUnitState(u,ConvertUnitState(0x12)) + GJL))
		endif
		/// 护甲
		if HJ != 0. then
			call SetUnitState(u,ConvertUnitState(0x20),(GetUnitState(u,ConvertUnitState(0x20)) + HJ))
		endif
		/// 生命值
		if SMZ != 0. then
			call SetUnitState(u,UNIT_STATE_MAX_LIFE,GetUnitState(u,UNIT_STATE_MAX_LIFE) + SMZ)
			call SetUnitState(u,UNIT_STATE_LIFE,GetUnitState(u,UNIT_STATE_LIFE) + SMZ)
		endif
		/// 魔法值
		if MP != 0. then
			call SetUnitState(u,UNIT_STATE_MAX_MANA,GetUnitState(u,UNIT_STATE_MAX_MANA) + MP)
			call SetUnitState(u,UNIT_STATE_MANA,GetUnitState(u,UNIT_STATE_MANA) + MP)
		endif
		/// 全属性
		if QSX != 0 then
			call SetHeroStr(u,GetHeroStr(u,false) + QSX,true)
			call SetHeroAgi(u,GetHeroAgi(u,false) + QSX,true)
			call SetHeroInt(u,GetHeroInt(u,false) + QSX,true)
		endif
		 ///杀敌属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_PROPERTY,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_PROPERTY)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_PROPERTY))
		 ///普攻属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ATTACK_ATTRIBUTES,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ATTACK_ATTRIBUTES)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_ATTACK_ATTRIBUTES))
		///暴击伤害
		call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_VIOLENT_ATTACK,\
        LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_VIOLENT_ATTACK)\
        +LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_VIOLENT_ATTACK))
         ///每秒属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_CYCLIC_PROPERTIES,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_CYCLIC_PROPERTIES)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_CYCLIC_PROPERTIES))
         //力量成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STR_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STR_GROW)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_STR_GROW))
         //敏捷成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_AGI_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_AGI_GROW)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_AGI_GROW))
         //智力成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_INT_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_INT_GROW)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_INT_GROW))
         //主属性成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_PRIMARY_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_PRIMARY_GROW)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_PRIMARY_GROW))
         //全属性成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ALL_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ALL_GROW)\
        +LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_ALL_GROW))
        
        if(HaveSavedReal(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_CHANCE)==true) then
             ///暴击几率
            call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_CHANCE,\
            LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_CHANCE)\
            +LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_CHANCE))
            
            //运行触发重新计算暴击几率
            //call SaveUnitHandle(YDHT,GetHandleId(gg_trg_DmgSystem_STRIKE_CHANCE),StringHash("tri"),u)
            //call TriggerExecute(gg_trg_DmgSystem_STRIKE_CHANCE)
            
        endif
        if(HaveSavedInteger(Item,GetItemTypeId(it),STRIKE)==true) then
             //暴击
            call SaveInteger(YDHT,GetHandleId(u),STRIKE,\
            LoadInteger(YDHT,GetHandleId(u),STRIKE)\
            +LoadInteger(Item,GetItemTypeId(it),STRIKE))
            //运行触发重新计算暴击几率
            call SaveUnitHandle(YDHT,GetHandleId(gg_trg_DmgSystem_STRIKE_CHANCE),StringHash("tri"),u)
            call TriggerExecute(gg_trg_DmgSystem_STRIKE_CHANCE)
        endif
         //魔弹上限
		call SaveInteger(YDHT,GetHandleId(u),MAGIC_BULLET_MAX,\
        LoadInteger(YDHT,GetHandleId(u),MAGIC_BULLET_MAX)\
        +LoadInteger(Item,GetItemTypeId(it),MAGIC_BULLET_MAX))
         //气力上限
		call SaveInteger(YDHT,GetHandleId(u),POW_MAX,\
        LoadInteger(YDHT,GetHandleId(u),POW_MAX)\
        +LoadInteger(Item,GetItemTypeId(it),POW_MAX))
        
        
        /*
        local integer BJ = LoadInteger(Item,GetItemTypeId(it),STRIKE)
        local integer MDSX = LoadInteger(Item,GetItemTypeId(it),MAGIC_BULLET_MAX)
        local integer QLSX = LoadInteger(Item,GetItemTypeId(it),POW_MAX)
        local real SHXZ = LoadReal(Item,GetItemTypeId(it),DMG_REMIX)*/

        
		 ///攻击吸血
		call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_BLOOD_SUCKING,\
        LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_BLOOD_SUCKING)\
        +LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_BLOOD_SUCKING))
		 ///每秒回血%
		call SaveReal(YDHT,GetHandleId(u),CIRCULATING_BLOOD,\
        LoadReal(YDHT,GetHandleId(u),CIRCULATING_BLOOD)\
        +LoadReal(Item,GetItemTypeId(it),CIRCULATING_BLOOD))
		  ///伤害减免
		call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_DAMAGE_RESISTANCE,\
        LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_DAMAGE_RESISTANCE)\
        +LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_DAMAGE_RESISTANCE))
        
		  ///伤害加成
		call SaveReal(YDHT,GetHandleId(u),DAMAGE_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),DAMAGE_ADDEX)\
        +LoadReal(Item,GetItemTypeId(it),DAMAGE_ADDEX))
		  ///物理抗性
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_REDUCE)\
        +LoadReal(Item,GetItemTypeId(it),PHYCICS_REDUCE))
		  ///物理加成
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_ADDEX)\
        +LoadReal(Item,GetItemTypeId(it),PHYCICS_ADDEX))
		  ///法术抗性
		call SaveReal(YDHT,GetHandleId(u),MAGIC_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),MAGIC_REDUCE)\
        +LoadReal(Item,GetItemTypeId(it),MAGIC_REDUCE))
		  ///法术加成
		call SaveReal(YDHT,GetHandleId(u),MAGIC_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),MAGIC_ADDEX)\
        +LoadReal(Item,GetItemTypeId(it),MAGIC_ADDEX))
		  ///暴击抗性
		call SaveReal(YDHT,GetHandleId(u),STRIKE_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),STRIKE_REDUCE)\
        +LoadReal(Item,GetItemTypeId(it),STRIKE_REDUCE))
		  ///冷却减免
		call SaveReal(YDHT,GetHandleId(u),COOLDOWN,\
        LoadReal(YDHT,GetHandleId(u),COOLDOWN)\
        +LoadReal(Item,GetItemTypeId(it),COOLDOWN))
		  ///护甲穿透
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_IGNORE,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_IGNORE)\
        +LoadReal(Item,GetItemTypeId(it),PHYCICS_IGNORE))
		  ///经验效率
		call SaveReal(YDHT,GetHandleId(u),EXP_ADD,\
        LoadReal(YDHT,GetHandleId(u),EXP_ADD)\
        +LoadReal(Item,GetItemTypeId(it),EXP_ADD))
		  ///冷却上限
		call SaveReal(YDHT,GetHandleId(u),COOLDOWN_UPLIMIT,\
        LoadReal(YDHT,GetHandleId(u),COOLDOWN_UPLIMIT)\
        +LoadReal(Item,GetItemTypeId(it),COOLDOWN_UPLIMIT))
		  ///减伤上限
		call SaveReal(YDHT,GetHandleId(u),DMG_REDUCE_UPLIMIT,\
        LoadReal(YDHT,GetHandleId(u),DMG_REDUCE_UPLIMIT)\
        +LoadReal(Item,GetItemTypeId(it),DMG_REDUCE_UPLIMIT))
		  ///伤害修正
		call SaveReal(YDHT,GetHandleId(u),DMG_REMIX,\
        LoadReal(YDHT,GetHandleId(u),DMG_REMIX)\
        +LoadReal(Item,GetItemTypeId(it),DMG_REMIX))
		  ///近战攻击伤害
		call SaveReal(YDHT,GetHandleId(u),RANGED_ATK_EX,\
        LoadReal(YDHT,GetHandleId(u),RANGED_ATK_EX)\
        +LoadReal(Item,GetItemTypeId(it),RANGED_ATK_EX))
		  ///远程攻击伤害
		call SaveReal(YDHT,GetHandleId(u),MELEE_ATK_EX,\
        LoadReal(YDHT,GetHandleId(u),MELEE_ATK_EX)\
        +LoadReal(Item,GetItemTypeId(it),MELEE_ATK_EX))
		  ///固定回蓝
		call SaveReal(YDHT,GetHandleId(u),CIRCULATING_Mana2,\
        LoadReal(YDHT,GetHandleId(u),CIRCULATING_Mana2)\
        +LoadReal(Item,GetItemTypeId(it),CIRCULATING_Mana2))
        
        
	endfunction

	private function trg1Ac takes nothing returns nothing
		///丢弃物品触发器，攻击力 护甲 生命值 获得之后直接减少，其他的给操作物品单位绑定值
        local unit u = GetManipulatingUnit()
        local item it = GetManipulatedItem()
		local real ATK = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_AGGRESSIVITY)
		local real DEF = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_ARMOR)
		local real HP = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_VALUE_OF_LIFE)
		local real MP = LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_VALUE_OF_MANA)
		local integer ATTR = LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_FULL_ATTRIBUTE)
        local integer STR = LoadInteger(Item,GetItemTypeId(it),STR_ATTRIBUTE)
		local integer AGI = LoadInteger(Item,GetItemTypeId(it),AGI_ATTRIBUTE)
		local integer INT = LoadInteger(Item,GetItemTypeId(it),INT_ATTRIBUTE)
        local integer ZSX = LoadInteger(Item,GetItemTypeId(it),MAIN_ATTRIBUTE)
        local real GJSD = LoadReal(Item,GetItemTypeId(it),ATK_SPEED)
        local real GJJG = LoadReal(Item,GetItemTypeId(it),ATTACK_INTERVAL)
        
        local real YDSD = LoadReal(Item,GetItemTypeId(it),MOVE_SPEED)
        local integer BJ = LoadInteger(Item,GetItemTypeId(it),STRIKE)
        local integer MDSX = LoadInteger(Item,GetItemTypeId(it),MAGIC_BULLET_MAX)
        local integer QLSX = LoadInteger(Item,GetItemTypeId(it),POW_MAX)
        local real SHXZ = LoadReal(Item,GetItemTypeId(it),DMG_REMIX)
        //call BJDebugMsg("丢弃")
		/// 力量
		if STR != 0 then
			call SetHeroStr(u,GetHeroStr(u,false) - STR,true)
		endif
		/// 敏捷
		if AGI != 0 then
			call SetHeroAgi(u,GetHeroAgi(u,false) - AGI,true)
		endif
		/// 智力
		if INT != 0 then
			call SetHeroInt(u,GetHeroInt(u,false) - INT,true)
		endif
        
		/// 主属性
		if ZSX != 0 then
            if LoadInteger(YDHT,GetUnitTypeId(u),StringHash("主属性"))==1 then
			    call SetHeroStr(u,GetHeroStr(u,false) - ZSX,true)
            else
                if LoadInteger(YDHT,GetUnitTypeId(u),StringHash("主属性"))==2 then
                    call SetHeroAgi(u,GetHeroAgi(u,false) - ZSX,true)
                else
                    call SetHeroInt(u,GetHeroInt(u,false) - ZSX,true)
                endif
            endif
		endif
		/// 攻击速度
		if GJSD != 0. then
			call SetUnitState(u,ConvertUnitState(0x51),(GetUnitState(u,ConvertUnitState(0x51)) - GJSD / 100 ))
		endif
		/// 攻击间隔
		if GJJG != 0. then
			call SetUnitState(u,ConvertUnitState(0x51),(GetUnitState(u,ConvertUnitState(0x25)) + GJJG / 100 ))
		endif

		if ATK != 0. then
            //攻击力
			call SetUnitState(u,ConvertUnitState(0x12),(GetUnitState(u,ConvertUnitState(0x12)) - ATK))
		endif
		if DEF != 0. then
            //护甲
			call SetUnitState(u,ConvertUnitState(0x20),(GetUnitState(u,ConvertUnitState(0x20)) - DEF))
		endif
		if  HP != 0. then
            //生命值
			call SetUnitState(u,UNIT_STATE_MAX_LIFE,GetUnitState(u,UNIT_STATE_MAX_LIFE) -  HP)
		endif
        
		if  MP != 0. then
            //魔法值
			call SetUnitState(u,UNIT_STATE_MAX_MANA,GetUnitState(u,UNIT_STATE_MAX_MANA) -  MP)
		endif
		if ATTR != 0 then
            //全属性
			call SetHeroStr(u,GetHeroStr(u,false) - ATTR,true)
			call SetHeroAgi(u,GetHeroAgi(u,false) - ATTR,true)
			call SetHeroInt(u,GetHeroInt(u,false) - ATTR,true)
		endif

        
        /// 移动速度
        if YDSD != 0. then
            // 在英雄选择时为英雄添加技能'A02P'
            call EXSetAbilityDataReal(EXGetUnitAbility(u, 'A02P'), GetConvertedPlayerId( GetOwningPlayer( u)), 108, EXGetAbilityDataReal(EXGetUnitAbility(u, 'A02P'), GetConvertedPlayerId( GetOwningPlayer( u)), 108)-YDSD)
			call SetUnitAbilityLevel(u,'A02P',8)
            call SetUnitAbilityLevel(u,'A02P',GetConvertedPlayerId( GetOwningPlayer(u)))
            call BJDebugMsg("MovLv:"+I2S(GetUnitAbilityLevel(u,'A02P')))
		endif
        
		 ///杀敌属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_PROPERTY,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_PROPERTY)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_PROPERTY))
		 ///普攻属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ATTACK_ATTRIBUTES,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ATTACK_ATTRIBUTES)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_ATTACK_ATTRIBUTES))
		 ///每秒属性
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_CYCLIC_PROPERTIES,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_CYCLIC_PROPERTIES)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_CYCLIC_PROPERTIES))
		 //力量成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STR_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_STR_GROW)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_STR_GROW))
		 //敏捷成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_AGI_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_AGI_GROW)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_AGI_GROW))
		 //智力成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_INT_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_INT_GROW)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_INT_GROW))
		 //主属性成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_PRIMARY_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_PRIMARY_GROW)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_PRIMARY_GROW))
		 //全属性成长
		call SaveInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ALL_GROW,\
        LoadInteger(YDHT,GetHandleId(u),ITEM_SYSTEM_ALL_GROW)\
        -LoadInteger(Item,GetItemTypeId(it),ITEM_SYSTEM_ALL_GROW))
        
         //魔弹上限
		call SaveInteger(YDHT,GetHandleId(u),MAGIC_BULLET_MAX,\
        LoadInteger(YDHT,GetHandleId(u),MAGIC_BULLET_MAX)\
        -LoadInteger(Item,GetItemTypeId(it),MAGIC_BULLET_MAX))
         //气力上限
		call SaveInteger(YDHT,GetHandleId(u),POW_MAX,\
        LoadInteger(YDHT,GetHandleId(u),POW_MAX)\
        -LoadInteger(Item,GetItemTypeId(it),POW_MAX))
    
        if(HaveSavedReal(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_CHANCE)==true) then
             ///暴击几率
            call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_CHANCE,\
            LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_STRIKE_CHANCE)\
            -LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_STRIKE_CHANCE))
            call SaveUnitHandle(YDHT,GetHandleId(gg_trg_DmgSystem_STRIKE_CHANCE),StringHash("tri"),u)
        endif
        if(HaveSavedInteger(Item,GetItemTypeId(it),STRIKE)==true) then
             //暴击
            call SaveInteger(YDHT,GetHandleId(u),STRIKE,\
            LoadInteger(YDHT,GetHandleId(u),STRIKE)\
            -LoadInteger(Item,GetItemTypeId(it),STRIKE))
            call SaveUnitHandle(YDHT,GetHandleId(gg_trg_DmgSystem_STRIKE_CHANCE),StringHash("tri"),u)
            call TriggerExecute(gg_trg_DmgSystem_STRIKE_CHANCE)
        endif
		 ///攻击吸血
		call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_BLOOD_SUCKING,\
        LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_BLOOD_SUCKING)\
        -LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_BLOOD_SUCKING))
		 ///每秒回血%
		call SaveReal(YDHT,GetHandleId(u),CIRCULATING_BLOOD,\
        LoadReal(YDHT,GetHandleId(u),CIRCULATING_BLOOD)\
        -LoadReal(Item,GetItemTypeId(it),CIRCULATING_BLOOD))
		  ///伤害减免
		call SaveReal(YDHT,GetHandleId(u),ITEM_SYSTEM_DAMAGE_RESISTANCE,\
        LoadReal(YDHT,GetHandleId(u),ITEM_SYSTEM_DAMAGE_RESISTANCE)\
        -LoadReal(Item,GetItemTypeId(it),ITEM_SYSTEM_DAMAGE_RESISTANCE))
		  ///伤害加成
		call SaveReal(YDHT,GetHandleId(u),DAMAGE_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),DAMAGE_ADDEX)\
        -LoadReal(Item,GetItemTypeId(it),DAMAGE_ADDEX))
		  ///物理抗性
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_REDUCE)\
        -LoadReal(Item,GetItemTypeId(it),PHYCICS_REDUCE))
		  ///物理加成
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_ADDEX)\
        -LoadReal(Item,GetItemTypeId(it),PHYCICS_ADDEX))
		  ///法术抗性
		call SaveReal(YDHT,GetHandleId(u),MAGIC_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),MAGIC_REDUCE)\
        -LoadReal(Item,GetItemTypeId(it),MAGIC_REDUCE))
		  ///法术加成
		call SaveReal(YDHT,GetHandleId(u),MAGIC_ADDEX,\
        LoadReal(YDHT,GetHandleId(u),MAGIC_ADDEX)\
        -LoadReal(Item,GetItemTypeId(it),MAGIC_ADDEX))
		  ///暴击抗性
		call SaveReal(YDHT,GetHandleId(u),STRIKE_REDUCE,\
        LoadReal(YDHT,GetHandleId(u),STRIKE_REDUCE)\
        -LoadReal(Item,GetItemTypeId(it),STRIKE_REDUCE))
		  ///冷却减免
		call SaveReal(YDHT,GetHandleId(u),COOLDOWN,\
        LoadReal(YDHT,GetHandleId(u),COOLDOWN)\
        -LoadReal(Item,GetItemTypeId(it),COOLDOWN))
		  ///护甲穿透
		call SaveReal(YDHT,GetHandleId(u),PHYCICS_IGNORE,\
        LoadReal(YDHT,GetHandleId(u),PHYCICS_IGNORE)\
        -LoadReal(Item,GetItemTypeId(it),PHYCICS_IGNORE))
		  ///经验效率
		call SaveReal(YDHT,GetHandleId(u),EXP_ADD,\
        LoadReal(YDHT,GetHandleId(u),EXP_ADD)\
        -LoadReal(Item,GetItemTypeId(it),EXP_ADD))
		  ///冷却上限
		call SaveReal(YDHT,GetHandleId(u),COOLDOWN_UPLIMIT,\
        LoadReal(YDHT,GetHandleId(u),COOLDOWN_UPLIMIT)\
        -LoadReal(Item,GetItemTypeId(it),COOLDOWN_UPLIMIT))
		  ///减伤上限
		call SaveReal(YDHT,GetHandleId(u),DMG_REDUCE_UPLIMIT,\
        LoadReal(YDHT,GetHandleId(u),DMG_REDUCE_UPLIMIT)\
        -LoadReal(Item,GetItemTypeId(it),DMG_REDUCE_UPLIMIT))

		  ///伤害修正
		call SaveReal(YDHT,GetHandleId(u),DMG_REMIX,\
        LoadReal(YDHT,GetHandleId(u),DMG_REMIX)\
        -LoadReal(Item,GetItemTypeId(it),DMG_REMIX))
        
		  ///近战攻击伤害
		call SaveReal(YDHT,GetHandleId(u),RANGED_ATK_EX,\
        LoadReal(YDHT,GetHandleId(u),RANGED_ATK_EX)\
        -LoadReal(Item,GetItemTypeId(it),RANGED_ATK_EX))
		  ///远程攻击伤害
		call SaveReal(YDHT,GetHandleId(u),MELEE_ATK_EX,\
        LoadReal(YDHT,GetHandleId(u),MELEE_ATK_EX)\
        -LoadReal(Item,GetItemTypeId(it),MELEE_ATK_EX))
	endfunction

    private function InitTrigCond takes nothing returns boolean
        //call BJDebugMsg("检查")
        return ItemIsCard(GetItemTypeId(GetManipulatedItem()))==false
    endfunction

	private function Init takes nothing returns nothing
		local integer Sy = 0
		call InItem()
		set trg[0] = CreateTrigger() ///获得物品
		set trg[1] = CreateTrigger() ///丢弃物品
		
		loop
			exitwhen Sy == 16
			call TriggerRegisterPlayerUnitEvent(trg[0], Player(Sy), ConvertPlayerUnitEvent(49), null)
            call TriggerAddCondition(trg[1],Condition(function InitTrigCond))
			call TriggerRegisterPlayerUnitEvent(trg[1], Player(Sy), ConvertPlayerUnitEvent(48), null)
			set Sy = Sy + 1
		endloop
		call TriggerAddAction(trg[0],function trg0Ac)
		call TriggerAddAction(trg[1],function trg1Ac)
        
        
        set trg[2] = CreateTrigger() ///单位注册
        call TriggerRegisterTimerEvent(trg[2], 0.00,false)
        call TriggerAddAction(trg[2], function InUnit)
        set trg[3] = CreateTrigger() ///单位注册
        call TriggerRegisterTimerEvent(trg[3], 0.00,false)
        call TriggerAddAction(trg[3], function InCard)
	endfunction

endlibrary