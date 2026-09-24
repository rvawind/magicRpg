#ifndef KKPREINCLUDE
#define KKPREINCLUDE


library LBKKPRE


    native DzSendKeyboard takes player p, integer key_code, integer is_down returns nothing
    native DzForceUiKeyboard takes player p, integer key_code, integer is_down returns nothing
    native DzDisableWindowKeyboard takes player p, integer key_code returns nothing 
    native DzDisableGameUIKeyboard takes player p, integer key_code returns nothing 
    native DzUnitCanPlaceAround takes widget obj, real x, real y returns boolean 

    function KKUnitCanPlaceAroundLoc takes widget obj, location loc returns boolean 
            return DzUnitCanPlaceAround(obj, GetLocationX(loc), GetLocationY(loc))
    endfunction     

    function kkUnitCanPlaceAroundItem takes widget obj, real x, real y returns boolean
            return DzUnitCanPlaceAround(obj, x, y)
    endfunction 

    function KKUnitCanPlaceAroundLocItem takes widget obj, location loc returns boolean
            return DzUnitCanPlaceAround(obj, GetLocationX(loc), GetLocationY(loc))
    endfunction 

    native DzPositionCanPlaceAround takes real x, real y, real collision_size, integer collision_type returns boolean 

    function KKPositionCanPlaceAroundLoc takes location loc, real collision_size, integer collision_type returns boolean 
            return DzPositionCanPlaceAround(GetLocationX(loc), GetLocationY(loc), collision_size, collision_type)
    endfunction 

    native DzGetTerrainZ takes real x, real y returns real 
    native DzGetUnitZ takes unit u returns real 
    native DzGetUnitOverheadOffset takes widget u returns real

    native DzFrameSetModelEnableWideScreen takes integer frame, boolean is_enable returns nothing 

    native DzSetUnitAbilityEnable takes unit u, integer abil_id returns boolean
    native DzSetUnitAbilityDisable takes unit u, integer abil_id returns boolean
    native DzGetUnitAbilityIsDisabled takes unit u, integer abil_id returns boolean
    native DzGetUnitAbilityDisabledCount takes unit u, integer abil_id returns integer
    native DzSetUnitAbilityTechReach takes unit u, integer abil_id, boolean reach returns boolean
    native DzGetUnitAbilityTechReach takes unit u, integer abil_id returns boolean
    native DzSetUnitAbilityTechReachTip takes unit u, integer abil_id, string tip returns boolean 

    native DzAsyncGetCurrentBuildingAbilityId takes nothing returns integer 
    native DzAsyncGetCurrentBuildingUnitId takes nothing returns integer 
    native DzFrameUnlockMouseRectLimit takes boolean is_unlock returns nothing 
    native KKSimpleFrameIsVisible takes integer simple_frame returns boolean
    native DzFrameGetChatEditBar takes nothing returns integer

    native DzGetLocalChatRecipient takes nothing returns integer 
    native DzPlayerSendChat takes player p, string msg, integer recipient returns nothing 



    native DzEnableHashtableSetNull takes boolean is_enable returns nothing 
    native DzSetItemCollisionSize takes item it, real size returns nothing 
    native DzGetItemCollisionSize takes item it returns real 
    native DzSetUnitDisableLocalOrder takes unit u, boolean is_disable returns nothing 
    native DzGetUnitDisableLocalOrder takes unit u returns boolean 
    native DzSetUnitDisableControlOrder takes unit u, boolean is_disable returns nothing 
    native DzGetUnitDisableControlOrder takes unit u returns boolean 
    native DzSetUnitAttack1TargetType takes unit u, integer target_type returns nothing
    native DzGetUnitAttack1TargetType takes unit u returns integer
    native DzSetUnitAttack2TargetType takes unit u, integer target_type returns nothing
    native DzGetUnitAttack2TargetType takes unit u returns integer
    native DzSetUnitAsAttackTargetType takes unit u, integer target_type returns nothing
    native DzGetUnitAsAttackTargetType takes unit u returns integer
    native DzFrameBindAddHideRect takes integer frame, real left, real bottom, real right, real top, real width, real height returns nothing 
    native DzFrameGetRealWidth takes integer frame returns real 
    native DzFrameGetRealHeight takes integer frame returns real 
    native DzSetUnitAbilitySpellBookAddAbility takes unit u, integer abil_id, integer add_abil_id returns boolean
    native DzSetUnitAbilitySpellBookRemoveAbility takes unit u, integer abil_id, integer remove_abil_id returns boolean
    native KKCommandButtonGetAbilityId takes integer command_button returns integer 
    native KKCommandButtonGetOrderId takes integer command_button returns integer 
    native DzFixUnitEventMemoryLeak takes nothing returns nothing

endlibrary

#endif

