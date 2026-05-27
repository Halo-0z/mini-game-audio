local Config    = require("Config")
local GameState = require("GameState")

local SoldierManager = {}

-- ===================== 障碍感知移动（分轴滑动）=====================
-- 单位半径（格），小于 0.5 确保不会卡进格子边缘
local UNIT_RADIUS = 0.35

-- 检查连续坐标 (col, row) 是否被建筑占用
-- buildingMgr 需传入 BuildingManager
local function isSolid(buildingMgr, col, row)
    if not buildingMgr then return false end
    -- 取整后查占格表
    local gc = math.floor(col)
    local gr = math.floor(row)
    return buildingMgr.IsOccupied(gc, gr)
end

-- 带障碍的移动：尝试全向→分轴滑动
-- 返回最终 (newCol, newRow)
local function moveWithSlide(buildingMgr, col, row, dc, dr)
    if dc == 0 and dr == 0 then return col, row end

    local function blocked(tc, tr)
        local r = UNIT_RADIUS
        return isSolid(buildingMgr, tc - r, tr - r)
            or isSolid(buildingMgr, tc + r, tr - r)
            or isSolid(buildingMgr, tc - r, tr + r)
            or isSolid(buildingMgr, tc + r, tr + r)
    end

    -- 如果起点本身已在建筑内（出生点/卡住），直接允许移出，不做阻挡判断
    if blocked(col, row) then
        return col + dc, row + dr
    end

    -- 1. 尝试全向移动
    if not blocked(col + dc, row + dr) then
        return col + dc, row + dr
    end

    -- 2. 只移动 col 轴
    if not blocked(col + dc, row) then
        return col + dc, row
    end

    -- 3. 只移动 row 轴
    if not blocked(col, row + dr) then
        return col, row + dr
    end

    -- 4. 完全被阻挡，停止
    return col, row
end

-- 农民状态常量
local FARMER_IDLE         = "idle"
local FARMER_WALK_TO_FARM = "walk_to_farm"
local FARMER_WORKING      = "working"
local FARMER_EXITING      = "exiting"

local soldiers_     = {}
local nextId_       = 1
local trainQueue_   = {}   -- {stype, timer, duration, barrackId}
local buildingMgrRef_ = nil  -- 由 Update 传入，用于查询兵营数量

function SoldierManager.Init(hqCol, hqRow)
    soldiers_   = {}
    trainQueue_ = {}
    nextId_     = 1
    -- 初始3名突击兵
    SoldierManager.Spawn("ASSAULT", hqCol + 2, hqRow)
    SoldierManager.Spawn("ASSAULT", hqCol + 2, hqRow + 1)
    SoldierManager.Spawn("ASSAULT", hqCol,     hqRow + 2)
end

function SoldierManager.GetSoldiers()
    return soldiers_
end

-- 查询训练队列
function SoldierManager.GetTrainQueue()
    return trainQueue_
end

-- 查询士兵总数
function SoldierManager.GetCount()
    return #soldiers_
end

-- 查询指定类型士兵数量
function SoldierManager.GetCountByType(stype)
    local n = 0
    for _, s in ipairs(soldiers_) do
        if s.type == stype then n = n + 1 end
    end
    return n
end

-- 加入训练队列（消耗资源，异步训练）
function SoldierManager.EnqueueTrain(stype, hqCol, hqRow)
    local cfg = Config.SOLDIERS[stype]
    if not cfg then return false, "未知类型" end
    -- 最多同时训练 3 个
    if #trainQueue_ >= 3 then return false, "训练槽已满（最多3个）" end
    local ok, miss = GameState.TrySpendResources(cfg.cost or {})
    if not ok then return false, "资源不足: " .. (miss or "") end
    table.insert(trainQueue_, {
        stype    = stype,
        timer    = 0,
        duration = cfg.trainTime or 15,
        spawnCol = hqCol + 2,   -- HQ 右侧空地，避免生成在建筑内被遮挡
        spawnRow = hqRow,
    })
    return true
end

