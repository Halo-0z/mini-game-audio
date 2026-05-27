-- ============================================================================
-- 服务端日志广播模块 (LogBroadcast)
-- 将服务端的 LogCapture 日志实时转发给所有已连接的客户端，
-- 客户端通过 LogCapture.InstallServerLogReceiver() 接收并显示。
--
-- ⚠️ 仅服务端使用：
--   - 在 Server 入口中调用 LogBroadcast.Install()
--   - 自动检测 IsServerMode()，非服务端环境跳过
--   - 自包含在 LogViewer/ 目录内，无需修改业务代码
--
-- 使用方式：
--   local LogBroadcast = require("LogViewer.LogBroadcast")
--   LogBroadcast.Install()   -- 在 Shared.RegisterEvents() 之后调用
--
-- 工作原理：
--   1. 调用 LogCapture.Install() 确保服务端日志被捕获
--   2. 订阅 LogCapture 的新条目事件
--   3. 通过 SendRemoteEvent 广播给所有客户端
--   4. 客户端 LogCapture.InstallServerLogReceiver() 接收并标记 source="server"
-- ============================================================================

---@diagnostic disable: undefined-global

local LogCapture = require("LogViewer.LogCapture")

local LogBroadcast = {}

--- 昵称请求/响应远程事件名（客户端 → 服务端 → 客户端）
LogBroadcast.NICKNAME_REQUEST_EVENT  = "LogViewerNicknameReq"
LogBroadcast.NICKNAME_RESPONSE_EVENT = "LogViewerNicknameRes"

local installed_ = false

--- 广播一条日志给所有已连接的客户端
---@param level string 日志级别 (INFO/WARN/ERROR/NET)
---@param msg string 日志内容
---@param source string|nil 日志来源 ("engine" = 引擎日志, nil = 用户代码)
local function broadcastToClients(level, msg, source)
    if not network or not network.serverRunning then return end

    local connections = network:GetClientConnections()
    if not connections or #connections == 0 then return end

    local data = VariantMap()
    data["Level"]   = Variant(level)
    data["Message"] = Variant(msg)
    if source and source ~= "" then
        data["Source"] = Variant(source)
    end

    for _, conn in ipairs(connections) do
        if conn then
            pcall(function()
                conn:SendRemoteEvent(LogCapture.SERVER_LOG_EVENT, true, data)
            end)
        end
    end
end

--- 安装服务端日志广播
-- 在 Server 入口的 Shared.RegisterEvents() 之后调用
-- 非服务端环境自动跳过，多次调用无副作用
function LogBroadcast.Install()
    if installed_ then return end

    -- 仅服务端启用
    if not IsServerMode or not IsServerMode() then return end

    installed_ = true

    -- 确保服务端 LogCapture 已安装（print hook + LogMessage）
    LogCapture.Install()

    -- 注册远程事件（服务端侧也需注册，否则 SendRemoteEvent 会被引擎忽略）
    network:RegisterRemoteEvent(LogCapture.SERVER_LOG_EVENT)

    -- 订阅 LogCapture 的所有新条目，广播给客户端（含 source 字段）
    LogCapture.Subscribe(function(entry)
        broadcastToClients(entry.level or "INFO", entry.msg or "", entry.source)
    end)

    -- ── 昵称查询服务（客户端 LogViewerUI 请求当前用户昵称）──────────
    network:RegisterRemoteEvent(LogBroadcast.NICKNAME_REQUEST_EVENT)
    network:RegisterRemoteEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT)

    SubscribeToEvent(LogBroadcast.NICKNAME_REQUEST_EVENT, function(_, evtData)
        local connection = evtData["Connection"]:GetPtr("Connection")
        if not connection then return end

        local reqId = evtData["ReqId"]:GetString()

        -- 获取连接对应的 userId
        local uid = 0
        pcall(function()
            if connection.identity then
                local v = connection.identity["user_id"]
                if v then uid = v:GetInt64() end
            end
        end)
        if uid == 0 then
            pcall(function()
                if type(SERVER_PLAYER_AUTH_INFOS) == "table" then
                    for _, info in pairs(SERVER_PLAYER_AUTH_INFOS) do
                        if info.connection == connection then
                            uid = tonumber(info.userId) or 0
                            break
                        end
                    end
                end
            end)
        end

        -- 构造响应
        local respData = VariantMap()
        respData["ReqId"] = Variant(reqId)

        if uid == 0 or type(GetUserNickname) ~= "function" then
            respData["Nickname"] = Variant("")
            connection:SendRemoteEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT, true, respData)
            return
        end

        GetUserNickname({
            userIds = { uid },
            onSuccess = function(nicknames)
                local nick = ""
                if type(nicknames) == "table" and nicknames[1] then
                    nick = nicknames[1].nickname or ""
                end
                respData["Nickname"] = Variant(nick)
                connection:SendRemoteEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT, true, respData)
            end,
            onError = function()
                respData["Nickname"] = Variant("")
                connection:SendRemoteEvent(LogBroadcast.NICKNAME_RESPONSE_EVENT, true, respData)
            end,
        })
    end)
end

return LogBroadcast
