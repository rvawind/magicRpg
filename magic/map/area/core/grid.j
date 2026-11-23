#ifndef AREA_GRID
#define AREA_GRID
#include "nncou\\debug.j"
/*
    逻辑网格模型（通用框架）

    提供 rows × cols 矩形网格的逻辑坐标系统：
    - 逻辑坐标 (row, col) 与稠密逻辑 ID（row*cols+col，0..rows*cols-1）互转。
    - 四方向邻接由坐标自动推导（上下左右）；实际连通边由 Grid_BuildEdges 生成：
      「生成树（保证连通）+ 额外边预算（braid 死路 + 随机环路）」。
    - 生成策略可通过 Grid_SetGeneratorMode 替换；日后新增 Prim / 主路径优先时只改
      生成函数与 GenerateSpanningTree 的分派。
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
    private constant integer HT_EDGE_COUNT = 2
    // 边存储：parent key = logicalId，子键 = HT_EDGE + dir
    private constant integer HT_EDGE = 100

    // ===== 生成策略（可替换）=====
    // 新增算法时：在这里加常量，在 GenerateSpanningTree 里加一个分派分支。
    constant integer GRID_GEN_DFS = 0
    // 预留：
    //   GRID_GEN_PRIM = 1   （多支路、短死路）
    //   GRID_GEN_PATH = 2   （主路径优先）

    private constant integer DEFAULT_EXTRA_EDGE_BUDGET = 10
    private constant real DEFAULT_BRAID_CHANCE = 0.60

    private integer GridGenMode = GRID_GEN_DFS
    // 生成树之外的额外边总数（含 braid 打通的边）
    private integer GridExtraEdgeBudget = DEFAULT_EXTRA_EDGE_BUDGET
    // 死路被打通的概率（消耗上面的预算）
    private real GridBraidChance = DEFAULT_BRAID_CHANCE

    // 生成/查询用临时数组（包围盒面积上限；B11：实际房间数可更少）
    private constant integer MAX_CELLS = 128
    private constant integer MAX_EDGES = 256
    private integer array DfsStack
    private boolean array DfsVisited
    private integer array DfsNeighborBuf
    private integer array CandEdgeBuf
    private integer array BfsQueue
    private integer array BfsDist
    private boolean array BfsVisited

    // ===== B11 稀疏模型：包围盒 + 存在格列表（允许缺格/洞/L 形）=====
    // 逻辑 id 仍为 row*cols+col（dense 空间，索引数组/边表）；只有存在格才有效。
    private boolean array CellPresent
    private integer array CellIds          // 存在格 id 列表（按加入顺序；UI/测试遍历用）
    private integer CellCount = 0
    private integer BoundRows = 0
    private integer BoundCols = 0
    // 固定边表模式：配置自行加边，跳过生成器（第一章教学布局等）
    private boolean GridManualEdges = false
endglobals

// 方向取反：0↔1（上下），2↔3（左右）
function Grid_OppositeDir takes integer dir returns integer
    return dir + 1 - 2 * ModuloInteger(dir, 2)
endfunction

// ===== 查询接口（B11：稀疏模型） =====

// 包围盒行/列（UI 排版/坐标计算用；稀疏时 ≠ 房间数）
function Grid_GetRows takes nothing returns integer
    return BoundRows
endfunction

function Grid_GetCols takes nothing returns integer
    return BoundCols
endfunction

// 实际存在的房间数（稀疏时 < 包围盒面积）
function Grid_GetTotal takes nothing returns integer
    return CellCount
endfunction

// 包围盒面积（id 空间上限；数组/hashtable 清理循环用）
function Grid_GetMaxId takes nothing returns integer
    return BoundRows * BoundCols
endfunction

// 坐标 -> 逻辑 id；越界或该格不存在返回 -1
function Grid_GetId takes integer row, integer col returns integer
    local integer id
    if row < 0 or row >= BoundRows or col < 0 or col >= BoundCols then
        return -1
    endif
    set id = row * BoundCols + col
    if not CellPresent[id] then
        return -1
    endif
    return id
endfunction

function Grid_GetRow takes integer id returns integer
    if BoundCols <= 0 then
        return -1
    endif
    return id / BoundCols
endfunction

function Grid_GetCol takes integer id returns integer
    if BoundCols <= 0 then
        return -1
    endif
    return id - (id / BoundCols) * BoundCols
endfunction

// 该 id 是否为「存在格」
function Grid_IsValidId takes integer id returns boolean
    if id < 0 or id >= Grid_GetMaxId() then
        return false
    endif
    return CellPresent[id]
endfunction

// 第 index 个存在格 id；越界返回 -1（UI/测试/生成统一用它遍历房间）
function Grid_GetCellByIndex takes integer index returns integer
    if index < 0 or index >= CellCount then
        return -1
    endif
    return CellIds[index]
endfunction

// 获取指定方向相邻逻辑 ID；越界/缺格/已剪枝返回 -1
function Grid_GetNeighbor takes integer id, integer dir returns integer
    local integer row
    local integer col
    local integer nrow
    local integer ncol
    local integer nid
    if not Grid_IsValidId(id) then
        return -1
    endif
    set row = Grid_GetRow(id)
    set col = Grid_GetCol(id)
    set nrow = row
    set ncol = col
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
    if nrow < 0 or nrow >= BoundRows or ncol < 0 or ncol >= BoundCols then
        return -1
    endif
    set nid = nrow * BoundCols + ncol
    if not CellPresent[nid] then
        return -1
    endif
    return LoadInteger(GridTable, id, HT_EDGE + dir)
endfunction

// ===== 规格查询 API（B11：UI/测试/文档不得写死具体规格，必须从这里推导）=====

// 实际存在的房间数（= Grid_GetTotal）
function Grid_GetCellCount takes nothing returns integer
    return CellCount
endfunction

// 布局包围盒行数/列数（UI 排版用）
function Grid_GetBoundingRows takes nothing returns integer
    return BoundRows
endfunction

function Grid_GetBoundingCols takes nothing returns integer
    return BoundCols
endfunction

// 坐标 -> 逻辑 id；该格不存在返回 -1（= Grid_GetId，显式命名，配置校验用）
function Grid_GetIdIfPresent takes integer row, integer col returns integer
    return Grid_GetId(row, col)
endfunction

// 实际连通边总数（无向；Grid_BuildEdges 完成后有效）
function Grid_GetEdgeCount takes nothing returns integer
    return LoadInteger(GridTable, 0, HT_EDGE_COUNT)
endfunction

// ===== 配置接口（在 Grid_BuildEdges 之前调用） =====

// 初始化「包围盒」；清空旧数据与存在格集合（之后用 Grid_AddCell 加入房间）
function Grid_InitBounds takes integer rows, integer cols returns nothing
    local integer i = 0
    call FlushChildHashtable(GridTable, 0)
    set BoundRows = rows
    set BoundCols = cols
    set CellCount = 0
    loop
        exitwhen i >= MAX_CELLS
        set CellPresent[i] = false
        set CellIds[i] = -1
        set i = i + 1
    endloop
    call SaveInteger(GridTable, 0, HT_ROWS, rows)
    call SaveInteger(GridTable, 0, HT_COLS, cols)
    call SaveInteger(GridTable, 0, HT_EDGE_COUNT, 0)
    set GridGenMode = GRID_GEN_DFS
    set GridExtraEdgeBudget = DEFAULT_EXTRA_EDGE_BUDGET
    set GridBraidChance = DEFAULT_BRAID_CHANCE
    set GridManualEdges = false
endfunction

// 加入一个存在格（坐标必须落在包围盒内；重复调用安全）
function Grid_AddCell takes integer row, integer col returns nothing
    local integer id
    if row < 0 or row >= BoundRows or col < 0 or col >= BoundCols then
        call DebugLogger_Log(LOG_WARN, "[grid] AddCell out of bounds: (" + I2S(row) + "," + I2S(col) + ")")
        return
    endif
    set id = row * BoundCols + col
    if CellPresent[id] then
        return
    endif
    if CellCount >= MAX_CELLS then
        call DebugLogger_Log(LOG_WARN, "[grid] AddCell exceeds MAX_CELLS=" + I2S(MAX_CELLS))
        return
    endif
    set CellPresent[id] = true
    set CellIds[CellCount] = id
    set CellCount = CellCount + 1
endfunction

// 便捷：满矩形初始化（等价 InitBounds + 逐格 AddCell）；旧章节配置可继续使用
function Grid_Init takes integer rows, integer cols returns nothing
    local integer r = 0
    local integer c
    call Grid_InitBounds(rows, cols)
    loop
        exitwhen r >= rows
        set c = 0
        loop
            exitwhen c >= cols
            call Grid_AddCell(r, c)
            set c = c + 1
        endloop
        set r = r + 1
    endloop
endfunction

// 选择生成树算法（默认 GRID_GEN_DFS）
function Grid_SetGeneratorMode takes integer mode returns nothing
    set GridGenMode = mode
endfunction

// 设置额外边总数（生成树之外，含 braid 打通的边）；0 = 纯生成树
function Grid_SetExtraEdgeBudget takes integer count returns nothing
    if count < 0 then
        set count = 0
    endif
    set GridExtraEdgeBudget = count
endfunction

// 设置死路被打通的概率（0.0~1.0）；打通的边消耗额外边预算
function Grid_SetBraidChance takes real chance returns nothing
    if chance < 0.0 then
        set chance = 0.0
    elseif chance > 1.0 then
        set chance = 1.0
    endif
    set GridBraidChance = chance
endfunction

// ===== 内部：边构建 =====

// 仅按坐标推导相邻 ID（不查边表）；越界返回 -1
private function GetRawNeighbor takes integer id, integer dir returns integer
    local integer cols = BoundCols
    local integer row = id / cols
    local integer col = id - row * cols
    local integer nid
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
    if row < 0 or row >= BoundRows or col < 0 or col >= BoundCols then
        return -1
    endif
    set nid = row * cols + col
    if not CellPresent[nid] then
        return -1
    endif
    return nid
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

// ===== 内部：生成与后处理 =====

private function GetCellDegree takes integer id returns integer
    local integer dir = 0
    local integer degree = 0
    loop
        exitwhen dir >= 4
        if LoadInteger(GridTable, id, HT_EDGE + dir) >= 0 then
            set degree = degree + 1
        endif
        set dir = dir + 1
    endloop
    return degree
endfunction

// 随机 DFS 生成树（当前默认策略：长走廊、死路多）
private function GenerateTreeDfs takes nothing returns nothing
    local integer total = CellCount
    local integer top = 0
    local integer idx = 0
    local integer id = 0
    local integer nbrCount
    local integer neighbor
    local integer dir
    local integer pick
    loop
        exitwhen idx >= total
        set DfsVisited[CellIds[idx]] = false
        set idx = idx + 1
    endloop
    if total <= 0 then
        return
    endif

    set DfsStack[0] = CellIds[0]
    set DfsVisited[CellIds[0]] = true
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
endfunction

// 生成树策略分派：日后加 Prim / 主路径算法时，只改这里与新增的生成函数
private function GenerateSpanningTree takes nothing returns nothing
    if GridGenMode == GRID_GEN_DFS then
        call GenerateTreeDfs()
    else
        call DebugLogger_Log(LOG_WARN, "[grid] unknown generator mode " + I2S(GridGenMode) + ", fallback to DFS")
        call GenerateTreeDfs()
    endif
endfunction

// 随机挑一条当前不存在的邻边方向；没有可加的边返回 -1
private function PickMissingDir takes integer id returns integer
    local integer dir = 0
    local integer missCount = 0
    local integer picked = -1
    loop
        exitwhen dir >= 4
        if GetRawNeighbor(id, dir) >= 0 and LoadInteger(GridTable, id, HT_EDGE + dir) < 0 then
            set missCount = missCount + 1
            if GetRandomInt(1, missCount) == 1 then
                set picked = dir
            endif
        endif
        set dir = dir + 1
    endloop
    return picked
endfunction

// 按预算加额外边：先 braid 死路，再用随机边补足预算。
// 返回被打通的死路数量（仅用于日志）。
private function AddExtraEdges takes integer budget returns integer
    local integer total = CellCount
    local integer added = 0
    local integer braided = 0
    local integer idx = 0
    local integer id
    local integer dir
    local integer candidateCount
    local integer i
    local integer j
    local integer swap
    local integer edgeCode
    if budget <= 0 then
        return 0
    endif

    // 第一阶段：死路（度为 1）按概率打通，消耗预算
    loop
        exitwhen idx >= total or added >= budget
        set id = CellIds[idx]
        if GetCellDegree(id) == 1 and GetRandomReal(0.0, 1.0) < GridBraidChance then
            set dir = PickMissingDir(id)
            if dir >= 0 then
                call AddEdge(id, GetRawNeighbor(id, dir), dir)
                set added = added + 1
                set braided = braided + 1
            endif
        endif
        set idx = idx + 1
    endloop

    if added >= budget then
        return braided
    endif

    // 第二阶段：收集所有尚未连通的邻边（只取向右/向下，避免重复），洗牌后补足预算
    set candidateCount = 0
    set idx = 0
    loop
        exitwhen idx >= total
        set id = CellIds[idx]
        if GetRawNeighbor(id, DIR_RIGHT) >= 0 and LoadInteger(GridTable, id, HT_EDGE + DIR_RIGHT) < 0 then
            set CandEdgeBuf[candidateCount] = id * 4 + DIR_RIGHT
            set candidateCount = candidateCount + 1
        endif
        if GetRawNeighbor(id, DIR_DOWN) >= 0 and LoadInteger(GridTable, id, HT_EDGE + DIR_DOWN) < 0 then
            set CandEdgeBuf[candidateCount] = id * 4 + DIR_DOWN
            set candidateCount = candidateCount + 1
        endif
        set idx = idx + 1
    endloop
    set i = candidateCount - 1
    loop
        exitwhen i <= 0
        set j = GetRandomInt(0, i)
        set swap = CandEdgeBuf[i]
        set CandEdgeBuf[i] = CandEdgeBuf[j]
        set CandEdgeBuf[j] = swap
        set i = i - 1
    endloop
    set i = 0
    loop
        exitwhen i >= candidateCount or added >= budget
        set edgeCode = CandEdgeBuf[i]
        set id = edgeCode / 4
        set dir = edgeCode - id * 4
        call AddEdge(id, GetRawNeighbor(id, dir), dir)
        set added = added + 1
        set i = i + 1
    endloop
    return braided
endfunction

// 从 fromId 出发的 BFS，返回可达格数
private function CountReachable takes integer fromId returns integer
    local integer maxId = Grid_GetMaxId()
    local integer head = 0
    local integer tail = 0
    local integer cur
    local integer dir
    local integer nbr
    local integer i = 0
    local integer total = CellCount
    if not Grid_IsValidId(fromId) then
        return 0
    endif
    loop
        exitwhen i >= maxId
        set BfsVisited[i] = false
        set i = i + 1
    endloop
    set BfsQueue[0] = fromId
    set BfsVisited[fromId] = true
    set tail = 1
    loop
        exitwhen head >= tail
        set cur = BfsQueue[head]
        set head = head + 1
        set dir = 0
        loop
            exitwhen dir >= 4
            set nbr = Grid_GetNeighbor(cur, dir)
            if nbr >= 0 and not BfsVisited[nbr] then
                set BfsVisited[nbr] = true
                set BfsQueue[tail] = nbr
                set tail = tail + 1
            endif
            set dir = dir + 1
        endloop
    endloop
    return tail
endfunction

// 生成后校验：连通性被破坏时打 WARN
private function AssertGridConnected takes nothing returns nothing
    local integer total = CellCount
    local integer reached = 0
    if total <= 0 then
        return
    endif
    set reached = CountReachable(CellIds[0])
    if reached < total then
        call DebugLogger_Log(LOG_WARN, "[grid] connectivity broken: reached=" + I2S(reached) + "/" + I2S(total))
    endif
endfunction

// ===== 查询：图距离 =====

// 从 fromId 出发做一次 BFS，把到每格的最短步数写入 BfsDist（不可达为 -1）
private function RunDistanceField takes integer fromId returns nothing
    local integer maxId = Grid_GetMaxId()
    local integer head = 0
    local integer tail = 0
    local integer cur
    local integer dir
    local integer nbr
    local integer i = 0
    loop
        exitwhen i >= maxId
        set BfsVisited[i] = false
        set BfsDist[i] = -1
        set i = i + 1
    endloop
    if not Grid_IsValidId(fromId) then
        return
    endif
    set BfsQueue[0] = fromId
    set BfsDist[fromId] = 0
    set BfsVisited[fromId] = true
    set tail = 1
    loop
        exitwhen head >= tail
        set cur = BfsQueue[head]
        set head = head + 1
        set dir = 0
        loop
            exitwhen dir >= 4
            set nbr = Grid_GetNeighbor(cur, dir)
            if nbr >= 0 and not BfsVisited[nbr] then
                set BfsVisited[nbr] = true
                set BfsDist[nbr] = BfsDist[cur] + 1
                set BfsQueue[tail] = nbr
                set tail = tail + 1
            endif
            set dir = dir + 1
        endloop
    endloop
endfunction

// 预计算「从某格到所有格」的距离场；之后用 Grid_GetFieldDistance 读取（O(1)）
function Grid_BuildDistanceField takes integer fromId returns nothing
    call RunDistanceField(fromId)
endfunction

// 读取最近一次 Grid_BuildDistanceField 的结果；不可达或非法返回 -1
function Grid_GetFieldDistance takes integer toId returns integer
    if not Grid_IsValidId(toId) then
        return -1
    endif
    return BfsDist[toId]
endfunction

// 网格图上的最短步数（只走真实存在的边）；不可达或参数非法返回 -1
// 批量查询同一源点时请改用 Grid_BuildDistanceField + Grid_GetFieldDistance，避免重复 BFS。
function Grid_GetDistance takes integer fromId, integer toId returns integer
    if not Grid_IsValidId(fromId) or not Grid_IsValidId(toId) then
        return -1
    endif
    if fromId == toId then
        return 0
    endif
    call RunDistanceField(fromId)
    return BfsDist[toId]
endfunction

/*
    生成连通网格（A 方案默认流水线）：
    1. 生成树：保证任意两点可达（当前 DFS；日后可换 Prim / 主路径优先）；
    2. 额外边预算：先 braid 死路，再用随机边补足；
    3. 连通性断言。

    必须在 Grid_Init 与各 Grid_Set* 之后调用。
*/
function Grid_BuildEdges takes nothing returns nothing
    local integer rows = BoundRows
    local integer cols = BoundCols
    local integer maxId = rows * cols
    local integer total = CellCount
    local integer idx
    local integer id
    local integer edgeCount
    local integer braided
    if maxId <= 0 or maxId > MAX_CELLS then
        call DebugLogger_Log(LOG_WARN, "[grid] BuildEdges skipped: bounds " + I2S(rows) + "x" + I2S(cols) + " (max " + I2S(MAX_CELLS) + ")")
        return
    endif
    if total <= 0 then
        call DebugLogger_Log(LOG_WARN, "[grid] BuildEdges skipped: no cells")
        return
    endif

    call ClearEdges(maxId)
    call GenerateSpanningTree()
    set braided = AddExtraEdges(GridExtraEdgeBudget)
    call AssertGridConnected()

    // 统计无向边数（只数向右/向下；目标必须是存在格）
    set edgeCount = 0
    set idx = 0
    loop
        exitwhen idx >= total
        set id = CellIds[idx]
        if LoadInteger(GridTable, id, HT_EDGE + DIR_RIGHT) >= 0 then
            set edgeCount = edgeCount + 1
        endif
        if LoadInteger(GridTable, id, HT_EDGE + DIR_DOWN) >= 0 then
            set edgeCount = edgeCount + 1
        endif
        set idx = idx + 1
    endloop

    call SaveInteger(GridTable, 0, HT_EDGE_COUNT, edgeCount)
    call DebugLogger_LogKey("[grid] BuildEdges done: bounds=" + I2S(rows) + "x" + I2S(cols) + " cells=" + I2S(total) + " edges=" + I2S(edgeCount) + " extra=" + I2S(GridExtraEdgeBudget) + " braided=" + I2S(braided) + " mode=" + I2S(GridGenMode))
