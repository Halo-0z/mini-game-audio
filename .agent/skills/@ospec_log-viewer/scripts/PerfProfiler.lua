-- ============================================================================
-- 性能数据采集模块 (PerfProfiler)
-- 功能：
--   1. 每帧记录帧时间到环形缓冲区
--   2. 提供统计数据（FPS、DrawCall、内存等）
--   3. 提供图表数据（分组取 max，供柱状图使用）
--   4. GC Collect / Clean Cache 操作
-- ============================================================================

---@diagnostic disable: undefined-global

local PerfProfiler = {}

-- ============================================================================
-- 常量
-- ============================================================================

local BUFFER_SIZE = 600 -- ~10 秒 @60fps

-- ============================================================================
-- 私有状态
-- ============================================================================

local initialized_ = false
local eventNode_ = nil
local eventSO_ = nil

-- 环形缓冲区
local frameTimes_ = {} -- 存储帧时间（ms）
local writeIdx_ = 1
local sampleCount_ = 0

-- UI DrawCall 采样（用于排除调试面板自身的 drawcall）
local afterRenderBatches_ = 0   -- PostRenderUpdate 时的 GPU batch（3D 完毕, UI 未画）
local endFrameBatches_    = 0   -- EndFrame 时的 GPU batch（全部渲染完毕）
local prevUIBatches_      = 0   -- 上一帧的纯 UI batch 数
local selfDCOffset_       = 0   -- 外部设置的"调试面板自身 DC"偏移量

-- ============================================================================
-- 私有方法
-- ============================================================================

