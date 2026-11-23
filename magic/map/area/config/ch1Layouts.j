#ifndef CH1_LAYOUTS
#define CH1_LAYOUTS
/*
    第一章固定路径布局数据（5 套，A~E；来源 .team/design/ch1_layouts.md，保守版 13~14 房）
    - 仅数据/查询，不含章节注册与实现；供后续 ch1 章节配置使用。
    - type: 0=spawn 1=normal 2=elite 3=shop 4=boss；tutorial: 0=无 1=N1 2=N2。
    - cell 坐标为 5×4 包围盒内 (row,col)；edge 用 r*4+c 编码。
*/
library ch1Layouts
globals
    private constant integer LAYOUT_COUNT = 5
    private integer array LayoutCellOff
    private integer array LayoutCellCnt
    private integer array LayoutEdgeOff
    private integer array LayoutEdgeCnt
    private integer array CellRow
    private integer array CellCol
    private integer array CellType
    private integer array CellTut
    private integer array EdgeA
    private integer array EdgeB
    private boolean DataReady = false
endglobals
private function InitCh1Layouts takes nothing returns nothing
    set LayoutCellOff[0] = 0
    set LayoutCellCnt[0] = 13
    set LayoutEdgeOff[0] = 0
    set LayoutEdgeCnt[0] = 12
    set LayoutCellOff[1] = 13
    set LayoutCellCnt[1] = 14
    set LayoutEdgeOff[1] = 12
    set LayoutEdgeCnt[1] = 13
    set LayoutCellOff[2] = 27
    set LayoutCellCnt[2] = 13
    set LayoutEdgeOff[2] = 25
    set LayoutEdgeCnt[2] = 12
    set LayoutCellOff[3] = 40
    set LayoutCellCnt[3] = 14
    set LayoutEdgeOff[3] = 37
    set LayoutEdgeCnt[3] = 13
    set LayoutCellOff[4] = 54
    set LayoutCellCnt[4] = 13
    set LayoutEdgeOff[4] = 50
    set LayoutEdgeCnt[4] = 12
    set CellRow[0] = 4
    set CellCol[0] = 0
    set CellType[0] = 0
    set CellTut[0] = 0
    set CellRow[1] = 3
    set CellCol[1] = 0
    set CellType[1] = 1
    set CellTut[1] = 1
    set CellRow[2] = 2
    set CellCol[2] = 0
    set CellType[2] = 1
    set CellTut[2] = 2
    set CellRow[3] = 2
    set CellCol[3] = 1
    set CellType[3] = 1
    set CellTut[3] = 0
    set CellRow[4] = 1
    set CellCol[4] = 1
    set CellType[4] = 1
    set CellTut[4] = 0
    set CellRow[5] = 1
    set CellCol[5] = 2
    set CellType[5] = 1
    set CellTut[5] = 0
    set CellRow[6] = 1
    set CellCol[6] = 0
    set CellType[6] = 1
    set CellTut[6] = 0
    set CellRow[7] = 2
    set CellCol[7] = 3
    set CellType[7] = 1
    set CellTut[7] = 0
    set CellRow[8] = 2
    set CellCol[8] = 2
    set CellType[8] = 3
    set CellTut[8] = 0
    set CellRow[9] = 0
    set CellCol[9] = 1
    set CellType[9] = 2
    set CellTut[9] = 0
    set CellRow[10] = 0
    set CellCol[10] = 0
    set CellType[10] = 2
    set CellTut[10] = 0
    set CellRow[11] = 3
    set CellCol[11] = 2
    set CellType[11] = 2
    set CellTut[11] = 0
    set CellRow[12] = 0
    set CellCol[12] = 2
    set CellType[12] = 4
    set CellTut[12] = 0
    set CellRow[13] = 4
    set CellCol[13] = 3
    set CellType[13] = 0
    set CellTut[13] = 0
    set CellRow[14] = 4
    set CellCol[14] = 2
    set CellType[14] = 1
    set CellTut[14] = 1
    set CellRow[15] = 3
    set CellCol[15] = 2
    set CellType[15] = 1
    set CellTut[15] = 2
    set CellRow[16] = 2
    set CellCol[16] = 2
    set CellType[16] = 1
    set CellTut[16] = 0
    set CellRow[17] = 1
    set CellCol[17] = 2
    set CellType[17] = 3
    set CellTut[17] = 0
    set CellRow[18] = 1
    set CellCol[18] = 1
    set CellType[18] = 1
    set CellTut[18] = 0
    set CellRow[19] = 0
    set CellCol[19] = 1
    set CellType[19] = 4
    set CellTut[19] = 0
    set CellRow[20] = 0
    set CellCol[20] = 2
    set CellType[20] = 2
    set CellTut[20] = 0
    set CellRow[21] = 0
    set CellCol[21] = 3
    set CellType[21] = 2
    set CellTut[21] = 0
    set CellRow[22] = 1
    set CellCol[22] = 0
    set CellType[22] = 2
    set CellTut[22] = 0
    set CellRow[23] = 2
    set CellCol[23] = 1
    set CellType[23] = 2
    set CellTut[23] = 0
    set CellRow[24] = 3
    set CellCol[24] = 1
    set CellType[24] = 1
    set CellTut[24] = 0
    set CellRow[25] = 3
    set CellCol[25] = 0
    set CellType[25] = 1
    set CellTut[25] = 0
    set CellRow[26] = 4
    set CellCol[26] = 0
    set CellType[26] = 1
    set CellTut[26] = 0
    set CellRow[27] = 0
    set CellCol[27] = 0
    set CellType[27] = 0
    set CellTut[27] = 0
    set CellRow[28] = 1
    set CellCol[28] = 0
    set CellType[28] = 1
    set CellTut[28] = 1
    set CellRow[29] = 2
    set CellCol[29] = 0
    set CellType[29] = 1
    set CellTut[29] = 2
    set CellRow[30] = 2
    set CellCol[30] = 1
    set CellType[30] = 1
    set CellTut[30] = 0
    set CellRow[31] = 2
    set CellCol[31] = 2
    set CellType[31] = 3
    set CellTut[31] = 0
    set CellRow[32] = 1
    set CellCol[32] = 2
    set CellType[32] = 1
    set CellTut[32] = 0
    set CellRow[33] = 0
    set CellCol[33] = 2
    set CellType[33] = 4
    set CellTut[33] = 0
    set CellRow[34] = 2
    set CellCol[34] = 3
    set CellType[34] = 1
    set CellTut[34] = 0
    set CellRow[35] = 3
    set CellCol[35] = 2
    set CellType[35] = 1
    set CellTut[35] = 0
    set CellRow[36] = 3
    set CellCol[36] = 0
    set CellType[36] = 1
    set CellTut[36] = 0
    set CellRow[37] = 1
    set CellCol[37] = 3
    set CellType[37] = 2
    set CellTut[37] = 0
    set CellRow[38] = 4
    set CellCol[38] = 2
    set CellType[38] = 2
    set CellTut[38] = 0
    set CellRow[39] = 3
    set CellCol[39] = 3
    set CellType[39] = 2
    set CellTut[39] = 0
    set CellRow[40] = 0
    set CellCol[40] = 3
    set CellType[40] = 0
    set CellTut[40] = 0
    set CellRow[41] = 1
    set CellCol[41] = 3
    set CellType[41] = 1
    set CellTut[41] = 1
    set CellRow[42] = 2
    set CellCol[42] = 3
    set CellType[42] = 1
    set CellTut[42] = 2
    set CellRow[43] = 2
    set CellCol[43] = 2
    set CellType[43] = 1
    set CellTut[43] = 0
    set CellRow[44] = 2
    set CellCol[44] = 1
    set CellType[44] = 1
    set CellTut[44] = 0
    set CellRow[45] = 1
    set CellCol[45] = 1
    set CellType[45] = 1
    set CellTut[45] = 0
    set CellRow[46] = 0
    set CellCol[46] = 1
    set CellType[46] = 1
    set CellTut[46] = 0
    set CellRow[47] = 0
    set CellCol[47] = 0
    set CellType[47] = 4
    set CellTut[47] = 0
    set CellRow[48] = 2
    set CellCol[48] = 0
    set CellType[48] = 3
    set CellTut[48] = 0
    set CellRow[49] = 1
    set CellCol[49] = 0
    set CellType[49] = 2
    set CellTut[49] = 0
    set CellRow[50] = 3
    set CellCol[50] = 2
    set CellType[50] = 1
    set CellTut[50] = 0
    set CellRow[51] = 3
    set CellCol[51] = 1
    set CellType[51] = 2
    set CellTut[51] = 0
    set CellRow[52] = 3
    set CellCol[52] = 0
    set CellType[52] = 2
    set CellTut[52] = 0
    set CellRow[53] = 4
    set CellCol[53] = 1
    set CellType[53] = 2
    set CellTut[53] = 0
    set CellRow[54] = 2
    set CellCol[54] = 3
    set CellType[54] = 0
    set CellTut[54] = 0
    set CellRow[55] = 2
    set CellCol[55] = 2
    set CellType[55] = 1
    set CellTut[55] = 1
    set CellRow[56] = 2
    set CellCol[56] = 1
    set CellType[56] = 1
    set CellTut[56] = 2
    set CellRow[57] = 3
    set CellCol[57] = 1
    set CellType[57] = 1
    set CellTut[57] = 0
    set CellRow[58] = 4
    set CellCol[58] = 1
    set CellType[58] = 1
    set CellTut[58] = 0
    set CellRow[59] = 4
    set CellCol[59] = 2
    set CellType[59] = 1
    set CellTut[59] = 0
    set CellRow[60] = 4
    set CellCol[60] = 3
    set CellType[60] = 4
    set CellTut[60] = 0
    set CellRow[61] = 2
    set CellCol[61] = 0
    set CellType[61] = 3
    set CellTut[61] = 0
    set CellRow[62] = 1
    set CellCol[62] = 0
    set CellType[62] = 1
    set CellTut[62] = 0
    set CellRow[63] = 0
    set CellCol[63] = 0
    set CellType[63] = 1
    set CellTut[63] = 0
    set CellRow[64] = 0
    set CellCol[64] = 1
    set CellType[64] = 2
    set CellTut[64] = 0
    set CellRow[65] = 4
    set CellCol[65] = 0
    set CellType[65] = 2
    set CellTut[65] = 0
    set CellRow[66] = 3
    set CellCol[66] = 0
    set CellType[66] = 2
    set CellTut[66] = 0
    set EdgeA[0] = 16
    set EdgeB[0] = 12
    set EdgeA[1] = 12
    set EdgeB[1] = 8
    set EdgeA[2] = 8
    set EdgeB[2] = 9
    set EdgeA[3] = 9
    set EdgeB[3] = 5
    set EdgeA[4] = 5
    set EdgeB[4] = 6
    set EdgeA[5] = 6
    set EdgeB[5] = 2
    set EdgeA[6] = 9
    set EdgeB[6] = 10
    set EdgeA[7] = 5
    set EdgeB[7] = 1
    set EdgeA[8] = 1
    set EdgeB[8] = 0
    set EdgeA[9] = 10
    set EdgeB[9] = 14
    set EdgeA[10] = 8
    set EdgeB[10] = 4
    set EdgeA[11] = 10
    set EdgeB[11] = 11
    set EdgeA[12] = 19
    set EdgeB[12] = 18
    set EdgeA[13] = 18
    set EdgeB[13] = 14
    set EdgeA[14] = 14
    set EdgeB[14] = 10
    set EdgeA[15] = 10
    set EdgeB[15] = 6
    set EdgeA[16] = 6
    set EdgeB[16] = 5
    set EdgeA[17] = 5
    set EdgeB[17] = 1
    set EdgeA[18] = 6
    set EdgeB[18] = 2
    set EdgeA[19] = 2
    set EdgeB[19] = 3
    set EdgeA[20] = 5
    set EdgeB[20] = 4
    set EdgeA[21] = 5
    set EdgeB[21] = 9
    set EdgeA[22] = 14
    set EdgeB[22] = 13
    set EdgeA[23] = 13
    set EdgeB[23] = 12
    set EdgeA[24] = 12
    set EdgeB[24] = 16
    set EdgeA[25] = 0
    set EdgeB[25] = 4
    set EdgeA[26] = 4
    set EdgeB[26] = 8
    set EdgeA[27] = 8
    set EdgeB[27] = 9
    set EdgeA[28] = 9
    set EdgeB[28] = 10
    set EdgeA[29] = 10
    set EdgeB[29] = 6
    set EdgeA[30] = 6
    set EdgeB[30] = 2
    set EdgeA[31] = 10
    set EdgeB[31] = 11
    set EdgeA[32] = 10
    set EdgeB[32] = 14
    set EdgeA[33] = 8
    set EdgeB[33] = 12
    set EdgeA[34] = 6
    set EdgeB[34] = 7
    set EdgeA[35] = 14
    set EdgeB[35] = 18
    set EdgeA[36] = 11
    set EdgeB[36] = 15
    set EdgeA[37] = 3
    set EdgeB[37] = 7
    set EdgeA[38] = 7
    set EdgeB[38] = 11
    set EdgeA[39] = 11
    set EdgeB[39] = 10
    set EdgeA[40] = 10
    set EdgeB[40] = 9
    set EdgeA[41] = 9
    set EdgeB[41] = 5
    set EdgeA[42] = 5
    set EdgeB[42] = 1
    set EdgeA[43] = 1
    set EdgeB[43] = 0
    set EdgeA[44] = 9
    set EdgeB[44] = 8
    set EdgeA[45] = 8
    set EdgeB[45] = 4
    set EdgeA[46] = 10
    set EdgeB[46] = 14
    set EdgeA[47] = 14
    set EdgeB[47] = 13
    set EdgeA[48] = 13
    set EdgeB[48] = 12
    set EdgeA[49] = 13
    set EdgeB[49] = 17
    set EdgeA[50] = 11
    set EdgeB[50] = 10
    set EdgeA[51] = 10
    set EdgeB[51] = 9
    set EdgeA[52] = 9
    set EdgeB[52] = 13
    set EdgeA[53] = 13
    set EdgeB[53] = 17
    set EdgeA[54] = 17
    set EdgeB[54] = 18
    set EdgeA[55] = 18
    set EdgeB[55] = 19
    set EdgeA[56] = 9
    set EdgeB[56] = 8
    set EdgeA[57] = 8
    set EdgeB[57] = 4
    set EdgeA[58] = 4
    set EdgeB[58] = 0
    set EdgeA[59] = 0
    set EdgeB[59] = 1
    set EdgeA[60] = 17
    set EdgeB[60] = 16
    set EdgeA[61] = 16
    set EdgeB[61] = 12
