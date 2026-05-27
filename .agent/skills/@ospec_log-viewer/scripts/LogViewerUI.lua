-- ============================================================================
-- 日志查看器 UI (LogViewerUI)
-- 功能：
--   1. 悬浮 LOG 按钮（右下角起始），松手后吸附到最近屏幕边缘
--   2. 短按打开全屏日志面板：顶行标题 + 过滤行（搜索框 + 3级 badge + 清空 + 关闭）
--   3. 日志分 INFO / NET / WARNING / ERROR 四级（WARN→WARNING）；悬浮按钮上 NET 计入 INFO
--   4. 每条日志可点击复制到剪贴板，面板内弹出"已复制"提示
--   5. 全部字体使用 "sans"（引擎内置 MiSans）
-- ============================================================================

---@diagnostic disable: undefined-global

-- ============================================================================
-- 缩放补偿：通过独立模块 ScaleHelper 提供 S() 函数。
-- 必须在 require 子模块之前初始化全局 S()，因为子模块顶层代码会调用它。
-- ============================================================================

_LVScaleHelper = require("LogViewer.ScaleHelper")
-- 导出为全局函数（子模块 SceneTreeView/UITreeView 顶层代码依赖全局 S）
S = _LVScaleHelper.S
_lvCompensate = 1

local UI            = require("urhox-libs/UI")
local LogCapture    = require("LogViewer.LogCapture")
local PerfProfiler  = require("LogViewer.PerfProfiler")
local UITreeView    = require("LogViewer.UITreeView")
local SceneTreeView = require("LogViewer.SceneTreeView")
local LogBroadcast  = require("LogViewer.LogBroadcast")

-- ============================================================================
-- 配置项（调用方可在 require 后直接覆盖）
-- ============================================================================

--- 是否启用日志面板（false 时不初始化、不接收日志、不显示按钮）
--- 建议正式上线前设为 false：
---   local LogViewerUI = require("LogViewer.LogViewerUI")
---   LogViewerUI.Enable = false
local LogViewerUI = {}
LogViewerUI.Enable = true
LogViewerUI.Version = "2.1.0"

-- ============================================================================
-- 默认主题色（暗色系，可按需替换整个 T 表）
-- ============================================================================
local T = {
    TEXT_PRIMARY    = { 245, 230, 211, 255 },
    TEXT_SECONDARY  = { 195, 175, 145, 255 },
    TEXT_HINT       = { 130, 115,  90, 255 },
    BG_DARK         = {  18,  14,  10, 255 },
    BORDER          = {  80,  65,  45, 200 },
}

-- ============================================================================
-- 常量
-- ============================================================================

local ITEM_HEIGHT    = S(44)
local BTN_W          = S(76)
local BTN_H          = S(76)
local BTN_PERF_W     = S(76) * 2                  -- 性能模式展开宽度
local BTN_PERF_H     = math.floor(S(76) * 1.3)    -- 性能模式展开高度
local BTN_UITREE_W   = BTN_W                      -- 界面模式使用默认宽度
local BTN_UITREE_H   = BTN_H                      -- 界面模式使用默认高度
local BTN_SCENE_W    = BTN_W                      -- 场景模式使用默认宽度
local BTN_SCENE_H    = BTN_H                      -- 场景模式使用默认高度
local BTN_MARGIN     = S(8)
local DRAG_THRESH    = S(4)
local TOAST_SECS     = 1.5
local BTN_DEFAULT_BG = { 35, 35, 42, 235 }   -- 默认深色背景
local BTN_ERROR_BG   = { 175, 28, 28, 240 }  -- 有错误时变红

-- 三级配置（显示用）
local LEVEL_CFG = {
    INFO    = { icon = "ℹ",  iconText = "i", iconColor = {  80, 160, 240, 255 }, activeBg = {  20,  55, 130, 200 } },
    NET     = { icon = "🌐", iconText = "🌐", iconColor = {  60, 190, 120, 255 }, activeBg = {  15,  70,  40, 200 } },
    WARNING = { icon = "⚠",  iconText = "⚠", iconColor = { 220, 170,  30, 255 }, activeBg = {  90,  65,  10, 200 } },
    ERROR   = { icon = "❗", iconText = "!", iconColor = { 210,  55,  45, 255 }, activeBg = {  90,  18,  18, 200 }, circleIcon = true },
    ENGINE  = { icon = "⚙",  iconText = "⚙", iconColor = { 160, 160, 175, 255 }, activeBg = {  50,  50,  60, 200 } },
}

-- 统一化 level：NET→INFO，WARN→WARNING
local function normalizeLevel(raw)
    if raw == "NET" then return "NET"
    elseif raw == "INFO" or raw == nil then return "INFO"
    elseif raw == "WARN" or raw == "WARNING" then return "WARNING"
    elseif raw == "ERROR" then return "ERROR"
    else return "INFO"
    end
end

-- ============================================================================
-- 私有状态
-- ============================================================================

local initialized_      = false
local logBtnRoot_       = nil
local btn_              = nil
local panel_            = nil
local vlist_            = nil
local currentUserId_    = 0
local currentUserName_  = ""
local accountInfoLabel_ = nil
local lastAccountInfoText_ = nil
local userNameRequestInFlight_ = false
local userNamePollNode_  = nil
local userNamePollSO_    = nil
local userNamePollActive_ = false

local btnLeft_          = 0
local btnTop_           = 0

-- 拖拽
local moved_            = false
local mouseDragging_    = false
local dragStartPointerX_ = 0
local dragStartPointerY_ = 0
local dragStartBtnLeft_  = 0
local dragStartBtnTop_   = 0
local suppressToggleUntil_ = 0

-- 按钮三行引用（垂直布局，各行计数标签）
local infoSeg_          = nil   -- INFO 行容器（保留兼容）
local warnSeg_          = nil   -- WARNING 行容器（保留兼容）
local errorSeg_         = nil   -- ERROR 行容器（保留兼容）
-- engineSeg_ 已移除（引擎日志改为通过悬浮按钮底部 tab 切换）
local infoSegLabel_     = nil
local warnSegLabel_     = nil
local errorSegLabel_    = nil
local engineSegLabel_   = nil



-- ── 性能面板状态 ──────────────────────────────────────
local floatingTab_      = "log"    -- "perf" | "log" | "uitree" | "scene"（悬浮窗当前 tab，默认日志）
local panelTab_         = "log"    -- "perf" | "log" | "uitree" | "scene"（全屏面板当前 tab，默认日志）
local perfTimer_        = 0
local PERF_INTERVAL     = 1.0      -- 1 秒刷新一次

-- 悬浮窗性能视图引用
local floatingPerfView_ = nil
local floatingLogView_  = nil
local fpsMiniLabel_     = nil
local ftMiniLabel_      = nil   -- 帧时间标签
local miniChartPanel_   = nil
local miniChartData_    = {}

-- 悬浮窗性能子Tab：fps / mem / net / render
local perfSubTab_       = "fps"
local floatingMemView_  = nil
local floatingNetView_  = nil
local floatingRenderView_ = nil
local floatingPerfContainer_ = nil  -- 所有 perf 子视图的容器（避免 space-evenly 多间距）
-- 悬浮窗子Tab数值标签引用
local miniMemLabels_    = {}   -- key -> UI.Label
local miniNetLabels_    = {}   -- key -> UI.Label
local miniRenderLabels_ = {}   -- key -> UI.Label
-- 全屏面板子Tab按钮引用
local perfSubTabBtns_   = {}   -- key -> UI.Button

-- 全屏面板性能视图引用
local perfContent_      = nil
local logContent_       = nil
local uitreeContent_    = nil    -- 界面 tab 内容区
local sceneContent_     = nil    -- 场景 tab 内容区
local panelPerfTab_     = nil
local panelLogTab_      = nil
local panelUITreeTab_   = nil    -- 界面 tab 按钮
local panelSceneTab_    = nil    -- 场景 tab 按钮

-- 悬浮窗界面/场景视图引用
local floatingUITreeView_ = nil
local floatingSceneView_  = nil
local uitreeMiniLabels_   = {}   -- key -> UI.Label
local sceneMiniLabels_    = {}   -- key -> UI.Label
local perfValLabels_    = {}   -- key -> UI.Label（性能数值标签表）
local perfMemBars_      = {}   -- key -> UI.Panel（内存进度条表）
local perfNetSection_   = nil  -- 网络分区容器（无网络时隐藏）
local fullChartPanel_   = nil
local fullChartData_    = {}
local filterRow_        = nil  -- 日志过滤行引用（始终可见，背景+关闭按钮）
local filterContent_    = nil  -- 过滤行内部内容（搜索+badges+清空，性能 tab 时隐藏）
local perfSubTabContent_ = nil -- 性能子标签内容（帧率/内存/网络/渲染，日志 tab 时隐藏）
local envTabGroup_      = nil  -- 前端/后端 tab 组引用（性能 tab 时隐藏）

-- UI DC 校准（排除调试面板自身 drawcall）
-- 策略：每次打开都记录基线，每帧持续更新 selfDC = 当前总DC - 基线
local preOpenBaseline_     = 0     -- 面板打开前的 UI DC 基线
local panelCalibTracking_  = false -- true=面板打开中，每帧持续更新 selfDC

-- 悬浮窗 DC 校准（排除悬浮窗自身 drawcall）
-- 两阶段校准：先隐藏浮窗测基线（纯游戏 DC），再显示浮窗测总量，差值 = 浮窗自身 DC
local FCALIB_IDLE      = 0  -- 空闲
local FCALIB_HIDE_WAIT = 1  -- 浮窗已隐藏，等几帧后测基线
local FCALIB_SHOW_WAIT = 2  -- 浮窗已显示，等几帧后测总量
local FCALIB_MOUNT_DELAY = 3  -- Mount 后延迟等待游戏稳定
local floatingCalibState_    = FCALIB_IDLE
local floatingCalibCountdown_ = 0
local floatingCalibBaseline_ = 0    -- 隐藏浮窗后测的"纯游戏"UI DC 基线
local floatingDCOffset_      = 0    -- 浮窗自身 DC 偏移量

-- 吸附 tween 状态（easeOutCubic 缓动）
-- 注意：btnLeft_/btnTop_ 始终等于当前视觉位置，tween 每帧直接更新它们。
local snapTween_ = {
    active   = false,
    fromLeft = 0,
    fromTop  = 0,
    toLeft   = 0,
    toTop    = 0,
    elapsed  = 0,
    duration = 0.5,
}

-- 悬浮窗尺寸动画状态
local btnCurW_       = BTN_W
local btnCurH_       = BTN_H
local resizeTween_   = {
    active   = false,
    elapsed  = 0,
    duration = 0.8,
    fromW    = BTN_W,
    fromH    = BTN_H,
    toW      = BTN_W,
    toH      = BTN_H,
    onComplete = nil,
}

-- 滚动到底部浮层按钮
local scrollDownBtn_      = nil
local scrollDownVisible_  = false
-- 内部 Update tick：用独立 ScriptObject 订阅，不覆盖全局 SubscribeToEvent("Update") 插槽
local eventNode_          = nil
local eventSO_            = nil
local updateActive_       = false
-- 延迟滚到底部：等 N 帧后再执行（GetLayout 返回 NaN 无法用，改用帧计数）
local pendingScrollFrames_ = 0
-- 批量刷新标志：订阅者收到新条目时不直接调用 refreshList，
-- 而是设置此标志，在下一帧 Update 中统一执行。
-- 原因：print() → LogCapture → 订阅者 是同步调用链，
-- 可能在 SetData 执行中途触发（UI 布局 Warning 递归），
-- 导致 savedOffset 读到 scrollY=0，破坏滚动位置。
local pendingRefresh_     = false
local pendingForceRender_ = false  -- 强制下一帧重跑 UpdateVisibleItems（Yoga layout pass 后）
local lastCopyTime_       = 0    -- copyEntry 防抖时间戳

-- 搜索框引用 & 清空 X 按钮
local searchField_       = nil
local clearFilterXBtn_   = nil

-- 界面搜索框引用
local uitreeSearchField_    = nil
local uitreeClearXBtn_      = nil
local uitreeFilterContent_  = nil

-- 场景搜索框引用
local sceneSearchField_     = nil
local sceneClearXBtn_       = nil
local sceneFilterContent_   = nil

-- 复制 Toast
local copyToast_        = nil
local copyToastTimer_   = 0

-- 过滤状态（多选，默认全选中）
local filterLevels_     = { INFO = true, NET = true, WARNING = true, ERROR = true, ENGINE = false }
local filterText_       = ""

-- 详情浮层
local detailCard_       = nil

-- 环境切换 tab（多人模式下可见）
local isNetworkMode_    = false   -- 是否为多人模式（Init 时检测）
local viewMode_         = "client"  -- "client" 前端 | "server" 后端
local clientTab_        = nil     -- "前端" tab 引用
local serverTab_        = nil     -- "后端" tab 引用

-- 面板内控件引用（用于动态更新）
local infoBadge_        = nil
local netBadge_         = nil
local warnBadge_        = nil
local errorBadge_       = nil
local engineBadge_      = nil
local infoCount_        = nil
local netCount_         = nil
local warnCount_        = nil
local errorCount_       = nil
local engineCount_      = nil

-- ============================================================================
-- 布局坐标系
-- ============================================================================

local function getLayoutSize()
    local scale = UI.Scale(1)
    return graphics.width / scale, graphics.height / scale, scale
end

local function trimString(value)
    if value == nil then
        return ""
    end
    return tostring(value):match("^%s*(.-)%s*$") or ""
end

local function getCurrentUserId()
    if currentUserId_ ~= 0 then
        return currentUserId_
    end

    if clientCloud and clientCloud.userId ~= nil then
        local userId = math.floor(tonumber(clientCloud.userId) or 0)
        if userId ~= 0 then
            return userId
        end
    end

    return 0
end


local function getCurrentUserName()
    return currentUserName_
end

local function buildAccountInfoText()
    local userName = getCurrentUserName()
    local userId = getCurrentUserId()

    if userName ~= "" and userId ~= 0 then
        return string.format("%s | ID:%s", userName, tostring(userId))
    end
    if userId ~= 0 then
        return "ID:" .. tostring(userId)
    end
    return userName
end

local function updateAccountInfoLabel()
    if not accountInfoLabel_ then
        return
    end

    local text = buildAccountInfoText()
    if text == lastAccountInfoText_ then
        return
    end

    lastAccountInfoText_ = text
    accountInfoLabel_:SetText(text)
end

local userNameFailCount_ = 0
local USER_NAME_MAX_RETRIES = 3
local stopUserNamePrefetch  -- forward declaration

--- 通过 LogBroadcast 向服务端请求当前用户昵称（CS 模式下 GetUserNickname 不可用时的回退路径）
-- 状态挂在模块表上，避免增加顶层 local 计数（local-limit 200）
LogViewerUI._nicknameReqState = { reqId = 0, installed = false}

local function requestNicknameViaBroadcast()
    if userNameRequestInFlight_ then return end

    local conn = nil
    pcall(function() conn = network:GetServerConnection() end)
    if not conn then return end

    if not LogViewerUI._nicknameReqState.installed then
        LogViewerUI._nicknameReqState.installed = true
        network:RegisterRemoteEvent(LogBroadcast.NICKNAME_REQUEST_EVENT)
        network:RegisterRemoteEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT)
        SubscribeToEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT, function(_, evtData)
            local rid = evtData["ReqId"]:GetString()
            if rid ~= tostring(LogViewerUI._nicknameReqState.reqId) then return end

            userNameRequestInFlight_ = false
            local nick = trimString(evtData["Nickname"]:GetString())
            if nick ~= "" then
                currentUserName_ = nick
                stopUserNamePrefetch()
                updateAccountInfoLabel()
                return
            end
            userNameFailCount_ = userNameFailCount_ + 1
            if userNameFailCount_ >= USER_NAME_MAX_RETRIES then
                currentUserName_ = "未知"
                stopUserNamePrefetch()
                updateAccountInfoLabel()
            end
        end)
    end

    userNameRequestInFlight_ = true
    LogViewerUI._nicknameReqState.reqId = LogViewerUI._nicknameReqState.reqId + 1
    local data = VariantMap()
    data["ReqId"] = Variant(tostring(LogViewerUI._nicknameReqState.reqId))
    conn:SendRemoteEvent(LogBroadcast.NICKNAME_REQUEST_EVENT, true, data)
end

local function requestCurrentUserName()
    if currentUserName_ ~= "" then
        return
    end

    if userNameFailCount_ >= USER_NAME_MAX_RETRIES then
        currentUserName_ = "未知"
        stopUserNamePrefetch()
        updateAccountInfoLabel()
        return
    end

    -- 1) CS 模式（有服务端连接）→ 直接走 LogBroadcast，
    --    GetUserNickname 在 CS 客户端因 lobby 对象为 nil 会静默失败（不调回调），不可靠
    local hasServerConn = false
    pcall(function() hasServerConn = network:GetServerConnection() ~= nil end)
    if hasServerConn then
        requestNicknameViaBroadcast()
        return
    end

    -- 2) 单机模式：客户端 GetUserNickname 可用时直接调用
    if type(GetUserNickname) == "function" then
        local uid = clientCloud and clientCloud.userId
        if uid == nil and currentUserId_ ~= 0 then
            uid = currentUserId_
        end
        if uid == nil then return end
        if userNameRequestInFlight_ then return end
        userNameRequestInFlight_ = true

        local callOk = pcall(GetUserNickname, {
            userIds = { uid },
            onSuccess = function(nicknames)
                userNameRequestInFlight_ = false
                userNameFailCount_ = 0
                if type(nicknames) == "table" and nicknames[1] then
                    local nick = trimString(nicknames[1].nickname)
                    if nick ~= "" then
                        currentUserName_ = nick
                        stopUserNamePrefetch()
                        updateAccountInfoLabel()
                    end
                end
            end,
            onError = function()
                userNameRequestInFlight_ = false
                userNameFailCount_ = userNameFailCount_ + 1
                if userNameFailCount_ >= USER_NAME_MAX_RETRIES then
                    currentUserName_ = "未知"
                    stopUserNamePrefetch()
                    updateAccountInfoLabel()
                end
            end,
        })
        if not callOk then
            userNameRequestInFlight_ = false
            userNameFailCount_ = userNameFailCount_ + 1
            if userNameFailCount_ >= USER_NAME_MAX_RETRIES then
                currentUserName_ = "未知"
                stopUserNamePrefetch()
                updateAccountInfoLabel()
            end
        end
        return
    end
end

local function ensureUserNamePollScriptObject()
    if userNamePollSO_ ~= nil then
        return
    end
    userNamePollNode_ = Node()
    userNamePollSO_ = userNamePollNode_:CreateScriptObject("LuaScriptObject")
end

stopUserNamePrefetch = function()
    if userNamePollActive_ and userNamePollSO_ then
        userNamePollSO_:UnsubscribeFromEvent("Update")
        userNamePollActive_ = false
    end
