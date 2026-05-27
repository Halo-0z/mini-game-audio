local Config    = require("Config")
local GameState = require("GameState")

local ZombieManager = {}

-- ===================== 障碍感知移动（分轴滑动）=====================
local UNIT_RADIUS = 0.35

local function isSolid(buildingMgr, col, row)
    if not buildingMgr then return false end
    local gc = math.floor(col)
    local gr = math.floor(row)
    return buildingMgr.IsOccupied(gc, gr)
end

-- excludeB: 可选，移动时忽略此建筑的碰撞（用于僵尸朝目标建筑移动）
local function moveWithSlide(buildingMgr, col, row, dc, dr, excludeB)
    if dc == 0 and dr == 0 then return col, row end

    local function solidEx(fc, fr)
        if not buildingMgr then return false end
        local gc = math.floor(fc)
        local gr = math.floor(fr)
        if excludeB then
            local ecfg = Config.BUILDINGS[excludeB.type]
            if ecfg then
                if gc >= excludeB.col and gc < excludeB.col + ecfg.size.w and
                   gr >= excludeB.row and gr < excludeB.row + ecfg.size.h then
                    return false
                end
            end
        end
        return buildingMgr.IsOccupied(gc, gr)
    end

    local function blocked(tc, tr)
        local r = UNIT_RADIUS
        return solidEx(tc - r, tr - r) or solidEx(tc + r, tr - r)
            or solidEx(tc - r, tr + r) or solidEx(tc + r, tr + r)
    end

    -- 如果起点本身已在建筑内（出生/卡住），直接允许移出
    if blocked(col, row) then
        return col + dc, row + dr
    end

    -- 1. 全向
    if not blocked(col + dc, row + dr) then
        return col + dc, row + dr
    end
    -- 2. 仅 col 轴
    if not blocked(col + dc, row) then
        return col + dc, row
    end
    -- 3. 仅 row 轴
    if not blocked(col, row + dr) then
        return col, row + dr
    end
    -- 4. 完全阻挡
    return col, row
end

local zombies_    = {}
local nextId_     = 1
local spawnTimer_ = 0

-- 生成边缘点
local SPAWN_EDGES = {}
local function buildSpawnEdges()
    SPAWN_EDGES = {}
    local c, r = Config.MAP.COLS, Config.MAP.ROWS
    for i = 0, c-1, 3 do
        table.insert(SPAWN_EDGES, {col=i,     row=0})
        table.insert(SPAWN_EDGES, {col=i,     row=r-1})
    end
    for i = 0, r-1, 3 do
        table.insert(SPAWN_EDGES, {col=0,     row=i})
        table.insert(SPAWN_EDGES, {col=c-1,   row=i})
    end
end
buildSpawnEdges()

-- 根据天数决定波次构成
local function waveConfig(day)
    local total = 3 + day * 2
    local types = {}
    if day >= 5  then table.insert(types, "CORROSIVE") end
    if day >= 8  then table.insert(types, "FAT") end
    -- 7的倍数召唤暴君
    if GameState.events.isBossNight then
        table.insert(types, "TYRANT")
        total = total + 5
    end
    return total, types
end

function ZombieManager.Init()
    zombies_    = {}
    nextId_     = 1
    spawnTimer_ = 0
end

function ZombieManager.GetZombies()
    return zombies_
end

