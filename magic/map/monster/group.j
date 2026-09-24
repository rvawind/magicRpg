#ifndef MONSTER_GROUP
#define MONSTER_GROUP
/*
    怪物组定义模块

    怪物组（MonsterGroup）定义了一组会同时出现的怪物。
    每个组有名称、难度范围，以及若干怪物条目（怪物ID + 数量）。
    怪物组总量可大于房间上限，room.j 负责分批刷出与补充刷新。
    怪物组与关卡绑定通过难度范围筛选实现。

    依赖：无外部依赖，独立模块。
    使用方：room.j 通过公开接口查询怪物组数据。
*/
library MonsterGroup

globals
    private hashtable MGTable = InitHashtable()

    private constant integer HT_GROUP_COUNT = 0
    private constant integer HT_GROUP_LIST = 1

    // 每个组的属性子键（parent key = groupId）
    private constant integer HT_NAME = 0
    private constant integer HT_MIN_LV = 1
    private constant integer HT_MAX_LV = 2
    private constant integer HT_ENTRY_COUNT = 3
    private constant integer HT_ENTRY_LIST = 4
    // 标签（parent key = groupId）：HT_TAG_COUNT 为数量，HT_TAG_LIST+i 为第 i 个标签
    private constant integer HT_TAG_COUNT = 5
    private constant integer HT_TAG_LIST = 6

    // 名称反向索引：parent key = StringHash(name), 子键 0 = groupId
    private constant integer HT_NAME_INDEX = 9000
endglobals

// ===== 内部辅助 =====

private function GetGroupCount takes nothing returns integer
    return LoadInteger(MGTable, 0, HT_GROUP_COUNT)
endfunction

// ===== 公开查询接口 =====

/*
    [MonsterGroup_GetGroupIdByName]
    title = "根据名称获取怪物组ID"
    description = "通过${完全匹配名称}查找怪物组ID，未找到返回-1"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = string
*/
public function GetGroupIdByName takes string name returns integer
    return LoadInteger(MGTable, StringHash(name), 0)
endfunction

/*
    [MonsterGroup_GetGroupMinLv]
    title = "获取怪物组难度下限"
    description = "获取${指定ID}怪物组的最低出场关卡"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
public function GetGroupMinLv takes integer groupId returns integer
    return LoadInteger(MGTable, groupId, HT_MIN_LV)
endfunction

/*
    [MonsterGroup_GetGroupMaxLv]
    title = "获取怪物组难度上限"
    description = "获取${指定ID}怪物组的最高出场关卡"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
public function GetGroupMaxLv takes integer groupId returns integer
    return LoadInteger(MGTable, groupId, HT_MAX_LV)
endfunction

/*
    [MonsterGroup_GetGroupEntryCount]
    title = "获取怪物组内怪物种类数"
    description = "获取${指定ID}怪物组中的怪物种类数量"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
public function GetGroupEntryCount takes integer groupId returns integer
    return LoadInteger(MGTable, groupId, HT_ENTRY_COUNT)
endfunction

/*
    [MonsterGroup_GetEntryMonsterId]
    title = "获取组内指定索引的怪物ID"
    description = "获取${指定ID}怪物组中第${索引}种怪物的单位ID"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function GetEntryMonsterId takes integer groupId, integer index returns integer
    return LoadInteger(MGTable, groupId, HT_ENTRY_LIST + index * 2)
endfunction

/*
    [MonsterGroup_GetEntryMonsterCount]
    title = "获取组内指定索引的怪物数量"
    description = "获取${指定ID}怪物组中第${索引}种怪物的数量"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function GetEntryMonsterCount takes integer groupId, integer index returns integer
    return LoadInteger(MGTable, groupId, HT_ENTRY_LIST + index * 2 + 1)
endfunction

/*
    [MonsterGroup_GetGroupTagCount]
    title = "获取怪物组标签数"
    description = "获取${指定ID}怪物组的标签数量"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
public function GetGroupTagCount takes integer groupId returns integer
    return LoadInteger(MGTable, groupId, HT_TAG_COUNT)
endfunction

/*
    [MonsterGroup_GetGroupTag]
    title = "获取怪物组标签"
    description = "获取${指定ID}怪物组中第${索引}个标签，未找到返回空串"
    category = TC_MAGIC
    returns = string
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function GetGroupTag takes integer groupId, integer index returns string
    return LoadStr(MGTable, groupId, HT_TAG_LIST + index)
endfunction

/*
    [GetGroupTotalCount]
    title = "获取怪物组怪物总数"
    description = "获取${指定ID}怪物组中所有怪物的数量之和"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
function GetGroupTotalCount takes integer groupId returns integer
    local integer entries = LoadInteger(MGTable, groupId, HT_ENTRY_COUNT)
    local integer total = 0
    local integer i = 0
    loop
        exitwhen i >= entries
        set total = total + LoadInteger(MGTable, groupId, HT_ENTRY_LIST + i * 2 + 1)
        set i = i + 1
    endloop
    return total
endfunction

/*
    [MonsterGroup_GetRandomGroupByDifficulty]
    title = "根据难度随机获取怪物组"
    description = "从所有怪物组中，随机选取一个难度范围包含${指定难度}的组，未找到返回-1"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = integer
*/
function GetRandomGroupByDifficulty takes integer difficulty returns integer
    local integer total = LoadInteger(MGTable, 0, HT_GROUP_COUNT)
    local integer suitable = 0
    local integer chosen = -1
    local integer i = 1
    local integer gid
    loop
        exitwhen i > total
        set gid = LoadInteger(MGTable, 0, HT_GROUP_LIST + i)
        if difficulty >= LoadInteger(MGTable, gid, HT_MIN_LV) and difficulty <= LoadInteger(MGTable, gid, HT_MAX_LV) then
            set suitable = suitable + 1
            if GetRandomInt(1, suitable) == 1 then
                set chosen = gid
            endif
        endif
        set i = i + 1
    endloop
    return chosen
