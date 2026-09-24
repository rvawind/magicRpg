
#include "nncou\\NNCouInterface.j"

library MaxSpeed requires NNCouInterface
    globals
    private constant real PERIOD = 0.03125
    private integer isAble = 0
    endglobals
    
    public function SetIsAble takes integer bool returns nothing
        set isAble = bool
    endfunction

    private module O
    private static method onInit takes nothing returns nothing
        call TimerStart(CreateTimer(),PERIOD,true,function thistype.iterate)
    endmethod
    endmodule
    
    struct ModSpeed extends array
    private thistype recycle
    private static integer ic = 0 //instance count
    private thistype next //readonly
    private thistype prev //readonly
    private unit u
    private real x
    private real y
    readonly real setSpeed //readonly
    private real bonus
    
    private static real tempx
    private static real tempy
    private static real incx //increament 增量
    private static real incy
    private static real incDist
    
    method modifyAmount takes real amount returns nothing
        if amount <= 522 then
            call SetUnitTimeScale(this.u,1)
            //call BJDebugMsg("amount<522,销毁")
            call this.destroy()
        else
            set this.bonus= (amount-522) * PERIOD
        endif
        set this.setSpeed = amount
        //call BJDebugMsg("this.setSpeed: "+R2S(this.setSpeed))
    endmethod
    
    static method register takes unit u returns thistype
        local thistype this = thistype(0).recycle
        if(0==this)then
            set this=ic+1
            set ic = this
        else
            set thistype(0).recycle = recycle
        endif
        set thistype(0).next.prev = this
        set this.next= thistype(0).next
        set thistype(0).next = this
        set this.prev = thistype(0)
        set this.u = u
        set this.bonus = 0.
        set this.x = GetUnitX(u)
        set this.y = GetUnitY(u)
        return this
    endmethod
    
    //重载[]为以下方法
    static method operator [] takes unit u returns thistype
        local thistype this = thistype(0)
        loop
            set this = this.next
            //call BJDebugMsg("this: "+I2S(this))
            exitwhen this == 0
            if this.u == u then
                //call BJDebugMsg("FIND")
                //call BJDebugMsg(GetUnitName(this.u) + " setSpeed :" + R2S(this.setSpeed))
                return this
            endif
        endloop
        return thistype.register(u)
    endmethod
    
    private static method move takes thistype t returns nothing
        local thistype this = t
        if IsUnitType(this.u,UNIT_TYPE_DEAD) then
            call this.destroy()
        else
            set thistype.tempx = GetUnitX(this.u)
            set thistype.tempy = GetUnitY(this.u)
            set thistype.incx = thistype.tempx - this.x
            set thistype.incy = thistype.tempy - this.y
            set thistype.incDist = SquareRoot(thistype.incx * thistype.incx + thistype.incy * thistype.incy)
            if(thistype.incDist>this.setSpeed *0.001 and GetUnitAbilityLevel(this.u,'BSTN')<1 and /*
                */ (NNCIsUnitCC(this.u,2)==false) and /*
                */ not IsUnitPaused(this.u) and this.setSpeed>522) then
                call SetUnitTimeScale(this.u,1+this.bonus/300)
                set thistype.incDist = this.bonus / thistype.incDist
                set thistype.tempx = thistype.tempx +thistype.incx * thistype.incDist
                set thistype.tempy = thistype.tempy +thistype.incy * thistype.incDist
                call SetUnitX(this.u,thistype.tempx)
                call SetUnitY(this.u,thistype.tempy)
                set this.x = thistype.tempx
                set this.y = thistype.tempy
                //call BJDebugMsg(R2S(thistype.incDist))
            endif
        endif    
    endmethod
    
    private static method iterate takes nothing returns nothing
        local thistype this = thistype(0)
        loop
            set this = this.next
            exitwhen this == 0
            if IsUnitType(this.u,UNIT_TYPE_DEAD) then
                call this.destroy()
            else
                call move(this)
            endif
        endloop
    endmethod
    
    method destroy takes nothing returns nothing
        set this.prev.next = this.next
        set this.next.prev = this.prev
        set this.recycle = thistype(0).recycle
        set this.setSpeed = 0
        set thistype(0).recycle = this
    endmethod
    
    implement O
    
    endstruct
    
    public function GetUnitMoveSpeedEx takes unit u returns real
        //call BJDebugMsg("获取移速")
        //call BJDebugMsg(R2S(ModSpeed[u].setSpeed))
        return RMaxBJ(GetUnitMoveSpeed(u),ModSpeed[u].setSpeed)
        //return 100
    endfunction
    
    function SetUnitMoveSpeedEx takes unit u ,real speed returns nothing
        //call BJDebugMsg("speed:"+R2S(speed))
        if(isAble==0)then
            return
        endif
        call ModSpeed[u].modifyAmount(speed)
    endfunction
    
    hook SetUnitMoveSpeed SetUnitMoveSpeedEx
    endlibrary
    