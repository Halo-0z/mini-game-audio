local Config = require("Config")
local GameState = {}

GameState.PHASE = {
    MENU     = "menu",
    PLAYING  = "playing",
    GAMEOVER = "gameover",
    WIN      = "win",
}

GameState.phase      = GameState.PHASE.MENU
GameState.day        = 1
GameState.isDay      = true
GameState.phaseTimer = 0
GameState.totalTime  = 0

GameState.resources = {
    SCRAP=200, FOOD=100, POWER=50, BIO=0, VIRUS=0,
}

GameState.stats = {
    zombiesKilled=0, soldiersLost=0, buildingsBuilt=0,
}

GameState.events = {
    isBossNight=false, isBloodMoon=false,
}

GameState.messages = {}
GameState.selectedBuildingType = nil
GameState.selectedEntity       = nil
GameState.hoveredTile          = {col=0, row=0}
-- 鼠标屏幕坐标（用于 hover tooltip）
GameState.mouseScreenX         = 0
GameState.mouseScreenY         = 0

-- 建造预览平滑吸附（防抖动）：浮点坐标，每帧向目标 hoveredTile 插值
GameState.previewSmooth        = {col=0.0, row=0.0}
-- 围墙拖拽路径：{col,row} 数组，只在 selectedBuildingType=="WALL" 时使用
GameState.wallDragPath         = nil   -- nil = 未拖拽中
GameState.wallDragActive       = false -- 鼠标按住拖拽中

function GameState.AddMessage(text, color)
    table.insert(GameState.messages, {
        text  = text,
        color = color or Config.COLORS.TEXT,
        timer = 3.0,
    })
    while #GameState.messages > 5 do
        table.remove(GameState.messages, 1)
    end
    print("[MSG] " .. text)
end

function GameState.TrySpendResources(cost)
    for k, v in pairs(cost) do
        if (GameState.resources[k] or 0) < v then
            return false, k
        end
    end
    for k, v in pairs(cost) do
        GameState.resources[k] = GameState.resources[k] - v
    end
    return true
end

function GameState.AddResource(rtype, amount)
    GameState.resources[rtype] = (GameState.resources[rtype] or 0) + amount
end

function GameState.GetDayProgress()
    local dur = GameState.isDay and Config.DAY.DAY_DURATION or Config.DAY.NIGHT_DURATION
    return math.min(1.0, GameState.phaseTimer / dur)
end

function GameState.StartNewDay()
    GameState.day = GameState.day + 1
    GameState.isDay = true
    GameState.phaseTimer = 0
    GameState.events.isBossNight = (GameState.day % Config.DAY.BOSS_INTERVAL == 0)
    GameState.events.isBloodMoon = (math.random() < 0.1)
    GameState.AddMessage("第 " .. GameState.day .. " 天 开始", Config.COLORS.GREEN)
end

function GameState.StartNight()
    GameState.isDay = false
    GameState.phaseTimer = 0
    if GameState.events.isBloodMoon then
        GameState.AddMessage("血月之夜！", Config.COLORS.RED)
    end
    GameState.AddMessage("夜晚降临，做好防守！", Config.COLORS.RED)
end

function GameState.UpdateMessages(dt)
    for i = #GameState.messages, 1, -1 do
        GameState.messages[i].timer = GameState.messages[i].timer - dt
        if GameState.messages[i].timer <= 0 then
            table.remove(GameState.messages, i)
        end
    end
end

function GameState.Reset()
    GameState.day        = 1
    GameState.isDay      = true
    GameState.phaseTimer = 0
    GameState.totalTime  = 0
    GameState.resources  = {
        SCRAP=Config.RESOURCES.SCRAP,
        FOOD=Config.RESOURCES.FOOD,
        POWER=Config.RESOURCES.POWER,
        BIO=Config.RESOURCES.BIO,
        VIRUS=Config.RESOURCES.VIRUS,
    }
    GameState.stats   = {zombiesKilled=0, soldiersLost=0, buildingsBuilt=0}
    GameState.events  = {isBossNight=false, isBloodMoon=false}
    GameState.messages = {}
    GameState.selectedBuildingType = nil
    GameState.selectedEntity       = nil
    GameState.hoveredTile          = {col=0, row=0}
    GameState.previewSmooth        = {col=0.0, row=0.0}
    GameState.wallDragPath         = nil
    GameState.wallDragActive       = false
end

return GameState