endfunction

// ===== 配置接口 =====

/*
    [MonsterGroup_CreateMonsterGroup]
    title = "创建怪物组"
    description = "创建名为${名称}的怪物组，难度范围为${最低关卡}至${最高关卡}，返回组ID"
    category = TC_MAGIC
    returns = integer
    [[.args]]
    type = string
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function CreateMonsterGroup takes string name, integer minLv, integer maxLv returns integer
    local integer count = LoadInteger(MGTable, 0, HT_GROUP_COUNT)
    local integer groupId = count + 1
    call SaveInteger(MGTable, 0, HT_GROUP_COUNT, groupId)
    call SaveInteger(MGTable, 0, HT_GROUP_LIST + groupId, groupId)
    call SaveStr(MGTable, groupId, HT_NAME, name)
    call SaveInteger(MGTable, groupId, HT_MIN_LV, minLv)
    call SaveInteger(MGTable, groupId, HT_MAX_LV, maxLv)
    call SaveInteger(MGTable, groupId, HT_ENTRY_COUNT, 0)
    // 名称反向索引
    call SaveInteger(MGTable, StringHash(name), 0, groupId)
    return groupId
endfunction

/*
    [AddMonsterToGroup]
    title = "添加怪物到组"
    description = "将${指定单位ID}的怪物x${数量}添加到${指定ID}的怪物组中"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = integer
    [[.args]]
    type = integer
*/
public function AddMonsterToGroup takes integer groupId, integer monsterId, integer count returns nothing
    local integer entries = LoadInteger(MGTable, groupId, HT_ENTRY_COUNT)
    call SaveInteger(MGTable, groupId, HT_ENTRY_LIST + entries * 2, monsterId)
    call SaveInteger(MGTable, groupId, HT_ENTRY_LIST + entries * 2 + 1, count)
    call SaveInteger(MGTable, groupId, HT_ENTRY_COUNT, entries + 1)
endfunction

/*
    [MonsterGroup_AddMonsterGroupTag]
    title = "为怪物组添加标签"
    description = "为${指定ID}的怪物组添加标签${标签}，可多次调用添加多个标签"
    category = TC_MAGIC
    [[.args]]
    type = integer
    [[.args]]
    type = string
*/
public function AddMonsterGroupTag takes integer groupId, string tag returns nothing
    local integer tagCount = LoadInteger(MGTable, groupId, HT_TAG_COUNT)
    // 跳过空标签与重复标签
    local integer i = 0
    if tag == "" then
        return
    endif
    loop
        exitwhen i >= tagCount
        if LoadStr(MGTable, groupId, HT_TAG_LIST + i) == tag then
            return
        endif
        set i = i + 1
    endloop
    call SaveStr(MGTable, groupId, HT_TAG_LIST + tagCount, tag)
    call SaveInteger(MGTable, groupId, HT_TAG_COUNT, tagCount + 1)
endfunction

endlibrary
#endif

