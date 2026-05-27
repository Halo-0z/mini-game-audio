-- ============================================================================
-- 日志捕获模块 (LogCapture)
-- 拦截全局 print() + 订阅引擎 LogMessage 事件，将所有日志存入环形缓冲区，
-- 供 LogViewerUI（客户端）或 LogBroadcast（服务端）读取。
--
-- ⚠️ 前后端通用模块：
--   - 客户端：Install() + InstallServerLogReceiver()（接收服务端日志）
--   - 服务端：Install() 即可（LogBroadcast 负责广播）
--   - LogViewerUI 仅客户端使用，本模块不依赖它
--
-- 捕获通道：
--   1. print() hook — 用户代码的 print 输出
--   2. LogMessage 事件 — 引擎内部日志（log:Write、运行时错误、资源警告等）
--   3. ServerLog 远程事件 — 服务端日志转发（多人客户端模式下自动启用）
--
-- 使用方式：
--   local LogCapture = require("LogViewer.LogCapture")
--   LogCapture.Subscribe(function(entry) ... end)
--   LogCapture.GetEntries()  --> { {id, time, level, msg, source}, ... }
--
-- 公共 API（前后端均可调用，自动输出到原生日志）：
--   LogCapture.Info(msg)   -- INFO 级别
--   LogCapture.Warn(msg)   -- WARN 级别
--   LogCapture.Error(msg)  -- ERROR 级别
--   LogCapture.Net(msg)    -- NET 级别（网络请求/响应）
--   LogCapture.Log(level, msg)  -- 自定义级别
--
-- 注意：仅在 LogViewerUI.Enable = true 时调用 LogCapture.Install()
-- ============================================================================

local LogCapture = {}

local MAX_ENTRIES = 500  -- 最大保留条目数（环形缓冲）

--- 服务端日志远程事件名（自包含，无需依赖 Shared）
LogCapture.SERVER_LOG_EVENT = "ServerLog"

local entries_   = {}   -- { {id, time, level, msg, source}, ... }
local listeners_ = {}   -- 新条目监听器列表
local counter_   = 0    -- 全局递增 id

-- ============================================================================
-- 时间格式化
-- ============================================================================

local function formatTime()
    return os.date("%H:%M:%S")
end

-- ============================================================================
-- 核心：追加一条日志
-- ============================================================================

local function appendEntry(level, msg, source)
    counter_ = counter_ + 1
    local entry = {
        id    = counter_,
        time  = formatTime(),
        level = level,
        msg   = tostring(msg),
        source = source,  -- "engine" = 引擎 LogMessage, "server" = 服务端转发, nil = 用户代码
    }

    -- 环形缓冲：超过上限则删最旧
    if #entries_ >= MAX_ENTRIES then
        table.remove(entries_, 1)
    end
    table.insert(entries_, entry)

    -- 通知所有监听器
    for i = 1, #listeners_ do
        pcall(listeners_[i], entry)
    end
end

-- ============================================================================
-- 安装状态 & 去重标记
-- ============================================================================

local installed_ = false

-- 去重：print() hook 记录最近一次捕获的消息文本，
-- LogMessage handler 通过比较消息内容决定是否跳过（仅跳过内容完全相同的那条）。
-- 这样做的好处：print() 期间引擎附带产生的其他 LogMessage 不会被误杀，
-- 可以正确标记为 source="engine"。
local lastPrintMsg_ = nil       -- print hook 最近捕获的消息
local insidePrintHook_ = false  -- print hook 执行中标记（用于 rawOutput 去重）
local insideRawOutput_ = false  -- rawOutput 执行中标记（blanket block，消息已由 API 记录）

-- 原始 print 引用（Install 时保存，供 API 函数输出到原生日志）
local origPrint_ = nil

--- 供内部 print hook 使用
function LogCapture._setInsidePrintHook(v)
    insidePrintHook_ = v
end

--- LogCapture level → 引擎 LOG_* 常量映射
local LEVEL_MAP = {
    INFO  = LOG_INFO,
    WARN  = LOG_WARNING,
    ERROR = LOG_ERROR,
    NET   = LOG_INFO,
}

--- 输出到引擎日志文件（engine.log），不触发 print hook 的重复捕获。
--- 注意：引擎默认日志级别为 WARNING，INFO 级别不会写入 engine.log。
--- 消息已由调用方通过 appendEntry 记录，此处仅做原生输出，
--- 期间所有 LogMessage 均为回声，用 insideRawOutput_ blanket block。
local function rawOutput(level, msg)
    insideRawOutput_ = true
    local logLevel = LEVEL_MAP[level] or LOG_INFO
    log:Write(logLevel, msg)
    insideRawOutput_ = false
end

-- ============================================================================
-- 不捕获的消息前缀列表
-- ============================================================================

local IGNORED_PREFIXES = {
}

local function shouldIgnore(msg)
    for _, prefix in ipairs(IGNORED_PREFIXES) do
        if string.find(msg, prefix, 1, true) then return true end
    end
    return false
end

-- ============================================================================
-- 公共 API — 手动写日志（前后端通用）
-- 同时输出到原生日志（保留控制台/日志文件可见性）
-- ============================================================================

function LogCapture.Log(level, msg)
    local lvl = level or "INFO"
    local m = tostring(msg)
    if shouldIgnore(m) then return end
    appendEntry(lvl, m)
    rawOutput(lvl, m)
end

function LogCapture.Info(msg)
    local m = tostring(msg)
    if shouldIgnore(m) then return end
    appendEntry("INFO", m)
    rawOutput("INFO", m)
end

function LogCapture.Warn(msg)
    local m = tostring(msg)
    if shouldIgnore(m) then return end
    appendEntry("WARN", m)
    rawOutput("WARN", m)
