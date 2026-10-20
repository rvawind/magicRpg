#ifndef AREA_GRID
#define AREA_GRID
#include "nncou\\debug.j"
/*
    逻辑网格模型（通用框架）

    提供 rows × cols 矩形网格的逻辑坐标系统：
    - 逻辑坐标 (row, col) 与稠密逻辑 ID（row*cols+col，0..rows*cols-1）互转。
    - 四方向邻接由坐标自动推导（上下左右），注册时按概率随机剪枝。
    - 房间类型/状态/怪物池等持久状态仍由 areaData 以逻辑 ID 为键存储。

    依赖：DebugLogger
*/
library areaGrid requires DebugLogger

globals
    // 方向常量
    constant integer DIR_UP = 0
    constant integer DIR_DOWN = 1
    constant integer DIR_LEFT = 2
    constant integer DIR_RIGHT = 3

    private hashtable GridTable = InitHashtable()
    // 网格尺寸（parent key = 0）
    private constant integer HT_ROWS = 0
    private constant integer HT_COLS = 1
    // 剪枝概率（parent key = 0）
    private constant integer HT_PRUNE_CHANCE = 2
    // 边存储：parent key = logicalId，子键 = HT_EDGE + dir
    private constant integer HT_EDGE = 100

    private real GridPruneChance = 0.0

    // 生成用临时数组（逻辑坐标总数上限）
    private constant integer MAX_CELLS = 128
    private integer array DfsStack
    private boolean array DfsVisited
    private integer array DfsNeighborBuf
endglobals

// 方向取反：0↔1（上下），2↔3（左右）
function Grid_OppositeDir takes integer dir returns integer
    return dir + 1 - 2 * ModuloInteger(dir, 2)
endfunction

// ===== 查询接口 =====

function Grid_GetRows takes nothing returns integer
    return LoadInteger(GridTable, 0, HT_ROWS)
endfunction

function Grid_GetCols takes nothing returns integer
    return LoadInteger(GridTable, 0, HT_COLS)
endfunction

// 逻辑坐标总数 = rows × cols
function Grid_GetTotal takes nothing returns integer
    return Grid_GetRows() * Grid_GetCols()
endfunction

// 由逻辑坐标推导逻辑 ID；越界返回 -1
function Grid_GetId takes integer row, integer col returns integer
    local integer rows = Grid_GetRows()
    local integer cols = Grid_GetCols()
    if row < 0 or row >= rows or col < 0 or col >= cols then
        return -1
    endif
    return row * cols + col
endfunction

function Grid_GetRow takes integer id returns integer
    return id / Grid_GetCols()
endfunction

function Grid_GetCol takes integer id returns integer
    return id - Grid_GetRow(id) * Grid_GetCols()
endfunction

function Grid_IsValidId takes integer id returns boolean
    return id >= 0 and id < Grid_GetTotal()
endfunction

// 获取指定方向相邻逻辑 ID；越界或已剪枝返回 -1
function Grid_GetNeighbor takes integer id, integer dir returns integer
    local integer row = Grid_GetRow(id)
    local integer col = Grid_GetCol(id)
    local integer nrow = row
    local integer ncol = col
    if dir == DIR_UP then
        set nrow = row - 1
    elseif dir == DIR_DOWN then
        set nrow = row + 1
    elseif dir == DIR_LEFT then
        set ncol = col - 1
    elseif dir == DIR_RIGHT then
        set ncol = col + 1
    else
        return -1
    endif
    if nrow < 0 or nrow >= Grid_GetRows() or ncol < 0 or ncol >= Grid_GetCols() then
        return -1
    endif
    return LoadInteger(GridTable, id, HT_EDGE + dir)
endfunction

// ===== 配置接口（在 Grid_BuildEdges 之前调用） =====

// 初始化网格尺寸，并清空旧数据
function Grid_Init takes integer rows, integer cols returns nothing
    call FlushChildHashtable(GridTable, 0)
    call SaveInteger(GridTable, 0, HT_ROWS, rows)
    call SaveInteger(GridTable, 0, HT_COLS, cols)
    set GridPruneChance = 0.0
endfunction

// 设置随机剪枝概率（0.0~1.0）：每个相邻边被移除的概率，默认 0（全连通）
function Grid_SetPruneChance takes real chance returns nothing
    if chance < 0.0 then
        set chance = 0.0
    elseif chance > 1.0 then
        set chance = 1.0
    endif
    set GridPruneChance = chance
endfunction

// ===== 内部：边构建 =====

// 仅按坐标推导相邻 ID（不查边表）；越界返回 -1
private function GetRawNeighbor takes integer id, integer dir returns integer
    local integer rows = Grid_GetRows()
    local integer cols = Grid_GetCols()
    local integer row = id / cols
    local integer col = id - row * cols
    if dir == DIR_UP then
        set row = row - 1
    elseif dir == DIR_DOWN then
        set row = row + 1
    elseif dir == DIR_LEFT then
        set col = col - 1
    elseif dir == DIR_RIGHT then
        set col = col + 1
    else
        return -1
    endif
    if row < 0 or row >= rows or col < 0 or col >= cols then
        return -1
    endif
    return row * cols + col
