
library NNCouString

//获得字符串ch第一次出现在字符串src的位置，并返回
function NNCFind takes string src,string ch returns integer
    local integer index = 0
    local integer srcLength = StringLength(src)
    local integer chLength = StringLength(ch)
    loop
        exitwhen (srcLength-chLength)<index
        if(ch==(SubString(src,index,(index+chLength)))) then
            return index
        endif
        set index = index+1
    endloop
    return -1
endfunction

//获得字符ch最后一次出现在字符串src的位置，并返回
function NNCGetLastIndex takes string src,string ch returns integer
    local integer start = 0
    local integer end = 0
    local integer lengthSrc = StringLength(src)
    local integer lengthCh = StringLength(ch)
    if(NNCFind(src,ch)==-1) then 
        return -1
    endif
	set end = lengthSrc
    set start = lengthSrc - lengthCh
	//call BJDebugMsg(I2S(end))
    loop
        exitwhen start < 0
        if(SubString(src,start,end) == ch) then
            return start
		else
			call BJDebugMsg(SubString(src,start,end))
        endif
        set start = start - 1
        set end = start + lengthCh
		//call BJDebugMsg("当前查找的最后一个位置为："+I2S(end))
		//call BJDebugMsg("当前查找的位置为："+I2S(start))
    endloop
    return -1
endfunction

//将字符串src根据字符串ch分割成N份，并把每份的数据储存于key1的哈希中，返回分割后的数量，并储存于key1的0值中。
function NNCSplit takes string src,string ch,string key1 returns integer
    local integer chLength = StringLength(ch)
    local integer srcLength = StringLength(src)
    local integer count = 0
    local integer index = NNCFind(src,ch)
    loop
        set count = count + 1
        exitwhen (-1==index or srcLength==0)
        if(ch=="") then
            call SaveStr(nncouHT,StringHash(key1),count,SubString(src,0,1))
            set src = SubString(src,1,srcLength)
        else
            if(SubString(src,0,index)=="")then
                call SaveStr(nncouHT,StringHash(key1),count," ")
            else
                call SaveStr(nncouHT,StringHash(key1),count,SubString(src,0,index))
            endif
            set src = SubString(src,index+chLength,srcLength)
        endif
        set index = NNCFind(src,ch)
        set srcLength = StringLength(src)
    endloop
    call SaveStr(nncouHT,StringHash(key1),count,src)
    call SaveInteger(nncouHT,StringHash(key1),0,count)
	return count
endfunction

function NNCLoadSpiltString takes string key1 ,integer key2 returns string
    return LoadStr(nncouHT,StringHash(key1),key2)
endfunction
endlibrary