-- 招募（消耗资源，立即出现，保留旧接口兼容）
function SoldierManager.Recruit(stype, col, row)
    local cfg = Config.SOLDIERS[stype]
    if not cfg then return false, "未知类型" end
    local ok, miss = GameState.TrySpendResources(cfg.cost or {})
    if not ok then return false, "资源不足: " .. (miss or "") end
    SoldierManager.Spawn(stype, col, row)
    return true
end

function SoldierManager.Spawn(stype, col, row)
    local cfg = Config.SOLDIERS[stype]
    if not cfg then return end
    local s = {
        id     = nextId_,
        type   = stype,
        col    = col + 0.0,
        row    = row + 0.0,
        hp     = cfg.maxHp,
        infect = 0,
        atkTimer = 0,
        guardCol = col + 0.0,
        guardRow = row + 0.0,
    }
    nextId_ = nextId_ + 1
    table.insert(soldiers_, s)
    return s
end

-- 移除士兵（农民死亡时清除 worker 槽）
local function removeSoldier(idx)
    local s = soldiers_[idx]
    if s and s.type == "FARMER" and s.targetFarm and buildingMgrRef_ then
        buildingMgrRef_.RemoveWorker(s.targetFarm, s.id)
    end
    table.remove(soldiers_, idx)
    GameState.stats.soldiersLost = GameState.stats.soldiersLost + 1
end