end

local userNamePollTimer_ = 0
local USER_NAME_POLL_INTERVAL = 2.0  -- 每2秒重试一次

local function startUserNamePrefetch()
    ensureUserNamePollScriptObject()
    if userNamePollActive_ or userNamePollSO_ == nil then
        return
    end

    userNamePollTimer_ = 0
    userNamePollSO_:SubscribeToEvent("Update", function(self, eventType, eventData)
        if currentUserName_ ~= "" then
            stopUserNamePrefetch()
            return
        end
        local dt = eventData["TimeStep"]:GetFloat()
        userNamePollTimer_ = userNamePollTimer_ + dt
        if userNamePollTimer_ >= USER_NAME_POLL_INTERVAL then
            userNamePollTimer_ = 0
            requestCurrentUserName()
        end
    end)
    userNamePollActive_ = true
end

-- 面板头部固定高度（title=32 + filterRow=44 + tabBar=44）
local PANEL_HEADER_H = S(32) + S(44) + S(44)   -- ~120 (title + filter row + bottom tab bar)

-- 计算 VirtualList 视口高度（屏幕高度减去面板头部），不依赖 GetLayout()
-- GetLayout() 在移动端 LuaJIT 下可能返回 NaN，导致所有比较失效
local function getVListHeight()
    local _, lh = getLayoutSize()
    return math.max(1, lh - PANEL_HEADER_H)
end

-- ============================================================================
-- 缓动函数
-- ============================================================================

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

-- ============================================================================
-- 性能图表绘制 & 更新
-- ============================================================================

--- 绘制帧时间柱状图（NanoVG）
---@param nvg NVGContextWrapper
---@param x number 左上角 x
---@param y number 左上角 y
---@param w number 宽度
---@param h number 高度
---@param bars table 帧时间数组（ms）
---@param showRefLines boolean 是否显示参考线
local function drawBarChart(nvg, x, y, w, h, bars, showRefLines)
    local count = #bars
    if count == 0 then return end
    local barW = w / count
    local maxMs = 50 -- 最大显示 50ms
    local compact = w < S(120) -- 悬浮窗小尺寸模式

    for i = 1, count do
        local ms = bars[i]
        if ms > 0 then
            local barH = math.min(ms / maxMs, 1.0) * h
            -- 颜色：<16ms 绿 / 16-33ms 黄 / >33ms 红
            local r, g, b
            if ms < 16 then
                r, g, b = 80, 200, 80
            elseif ms < 33 then
                r, g, b = 220, 170, 30
            else
                r, g, b = 210, 55, 45
            end
            nvgBeginPath(nvg)
            nvgRect(nvg, x + (i - 1) * barW, y + h - barH, math.max(barW - 1, 1), barH)
            nvgFillColor(nvg, nvgRGBA(r, g, b, compact and 200 or 255))
            nvgFill(nvg)
        end
    end

    -- 参考线 + 标签
    if showRefLines then
        local fontSize = compact and S(7) or S(9)
        nvgStrokeWidth(nvg, 1)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, fontSize)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        -- 16ms (60FPS) 线
        local y16 = y + h - (16 / maxMs) * h
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, y16)
        nvgLineTo(nvg, x + w, y16)
        nvgStrokeColor(nvg, nvgRGBA(80, 200, 80, 100))
        nvgStroke(nvg)
        nvgFillColor(nvg, nvgRGBA(80, 200, 80, 230))
        nvgText(nvg, x + S(3), y16 - S(6), compact and "16ms" or "16ms (60FPS)")
        -- 33ms (30FPS) 线
        local y33 = y + h - (33 / maxMs) * h
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, y33)
        nvgLineTo(nvg, x + w, y33)
        nvgStrokeColor(nvg, nvgRGBA(220, 170, 30, 100))
        nvgStroke(nvg)
        nvgFillColor(nvg, nvgRGBA(220, 170, 30, 230))
        nvgText(nvg, x + S(3), y33 - S(6), compact and "33ms" or "33ms (30FPS)")
    end
end

--- 刷新性能显示数据（由 0.5s 定时器调用）
local function updatePerfDisplay()
    local stats = PerfProfiler.GetStats()

    -- 悬浮窗性能视图（动画期间不刷新）
    if fpsMiniLabel_ and not resizeTween_.active then
        local fpsColor
        if stats.fps >= 55 then fpsColor = { 80, 200, 80, 255 }        -- 绿色（正常）
        elseif stats.fps >= 30 then fpsColor = { 220, 170, 30, 255 }   -- 黄色（<55）
        else fpsColor = { 210, 55, 45, 255 } end                       -- 红色（<30）
        fpsMiniLabel_:SetText(string.format("%d", math.floor(stats.fps)))
        fpsMiniLabel_:SetStyle({ fontColor = fpsColor })
    end
    if ftMiniLabel_ and not resizeTween_.active then
        local ft = (stats.fps > 0) and (1000.0 / stats.fps) or 0
        ftMiniLabel_:SetText(string.format("%d ms", math.floor(ft)))
    end
    if not resizeTween_.active then
        miniChartData_ = PerfProfiler.GetChartData(40)
    end

    -- 悬浮窗子视图数据更新（动画期间不刷新）
    if not resizeTween_.active then
        -- 内存子视图
        local function setML(key, text)
            local lbl = miniMemLabels_[key]
            if lbl then lbl:SetText(text) end
        end
        if stats.totalMemoryMB then setML("totalMem", string.format("%.0f MB", stats.totalMemoryMB)) end
        setML("luaMem",   string.format("%.0f MB", stats.luaMemMB))
        setML("cacheMem", string.format("%.0f MB", stats.cacheMemMB))
        if stats.texMemMB then setML("texMem", string.format("%.0f MB", stats.texMemMB)) end
        if stats.modelMemMB then setML("modelMem", string.format("%.0f MB", stats.modelMemMB)) end

        -- 网络子视图
        local function setNL(key, text)
            local lbl = miniNetLabels_[key]
            if lbl then lbl:SetText(text) end
        end
        local function fmtBytesShort(b)
            if b >= 1048576 then return string.format("%.0f MB/s", b / 1048576) end
            if b >= 1024 then return string.format("%.0f KB/s", b / 1024) end
            return string.format("%d B/s", math.floor(b))
        end
        if stats.ping then
            setNL("ping",       string.format("%d ms", stats.ping))
            setNL("bytesIn",    fmtBytesShort(stats.bytesIn or 0))
            setNL("bytesOut",   fmtBytesShort(stats.bytesOut or 0))
            setNL("packetsIn",  string.format("%.0f /s", stats.packetsIn or 0))
            setNL("packetsOut", string.format("%.0f /s", stats.packetsOut or 0))
        else
            setNL("ping", "离线")
            setNL("bytesIn", "--")
            setNL("bytesOut", "--")
            setNL("packetsIn", "--")
            setNL("packetsOut", "--")
        end

        -- 渲染子视图
        local function setRL(key, text)
            local lbl = miniRenderLabels_[key]
            if lbl then lbl:SetText(text) end
        end
        local function fmtBigNumShort(n)
            if n >= 1000000 then return string.format("%.0fM", n / 1000000) end
            if n >= 1000 then return string.format("%.0fK", n / 1000) end
            return string.format("%d", n)
        end
        local gpuB_ = stats.gpuBatches or 0
        local rendB_ = stats.drawCalls or 0
        local rawUIDC_ = math.max(0, gpuB_ - rendB_)
        local fOff_ = floatingDCOffset_ or 0
        local panelOff_ = panel_ and (stats.selfDCOffset or 0) or 0
        local totalOff_ = fOff_ + panelOff_
        local uiDC_ = math.max(0, rawUIDC_ - totalOff_)
        local gameGpuB_ = math.max(0, gpuB_ - totalOff_)
        setRL("gpuBatches",    string.format("%d", gameGpuB_))
        setRL("drawCalls",     string.format("%d", rendB_))
        setRL("uiDrawCalls",   string.format("%d", uiDC_))
        setRL("primitives",    fmtBigNumShort(stats.primitives or 0))
        setRL("gpuPrimitives", fmtBigNumShort(stats.gpuPrimitives or 0))

        -- 界面(UITree)悬浮视图摘要
        if floatingTab_ == "uitree" then
            local us = UITreeView.GetFloatingSummary()
            local function setUL(key, text)
                local lbl = uitreeMiniLabels_[key]
                if lbl then lbl:SetText(text) end
            end
            setUL("nodes",   tostring(us.totalNodes))
            setUL("depth",   tostring(us.maxDepth))
            -- UI 批次：排除 LogViewer 自身 DC
            local uiB = PerfProfiler.GetTotalUIBatches()
            local fOff2 = floatingDCOffset_ or 0
            local pOff2 = panel_ and (stats.selfDCOffset or 0) or 0
            setUL("batches", string.format("%d", math.max(0, uiB - fOff2 - pOff2)))
            setUL("hidden",  tostring(us.hiddenCount))
        end

        -- 场景(Scene)悬浮视图摘要
        if floatingTab_ == "scene" then
            local ss = SceneTreeView.GetFloatingSummary()
            local function setSL(key, text)
                local lbl = sceneMiniLabels_[key]
                if lbl then lbl:SetText(text) end
            end
            setSL("nodes",    tostring(ss.totalNodes))
            setSL("comps",    string.format("%d", ss.totalComps))
            setSL("depth",    tostring(ss.maxDepth))
            setSL("disabled", tostring(ss.disabledCount))
        end
    end

    -- 全屏面板性能视图（表驱动更新）
    local function setPV(key, text, color)
        local lbl = perfValLabels_[key]
        if not lbl then return end
        lbl:SetText(text)
        if color then lbl:SetStyle({ fontColor = color }) end
    end

    -- 帧率颜色
    local fpsColor
    if stats.fps >= 55 then fpsColor = { 80, 200, 80, 255 }
    elseif stats.fps >= 30 then fpsColor = { 220, 170, 30, 255 }
    else fpsColor = { 210, 55, 45, 255 } end

    setPV("fps", string.format("%.1f", stats.fps), fpsColor)
    setPV("dt", string.format("%.2f ms", (stats.timeStep or 0) * 1000))
    setPV("frameNum", string.format("%d", stats.frameNumber or 0))
    -- 运行时长格式化
    local elapsed = stats.elapsedTime or 0
    local em = math.floor(elapsed / 60)
    local es = math.floor(elapsed % 60)
    local eh = math.floor(em / 60)
    em = em % 60
    setPV("elapsed", string.format("%02d:%02d:%02d", eh, em, es))

    -- 渲染（排除全屏面板 + 悬浮窗自身 DC）
    local gpuB = stats.gpuBatches or 0
    local rendB = stats.drawCalls or 0
    local selfOff = stats.selfDCOffset or 0
    local fOff = floatingDCOffset_ or 0
    local totalOff = selfOff + fOff
    local uiDC = math.max(0, gpuB - rendB - totalOff)
    local gameGpuB = math.max(0, gpuB - totalOff)
    setPV("gpuBatches", string.format("%d", gameGpuB))
    setPV("drawCalls", string.format("%d", rendB))
    setPV("uiDrawCalls", string.format("%d", uiDC))
    local function fmtBigNum(n)
        if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
        if n >= 1000 then return string.format("%.1fK", n / 1000) end
        return tostring(n)
    end
    local function fmtBigNumInt(n)
        if n >= 1000000 then return string.format("%.0fM", n / 1000000) end
        if n >= 1000 then return string.format("%.0fK", n / 1000) end
        return string.format("%d", n)
    end
    setPV("primitives", fmtBigNumInt(stats.primitives or 0))
    setPV("gpuPrimitives", fmtBigNumInt(stats.gpuPrimitives or 0))
    setPV("views", string.format("%d", stats.views or 0))
    setPV("geometries", string.format("%d", stats.geometries or 0))
    setPV("lights", string.format("%d", stats.lights or 0))
    setPV("shadowMaps", string.format("%d", stats.shadowMaps or 0))
    setPV("occluders", string.format("%d", stats.occluders or 0))
    setPV("apiName", stats.apiName or "--")
    setPV("vsync", (stats.vsync == true) and "开启" or (stats.vsync == false) and "关闭" or "--")
    -- 渲染设置
    local function fmtBool(v) return (v == true) and "开启" or (v == false) and "关闭" or "--" end
    setPV("dynamicInstancing", fmtBool(stats.dynamicInstancing))
    setPV("drawShadows", fmtBool(stats.drawShadows))
    if stats.shadowMapSize then setPV("shadowMapSize", string.format("%d", stats.shadowMapSize)) end
    setPV("hdrRendering", fmtBool(stats.hdrRendering))
    setPV("specularLighting", fmtBool(stats.specularLighting))
    local TEX_Q_NAMES = { [0] = "低", [1] = "中", [2] = "高" }
    if stats.textureQuality ~= nil then setPV("textureQuality", TEX_Q_NAMES[stats.textureQuality] or tostring(stats.textureQuality)) end
    if stats.textureAnisotropy then setPV("textureAnisotropy", string.format("%dx", stats.textureAnisotropy)) end
    if stats.maxBones then setPV("maxBones", string.format("%d", stats.maxBones)) end
    setPV("instancingSupport", fmtBool(stats.instancingSupport))
    setPV("srgb", fmtBool(stats.srgb))

    -- 内存
    if stats.totalMemoryMB then
        setPV("totalMem", string.format("%.0f MB", stats.totalMemoryMB))
    end
    setPV("luaMem", string.format("%.1f MB", stats.luaMemMB))
    setPV("cacheMem", string.format("%.1f MB", stats.cacheMemMB))
    if stats.texMemMB then setPV("texMem", string.format("%.1f MB", stats.texMemMB)) end
    if stats.modelMemMB then setPV("modelMem", string.format("%.1f MB", stats.modelMemMB)) end
    if stats.soundMemMB then setPV("soundMem", string.format("%.1f MB", stats.soundMemMB)) end
    -- 内存进度条
    local function setBar(key, value, maxVal)
        local bar = perfMemBars_[key]
        if bar then
            local pct = math.min(value / maxVal, 1.0)
            bar:SetStyle({ width = string.format("%.0f%%", pct * 100) })
        end
    end
    setBar("luaMem", stats.luaMemMB, 64)
    setBar("cacheMem", stats.cacheMemMB, 128)
    if stats.bgLoadResources then setPV("bgLoadResources", string.format("%d", stats.bgLoadResources)) end

    -- 屏幕
    setPV("resolution", string.format("%d x %d", stats.screenW or 0, stats.screenH or 0))
    if stats.desktopW then
        setPV("desktopRes", string.format("%d x %d", stats.desktopW, stats.desktopH))
    end
    setPV("dpr", string.format("%.1f", stats.dpr or 1))
    if stats.displayDPI then
        local dpi = stats.displayDPI
        setPV("displayDPI", string.format("%.0f / %.0f / %.0f", dpi.x, dpi.y, dpi.z))
    end
    setPV("msaa", string.format("%dx", stats.multiSample or 0))
    if stats.refreshRate then setPV("refreshRate", string.format("%d Hz", stats.refreshRate)) end
    if stats.maxFps then setPV("maxFps", string.format("%d", stats.maxFps)) end
    if stats.minFps then setPV("minFps", string.format("%d", stats.minFps)) end
    if stats.timerPeriod then setPV("timerPeriod", string.format("%d ms", stats.timerPeriod)) end
    setPV("fullscreen", fmtBool(stats.fullscreen))
    if stats.monitorCount then setPV("monitorCount", string.format("%d", stats.monitorCount)) end
    setPV("tripleBuffer", fmtBool(stats.tripleBuffer))

    -- 系统信息
    setPV("platform", stats.platform or "--")
    setPV("osVersion", stats.osVersion or "--")
    if stats.cpuPhysical then setPV("cpuPhysical", string.format("%d", stats.cpuPhysical)) end
    if stats.cpuLogical then setPV("cpuLogical", string.format("%d", stats.cpuLogical)) end
    setPV("hostName", stats.hostName or "--")
    setPV("loginName", stats.loginName or "--")

    -- 其它
    if stats.audioMixRate then setPV("audioMixRate", string.format("%d Hz", stats.audioMixRate)) end
    setPV("audioStereo", fmtBool(stats.audioStereo))
    if stats.maxInactiveFps then setPV("maxInactiveFps", string.format("%d", stats.maxInactiveFps)) end
    if stats.timeStepSmoothing then setPV("timeStepSmoothing", string.format("%d", stats.timeStepSmoothing)) end
    setPV("pauseMinimized", fmtBool(stats.pauseMinimized))
    if stats.timeScale then setPV("timeScale", string.format("%.2fx", stats.timeScale)) end

    -- 网络
    if perfNetSection_ then
        if stats.ping then
            perfNetSection_.visible = true
            perfNetSection_:SetStyle({ height = "auto", overflow = "visible" })
            local function fmtBytes(b)
                if b >= 1048576 then return string.format("%.2f MB/s", b / 1048576) end
                if b >= 1024 then return string.format("%.2f KB/s", b / 1024) end
                return string.format("%.0f B/s", b)
            end
            setPV("ping", string.format("%d ms", stats.ping))
            setPV("bytesIn", fmtBytes(stats.bytesIn or 0))
            setPV("bytesOut", fmtBytes(stats.bytesOut or 0))
            setPV("packetsIn", string.format("%.0f /s", stats.packetsIn or 0))
            setPV("packetsOut", string.format("%.0f /s", stats.packetsOut or 0))
        else
            perfNetSection_.visible = false
            perfNetSection_:SetStyle({ height = S(0), overflow = "hidden" })
        end
    end
    fullChartData_ = PerfProfiler.GetChartData(80)
end

-- ============================================================================
-- 悬浮窗尺寸动画
-- ============================================================================

local function startResizeTween(toW, toH, onComplete)
    resizeTween_.active     = true
    resizeTween_.elapsed    = 0
    resizeTween_.fromW      = btnCurW_
    resizeTween_.fromH      = btnCurH_
    resizeTween_.toW        = toW
    resizeTween_.toH        = toH
    resizeTween_.onComplete = onComplete
    -- 动画期间隐藏悬浮窗所有内部视图
    -- 动画期间清空 btn_ 子元素
    if btn_ then
        local oldChildren = btn_:GetChildren()
        for i = #oldChildren, 1, -1 do
            btn_:RemoveChild(oldChildren[i])
        end
    end
end

