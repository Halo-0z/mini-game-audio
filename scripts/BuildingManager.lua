local Config      = require("Config")
local GameState   = require("GameState")
local WallTiling  = require("WallTiling")

local BuildingManager = {}

local buildings_ = {}  ---@type table[]
local occupied_  = {}  -- occupied_[row][col] = building_id
local nextId_    = 1

-- 判断指定格子是否存在围墙（用于 WallTiling）
local function isWallAt(col, row)
    if not (occupied_[row] and occupied_[row][col]) then return false end
    local id = occupied_[row][col]
    for _, b in ipairs(buildings_) do
        if b.id == id then return b.type == "WALL" end
    end
    return false
end

-- 返回指定格子围墙的 wallMask（用于 WallTiling.GetStraightRunLen）
local function getWallMaskAt(col, row)
    if not (occupied_[row] and occupied_[row][col]) then return -1 end
    local id = occupied_[row][col]
    for _, b in ipairs(buildings_) do
        if b.id == id and b.type == "WALL" then
            return b.wallMask or 0
        end
    end
    return -1
end

-- ===================== 内部辅助 =====================

local function isOccupied(col, row)
    return occupied_[row] and occupied_[row][col] ~= nil
end

local function setOccupied(col, row, id)
    if not occupied_[row] then occupied_[row] = {} end
    occupied_[row][col] = id
end

local function clearOccupied(col, row)
    if occupied_[row] then occupied_[row][col] = nil end
end

-- ===================== 公共接口 =====================

function BuildingManager.Init()
    buildings_ = {}
    occupied_  = {}
    nextId_    = 1
    -- 在地图中心放置总部
    local hqCol = math.floor(Config.MAP.COLS * 0.5) - 1
    local hqRow = math.floor(Config.MAP.ROWS * 0.5) - 1
    BuildingManager.PlaceBuilding("HQ", hqCol, hqRow, true)
    -- 初始化所有围墙 bitmask + runLen（地图有预设围墙时保证正确）
    WallTiling.RefreshAll(buildings_, isWallAt, getWallMaskAt)
    return hqCol, hqRow
end

function BuildingManager.GetBuildings()
    return buildings_
end

function BuildingManager.IsOccupied(col, row)
    return isOccupied(col, row)
end

-- 检查某建筑类型放置在 col,row 是否可行（不扣资源，仅检查位置和边界）
-- 返回 true/false
function BuildingManager.CanPlace(btype, col, row)
    local cfg = Config.BUILDINGS[btype]
    if not cfg then return false end
    col = math.floor(col + 0.5)
    row = math.floor(row + 0.5)
    if col < 0 or row < 0
       or col + cfg.size.w > Config.MAP.COLS
       or row + cfg.size.h > Config.MAP.ROWS then
        return false
    end
    for dc = 0, cfg.size.w - 1 do
        for dr = 0, cfg.size.h - 1 do
            if isOccupied(col+dc, row+dr) then return false end
        end
    end
    return true
end

-- 尝试建造（先检查资源+格子）
function BuildingManager.TryBuild(btype, col, row)
    local cfg = Config.BUILDINGS[btype]
    if not cfg then return false, "未知建筑类型" end

    -- 检查是否在地图内
    if col < 0 or row < 0
       or col + cfg.size.w > Config.MAP.COLS
       or row + cfg.size.h > Config.MAP.ROWS then
        return false, "超出地图边界"
    end

    -- 检查格子占用
    for dc = 0, cfg.size.w - 1 do
        for dr = 0, cfg.size.h - 1 do
            if isOccupied(col+dc, row+dr) then
                return false, "该位置已被占用"
            end
        end
    end

    -- 检查并扣除资源
    local ok, missing = GameState.TrySpendResources(cfg.cost)
    if not ok then
        return false, "资源不足: " .. (missing or "")
    end

    BuildingManager.PlaceBuilding(btype, col, row, false)
    GameState.stats.buildingsBuilt = GameState.stats.buildingsBuilt + 1
    return true
end

-- ===================== Worker 槽位接口 =====================

-- 农民进入农场：返回 true 表示成功入驻
function BuildingManager.AssignWorker(building, soldierId)
    local cfg = Config.BUILDINGS[building.type]
    if not cfg or not cfg.workerSlots then return false end
    if not building.workers then building.workers = {} end
    if #building.workers >= cfg.workerSlots then return false end
    -- 防止重复入驻
    for _, id in ipairs(building.workers) do
        if id == soldierId then return false end
    end
    table.insert(building.workers, soldierId)
    local slotIdx = #building.workers  -- 1 = 左工位, 2 = 右工位
    return true, slotIdx
end

-- 农民退出农场
function BuildingManager.RemoveWorker(building, soldierId)
    if not building.workers then return end
    for i, id in ipairs(building.workers) do
        if id == soldierId then
            table.remove(building.workers, i)
            return
        end
    end
end

-- 查找最近的有空槽农场（返回建筑对象或 nil）
function BuildingManager.FindNearestFarmWithSlot(col, row)
    local best, bestDist = nil, math.huge
    for _, b in ipairs(buildings_) do
        if b.type == "FARM" then
            local cfg = Config.BUILDINGS["FARM"]
            local workers = b.workers or {}
            if #workers < cfg.workerSlots then
                local cx = b.col + cfg.size.w * 0.5
                local cr = b.row + cfg.size.h * 0.5
                local dx = cx - col
                local dr = cr - row
                local d = math.sqrt(dx*dx + dr*dr)
                if d < bestDist then
                    best = b
                    bestDist = d
                end
            end
        end
    end
    return best
