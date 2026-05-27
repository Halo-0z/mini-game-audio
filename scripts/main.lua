-- 尸城：第99天 — 主入口
-- 架构：NanoVG 渲染地图 + urhox-libs/UI 渲染 HUD
require "LuaScripts/Utilities/Sample"

local Config          = require("Config")
local GameState       = require("GameState")
local MapRenderer     = require("MapRenderer")
local BuildingManager = require("BuildingManager")
local SoldierManager  = require("SoldierManager")
local ZombieManager   = require("ZombieManager")
local DayNightManager = require("DayNightManager")
local ResourceManager = require("ResourceManager")
local HUD             = require("HUD")
local BGMManager      = require("BGMManager")

-- ===================== 全局状态 =====================
local vg_         = nil   ---@type userdata
local hqCol_      = 0
local hqRow_      = 0
local rmb_held_   = false  -- 右键是否按下（用于拖拽）

-- 双指捏合缩放状态
local pinch_      = {
    active    = false,
    baseDist  = 0,    -- 捏合开始时的两指距离（像素）
    baseZoom  = 1.0,  -- 捏合开始时的缩放值
}

-- ===================== 初始化游戏 =====================

local function InitGame()
    GameState.Reset()

    hqCol_, hqRow_ = BuildingManager.Init()
    SoldierManager.Init(hqCol_, hqRow_)
    ZombieManager.Init()

    GameState.phase = GameState.PHASE.PLAYING
    HUD.ShowGame()
    GameState.AddMessage("据点已建立，保卫它！", Config.COLORS.GOLD)
    print("[MAIN] 游戏已初始化，HQ at " .. hqCol_ .. "," .. hqRow_)
end

-- ===================== 生命周期 =====================