local function tickResizeTween(dt)
    if not resizeTween_.active or not btn_ then return end
    resizeTween_.elapsed = resizeTween_.elapsed + dt
    local t = math.min(resizeTween_.elapsed / resizeTween_.duration, 1.0)
    local e = 1 - (1 - t) ^ 3   -- easeOutCubic

    local w = resizeTween_.fromW + (resizeTween_.toW - resizeTween_.fromW) * e
    local h = resizeTween_.fromH + (resizeTween_.toH - resizeTween_.fromH) * e
    btnCurW_ = w
    btnCurH_ = h

    -- 保持悬浮窗不超出屏幕
    local layoutW, layoutH = getLayoutSize()
    if btnLeft_ + w > layoutW - BTN_MARGIN then
        btnLeft_ = math.max(BTN_MARGIN, layoutW - w - BTN_MARGIN)
    end
    if btnTop_ + h > layoutH - BTN_MARGIN then
        btnTop_ = math.max(BTN_MARGIN, layoutH - h - BTN_MARGIN)
    end
    btn_:SetStyle({ width = w, height = h, left = btnLeft_, top = btnTop_ })

    if t >= 1.0 then
        resizeTween_.active = false
        if resizeTween_.onComplete then resizeTween_.onComplete() end
    end
end

-- 显示/隐藏悬浮窗子视图的辅助
-- 将单个活跃视图设为 btn_ 的唯一子元素（避免隐藏元素占空间）
local function setActiveFloatingView(view)
    if not btn_ or not view then return end
    -- 移除当前所有子元素
    local oldChildren = btn_:GetChildren()
    for i = #oldChildren, 1, -1 do
        btn_:RemoveChild(oldChildren[i])
    end
    -- 添加新的活跃视图
    view.visible = true
    view:SetStyle({ flexGrow = 1, height = "auto", overflow = "visible" })
    btn_:AddChild(view)
end

-- 触发悬浮窗 DC 两阶段重校准
-- 阶段1: 从渲染树移除浮窗 → 等3帧 → 测基线(纯游戏DC)
-- 阶段2: 重新挂回渲染树 → 等3帧 → 测总量 → offset = 总量 - 基线
local function triggerFloatingRecalib()
    if not logBtnRoot_ then return end
    -- 面板打开时不启动浮窗校准（避免基线互相干扰）
    if panelCalibTracking_ then return end
    -- 阶段1: 从渲染树移除浮窗（display="none" 不影响 GPU batch，必须真正移除）
    local root = UI.GetRoot()
    if root then root:RemoveChild(logBtnRoot_) end
    floatingCalibState_ = FCALIB_HIDE_WAIT
    floatingCalibCountdown_ = 3
end

-- 取消正在进行的浮窗校准，确保浮窗挂回渲染树
local function cancelFloatingRecalib()
    if floatingCalibState_ ~= FCALIB_IDLE and logBtnRoot_ then
        local root = UI.GetRoot()
        if root and not logBtnRoot_.parent then
            root:AddChild(logBtnRoot_)
        end
    end
    floatingCalibState_ = FCALIB_IDLE
    floatingCalibCountdown_ = 0
end

-- 悬浮窗视图切换（由全屏面板 tab 同步驱动，无独立 tab 按钮）
local perfSubViewMap_ = nil  -- 延迟初始化
local function switchFloatingTab(tab)
    floatingTab_ = tab
    if tab == "perf" then
        if not perfSubViewMap_ then
            perfSubViewMap_ = { fps = floatingPerfView_, mem = floatingMemView_, net = floatingNetView_, render = floatingRenderView_ }
        end
        setActiveFloatingView(perfSubViewMap_[perfSubTab_] or floatingPerfView_)
    elseif tab == "uitree" then
        setActiveFloatingView(floatingUITreeView_)
    elseif tab == "scene" then
        setActiveFloatingView(floatingSceneView_)
    else
        setActiveFloatingView(floatingLogView_)
    end
    -- 切换视图后重新校准悬浮窗 DC 偏移
    triggerFloatingRecalib()
end

-- 悬浮窗性能子Tab切换
local function switchPerfSubTab(subTab)
    if perfSubTab_ == subTab then return end
    perfSubTab_ = subTab
    -- 仅在性能模式下切换悬浮窗子视图
    if floatingTab_ == "perf" then
        if not perfSubViewMap_ then
            perfSubViewMap_ = { fps = floatingPerfView_, mem = floatingMemView_, net = floatingNetView_, render = floatingRenderView_ }
        end
        setActiveFloatingView(perfSubViewMap_[subTab] or floatingPerfView_)
        -- 切换子视图后重新校准悬浮窗 DC 偏移
        triggerFloatingRecalib()
    end
    -- 更新全屏面板子Tab按钮样式
    local ST_ACTIVE_BG = { 70, 130, 200, 255 }
    local ST_INACTIVE_BG = { 40, 38, 35, 200 }
    local ST_ACTIVE_FG = { 255, 255, 255, 255 }
    local ST_INACTIVE_FG = { 170, 160, 140, 255 }
    for key, btn in pairs(perfSubTabBtns_) do
        local active = (key == subTab)
        btn:SetStyle({
            backgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            hoverBackgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            pressedBackgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            fontColor = active and ST_ACTIVE_FG or ST_INACTIVE_FG,
        })
    end
end

-- 全屏面板 tab 切换
local function switchPanelTab(tab)
    if panelTab_ == tab then return end
    local prevTab = panelTab_
    panelTab_ = tab

    -- 停用离开的 tree tab
    if prevTab == "uitree" then UITreeView.SetActive(false) end
    if prevTab == "scene"  then SceneTreeView.SetActive(false) end

    if perfContent_ then
        perfContent_.visible = (tab == "perf")
        perfContent_:SetStyle({
            flexGrow = (tab == "perf") and 1 or 0,
            height = (tab == "perf") and "auto" or 0,
            overflow = (tab == "perf") and "visible" or "hidden",
            flexBasis = 0,
            paddingBottom = (tab == "perf") and S(10) or 0,
        })
    end
    if logContent_ then
        logContent_.visible = (tab == "log")
        logContent_:SetStyle({
            flexGrow = (tab == "log") and 1 or 0,
            height = (tab == "log") and "auto" or 0,
            overflow = (tab == "log") and "visible" or "hidden",
        })
    end
    if uitreeContent_ then
        uitreeContent_.visible = (tab == "uitree")
        uitreeContent_:SetStyle({
            flexGrow = (tab == "uitree") and 1 or 0,
            height = (tab == "uitree") and "auto" or 0,
            flexBasis = 0,
        })
    end
    if sceneContent_ then
        sceneContent_.visible = (tab == "scene")
        sceneContent_:SetStyle({
            flexGrow = (tab == "scene") and 1 or 0,
            height = (tab == "scene") and "auto" or 0,
            flexBasis = 0,
        })
    end
    -- filterRow_ 底部边框：日志/性能 tab 显示，界面/场景 tab 隐藏
    if filterRow_ then
        local showBorder = (tab == "log" or tab == "perf")
        filterRow_:SetStyle({ borderBottomWidth = showBorder and 1 or 0 })
    end
    -- filterRow_ 始终可见（保持背景+关闭按钮），仅切换内部过滤内容
    if filterContent_ then filterContent_.visible = (tab == "log") end
    if perfSubTabContent_ then perfSubTabContent_.visible = (tab == "perf") end
    if uitreeFilterContent_ then uitreeFilterContent_.visible = (tab == "uitree") end
    if sceneFilterContent_ then sceneFilterContent_.visible = (tab == "scene") end
    -- 前端/后端 tab 组仅在日志 tab 时显示
    if envTabGroup_ then envTabGroup_.visible = (tab == "log") end
    -- scrollDownBtn_ 仅在日志 tab 时可用
    if scrollDownBtn_ then
        if tab == "log" then
            local op = scrollDownVisible_ and 1 or 0
            local pe = scrollDownVisible_ and "auto" or "none"
            scrollDownBtn_:SetStyle({ opacity = op, pointerEvents = pe })
        else
            scrollDownBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
        end
    end

    -- 激活进入的 tree tab
    if tab == "uitree" then UITreeView.Rebuild() end
    if tab == "scene"  then SceneTreeView.Rebuild() end

    -- 同步悬浮窗视图（带尺寸动画）
    if tab == "perf" then
        startResizeTween(BTN_PERF_W, BTN_PERF_H, function()
            switchFloatingTab("perf")
        end)
    elseif tab == "uitree" then
        startResizeTween(BTN_UITREE_W, BTN_UITREE_H, function()
            switchFloatingTab("uitree")
        end)
    elseif tab == "scene" then
        startResizeTween(BTN_SCENE_W, BTN_SCENE_H, function()
            switchFloatingTab("scene")
        end)
    else
        startResizeTween(BTN_W, BTN_H, function()
            switchFloatingTab("log")
        end)
    end
    -- 更新 tab 按钮样式
    local ACTIVE_BG = { 60, 55, 50, 255 }
    local INACTIVE_BG = { 30, 25, 20, 200 }
    local ACTIVE_FG = { 245, 230, 211, 255 }
    local INACTIVE_FG = { 195, 175, 145, 255 }
    local ACTIVE_BORDER = { 60, 50, 40, 150 }
    local INACTIVE_BORDER = { 80, 65, 45, 200 }
    local allTabs = {
        { ref = panelLogTab_,    key = "log" },
        { ref = panelPerfTab_,   key = "perf" },
        { ref = panelUITreeTab_, key = "uitree" },
        { ref = panelSceneTab_,  key = "scene" },
    }
    for _, t in ipairs(allTabs) do
        if t.ref then
            local active = (tab == t.key)
            t.ref:SetStyle({
                backgroundColor = active and ACTIVE_BG or INACTIVE_BG,
                hoverBackgroundColor = active and ACTIVE_BG or INACTIVE_BG,
                pressedBackgroundColor = active and ACTIVE_BG or INACTIVE_BG,
                borderColor = active and ACTIVE_BORDER or INACTIVE_BORDER,
                fontColor = active and ACTIVE_FG or INACTIVE_FG,
            })
        end
    end
end

-- ============================================================================
-- 吸附到最近的屏幕边缘（单边，保持另一轴不变）
-- ============================================================================

local function snapToEdge()
    if not btn_ then return end
    local layoutW, layoutH, _ = getLayoutSize()

    -- 四条边的距离（按钮边缘到屏幕边缘，使用当前实际尺寸）
    local curW, curH = btnCurW_, btnCurH_
    local distLeft   = btnLeft_
    local distRight  = layoutW - (btnLeft_ + curW)
    local distTop    = btnTop_
    local distBottom = layoutH - (btnTop_  + curH)

    local minDist = math.min(distLeft, distRight, distTop, distBottom)

    local newLeft, newTop
    if minDist == distLeft then
        newLeft = BTN_MARGIN
        newTop  = math.max(BTN_MARGIN, math.min(btnTop_, layoutH - curH - BTN_MARGIN))
    elseif minDist == distRight then
        newLeft = layoutW - curW - BTN_MARGIN
        newTop  = math.max(BTN_MARGIN, math.min(btnTop_, layoutH - curH - BTN_MARGIN))
    elseif minDist == distTop then
        newTop  = BTN_MARGIN
        newLeft = math.max(BTN_MARGIN, math.min(btnLeft_, layoutW - curW - BTN_MARGIN))
    else  -- distBottom
        newTop  = layoutH - curH - BTN_MARGIN
        newLeft = math.max(BTN_MARGIN, math.min(btnLeft_, layoutW - curW - BTN_MARGIN))
    end

    -- 动画策略：
    -- 1. left/top 立即写入吸附目标（Yoga 锁定最终位置）
    -- 2. 用 Widget:Animate() 把 translateX/Y 从偏移量动画到 0
    --    → renderProps_ 优先级高于 props，不受 Yoga 每帧 layout pass 干扰
    --    → Animate() 内部由 Transition 系统 tick 驱动，真正逐帧插值
    local offsetX = btnLeft_ - newLeft
    local offsetY = btnTop_  - newTop
    btnLeft_ = newLeft
    btnTop_  = newTop
    btn_:SetStyle({ left = newLeft, top = newTop })
    btn_:Animate({
        keyframes = {
            [0] = { translateX = offsetX, translateY = offsetY },
            [1] = { translateX = 0,       translateY = 0       },
        },
        duration   = 0.3,
        easing     = "easeOutCubic",
        fillMode   = "backwards",   -- 立即应用 [0] 帧，防止闪一帧原始位置
        onComplete = function()
            snapTween_.active = false
        end,
    })
    snapTween_.active   = true
    snapTween_.fromLeft = offsetX   -- 保留，供 MouseDown cancel 读取起始偏移
    snapTween_.fromTop  = offsetY
    snapTween_.elapsed  = 0
end

local function cancelSnapTween()
    if not snapTween_.active or not btn_ then
        return
    end
    local tx = (btn_.renderProps_ and btn_.renderProps_["translateX"]) or 0
    local ty = (btn_.renderProps_ and btn_.renderProps_["translateY"]) or 0
    btnLeft_ = btnLeft_ + tx
    btnTop_  = btnTop_  + ty
    btn_:StopAnimation()
    btn_:SetStyle({ left = btnLeft_, top = btnTop_, translateX = 0, translateY = 0 })
    snapTween_.active = false
end

local function togglePanel()
    local now = time:GetElapsedTime()
    if now < suppressToggleUntil_ then
        return
    end
    if panel_ then LogViewerUI.Hide() else LogViewerUI.Show() end
end

-- ============================================================================
-- 引擎事件：拖拽（旧实现，保留注释）
-- ============================================================================

function HandleLogViewerMouseDown(eventType, eventData)
    if not btn_ then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    if not hovered_ then return end

    -- 取消进行中的吸附动画：从 renderProps_ 读取当前 translate 偏移，
    -- 固化到 left/top，再 StopAnimation() 清除 renderProps_，translate 归零。
    -- 视觉位置 = (btnLeft_ + translateX, btnTop_ + translateY)
    if snapTween_.active then
        local tx = (btn_.renderProps_ and btn_.renderProps_["translateX"]) or 0
        local ty = (btn_.renderProps_ and btn_.renderProps_["translateY"]) or 0
        btnLeft_ = btnLeft_ + tx
        btnTop_  = btnTop_  + ty
        btn_:StopAnimation()
        btn_:SetStyle({ left = btnLeft_, top = btnTop_, translateX = 0, translateY = 0 })
        snapTween_.active = false
    end

    dragging_         = true
    moved_            = false
    local mp          = input.mousePosition
    dragStartMX_      = mp.x
    dragStartMY_      = mp.y
    dragStartBtnLeft_ = btnLeft_
    dragStartBtnTop_  = btnTop_
end

function HandleLogViewerMouseMove(eventType, eventData)
    if not dragging_ or not btn_ then return end
    local layoutW, layoutH, scale = getLayoutSize()
    local mp = input.mousePosition
    local dx = (mp.x - dragStartMX_) / scale
    local dy = (mp.y - dragStartMY_) / scale
    if math.abs(dx) > DRAG_THRESH or math.abs(dy) > DRAG_THRESH then moved_ = true end
    if moved_ then
        btnLeft_ = math.max(0, math.min(dragStartBtnLeft_ + dx, layoutW - BTN_W))
        btnTop_  = math.max(0, math.min(dragStartBtnTop_  + dy, layoutH - BTN_H))
        btn_:SetStyle({ left = btnLeft_, top = btnTop_ })
        snapTween_.active = false  -- 拖拽中取消任何进行中的 tween
    end
end

function HandleLogViewerMouseUp(eventType, eventData)
    if not dragging_ then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local wasMoved = moved_
    dragging_ = false
    moved_    = false
    if wasMoved then
        snapToEdge()   -- 拖拽：仅吸附，不触发点击
    else
        -- 短按：切换面板（与拖拽完全互斥）
        if panel_ then LogViewerUI.Hide() else LogViewerUI.Show() end
    end
end

-- ============================================================================
-- 引擎事件：触摸拖拽（移动端，与鼠标事件完全并行）
-- ============================================================================

-- 判断物理坐标 (px, py) 是否落在按钮范围内
local function isTouchOnBtn(px, py)
    if not btn_ then return false end
    local _, _, scale = getLayoutSize()
    local bx1 = btnLeft_  * scale
    local by1 = btnTop_   * scale
    local bx2 = (btnLeft_ + BTN_W) * scale
    local by2 = (btnTop_  + BTN_H) * scale
    return px >= bx1 and px <= bx2 and py >= by1 and py <= by2
end

function HandleLogViewerTouchBegin(eventType, eventData)
    if not btn_ then return end
    if activeTouchId_ >= 0 then return end   -- 已有手指在追踪，忽略多点
    local touchId = eventData["TouchID"]:GetInt()
    local px      = eventData["X"]:GetInt()
    local py      = eventData["Y"]:GetInt()
    if not isTouchOnBtn(px, py) then return end

    -- 取消进行中的吸附动画（与 MouseDown 相同逻辑）
    if snapTween_.active then
        local tx = (btn_.renderProps_ and btn_.renderProps_["translateX"]) or 0
        local ty = (btn_.renderProps_ and btn_.renderProps_["translateY"]) or 0
        btnLeft_ = btnLeft_ + tx
        btnTop_  = btnTop_  + ty
        btn_:StopAnimation()
        btn_:SetStyle({ left = btnLeft_, top = btnTop_, translateX = 0, translateY = 0 })
        snapTween_.active = false
    end

    activeTouchId_    = touchId
    dragging_         = true
    moved_            = false
    dragStartMX_      = px
    dragStartMY_      = py
    dragStartBtnLeft_ = btnLeft_
    dragStartBtnTop_  = btnTop_
end

function HandleLogViewerTouchMove(eventType, eventData)
    if not dragging_ or not btn_ then return end
    if eventData["TouchID"]:GetInt() ~= activeTouchId_ then return end
    local layoutW, layoutH, scale = getLayoutSize()
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx = (px - dragStartMX_) / scale
    local dy = (py - dragStartMY_) / scale
    if math.abs(dx) > DRAG_THRESH or math.abs(dy) > DRAG_THRESH then moved_ = true end
    if moved_ then
        btnLeft_ = math.max(0, math.min(dragStartBtnLeft_ + dx, layoutW - BTN_W))
        btnTop_  = math.max(0, math.min(dragStartBtnTop_  + dy, layoutH - BTN_H))
        btn_:SetStyle({ left = btnLeft_, top = btnTop_ })
        snapTween_.active = false
    end
end

function HandleLogViewerTouchEnd(eventType, eventData)
    if not dragging_ then return end
    if eventData["TouchID"]:GetInt() ~= activeTouchId_ then return end
    local wasMoved = moved_
    dragging_      = false
    moved_         = false
    activeTouchId_ = -1
    if wasMoved then
        snapToEdge()
    else
        if panel_ then LogViewerUI.Hide() else LogViewerUI.Show() end
    end
end

-- ============================================================================
-- 逐帧更新（通过内部 ScriptObject 订阅 "Update" 事件驱动）
-- ============================================================================

