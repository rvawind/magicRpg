
library NNCouEnumRect
globals
private group g = null
private real Al = 0
private real Bl = 0
private real Cl = 0
private real Aw = 0
private real Bw = 0
private real Cw = 0
private real r = 0
private real tw = 0
private real tl = 0
endglobals

//|Ax + Bx + C| / （A2 + B2）^0.5 点到直线的距禄1�7
private function EnumRectUnitFilter takes nothing returns nothing
    local real x = GetUnitX(GetEnumUnit())
    local real y = GetUnitX(GetEnumUnit())
    local real distanceL = (Al * x + Bl * y + Cl) / SquareRoot(Al*Al + Bl*Bl)
    local real distanceW = (Aw * x + Bw * y + Cw) / SquareRoot(Aw*Aw + Bw*Bw)
    if( (distanceL> tw / 2) or (distanceW > tl / 2) ) then
        call GroupRemoveUnit(g,GetEnumUnit())
    endif
endfunction

private function UnitHasNotAloc takes nothing returns boolean
    return GetUnitAbilityLevel(GetFilterUnit(),'Aloc') == 0
endfunction
//
//
//计算出中心点的直线和垂线
//并以斜线为半径画圆
public function EnumRectUnitByXY takes real x0,real y0,real x1,real y1,real length,real width returns group
    set Al = y1 - y0
    set Bl = x0 - x1
    set Cl = x1 * y0 - x0 * y1
    set Aw = Bl
    set Bw = 0 - Al
    set Cw = Al * y1 - Bl * x1
    set r = SquareRoot(length*length /4 +width*width /4)
    set g = CreateGroup()
    set tl = length
    set tw = width
    call GroupEnumUnitsInRange(g,x1,y1,r,Condition(function UnitHasNotAloc))
    call ForGroup(g, function EnumRectUnitFilter)
    return g
endfunction

//根据矩形的中心点选取单位
public function EnumRectUnitByCenterAngle takes real x1,real y1,real angle,real length,real width returns group
    local real x0 = x1+ length / 2 * CosBJ(angle-180)
    local real y0 = y1+ length / 2 * SinBJ(angle-180)
    return EnumRectUnitByXY(x0,y0,x1,y1,length,width)
endfunction


//根据矩形的起始点选取单位
public function  EnumRectUnitByBeginAngle takes real x0,real y0,real angle,real length,real width returns group
    local real x1 = x0+ length / 2 * CosBJ(angle)
    local real y1 = y0+ length / 2 * SinBJ(angle)
    //call BJDebugMsg("起点：("+R2S(x0)+","+R2S(y0)+")")
    //call BJDebugMsg("中点：("+R2S(x1)+","+R2S(y1)+")")
    return EnumRectUnitByXY(x0,y0,x1,y1,length,width)
endfunction

endlibrary