local function recordFrame(dt)
    local ms = dt * 1000
    frameTimes_[writeIdx_] = ms
    writeIdx_ = writeIdx_ + 1
    if writeIdx_ > BUFFER_SIZE then
        writeIdx_ = 1
    end
    if sampleCount_ < BUFFER_SIZE then
        sampleCount_ = sampleCount_ + 1
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化：订阅 Update 事件，每帧记录帧时间
function PerfProfiler.Init()
    if initialized_ then return end
    initialized_ = true

    -- 预填充缓冲区
    for i = 1, BUFFER_SIZE do
        frameTimes_[i] = 0
    end

    -- 创建独立 ScriptObject 订阅 Update（不占用全局插槽）
    eventNode_ = Node()
    eventSO_ = eventNode_:CreateScriptObject("LuaScriptObject")
    eventSO_:SubscribeToEvent("Update", function(self, eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        recordFrame(dt)
    end)

    -- PostRenderUpdate: 3D 渲染已完成，UI 还没画
    eventSO_:SubscribeToEvent("PostRenderUpdate", function(self, eventType, eventData)
        pcall(function() afterRenderBatches_ = graphics:GetNumBatches() end)
    end)

    -- EndFrame: 当前帧全部渲染完毕（含 UI）
    eventSO_:SubscribeToEvent("EndFrame", function(self, eventType, eventData)
        pcall(function() endFrameBatches_ = graphics:GetNumBatches() end)
        prevUIBatches_ = math.max(0, endFrameBatches_ - afterRenderBatches_)
    end)
end

--- 获取实时统计数据（所有引擎可用的性能指标）
---@return table 完整性能数据
function PerfProfiler.GetStats()
    local stats = {
        -- 帧率
        fps         = time:GetFramesPerSecond(),
        frameNumber = time:GetFrameNumber(),
        timeStep    = time:GetTimeStep(),
        -- 渲染
        drawCalls   = renderer:GetNumBatches(),
        primitives  = renderer:GetNumPrimitives(),
        views       = renderer:GetNumViews(),
        geometries  = renderer:GetNumGeometries(true),
        lights      = renderer:GetNumLights(true),
        shadowMaps  = renderer:GetNumShadowMaps(true),
        occluders   = renderer:GetNumOccluders(true),
        -- 内存
        cacheMemMB  = cache:GetTotalMemoryUse() / (1024 * 1024),
        luaMemMB    = collectgarbage("count") / 1024,
        -- 屏幕
        screenW     = graphics:GetWidth(),
        screenH     = graphics:GetHeight(),
        dpr         = graphics:GetDPR(),
        multiSample = graphics:GetMultiSample(),
    }
    -- 安全获取可能不可用的指标
    pcall(function() stats.elapsedTime = time:GetElapsedTime() end)
    pcall(function() stats.maxFps = engine:GetMaxFps() end)
    pcall(function() stats.refreshRate = graphics:GetRefreshRate() end)
    pcall(function() stats.texMemMB = cache:GetMemoryUse("Texture2D") / (1024 * 1024) end)
    pcall(function() stats.modelMemMB = cache:GetMemoryUse("Model") / (1024 * 1024) end)
    pcall(function() stats.soundMemMB = cache:GetMemoryUse("Sound") / (1024 * 1024) end)
    -- GPU 批次（含 UI DrawCall）
    pcall(function() stats.gpuBatches = graphics:GetNumBatches() end)
    pcall(function() stats.gpuPrimitives = graphics:GetNumPrimitives() end)
    -- 渲染 API / VSync
    pcall(function() stats.apiName = graphics:GetApiName() end)
    pcall(function() stats.vsync = graphics:GetVSync() end)
    -- 定时器精度
    pcall(function() stats.timerPeriod = time:GetTimerPeriod() end)
    pcall(function() stats.minFps = engine:GetMinFps() end)
    -- 系统物理内存
    pcall(function() stats.totalMemoryMB = GetTotalMemory() / (1024 * 1024) end)
    -- 桌面分辨率 / DPI
    pcall(function()
        local res = graphics:GetDesktopResolution(0)
        stats.desktopW = res.x
        stats.desktopH = res.y
    end)
    pcall(function()
        local dpi = graphics:GetDisplayDPI(0)
        stats.displayDPI = dpi
    end)
    -- 系统信息
    pcall(function() stats.platform = GetPlatform() end)
    pcall(function() stats.osVersion = GetOSVersion() end)
    pcall(function() stats.cpuPhysical = GetNumPhysicalCPUs() end)
    pcall(function() stats.cpuLogical = GetNumLogicalCPUs() end)
    pcall(function() stats.hostName = GetHostName() end)
    pcall(function() stats.loginName = GetLoginName() end)
    -- 渲染设置
    pcall(function() stats.dynamicInstancing = renderer:GetDynamicInstancing() end)
    pcall(function() stats.drawShadows = renderer:GetDrawShadows() end)
    pcall(function() stats.shadowMapSize = renderer:GetShadowMapSize() end)
    pcall(function() stats.hdrRendering = renderer:GetHDRRendering() end)
    pcall(function() stats.specularLighting = renderer:GetSpecularLighting() end)
    pcall(function() stats.textureQuality = renderer:GetTextureQuality() end)
    pcall(function() stats.textureAnisotropy = renderer:GetTextureAnisotropy() end)
    pcall(function() stats.maxBones = graphics:GetMaxBones() end)
    pcall(function() stats.instancingSupport = graphics:GetInstancingSupport() end)
    pcall(function() stats.srgb = graphics:GetSRGB() end)
    pcall(function() stats.tripleBuffer = graphics:GetTripleBuffer() end)
    -- 屏幕设置
    pcall(function() stats.fullscreen = graphics:GetFullscreen() end)
    pcall(function() stats.monitorCount = graphics:GetMonitorCount() end)
    -- 内存
    pcall(function() stats.bgLoadResources = cache:GetNumBackgroundLoadResources() end)
    -- 引擎设置
    pcall(function() stats.maxInactiveFps = engine:GetMaxInactiveFps() end)
    pcall(function() stats.timeStepSmoothing = engine:GetTimeStepSmoothing() end)
    pcall(function() stats.pauseMinimized = engine:GetPauseMinimized() end)
    -- 场景
    pcall(function() if scene_ then stats.timeScale = scene_:GetTimeScale() end end)
    -- 音频
    pcall(function() stats.audioMixRate = audio:GetMixRate() end)
    pcall(function() stats.audioStereo = audio:IsStereo() end)
    -- 网络（多人模式下可用）
    if network then
        local conn = nil
        pcall(function() conn = network:GetServerConnection() end)
        if conn then
            stats.ping         = math.floor((conn:GetRoundTripTime() or 0) * 1000)
            stats.bytesIn      = conn:GetBytesInPerSec()
            stats.bytesOut     = conn:GetBytesOutPerSec()
            stats.packetsIn    = conn:GetPacketsInPerSec()
            stats.packetsOut   = conn:GetPacketsOutPerSec()
        end
    end
    -- UI DrawCall 采样数据（排除调试面板用）
    stats.totalUIBatches = prevUIBatches_
    stats.selfDCOffset   = selfDCOffset_
    return stats
end

--- 设置"调试面板自身 DC"偏移量（由 LogViewerUI 在面板显隐时采样设置）
---@param offset number
function PerfProfiler.SetSelfDCOffset(offset)
    selfDCOffset_ = offset or 0
end

--- 获取当前"调试面板自身 DC"偏移量
---@return number
function PerfProfiler.GetSelfDCOffset()
    return selfDCOffset_
end

--- 获取当前帧纯 UI batch 数（含所有 UI，包括调试面板）
--- 注意：NanoVG UI 不走传统 EndFrame-PostRenderUpdate 差值，
--- 改用 graphics:GetNumBatches() - renderer:GetNumBatches() 计算
---@return number
function PerfProfiler.GetTotalUIBatches()
    local gpuB, rendB = 0, 0
    pcall(function() gpuB = graphics:GetNumBatches() end)
    pcall(function() rendB = renderer:GetNumBatches() end)
    return math.max(0, gpuB - rendB)
end

--- 获取图表柱子数据
--- 将缓冲区最近的数据分组，每组取 max 值
---@param barCount number 需要的柱子数量
---@return table 帧时间数组（ms），长度 = barCount
function PerfProfiler.GetChartData(barCount)
    local result = {}
    if sampleCount_ == 0 then
        for i = 1, barCount do result[i] = 0 end
        return result
    end

    -- 计算每组包含多少样本
    local totalSamples = math.min(sampleCount_, BUFFER_SIZE)
    local samplesPerBar = math.max(1, math.floor(totalSamples / barCount))
    local usedSamples = samplesPerBar * barCount

    -- 从最新样本向前读取
    local readStart = writeIdx_ - usedSamples
    if readStart < 1 then readStart = readStart + BUFFER_SIZE end

    for bar = 1, barCount do
        local maxVal = 0
        for s = 1, samplesPerBar do
            local idx = readStart + (bar - 1) * samplesPerBar + (s - 1)
            if idx > BUFFER_SIZE then idx = idx - BUFFER_SIZE end
            if idx < 1 then idx = idx + BUFFER_SIZE end
            local v = frameTimes_[idx] or 0
            if v > maxVal then maxVal = v end
        end
        result[bar] = maxVal
    end

    return result
end

--- 强制 GC
function PerfProfiler.CollectGC()
    collectgarbage("collect")
end

--- 清理资源缓存
function PerfProfiler.CleanCache()
    cache:ReleaseAllResources(true)
end

--- 停止性能采集（取消所有事件订阅，释放 ScriptObject）
--- 调用后可再次 Init() 重新启动
function PerfProfiler.Shutdown()
    if not initialized_ then return end
    -- 取消所有事件订阅
    if eventSO_ then
        eventSO_:UnsubscribeFromAllEvents()
    end
    -- 释放节点（ScriptObject 随之销毁）
    if eventNode_ then
        eventNode_:Remove()
    end
    eventNode_ = nil
    eventSO_ = nil
    initialized_ = false
    -- 重置采样状态
    frameTimes_ = {}
    writeIdx_ = 1
    sampleCount_ = 0
    afterRenderBatches_ = 0
    endFrameBatches_ = 0
    prevUIBatches_ = 0
    selfDCOffset_ = 0
end

--- 是否已初始化
---@return boolean
function PerfProfiler.IsInitialized()
    return initialized_
end

return PerfProfiler