local function handleLogViewerUpdate(dt)
    -- 悬浮窗尺寸动画
    tickResizeTween(dt)

    if panel_ then
        updateAccountInfoLabel()
    end

    -- 面板 DC 校准：每帧持续追踪（selfDC = 当前总DC - 打开前基线）
    -- 面板构建过程中 selfDC 自然增长，构建完成后自动收敛到正确值
    if panelCalibTracking_ and panel_ then
        local currentDC = PerfProfiler.GetTotalUIBatches()
        local selfDC = math.max(0, currentDC - preOpenBaseline_)
        PerfProfiler.SetSelfDCOffset(selfDC)
    end

    -- 悬浮窗 DC 两阶段校准状态机
    if floatingCalibState_ == FCALIB_MOUNT_DELAY then
        -- Mount 后延迟等待游戏 UI 稳定
        floatingCalibCountdown_ = floatingCalibCountdown_ - 1
        if floatingCalibCountdown_ == 0 then
            -- 游戏应该稳定了，启动两阶段校准
            floatingCalibState_ = FCALIB_IDLE
            triggerFloatingRecalib()
        end
    elseif floatingCalibState_ == FCALIB_HIDE_WAIT then
        -- 面板打开时不做浮窗校准
        if panelCalibTracking_ then
            cancelFloatingRecalib()
        else
            floatingCalibCountdown_ = floatingCalibCountdown_ - 1
            if floatingCalibCountdown_ == 0 then
                -- 浮窗已隐藏 3 帧，测基线（纯游戏 DC + 面板 DC if any）
                floatingCalibBaseline_ = PerfProfiler.GetTotalUIBatches()
                -- 将浮窗重新挂回渲染树
                if logBtnRoot_ then
                    local root = UI.GetRoot()
                    if root and not logBtnRoot_.parent then
                        root:AddChild(logBtnRoot_)
                    end
                end
                floatingCalibState_ = FCALIB_SHOW_WAIT
                floatingCalibCountdown_ = 3
            end
        end
    elseif floatingCalibState_ == FCALIB_SHOW_WAIT then
        -- 面板打开时不做浮窗校准
        if panelCalibTracking_ then
            floatingCalibState_ = FCALIB_IDLE
        else
            floatingCalibCountdown_ = floatingCalibCountdown_ - 1
            if floatingCalibCountdown_ == 0 then
                -- 浮窗已显示 3 帧，测总量
                -- 注意：不需要减 panelOff，因为基线和总量都包含面板 DC，相减已自动抵消
                local currentUIBatches = PerfProfiler.GetTotalUIBatches()
                floatingDCOffset_ = math.max(0, currentUIBatches - floatingCalibBaseline_)
                floatingCalibState_ = FCALIB_IDLE
                -- 校准完成立即刷新显示（不用等 PERF_INTERVAL）
                updatePerfDisplay()
                perfTimer_ = 0
            end
        end
    end

    -- 性能数据定时刷新（悬浮窗和全屏面板共用）
    perfTimer_ = perfTimer_ + dt
    if perfTimer_ >= PERF_INTERVAL then
        perfTimer_ = 0
        updatePerfDisplay()
    end

    -- 界面/场景树自动刷新（面板打开且对应 tab 激活时）
    if panel_ then
        if panelTab_ == "uitree" then
            UITreeView.Update(dt)
        elseif panelTab_ == "scene" then
            SceneTreeView.Update(dt)
        end
    end

    -- Toast 倒计时
    if copyToastTimer_ > 0 then
        copyToastTimer_ = copyToastTimer_ - dt
        if copyToastTimer_ <= 0 then
            copyToastTimer_ = 0
            if copyToast_ and panel_ then
                panel_:RemoveChild(copyToast_)
                copyToast_ = nil
            end
        end
    end

    -- refreshList 执行后的【下一帧】：Yoga layout pass 已完成，强制 UpdateVisibleItems 重跑。
    -- ⚠️ 必须放在 pendingRefresh_ 块【之前】：
    --   若放在之后，pendingRefresh_ 在第 N 帧 set pendingForceRender_=true，
    --   下方检查会在同一帧立即消费它，Yoga 还没有跑 layout pass，fix 完全失效。
    --   放在前面后，第 N 帧的检查已经跑过（此时 pendingForceRender_=false，跳过），
    --   pendingRefresh_ 随后 set pendingForceRender_=true，第 N+1 帧才会消费。
    if pendingForceRender_ and panel_ and vlist_ then
        pendingForceRender_ = false
        pcall(function()
            vlist_.visibleRange_ = { first = 0, last = 0 }  -- 绕过 early-return 守卫
            local _, curY = vlist_.scrollView_:GetScroll()
            vlist_.scrollView_:SetScrollDirect(0, curY or 0)
        end)
    end

    -- 新日志到达时批量刷新（订阅者设 flag，此处统一执行）
    -- 粘底策略：直接计算距底部距离，避免依赖 scrollDownVisible_ 的时机问题
    -- 注意：不能用 `scrollDownVisible_ and nil or "bottom"`——Lua and/or 陷阱：
    --   当 b=nil 时，`a and nil or c` 永远返回 c，与 a 无关！
    if pendingRefresh_ and panel_ and vlist_ then
        pendingRefresh_ = false
        local _, curY   = vlist_.scrollView_:GetScroll()
        local cH        = vlist_.scrollView_.contentHeight_ or 0
        local viewH     = getVListHeight()
        local maxScroll = math.max(0, cH - viewH)
        -- 用户在距底部 1.5 行以内 → 自动追底；否则保留位置
        local atBottom  = (maxScroll <= 0) or ((maxScroll - (curY or 0)) <= ITEM_HEIGHT * 1.5)
        local mode      = atBottom and "bottom" or nil
        pcall(refreshList, mode)
        pendingForceRender_ = true   -- 标记：下一帧（N+1）Yoga layout pass 后强制重渲
    end

    -- 延迟滚到底部：每帧都执行，直到计数归零
    -- 连续多帧是为了确保 Yoga 完成布局后位置正确（第1帧可能 NaN，第2-N帧才生效）
    if pendingScrollFrames_ > 0 and panel_ and vlist_ then
        pendingScrollFrames_ = pendingScrollFrames_ - 1
        pcall(function()
            local viewH    = getVListHeight()
            local contentH = vlist_:GetItemCount() * vlist_.rowHeight_
            vlist_.scrollView_.contentHeight_ = contentH
            local target   = math.max(0, contentH - viewH)
            vlist_.scrollView_:SetScrollDirect(0, target)
        end)
    end

    -- ↓ 按钮：当距离底部超过 20% 时显示
    if panel_ and vlist_ then
        local shouldShow  = false
        local rowH        = vlist_.rowHeight_ or ITEM_HEIGHT
        local total       = vlist_:GetItemCount()
        -- 优先用 scrollView_ 已缓存的 contentHeight_（UpdateContentSize 每帧更新）
        local svH         = vlist_.scrollView_.contentHeight_
        local totalH      = (svH and svH > 0) and svH or (total * rowH)
        local viewH       = getVListHeight()   -- 屏幕高度 - header，不依赖 GetLayout
        local maxScroll   = math.max(0, totalH - viewH)
        if maxScroll > 0 then
            local _, sy = vlist_.scrollView_:GetScroll()
            local scrollY = sy or 0
            shouldShow = (maxScroll - scrollY) / maxScroll > 0.05
        end

        -- 更新按钮可见性
        if shouldShow ~= scrollDownVisible_ then
            scrollDownVisible_ = shouldShow
            if scrollDownBtn_ then
                scrollDownBtn_:SetStyle({
                    opacity       = shouldShow and 1 or 0,
                    pointerEvents = shouldShow and "auto" or "none",
                })
            end
        end
    end
end

-- ============================================================================
-- 过滤逻辑
-- ============================================================================

local function isEngineSource(source)
    return source and string.find(source, "engine", 1, true) ~= nil
end

local function getFilteredEntries()
    local all    = LogCapture.GetEntries()
    local hasTxt = filterText_ and filterText_ ~= ""
    -- 判断是否全选（全选 + 无文本 + 非后端视图 + 引擎开 = 直接返回全量）
    local allSelected = filterLevels_.INFO and filterLevels_.NET and filterLevels_.WARNING and filterLevels_.ERROR and filterLevels_.ENGINE
    local needSourceFilter = isNetworkMode_  -- 多人模式下需要按 viewMode_ 过滤 source
    if allSelected and not hasTxt and not needSourceFilter then return all end

    local result   = {}
    local txtLower = hasTxt and string.lower(filterText_) or nil
    for _, e in ipairs(all) do
        -- 环境过滤：后端视图只显示 source 含 "server"（包括 "server"、"server_engine"），
        -- 前端视图隐藏所有 source 含 "server" 的条目
        if needSourceFilter then
            local src = e.source or ""
            local isServer = string.find(src, "server", 1, true) ~= nil
            if viewMode_ == "server" then
                if not isServer then goto continue end
            else
                if isServer then goto continue end
            end
        end
        -- 引擎日志过滤：source 含 "engine" 的条目需要 ENGINE 开关开启
        if isEngineSource(e.source) and not filterLevels_.ENGINE then goto continue end
        local lvl = normalizeLevel(e.level)
        -- 该 level 未选中 → 跳过
        if not filterLevels_[lvl] then goto continue end
        -- 文本过滤
        if txtLower then
            local msg = string.lower(e.msg or "")
            if not string.find(msg, txtLower, 1, true) then goto continue end
        end
        table.insert(result, e)
        ::continue::
    end
    return result
end

-- ============================================================================
-- 更新按钮三段比例（基于过滤后日志，面板开关均可调用）
-- ============================================================================

local function updateBtnSegments()
    if not btn_ then return end
    local all = LogCapture.GetEntries()
    local c = { INFO = 0, NET = 0, WARNING = 0, ERROR = 0 }
    for _, e in ipairs(all) do
        -- 跳过引擎日志
        if isEngineSource(e.source) then goto continue end
        -- 多人模式下按 viewMode_ 过滤 source（与面板一致）
        if isNetworkMode_ then
            local src = e.source or ""
            local isServer = string.find(src, "server", 1, true) ~= nil
            if viewMode_ == "server" then
                if not isServer then goto continue end
            else
                if isServer then goto continue end
            end
        end
        local lvl = normalizeLevel(e.level)
        c[lvl] = (c[lvl] or 0) + 1
        ::continue::
    end
    -- 更新各行计数文字
    if infoSegLabel_   then infoSegLabel_:SetText(tostring(c.INFO))   end
    if warnSegLabel_   then warnSegLabel_:SetText(tostring(c.WARNING))  end
    if errorSegLabel_  then errorSegLabel_:SetText(tostring(c.ERROR))   end
    -- 错误状态：有 ERROR 时整个按钮变红；全为 0 时恢复默认深色
    local bg = BTN_DEFAULT_BG
    if c.ERROR > 0 then
        bg = BTN_ERROR_BG
    end
    btn_:SetStyle({ backgroundColor = bg })
end

-- 同步更新面板内 badge 计数（infoCount_ / warnCount_ / errorCount_）
-- 与 updateBtnSegments() 并行调用，确保面板计数随新日志即时刷新。
-- 可安全在订阅者（print() 调用链）中直接调用，代价与 SetText 相同。
-- badge 计数始终显示实时总数（仅按 source 过滤，不受 filterLevels_ 开关影响）
local function updatePanelCounts()
    if not infoCount_ then return end
    local all = LogCapture.GetEntries()
    local c = { INFO = 0, NET = 0, WARNING = 0, ERROR = 0 }
    local engineC = 0
    for _, e in ipairs(all) do
        -- 仅按 viewMode_ source 过滤（多人模式下区分前端/后端）
        if isNetworkMode_ then
            local src = e.source or ""
            local isServer = string.find(src, "server", 1, true) ~= nil
            if viewMode_ == "server" then
                if not isServer then goto continue end
            else
                if isServer then goto continue end
            end
        end
        if isEngineSource(e.source) then
            engineC = engineC + 1
        else
            local lvl = normalizeLevel(e.level)
            c[lvl] = (c[lvl] or 0) + 1
        end
        ::continue::
    end
    infoCount_:SetText(tostring(c.INFO))
    if netCount_ then netCount_:SetText(tostring(c.NET)) end
    warnCount_:SetText(tostring(c.WARNING))
    errorCount_:SetText(tostring(c.ERROR))
    if engineCount_ then engineCount_:SetText(tostring(engineC)) end
end

-- ============================================================================
-- 更新 badge 激活样式
-- ============================================================================

local function updateBadgeStyles()
    if not infoBadge_ then return end
    local BG0 = { 0, 0, 0, 0 }
    -- 无 hover/press 效果：三个颜色始终与 backgroundColor 相同
    local function bs(active, activeBg)
        local bg = active and activeBg or BG0
        return { backgroundColor = bg, hoverBackgroundColor = bg, pressedBackgroundColor = bg }
    end
    -- 选中：使用各 level 对应主题色背景；未选中：透明
    infoBadge_:SetStyle(bs(filterLevels_.INFO,    LEVEL_CFG.INFO.activeBg))
    if netBadge_ then netBadge_:SetStyle(bs(filterLevels_.NET, LEVEL_CFG.NET.activeBg)) end
    warnBadge_:SetStyle(bs(filterLevels_.WARNING, LEVEL_CFG.WARNING.activeBg))
    errorBadge_:SetStyle(bs(filterLevels_.ERROR,  LEVEL_CFG.ERROR.activeBg))
    if engineBadge_ then engineBadge_:SetStyle(bs(filterLevels_.ENGINE, LEVEL_CFG.ENGINE.activeBg)) end
end

-- ============================================================================
-- 刷新列表 + 更新计数
-- ============================================================================

-- scrollMode:
--   "top"    过滤条件变化 → 滚到顶部
--   "bottom" 初始打开 / 清空 → 滚到底部
--   nil      新日志到来 → 只更新数据，不改变滚动位置
local function refreshList(scrollMode)
    local filtered = getFilteredEntries()

    updatePanelCounts()
    updateBtnSegments()

    if vlist_ then
        if scrollMode == "top" or scrollMode == true then
            vlist_:SetData(filtered)
            -- 立即更新 contentHeight_，防止 ScrollToTop/ScrollToBottom 使用过期值
            vlist_.scrollView_.contentHeight_ = #filtered * vlist_.rowHeight_
            vlist_:ScrollToTop()
        elseif scrollMode == "bottom" then
            local cH = #filtered * (vlist_.rowHeight_ or ITEM_HEIGHT)
            -- 绕开 SetData 内部的 SetScroll(0,0) 中间状态：
            -- SetData 会先 reset scrollOffset_=0 再 SetScroll(0,0)，让 UpdateVisibleItems 渲染顶部内容，
            -- 然后我们再 SetScrollDirect 到底部时，新插入的 item 通过 SetStyle({top=yPos}) 标记 Yoga dirty，
            -- 但 Yoga layout pass 还没跑，NanoVGRender 看到的 top 是 0，item 全部在 -target 位置（屏幕外上方）。
            -- 解决：直接操作 props.data + ReleaseAllItems，预设 scrollOffset_，跳过中间的 scroll-to-0 状态。
            vlist_.props.data = filtered
            if vlist_.contentContainer_ then
                vlist_.contentContainer_:SetStyle({ height = cH })
            end
            vlist_.scrollView_.contentHeight_ = cH
            vlist_:ReleaseAllItems()
            vlist_.visibleRange_ = { first = 0, last = 0 }
            local viewH = getVListHeight()
            local target = math.max(0, cH - viewH)
            vlist_.scrollOffset_ = target   -- 预设 offset，确保 UpdateVisibleItems 计算正确可见范围
            vlist_.scrollView_:SetScrollDirect(0, target)
        else
            -- 新日志：直接更新数据，保留滚动位置
            -- 原因：SetData() 内部调用 SetScroll(0,0)，强制重置滚动位置。
            -- 改为直接修改 props.data，然后通过重发 scroll 事件触发 UpdateVisibleItems。
            -- 重发 scroll 事件会经过 OnScroll → scrollOffset_ 更新 → UpdateVisibleItems()
            -- 并且通过重置 visibleRange_ 来绕过 UpdateVisibleItems 的 early-return。
            vlist_.props.data = filtered
            local cH = #filtered * (vlist_.rowHeight_ or ITEM_HEIGHT)
            vlist_.scrollView_.contentHeight_ = cH
            -- 重置 visibleRange_，确保 UpdateVisibleItems 不会 early-return
            vlist_.visibleRange_ = { first = 0, last = 0 }
            -- 重发当前滚动位置，触发完整的 OnScroll → UpdateVisibleItems 链路
            local _, curY = vlist_.scrollView_:GetScroll()
            vlist_.scrollView_:SetScrollDirect(0, curY or 0)
        end
    end
end

-- ============================================================================
-- 环境切换 tab 样式更新
-- ============================================================================

local TAB_ACTIVE_BG   = { 60, 55, 50, 255 }
local TAB_INACTIVE_BG = { 0, 0, 0, 0 }
local TAB_ACTIVE_FG   = { 255, 255, 255, 255 }
local TAB_INACTIVE_FG = { 130, 115, 90, 255 }

local function updateViewModeTabs()
    if not clientTab_ or not serverTab_ then return end
    local isClient = (viewMode_ == "client")
    clientTab_:SetStyle({
        backgroundColor        = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
        hoverBackgroundColor   = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
        pressedBackgroundColor = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
        fontColor              = isClient and TAB_ACTIVE_FG or TAB_INACTIVE_FG,
    })
    serverTab_:SetStyle({
        backgroundColor        = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
        hoverBackgroundColor   = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
        pressedBackgroundColor = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
        fontColor              = isClient and TAB_INACTIVE_FG or TAB_ACTIVE_FG,
    })
end

local lastTabSwitchTime_ = 0

local function switchViewMode(mode)
    if viewMode_ == mode then return end
    -- 防抖：onClick + onTap 移动端可能同时触发
    local now = time:GetElapsedTime()
    if now - lastTabSwitchTime_ < 0.3 then return end
    lastTabSwitchTime_ = now
    viewMode_ = mode
    updateViewModeTabs()
    refreshList("top")
end



-- ============================================================================
-- 复制到剪贴板 + Toast
-- ============================================================================

local function showCopyToast()
    if not panel_ then return end
    if copyToast_ then panel_:RemoveChild(copyToast_) end
    copyToast_ = UI.Panel {
        position        = "absolute",
        left            = S(0),
        right           = S(0),
        bottom          = S(20),
        flexDirection   = "row",
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
        children = {
            UI.Label {
                text              = "已复制",
                fontSize          = S(12),
                fontFamily        = "sans",
                fontColor         = { 255, 255, 255, 255 },
                paddingHorizontal = S(18),
                paddingVertical   = S(6),
                backgroundColor   = { 40, 40, 40, 220 },
                borderRadius      = S(6),
            },
        },
    }
    panel_:AddChild(copyToast_)
    copyToastTimer_ = TOAST_SECS
end