endfunction

// ===== 固定边表 API（B11 稀疏章节：教学布局/脚本化边表） =====
// 用法：Grid_InitBounds → Grid_AddCell* → Grid_BeginManualEdges → Grid_AddEdge* → Grid_EndManualEdges
// 与 Grid_BuildEdges（生成器）二选一；EndManualEdges 会统计边数/做连通性断言。

function Grid_BeginManualEdges takes nothing returns nothing
    local integer maxId = Grid_GetMaxId()
    if maxId <= 0 or maxId > MAX_CELLS then
        call DebugLogger_Log(LOG_WARN, "[grid] BeginManualEdges skipped: bounds invalid/max " + I2S(maxId))
        return
    endif
    call ClearEdges(maxId)
    set GridManualEdges = true
endfunction

// 手动加一条边（无向；a 必须存在，dir 方向目标也必须存在）
function Grid_AddEdge takes integer a, integer dir returns nothing
    local integer b
    if not Grid_IsValidId(a) then
        call DebugLogger_Log(LOG_WARN, "[grid] AddEdge invalid id " + I2S(a))
        return
    endif
    set b = GetRawNeighbor(a, dir)
    if b < 0 then
        call DebugLogger_Log(LOG_WARN, "[grid] AddEdge no neighbor id=" + I2S(a) + " dir=" + I2S(dir))
        return
    endif
    call AddEdge(a, b, dir)
