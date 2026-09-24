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

// 根据网格尺寸推导邻接，并按剪枝概率随机决定边是否连通（无向）
// 必须在 Grid_Init / Grid_SetPruneChance 之后调用
function Grid_BuildEdges takes nothing returns nothing
    local integer rows = Grid_GetRows()
    local integer cols = Grid_GetCols()
    local integer r = 0
    local integer c = 0
    local integer id
    local integer neighbor
    local boolean kept
    loop
        exitwhen r >= rows
        set c = 0
        loop
            exitwhen c >= cols
            set id = r * cols + c
            // 向右 (r, c+1)
            if c + 1 < cols then
                set neighbor = r * cols + (c + 1)
                set kept = GetRandomReal(0.0, 1.0) >= GridPruneChance
                if kept then
                    call SaveInteger(GridTable, id, HT_EDGE + DIR_RIGHT, neighbor)
                    call SaveInteger(GridTable, neighbor, HT_EDGE + DIR_LEFT, id)
                else
                    call SaveInteger(GridTable, id, HT_EDGE + DIR_RIGHT, -1)
                    call SaveInteger(GridTable, neighbor, HT_EDGE + DIR_LEFT, -1)
                endif
            endif
            // 向下 (r+1, c)
            if r + 1 < rows then
                set neighbor = (r + 1) * cols + c
                set kept = GetRandomReal(0.0, 1.0) >= GridPruneChance
                if kept then
                    call SaveInteger(GridTable, id, HT_EDGE + DIR_DOWN, neighbor)
                    call SaveInteger(GridTable, neighbor, HT_EDGE + DIR_UP, id)
                else
                    call SaveInteger(GridTable, id, HT_EDGE + DIR_DOWN, -1)
                    call SaveInteger(GridTable, neighbor, HT_EDGE + DIR_UP, -1)
                endif
            endif
            set c = c + 1
        endloop
        set r = r + 1
    endloop
    call DebugLogger_Log(LOG_INFO, "[grid] BuildEdges done: " + I2S(rows) + "x" + I2S(cols) + " prune=" + R2S(GridPruneChance))
endfunction

// 重置网格数据
function ResetAreaGrid takes nothing returns nothing
    call FlushChildHashtable(GridTable, 0)
    set GridPruneChance = 0.0
endfunction

endlibrary
#endif