-- 主更新
function SoldierManager.Update(dt, zombies, buildingManager, onEffect)
    buildingMgrRef_ = buildingManager  -- 缓存供 moveWithSlide 使用
    for i = #soldiers_, 1, -1 do
        local s = soldiers_[i]
        local cfg = Config.SOLDIERS[s.type]
        if not cfg then goto continue end

        -- 感染致死
        if s.infect >= 100 then
            GameState.AddMessage(cfg.name .. " 因感染牺牲", Config.COLORS.RED)
            removeSoldier(i)
            goto continue
        end

        -- ===================== 农民专属状态机 =====================
        if s.type == "FARMER" then
            local fstate = s.farmerState or FARMER_IDLE

            -- 农场被摧毁时强制退出
            if (fstate == FARMER_WORKING or fstate == FARMER_WALK_TO_FARM) and s.targetFarm then
                local farmStillAlive = false
                for _, b in ipairs(buildingManager and buildingManager.GetBuildings() or {}) do
                    if b.id == s.targetFarm.id then farmStillAlive = true; break end
                end
                if not farmStillAlive then
                    if fstate == FARMER_WORKING then
                        buildingManager.RemoveWorker(s.targetFarm, s.id)
                    end
                    s.farmerState   = FARMER_IDLE
                    s.targetFarm    = nil
                    s.isWorking     = false
                    s.workerSlotIdx = nil
                end
            end

            fstate = s.farmerState or FARMER_IDLE

            if fstate == FARMER_IDLE then
                -- 夜晚不进农场；先看有没有僵尸威胁
                local threatened = false
                for _, z in ipairs(zombies or {}) do
                    local dx = z.col - s.col
                    local dy = z.row - s.row
                    if math.sqrt(dx*dx + dy*dy) < cfg.atkRange + 4 then
                        threatened = true; break
                    end
                end

                if GameState.isDay and not threatened and buildingManager then
                    -- 寻找最近有空槽农场
                    local farm = buildingManager.FindNearestFarmWithSlot(s.col, s.row)
                    if farm then
                        s.targetFarm  = farm
                        s.farmerState = FARMER_WALK_TO_FARM
                        fstate        = FARMER_WALK_TO_FARM
                    end
                end
            end

            if fstate == FARMER_WALK_TO_FARM then
                -- 夜晚取消前往
                if not GameState.isDay then
                    s.farmerState = FARMER_IDLE
                    s.targetFarm  = nil
                    goto farmer_done
                end

                local farm = s.targetFarm
                local fcfg = Config.BUILDINGS["FARM"]
                -- 目标：农场正前方外侧（row+h+0.3），不在建筑占格内，moveWithSlide不会拦截
                local tcol = farm.col + fcfg.size.w * 0.5
                local trow = farm.row + fcfg.size.h + 0.3
                local dx = tcol - s.col
                local dy = trow - s.row
                local d  = math.sqrt(dx*dx + dy*dy)

                -- 途中遇到僵尸先迎击
                local urgentZ = nil
                for _, z in ipairs(zombies or {}) do
                    local zx = z.col - s.col
                    local zy = z.row - s.row
                    if math.sqrt(zx*zx + zy*zy) < cfg.atkRange + 2 then
                        urgentZ = z; break
                    end
                end
                if urgentZ then
                    -- 攻击逻辑
                    s.atkTimer = s.atkTimer - dt
                    if s.atkTimer <= 0 then
                        s.atkTimer = 1.0 / cfg.atkRate
                        urgentZ.hp = urgentZ.hp - cfg.atk
                        if onEffect then onEffect("hit", urgentZ.col, urgentZ.row) end
                    end
                    goto farmer_done
                end

                -- 阈值1.5：靠近农场前方即视为"到达"，然后 snap 到工位
                if d < 1.5 then
                    -- 到达农场，尝试入驻
                    local ok, slotIdx = buildingManager.AssignWorker(farm, s.id)
                    if ok then
                        s.farmerState   = FARMER_WORKING
                        s.isWorking     = true   -- 渲染时切换为劳作图
                        s.workerSlotIdx = slotIdx or 1
                        -- 固定到工位坐标（农场前沿左/右两个工位，不重叠）
                        local farmCfg = Config.BUILDINGS["FARM"]
                        if s.workerSlotIdx == 1 then
                            s.col = farm.col + 0.35
                            s.row = farm.row + farmCfg.size.h - 0.4
                        else
                            s.col = farm.col + farmCfg.size.w - 0.35
                            s.row = farm.row + farmCfg.size.h - 0.4
                        end
                        GameState.AddMessage("农民进驻农场，粮食产量+1", Config.COLORS.GREEN)
                    else
                        -- 槽位被其他农民抢占，回 idle
                        s.farmerState = FARMER_IDLE
                        s.targetFarm  = nil
                    end
                else
                    local dc = dx/d * cfg.speed * dt
                    local dr = dy/d * cfg.speed * dt
                    s.col, s.row = moveWithSlide(buildingManager, s.col, s.row, dc, dr)
                end

            elseif fstate == FARMER_WORKING then
                -- 夜晚退出
                if not GameState.isDay then
                    local farm = s.targetFarm
                    if farm then buildingManager.RemoveWorker(farm, s.id) end
                    s.farmerState   = FARMER_EXITING
                    s.isWorking     = false
                    s.workerSlotIdx = nil
                    -- 退出目标：农场右侧外一格空地
                    local fcfg = Config.BUILDINGS["FARM"]
                    s.exitCol = farm.col + fcfg.size.w + 0.5
                    s.exitRow = farm.row + fcfg.size.h * 0.5
                end
                -- 在场内时静止不动（工位已固定）

            elseif fstate == FARMER_EXITING then
                local tx = s.exitCol or s.guardCol
                local tr = s.exitRow or s.guardRow
                local dx = tx - s.col
                local dy = tr - s.row
                local d  = math.sqrt(dx*dx + dy*dy)
                if d < 0.5 then
                    s.farmerState = FARMER_IDLE
                    s.targetFarm  = nil
                    s.exitCol     = nil
                    s.exitRow     = nil
                else
                    -- 退出农场时直接移动（已不在建筑内，障碍感知正常）
                    local dc = dx/d * cfg.speed * dt
                    local dr = dy/d * cfg.speed * dt
                    s.col, s.row = moveWithSlide(buildingManager, s.col, s.row, dc, dr)
                end
            end

            ::farmer_done::
            -- 感染值
            if not GameState.isDay then
                local infectRate = GameState.events.isBloodMoon and 0.5 or 0.1
                s.infect = math.min(100, s.infect + infectRate * dt)
            end
            goto continue
        end
        -- ===================== 非农民通用 AI =====================

        -- 找最近的僵尸
        local target = nil
        local targetDist = math.huge
        for _, z in ipairs(zombies or {}) do
            local dx = z.col - s.col
            local dy = z.row - s.row
            local d = math.sqrt(dx*dx + dy*dy)
            if d < cfg.atkRange + 5 and d < targetDist then
                target = z
                targetDist = d
            end
        end

        if target and targetDist <= cfg.atkRange then
            -- 攻击
            s.atkTimer = s.atkTimer - dt
            if s.atkTimer <= 0 then
                s.atkTimer = 1.0 / cfg.atkRate
                target.hp = target.hp - cfg.atk
                if onEffect then onEffect("hit", target.col, target.row) end
                -- 腐蚀尸传播感染
                if target.type == "CORROSIVE" then
                    s.infect = math.min(100, s.infect + 5)
                end
            end
        elseif target then
            -- 向目标移动（障碍感知）
            local dx = target.col - s.col
            local dy = target.row - s.row
            local d  = math.sqrt(dx*dx + dy*dy)
            if d > 0 then
                local dc = dx/d * cfg.speed * dt
                local dr = dy/d * cfg.speed * dt
                s.col, s.row = moveWithSlide(buildingManager, s.col, s.row, dc, dr)
            end
        else
            -- 回守卫位置（障碍感知）
            local dx = s.guardCol - s.col
            local dy = s.guardRow - s.row
            local d  = math.sqrt(dx*dx + dy*dy)
            if d > 0.3 then
                local dc = dx/d * cfg.speed * dt
                local dr = dy/d * cfg.speed * dt
                s.col, s.row = moveWithSlide(buildingManager, s.col, s.row, dc, dr)
            end

            -- 医疗兵治疗附近友军
            if s.type == "MEDIC" then
                for _, other in ipairs(soldiers_) do
                    if other.id ~= s.id then
                        local ox = other.col - s.col
                        local oy = other.row - s.row
                        if math.sqrt(ox*ox+oy*oy) < 3 then
                            local ocfg = Config.SOLDIERS[other.type]
                            if ocfg then
                                other.hp = math.min(ocfg.maxHp, other.hp + 10 * dt)
                            end
                        end
                    end
                end
            end

            -- 工程兵修复建筑
            if s.type == "ENGINEER" and buildingManager then
                for _, b in ipairs(buildingManager.GetBuildings()) do
                    local bcfg = Config.BUILDINGS[b.type]
                    if bcfg then
                        local bCx = b.col + bcfg.size.w * 0.5
                        local bCy = b.row + bcfg.size.h * 0.5
                        local dx2 = bCx - s.col
                        local dy2 = bCy - s.row
                        if math.sqrt(dx2*dx2+dy2*dy2) < 3 and b.hp < bcfg.maxHp then
                            buildingManager.RepairBuilding(b, 20 * dt)
                        end
                    end
                end
            end
        end

        -- 感染值自然增加（血月加速）
        if not GameState.isDay then
            local infectRate = GameState.events.isBloodMoon and 0.5 or 0.1
            s.infect = math.min(100, s.infect + infectRate * dt)
        end

        ::continue::
    end
end

-- 推进训练队列（仅白天训练）
function SoldierManager.UpdateTraining(dt, hqCol, hqRow)
    if not GameState.isDay then return end   -- 夜晚暂停训练
    for i = #trainQueue_, 1, -1 do
        local t = trainQueue_[i]
        t.timer = t.timer + dt
        if t.timer >= t.duration then
            -- 训练完成，在HQ附近生成
            local spawnCol = t.spawnCol or hqCol
            local spawnRow = t.spawnRow or hqRow
            SoldierManager.Spawn(t.stype, spawnCol, spawnRow)
            local cfg = Config.SOLDIERS[t.stype]
            GameState.AddMessage(
                (cfg and cfg.name or t.stype) .. " 训练完成！",
                Config.COLORS.GREEN)
            table.remove(trainQueue_, i)
        end
    end
end

return SoldierManager