function ZombieManager.SpawnOne(ztype)
    local cfg = Config.ZOMBIES[ztype]
    if not cfg then return end
    local sp = SPAWN_EDGES[math.random(1, #SPAWN_EDGES)]
    local z = {
        id    = nextId_,
        type  = ztype,
        col   = sp.col + 0.0,
        row   = sp.row + 0.0,
        hp    = cfg.maxHp,
        atkTimer = 0,
    }
    nextId_ = nextId_ + 1
    table.insert(zombies_, z)
end

function ZombieManager.SpawnWave(day)
    local total, extraTypes = waveConfig(day)
    for i = 1, total do
        local ztype = "NORMAL"
        if #extraTypes > 0 and math.random() < 0.3 then
            ztype = extraTypes[math.random(1, #extraTypes)]
        end
        ZombieManager.SpawnOne(ztype)
    end
    GameState.AddMessage("波次开始！" .. total .. " 只丧尸入侵", Config.COLORS.RED)
end

-- 找最近的建筑中心
local function findTarget(z, buildings)
    local nearest, nearDist = nil, math.huge
    for _, b in ipairs(buildings or {}) do
        local cfg = Config.BUILDINGS[b.type]
        if cfg then
            local cx = b.col + cfg.size.w * 0.5
            local cy = b.row + cfg.size.h * 0.5
            local dx = cx - z.col
            local dy = cy - z.row
            local d  = math.sqrt(dx*dx + dy*dy)
            if d < nearDist then
                nearest  = b
                nearDist = d
            end
        end
    end
    return nearest, nearDist
end

function ZombieManager.Update(dt, soldiers, buildingManager, onEffect, onGameOver)
    local buildings = buildingManager and buildingManager.GetBuildings() or {}

    -- 夜间持续生成小股
    if not GameState.isDay then
        spawnTimer_ = spawnTimer_ + dt
        if spawnTimer_ >= 4.0 then
            spawnTimer_ = 0
            local n = math.random(1, 3)
            for _ = 1, n do
                ZombieManager.SpawnOne("NORMAL")
            end
        end
    end

    for i = #zombies_, 1, -1 do
        local z = zombies_[i]
        local cfg = Config.ZOMBIES[z.type]
        if not cfg then goto zdone end

        if z.hp <= 0 then
            -- 掉落资源
            if cfg.drop then
                for rtype, amt in pairs(cfg.drop) do
                    GameState.AddResource(rtype, math.ceil(amt))
                end
            end
            GameState.stats.zombiesKilled = GameState.stats.zombiesKilled + 1
            if onEffect then onEffect("explosion", z.col, z.row) end
            table.remove(zombies_, i)
            goto zdone
        end

        -- 先看能否攻击士兵
        local atkedSoldier = false
        for _, s in ipairs(soldiers or {}) do
            local dx = s.col - z.col
            local dy = s.row - z.row
            local d  = math.sqrt(dx*dx + dy*dy)
            if d <= cfg.atkRange then
                z.atkTimer = z.atkTimer - dt
                if z.atkTimer <= 0 then
                    z.atkTimer = 1.0 / cfg.atkRate
                    s.hp = s.hp - cfg.atk
                    if onEffect then onEffect("hit", s.col, s.row) end
                end
                atkedSoldier = true
                break
            end
        end

        if not atkedSoldier then
            -- 向最近建筑移动/攻击
            local targetB, dist = findTarget(z, buildings)
            if targetB then
                local bcfg = Config.BUILDINGS[targetB.type]
                local cx = targetB.col + bcfg.size.w * 0.5
                local cy = targetB.row + bcfg.size.h * 0.5
                if dist <= cfg.atkRange + 1 then
                    z.atkTimer = z.atkTimer - dt
                    if z.atkTimer <= 0 then
                        z.atkTimer = 1.0 / cfg.atkRate
                        buildingManager.DamageBuilding(targetB, cfg.atk, onGameOver)
                        if onEffect then onEffect("hit", z.col, z.row) end
                    end
                else
                    -- 向目标建筑移动（绕开其他建筑，目标建筑本身可穿越）
                    local dx = cx - z.col
                    local dy = cy - z.row
                    local d  = math.sqrt(dx*dx + dy*dy)
                    if d > 0 then
                        local dc = dx/d * cfg.speed * dt
                        local dr = dy/d * cfg.speed * dt
                        z.col, z.row = moveWithSlide(buildingManager, z.col, z.row, dc, dr, targetB)
                    end
                end
            end
        end

        ::zdone::
    end
end

function ZombieManager.Clear()
    zombies_ = {}
end

return ZombieManager