function Start()
    -- 初始化 NanoVG (通过 HUD.Init 内部的 UI.Init 已创建)
    -- 但 MapRenderer 需要单独的 nvgCreate 用于地图层
    vg_ = nvgCreate(1)
    if not vg_ then
        print("[ERROR] nvgCreate failed")
        return
    end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    MapRenderer.Init(vg_, w, h)

    -- 初始化 HUD（UI 系统）
    HUD.Init(function(btype)
        GameState.selectedBuildingType = btype
        GameState.AddMessage("选择放置位置：" .. Config.BUILDINGS[btype].name, Config.COLORS.TEXT)
    end)

    -- 注册招募回调（在 InitGame 后 hqCol_/hqRow_ 会更新，每次用闭包拿到当前值）
    HUD.SetRecruitCallback(function(stype)
        return SoldierManager.EnqueueTrain(stype, hqCol_, hqRow_)
    end)

    HUD.ShowMenu()

    -- 订阅事件（必须订阅特定 vg_ 上下文，避免触发 UI 库的 nvg 事件导致地图覆盖 UI）
    SubscribeToEvent(vg_, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update",          "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp",   "HandleMouseUp")
    SubscribeToEvent("MouseMove",       "HandleMouseMove")
    SubscribeToEvent("MouseWheel",      "HandleMouseWheel")
    SubscribeToEvent("KeyDown",         "HandleKeyDown")
    -- 触摸事件（手机双指捏合缩放）
    SubscribeToEvent("TouchBegin",      "HandleTouchBegin")
    SubscribeToEvent("TouchMove",       "HandleTouchMove")
    SubscribeToEvent("TouchEnd",        "HandleTouchEnd")
    SubscribeToEvent("StartGame",       "HandleStartGame")
    SubscribeToEvent("RestartGame",     "HandleRestartGame")

    -- 初始化BGM系统（需在 scene_ 存在后调用）
    BGMManager.Init()
    BGMManager.SetSoldiersGetter(function()
        return SoldierManager.GetSoldiers()
    end)

    print("[MAIN] Start() 完成")
end

function Stop()
    BGMManager.Destroy()
    if vg_ then
        nvgDelete(vg_)
        vg_ = nil
    end
end

-- ===================== 渲染 =====================

function HandleNanoVGRender(eventType, eventData)
    if not vg_ then return end
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    -- 每帧同步屏幕尺寸，避免窗口大小变化时 NanoVG 画布覆盖不全
    MapRenderer.Resize(w, h)

    nvgBeginFrame(vg_, w, h, 1.0)

    local skyColor   = DayNightManager.GetSkyColor()
    local nightAlpha = DayNightManager.GetNightOverlayAlpha()

    MapRenderer.Draw(
        0.016,  -- dt 近似值（特效用）
        BuildingManager.GetBuildings(),
        SoldierManager.GetSoldiers(),
        ZombieManager.GetZombies(),
        nightAlpha, skyColor,
        GameState.hoveredTile,
        GameState.selectedBuildingType,
        function(col, row)
            return BuildingManager.IsOccupied(col, row)
        end,
        function(btype, col, row)
            return BuildingManager.CanPlace(btype, col, row)
        end,
        {
            smoothCol     = GameState.previewSmooth.col,
            smoothRow     = GameState.previewSmooth.row,
            wallDragActive = GameState.wallDragActive,
            wallDragPath   = GameState.wallDragPath,
            mouseScreenX  = GameState.mouseScreenX,
            mouseScreenY  = GameState.mouseScreenY,
        }
    )

    nvgEndFrame(vg_)
end

-- ===================== 逻辑更新 =====================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- BGM每帧驱动（含淡入淡出插值）
    BGMManager.Update(dt)

    if GameState.phase ~= GameState.PHASE.PLAYING then
        GameState.UpdateMessages(dt)
        HUD.Update(dt)
        return
    end

    -- 各系统更新
    DayNightManager.Update(dt, ZombieManager)
    ResourceManager.Update(dt, BuildingManager)
    SoldierManager.UpdateTraining(dt, hqCol_, hqRow_)
    SoldierManager.Update(dt, ZombieManager.GetZombies(), BuildingManager,
        function(etype, col, row)
            MapRenderer.AddEffect(etype, col, row)
        end
    )
    ZombieManager.Update(dt, SoldierManager.GetSoldiers(), BuildingManager,
        function(etype, col, row)
            MapRenderer.AddEffect(etype, col, row)
        end,
        function()  -- onGameOver
            GameState.phase = GameState.PHASE.GAMEOVER
            HUD.ShowGameOver(false)
        end
    )
    BuildingManager.Update(dt)
    BuildingManager.UpdateAutoAttack(dt, ZombieManager.GetZombies(),
        function(etype, col, row)
            MapRenderer.AddEffect(etype, col, row)
        end
    )

    -- 建造预览平滑吸附：将浮点坐标插值向目标格子（防止光标抖动导致预览跳格）
    if GameState.selectedBuildingType then
        local sp   = GameState.previewSmooth
        local tgt  = GameState.hoveredTile
        local snap = 1.0 - math.pow(0.004, dt)  -- ~18帧收敛，dt=0.016 → 约0.97/帧
        sp.col = sp.col + (tgt.col - sp.col) * snap
        sp.row = sp.row + (tgt.row - sp.row) * snap
        -- 当浮点坐标足够靠近整数时直接吸附，避免永远无法落到整格
        if math.abs(sp.col - tgt.col) < 0.06 then sp.col = tgt.col end
        if math.abs(sp.row - tgt.row) < 0.06 then sp.row = tgt.row end
    end

    GameState.UpdateMessages(dt)

    -- 胜利检查
    if GameState.phase == GameState.PHASE.WIN then
        HUD.ShowGameOver(true)
    end

    HUD.Update(dt)
end

-- ===================== 输入 =====================

-- 将两点之间的直线格子列表写入 path（Bresenham 等距格子版）
local function appendWallLine(path, visited, c0, r0, c1, r1)
    local dc = c1 - c0
    local dr = r1 - r0
    local steps = math.max(math.abs(dc), math.abs(dr))
    if steps == 0 then
        local k = c0 .. "," .. r0
        if not visited[k] then visited[k]=true; table.insert(path, {col=c0, row=r0}) end
        return
    end
    for i = 0, steps do
        local t  = i / steps
        local cc = math.floor(c0 + dc * t + 0.5)
        local rr = math.floor(r0 + dr * t + 0.5)
        local k  = cc .. "," .. rr
        if not visited[k] then visited[k]=true; table.insert(path, {col=cc, row=rr}) end
    end
end

function HandleMouseDown(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    local mx  = eventData["X"]:GetInt()
    local my  = eventData["Y"]:GetInt()

    if btn == MOUSEB_RIGHT then
        rmb_held_ = true
        MapRenderer.BeginDrag(mx, my)
    elseif btn == MOUSEB_LEFT then
        if GameState.phase ~= GameState.PHASE.PLAYING then return end

        local col, row = MapRenderer.ScreenToIso(mx, my)
        GameState.hoveredTile  = {col=col, row=row}
        -- 预览坐标瞬时同步，防止第一帧从 (0,0) 插值过来
        GameState.previewSmooth = {col=col+0.0, row=row+0.0}

        if GameState.selectedBuildingType == "WALL" then
            -- 开始围墙拖拽
            GameState.wallDragActive = true
            local visited = {}
            local path    = {}
            local k = col..","..row
            visited[k] = true
            table.insert(path, {col=col, row=row})
            GameState.wallDragPath     = path
            GameState.wallDragVisited_ = visited   -- 内部用，不暴露到文档
            GameState.wallDragLastCol_ = col
            GameState.wallDragLastRow_ = row
        elseif GameState.selectedBuildingType then
            -- 非围墙建筑：直接建造
            local ok, reason = BuildingManager.TryBuild(
                GameState.selectedBuildingType, col, row)
            if ok then
                GameState.AddMessage(
                    "建造：" .. Config.BUILDINGS[GameState.selectedBuildingType].name,
                    Config.COLORS.GREEN)
                GameState.selectedBuildingType = nil
            else
                GameState.AddMessage("无法建造：" .. (reason or ""), Config.COLORS.RED)
            end
        end
    end
end

function HandleMouseUp(eventType, eventData)
    local btn = eventData["Button"]:GetInt()
    if btn == MOUSEB_RIGHT then
        rmb_held_ = false
        MapRenderer.EndDrag()
    elseif btn == MOUSEB_LEFT then
        -- 围墙拖拽结束：批量建造路径上的围墙
        if GameState.wallDragActive and GameState.wallDragPath then
            local built = 0
            for _, tile in ipairs(GameState.wallDragPath) do
                local ok = BuildingManager.TryBuild("WALL", tile.col, tile.row)
                if ok then built = built + 1 end
            end
            if built > 0 then
                GameState.AddMessage("建造围墙 ×" .. built, Config.COLORS.GREEN)
            end
            -- 拖拽完成后保持 WALL 模式，方便连续建造
        end
        GameState.wallDragActive   = false
        GameState.wallDragPath     = nil
        GameState.wallDragVisited_ = nil
        GameState.wallDragLastCol_ = nil
        GameState.wallDragLastRow_ = nil
    end
end

function HandleMouseMove(eventType, eventData)
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    -- 始终同步鼠标屏幕坐标（供 hover tooltip 使用）
    GameState.mouseScreenX = mx
    GameState.mouseScreenY = my

    if rmb_held_ then
        MapRenderer.UpdateDrag(mx, my)
    end

    if GameState.phase == GameState.PHASE.PLAYING then
        local col, row = MapRenderer.ScreenToIso(mx, my)
        GameState.hoveredTile = {col=col, row=row}

        -- 围墙拖拽：把新格子追加到路径
        if GameState.wallDragActive and GameState.wallDragPath then
            local lc = GameState.wallDragLastCol_
            local lr = GameState.wallDragLastRow_
            if col ~= lc or row ~= lr then
                appendWallLine(GameState.wallDragPath,
                    GameState.wallDragVisited_, lc, lr, col, row)
                GameState.wallDragLastCol_ = col
                GameState.wallDragLastRow_ = row
            end
        end
    end
end

function HandleMouseWheel(eventType, eventData)
    if GameState.phase ~= GameState.PHASE.PLAYING then return end
    local wheel = eventData["Wheel"]:GetInt()
    -- 只取方向（±1），避免系统加速导致一次滚动步进过大
    local dir = (wheel > 0) and 1 or -1
    MapRenderer.Zoom(dir)
end

-- ===================== 触摸（双指捏合缩放） =====================

local function getTwoTouchDist()
    -- 遍历当前所有触点，取前两个计算距离
    local count = input:GetNumTouches()
    if count < 2 then return nil end
    local t0 = input:GetTouch(0)
    local t1 = input:GetTouch(1)
    if not t0 or not t1 then return nil end
    local dx = t0.position.x - t1.position.x
    local dy = t0.position.y - t1.position.y
    return math.sqrt(dx*dx + dy*dy)
end

-- 每像素对应的缩放量：两指距离变化 100px ≈ 缩放变化 0.15
local PINCH_FACTOR = 0.0015

function HandleTouchBegin(eventType, eventData)
    local count = input:GetNumTouches()
    if count == 2 then
        local dist = getTwoTouchDist()
        if dist then
            pinch_.active   = true
            pinch_.baseDist = dist
            pinch_.baseZoom = MapRenderer.GetZoomTarget()
        end
    end
end

function HandleTouchMove(eventType, eventData)
    if not pinch_.active then return end
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    local dist = getTwoTouchDist()
    if not dist then return end

    -- 线性：新缩放 = 捏合开始时的缩放 + 距离变化量 × 系数
    local delta = dist - pinch_.baseDist
    MapRenderer.SetZoom(pinch_.baseZoom + delta * PINCH_FACTOR)
end

function HandleTouchEnd(eventType, eventData)
    local count = input:GetNumTouches()
    if count < 2 then
        pinch_.active   = false
        pinch_.baseDist = 0
    end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        GameState.selectedBuildingType = nil
        HUD.CancelBuild()
    elseif key == KEY_SPACE then
        -- 跳过当前阶段
        if GameState.phase == GameState.PHASE.PLAYING then
            local dur = GameState.isDay and Config.DAY.DAY_DURATION or Config.DAY.NIGHT_DURATION
            GameState.phaseTimer = dur
        end
    elseif key == KEY_F1 then
        -- 调试：补充资源
        GameState.resources.SCRAP = GameState.resources.SCRAP + 500
        GameState.resources.FOOD  = GameState.resources.FOOD  + 200
        GameState.resources.POWER = GameState.resources.POWER + 100
        GameState.AddMessage("[DEBUG] 资源+500/200/100", Config.COLORS.GOLD)
    end
end

function HandleStartGame()
    InitGame()
    BGMManager.OnGameStart()
end

function HandleRestartGame()
    InitGame()
    BGMManager.OnGameStart()
end
