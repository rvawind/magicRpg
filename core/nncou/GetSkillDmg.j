<?local slk = require 'slk' 
        --[[
        需要做的事：
        //技能公式： (A+ B x Lv) x Attr + C x Lv
            替换Attr为对应的属性，例如"力量"、"敏捷"、"智力"等
                A、C可能为0
          1.  s = 技能公式
          2.  去除s中的所有空格
          3.  将Attr文本替换为对应属性 Q：当技能同时附带两种不同属性时？ A：暂不处理
                保存
          4.  预处理保存A,B,C的值
          5.  编写function(unit spell,int skillid) 返回 技能对应的伤害
          <??>内部为lua代码

        --]]

        function ExtractDamageInfo(str)
            -- 使用模式匹配直接捕获"造成伤害："后的内容（直到遇到|n或字符串结束）
            local damageInfo = string.match(str, "造成伤害：([^|]+)")

            -- 如果直接匹配失败，尝试分割后查找
            if not damageInfo then
                local parts = {}
                -- 按|n分割字符串
                for part in string.gmatch(str, "[^|n]+") do
                    -- 查找包含"造成伤害："的部分
                    local startPos = string.find(part, "造成伤害：")
                    if startPos then
                        -- 提取冒号后的内容
                        damageInfo = string.sub(part, startPos + #"造成伤害：")
                        break
                    end
                end
            end
            
            return damageInfo
        end



?>


library NNCouInitSkillDmg initializer Init

    private function Init takes nothing returns nothing
    <?
        for id, obj in pairs(slk.ability) do
            local text = obj.ubertip -- //获取技能描述
            local dmgtext = ExtractDamageInfo(text) or ''
            local normalized = dmgtext:lower()
                    :gsub("%s+", "")     -- //移除所有空格
                    :gsub("xx", "x")     -- //修复可能的双乘号
                    :gsub("%*", "x")     -- //统一使用 x 作为乘号
                    :gsub("×", "x")      -- //处理不同形式的乘号
                    :gsub("lv", "lv")    -- //确保等级变量统一为小写 lv
                    :gsub("level", "lv") -- //处理可能的 "level" 写法
                    :gsub("技能等级", "lv") -- //处理可能的 "level" 写法
                    :gsub("N", "lv") -- //处理可能的 "level" 写法
            
            -- //提取括号内的部分和括号外的部分
            local A, B,Attr = 0, 0, 0  -- 默认值设为0
            local inner_part = normalized:match("%((.-)%)")
            if inner_part then
                -- //有括号的情况
                if inner_part:find("+") then
                    -- //处理 A + B x Lv 格式
                    A, B = inner_part:match("([%d%.]+)%+([%d%.]+)x?lv")
                else
                    -- //处理 B x Lv 格式（没有加号）
                    B = inner_part:match("([%d%.]+)x?lv")
                end
            else
                -- //没有括号的情况，直接查找 B x Lv 格式
                B = normalized:match("([%d%.]+)x?lv")
            end
            
            -- //提取 C 部分
            local C = normalized:match("%+([%d%.]+)x?lv[^%d]*$")
            if not C then
                -- //尝试在字符串末尾查找
                C = normalized:match("%+([%d%.]+)x?lv$")
            end
            if not C then
                -- //如果没有找到，尝试处理减号情况
                C = normalized:match("%-([%d%.]+)x?lv$")
                if C then
                    C = "-" .. C
                else
                    C = "0"  -- //默认值为0
                end
            end
            
            
            -- 转换为数字
            A = tonumber(A) or 0
            B = tonumber(B) or 0
            C = tonumber(C) or 0
            ?>
            <?if A ~= 0 then?>
                call SaveReal(ht,'<?=id?>',1,<?=A?>)
            <?end?>
            
            <?if B ~= 0 then?>
                call SaveReal(ht,'<?=id?>',2,<?=B?>)
            <?end?>
            
            <?if C ~= 0 then?>
                call SaveReal(ht,'<?=id?>',3,<?=C?>)
            <?end?>
            <?
            -- 提取属性Attr，根据Attr的值保存？
            
            if normalized.find("力量",0)~=nil then
                Attr = 1
            elseif normalized.find("敏捷",0)~=nil then
                Attr = 2
            elseif normalized.find("智力",0)~=nil then
                Attr = 3
            elseif normalized.find("全属性",0)~=nil then
                Attr = 4
            end
            
            if id == 'A05U' then
                print("技能：",id)
                print("文本：",dmgtext)
                print("normalized：",normalized)
                print("inner_part：",inner_part)
                print("A：",A)
                print("B：",B)
                print("C：",C)
                print("Attr：",Attr)
                
            end
            ?>
            <?if Attr ~= 0 then?>
                call SaveInteger(ht,'<?=id?>',4,<?=Attr?>)
            <?end?>
        <?end
    ?>
    
    endfunction
endlibrary