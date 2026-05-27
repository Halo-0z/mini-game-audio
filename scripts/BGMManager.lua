-- BGMManager.lua
-- 动态BGM系统：单 SoundSource，Play/Stop 直接切换
-- Boss BGM 在波次到来前20秒提前播放

local GameState = require("GameState")
local Config    = require("Config")

local BGMManager = {}

-- ===================== 音乐文件路径 =====================
local TRACKS = {
    DAY    = "audio/music_1779640829255.ogg",  -- 白天基地运营：废土黎明
    NIGHT  = "audio/music_1779640915376.ogg",  -- 夜晚尸潮战斗：黑夜围城
    INFECT = "audio/music_1779641015270.ogg",  -- 感染系统：异化边界（叠加层）
    BOSS   = "audio/music_1779641122006.ogg",  -- Boss战：暴君降临
    ERA    = "audio/music_1779641397308.ogg",  -- 世界纪元揭示：人类遗产
    UI     = "audio/music_1779641502401.ogg",  -- UI/基地管理：静谧废土
}

-- ===================== 内部状态 =====================
local audioScene_  = nil  ---@type Scene
local mainSource_  = nil  ---@type SoundSource  -- 主音乐轨
local infectSource_= nil  ---@type SoundSource  -- 感染叠加轨（独立）
local current_     = nil  -- 当前主音乐 track 名
local eraPlayed_   = {}   -- 哪些天已播过 ERA（防重复）

local MASTER_VOL     = 0.7
local INFECT_MAX_VOL = 0.4  -- 感染值满时叠加音量

-- ===================== 私有工具 =====================

local function playTrack(src, path, looped)
    local snd = cache:GetResource("Sound", path)
    if not snd then
        print("[BGM] 找不到文件：" .. path)
        return false
    end
    snd:SetLooped(looped)
    src:Play(snd)
    src:SetGain(MASTER_VOL)
    return true
end

local function switchTo(name)
    if current_ == name then return end
    if not TRACKS[name] then return end

    local looped = (name ~= "ERA")
    if playTrack(mainSource_, TRACKS[name], looped) then
        current_ = name
        print("[BGM] 切换 → " .. name)
    end
end

-- ===================== 公开接口 =====================

function BGMManager.Init()
    -- 创建独立音频场景（不依赖 scene_ 全局，本游戏为纯 NanoVG 架构）
    audioScene_ = Scene()
    local node = audioScene_:CreateChild("BGMNode")

    -- 主音乐轨
    mainSource_ = node:CreateComponent("SoundSource")
    mainSource_:SetSoundType("Music")

    -- 感染叠加轨
    local infectNode = audioScene_:CreateChild("BGMInfect")
    infectSource_ = infectNode:CreateComponent("SoundSource")
    infectSource_:SetSoundType("Music")
    local infectSnd = cache:GetResource("Sound", TRACKS.INFECT)
    if infectSnd then
        infectSnd:SetLooped(true)
        infectSource_:Play(infectSnd)
        infectSource_:SetGain(0.0)
    end

    -- 默认播放菜单 UI 音乐
    switchTo("UI")
    print("[BGM] 初始化完成")
end

function BGMManager.OnGameStart()
    switchTo("DAY")
end

-- 每帧调用：根据游戏状态自动切换音乐
function BGMManager.Update(dt)
    if not mainSource_ then return end

    local phase = GameState.phase
    local PHASE = GameState.PHASE

    -- ── 非游玩状态 → UI 音乐 ──
    if phase == PHASE.MENU or phase == PHASE.GAMEOVER or phase == PHASE.WIN then
        switchTo("UI")
        if infectSource_ then infectSource_:SetGain(0.0) end
        return
    end

    if phase ~= PHASE.PLAYING then return end

    -- ── 纪元揭示（每隔7天，黎明时刻，只播一次）──
    local day = GameState.day
    local isEraDay = (day > 1)
        and (day % Config.DAY.BOSS_INTERVAL == 0)
        and GameState.isDay
        and (GameState.GetDayProgress() < 0.05)
    if isEraDay and not eraPlayed_[day] then
        eraPlayed_[day] = true
        switchTo("ERA")
    end

    -- ── 纯状态驱动：每帧直接决定应播哪首曲目 ──
    -- 优先级：UI/非游玩（已在上方 return）> ERA > BOSS预告/BOSS夜 > NIGHT > DAY
    local isBossNight = GameState.events.isBossNight

    if GameState.isDay then
        -- 白天
        if current_ == "ERA" then
            -- ERA 播完会自动停止（非循环），停止后切回 DAY
            if not mainSource_:IsPlaying() then
                switchTo("DAY")
            end
        elseif isBossNight then
            -- Boss 日：最后20秒提前播 Boss BGM，否则照常播白天
            local remaining = Config.DAY.DAY_DURATION - GameState.phaseTimer
            if remaining <= 20.0 then
                switchTo("BOSS")
            else
                -- 还没到预告时间，确保播白天
                if current_ ~= "DAY" then
                    switchTo("DAY")
                end
            end
        else
            -- 普通白天：直接确保播 DAY
            if current_ ~= "DAY" then
                switchTo("DAY")
            end
        end
    else
        -- 夜晚
        if isBossNight then
            if current_ ~= "BOSS" then switchTo("BOSS") end
        else
            if current_ ~= "NIGHT" then switchTo("NIGHT") end
        end
    end

    -- ── 感染叠加层：随全队平均感染值线性增减 ──
    if infectSource_ then
        local avg = BGMManager.GetAvgInfect()
        -- 感染值 > 20 开始叠入，100 时达到最大音量
        local vol = math.max(0.0, (avg - 20.0) / 80.0) * INFECT_MAX_VOL
        infectSource_:SetGain(vol)
    end
end

-- ===================== 感染值获取 =====================

local getSoldiersFunc_ = nil
function BGMManager.SetSoldiersGetter(fn)
    getSoldiersFunc_ = fn
end

function BGMManager.GetAvgInfect()
    if not getSoldiersFunc_ then return 0 end
    local soldiers = getSoldiersFunc_()
    if not soldiers or #soldiers == 0 then return 0 end
    local total = 0
    for _, s in ipairs(soldiers) do
        total = total + (s.infect or 0)
    end
    return total / #soldiers
end

-- ===================== 清理 =====================

function BGMManager.Destroy()
    if audioScene_ then
        audioScene_:Remove()
        audioScene_ = nil
    end
    mainSource_   = nil
    infectSource_ = nil
    current_      = nil
    eraPlayed_    = {}
end

return BGMManager