local function copyEntry(data)
    if not data then return end
    -- 防抖：onClick + onTap 在移动端可能同一次点击都触发，300ms 内只执行一次
    local now = time:GetElapsedTime()
    if now - lastCopyTime_ < 0.3 then return end
    lastCopyTime_ = now

    local lvl  = normalizeLevel(data.level)
    local text = string.format("[%s][%s] %s", data.time or "", lvl, data.msg or "")
    -- 不设置 ui.useSystemClipboard = true：
    -- 系统剪贴板在 TapTap WASM iframe 中调用 JS copyToClipboard 会 crash（函数未定义）
    -- 使用引擎内部剪贴板缓冲，安全无崩溃
    ui:SetClipboardText(text)
    showCopyToast()
end

-- ============================================================================
-- 详情浮层（点击行弹出，显示完整日志文本）
-- ============================================================================

local function hideDetailCard()
    if not detailCard_ or not panel_ then
        detailCard_ = nil
        return
    end
    panel_:RemoveChild(detailCard_)
    detailCard_ = nil
    -- 恢复向下滚动按钮（如果之前可见）
    if scrollDownBtn_ then
        local op = scrollDownVisible_ and 1 or 0
        local pe = scrollDownVisible_ and "all" or "none"
        scrollDownBtn_:SetStyle({ opacity = op, pointerEvents = pe })
    end
end

local function showDetailCard(data)
    if not panel_ or not data then return end
    hideDetailCard()
    -- 遮住向下滚动按钮，避免它的层级浮在浮层之上
    if scrollDownBtn_ then
        scrollDownBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
    end

    local lvl = normalizeLevel(data.level)
    local cfg = LEVEL_CFG[lvl]

    -- 级别图标（复用 createItem 风格）
    -- height=1+minHeight=0：Yoga 高度固定为 1px，autoWidth_=true 无 scissor，NanoVG 仍渲染到视觉中心
    local iconLabel = UI.Label {
        text          = cfg.circleIcon and "!" or cfg.icon,
        fontSize      = cfg.circleIcon and S(11) or S(14),
        fontFamily    = "sans",
        fontColor     = cfg.circleIcon and { 255, 255, 255, 255 } or cfg.iconColor,
        textAlign     = "center",
        height        = S(1),
        minHeight     = S(0),
        pointerEvents = "none",
    }
    local iconBox = UI.Panel {
        width           = S(20),
        height          = S(20),
        borderRadius    = cfg.circleIcon and S(10) or 0,
        flexShrink      = 0,
        backgroundColor = cfg.circleIcon and cfg.iconColor or { 0, 0, 0, 0 },
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
        children        = { iconLabel },
    }

    -- 标题行：图标 + 时间 + 复制 + 关闭
    local headerRow = UI.Panel {
        width             = "100%",
        height            = S(38),
        flexDirection     = "row",
        alignItems        = "center",
        gap               = S(6),
        paddingHorizontal = S(10),
        borderBottomWidth = 1,
        borderColor       = { 60, 50, 40, 150 },
        children = {
            iconBox,
            UI.Label {
                text          = data.time or "",
                fontSize      = S(11),
                fontFamily    = "sans",
                fontColor     = T.TEXT_HINT,
                flexGrow      = 1,
                flexShrink    = 1,
                pointerEvents = "none",
            },
            UI.Button {
                text       = "复制",
                fontSize   = S(13),
                fontFamily = "sans",
                height     = S(32),
                variant    = "ghost",
                fontColor  = { 100, 180, 255, 255 },
                onClick    = function()
                    local text = string.format("[%s][%s] %s", data.time or "", lvl, data.msg or "")
                    ui:SetClipboardText(text)
                    showCopyToast()
                end,
            },
            UI.Button {
                text       = "✕",
                fontSize   = S(15),
                fontFamily = "sans",
                width      = S(32),
                height     = S(32),
                variant    = "ghost",
                fontColor  = T.TEXT_SECONDARY,
                onClick    = function() hideDetailCard() end,
            },
        },
    }

    -- 全文消息（自动换行 + 自动撑高）
    -- whiteSpace="normal"：Label 的正确换行 API
    --   → multiline_=true → alignSelf="stretch"（撑满父容器宽度）
    --   → autoHeight_=true → Render 每帧 nvgTextBoxBounds 计算折行高，Widget.SetHeight 更新 Yoga
    -- 不设 width：由 whiteSpace="normal" 自动 alignSelf="stretch"，从父 Panel 继承宽度
    local msgBody = UI.Label {
        text              = data.msg or "",
        fontSize          = S(12),
        fontFamily        = "sans",
        fontColor         = T.TEXT_PRIMARY,
        whiteSpace        = "normal",
        paddingHorizontal = S(12),
        paddingTop        = S(10),
        paddingBottom     = S(14),
        pointerEvents     = "none",
    }

    -- 消息区域：
    -- UI.ScrollView 的内部滚动容器向子元素传 widthMode=UNDEFINED，
    -- 导致 Label measureFunc 取单行宽度路径，layoutWidth=全文宽，wrapWidth=全文宽，无折行。
    -- 改用普通 Panel：Yoga 列 flex 容器一定给子元素传 widthMode=EXACTLY，换行必然生效。
    -- 超过 800px 时内容被 card.maxHeight 截断（可接受），wrapping 正确是优先保证的。
    local msgScroll = UI.Panel {
        width      = "100%",
        flexShrink = 1,
        children   = { msgBody },
    }

    -- 遮罩层：点击卡片外部关闭
    local overlay = UI.Panel {
        position        = "absolute",
        left            = S(0), top = S(0),
        width           = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 80 },
        onClick         = function() hideDetailCard() end,
    }

    -- 卡片主体：Y 轴居中，内容自动撑高，超过 800 后转为滚动
    -- marginLeft/Right 给卡片与屏幕边缘留空隙（外边距）
    local card = UI.Panel {
        marginLeft      = S(12),
        marginRight     = S(12),
        maxHeight       = S(800),
        flexDirection   = "column",
        backgroundColor = { 28, 22, 18, 252 },
        borderRadius    = S(10),
        borderWidth     = S(1),
        borderColor     = { 80, 65, 50, 220 },
        -- 阻止点击穿透到 overlay（卡片内部点击不关闭）
        onClick         = function() end,
        children        = { headerRow, msgScroll },
    }

    -- detailCard_ 是 overlay + card 的容器，整体挂在 panel_
    -- justifyContent="center" 使 card（普通 flow 子元素）垂直居中
    -- overlay 为绝对定位，不参与 flex 布局，不影响居中计算
    detailCard_ = UI.Panel {
        position        = "absolute",
        left            = S(0), top = S(0),
        width           = "100%", height = "100%",
        flexDirection   = "column",
        justifyContent  = "center",
        alignItems      = "stretch",
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents   = "box-none",
        children        = { overlay, card },
    }
    panel_:AddChild(detailCard_)
end

-- ============================================================================
-- VirtualList：item 工厂 & 绑定
-- ============================================================================

local function createItem()
    -- 统一图标容器（INFO/WARNING 显示 emoji，ERROR 显示红圈 "!"）
    -- 用单一元素避免 display=none 可能的渲染问题
    local iconLabel = UI.Label {
        text          = "ℹ",
        fontSize      = S(13),
        fontFamily    = "sans",
        fontColor     = LEVEL_CFG.INFO.iconColor,
        pointerEvents = "none",
        textAlign     = "center",
        height        = S(1),  -- 消除 Yoga intrinsic 高度(~19px)，NanoVG 无 scissor 仍渲染到视觉中心
        minHeight     = S(0),  -- 允许 Yoga 使用 height=S(1) 而非 Label.Init 自动计算值
    }
    local iconBox = UI.Panel {
        width           = S(18),
        height          = S(18),
        borderRadius    = S(0),
        flexShrink      = 0,
        backgroundColor = { 0, 0, 0, 0 },
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
        children        = { iconLabel },
    }
    local timeLabel = UI.Label {
        text          = "",
        fontSize      = S(10),
        fontFamily    = "sans",
        fontColor     = T.TEXT_HINT,
        width         = S(60),
        flexShrink    = 0,
        pointerEvents = "none",
    }
    local msgLabel = UI.Label {
        text          = "",
        fontSize      = S(11),
        fontFamily    = "sans",
        fontColor     = T.TEXT_PRIMARY,
        width         = S(1),         -- 显式宽度禁用 autoWidth_，让 Render 启用 scissor 裁切，防止自动换行
        flexGrow      = 1,
        flexShrink    = 1,
        overflow      = "hidden",
        pointerEvents = "none",
    }

    local row = UI.Panel {
        width             = "100%",
        height            = ITEM_HEIGHT,
        flexDirection     = "row",
        alignItems        = "center",
        gap               = S(6),
        paddingHorizontal = S(10),
        paddingVertical   = S(4),
        borderBottomWidth = 1,
        borderColor       = { 50, 42, 32, 80 },
        onClick           = function(self, event) showDetailCard(self._data) end,
        onTap             = function(event, self) showDetailCard(self._data) end,
        children = { iconBox, timeLabel, msgLabel },
    }
    row._iconBox   = iconBox
    row._iconLabel = iconLabel
    row._timeLabel = timeLabel
    row._msgLabel  = msgLabel
    return row
end

local function bindItem(item, data, index)
    item._data = data
    local lvl = normalizeLevel(data.level)
    local cfg = LEVEL_CFG[lvl]

    if cfg.circleIcon then
        -- ERROR：红色圆圈 + "!" 文字
        item._iconBox:SetStyle({ borderRadius = S(9), backgroundColor = cfg.iconColor })
        item._iconLabel:SetStyle({ fontSize = S(11), fontColor = { 255, 255, 255, 255 } })
        item._iconLabel:SetText("!")
    else
        -- INFO / WARNING：透明背景 + emoji
        item._iconBox:SetStyle({ borderRadius = S(0), backgroundColor = { 0, 0, 0, 0 } })
        item._iconLabel:SetStyle({ fontSize = S(13), fontColor = cfg.iconColor })
        item._iconLabel:SetText(cfg.icon)
    end
    item._timeLabel:SetText(data.time or "")
    item._msgLabel:SetText(data.msg or "")
    -- 引擎层日志偏灰色（前后端均适用），用户代码日志保持原级别颜色
    -- source 含 "engine" 的都是引擎日志（"engine" = 前端引擎, "server_engine" = 后端引擎）
    local msgColor = cfg.iconColor
    local src = data.source or ""
    if string.find(src, "engine", 1, true) then
        msgColor = { 160, 160, 175, 255 }
    end
    item._msgLabel:SetStyle({ fontColor = msgColor })

    local bg = (index % 2 == 0) and { 28, 22, 16, 120 } or { 0, 0, 0, 0 }
    item:SetStyle({ backgroundColor = bg })
end

-- ============================================================================
-- 面板内 badge 工厂（可点击，显示计数）
-- ============================================================================

local function makeBadge(cfg, level, countRef)
    -- ERROR 用圆形图标；INFO / WARNING 保持原始 emoji label
    local iconWidget
    if cfg.circleIcon then
        local iconInner = UI.Label {
            text          = cfg.iconText,
            fontSize      = S(10),
            fontFamily    = "sans",
            fontColor     = { 255, 255, 255, 255 },
            pointerEvents = "none",
            textAlign     = "center",
            height        = S(1),  -- 消除 Yoga intrinsic 高度，NanoVG 无 scissor 仍渲染到视觉中心
            minHeight     = S(0),  -- 允许 Yoga 使用 height=S(1)
        }
        iconWidget = UI.Panel {
            width           = S(16),
            height          = S(16),
            borderRadius    = S(8),
            flexShrink      = 0,
            backgroundColor = cfg.iconColor,
            justifyContent  = "center",
            alignItems      = "center",
            pointerEvents   = "none",
            children        = { iconInner },
        }
    else
        iconWidget = UI.Label {
            text          = cfg.icon,
            fontSize      = S(12),
            fontFamily    = "sans",
            fontColor     = cfg.iconColor,
            flexShrink    = 0,
            pointerEvents = "none",
        }
    end
    local cntLbl = UI.Label {
        text          = "0",
        fontSize      = S(12),
        fontFamily    = "sans",
        fontColor     = T.TEXT_PRIMARY,
        flexShrink    = 0,
        pointerEvents = "none",
    }
    countRef[1] = cntLbl

    -- 防抖时间戳：防止 pointer click + gesture tap 同时触发导致双重 toggle
    local lastToggleTime_ = 0
    local function doToggle()
        local now = time:GetElapsedTime()
        if now - lastToggleTime_ < 0.3 then return end
        lastToggleTime_ = now
        filterLevels_[level] = not filterLevels_[level]
        updateBadgeStyles()
        refreshList(true)
    end

    local badge = UI.Button {
        flexDirection          = "row",
        alignItems             = "center",
        height                 = S(34),
        minWidth               = S(0),   -- 覆盖 Button 默认的 64px 最小宽
        gap                    = S(3),
        paddingHorizontal      = S(7),
        borderRadius           = S(5),
        backgroundColor        = { 0, 0, 0, 0 },
        hoverBackgroundColor   = { 0, 0, 0, 0 },  -- 无 hover 效果
        pressedBackgroundColor = { 0, 0, 0, 0 },  -- 无 press 效果
        variant                = "ghost",
        onClick                = function(self) doToggle() end,
        -- onTap：移动端手势系统独立路径，与 onClick 互补（防抖防双触发）
        onTap                  = function(event, self) doToggle() end,
        children = { iconWidget, cntLbl },
    }
    return badge
end

-- ============================================================================
-- 日志面板
-- ============================================================================