endfunction

private function AddEdge takes integer a, integer b, integer dir returns nothing
    call SaveInteger(GridTable, a, HT_EDGE + dir, b)
    call SaveInteger(GridTable, b, HT_EDGE + Grid_OppositeDir(dir), a)
endfunction

private function ClearEdges takes integer total returns nothing
    local integer i = 0
    local integer d = 0
    loop
        exitwhen i >= total
        set d = 0
        loop
            exitwhen d >= 4
            call SaveInteger(GridTable, i, HT_EDGE + d, -1)
            set d = d + 1
        endloop
        set i = i + 1
    endloop
endfunction

/*
    生成连通网格：
    1. 随机 DFS 生成一棵生成树，保证任意两点可达；
    2. 对其余相邻边以 (1 - pruneChance) 的概率额外连通，形成环路。

    旧实现逐边独立剪枝，可能把网格切成不可达的孤岛；这里改为「先保证连通，再随机加边」。
    必须在 Grid_Init / Grid_SetPruneChance 之后调用。
*/
function Grid_BuildEdges takes nothing returns nothing
    local integer rows = Grid_GetRows()
    local integer cols = Grid_GetCols()
    local integer total = rows * cols
    local integer r
    local integer c
    local integer id
    local integer neighbor
    local integer dir
    local integer nbrCount
    local integer top
    local integer pick
    local integer edgeCount
    local real keepChance
    if total <= 0 or total > MAX_CELLS then
        call DebugLogger_Log(LOG_WARN, "[grid] BuildEdges skipped: invalid size " + I2S(rows) + "x" + I2S(cols) + " (max " + I2S(MAX_CELLS) + ")")
        return
    endif

    call ClearEdges(total)
    set id = 0
    loop
        exitwhen id >= total
        set DfsVisited[id] = false
        set id = id + 1
    endloop

    // 随机 DFS 生成树
    set top = 0
    set DfsStack[0] = 0
    set DfsVisited[0] = true
    loop
        exitwhen top < 0
        set id = DfsStack[top]
        set nbrCount = 0
        set dir = 0
        loop
            exitwhen dir >= 4
            set neighbor = GetRawNeighbor(id, dir)
            if neighbor >= 0 and not DfsVisited[neighbor] then
                set DfsNeighborBuf[nbrCount] = neighbor * 4 + dir
                set nbrCount = nbrCount + 1
            endif
            set dir = dir + 1
        endloop
        if nbrCount > 0 then
            set pick = DfsNeighborBuf[GetRandomInt(0, nbrCount - 1)]
            set neighbor = pick / 4
            set dir = pick - neighbor * 4
            call AddEdge(id, neighbor, dir)
            set DfsVisited[neighbor] = true
            set top = top + 1
            set DfsStack[top] = neighbor
        else
            set top = top - 1
        endif
    endloop

    // 额外边：向右 / 向下各判定一次，已连通的边不再重复
    set keepChance = 1.0 - GridPruneChance
    set edgeCount = 0
    set r = 0
    loop
        exitwhen r >= rows
        set c = 0
        loop
            exitwhen c >= cols
            set id = r * cols + c
            if c + 1 < cols then
                set neighbor = r * cols + (c + 1)
                if LoadInteger(GridTable, id, HT_EDGE + DIR_RIGHT) < 0 and GetRandomReal(0.0, 1.0) < keepChance then
                    call AddEdge(id, neighbor, DIR_RIGHT)
                endif
            endif
            if r + 1 < rows then
                set neighbor = (r + 1) * cols + c
                if LoadInteger(GridTable, id, HT_EDGE + DIR_DOWN) < 0 and GetRandomReal(0.0, 1.0) < keepChance then
                    call AddEdge(id, neighbor, DIR_DOWN)
                endif
            endif
            set c = c + 1
        endloop
        set r = r + 1
    endloop

    // 统计无向边数（只数向右/向下）
    set r = 0
    loop
        exitwhen r >= rows
        set c = 0
        loop
            exitwhen c >= cols
            set id = r * cols + c
            if c + 1 < cols and LoadInteger(GridTable, id, HT_EDGE + DIR_RIGHT) >= 0 then
                set edgeCount = edgeCount + 1
            endif
            if r + 1 < rows and LoadInteger(GridTable, id, HT_EDGE + DIR_DOWN) >= 0 then
                set edgeCount = edgeCount + 1
            endif
            set c = c + 1
        endloop
        set r = r + 1
    endloop

    call DebugLogger_Log(LOG_INFO, "[grid] BuildEdges done: " + I2S(rows) + "x" + I2S(cols) + " cells=" + I2S(total) + " edges=" + I2S(edgeCount) + " prune=" + R2S(GridPruneChance))
endfunction

// 重置网格数据（尺寸、剪枝概率、边表）
function ResetAreaGrid takes nothing returns nothing
    local integer total = Grid_GetTotal()
    local integer i = 0
    loop
        exitwhen i >= total
        call FlushChildHashtable(GridTable, i)
        set i = i + 1
    endloop
    call FlushChildHashtable(GridTable, 0)
    set GridPruneChance = 0.0
endfunction

endlibrary
#endif
