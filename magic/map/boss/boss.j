#ifndef BOSS_SYSTEM_INCLUDED
#define BOSS_SYSTEM_INCLUDED
#include "nncou\\debug.j"
/*
    BOSS系统模块

    负责：
    1. 首个玩家进入BOSS房时生成BOSS
    2. BOSS状态管理
    3. BOSS死亡事件处理

    BOSS 房使用 areaSlot 的预留槽位（地形 -1），不受普通槽位驱逐影响。
    纯框架+钩子模式：接口和钩子定义在此文件中，具体数值由WE/GUI填入。

    依赖：areaData, areaEnter, DebugLogger
*/
library BossSystem requires areaData, areaEnter, DebugLogger

globals
    private hashtable BossTable = InitHashtable()

    // BOSS状态（parent key = 0）
    private constant integer HT_BOSS_SPAWNED = 0
    private constant integer HT_BOSS_UNIT = 1
    private constant integer HT_BOSS_AREA = 2
    private constant integer HT_BOSS_TYPE_ID = 3
    private constant integer HT_BOSS_IS_DEAD = 4
    private constant integer HT_BOSS_FIRST_ATTACKED = 5

    // 触发器
    private trigger BossEnterTrig = null
    private trigger BossDeathTrig = null
    // BOSS死亡回调（供ChapterManager等外部模块注册，避免循环依赖）
    private trigger BossDeathCallback = null
endglobals

// ===== 钩子（private，可在 boss.j 内部覆写）=====

// BOSS生成前触发，用于配置BOSS属性
private function OnBossSpawn takes unit boss returns nothing
endfunction

// BOSS死亡时触发，执行外部注册的回调
private function OnBossDeath takes unit boss returns nothing
    if BossDeathCallback != null then
        call TriggerExecute(BossDeathCallback)
    endif
endfunction

// BOSS首次被攻击时触发
private function OnBossFirstAttacked takes unit boss returns nothing
endfunction

// 判断是否允许生成BOSS（可覆写以添加条件）
private function CanSpawnBoss takes nothing returns boolean
    return true
endfunction

// 获取BOSS生成位置（可覆写以自定义位置）
private function GetBossSpawnPosition takes integer areaId returns location
    local rect r = GetAreaRect(areaId)
    if r == null then
        return null
    endif
    return Location(GetRectCenterX(r), GetRectCenterY(r))
endfunction

// ===== 内部：生成BOSS =====

private function DoSpawnBoss takes nothing returns nothing
    local integer bossArea = GetBossArea()
    local integer typeId = LoadInteger(BossTable, 0, HT_BOSS_TYPE_ID)
    local location loc
    local unit boss
    if bossArea < 0 then
        call DebugLogger_Log(LOG_WARN, "[boss] DoSpawnBoss skipped: boss area not configured")
        return
    endif
    if typeId == 0 then
        call DebugLogger_Log(LOG_WARN, "[boss] DoSpawnBoss skipped: boss type id not configured")
        return
    endif
    // BOSS 必须绑定到预留槽位（InitBossSystem 通常已绑定，这里做幂等保护）
    if Area_EnsureBound(bossArea) < 0 then
        call DebugLogger_Log(LOG_WARN, "[boss] DoSpawnBoss failed: cannot bind boss area " + GetAreaIdName(bossArea))
        return
    endif
    set loc = GetBossSpawnPosition(bossArea)
    if loc == null then
        call DebugLogger_Log(LOG_WARN, "[boss] DoSpawnBoss failed: no spawn position for " + GetAreaIdName(bossArea))
        return
    endif
    set boss = CreateUnitAtLoc(Player(PLAYER_NEUTRAL_AGGRESSIVE), typeId, loc, 270.0)
    call RemoveLocation(loc)
    set loc = null
    if boss == null then
        call DebugLogger_Log(LOG_WARN, "[boss] DoSpawnBoss failed: CreateUnitAtLoc returned null")
        return
    endif
    call SaveBoolean(BossTable, 0, HT_BOSS_SPAWNED, true)
    call SaveUnitHandle(BossTable, 0, HT_BOSS_UNIT, boss)
    call SaveInteger(BossTable, 0, HT_BOSS_AREA, bossArea)
    call SaveBoolean(BossTable, 0, HT_BOSS_IS_DEAD, false)
    call SaveBoolean(BossTable, 0, HT_BOSS_FIRST_ATTACKED, false)
    if BossDeathTrig != null then
        call TriggerRegisterUnitEvent(BossDeathTrig, boss, EVENT_UNIT_DEATH)
    endif
    call OnBossSpawn(boss)
    call DebugLogger_Log(LOG_INFO, "[boss] spawned in " + GetAreaIdName(bossArea) + " typeId=" + I2S(typeId))
    set boss = null
endfunction

// ===== 公开接口（提前声明，供内部函数调用）=====

public function IsBossSpawned takes nothing returns boolean
    return LoadBoolean(BossTable, 0, HT_BOSS_SPAWNED)
endfunction

// ===== 内部：玩家进入BOSS房触发 =====

private function Trig_PlayerEnterBossRoom takes nothing returns nothing
    local unit u = GetEnteringUnit()
    if u == null or not IsUnitType(u, UNIT_TYPE_HERO) then
        set u = null
        return
    endif
    if IsBossSpawned() then
        set u = null
        return
    endif
    if not CanSpawnBoss() then
        set u = null
        return
    endif
    call DoSpawnBoss()
    set u = null
endfunction

// ===== 内部：BOSS死亡触发 =====

