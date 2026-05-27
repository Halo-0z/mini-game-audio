local Config    = require("Config")
local GameState = require("GameState")

local ResourceManager = {}

local tickTimer_ = 0
local TICK = 1.0  -- 每秒产出一次

function ResourceManager.Update(dt, buildingManager)
    tickTimer_ = tickTimer_ + dt
    if tickTimer_ >= TICK then
        tickTimer_ = tickTimer_ - TICK
        buildingManager.ProduceResources()
        -- 资源上限保护
        for k, v in pairs(GameState.resources) do
            GameState.resources[k] = math.min(v, 9999)
        end
    end
end

return ResourceManager
