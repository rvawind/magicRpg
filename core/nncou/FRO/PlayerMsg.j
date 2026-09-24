
#ifndef BZAPIINCLUDE
#include "BlizzardAPI.j"
#endif
#ifndef KKAPIINCLUDE 
#include "KKAPI.j"
#endif
    
library FroMsg initializer InitFroMsgSystem requires BzAPI,LBKKAPI

    globals


        private real MSG_BOX_WIDTH = 0.6  // 消息容器宽度（倍率）
        private real MSG_BOX_HEIGHT_MAX = 0.35 // 消息容器最大高度（倍率）
        private real MSG_BOX_PADDING = 0.003  // 消息框体间距（倍率）
        private real LINE_HEIGHT = 0.01407 // 单行文字高度（倍率）
        private real IMG_HEIGHT = 0.045 // 图片高度（倍率）
        private real IMG_WIDTH = 0.045  // 图片宽度（倍率）
        private string msgBoxTexture = "war3mapImported\\blank.tga" // 消息容器背景贴图路径
        private string msgFrameTexture = "war3mapImported\\blank.tga" // 消息框体背景贴图路径 
        private string msgFrameTextTexture = "" // 消息文本框体背景贴图路径
        private string fontPath = "" // 默认字体路径
        private real fontSize = 0.0016 // 默认字体大小
        private integer fontFlag = 3 // 默认字体样式 0-普通 1-粗体 2-斜体 3-粗斜体
        private real gifModelScale = 0.008   //动态框体缩放比例

        private constant integer MSG_MAX_COUNT = 20     // 最大消息数量
        private constant real DEFAULT_SHOW_TIME = 10.0 // 默认显示时间（秒）
        private constant real DEFAULT_FADE_TIME = 1.0 // 默认消逝时间（秒）


        private msgFramePool globalMsgPool = 0 
        private timer msgUpdateTimer = null 

        private integer msgBoxFrame = 0 
        private integer msgCount = 0 
        
    endglobals



    struct PlayerMsg
        string msgContent           // 消息内容
        string imgPath              // 图片路径
        integer imgFlag             // 图片是否平铺 0-否 1-是
        integer msgType             // 消息类型 0-普通文字 1-图片
        integer isGif               // 是否为动态图片 0-否 1-是
        integer gifIndex            // 动态图片动画序号
        boolean isLoop              // 动态图片是否循环播放

        integer isShow              // 是否正在显示 0-否 1-是
        integer isFading            // 是否正在消逝 0-否 1-是
        real elapsedTime            // 已经显示时间（秒）
        real showTime               // 显示时间（秒）
        real fadeTime               // 消逝时间（秒）
        real height                // 消息框体高度
        real currentY              // 当前Y坐标（对于外部容器底部），用于定位
        integer index              // 消息索引 当前队列位置
        private integer msgFrame              // 消息框体
        private integer msgFrameText          // 文本框体
        private integer msgFrameImg           // 图片框体
        private integer msgFrameGif           // 动态图片框体

        method testMsgFrame takes nothing returns nothing
            call DzFrameSetTexture(msgFrame,"war3mapImported\\chen.blp",1)
        endmethod

        static method create takes nothing returns PlayerMsg
            local PlayerMsg msgObj = PlayerMsg.allocate()
            set msgObj.msgType = 0
            set msgObj.showTime = DEFAULT_SHOW_TIME
            set msgObj.fadeTime = DEFAULT_FADE_TIME
            //创建框体
            set msgObj.msgFrame = DzCreateFrameByTagName( "BACKDROP", "FroMsgText"+I2S(msgCount), msgBoxFrame, "template", 0)
            set msgObj.msgFrameText = DzCreateFrameByTagName( "TEXT", "FroMsgTextContent"+I2S(msgCount), msgObj.msgFrame, "template", 0)
            set msgObj.msgFrameImg = DzCreateFrameByTagName( "BACKDROP", "FroMsgImgContent"+I2S(msgCount), msgObj.msgFrame, "template", 0)
            set msgObj.msgFrameGif = DzCreateFrameByTagName( "SPRITE", "FroMsgGifContent"+I2S(msgCount), msgObj.msgFrame, "template", 0)

            //设置初始贴图
            call DzFrameSetTexture(msgObj.msgFrame, msgFrameTexture, 0)

            call DzFrameSetEnable( msgObj.msgFrameText, false)
            //call DzFrameSetEnable( msgObj.msgFrameGif, false)
            call DzFrameSetIgnoreTrackEvents( msgObj.msgFrameGif, true)

            //设置框体位置
            
            call DzFrameSetPoint(msgObj.msgFrame, 6, msgBoxFrame, 6, 0.0, 0.0)
            call DzFrameSetPoint(msgObj.msgFrameText, 6, msgObj.msgFrame, 6, 0.0, 0.0)
            call DzFrameSetPoint(msgObj.msgFrameImg, 6, msgObj.msgFrame, 6, 0.0, 0.0)
            call DzFrameSetPoint(msgObj.msgFrameGif, 6, msgObj.msgFrame, 6, 0.0, 0.0)
            //设置框体大小
            call DzFrameSetSize(msgObj.msgFrame, MSG_BOX_WIDTH, LINE_HEIGHT)
            call DzFrameSetSize(msgObj.msgFrameText, 0, LINE_HEIGHT)
            call DzFrameSetSize(msgObj.msgFrameImg, IMG_WIDTH, IMG_HEIGHT) // 固定大小
            call DzFrameSetSize(msgObj.msgFrameGif, 0, IMG_HEIGHT) // 固定大小

            //初始化框体
            call msgObj.reset()
            //隐藏所有内容
            call DzFrameShow(msgObj.msgFrame, false)
            call DzFrameShow(msgObj.msgFrameText, false)
            call DzFrameShow(msgObj.msgFrameImg, false)
            call DzFrameShow(msgObj.msgFrameGif, false)
            return msgObj
        endmethod

        
        method setFadeTime takes real time returns nothing
            set fadeTime = time
        endmethod

        method setShowTime takes real time returns nothing
            set showTime = time
        endmethod

        method setPostionY takes real y returns nothing
            set currentY = y
            call DzFrameSetPoint(msgFrame, 6, msgBoxFrame, 6, 0.0, currentY)
            // call BJDebugMsg("FroMsg:setPostionY - idx=" + I2S(index) + " y=" + R2S(currentY))
        endmethod

        method setAlpha takes integer alpha returns nothing
            call DzFrameSetAlpha(msgFrame, alpha)
            call DzFrameSetAlpha(msgFrameText, alpha)
            call DzFrameSetAlpha(msgFrameImg, alpha)
            call DzFrameSetAlpha(msgFrameGif, alpha)
        endmethod

        // 禁止外部通过DzFrameShow方法隐藏消息框体，必须通过 reset 方法
        method reset takes nothing returns nothing
            set isShow = 0
            set isFading = 0
            set elapsedTime = 0.0
            set currentY = 0
            set msgContent = ""
            set imgPath = ""
            set imgFlag = 0
            set msgType = 0
            set isGif = 0
            set gifIndex = 0
            set isLoop = false
            // 将位置设置为未显示位置并隐藏所有子控件
            call setPostionY(currentY)
            call setAlpha(0)
            call DzFrameShow(msgFrame, false)
            call DzFrameShow(msgFrameText, false)
            call DzFrameShow(msgFrameImg, false)
            call DzFrameShow(msgFrameGif, false)
            // 调试信息（如需安静可注释）
            // call BJDebugMsg("FroMsg:reset - idx=" + I2S(index))
        endmethod

        // 禁止外部通过DzFrameShow方法显示消息框体，必须通过 show 方法
        method show takes nothing returns nothing
            set isShow = 1
            set isFading = 0
            set elapsedTime = 0.0
            if(msgType == 1) then
                call DzFrameShow(msgFrameText, true) //由于需要显示发言人，不隐藏文字框体
                // call BJDebugMsg("FroMsg:show - idx=" + I2S(index) + " show IMG")
                if( isGif == 1) then
                    // 动态图片消息
                    call DzFrameShow(msgFrameGif, true)
                    call DzFrameShow(msgFrameImg, false)
                else
                    // 静态图片消息
                    call DzFrameShow(msgFrameImg, true)
                    call DzFrameShow(msgFrameGif, false)
                endif
            else
                //文字消息
                call DzFrameShow(msgFrameText, true)
                call DzFrameShow(msgFrameImg, false)
                call DzFrameShow(msgFrameGif, false)
                // call BJDebugMsg("FroMsg:show - idx=" + I2S(index) + " show TEXT")
            endif
            
            call setAlpha(255) // 重置透明度
            call DzFrameShow(msgFrame, true)
        endmethod

        
        method setMsg takes string msg,string imgPath,integer imgFlag returns nothing
            if(imgPath != "") then
                set msgType = 1
            else
                set msgType = 0
            endif
            set msgContent = msg

            //设置消息内容
            call DzFrameSetText(msgFrameText, msgContent)
            if(fontPath != "") then
                call DzFrameSetFont(msgFrameText, fontPath, fontSize, fontFlag)
            endif

            if (msgType == 1) then
                //静态图片消息
                set height = IMG_HEIGHT
                //修改消息框体高度以适应
                call DzFrameSetSize(msgFrame, MSG_BOX_WIDTH, IMG_HEIGHT)
                call DzFrameSetSize(msgFrameImg, IMG_WIDTH, IMG_HEIGHT)
                // call DzFrameSetSize(msgFrameGif, 0, 0)
                //图片消息，显示图片
                call DzFrameSetTexture(msgFrameImg, imgPath, imgFlag)
                //设置文字框体左上锚点为消息框体左上锚点
                call DzFrameSetPoint(msgFrameText, 0, msgFrame, 0, 0.0, 0.0)
                //设置图片框体左上锚点在文字框体右上锚点
                call DzFrameSetPoint(msgFrameImg, 0, msgFrameText, 2, 0.0, 0.0)

                // call BJDebugMsg("FroMsg:setMsg - idx=" + I2S(index) + " type=IMG height=" + R2S(height))
            else
                //文字消息
                set height = LINE_HEIGHT
                call DzFrameSetSize(msgFrame, MSG_BOX_WIDTH, LINE_HEIGHT)
                call DzFrameSetSize(msgFrameText, MSG_BOX_WIDTH, LINE_HEIGHT)
                call DzFrameSetPoint(msgFrame, 6, msgBoxFrame, 6, 0.0, 0.0)
                call DzFrameSetPoint(msgFrameText, 6, msgFrame, 6, 0.0, 0.0)
                // call BJDebugMsg("FroMsg:setMsg - idx=" + I2S(index) + " type=TEXT height=" + R2S(height)+ " width=" + R2S(MSG_BOX_WIDTH) + " content=" + msgContent)
            endif
        endmethod

        method setGifMsg takes string msg,string modelPath,integer modelType,integer flag,integer animateIndex,boolean isLoop,real gifSize returns nothing
            set msgType = 1
            set msgContent = msg
            set isGif = 1
            set gifIndex = animateIndex
            set isLoop = isLoop

            //设置消息内容
            call DzFrameSetText(msgFrameText, msgContent)
            if(fontPath != "") then
                call DzFrameSetFont(msgFrameText, fontPath, fontSize, fontFlag)
            endif
                        // 1      0.045       0.008 *1000
            set height = gifSize*IMG_HEIGHT

            //设置
            //修改消息框体高度以适应
            // call DzFrameSetSize(msgFrame, MSG_BOX_WIDTH, IMG_HEIGHT)
            // call DzFrameSetSize(msgFrameGif, IMG_WIDTH, IMG_HEIGHT)
            // call BJDebugMsg("FroMsg:setGifMsg - idx=" + I2S(index) + " type=GIF height=" + R2S(height) + " modelPath=" + modelPath + " modelType=" + I2S(modelType) + " flag=" + I2S(flag) + " gifSize=" + R2S(gifSize))
            call DzFrameSetSize(msgFrame, MSG_BOX_WIDTH, height)
            call DzFrameSetSize(msgFrameGif, 0, height)
            //设置gif模型路径
            call DzFrameSetModel( msgFrameGif, modelPath, modelType, flag)
            call DzFrameSetScale( msgFrameGif , gifSize * gifModelScale) //设置缩放比例
            //设置文字框体左上锚点为消息框体左上锚点
            call DzFrameSetPoint(msgFrameText, 0, msgFrame, 0, 0.0, 0.0)
            //设置图片框体左上锚点在文字框体右上锚点
            call DzFrameSetPoint(msgFrameGif, 3, msgFrameText, 5, 0.00, 0.0)
            call DzFrameSetPoint(msgFrameGif, 7, msgFrame, 7, 0.00, 0.0)

            
            call DzFrameSetEnable( msgFrameGif, false)
        endmethod

    endstruct


        //消息框体池，管理消息框体的创建和复用
    struct msgFramePool
        PlayerMsg array msgList[20]  // 消息列表
        integer firstMsgIndex = 0               // 最早消息索引
        
        //创建一个消息框体池
        static method create takes nothing returns msgFramePool
            local msgFramePool pool = msgFramePool.allocate()
            return pool
        endmethod

        //从池中取出闲置的消息框体，若没有则新建消息框体
        method getFrame takes nothing returns PlayerMsg
            local integer i =0
            //尝试寻找空框体
            loop
                exitwhen i >= MSG_MAX_COUNT
                if (this.msgList[i] == null) then
                    //新建消息框体
                    set this.msgList[i] = PlayerMsg.create()
                    set msgCount = msgCount + 1
                    // 记录槽位索引并初始化状态
                    set this.msgList[i].index = i
                    // call BJDebugMsg("FroMsg:getFrame - create slot=" + I2S(i))
                    return this.msgList[i]
                endif
                set i = i + 1
            endloop

            //没找到空框体，将最早的消息框体覆盖使用
            set i = this.firstMsgIndex
            set this.firstMsgIndex = ModuloInteger(this.firstMsgIndex + 1, MSG_MAX_COUNT)
            // 重用时记录索引并重置显示相关字段
            set this.msgList[i].index = i
            // call BJDebugMsg("FroMsg:getFrame - reuse slot=" + I2S(i))
            call msgList[i].reset()
            return this.msgList[i]
        endmethod
    endstruct
    
    //更新消息框体显示状态
    private function UpdateMsgFrames takes nothing returns nothing
        local integer i = 0
        local PlayerMsg msgObj = 0
        local real fadeProgress = 0.0
        loop
            exitwhen i >= MSG_MAX_COUNT
            set msgObj = globalMsgPool.msgList[i]
            if (msgObj != 0) then
                //正在显示的消息
                if (msgObj.isShow == 1) then
                    set msgObj.elapsedTime = msgObj.elapsedTime + 0.1
                    //检查是否达到显示时间，开始消逝
                    if (msgObj.isFading == 0 and msgObj.elapsedTime >= msgObj.showTime) then
                        set msgObj.isFading = 1
                        set msgObj.elapsedTime = 0.0
                        // call BJDebugMsg("FroMsg:UpdateMsgFrames - idx=" + I2S(i) + " start fading")
                    endif

                    //处理消逝过程
                    if (msgObj.isFading == 1) then
                        set fadeProgress = msgObj.elapsedTime / msgObj.fadeTime
                        if (fadeProgress >= 1.0) then
                            //消逝完成，隐藏消息框体
                            call msgObj.reset()
                            // call BJDebugMsg("FroMsg:UpdateMsgFrames - idx=" + I2S(i) + " faded out")
                        else
                            // 透明度函数 DzFrameSetAlpha(integer whichFrame,integer alpha)，alpha取值0-255，为0时完全透明
                            call msgObj.setAlpha(255 - R2I(fadeProgress * 255))
                        endif
                    endif
                endif
            endif
            set i = i + 1
        endloop
    endfunction

    private function CreateFrameBox takes nothing returns integer
        local integer f = DzCreateFrameByTagName( "BACKDROP", "FroMsgBox", DzGetGameUI(), "template", 0)
        
        call DzFrameSetAbsolutePoint(f, 6,0.0125,0.20743) // 左下角位置
        call DzFrameSetSize(f, MSG_BOX_WIDTH, MSG_BOX_HEIGHT_MAX) // 高度根据内容自动调整
        
        //设置初始贴图
        call DzFrameSetTexture(f, msgBoxTexture, 0)
        call DzFrameSetAlpha(f, 0) // 全透明背景
        call DzFrameShow(f, true)
        return f
    endfunction

    //初始化消息系统
    private function InitFroMsgSystem takes nothing returns nothing
        set globalMsgPool = msgFramePool.create()
        set msgBoxFrame = CreateFrameBox()
        set msgUpdateTimer = CreateTimer()
        call TimerStart(msgUpdateTimer, 0.1, true, function UpdateMsgFrames)
    endfunction

    // 根据时间先后修改所有已显示消息框体的位置,且保持间距，最新的消息在最下方
    private function InputMsg takes PlayerMsg msg returns nothing
        local integer i = 0
        local integer j = 0
        local real shift = 0.0
        local real containerH = MSG_BOX_HEIGHT_MAX
        local real oldY = 0.0

        if (msg == 0) then
            return
        endif
        set shift = msg.height + MSG_BOX_PADDING
        call msg.show()

        // 遍历所有槽位，取却msg以外的所有消息向上平移msg的height值+MSG_BOX_PADDING
        set j = 0
        loop
            exitwhen j >= MSG_MAX_COUNT
            if (globalMsgPool.msgList[j] != 0) and (globalMsgPool.msgList[j].isShow == 1) and (j != msg.index) then
                if (globalMsgPool.msgList[j]!= msg) then
                    set oldY = globalMsgPool.msgList[j].currentY
                    set globalMsgPool.msgList[j].currentY = globalMsgPool.msgList[j].currentY + shift
                endif

                // 隐藏超出容器高度的消息
                if (globalMsgPool.msgList[j].currentY + globalMsgPool.msgList[j].height > containerH) then
                    call globalMsgPool.msgList[j].reset()
                else
                    call globalMsgPool.msgList[j].setPostionY(globalMsgPool.msgList[j].currentY)
                endif
            endif
            set j = j + 1
        endloop
    endfunction
    



    //显示消息
    public function ShowMessage takes string msg,string imgPath,integer imgFlag returns nothing
        local PlayerMsg msgObj = 0
        set msgObj = globalMsgPool.getFrame()
        call msgObj.setMsg(msg, imgPath, imgFlag)
        call InputMsg(msgObj)
        call msgObj.show()
        set msgObj = 0 
    endfunction
    
    //显示动态图片消息
    public function ShowGifMessage takes string msg,string modelPath,integer modelType,integer flag,integer animateIndex,boolean isLoop, real gifSize returns nothing
        local PlayerMsg msgObj = 0
        set msgObj = globalMsgPool.getFrame()
        call msgObj.setGifMsg(msg, modelPath, modelType, flag, animateIndex, isLoop,gifSize)
        call InputMsg(msgObj)
        call msgObj.show()
        set msgObj = 0 
    endfunction

    
    /*
        [FroMsg_ShowGifMessage]
        title = "【聊天框】显示动态图片消息"
        description = "显示消息：前置文本：${文本}，模型：${modelPath}，${modelType}，${flag}，动画序号：${animateIndex}，是否循环播放：${isLoop},大小比例：${gifSize} "
        category = TC_FRO
        comment = "模型和动画相关参数参考‘界面-设置模型’与‘界面-设置动画’相关API说明"
        [[.args]]
        type = string
        [[.args]]
        type = string
        [[.args]]
        type = integer
        [[.args]]
        type = integer
        default = 0
        [[.args]]
        type = integer
        default = 0
        [[.args]]
        type = isnotoption
        default = "IsNotIs"
        [[.args]]
        type = real
        default = 1.0
    */

    // 设置字体路径和大小
    public function SetFont takes string path, real size , integer flag returns nothing
        set fontPath = path
        set fontSize = size
        set fontFlag = flag
    endfunction

    /*
        [FroMsg_SetFont]
        title = "【聊天框】设置字体"
        description = "设置字体路径为：${path}，大小为：${size},样式为：${flag} "
        category = TC_FRO
        comment = "不影响已显示的消息，仅影响后续显示的消息，样式参数可选：普通 粗体 斜体 粗体+斜体"
        [[.args]]
        type = string
        [[.args]]
        type = real
        default = 0.0016
        [[.args]]
        type = integer
        default = 0
    */

    // 设置消息容器宽度
    public function SetBoxWidth takes real width returns nothing
        set MSG_BOX_WIDTH = width
        call DzFrameSetSize(msgBoxFrame, MSG_BOX_WIDTH, 0)
    endfunction

    /*
        [SetBoxWidth]
        title = "【聊天框】设置消息容器宽度"
        description = "设置消息容器宽度为：${width} "
        category = TC_FRO
        [[.args]]
        type = real
    */

    // 设置消息容器最大高度
    public function SetBoxMaxHeight takes real height returns nothing
        set MSG_BOX_HEIGHT_MAX = height
    endfunction

    /*
        [SetBoxMaxHeight]
        title = "【聊天框】设置消息容器最大高度"
        description = "设置消息容器最大高度为：${height} "
        category = TC_FRO
        [[.args]]
        type = real
    */

    // 设置文本消息的行高
    public function SetLineHeight takes real height returns nothing
        set LINE_HEIGHT = height
    endfunction

    /*
        [SetLineHeight]
        title = "【聊天框】设置文本消息的行高"
        description = "设置文本消息的行高为：${height} "
        category = TC_FRO
        [[.args]]
        type = real
    */

    // 设置图片大小
    public function SetImageSize takes real width, real height returns nothing
        set IMG_WIDTH = width
        set IMG_HEIGHT = height
    endfunction

    /*
        [SetImageSize]
        title = "【聊天框】设置图片大小"
        description = "设置图片宽度为：${width}，高度为：${height} "
        category = TC_FRO
        [[.args]]
        type = real
        [[.args]]
        type = real
    */

    // 设置行间距
    public function SetPadding takes real padding returns nothing
        set MSG_BOX_PADDING = padding
    endfunction

    /*
        [FroMsg_SetPadding]
        title = "【聊天框】设置行间距"
        description = "设置消息行间距为：${padding} "
        category = TC_FRO
        [[.args]]
        type = real
    */


endlibrary