private function Trig_BossDeath takes nothing returns nothing
    local unit boss = GetDyingUnit()
    local unit registered = LoadUnitHandle(BossTable, 0, HT_BOSS_UNIT)
    if boss == null or registered == null or boss != registered then
        set boss = null
        set registered = null
        return
    endif
    call SaveBoolean(BossTable, 0, HT_BOSS_IS_DEAD, true)
    call OnBossDeath(boss)
    set boss = null
    set registered = null
endfunction

// ===== 公开接口 =====

/*
    [BossSystem_RegisterBossDeathCallback]
    title = "注册BOSS死亡回调"
    description = "注册BOSS死亡时执行的${回调函数}，避免循环依赖"
    category = TC_FRO
    [[.args]]
    type = code
*/
public function RegisterBossDeathCallback takes code cb returns nothing
    set BossDeathCallback = CreateTrigger()
    call TriggerAddAction(BossDeathCallback, cb)
endfunction

/*
    [BossSystem_SetBossTypeId]
    title = "设置BOSS类型"
    description = "设置BOSS的单位类型ID为${类型ID}"
    category = TC_FRO
    [[.args]]
    type = integer
*/
public function SetBossTypeId takes integer typeId returns nothing
    call SaveInteger(BossTable, 0, HT_BOSS_TYPE_ID, typeId)
endfunction

/*
    [BossSystem_InitBossSystem]
    title = "初始化BOSS系统"
    description = "初始化BOSS系统，必须在InitArea之后调用"
    category = TC_FRO
*/
public function InitBossSystem takes nothing returns nothing
    local integer bossArea = GetBossArea()
    local rect bossRect
    if bossArea < 0 then
        call DebugLogger_Log(LOG_WARN, "[boss] InitBossSystem skipped: boss area not configured")
        return
    endif
    // 确保 BOSS 逻辑房已绑定预留物理槽位
    if Area_EnsureBound(bossArea) < 0 then
        call DebugLogger_Log(LOG_WARN, "[boss] InitBossSystem failed: cannot bind boss area " + GetAreaIdName(bossArea))
        return
    endif
    set bossRect = GetAreaRect(bossArea)
    if bossRect == null then
        call DebugLogger_Log(LOG_WARN, "[boss] InitBossSystem failed: boss rect is null")
        return
    endif
    // 创建BOSS房进入触发器
    if BossEnterTrig != null then
        call DestroyTrigger(BossEnterTrig)
    endif
    set BossEnterTrig = CreateTrigger()
    call TriggerRegisterEnterRectSimple(BossEnterTrig, bossRect)
    call TriggerAddAction(BossEnterTrig, function Trig_PlayerEnterBossRoom)
    // 创建BOSS死亡触发器
    if BossDeathTrig != null then
        call DestroyTrigger(BossDeathTrig)
    endif
    set BossDeathTrig = CreateTrigger()
    call TriggerAddAction(BossDeathTrig, function Trig_BossDeath)
    call DebugLogger_Log(LOG_INFO, "[boss] InitBossSystem done: area=" + GetAreaIdName(bossArea))
    set bossRect = null
endfunction

/*
    [BossSystem_GetBossUnit]
    title = "获取BOSS单位"
    description = "获取BOSS单位句柄"
    category = TC_FRO
    returns = unit
*/
public function GetBossUnit takes nothing returns unit
    return LoadUnitHandle(BossTable, 0, HT_BOSS_UNIT)
endfunction

/*
    [BossSystem_IsBossDead]
    title = "BOSS是否已死亡"
    description = "判断BOSS是否已死亡"
    category = TC_FRO
    returns = boolean
*/
public function IsBossDead takes nothing returns boolean
    return LoadBoolean(BossTable, 0, HT_BOSS_IS_DEAD)
endfunction

/*
    [BossSystem_GetBossRoomId]
    title = "获取BOSS所在区域"
    description = "获取BOSS所在区域ID"
    category = TC_FRO
    returns = integer
*/
public function GetBossRoomId takes nothing returns integer
    return LoadInteger(BossTable, 0, HT_BOSS_AREA)
endfunction

/*
    [BossSystem_ForceSpawnBoss]
    title = "强制生成BOSS"
    description = "强制生成BOSS（跳过进入检测）"
    category = TC_FRO
*/
public function ForceSpawnBoss takes nothing returns nothing
    if IsBossSpawned() then
        return
    endif
    call DoSpawnBoss()
endfunction

/*
    [BossSystem_KillBoss]
    title = "杀死BOSS"
    description = "立即杀死BOSS"
    category = TC_FRO
*/
public function KillBoss takes nothing returns nothing
    local unit boss = LoadUnitHandle(BossTable, 0, HT_BOSS_UNIT)
    if boss != null and not IsBossDead() then
        call KillUnit(boss)
    endif
    set boss = null
endfunction

// 重置BOSS系统：杀死BOSS，销毁触发器，清空数据
// 供 ChapterManager 在关卡切换时调用
function ResetBossSystem takes nothing returns nothing
    local unit boss = LoadUnitHandle(BossTable, 0, HT_BOSS_UNIT)
    // 直接移除BOSS：不要 KillUnit，避免在关卡重置时触发死亡回调
    if boss != null then
        call RemoveUnit(boss)
    endif
    // 销毁触发器
    if BossEnterTrig != null then
        call DestroyTrigger(BossEnterTrig)
        set BossEnterTrig = null
    endif
    if BossDeathTrig != null then
        call DestroyTrigger(BossDeathTrig)
        set BossDeathTrig = null
    endif
    // 清空本关状态（HT_BOSS_TYPE_ID 由下一关的 InitForest 重新设置）
    call FlushChildHashtable(BossTable, 0)
    set boss = null
endfunction

endlibrary
#endif