end

function LogCapture.Error(msg)
    local m = tostring(msg)
    if shouldIgnore(m) then return end
    appendEntry("ERROR", m)
    rawOutput("ERROR", m)
end

function LogCapture.Net(msg)
    local m = tostring(msg)
    if shouldIgnore(m) then return end
    appendEntry("NET", m)
    rawOutput("NET", m)
end

-- ============================================================================
-- 订阅/取消订阅新日志
-- ============================================================================

function LogCapture.Subscribe(fn)
    table.insert(listeners_, fn)
end

function LogCapture.Unsubscribe(fn)
    for i = #listeners_, 1, -1 do
        if listeners_[i] == fn then
            table.remove(listeners_, i)
            return
        end
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 返回所有日志条目（直接引用，勿外部修改）
function LogCapture.GetEntries()
    return entries_
end

function LogCapture.GetCount()
    return #entries_
end

function LogCapture.Clear()
    entries_ = {}
end

--- 是否已安装（print hook 已接管）
--- 服务端业务代码可通过此方法判断是否输出详细日志（如 JSON 内容），节省未开启时的性能开销
function LogCapture.IsInstalled()
    return installed_
end

-- ============================================================================
-- 安装：接管全局 print()，所有 print 输出也进入日志
-- ⚠️ 前后端均可调用，多次调用无副作用
-- ============================================================================

function LogCapture.Install()
    if installed_ then return end
    installed_ = true

    origPrint_ = print

    -- 覆盖全局 print
    print = function(...)
        local parts = {}
        local n = select("#", ...)
        for i = 1, n do
            parts[i] = tostring(select(i, ...))
        end
        local msg = table.concat(parts, "\t")
        lastPrintMsg_ = msg    -- 记录本次 print 消息，供 LogMessage handler 去重
        insidePrintHook_ = true
        origPrint_(msg)        -- 保留原始输出到 user_script.log
        insidePrintHook_ = false
        if shouldIgnore(msg) then return end
        appendEntry("INFO", msg)
        -- 同时写入 engine.log（insideRawOutput_ 阻止 LogMessage handler 重复捕获）
        insideRawOutput_ = true
        log:Write(LOG_INFO, msg)
        insideRawOutput_ = false
        lastPrintMsg_ = nil    -- 清除，避免影响后续无关的 LogMessage
    end

    -- 订阅 LogMessage 事件，统一捕获引擎级日志（前后端均有此事件）
    LogCapture.InstallLogHook()

    -- 多人客户端模式下订阅服务端日志远程事件（服务端/单机自动跳过）
    LogCapture.InstallServerLogReceiver()
end

-- ============================================================================
-- 订阅引擎 LogMessage 事件，统一捕获所有引擎级日志
-- 覆盖范围：log:Write()、引擎内部日志、Lua 运行时错误等
-- 与 print() hook 通过 insidePrintHook_ 标记去重
-- ⚠️ 前后端均可调用
-- ============================================================================

local logHookInstalled_ = false

function LogCapture.InstallLogHook()
    if logHookInstalled_ then return end
    logHookInstalled_ = true

    SubscribeToEvent("LogMessage", function(eventType, eventData)
        local level = eventData:GetInt("Level")
        local msg   = eventData:GetString("Message")

        if shouldIgnore(msg) then return end

        -- rawOutput 期间完全跳过（消息已由 Net/Info/Warn/Error/Log 记录）
        if insideRawOutput_ then return end

        -- print hook 期间：仅跳过与 print 消息完全相同的回声，
        -- 其他引擎日志保留并标记 source="engine"
        if insidePrintHook_ and lastPrintMsg_ and msg == lastPrintMsg_ then
            return
        end

        if     level == LOG_ERROR   then appendEntry("ERROR", msg, "engine")
        elseif level == LOG_WARNING then appendEntry("WARN",  msg, "engine")
        elseif level == LOG_INFO    then appendEntry("INFO",  msg, "engine")
        elseif level == LOG_DEBUG   then appendEntry("INFO",  "[D] " .. msg, "engine")
        end
    end)
end

-- ============================================================================
-- 服务端日志接收（仅客户端侧）
-- 多人客户端模式下自动订阅 ServerLog 远程事件，将服务端日志写入本地 LogCapture
-- ⚠️ 服务端/单机模式自动跳过，不会报错
-- ============================================================================

local serverLogInstalled_ = false

function LogCapture.InstallServerLogReceiver()
    if serverLogInstalled_ then return end

    -- 仅在多人客户端模式下启用
    if not IsNetworkMode or not IsNetworkMode() then return end
    if IsServerMode and IsServerMode() then return end  -- 服务端自身不接收

    serverLogInstalled_ = true

    -- 使用自包含的事件名，无需依赖 Shared
    network:RegisterRemoteEvent(LogCapture.SERVER_LOG_EVENT)

    SubscribeToEvent(LogCapture.SERVER_LOG_EVENT, function(eventType, eventData)
        local level  = eventData:GetString("Level")
        local msg    = eventData:GetString("Message")
        local source = eventData:GetString("Source")  -- 服务端原始 source（"engine" 或 ""）

        if level == "" then level = "INFO" end
        if shouldIgnore(msg) then return end

        -- 组合标记：保留服务端来源 + 原始 source 类型
        -- "server_engine" = 服务端引擎日志（灰色显示）
        -- "server"        = 服务端用户代码日志（按级别颜色显示）
        local combinedSource = "server"
        if source == "engine" then
            combinedSource = "server_engine"
        end

        appendEntry(level, msg, combinedSource)
    end)
end

return LogCapture