end

-- 夜晚：清空所有农场 worker 槽（由 SoldierManager 配合调用）
function BuildingManager.ClearAllFarmWorkers()
    for _, b in ipairs(buildings_) do
        if b.type == "FARM" then
            b.workers = {}
        end
    end
end

-- 直接放置（无资源扣除，用于初始化和测试）
function BuildingManager.PlaceBuilding(btype, col, row, free)
    local cfg = Config.BUILDINGS[btype]
    if not cfg then return end
    local id = nextId_
    nextId_ = nextId_ + 1
    local b = {
        id   = id,
        type = btype,
        col  = col,
        row  = row,
        hp   = cfg.maxHp,
    }
    -- 围墙建造动画：free=true（初始化/测试）跳过动画，玩家主动建造时播放
    if btype == "WALL" and not free then
        b.buildProgress   = 0.0
        b.buildDuration   = 0.5 + math.random() * 0.3  -- 0.5~0.8 秒
    else
        b.buildProgress = 1.0  -- 无需动画
    end

    table.insert(buildings_, b)
    for dc = 0, cfg.size.w - 1 do
        for dr = 0, cfg.size.h - 1 do
            setOccupied(col+dc, row+dr, id)
        end
    end
    -- 围墙：计算自身 bitmask + runLen 并刷新四周邻居
    if btype == "WALL" then
        WallTiling.RefreshAround(buildings_, isWallAt, col, row, getWallMaskAt)
    end
    return b
end

function BuildingManager.FindAtTile(col, row)
    if not isOccupied(col, row) then return nil end
    local id = occupied_[row][col]
    for _, b in ipairs(buildings_) do
        if b.id == id then return b end
    end
    return nil
end

function BuildingManager.FindById(id)
    for _, b in ipairs(buildings_) do
        if b.id == id then return b end
    end
    return nil
end

function BuildingManager.DamageBuilding(b, dmg, onGameOver)
    b.hp = b.hp - dmg
    if b.hp <= 0 then
        b.hp = 0
        if b.type == "HQ" then
            if onGameOver then onGameOver() end
        else
            BuildingManager.Demolish(b)
        end
    end
end

function BuildingManager.RepairBuilding(b, amount)
    local cfg = Config.BUILDINGS[b.type]
    if cfg then
        b.hp = math.min(cfg.maxHp, b.hp + amount)
    end
end

function BuildingManager.Demolish(b)
    -- 记录拆除前信息（围墙拆除后需刷新邻居）
    local wasWall = (b.type == "WALL")
    local dCol, dRow = b.col, b.row

    local cfg = Config.BUILDINGS[b.type]
    if cfg then
        for dc = 0, cfg.size.w - 1 do
            for dr = 0, cfg.size.h - 1 do
                clearOccupied(b.col+dc, b.row+dr)
            end
        end
    end
    for i, v in ipairs(buildings_) do
        if v.id == b.id then
            table.remove(buildings_, i)
            break
        end
    end
    -- 围墙拆除后刷新四周邻居（自身已移除，邻居连接状态需更新）
    if wasWall then
        WallTiling.RefreshAround(buildings_, isWallAt, dCol, dRow, getWallMaskAt)
    end
end

-- ===================== 每帧更新（建造动画 / 未来扩展）=====================

function BuildingManager.Update(dt)
    for _, b in ipairs(buildings_) do
        -- 推进建造动画进度
        if b.buildProgress and b.buildProgress < 1.0 then
            local dur = b.buildDuration or 0.6
            b.buildProgress = math.min(1.0, b.buildProgress + dt / dur)
        end
    end
end

-- 更新瞭望塔自动攻击，返回产生的特效列表
function BuildingManager.UpdateAutoAttack(dt, zombies, onHit)
    for _, b in ipairs(buildings_) do
        local cfg = Config.BUILDINGS[b.type]
        if cfg and cfg.attack then
            b.atkTimer = (b.atkTimer or 0) - dt
            if b.atkTimer <= 0 then
                b.atkTimer = 1.0 / cfg.attack.rate
                local bCenterCol = b.col + (Config.BUILDINGS[b.type].size.w or 1) * 0.5
                local bCenterRow = b.row + (Config.BUILDINGS[b.type].size.h or 1) * 0.5
                -- 找最近的僵尸
                local nearest, nearDist = nil, math.huge
                for _, z in ipairs(zombies or {}) do
                    local dx = z.col - bCenterCol
                    local dy = z.row - bCenterRow
                    local d  = math.sqrt(dx*dx + dy*dy)
                    if d < cfg.attack.range and d < nearDist then
                        nearest  = z
                        nearDist = d
                    end
                end
                if nearest then
                    nearest.hp = nearest.hp - cfg.attack.damage
                    if onHit then onHit("hit", nearest.col, nearest.row) end
                end
            end
        end
    end
end

-- 资源生产（每秒调用一次）
function BuildingManager.ProduceResources()
    for _, b in ipairs(buildings_) do
        local cfg = Config.BUILDINGS[b.type]
        if cfg and cfg.production then
            for rtype, amount in pairs(cfg.production) do
                -- worker 加成：每个入驻农民额外贡献 workerBonus
                local bonus = 0
                if cfg.workerBonus and b.workers then
                    bonus = #b.workers * cfg.workerBonus
                end
                GameState.AddResource(rtype, amount + bonus)
            end
        end
    end
end

return BuildingManager