endfunction

private function EnsureData takes nothing returns nothing
    if not DataReady then
        set DataReady = true
        call InitCh1Layouts()
    endif
endfunction

public function GetLayoutCount takes nothing returns integer
    call EnsureData()
    return LAYOUT_COUNT
endfunction
public function GetLayoutCellCount takes integer layout returns integer
    call EnsureData()
    if layout < 0 or layout >= LAYOUT_COUNT then
        return 0
    endif
    return LayoutCellCnt[layout]
endfunction
public function GetLayoutCellRow takes integer layout, integer index returns integer
    call EnsureData()
    return CellRow[LayoutCellOff[layout] + index]
endfunction
public function GetLayoutCellCol takes integer layout, integer index returns integer
    call EnsureData()
    return CellCol[LayoutCellOff[layout] + index]
endfunction
public function GetLayoutCellType takes integer layout, integer index returns integer
    call EnsureData()
    return CellType[LayoutCellOff[layout] + index]
endfunction
public function GetLayoutCellTutorial takes integer layout, integer index returns integer
    call EnsureData()
    return CellTut[LayoutCellOff[layout] + index]
endfunction
public function GetLayoutEdgeCount takes integer layout returns integer
    call EnsureData()
    if layout < 0 or layout >= LAYOUT_COUNT then
        return 0
    endif
    return LayoutEdgeCnt[layout]
endfunction
public function GetLayoutEdgeARow takes integer layout, integer index returns integer
    call EnsureData()
    return EdgeA[LayoutEdgeOff[layout] + index] / 4
endfunction
public function GetLayoutEdgeACol takes integer layout, integer index returns integer
    call EnsureData()
    return EdgeA[LayoutEdgeOff[layout] + index] - (EdgeA[LayoutEdgeOff[layout] + index] / 4) * 4
endfunction
public function GetLayoutEdgeBRow takes integer layout, integer index returns integer
    call EnsureData()
    return EdgeB[LayoutEdgeOff[layout] + index] / 4
endfunction
public function GetLayoutEdgeBCol takes integer layout, integer index returns integer
    call EnsureData()
    return EdgeB[LayoutEdgeOff[layout] + index] - (EdgeB[LayoutEdgeOff[layout] + index] / 4) * 4
endfunction
private function Init takes nothing returns nothing
    call InitCh1Layouts()
endfunction
endlibrary
#endif