local function createLogPanel()
    -- 不重置 filterLevels_ / filterText_（全局持久化，面板关闭后也保留）

    -- ── 环境切换 tab（多人模式下可见）─────────────────────
    local tabGroup = nil
    if isNetworkMode_ then
        local isClient = (viewMode_ == "client")
        clientTab_ = UI.Button {
            text       = "前端",
            fontSize   = S(11),
            fontFamily = "sans",
            height     = S(24),
            minWidth   = S(0),
            paddingHorizontal = S(10),
            borderRadius      = S(4),
            variant            = "ghost",
            backgroundColor        = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
            hoverBackgroundColor   = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
            pressedBackgroundColor = isClient and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
            fontColor              = isClient and TAB_ACTIVE_FG or TAB_INACTIVE_FG,
            onClick = function(self) switchViewMode("client") end,
            onTap   = function(event, self) switchViewMode("client") end,
        }
        serverTab_ = UI.Button {
            text       = "后端",
            fontSize   = S(11),
            fontFamily = "sans",
            height     = S(24),
            minWidth   = S(0),
            paddingHorizontal = S(10),
            borderRadius      = S(4),
            variant            = "ghost",
            backgroundColor        = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
            hoverBackgroundColor   = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
            pressedBackgroundColor = isClient and TAB_INACTIVE_BG or TAB_ACTIVE_BG,
            fontColor              = isClient and TAB_INACTIVE_FG or TAB_ACTIVE_FG,
            onClick = function(self) switchViewMode("server") end,
            onTap   = function(event, self) switchViewMode("server") end,
        }
        tabGroup = UI.Panel {
            flexDirection   = "row",
            alignItems      = "center",
            gap             = S(2),
            height          = S(28),
            marginTop       = S(7),
            paddingHorizontal = S(2),
            borderRadius    = S(6),
            backgroundColor = { 30, 25, 20, 200 },
            borderWidth     = S(1),
            borderColor     = { 60, 50, 40, 150 },
            children        = { clientTab_, serverTab_ },
        }
    end

    -- ── 标题行（共享组件：性能 tab 仅显示标题+关闭，日志 tab 显示 envTab+accountInfo）──
    local titleChildren = {}
    -- 前端/后端 tab 组（仅日志 tab 可见，性能 tab 隐藏）
    if tabGroup then
        envTabGroup_ = tabGroup
        envTabGroup_.visible = (panelTab_ == "log")
        table.insert(titleChildren, envTabGroup_)
    end
    table.insert(titleChildren, UI.Panel { flexGrow = 1 })   -- 弹性间距
    accountInfoLabel_ = UI.Label {
        text          = buildAccountInfoText(),
        fontSize      = S(11),
        fontFamily    = "sans",
        fontColor     = T.TEXT_HINT,
        textAlign     = "right",
        maxWidth      = S(320),
        flexShrink    = 1,
        pointerEvents = "none",
        marginRight   = S(4),
    }
    table.insert(titleChildren, accountInfoLabel_)
    -- "调试助手" + 版本号：绝对定位容器，始终水平+垂直居中
    table.insert(titleChildren, UI.Panel {
        position       = "absolute",
        left           = S(0),
        width          = "100%",
        height         = "100%",
        justifyContent = "center",
        alignItems     = "center",
        pointerEvents  = "none",
        children = {
            UI.Panel {
                flexDirection  = "row",
                alignItems     = "baseline",
                gap            = S(4),
                pointerEvents  = "none",
                children = {
                    UI.Label {
                        text          = "调试助手",
                        fontSize      = S(13),
                        fontFamily    = "sans",
                        fontColor     = { 220, 200, 160, 255 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text          = LogViewerUI.Version,
                        fontSize      = S(9),
                        fontFamily    = "sans",
                        fontColor     = { 120, 115, 105, 180 },
                        pointerEvents = "none",
                    },
                },
            },
        },
    })

    local titleRow = UI.Panel {
        width           = "100%",
        height          = S(32),
        flexDirection   = "row",
        alignItems      = "center",
        paddingHorizontal = S(8),
        backgroundColor = T.BG_DARK,
        children = titleChildren,
    }

    -- ── 过滤行 ──────────────────────────────────────────
    local infoRef  = {}
    local warnRef  = {}
    local errorRef = {}

    local netRef    = {}
    local engineRef = {}
    infoBadge_   = makeBadge(LEVEL_CFG.INFO,    "INFO",    infoRef)
    netBadge_    = makeBadge(LEVEL_CFG.NET,     "NET",     netRef)
    warnBadge_   = makeBadge(LEVEL_CFG.WARNING, "WARNING", warnRef)
    errorBadge_  = makeBadge(LEVEL_CFG.ERROR,   "ERROR",   errorRef)
    engineBadge_ = makeBadge(LEVEL_CFG.ENGINE,  "ENGINE",  engineRef)

    infoCount_   = infoRef[1]
    netCount_    = netRef[1]
    warnCount_   = warnRef[1]
    errorCount_  = errorRef[1]
    engineCount_ = engineRef[1]

    -- 搜索框（恢复持久 filterText_）
    searchField_ = UI.TextField {
        width       = "100%",
        height      = S(30),
        placeholder = "过滤",
        fontSize    = S(12),
        paddingRight = S(26),          -- 为 X 按钮留出右侧空间
        value       = filterText_,  -- 持久化：用上次的过滤文字
        onChange    = function(self, value)
            filterText_ = value
            -- 显示/隐藏 X 按钮（用 opacity 而非 display，更适合绝对定位元素）
            if clearFilterXBtn_ then
                local visible = value ~= ""
                clearFilterXBtn_:SetStyle({
                    opacity       = visible and 1 or 0,
                    pointerEvents = visible and "auto" or "none",
                })
            end
            refreshList(true)
        end,
    }

    -- X 清空按钮：绝对定位在输入框内右侧，垂直居中（(30-18)/2=6）
    -- 使用 opacity=0 + pointerEvents="none" 隐藏（display 对绝对定位元素不可靠）
    clearFilterXBtn_ = UI.Panel {
        position        = "absolute",
        right           = S(5),
        top             = S(6),
        width           = S(18),
        height          = S(18),
        borderRadius    = S(9),
        backgroundColor = { 100, 100, 110, 200 },
        justifyContent  = "center",
        alignItems      = "center",
        opacity         = (filterText_ ~= "") and 1 or 0,
        pointerEvents   = (filterText_ ~= "") and "auto" or "none",
        onClick         = function(self, event)
            filterText_ = ""
            if searchField_ then searchField_:Clear() end
            if clearFilterXBtn_ then
                clearFilterXBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
            end
            refreshList(true)
        end,
        children = {
            UI.Label {
                text          = "×",
                fontSize      = S(12),
                fontFamily    = "sans",
                fontColor     = { 220, 220, 220, 255 },
                pointerEvents = "none",
                textAlign     = "center",
                height        = S(1),      -- 消除 Yoga intrinsic 高度(~19px)，NanoVG 无 scissor 仍渲染到视觉中心
                minHeight     = S(0),      -- 允许 Yoga 使用 height=S(1) 而非 Label.Init 自动计算值
            },
        },
    }

    -- 搜索框容器（输入框为 relative 容器，X 按钮绝对定位在其内）
    local searchContainer = UI.Panel {
        flexGrow = 1,
        height   = S(30),
        children = { searchField_, clearFilterXBtn_ },
    }

    -- 过滤内容容器（搜索框 + badges + 清空按钮，性能 tab 时隐藏）
    filterContent_ = UI.Panel {
        flexGrow      = 1,
        flexShrink    = 1,
        flexDirection = "row",
        alignItems    = "center",
        gap           = S(2),
        visible       = (panelTab_ == "log"),
        children = {
            searchContainer,
            UI.Panel { width = S(4) },
            infoBadge_,
            netBadge_,
            warnBadge_,
            errorBadge_,
            engineBadge_,
            UI.Panel { width = S(6) },
            UI.Button {
                text       = "清空",
                fontSize   = S(13),
                fontFamily = "sans",
                variant    = "ghost",
                height     = S(34),
                fontColor  = T.TEXT_HINT,
                onClick    = function()
                    LogCapture.Clear()
                    refreshList("bottom")
                end,
            },
        },
    }

    -- ── 悬浮窗性能子Tab（与关闭按钮同行，日志 tab 时隐藏）──
    local ST_ACTIVE_BG = { 70, 130, 200, 255 }
    local ST_INACTIVE_BG = { 50, 48, 42, 200 }
    local ST_ACTIVE_FG = { 255, 255, 255, 255 }
    local ST_INACTIVE_FG = { 170, 160, 140, 255 }
    local SUB_TABS = {
        { key = "fps",    label = "帧率" },
        { key = "mem",    label = "内存" },
        { key = "net",    label = "网络" },
        { key = "render", label = "渲染" },
    }
    local subTabChildren = {
        UI.Label {
            text = "悬浮窗:", fontSize = S(13), fontFamily = "sans",
            fontColor = { 150, 145, 135, 255 }, marginRight = S(2),
        },
    }
    for _, st in ipairs(SUB_TABS) do
        local active = (perfSubTab_ == st.key)
        local btn = UI.Button {
            text = st.label, fontSize = S(13), fontFamily = "sans",
            height = S(28), paddingHorizontal = S(14),
            borderRadius = S(14), variant = "ghost",
            borderWidth = S(0),
            backgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            hoverBackgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            pressedBackgroundColor = active and ST_ACTIVE_BG or ST_INACTIVE_BG,
            fontColor = active and ST_ACTIVE_FG or ST_INACTIVE_FG,
            onClick = function(self) switchPerfSubTab(st.key) end,
        }
        perfSubTabBtns_[st.key] = btn
        subTabChildren[#subTabChildren + 1] = btn
    end
    perfSubTabContent_ = UI.Panel {
        position      = "absolute",
        left          = S(10),
        top           = S(0),
        height        = "100%",
        flexDirection = "row",
        alignItems    = "center",
        gap           = S(4),
        visible       = (panelTab_ == "perf"),
        children      = subTabChildren,
    }

    -- ── 界面 tab 搜索框（与日志搜索框同位置、同风格）────────────
    local uitreeFilterText = UITreeView.GetFilter and UITreeView.GetFilter() or ""
    uitreeSearchField_ = UI.TextField {
        width       = "100%",
        height      = S(30),
        placeholder = "搜索控件…",
        fontSize    = S(12),
        paddingRight = S(26),
        value       = uitreeFilterText,
        onChange    = function(self, value)
            if uitreeClearXBtn_ then
                local vis = value ~= ""
                uitreeClearXBtn_:SetStyle({
                    opacity       = vis and 1 or 0,
                    pointerEvents = vis and "auto" or "none",
                })
            end
            UITreeView.SetFilter(value)
        end,
    }
    uitreeClearXBtn_ = UI.Panel {
        position        = "absolute",
        right           = S(5),
        top             = S(6),
        width           = S(18),
        height          = S(18),
        borderRadius    = S(9),
        backgroundColor = { 100, 100, 110, 200 },
        justifyContent  = "center",
        alignItems      = "center",
        opacity         = (uitreeFilterText ~= "") and 1 or 0,
        pointerEvents   = (uitreeFilterText ~= "") and "auto" or "none",
        onClick         = function(self)
            if uitreeSearchField_ then uitreeSearchField_:Clear() end
            if uitreeClearXBtn_ then
                uitreeClearXBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
            end
            UITreeView.SetFilter("")
        end,
        children = {
            UI.Label {
                text          = "×",
                fontSize      = S(12),
                fontFamily    = "sans",
                fontColor     = { 220, 220, 220, 255 },
                pointerEvents = "none",
                textAlign     = "center",
                height        = S(1),
                minHeight     = S(0),
            },
        },
    }
    local uitreeSearchContainer = UI.Panel {
        flexGrow = 1,
        height   = S(30),
        children = { uitreeSearchField_, uitreeClearXBtn_ },
    }
    uitreeFilterContent_ = UI.Panel {
        position      = "absolute",
        left          = S(10),
        right         = S(56),
        top           = S(0),
        height        = "100%",
        flexDirection = "row",
        alignItems    = "center",
        visible       = (panelTab_ == "uitree"),
        children      = { uitreeSearchContainer },
    }

    -- ── 场景 tab 搜索框（与日志搜索框同位置、同风格）────────────
    local sceneFilterText = SceneTreeView.GetFilter and SceneTreeView.GetFilter() or ""
    sceneSearchField_ = UI.TextField {
        width       = "100%",
        height      = S(30),
        placeholder = "搜索节点/组件…",
        fontSize    = S(12),
        paddingRight = S(26),
        value       = sceneFilterText,
        onChange    = function(self, value)
            if sceneClearXBtn_ then
                local vis = value ~= ""
                sceneClearXBtn_:SetStyle({
                    opacity       = vis and 1 or 0,
                    pointerEvents = vis and "auto" or "none",
                })
            end
            SceneTreeView.SetFilter(value)
        end,
    }
    sceneClearXBtn_ = UI.Panel {
        position        = "absolute",
        right           = S(5),
        top             = S(6),
        width           = S(18),
        height          = S(18),
        borderRadius    = S(9),
        backgroundColor = { 100, 100, 110, 200 },
        justifyContent  = "center",
        alignItems      = "center",
        opacity         = (sceneFilterText ~= "") and 1 or 0,
        pointerEvents   = (sceneFilterText ~= "") and "auto" or "none",
        onClick         = function(self)
            if sceneSearchField_ then sceneSearchField_:Clear() end
            if sceneClearXBtn_ then
                sceneClearXBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
            end
            SceneTreeView.SetFilter("")
        end,
        children = {
            UI.Label {
                text          = "×",
                fontSize      = S(12),
                fontFamily    = "sans",
                fontColor     = { 220, 220, 220, 255 },
                pointerEvents = "none",
                textAlign     = "center",
                height        = S(1),
                minHeight     = S(0),
            },
        },
    }
    local sceneSearchContainer = UI.Panel {
        flexGrow = 1,
        height   = S(30),
        children = { sceneSearchField_, sceneClearXBtn_ },
    }
    sceneFilterContent_ = UI.Panel {
        position      = "absolute",
        left          = S(10),
        right         = S(56),
        top           = S(0),
        height        = "100%",
        flexDirection = "row",
        alignItems    = "center",
        visible       = (panelTab_ == "scene"),
        children      = { sceneSearchContainer },
    }

    local filterRow = UI.Panel {
        width             = "100%",
        height            = S(44),
        flexDirection     = "row",
        alignItems        = "center",
        paddingHorizontal = S(10),
        backgroundColor   = T.BG_DARK,
        borderBottomWidth = (panelTab_ == "log" or panelTab_ == "perf") and 1 or 0,
        borderColor       = T.BORDER,
        children = {
            filterContent_,
            perfSubTabContent_,
            uitreeFilterContent_,      -- absolute: 不参与 flex 布局
            sceneFilterContent_,       -- absolute: 不参与 flex 布局
            UI.Panel { width = S(2) },
            UI.Button {
                text       = "✕",
                fontSize   = S(15),
                fontFamily = "sans",
                width      = S(34),
                height     = S(34),
                variant    = "ghost",
                fontColor  = T.TEXT_SECONDARY,
                onClick    = function()
                    LogViewerUI.Hide()
                end,
            },
        },
    }

    -- ── 列表 ────────────────────────────────────────────
    -- bounces=false：GetLayout() 在移动端返回 NaN → maxScrollY=0 → bounce 代码每帧把 scrollY×0.9 弹回 0
    -- viewportHeight：绕开 CalculateVisibleRange 里 GetLayout NaN 导致的 fallback=400（会漏掉末尾几项）
    vlist_ = UI.VirtualList {
        width          = "100%",
        flexGrow       = 1,
        flexShrink     = 1,
        itemHeight     = ITEM_HEIGHT,
        bounces        = false,
        viewportHeight = math.floor(getVListHeight()),
        data           = {},
        createItem     = createItem,
        bindItem       = bindItem,
    }

    -- 保存 filterRow 引用到模块变量
    filterRow_ = filterRow

    -- ── 日志内容容器（仅 vlist，panelTab_ == "log" 时可见）
    logContent_ = UI.Panel {
        width = "100%",
        flexGrow = (panelTab_ == "log") and 1 or 0,
        flexShrink = 1,
        height = (panelTab_ == "log") and "auto" or 0,
        overflow = (panelTab_ == "log") and "visible" or "hidden",
        flexDirection = "column",
        visible = (panelTab_ == "log"),
        backgroundColor = T.BG_DARK,
        children = { vlist_ },
    }

    -- ── 性能内容容器（panelTab_ == "perf" 时可见）──────────

    perfValLabels_ = {}
    perfMemBars_ = {}

    -- 颜色定义
    local SEC_HDR_BG  = { 38, 35, 30, 255 }
    local SEC_HDR_FG  = { 245, 230, 211, 255 }
    local ROW_LABEL   = { 155, 145, 130, 255 }
    local ROW_VALUE   = { 225, 215, 200, 255 }
    local ROW_H       = S(34)
    local LABEL_FS    = S(12)
    local VALUE_FS    = S(13)
    local MEM_BAR_H   = S(6)

    -- 数据行工厂：左侧中文标签 + 右侧数值
    local function makePerfRow(key, label, valueColor)
        local valLabel = UI.Label {
            text = "--", fontSize = VALUE_FS, fontFamily = "sans",
            fontColor = valueColor or ROW_VALUE, pointerEvents = "none",
        }
        perfValLabels_[key] = valLabel
        return UI.Panel {
            width = "100%", height = ROW_H,
            flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            paddingHorizontal = S(16),
            children = {
                UI.Label {
                    text = label, fontSize = LABEL_FS, fontFamily = "sans",
                    fontColor = ROW_LABEL, pointerEvents = "none",
                },
                valLabel,
            },
        }
    end

    -- 内存行工厂：标签 + 进度条 + 数值
    local function makeMemPerfRow(key, label, barColor)
        local valLabel = UI.Label {
            text = "--", fontSize = VALUE_FS, fontFamily = "sans",
            fontColor = ROW_VALUE, pointerEvents = "none",
            width = S(70), textAlign = "right",
        }
        perfValLabels_[key] = valLabel
        local bar = UI.Panel {
            width = "0%", height = MEM_BAR_H,
            borderRadius = S(3), backgroundColor = barColor,
        }
        perfMemBars_[key] = bar
        local barBg = UI.Panel {
            flexGrow = 1, flexShrink = 1, height = MEM_BAR_H,
            borderRadius = S(3), backgroundColor = { 45, 42, 38, 255 },
            children = { bar },
        }
        return UI.Panel {
            width = "100%", height = ROW_H,
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = S(16), gap = S(10),
            children = {
                UI.Label {
                    text = label, fontSize = LABEL_FS, fontFamily = "sans",
                    fontColor = ROW_LABEL, pointerEvents = "none",
                    width = S(80),
                },
                barBg,
                valLabel,
            },
        }
    end

    -- 分区标题工厂
    local function makeSectionHeader(title)
        return UI.Panel {
            width = "100%", height = S(30),
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = S(14),
            backgroundColor = SEC_HDR_BG,
            marginTop = S(2),
            children = {
                UI.Label {
                    text = title, fontSize = S(11), fontFamily = "sans",
                    fontColor = SEC_HDR_FG, pointerEvents = "none",
                    fontWeight = "bold",
                },
            },
        }
    end

    -- 分隔线
    local function makeDivider()
        return UI.Panel {
            width = "100%", height = S(1),
            backgroundColor = { 50, 46, 40, 255 },
            marginHorizontal = S(14),
        }
    end

    -- ── 帧率数据行（水平排列在图表顶部）──
    local MINI_FS = S(11)
    local MINI_LABEL_CLR = { 130, 125, 115, 255 }
    local MINI_VAL_CLR   = { 220, 215, 200, 255 }
    local function makeMiniStat(key, label, valueColor)
        local valLabel = UI.Label {
            text = "--", fontSize = MINI_FS, fontFamily = "sans",
            fontColor = valueColor or MINI_VAL_CLR, pointerEvents = "none",
        }
        perfValLabels_[key] = valLabel
        return UI.Panel {
            flexDirection = "row", alignItems = "center", gap = S(3),
            pointerEvents = "none",
            children = {
                UI.Label {
                    text = label, fontSize = MINI_FS, fontFamily = "sans",
                    fontColor = MINI_LABEL_CLR, pointerEvents = "none",
                },
                valLabel,
            },
        }
    end

    local fpsStatsBar = UI.Panel {
        width = "100%", height = S(22),
        flexDirection = "row", alignItems = "center",
        justifyContent = "flex-start", gap = S(40),
        paddingHorizontal = S(10),
        backgroundColor = { 15, 14, 12, 200 },
        borderTopLeftRadius = S(6), borderTopRightRadius = S(6),
        pointerEvents = "none",
        children = {
            makeMiniStat("fps",      "FPS:", { 80, 200, 80, 255 }),
            makeMiniStat("dt",       "帧时间:"),
            makeMiniStat("frameNum", "帧:"),
            makeMiniStat("elapsed",  "运行:"),
        },
    }

    -- ── 帧率图表 ──
    local chartBody = UI.Panel {
        width = "100%", flexGrow = 1,
        backgroundColor = { 10, 10, 12, 255 },
        borderBottomLeftRadius = S(6), borderBottomRightRadius = S(6),
    }
    local origFullRender = chartBody.Render
    chartBody.Render = function(self, nvg)
        if origFullRender then origFullRender(self, nvg) end
        local layout = self:GetAbsoluteLayout()
        if layout and #fullChartData_ > 0 then
            drawBarChart(nvg, layout.x + S(2), layout.y + S(2), layout.w - S(4), layout.h - S(4), fullChartData_, true)
        end
    end

    fullChartPanel_ = UI.Panel {
        width = "100%", height = S(130),
        flexDirection = "column",
        marginHorizontal = S(10), marginTop = S(6), marginBottom = S(4),
        children = { fpsStatsBar, chartBody },
    }

    -- ── 内存分区（含操作按钮）──
    local memSection = UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            -- 内存标题行（含操作按钮）
            UI.Panel {
                width = "100%", height = S(38),
                flexDirection = "row", alignItems = "center",
                paddingHorizontal = S(14),
                backgroundColor = SEC_HDR_BG,
                marginTop = S(2),
                children = {
                    UI.Label {
                        text = "内存", fontSize = S(11), fontFamily = "sans",
                        fontColor = SEC_HDR_FG, pointerEvents = "none",
                        fontWeight = "bold",
                    },
                    UI.Panel { flexGrow = 1 },  -- 弹性间隔
                    UI.Button {
                        text = "GC 回收", fontSize = S(11), fontFamily = "sans",
                        height = S(26), paddingHorizontal = S(12),
                        variant = "outline", borderRadius = S(4),
                        fontColor = { 80, 160, 240, 255 },
                        borderColor = { 80, 160, 240, 180 },
                        onClick = function(self)
                            PerfProfiler.CollectGC()
                            updatePerfDisplay()
                        end,
                    },
                    UI.Button {
                        text = "清理缓存", fontSize = S(11), fontFamily = "sans",
                        height = S(26), paddingHorizontal = S(12), marginLeft = S(8),
                        variant = "outline", borderRadius = S(4),
                        fontColor = { 220, 170, 30, 255 },
                        borderColor = { 220, 170, 30, 180 },
                        onClick = function(self)
                            PerfProfiler.CleanCache()
                            updatePerfDisplay()
                        end,
                    },
                },
            },
            makePerfRow("totalMem",    "系统物理内存"),
            makeMemPerfRow("luaMem",    "Lua 内存",  { 80, 160, 240, 255 }),
            makeMemPerfRow("cacheMem",  "缓存总量",  { 220, 170, 30, 255 }),
            makeMemPerfRow("texMem",    "纹理内存",  { 140, 200, 100, 255 }),
            makeMemPerfRow("modelMem",  "模型内存",  { 200, 130, 220, 255 }),
            makeMemPerfRow("soundMem",  "音频内存",  { 240, 140, 80, 255 }),
            makePerfRow("bgLoadResources", "后台加载资源"),
        },
    }

    -- ── 网络分区（多人模式时才显示）──
    perfNetSection_ = UI.Panel {
        width = "100%", flexDirection = "column",
        visible = false, height = S(0), overflow = "hidden",
        children = {
            makeSectionHeader("网络"),
            makePerfRow("bytesIn",    "接收速率"),
            makePerfRow("bytesOut",   "发送速率"),
            makePerfRow("packetsIn",  "接收包数"),
            makePerfRow("packetsOut", "发送包数"),
            makePerfRow("ping",       "延迟"),
        },
    }

    -- ── 渲染分区 ──
    local renderSection = UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            makeSectionHeader("渲染"),
            makePerfRow("gpuBatches",  "GPU 总批次"),
            makePerfRow("drawCalls",   "3D 批次"),
            makePerfRow("uiDrawCalls", "UI 批次"),
            makePerfRow("primitives",  "三角面数"),
            makePerfRow("gpuPrimitives","总面数"),
            makePerfRow("views",       "视图数"),
            makePerfRow("geometries",  "几何体数"),
            makePerfRow("lights",      "光源数"),
            makePerfRow("shadowMaps",  "阴影贴图数"),
            makePerfRow("occluders",   "遮挡体数"),
            makePerfRow("apiName",     "渲染 API"),
            makePerfRow("vsync",       "垂直同步"),
            makePerfRow("dynamicInstancing", "动态实例化"),
            makePerfRow("drawShadows",      "阴影绘制"),
            makePerfRow("shadowMapSize",    "阴影贴图尺寸"),
            makePerfRow("hdrRendering",     "HDR 渲染"),
            makePerfRow("specularLighting", "高光照明"),
            makePerfRow("textureQuality",   "纹理质量"),
            makePerfRow("textureAnisotropy","各向异性过滤"),
            makePerfRow("maxBones",         "最大骨骼数"),
            makePerfRow("instancingSupport","GPU 实例化"),
            makePerfRow("srgb",             "sRGB"),
        },
    }

    -- ── 屏幕分区 ──
    local screenSection = UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            makeSectionHeader("屏幕"),
            makePerfRow("resolution",    "渲染分辨率"),
            makePerfRow("desktopRes",    "桌面分辨率"),
            makePerfRow("dpr",           "像素比 (DPR)"),
            makePerfRow("displayDPI",    "屏幕 DPI"),
            makePerfRow("msaa",          "抗锯齿 (MSAA)"),
            makePerfRow("refreshRate",   "刷新率"),
            makePerfRow("maxFps",        "最大帧率"),
            makePerfRow("minFps",        "最小帧率"),
            makePerfRow("timerPeriod",   "定时器精度"),
            makePerfRow("fullscreen",   "全屏模式"),
            makePerfRow("monitorCount", "显示器数量"),
            makePerfRow("tripleBuffer", "三重缓冲"),
        },
    }

    -- ── 系统信息分区 ──
    local systemSection = UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            makeSectionHeader("系统"),
            makePerfRow("platform",    "运行平台"),
            makePerfRow("osVersion",   "操作系统"),
            makePerfRow("cpuPhysical", "物理 CPU 核心"),
            makePerfRow("cpuLogical",  "逻辑 CPU 核心"),
            makePerfRow("hostName",    "主机名"),
            makePerfRow("loginName",   "登录名"),
        },
    }

    -- ── 其它分区 ──
    local otherSection = UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            makeSectionHeader("其它"),
            makePerfRow("audioMixRate",      "音频混合率"),
            makePerfRow("audioStereo",       "音频立体声"),
            makePerfRow("maxInactiveFps",    "后台最大帧率"),
            makePerfRow("timeStepSmoothing", "帧平滑步数"),
            makePerfRow("pauseMinimized",   "最小化时暂停"),
            makePerfRow("timeScale",        "场景时间缩放"),
        },
    }

    -- 性能内容主容器（滚动布局，占满整页）
    -- 顺序：图表(含帧率数据) → 内存(含操作按钮) → 网络 → 渲染 → 屏幕 → 系统 → 其它
    perfContent_ = UI.ScrollView {
        width = "100%",
        flexGrow = (panelTab_ == "perf") and 1 or 0,
        height = (panelTab_ == "perf") and "auto" or 0,
        overflow = (panelTab_ == "perf") and "visible" or "hidden",
        flexBasis = 0,
        flexShrink = 1,
        scrollY = true,
        showScrollbar = true,
        flexDirection = "column",
        visible = (panelTab_ == "perf"),
        backgroundColor = T.BG_DARK,
        paddingBottom = (panelTab_ == "perf") and S(10) or 0,
        children = {
            fullChartPanel_,
            memSection,
            perfNetSection_,
            renderSection,
            screenSection,
            systemSection,
            otherSection,
        },
    }

    -- ── 界面 tab 内容区 ──────────────────────────────────────
    uitreeContent_ = UI.Panel {
        width = "100%",
        flexGrow = (panelTab_ == "uitree") and 1 or 0,
        height = (panelTab_ == "uitree") and "auto" or 0,
        flexBasis = 0,
        flexDirection = "column",
        visible = (panelTab_ == "uitree"),
        backgroundColor = T.BG_DARK,
    }
    UITreeView.Create(uitreeContent_)

    -- ── 场景 tab 内容区 ──────────────────────────────────────
    sceneContent_ = UI.Panel {
        width = "100%",
        flexGrow = (panelTab_ == "scene") and 1 or 0,
        height = (panelTab_ == "scene") and "auto" or 0,
        flexBasis = 0,
        flexDirection = "column",
        visible = (panelTab_ == "scene"),
        backgroundColor = T.BG_DARK,
    }
    SceneTreeView.Create(sceneContent_)

    -- ── 底部 tab 栏（全屏面板，GMTools 风格）──────────────────
    local P_TAB_H = S(44)
    local P_ACTIVE_BG = { 60, 55, 50, 255 }
    local P_INACTIVE_BG = { 30, 25, 20, 200 }
    local P_ACTIVE_FG = { 245, 230, 211, 255 }
    local P_INACTIVE_FG = { 195, 175, 145, 255 }
    local P_ACTIVE_BORDER = { 60, 50, 40, 150 }
    local P_INACTIVE_BORDER = { 80, 65, 45, 200 }
    local function makePanelTabBtn(label, key)
        return UI.Button {
            text = label, fontSize = S(13), fontFamily = "sans",
            height = P_TAB_H - S(8), flexGrow = 1, minWidth = S(0),
            borderRadius = S(6), variant = "ghost",
            borderWidth = S(1),
            backgroundColor = panelTab_ == key and P_ACTIVE_BG or P_INACTIVE_BG,
            hoverBackgroundColor = panelTab_ == key and P_ACTIVE_BG or P_INACTIVE_BG,
            pressedBackgroundColor = panelTab_ == key and P_ACTIVE_BG or P_INACTIVE_BG,
            borderColor = panelTab_ == key and P_ACTIVE_BORDER or P_INACTIVE_BORDER,
            fontColor = panelTab_ == key and P_ACTIVE_FG or P_INACTIVE_FG,
            onClick = function(self) switchPanelTab(key) end,
        }
    end
    panelLogTab_    = makePanelTabBtn("日志", "log")
    panelPerfTab_   = makePanelTabBtn("性能", "perf")
    panelUITreeTab_ = makePanelTabBtn("界面", "uitree")
    panelSceneTab_  = makePanelTabBtn("场景", "scene")
    local panelTabBar = UI.Panel {
        width = "100%", height = P_TAB_H,
        flexDirection = "row", alignItems = "center",
        gap = S(5), paddingHorizontal = S(8),
        backgroundColor = T.BG_DARK,
        borderTopWidth = 1, borderColor = T.BORDER,
        children = { panelLogTab_, panelPerfTab_, panelUITreeTab_, panelSceneTab_ },
    }

    panel_ = UI.Panel {
        id              = "logViewerPanel",
        position        = "absolute",
        zIndex          = 20001,
        left            = S(0),
        top             = S(0),
        width           = "100%",
        height          = "100%",
        flexDirection   = "column",
        backgroundColor = { 18, 14, 10, 240 },
        children        = { titleRow, filterRow_, logContent_, perfContent_, uitreeContent_, sceneContent_, panelTabBar },
    }

    local root = UI.GetRoot()
    if root then root:AddChild(panel_) end

    -- 滚动到底部按钮：挂在 root（最顶层），不挂在 panel_ 内，
    -- 避免被 VirtualList 的滚动内容遮挡
    local btnSize   = 40
    local btnMargin = 14
    local lw, lh    = getLayoutSize()
    scrollDownBtn_ = UI.Panel {
        position        = "absolute",
        left            = lw - btnSize - btnMargin - 10,
        top             = lh - btnSize - btnMargin,
        width           = btnSize,
        height          = btnSize,
        borderRadius    = btnSize / 2,
        backgroundColor = { 55, 55, 65, 230 },
        justifyContent  = "center",
        alignItems      = "center",
        opacity         = 0,
        pointerEvents   = "none",
        onClick         = function(self, event)
            if vlist_ then
                local sv  = vlist_.scrollView_
                local cH  = vlist_:GetItemCount() * (vlist_.rowHeight_ or ITEM_HEIGHT)
                sv.contentHeight_ = cH
                sv:SetScrollDirect(0, math.max(0, cH - getVListHeight()))
                scrollDownVisible_ = false
                if scrollDownBtn_ then
                    scrollDownBtn_:SetStyle({ opacity = 0, pointerEvents = "none" })
                end
            end
        end,
        children = {
            UI.Label {
                text          = "↓",
                fontSize      = S(20),
                fontFamily    = "sans",
                fontColor     = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    }
    if root then root:AddChild(scrollDownBtn_) end

    -- panel_ 和 scrollDownBtn_ 已创建，更新 UITreeView 外部引用（用于排除自身节点）
    UITreeView.UpdateRefs({
        panel = panel_,
        btn = logBtnRoot_,
        scrollDownBtn = scrollDownBtn_,
    })
end

-- ============================================================================
-- 悬浮 LOG 按钮
-- ============================================================================

local btnPositionInit_ = false   -- 首次构建标记
local function buildBtnWidget()
    if not btnPositionInit_ then
        -- 首次构建：初始位置为右下角
        local layoutW, layoutH, _ = getLayoutSize()
        btnLeft_ = layoutW - btnCurW_ - BTN_MARGIN
        btnTop_  = layoutH - btnCurH_ - BTN_MARGIN
        btnPositionInit_ = true
    end
    -- 后续重建保留 btnLeft_/btnTop_ 不变

    -- ── 各行计数标签 ─────────────────────────────────────
    local function makeCountLabel()
        return UI.Label {
            text          = "0",
            fontSize      = S(11),
            fontFamily    = "sans",
            fontColor     = { 255, 255, 255, 220 },
            flexGrow      = 1,
            flexShrink    = 1,   -- 允许压缩，防止行高溢出
            textAlign     = "right",
            pointerEvents = "none",
        }
    end
    infoSegLabel_  = makeCountLabel()
    warnSegLabel_  = makeCountLabel()
    errorSegLabel_ = makeCountLabel()
    engineSegLabel_ = nil  -- 不再在按钮上显示引擎计数

    -- ── INFO 行图标：emoji ℹ，13px，20×20 box
    local infoIconLabel = UI.Label {
        text          = LEVEL_CFG.INFO.icon,
        fontSize      = S(13),
        fontFamily    = "sans",
        fontColor     = LEVEL_CFG.INFO.iconColor,
        pointerEvents = "none",
        textAlign     = "center",
        height        = S(1),
        minHeight     = S(0),
    }
    local infoIconBox = UI.Panel {
        width = S(20), height = S(20), borderRadius = S(0),
        flexShrink = 0,
        backgroundColor = { 0, 0, 0, 0 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "none",
        children = { infoIconLabel },
    }

    -- ── WARNING 行图标：emoji ⚠，13px，20×20 box
    local warnIconLabel = UI.Label {
        text          = LEVEL_CFG.WARNING.icon,
        fontSize      = S(13),
        fontFamily    = "sans",
        fontColor     = LEVEL_CFG.WARNING.iconColor,
        pointerEvents = "none",
        textAlign     = "center",
        height        = S(1),
        minHeight     = S(0),
    }
    local warnIconBox = UI.Panel {
        width = S(20), height = S(20), borderRadius = S(0),
        flexShrink = 0,
        backgroundColor = { 0, 0, 0, 0 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "none",
        children = { warnIconLabel },
    }

    -- ── ERROR 行图标：红色圆圈 + "!"，20×20 borderRadius=10
    local errorIconInner = UI.Label {
        text          = "!",
        fontSize      = S(11),
        fontFamily    = "sans",
        fontColor     = { 255, 255, 255, 255 },
        pointerEvents = "none",
        textAlign     = "center",
        height        = S(1),
        minHeight     = S(0),
    }
    local errorIconBox = UI.Panel {
        width           = S(20),
        height          = S(20),
        borderRadius    = S(10),
        flexShrink      = 0,
        backgroundColor = LEVEL_CFG.ERROR.iconColor,
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
        children        = { errorIconInner },
    }

    -- ── 三行（图标 + 计数，vertically stacked）────────────
    local function makeRow(iconBox, countLabel)
        return UI.Panel {
            width             = "100%",
            height            = S(22),          -- 固定行高，3行×22=66 配合 space-evenly 居中
            flexDirection     = "row",
            alignItems        = "center",
            gap               = S(4),
            paddingHorizontal = S(8),
            pointerEvents     = "none",
            children          = { iconBox, countLabel },
        }
    end
    infoSeg_   = makeRow(infoIconBox,   infoSegLabel_)
    warnSeg_   = makeRow(warnIconBox,   warnSegLabel_)
    errorSeg_  = makeRow(errorIconBox,  errorSegLabel_)

    -- ── 日志视图容器（悬浮窗 log tab）────────────────────────
    floatingLogView_ = UI.Panel {
        width = "100%",
        flexGrow = (floatingTab_ == "log") and 1 or 0,
        height = (floatingTab_ == "log") and "auto" or 0,
        overflow = (floatingTab_ == "log") and "visible" or "hidden",
        flexDirection = "column", justifyContent = "space-evenly",
        alignItems = "stretch", pointerEvents = "none",
        visible = (floatingTab_ == "log"),
        children = { infoSeg_, warnSeg_, errorSeg_ },
    }

    -- ── 性能视图容器（悬浮窗 perf tab）───────────────────────
    -- 标签/值分离，与全屏面板风格统一
    local MINI_LBL_CLR = { 130, 125, 115, 255 }
    fpsMiniLabel_ = UI.Label {
        text = "--", fontSize = S(9), fontFamily = "sans",
        fontColor = { 80, 200, 80, 255 }, pointerEvents = "none",
    }
    ftMiniLabel_ = UI.Label {
        text = "--", fontSize = S(9), fontFamily = "sans",
        fontColor = { 220, 215, 200, 255 }, pointerEvents = "none",
    }
    local miniStatsBar = UI.Panel {
        width = "100%", height = S(14), marginTop = S(3),
        flexDirection = "row", alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = S(4),
        pointerEvents = "none",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = S(2),
                pointerEvents = "none",
                children = {
                    UI.Label { text = "FPS:", fontSize = S(9), fontFamily = "sans",
                        fontColor = MINI_LBL_CLR, pointerEvents = "none" },
                    fpsMiniLabel_,
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = S(2),
                pointerEvents = "none",
                children = {
                    UI.Label { text = "每帧:", fontSize = S(9), fontFamily = "sans",
                        fontColor = MINI_LBL_CLR, pointerEvents = "none" },
                    ftMiniLabel_,
                },
            },
        },
    }
    miniChartPanel_ = UI.Panel {
        width = "100%", flexGrow = 1,
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }
    -- monkey-patch: override Render to draw mini bar chart
    local origMiniRender = miniChartPanel_.Render
    miniChartPanel_.Render = function(self, nvg)
        if origMiniRender then origMiniRender(self, nvg) end
        local layout = self:GetAbsoluteLayout()
        if layout and #miniChartData_ > 0 then
            drawBarChart(nvg, layout.x, layout.y, layout.w, layout.h, miniChartData_, true)
        end
    end
    local showFps = (floatingTab_ == "perf" and perfSubTab_ == "fps")
    floatingPerfView_ = UI.Panel {
        width = "100%",
        flexGrow = showFps and 1 or 0,
        height = showFps and "auto" or 0,
        overflow = showFps and "visible" or "hidden",
        flexDirection = "column",
        pointerEvents = "none",
        visible = showFps,
        children = { miniStatsBar, miniChartPanel_ },
    }

    -- ── 内存悬浮视图 ──
    local MINI_SUB_FS = S(9)
    local MINI_SUB_LBL = { 120, 115, 105, 255 }
    local MINI_SUB_VAL = { 220, 215, 200, 255 }
    miniMemLabels_ = {}
    local function makeMiniKV(tbl, key, label, valColor, labelW)
        local vl = UI.Label {
            text = "--", fontSize = MINI_SUB_FS, fontFamily = "sans",
            fontColor = valColor or MINI_SUB_VAL, pointerEvents = "none",
            flexGrow = 1, textAlign = "right",
        }
        tbl[key] = vl
        return UI.Panel {
            flexDirection = "row", alignItems = "center",
            width = "100%", paddingHorizontal = S(6),
            pointerEvents = "none",
            children = {
                UI.Label {
                    text = label, fontSize = MINI_SUB_FS, fontFamily = "sans",
                    fontColor = MINI_SUB_LBL, pointerEvents = "none",
                    flexShrink = 0,
                },
                vl,
            },
        }
    end
    local showMem = (floatingTab_ == "perf" and perfSubTab_ == "mem")
    floatingMemView_ = UI.Panel {
        width = "100%",
        flexGrow = showMem and 1 or 0,
        height = showMem and "auto" or 0,
        overflow = showMem and "visible" or "hidden",
        flexDirection = "column",
        justifyContent = "center",
        pointerEvents = "none",
        visible = showMem,
        paddingVertical = S(2),
        children = {
            makeMiniKV(miniMemLabels_, "luaMem",    "Lua:",   { 80, 160, 240, 255 }),
            makeMiniKV(miniMemLabels_, "cacheMem",  "缓存:",  { 220, 170, 30, 255 }),
            makeMiniKV(miniMemLabels_, "texMem",    "纹理:",  { 140, 200, 100, 255 }),
            makeMiniKV(miniMemLabels_, "modelMem",  "模型:",  { 200, 130, 220, 255 }),
            makeMiniKV(miniMemLabels_, "totalMem",  "物理:",  { 180, 180, 180, 255 }),
        },
    }

    -- ── 网络悬浮视图 ──
    miniNetLabels_ = {}
    local showNet = (floatingTab_ == "perf" and perfSubTab_ == "net")
    floatingNetView_ = UI.Panel {
        width = "100%",
        flexGrow = showNet and 1 or 0,
        height = showNet and "auto" or 0,
        overflow = showNet and "visible" or "hidden",
        flexDirection = "column",
        justifyContent = "center",
        pointerEvents = "none",
        visible = showNet,
        paddingVertical = S(2),
        children = {
            makeMiniKV(miniNetLabels_, "bytesIn",    "接收:",  { 80, 160, 240, 255 }),
            makeMiniKV(miniNetLabels_, "bytesOut",   "发送:",  { 240, 160, 80, 255 }),
            makeMiniKV(miniNetLabels_, "packetsIn",  "包入:",  { 170, 170, 170, 255 }),
            makeMiniKV(miniNetLabels_, "packetsOut", "包出:",  { 170, 170, 170, 255 }),
            makeMiniKV(miniNetLabels_, "ping",       "延迟:",  { 80, 200, 80, 255 }),
        },
    }

    -- ── 渲染悬浮视图 ──
    miniRenderLabels_ = {}
    local showRender = (floatingTab_ == "perf" and perfSubTab_ == "render")
    floatingRenderView_ = UI.Panel {
        width = "100%",
        flexGrow = showRender and 1 or 0,
        height = showRender and "auto" or 0,
        overflow = showRender and "visible" or "hidden",
        flexDirection = "column",
        justifyContent = "center",
        pointerEvents = "none",
        visible = showRender,
        paddingVertical = S(2),
        children = {
            makeMiniKV(miniRenderLabels_, "gpuBatches",    "GPU总批次:",  { 80, 160, 240, 255 },  62),
            makeMiniKV(miniRenderLabels_, "drawCalls",     "3D批次:", { 240, 180, 80, 255 },  62),
            makeMiniKV(miniRenderLabels_, "uiDrawCalls",   "UI批次:", { 240, 180, 80, 255 },  62),
            makeMiniKV(miniRenderLabels_, "primitives",    "三角面数:",    { 80, 200, 80, 255 },  62),
            makeMiniKV(miniRenderLabels_, "gpuPrimitives", "总面数:",  { 80, 200, 80, 255 },  62),
        },
    }

    -- ── 界面(UITree)悬浮视图 ──
    uitreeMiniLabels_ = {}
    local showUITree = (floatingTab_ == "uitree")
    floatingUITreeView_ = UI.Panel {
        width = "100%",
        flexGrow = showUITree and 1 or 0,
        height = showUITree and "auto" or 0,
        overflow = showUITree and "visible" or "hidden",
        flexDirection = "column",
        justifyContent = "center",
        pointerEvents = "none",
        visible = showUITree,
        paddingVertical = S(2),
        children = {
            makeMiniKV(uitreeMiniLabels_, "nodes",   "节点:", { 80, 160, 240, 255 }, 36),
            makeMiniKV(uitreeMiniLabels_, "depth",   "深度:", { 220, 170, 30, 255 }, 36),
            makeMiniKV(uitreeMiniLabels_, "batches", "批次:", { 240, 180, 80, 255 }, 36),
            makeMiniKV(uitreeMiniLabels_, "hidden",  "隐藏:", { 180, 180, 180, 255 }, 36),
        },
    }

    -- ── 场景(Scene)悬浮视图 ──
    sceneMiniLabels_ = {}
    local showScene = (floatingTab_ == "scene")
    floatingSceneView_ = UI.Panel {
        width = "100%",
        flexGrow = showScene and 1 or 0,
        height = showScene and "auto" or 0,
        overflow = showScene and "visible" or "hidden",
        flexDirection = "column",
        justifyContent = "center",
        pointerEvents = "none",
        visible = showScene,
        paddingVertical = S(2),
        children = {
            makeMiniKV(sceneMiniLabels_, "nodes",    "节点:",  { 80, 160, 240, 255 }, 36),
            makeMiniKV(sceneMiniLabels_, "comps",    "组件:",  { 140, 200, 100, 255 }, 36),
            makeMiniKV(sceneMiniLabels_, "depth",    "深度:",  { 220, 170, 30, 255 }, 36),
            makeMiniKV(sceneMiniLabels_, "disabled", "禁用:",  { 180, 180, 180, 255 }, 36),
        },
    }

    -- ── 按钮主体（绝对定位，拖拽直接挂在自身）────────────────
    btn_ = UI.Panel {
        position        = "absolute",
        zIndex          = 20000,
        left            = btnLeft_,
        top             = btnTop_,
        width           = btnCurW_,
        height          = btnCurH_,
        borderRadius    = S(10),
        backgroundColor = BTN_DEFAULT_BG,
        flexDirection   = "column",
        justifyContent  = "space-evenly",
        alignItems      = "stretch",
        pointerEvents   = "auto",
        onTap           = function(event, self) togglePanel() end,
        onPointerDown   = function(event, self)
            if not event or not event.IsMouse or not event:IsMouse() then return end
            if event.IsPrimaryAction and not event:IsPrimaryAction() then return end
            cancelSnapTween()
            mouseDragging_     = true
            moved_             = false
            dragStartPointerX_ = tonumber(event.x) or 0
            dragStartPointerY_ = tonumber(event.y) or 0
            dragStartBtnLeft_  = btnLeft_
            dragStartBtnTop_   = btnTop_
        end,
        onPointerMove   = function(event, self)
            if not mouseDragging_ or not event or not event.IsMouse or not event:IsMouse() then return end
            local lw, lh = getLayoutSize()
            local dx = (tonumber(event.x) or 0) - dragStartPointerX_
            local dy = (tonumber(event.y) or 0) - dragStartPointerY_
            if math.abs(dx) > DRAG_THRESH or math.abs(dy) > DRAG_THRESH then moved_ = true end
            if moved_ then
                btnLeft_ = math.max(0, math.min(dragStartBtnLeft_ + dx, lw - btnCurW_))
                btnTop_  = math.max(0, math.min(dragStartBtnTop_  + dy, lh - btnCurH_))
                btn_:SetStyle({ left = btnLeft_, top = btnTop_ })
            end
        end,
        onPointerUp     = function(event, self)
            if not mouseDragging_ or not event or not event.IsMouse or not event:IsMouse() then return end
            mouseDragging_ = false
            if moved_ then
                snapToEdge()
                suppressToggleUntil_ = time:GetElapsedTime() + 0.2
            end
            moved_ = false
        end,
        onPanStart      = function(event, self)
            moved_ = false
            cancelSnapTween()
        end,
        onPanMove       = function(event, self)
            local lw, lh = getLayoutSize()
            local dx = tonumber(event.deltaX) or 0
            local dy = tonumber(event.deltaY) or 0
            if math.abs(dx) > 0 or math.abs(dy) > 0 then moved_ = true end
            btnLeft_ = math.max(0, math.min(btnLeft_ + dx, lw - btnCurW_))
            btnTop_  = math.max(0, math.min(btnTop_  + dy, lh - btnCurH_))
            btn_:SetStyle({ left = btnLeft_, top = btnTop_ })
        end,
        onPanEnd        = function(event, self)
            if moved_ then
                snapToEdge()
                suppressToggleUntil_ = time:GetElapsedTime() + 0.2
            end
            moved_ = false
        end,
        children        = {},  -- 初始为空，下方 switchFloatingTab 会设置活跃视图
    }

    -- 初始化 perfSubViewMap_ 并设置活跃视图
    perfSubViewMap_ = { fps = floatingPerfView_, mem = floatingMemView_, net = floatingNetView_, render = floatingRenderView_ }
    switchFloatingTab(floatingTab_)

    return btn_
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function LogViewerUI.Init()
    if not LogViewerUI.Enable then return end
    if initialized_ then return end
    initialized_ = true

    -- 计算缩放补偿系数（逻辑集中在 ScaleHelper 模块）
    do
        local compensate = _LVScaleHelper.Init()  -- 计算并设置 _lvCompensate
        if compensate ~= 1 then
            -- 重算文件顶层常量（它们在 require 时以 compensate=1 求值，需要刷新）
            ITEM_HEIGHT  = S(44)
            BTN_W        = S(76)
            BTN_H        = S(76)
            BTN_PERF_W   = S(76) * 2
            BTN_PERF_H   = math.floor(S(76) * 1.3)
            BTN_UITREE_W = BTN_W
            BTN_UITREE_H = BTN_H
            BTN_SCENE_W  = BTN_W
            BTN_SCENE_H  = BTN_H
            BTN_MARGIN   = S(8)
            DRAG_THRESH  = S(4)
            PANEL_HEADER_H = S(32) + S(44) + S(44)
            -- 通知子模块重算各自顶层常量
            SceneTreeView.ApplyScale()
            UITreeView.ApplyScale()
            -- 刷新依赖常量的运行时状态变量（它们在文件加载时以旧值初始化）
            btnCurW_ = BTN_W
            btnCurH_ = BTN_H
            resizeTween_.fromW = BTN_W
            resizeTween_.fromH = BTN_H
            resizeTween_.toW   = BTN_W
            resizeTween_.toH   = BTN_H
        end
    end

    LogCapture.Install()
    PerfProfiler.Init()
    -- 检测是否为多人模式（决定是否显示 前端/后端 tab）
    isNetworkMode_ = (IsNetworkMode ~= nil and IsNetworkMode() == true)
    LogCapture.Subscribe(function(entry)
        updateBtnSegments()             -- 面板关闭时也实时更新按钮比例
        updatePanelCounts()             -- 面板打开时同步更新 badge 计数（即时刷新，无需等下一帧）
        if panel_ then
            -- 不在此处直接调用 refreshList！
            -- print() → LogCapture 是同步调用链，可能在 UI 布局期间（SetData 内部）触发。
            -- 改为设 flag，下一帧 Update 回调中统一处理（Yoga 布局已稳定，无递归风险）。
            -- pendingRefresh_ 每帧只消费一次（在 handleLogViewerUpdate 中），
            -- 即使 Layout Warning 每帧触发，也只会每帧执行一次 refreshList，不会无限递归。
            pendingRefresh_ = true
        end
    end)
    -- 创建独立 ScriptObject，用于订阅 "Update" 事件（不占用全局单槽）
    if not eventNode_ then
        eventNode_ = Node()
        eventSO_   = eventNode_:CreateScriptObject("LuaScriptObject")
    end
end

function LogViewerUI.Mount()
    if not LogViewerUI.Enable then return end
    if not initialized_ then return end
    local root = UI.GetRoot()
    if not root then return end

    -- ── 全屏面板相关引用重置（面板每次关闭时已清理，此处确保干净）──
    panel_ = nil; vlist_ = nil
    copyToast_ = nil; copyToastTimer_ = 0
    infoBadge_ = nil; warnBadge_ = nil; errorBadge_ = nil; engineBadge_ = nil
    infoCount_ = nil; warnCount_ = nil; errorCount_ = nil; engineCount_ = nil
    accountInfoLabel_ = nil; lastAccountInfoText_ = nil
    searchField_ = nil; clearFilterXBtn_ = nil
    uitreeSearchField_ = nil; uitreeClearXBtn_ = nil; uitreeFilterContent_ = nil
    sceneSearchField_ = nil; sceneClearXBtn_ = nil; sceneFilterContent_ = nil
    scrollDownBtn_ = nil; scrollDownVisible_ = false
    clientTab_ = nil; serverTab_ = nil
    perfContent_ = nil; logContent_ = nil
    uitreeContent_ = nil; sceneContent_ = nil
    panelPerfTab_ = nil; panelLogTab_ = nil
    panelUITreeTab_ = nil; panelSceneTab_ = nil
    UITreeView.Destroy(); SceneTreeView.Destroy()
    perfValLabels_ = {}; perfMemBars_ = {}
    perfNetSection_ = nil
    fullChartPanel_ = nil; fullChartData_ = {}
    filterRow_ = nil; filterContent_ = nil; perfSubTabContent_ = nil; uitreeFilterContent_ = nil; sceneFilterContent_ = nil; envTabGroup_ = nil; perfTimer_ = 0
    pendingScrollFrames_ = 0; pendingRefresh_ = false; pendingForceRender_ = false

    -- ── 悬浮窗按钮引用重置（每次重建，但保留 btnLeft_/btnTop_/btnCurW_/btnCurH_/floatingTab_ 等状态）──
    logBtnRoot_ = nil; btn_ = nil
    infoSeg_ = nil; warnSeg_ = nil; errorSeg_ = nil
    infoSegLabel_ = nil; warnSegLabel_ = nil; errorSegLabel_ = nil; engineSegLabel_ = nil
    floatingPerfView_ = nil; floatingLogView_ = nil
    floatingUITreeView_ = nil; floatingSceneView_ = nil
    floatingMemView_ = nil; floatingNetView_ = nil; floatingRenderView_ = nil; floatingPerfContainer_ = nil
    miniMemLabels_ = {}; miniNetLabels_ = {}; miniRenderLabels_ = {}
    uitreeMiniLabels_ = {}; sceneMiniLabels_ = {}
    perfSubTabBtns_ = {}
    fpsMiniLabel_ = nil; ftMiniLabel_ = nil
    miniChartPanel_ = nil
    mouseDragging_ = false; moved_ = false
    suppressToggleUntil_ = 0
    snapTween_.active = false; snapTween_.elapsed = 0
    resizeTween_.active = false; resizeTween_.elapsed = 0

    logBtnRoot_ = buildBtnWidget()
    root:AddChild(logBtnRoot_)
    updateBtnSegments()  -- 同步按钮色段比例

    -- Mount 后延迟 30 帧等游戏 UI 稳定，再启动两阶段校准（隐藏→测基线→显示→测总量）
    floatingCalibState_ = FCALIB_MOUNT_DELAY
    floatingCalibCountdown_ = 30

    -- 订阅 Update 事件（性能数据需要持续刷新，即使面板未打开）
    if not updateActive_ and eventSO_ then
        eventSO_:SubscribeToEvent("Update", function(self, eventType, eventData)
            local dt = eventData["TimeStep"]:GetFloat()
            handleLogViewerUpdate(dt)
        end)
        updateActive_ = true
    end

    -- Mount 重建了 UI，同步已有的账号信息（currentUserName_ 跨 Mount 保留）
    updateAccountInfoLabel()
end

function LogViewerUI.Show()
    if panel_ then return end
    -- 面板打开前采样 UI DC 基线（此时面板不存在，totalUIBatches 不含 LogViewer）
    -- 取消浮窗校准（面板打开后 DC 环境又变了，等面板校准完再说）
    cancelFloatingRecalib()
    -- 每次打开都记录基线，启动连续追踪（selfDC = 当前DC - 基线，每帧更新）
    preOpenBaseline_ = PerfProfiler.GetTotalUIBatches()
    PerfProfiler.SetSelfDCOffset(0)
    panelCalibTracking_ = true
    requestCurrentUserName()
    startUserNamePrefetch()
    createLogPanel()
    -- 如果当前 tab 是界面/场景，Create() 只建了容器，需要主动 Rebuild 填充树
    if panelTab_ == "uitree" then UITreeView.Rebuild()
    elseif panelTab_ == "scene" then SceneTreeView.Rebuild() end
    updateAccountInfoLabel()
    updateBadgeStyles()  -- 初始化 badge 选中状态（默认全选中）
    updatePerfDisplay()  -- 初始化性能数据
    perfTimer_ = 0       -- 重置性能刷新计时器
    refreshList("bottom")  -- 立即用 getVListHeight() 滚到底部
    -- 连续 5 帧强制滚到底部，确保 Yoga 布局稳定后位置正确
    -- 第1帧 Yoga 可能未完成，第2-5帧会覆盖任何意外重置
    pendingScrollFrames_ = 5
end

function LogViewerUI.Hide()
    if not panel_ then return end
    -- 停止连续追踪
    panelCalibTracking_ = false
    local root = UI.GetRoot()
    if root then
        root:RemoveChild(panel_)
        -- scrollDownBtn_ 挂在 root，需单独移除
        if scrollDownBtn_ then root:RemoveChild(scrollDownBtn_) end
    end
    panel_ = nil; vlist_ = nil; detailCard_ = nil
    copyToast_ = nil; copyToastTimer_ = 0
    infoBadge_ = nil; warnBadge_ = nil; errorBadge_ = nil; engineBadge_ = nil
    infoCount_ = nil; warnCount_ = nil; errorCount_ = nil; engineCount_ = nil
    accountInfoLabel_ = nil; lastAccountInfoText_ = nil
    searchField_ = nil; clearFilterXBtn_ = nil
    uitreeSearchField_ = nil; uitreeClearXBtn_ = nil; uitreeFilterContent_ = nil
    sceneSearchField_ = nil; sceneClearXBtn_ = nil; sceneFilterContent_ = nil
    scrollDownBtn_ = nil; scrollDownVisible_ = false
    clientTab_ = nil; serverTab_ = nil
    -- 性能面板引用清理
    perfContent_ = nil; logContent_ = nil
    uitreeContent_ = nil; sceneContent_ = nil
    panelPerfTab_ = nil; panelLogTab_ = nil
    panelUITreeTab_ = nil; panelSceneTab_ = nil
    UITreeView.Destroy(); SceneTreeView.Destroy()
    perfValLabels_ = {}; perfMemBars_ = {}
    perfNetSection_ = nil; perfSubTabBtns_ = {}
    fullChartPanel_ = nil; fullChartData_ = {}
    filterRow_ = nil; filterContent_ = nil; perfSubTabContent_ = nil; uitreeFilterContent_ = nil; sceneFilterContent_ = nil; envTabGroup_ = nil
    -- 面板关闭后重置 selfDC
    PerfProfiler.SetSelfDCOffset(0)
    -- 立即完成正在进行的浮窗尺寸动画（确保浮窗到达目标尺寸和 tab 状态）
    if resizeTween_.active then
        resizeTween_.active = false
        btnCurW_ = resizeTween_.toW
        btnCurH_ = resizeTween_.toH
        if btn_ then
            btn_:SetStyle({ width = btnCurW_, height = btnCurH_ })
        end
        if resizeTween_.onComplete then
            resizeTween_.onComplete()  -- 完成 tab 切换（switchFloatingTab → triggerFloatingRecalib）
            resizeTween_.onComplete = nil
        end
    end
    -- 面板期间浮窗可能切换了 tab/子视图，其 recalib 被 panelCalibTracking_ 阻止了，现在补做
    triggerFloatingRecalib()
    -- 注意：不在 Hide 中 UnsubscribeFromEvent("Update")
    -- 因为悬浮窗的性能数据需要持续刷新（在 Mount 中订阅，仅在下次 Mount 时重置）
    pendingScrollFrames_ = 0; pendingRefresh_ = false; pendingForceRender_ = false
end

function LogViewerUI.SetCurrentUserId(userId)
    local normalized = math.floor(tonumber(userId) or 0)
    if currentUserId_ ~= normalized then
        currentUserName_ = ""
        userNameRequestInFlight_ = false
        userNameFailCount_ = 0
    end
    currentUserId_ = normalized
    updateAccountInfoLabel()
end

function LogViewerUI.SetCurrentUserName(name)
    local normalized = trimString(name)
    if normalized ~= "" then
        currentUserName_ = normalized
        stopUserNamePrefetch()
        updateAccountInfoLabel()
    end
end

return LogViewerUI