endfunction

function Grid_EndManualEdges takes nothing returns nothing
    local integer total = CellCount
    local integer idx = 0
    local integer id
    local integer edgeCount = 0
    if not GridManualEdges then
        call DebugLogger_Log(LOG_WARN, "[grid] EndManualEdges without Begin")
        return
    endif
    loop
        exitwhen idx >= total
        set id = CellIds[idx]
        if LoadInteger(GridTable, id, HT_EDGE + DIR_RIGHT) >= 0 then
            set edgeCount = edgeCount + 1
        endif
        if LoadInteger(GridTable, id, HT_EDGE + DIR_DOWN) >= 0 then
            set edgeCount = edgeCount + 1
        endif
        set idx = idx + 1
    endloop
    call SaveInteger(GridTable, 0, HT_EDGE_COUNT, edgeCount)
    set GridManualEdges = false
    call AssertGridConnected()
    call DebugLogger_LogKey("[grid] ManualEdges done: bounds=" + I2S(BoundRows) + "x" + I2S(BoundCols) + " cells=" + I2S(total) + " edges=" + I2S(edgeCount))
endfunction

// 重置网格数据（尺寸、生成参数、边表）
function ResetAreaGrid takes nothing returns nothing
    local integer maxId = Grid_GetMaxId()
    local integer i = 0
    loop
        exitwhen i >= maxId
        call FlushChildHashtable(GridTable, i)
        set i = i + 1
    endloop
    call FlushChildHashtable(GridTable, 0)
    loop
        exitwhen i >= MAX_CELLS
        set CellPresent[i] = false
        set CellIds[i] = -1
        set i = i + 1
    endloop
    set CellCount = 0
    set BoundRows = 0
    set BoundCols = 0
    set GridGenMode = GRID_GEN_DFS
    set GridExtraEdgeBudget = DEFAULT_EXTRA_EDGE_BUDGET
    set GridBraidChance = DEFAULT_BRAID_CHANCE
    set GridManualEdges = false
endfunction

endlibrary
#endif
