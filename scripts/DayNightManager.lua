local Config    = require("Config")
local GameState = require("GameState")

local DayNightManager = {}

-- 天空插值辅助
local function lerpColor(c1, c2, t)
    return {
        math.floor(c1[1] + (c2[1]-c1[1]) * t),
        math.floor(c1[2] + (c2[2]-c1[2]) * t),
        math.floor(c1[3] + (c2[3]-c1[3]) * t),
        255,
    }
end

function DayNightManager.GetSkyColor()
    local t = GameState.GetDayProgress()
    if GameState.isDay then
        if t < 0.1 then
            return lerpColor(Config.COLORS.NIGHT_SKY, Config.COLORS.DAY_SKY, t / 0.1)
        elseif t > 0.85 then
            return lerpColor(Config.COLORS.DAY_SKY, Config.COLORS.NIGHT_SKY, (t-0.85)/0.15)
        else
            return Config.COLORS.DAY_SKY
        end
    else
        return Config.COLORS.NIGHT_SKY
    end
end

function DayNightManager.GetNightOverlayAlpha()
    if GameState.isDay then return 0 end
    local t = GameState.GetDayProgress()
    if t < 0.1 then
        return t / 0.1
    elseif t > 0.9 then
        return (1 - t) / 0.1
    else
        return 1.0
    end
end

function DayNightManager.Update(dt, zombieManager)
    local dur = GameState.isDay and Config.DAY.DAY_DURATION or Config.DAY.NIGHT_DURATION
    GameState.phaseTimer  = GameState.phaseTimer + dt
    GameState.totalTime   = GameState.totalTime + dt

    if GameState.isDay then
        if GameState.phaseTimer >= dur then
            GameState.StartNight()
            if zombieManager then
                zombieManager.SpawnWave(GameState.day)
            end
        end
    else
        if GameState.phaseTimer >= dur then
            -- 清理剩余僵尸
            if zombieManager then zombieManager.Clear() end
            -- 胜利判定
            if GameState.day >= Config.DAY.TOTAL_DAYS then
                GameState.phase = GameState.PHASE.WIN
                return
            end
            GameState.StartNewDay()
        end
    end
end

return DayNightManager
