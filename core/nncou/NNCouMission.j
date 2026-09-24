
library NNCouMission uses NNCouString
    globals
        private hashtable ht = InitHashtable()
		private string COLOR_TITLE = "|cffccffcc"
    endglobals
	public function setTitleColor takes string str returns nothing
		set COLOR_TITLE = str
	endfunction
	public function setCount takes string name,integer count returns nothing
		call SaveInteger(ht,StringHash(name),StringHash("count"),count)
	endfunction
    public function setTitle takes string name,string title returns nothing
        call SaveStr(ht,StringHash(name),StringHash("title"),title)
    endfunction
    
    public function setDescribe takes string name,integer id,string describe returns nothing
        call SaveStr(ht,StringHash(name),StringHash("describe"+I2S(id)),describe)
    endfunction

    public function setValueHandle takes string name,integer id,integer key1 returns nothing
        call SaveInteger(ht,StringHash(name),StringHash("value"+I2S(id)),key1)
    endfunction

    public function getValueHandle takes string name,integer id returns integer
        return LoadInteger(ht,StringHash(name),StringHash("value"+I2S(id)))
    endfunction

    public function getValue takes player p,string name,integer id returns integer
        local integer key1 = LoadInteger(ht,StringHash(name),StringHash("value"+I2S(id)))
        return LoadInteger(YDHT,GetHandleId(p),key1)
    endfunction

    public function getTitle takes string name ,boolean isColor returns string
		if(isColor==false) then
			if(HaveSavedString(ht,StringHash(name),StringHash("title"))) then
				return LoadStr(ht,StringHash(name),StringHash("title"))
			endif
			return name
		else
			if(HaveSavedString(ht,StringHash(name),StringHash("title"))) then
				return COLOR_TITLE+LoadStr(ht,StringHash(name),StringHash("title"))+"|r"
			endif
			return COLOR_TITLE+name+"|r"
		endif
    endfunction

    public function getDescribe takes string name,integer id returns string
        return LoadStr(ht,StringHash(name),StringHash("describe"+I2S(id)))
    endfunction
	public function getCount takes string name returns integer
		return LoadInteger(ht,StringHash(name),StringHash("count"))
	endfunction
    public function create takes string name,integer count,integer flag returns nothing
        call SaveInteger(ht,StringHash(name),StringHash("type"),1)
		call SaveInteger(ht,StringHash(name),StringHash("count"),count)
    endfunction
    
    /*public function createKillerMission takes string name,integer typeid,integer count,integer flag returns nothing
        call SaveInteger(ht,StringHash(name),StringHash("type"),2)
        call setValueHandle(name,typeid)
    endfunction*/
    
endlibrary
