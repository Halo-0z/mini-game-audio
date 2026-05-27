local Config      = require("Config")
local GameState   = require("GameState")
local WallTiling  = require("WallTiling")

local MapRenderer = {}

-- 内部状态
local vg_      = nil
local screenW_ = 1280
local screenH_ = 720
local camX_    = 0
local camY_    = 0
local dragging_= false
local dragSX_  = 0
local dragSY_  = 0
local dragCX_  = 0
local dragCY_  = 0

local effects_ = {}   -- {type, sx, sy, timer}
local fonts_   = {}

-- 图片句柄
local bldImgs_  = {}    -- bldImgs_["HQ"] = nvgImage id
local unitImgs_ = {}    -- unitImgs_["soldier_ASSAULT"] = id, unitImgs_["zombie_NORMAL"] = id
local tileImgs_ = {}    -- tileImgs_.grass_a / grass_b / dirt / crack（保留兼容，暂未使用）
local groundImg_   = -1    -- 整幅地面底图

-- 动画计时器（全局，用于呼吸灯/脉冲效果）
local animTimer_ = 0

local tw = Config.MAP.TILE_W
local th = Config.MAP.TILE_H

-- 缩放（平滑插值）
local zoom_        = 1.0
local zoomTarget_  = 1.0   -- 目标缩放，实际值向它平滑靠近
local ZOOM_MIN     = 0.4
local ZOOM_MAX     = 3.0
local ZOOM_STEP    = 0.08  -- 每次滚轮步进（一格滚轮 = 8% 缩放变化）
local ZOOM_SMOOTH  = 12.0  -- 平滑速度（越大收敛越快）

-- 整幅地面底图文件
local GROUND_IMG_FILE   = "image/ground_wasteland_20260524122813.png"
-- 基地平台半径（格数，用于 drawGroundDensityMask）
local PLATFORM_RADIUS   = 7

-- 地砖 → 文件名映射（保留，暂未使用）
local TILE_IMG_FILES = {
    grass_a = "image/tile_grass_a_20260524120121.png",
    grass_b = "image/tile_grass_b_20260524120142.png",
    dirt    = "image/tile_dirt_20260524120129.png",
    crack   = "image/tile_crack_20260524120128.png",
}

-- ===================== Decal 系统 =====================

-- Decal 类型配置：颜色 + 默认持续时间（-1 = 永久）
local DECAL_CFG = {
    BLOOD   = { r=180, g=20,  b=20,  a=160, duration=-1 },   -- 干涸血迹（永久）
    SCORCH  = { r=30,  g=25,  b=15,  a=180, duration=-1 },   -- 烧焦痕迹（永久）
    INFECT  = { r=80,  g=200, b=60,  a=140, duration=15  },  -- 感染区（15秒）
    TOXIC   = { r=120, g=220, b=20,  a=130, duration=10  },  -- 毒雾残留（10秒）
    CORPSE  = { r=90,  g=70,  b=40,  a=170, duration=-1 },   -- 尸体残骸（永久）
}

-- Decal 状态列表：{type, col, row, timer, maxTimer, radiusX, radiusY, angle}
local decals_ = {}

-- 建筑 → 文件名映射
local BLD_IMG_FILES = {
    HQ_GROUND   = "image/hq_ground_iso_20260524131128.png",
    HQ          = "image/bld_hq_iso_20260523162910.png",
    BARRACKS    = "image/bld_barracks_iso_20260523162913.png",
    POWER_PLANT = "image/bld_powerplant_iso_20260523162912.png",
    HOSPITAL    = "image/bld_hospital_iso_20260523162908.png",
    WORKSHOP    = "image/bld_workshop_iso_20260523162909.png",
    WALL        = "image/bld_wall_iso_20260523162920.png",   -- 后备（HUD 用）
    WATCHTOWER  = "image/bld_watchtower_iso_20260523162908.png",
    FARM        = "image/bld_farm_new_20260524173117.png",
    FARM_GROUND = "image/bld_farm_ground_20260524175854.png",
    LAB         = "image/bld_lab_iso_20260523162911.png",
    PROCESSOR   = "image/bld_processor_iso_20260523162912.png",
    -- ── 围墙自动拼接 16 种变体（键名 = WALL_<bitmask>）──
    -- bitmask: up(bit0)|right(bit1)|down(bit2)|left(bit3)
    WALL_0  = "image/wall_single_20260524132118.png",      -- 0000 孤立
    WALL_1  = "image/wall_end_N_20260524132148.png",       -- 0001 仅北
    WALL_2  = "image/wall_end_E_20260524132308.png",       -- 0010 仅东
    WALL_3  = "image/wall_corner_NE_20260524132444.png",   -- 0011 北+东
    WALL_4  = "image/wall_end_S_20260524132231.png",       -- 0100 仅南
    WALL_5  = "image/wall_v_20260524132125.png",           -- 0101 北+南（纵直线）
    WALL_6  = "image/wall_corner_SE_20260524132440.png",   -- 0110 东+南
    WALL_7  = "image/wall_T_W_20260524132448.png",         -- 0111 北+东+南（缺西 T_W）
    WALL_8  = "image/wall_end_W_20260524132132.png",       -- 1000 仅西
    WALL_9  = "image/wall_corner_NW_20260524132600.png",   -- 1001 北+西
    WALL_10 = "image/wall_h_20260524132124.png",           -- 1010 东+西（横直线）
    WALL_11 = "image/wall_T_S_20260524132442.png",         -- 1011 北+东+西（缺南 T_S）
    WALL_12 = "image/wall_corner_SW_20260524132449.png",   -- 1100 南+西
    WALL_13 = "image/wall_T_E_20260524132441.png",         -- 1101 北+南+西（缺东 T_E）
    WALL_14 = "image/wall_T_N_20260524132443.png",         -- 1110 东+南+西（缺北 T_N）
    WALL_15 = "image/wall_cross_20260524132355.png",       -- 1111 十字

    -- ── V1.5：节点柱 / 长墙装饰 / 损坏叠加 ──────────────────────
    WALL_CORNER_POST  = "image/wall_corner_post_20260524134022.png",   -- 转角/T/十字节点铁柱
    WALL_DECO_WIRE    = "image/wall_deco_wire_20260524133746.png",      -- 刺铁丝网装饰（叠加层）
    WALL_DECO_LIGHT   = "image/wall_deco_light_20260524133744.png",     -- 探照灯装饰（叠加层）
    WALL_DECO_BANNER  = "image/wall_deco_banner_20260524134053.png",    -- 警示横幅（叠加层）
    WALL_DECO_DAMAGE  = "image/wall_deco_banner_20260524134053.png",    -- 损坏标记（临时复用 banner）
    WALL_DAMAGE_1     = "image/wall_damage_1_20260524133743.png",       -- 轻度损坏（70%~40% HP）
    WALL_DAMAGE_2     = "image/wall_damage_2_20260524133747.png",       -- 重度损坏（<40% HP）
}

-- 士兵 → 文件名映射
local SOLDIER_IMG_FILES = {
    ASSAULT  = "image/unit_soldier_assault_20260523163049.png",
    SNIPER   = "image/unit_soldier_sniper_20260523163043.png",
    GUARD    = "image/unit_soldier_guard_20260523163128.png",
    MEDIC    = "image/unit_soldier_medic_20260523163052.png",
    ENGINEER = "image/unit_soldier_engineer_20260523163106.png",
    FLAMER   = "image/unit_soldier_flamer_20260523163101.png",
    FARMER         = "image/unit_soldier_farmer_20260524171144.png",
    FARMER_WORKING = "image/unit_farmer_working_20260524173124.png",
}

-- 僵尸 → 文件名映射
local ZOMBIE_IMG_FILES = {
    NORMAL   = "image/unit_zombie_normal_20260523163436.png",
    CORROSIVE= "image/unit_zombie_acid_20260523163435.png",
    FAT      = "image/unit_zombie_bloated_20260523163436.png",
    SCREAMER = "image/unit_zombie_screamer_20260523163437.png",
    JUMPER   = "image/unit_zombie_leaper_20260523163442.png",
    TYRANT   = "image/unit_zombie_tyrant_20260523163439.png",
}

-- ===================== 初始化 =====================

function MapRenderer.Init(vg, w, h)
    vg_ = vg
    screenW_ = w
    screenH_ = h
    fonts_.sans = nvgCreateFont(vg_, "map-sans", "Fonts/MiSans-Regular.ttf")

    -- 加载整幅地面底图（不重复，单次映射到整个菱形）
    groundImg_ = nvgCreateImage(vg_, GROUND_IMG_FILE, 0)
    if groundImg_ and groundImg_ >= 0 then
        print("[MapRenderer] 地面底图加载成功: " .. GROUND_IMG_FILE)
    else
        groundImg_ = -1
        print("[MapRenderer] 地面底图加载失败（将使用程序化渐变）: " .. GROUND_IMG_FILE)
    end

    -- 加载建筑图片
    for btype, path in pairs(BLD_IMG_FILES) do
        local id = nvgCreateImage(vg_, path, 0)
        if id and id >= 0 then
            bldImgs_[btype] = id
        else
            print("[MapRenderer] 建筑图片加载失败: " .. path)
        end
    end

    -- 加载士兵图片（FARMER_WORKING 单独存入 s_FARMER_WORKING）
    for stype, path in pairs(SOLDIER_IMG_FILES) do
        local id = nvgCreateImage(vg_, path, 0)
        if id and id >= 0 then
            unitImgs_["s_" .. stype] = id
        else
            print("[MapRenderer] 士兵图片加载失败: " .. path)
        end
    end

    -- 加载僵尸图片
    for ztype, path in pairs(ZOMBIE_IMG_FILES) do
        local id = nvgCreateImage(vg_, path, 0)
        if id and id >= 0 then
            unitImgs_["z_" .. ztype] = id
        else
            print("[MapRenderer] 僵尸图片加载失败: " .. path)
        end
    end

    print("[MapRenderer] 图片加载完成")
end

function MapRenderer.Resize(w, h)
    screenW_ = w
    screenH_ = h
end

-- ===================== 坐标转换 =====================

-- 当前缩放后的瓦片尺寸
local function ztw() return tw * zoom_ end
local function zth() return th * zoom_ end

-- 计算地图原点，使地图居中于可用区域
local function calcOrigin()
    local topBarH = Config.HUD.TOP_H + 36   -- 资源栏 + 天数栏
    local availW  = screenW_ - Config.HUD.SIDE_W
    -- 地图菱形总高度（缩放后）= (COLS-1 + ROWS-1) * zth()/2
    local mapH    = (Config.MAP.COLS - 1 + Config.MAP.ROWS - 1) * (zth() * 0.5)
    local availH  = screenH_ - topBarH
    local originX = availW * 0.5 + camX_
    -- 垂直居中于顶部栏以下区域
    local originY = topBarH + math.max(0, (availH - mapH) * 0.5) + camY_
    return originX, originY
end

function MapRenderer.IsoToScreen(col, row)
    local originX, originY = calcOrigin()
    local sx = originX + (col - row) * (ztw() * 0.5)
    local sy = originY + (col + row) * (zth() * 0.5)
    return sx, sy
end

function MapRenderer.ScreenToIso(sx, sy)
    local originX, originY = calcOrigin()
    local dx = sx - originX
    local dy = sy - originY
    local col = (dx / (ztw() * 0.5) + dy / (zth() * 0.5)) * 0.5
    local row = (dy / (zth() * 0.5) - dx / (ztw() * 0.5)) * 0.5
    return math.floor(col + 0.5), math.floor(row + 0.5)
end

-- 缩放控制：delta > 0 放大，delta < 0 缩小（写入目标值，Draw 里平滑插值）
function MapRenderer.Zoom(delta)
    zoomTarget_ = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoomTarget_ + delta * ZOOM_STEP))
end

-- 直接设置目标缩放（用于双指捏合的绝对缩放）
function MapRenderer.SetZoom(value)
    zoomTarget_ = math.max(ZOOM_MIN, math.min(ZOOM_MAX, value))
end

function MapRenderer.GetZoom()
    return zoom_
end

function MapRenderer.GetZoomTarget()
    return zoomTarget_
end

function MapRenderer.IsValidTile(col, row)
    return col >= 0 and col < Config.MAP.COLS and row >= 0 and row < Config.MAP.ROWS
end

-- ===================== 绘制基础形状 =====================

-- 绘制一个等距菱形（用于地砖），支持渐变填充
local function drawDiamondFill(sx, sy, w, h, r, g, b, a)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, sx,         sy - h*0.5)
    nvgLineTo(vg_, sx + w*0.5, sy)
    nvgLineTo(vg_, sx,         sy + h*0.5)
    nvgLineTo(vg_, sx - w*0.5, sy)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(r, g, b, a))
    nvgFill(vg_)
end

-- 绘制一个等距菱形（带垂直渐变，增加立体感）
local function drawDiamondGradient(sx, sy, w, h, r1,g1,b1, r2,g2,b2, alpha)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, sx,         sy - h*0.5)
    nvgLineTo(vg_, sx + w*0.5, sy)
    nvgLineTo(vg_, sx,         sy + h*0.5)
    nvgLineTo(vg_, sx - w*0.5, sy)
    nvgClosePath(vg_)
    local paint = nvgLinearGradient(vg_,
        sx, sy - h*0.5,   -- 顶点（亮色）
        sx, sy + h*0.5,   -- 底点（暗色）
        nvgRGBA(r1,g1,b1,alpha),
        nvgRGBA(r2,g2,b2,alpha))
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- ===================== 绘制地图底层 =====================

-- 地砖颜色预设（偶数/奇数两套，各自亮色+暗色，形成立体渐变）
local TILE_EVEN_LIGHT = {105, 138,  78}   -- 浅绿草地
local TILE_EVEN_DARK  = { 72,  98,  52}   -- 深绿草地
local TILE_ODD_LIGHT  = { 96, 128,  70}   -- 偶数格稍浅
local TILE_ODD_DARK   = { 65,  90,  46}   -- 偶数格稍深

-- 整个地图地面作为一个大菱形渲染
-- 若底图已加载：单张图一次性铺满整个菱形，无重复无接缝
-- 若底图未加载：程序化暗色渐变兜底
local function drawGround()
    -- 地图四角屏幕坐标
    local topX,   topY   = MapRenderer.IsoToScreen(0,               0)
    local rightX, rightY = MapRenderer.IsoToScreen(Config.MAP.COLS,  0)
    local botX,   botY   = MapRenderer.IsoToScreen(Config.MAP.COLS,  Config.MAP.ROWS)
    local leftX,  leftY  = MapRenderer.IsoToScreen(0,               Config.MAP.ROWS)

    -- 菱形包围盒：左上角 = (leftX, topY)，宽高 = 整个菱形 bounding rect
    local bboxX = leftX
    local bboxY = topY
    local bboxW = rightX - leftX   -- 菱形宽（从左角到右角）
    local bboxH = botY  - topY     -- 菱形高（从顶角到底角）

    -- 菱形裁切路径（所有绘制层共用）
    local function clipDiamond()
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, topX,   topY)
        nvgLineTo(vg_, rightX, rightY)
        nvgLineTo(vg_, botX,   botY)
        nvgLineTo(vg_, leftX,  leftY)
        nvgClosePath(vg_)
    end

    if groundImg_ >= 0 then
        -- ── 有底图：单次映射，无任何重复 ──
        -- nvgImagePattern: pattern 原点 = bboxX/bboxY，铺展宽高 = bboxW/bboxH
        -- 图像被拉伸填满整个菱形包围盒，菱形路径裁切边界
        local paint = nvgImagePattern(vg_, bboxX, bboxY, bboxW, bboxH, 0, groundImg_, 1.0)
        clipDiamond()
        nvgFillPaint(vg_, paint)
        nvgFill(vg_)

        -- 叠加边缘暗化 vignette，增强纵深感
        local cx    = (topX + botX) * 0.5
        local cy    = (topY + botY) * 0.5
        local halfW = bboxW * 0.5
        local vignette = nvgRadialGradient(vg_, cx, cy,
            halfW * 0.4, halfW * 1.1,
            nvgRGBA(0, 0, 0,   0),
            nvgRGBA(0, 0, 0, 110))
        clipDiamond()
        nvgFillPaint(vg_, vignette)
        nvgFill(vg_)
    else
        -- ── 无底图：程序化渐变兜底 ──
        local cx = (topX + botX) * 0.5
        local cy = (topY + botY) * 0.5

        -- 基础底色
        local baseFill = nvgLinearGradient(vg_,
            topX, topY, botX, botY,
            nvgRGBA(78,  88, 54, 255),
            nvgRGBA(52,  62, 36, 255))
        clipDiamond()
        nvgFillPaint(vg_, baseFill)
        nvgFill(vg_)

        -- 边缘暗化
        local halfW = bboxW * 0.5
        local vignette = nvgRadialGradient(vg_, cx, cy,
            halfW * 0.35, halfW * 1.05,
            nvgRGBA(0, 0, 0,   0),
            nvgRGBA(0, 0, 0, 130))
        clipDiamond()
        nvgFillPaint(vg_, vignette)
        nvgFill(vg_)
    end
end

-- ===================== 地面细节密度分层叠加 =====================
-- 中心区域叠加半透明暗色，降低底图细节干扰；边缘保持原始纹理
local function drawGroundDensityMask(hqCol, hqRow)
    -- 找到中心参考点：若有 HQ 则以 HQ 为中心，否则以地图中心
    local cCol = hqCol or (Config.MAP.COLS * 0.5)
    local cRow = hqRow or (Config.MAP.ROWS * 0.5)
    local cx, cy = MapRenderer.IsoToScreen(cCol, cRow)

    -- 中心区半径（等距屏幕像素）
    local centerR = (PLATFORM_RADIUS + 2) * ztw() * 0.5

    -- 内圈：30% 细节 → 叠加 50 alpha 的暗色压制纹理
    local inner = nvgRadialGradient(vg_, cx, cy,
        centerR * 0.3, centerR * 1.0,
        nvgRGBA(18, 14, 10, 60),   -- 中心：明显压暗
        nvgRGBA(18, 14, 10, 0))    -- 向外渐变为透明
    local topX,   topY   = MapRenderer.IsoToScreen(0,               0)
    local rightX, rightY = MapRenderer.IsoToScreen(Config.MAP.COLS,  0)
    local botX,   botY   = MapRenderer.IsoToScreen(Config.MAP.COLS,  Config.MAP.ROWS)
    local leftX,  leftY  = MapRenderer.IsoToScreen(0,               Config.MAP.ROWS)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, topX, topY) nvgLineTo(vg_, rightX, rightY)
    nvgLineTo(vg_, botX, botY) nvgLineTo(vg_, leftX,  leftY)
    nvgClosePath(vg_)
    nvgFillPaint(vg_, inner)
    nvgFill(vg_)
end

-- ===================== HQ 地面底座 =====================
-- 将 HQ_ground.png 贴图映射到 HQ 所在的等距菱形区域
-- PNG 自身的透明通道负责边缘融合，无需程序化遮罩
local function drawHQGround(buildings)
    if not buildings then return end

    local imgId = bldImgs_["HQ_GROUND"]
    if not imgId or imgId < 0 then return end

    -- 找 HQ 建筑
    local hq = nil
    for _, b in ipairs(buildings) do
        if b.type == "HQ" then hq = b; break end
    end
    if not hq then return end

    local cfg = Config.BUILDINGS["HQ"]
    if not cfg then return end

    local hqCX = hq.col + cfg.size.w * 0.5
    local hqCY = hq.row + cfg.size.h * 0.5
    local R    = PLATFORM_RADIUS   -- 8 格半径覆盖 8×8 菱形区域

    -- 计算等距菱形的包围盒（四角极点 → bbox）
    -- 图片透明通道自行处理边缘融合，这里直接铺满包围盒矩形
    local topX,   topY   = MapRenderer.IsoToScreen(hqCX,     hqCY - R)
    local rightX, rightY = MapRenderer.IsoToScreen(hqCX + R, hqCY)
    local botX,   botY   = MapRenderer.IsoToScreen(hqCX,     hqCY + R)
    local leftX,  leftY  = MapRenderer.IsoToScreen(hqCX - R, hqCY)

    local bboxX = leftX
    local bboxY = topY
    local bboxW = rightX - leftX
    local bboxH = botY   - topY

    -- 将图片单次非重复地拉伸到整个包围盒，PNG 透明边缘自然融入地面
    local paint = nvgImagePattern(vg_, bboxX, bboxY, bboxW, bboxH, 0, imgId, 1.0)
    nvgBeginPath(vg_)
    nvgRect(vg_, bboxX, bboxY, bboxW, bboxH)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- ===================== Decal 绘制 =====================

-- 绘制所有 decal（在地面上、建筑下）
local function drawDecals(dt)
    for i = #decals_, 1, -1 do
        local d = decals_[i]
        local cfg = DECAL_CFG[d.type]
        if not cfg then
            table.remove(decals_, i)
        else
            -- 更新计时器
            if d.timer > 0 then
                d.timer = d.timer - (dt or 0.016)
                if d.timer <= 0 then
                    table.remove(decals_, i)
                    goto continue
                end
            end

            -- 透明度：有限时间 decal 末尾渐隐
            local alpha = cfg.a
            if d.timer > 0 and d.maxTimer > 0 then
                local fade = d.timer / d.maxTimer  -- 1=刚放置 0=即将消失
                alpha = math.floor(cfg.a * math.min(1, fade * 3))  -- 最后1/3时间渐隐
            end

            if alpha > 0 then
                local sx, sy = MapRenderer.IsoToScreen(d.col + 0.5, d.row + 0.5)
                local rx = d.radiusX * zoom_
                local ry = d.radiusY * zoom_

                -- 保存变换状态，旋转绘制椭圆
                nvgSave(vg_)
                nvgTranslate(vg_, sx, sy)
                nvgRotate(vg_, d.angle)

                nvgBeginPath(vg_)
                nvgEllipse(vg_, 0, 0, rx, ry)

                if d.type == "BLOOD" then
                    -- 血迹：深红中心 + 暗棕边缘
                    local paint = nvgRadialGradient(vg_, 0, 0,
                        rx * 0.3, rx,
                        nvgRGBA(160, 10, 10, alpha),
                        nvgRGBA(80,  5,  5,  0))
                    nvgFillPaint(vg_, paint)
                elseif d.type == "SCORCH" then
                    -- 烧焦：焦黑中心 + 深灰边缘
                    local paint = nvgRadialGradient(vg_, 0, 0,
                        rx * 0.4, rx,
                        nvgRGBA(20, 15, 8, alpha),
                        nvgRGBA(10, 8,  4, 0))
                    nvgFillPaint(vg_, paint)
                elseif d.type == "INFECT" then
                    -- 感染：毒绿渐变，带脉冲感（用 timer 驱动透明度波动）
                    local pulse = math.floor(alpha * (0.7 + 0.3 * math.abs(math.sin(d.timer * 2))))
                    local paint = nvgRadialGradient(vg_, 0, 0,
                        rx * 0.3, rx,
                        nvgRGBA(cfg.r, cfg.g, cfg.b, pulse),
                        nvgRGBA(cfg.r, cfg.g, cfg.b, 0))
                    nvgFillPaint(vg_, paint)
                elseif d.type == "TOXIC" then
                    -- 毒雾：黄绿色
                    local paint = nvgRadialGradient(vg_, 0, 0,
                        rx * 0.2, rx,
                        nvgRGBA(cfg.r, cfg.g, cfg.b, alpha),
                        nvgRGBA(cfg.r, cfg.g, cfg.b, 0))
                    nvgFillPaint(vg_, paint)
                else
                    -- CORPSE 及默认：纯色椭圆
                    nvgFillColor(vg_, nvgRGBA(cfg.r, cfg.g, cfg.b, alpha))
                end
                nvgFill(vg_)

                nvgRestore(vg_)
            end

            ::continue::
        end
    end
end

-- ===================== 建筑（使用图片） =====================

-- 用图片绘制建筑，以格子中心等距投影对齐
-- cfg.drawScale（可选）：图片渲染缩放比例，默认 1.0；< 1.0 缩小，使建筑更贴合格子脚印
local function drawBuildingImage(b, cfg, imgId, hpRatio)
    -- 建筑占 cfg.size.w × cfg.size.h 格
    local x0, y0 = MapRenderer.IsoToScreen(b.col,              b.row)              -- 顶角
    local x1, y1 = MapRenderer.IsoToScreen(b.col + cfg.size.w, b.row)              -- 右角
    local x2, y2 = MapRenderer.IsoToScreen(b.col + cfg.size.w, b.row + cfg.size.h) -- 底角
    local x3, y3 = MapRenderer.IsoToScreen(b.col,              b.row + cfg.size.h) -- 左角

    -- 菱形脚印宽度（屏幕像素）
    local footW = (x1 - x3)   -- 等距菱形宽度
    local footH = (x2 - x0) * 0.5  -- 等距菱形高度（≈ footW * 0.5 for standard iso）

    -- 图片渲染宽度：乘以可选缩放系数
    local scale = cfg.drawScale or 1.0
    local imgW  = footW * scale

    -- 图片底部对齐到菱形底角 y2（建筑脚踩地面），水平居中于菱形
    local cx = (x0 + x2) * 0.5  -- 菱形水平中心
    local drawX = cx - imgW * 0.5
    local drawY = y2 - imgW      -- 图片是正方形，底对齐底角

    -- 受损变暗
    local alpha = math.floor(220 * (0.5 + hpRatio * 0.5))

    local paint = nvgImagePattern(vg_, drawX, drawY, imgW, imgW, 0, imgId, alpha / 255.0)
    nvgBeginPath(vg_)
    nvgRect(vg_, drawX, drawY, imgW, imgW)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- 程序化立方体（图片加载失败时的后备）
local function drawIsoCubeFallback(b, cfg)
    local c    = cfg.color
    local cTop   = {math.min(255,c[1]+30), math.min(255,c[2]+30), math.min(255,c[3]+30), 255}
    local cLeft  = {math.floor(c[1]*0.6), math.floor(c[2]*0.6), math.floor(c[3]*0.6), 255}
    local cRight = {math.floor(c[1]*0.8), math.floor(c[2]*0.8), math.floor(c[3]*0.8), 255}
    local depth  = 20 + (cfg.size.w + cfg.size.h) * 4
    local hpRatio = b.hp / cfg.maxHp
    if hpRatio < 0.5 then
        local f = 0.5 + hpRatio
        for _, cc in ipairs({cTop, cLeft, cRight}) do
            cc[1] = math.floor(cc[1]*f)
            cc[2] = math.floor(cc[2]*f)
            cc[3] = math.floor(cc[3]*f)
        end
    end

    local x0,y0 = MapRenderer.IsoToScreen(b.col,          b.row)
    local x1,y1 = MapRenderer.IsoToScreen(b.col+cfg.size.w, b.row)
    local x2,y2 = MapRenderer.IsoToScreen(b.col+cfg.size.w, b.row+cfg.size.h)
    local x3,y3 = MapRenderer.IsoToScreen(b.col,          b.row+cfg.size.h)

    nvgBeginPath(vg_)
    nvgMoveTo(vg_, x0,y0) nvgLineTo(vg_, x1,y1)
    nvgLineTo(vg_, x2,y2) nvgLineTo(vg_, x3,y3)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(cTop[1],cTop[2],cTop[3],255))
    nvgFill(vg_)

    nvgBeginPath(vg_)
    nvgMoveTo(vg_, x3,y3) nvgLineTo(vg_, x2,y2)
    nvgLineTo(vg_, x2,y2+depth) nvgLineTo(vg_, x3,y3+depth)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(cLeft[1],cLeft[2],cLeft[3],255))
    nvgFill(vg_)

    nvgBeginPath(vg_)
    nvgMoveTo(vg_, x1,y1) nvgLineTo(vg_, x2,y2)
    nvgLineTo(vg_, x2,y2+depth) nvgLineTo(vg_, x1,y1+depth)
    nvgClosePath(vg_)
    nvgFillColor(vg_, nvgRGBA(cRight[1],cRight[2],cRight[3],255))
    nvgFill(vg_)
end

-- 建筑底部等距阴影椭圆
local function drawBuildingShadow(b, cfg)
    local cx_col = b.col + cfg.size.w * 0.5
    local cx_row = b.row + cfg.size.h * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx_col, cx_row)
    local w  = ztw() * cfg.size.w * 0.75
    local rx = w * 0.5
    local ry = rx * 0.32
    nvgBeginPath(vg_)
    nvgEllipse(vg_, sx, sy, rx, ry)
    local shadow = nvgRadialGradient(vg_, sx, sy, rx * 0.2, rx,
        nvgRGBA(0, 0, 0, 80),
        nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(vg_, shadow)
    nvgFill(vg_)
end

-- HQ 呼吸光效（蓝色/红色脉冲光晕）
local function drawHQGlow(b, cfg, nightAlpha)
    local cx_col = b.col + cfg.size.w * 0.5
    local cx_row = b.row + cfg.size.h * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx_col, cx_row)
    local pulse = 0.5 + 0.5 * math.sin(animTimer_ * 1.8)

    -- 白天：微弱蓝光
    local dayAlpha  = math.floor(30 + pulse * 35)
    local glow = nvgRadialGradient(vg_, sx, sy - ztw() * 0.3,
        ztw() * 0.6, ztw() * 2.0,
        nvgRGBA(60, 140, 255, dayAlpha),
        nvgRGBA(60, 140, 255, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy - ztw() * 0.3, ztw() * 2.0)
    nvgFillPaint(vg_, glow)
    nvgFill(vg_)

    -- 夜晚叠加：更强蓝色光晕
    if nightAlpha and nightAlpha > 0.1 then
        local nightGlowA = math.floor(nightAlpha * (50 + pulse * 60))
        local nightGlow = nvgRadialGradient(vg_, sx, sy - ztw() * 0.3,
            ztw() * 0.4, ztw() * 2.8,
            nvgRGBA(80, 180, 255, nightGlowA),
            nvgRGBA(80, 180, 255, 0))
        nvgBeginPath(vg_)
        nvgCircle(vg_, sx, sy - ztw() * 0.3, ztw() * 2.8)
        nvgFillPaint(vg_, nightGlow)
        nvgFill(vg_)
    end
end

-- ===================== V1.5 围墙专用渲染辅助 =====================

-- 在等距坐标 (b.col, b.row) 处以指定 alpha 绘制一张叠加层图片
local function drawWallOverlay(b, cfg, imgId, alpha)
    if not imgId or imgId < 0 then return end
    local cx = b.col + cfg.size.w * 0.5
    local cy = b.row + cfg.size.h * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx, cy)
    local w  = ztw() * cfg.size.w
    local h  = w     -- 1×1 格等距正方形贴图
    local paint = nvgImagePattern(vg_, sx - w * 0.5, sy - h, w, h, 0, imgId, alpha)
    nvgBeginPath(vg_)
    nvgRect(vg_, sx - w * 0.5, sy - h, w, h)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- 损坏状态叠加（HPRatio → 叠加贴图）
local function drawWallDamageOverlay(b, cfg, hpRatio)
    if hpRatio >= 0.7 then return end
    local key   = hpRatio < 0.4 and "WALL_DAMAGE_2" or "WALL_DAMAGE_1"
    local imgId = bldImgs_[key]
    if not imgId then return end
    -- 损坏程度越高越鲜明
    local alpha = hpRatio < 0.4 and 0.9 or 0.65
    drawWallOverlay(b, cfg, imgId, alpha)
end

-- 感染状态 NanoVG 程序化效果（infect 0~100）
local function drawWallInfection(b, cfg, infect)
    if not infect or infect < 50 then return end
    local cx = b.col + cfg.size.w * 0.5
    local cy = b.row + cfg.size.h * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx, cy)
    local r   = ztw() * 0.55
    local t   = animTimer_
    local fac = (infect - 50) / 50.0  -- 0~1

    -- 肉色脉动光晕
    local pulse   = 0.5 + 0.5 * math.sin(t * 2.2 + b.col * 1.3)
    local baseA   = math.floor(fac * 80 + pulse * 40)
    local glow    = nvgRadialGradient(vg_, sx, sy - r * 0.3,
        r * 0.2, r * 1.6,
        nvgRGBA(180, 40, 80, baseA),
        nvgRGBA(180, 40, 80, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy - r * 0.3, r * 1.6)
    nvgFillPaint(vg_, glow)
    nvgFill(vg_)

    -- infect>=100：触手纹路
    if infect >= 100 then
        nvgBeginPath(vg_)
        for i = 1, 5 do
            local ang  = t * 0.6 + i * 1.257
            local len  = r * (0.7 + 0.3 * math.sin(t * 1.8 + i))
            local x0   = sx + math.cos(ang)         * r * 0.2
            local y0   = sy - r * 0.4 + math.sin(ang) * r * 0.1
            local x1   = sx + math.cos(ang + 0.4)   * len
            local y1   = sy - r * 0.4 + math.sin(ang + 0.4) * len * 0.55
            nvgMoveTo(vg_, x0, y0)
            nvgQuadTo(vg_,
                (x0 + x1) * 0.5 + math.cos(ang + 1.57) * r * 0.25,
                (y0 + y1) * 0.5 + math.sin(ang + 1.57) * r * 0.12,
                x1, y1)
        end
        nvgStrokeColor(vg_, nvgRGBA(220, 60, 100, 160))
        nvgStrokeWidth(vg_, math.max(1, zoom_ * 1.2))
        nvgStroke(vg_)
    end
end

-- 建造动画（progress 0→1，约 0.5~0.8 秒完成）
local function drawWallBuildAnim(b, cfg, progress)
    if progress >= 1.0 then return end
    local cx = b.col + cfg.size.w * 0.5
    local cy = b.row + cfg.size.h * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx, cy)
    local w  = ztw() * cfg.size.w
    local h  = w

    -- 阶段1（0~0.35）：钢架轮廓
    if progress < 0.35 then
        local fac = progress / 0.35
        -- 虚线矩形骨架
        nvgBeginPath(vg_)
        nvgRect(vg_, sx - w * 0.5 * fac, sy - h * fac, w * fac, h * fac)
        nvgStrokeColor(vg_, nvgRGBA(200, 160, 50, math.floor(180 * fac)))
        nvgStrokeWidth(vg_, math.max(1, zoom_ * 1.5))
        nvgStroke(vg_)
        -- 斜撑十字
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, sx - w * 0.5 * fac, sy)
        nvgLineTo(vg_, sx + w * 0.5 * fac, sy - h * fac)
        nvgMoveTo(vg_, sx + w * 0.5 * fac, sy)
        nvgLineTo(vg_, sx - w * 0.5 * fac, sy - h * fac)
        nvgStrokeColor(vg_, nvgRGBA(200, 160, 50, math.floor(120 * fac)))
        nvgStroke(vg_)

    -- 阶段2（0.35~0.65）：焊接火花
    elseif progress < 0.65 then
        local fac = (progress - 0.35) / 0.30
        math.randomseed(b.id * 137)  -- 固定随机序列
        for i = 1, 8 do
            local ang  = math.random() * 6.28
            local dist = w * 0.3 * math.random()
            local px   = sx + math.cos(ang) * dist
            local py   = sy - h * 0.5 + math.sin(ang) * dist * 0.4
            local size = math.max(1, zoom_ * (1.5 + math.random() * 2))
            nvgBeginPath(vg_)
            nvgCircle(vg_, px, py, size)
            nvgFillColor(vg_, nvgRGBA(255, math.random(150, 255), 20,
                math.floor((1 - fac) * 220)))
            nvgFill(vg_)
        end

    -- 阶段3（0.65~1.0）：围墙从下往上升起
    else
        -- 透明度从 0 淡入
        local fac = (progress - 0.65) / 0.35
        -- "揭示"效果用 alpha 模拟
        -- 实际图片由调用方控制 alpha（返回 fac 给调用方）
        -- 这里额外画一道橙色扫光线
        local scanY = sy - h * fac
        local grad  = nvgLinearGradient(vg_, sx - w * 0.5, scanY - 4 * zoom_,
            sx - w * 0.5, scanY + 4 * zoom_,
            nvgRGBA(255, 180, 50, 0),
            nvgRGBA(255, 180, 50, math.floor(180 * (1 - fac))))
        nvgBeginPath(vg_)
        nvgRect(vg_, sx - w * 0.5, scanY - 4 * zoom_, w, 8 * zoom_)
        nvgFillPaint(vg_, grad)
        nvgFill(vg_)
    end
end

-- ===================== 单个建筑绘制 =====================

local function drawOneBuilding(b, nightAlpha)
    local cfg = Config.BUILDINGS[b.type]
    if not cfg then return end

    local hpRatio = b.hp / cfg.maxHp

    -- 围墙：根据 wallMask 选取对应变体贴图
    local imgId
    if b.type == "WALL" then
        local maskKey = "WALL_" .. (b.wallMask or 0)
        imgId = bldImgs_[maskKey] or bldImgs_["WALL"]
    else
        imgId = bldImgs_[b.type]
    end

    -- 农场：地面层（用 GPT Image 2 生成的田垄贴图填充精确脚印，无扩展，避免 Z-order 遮挡）
    if b.type == "FARM" then
        local groundImgId = bldImgs_["FARM_GROUND"]
        -- 精确的 2×2 建筑脚印四角（不扩展）
        local x0, y0 = MapRenderer.IsoToScreen(b.col,              b.row)
        local x1, y1 = MapRenderer.IsoToScreen(b.col + cfg.size.w, b.row)
        local x2, y2 = MapRenderer.IsoToScreen(b.col + cfg.size.w, b.row + cfg.size.h)
        local x3, y3 = MapRenderer.IsoToScreen(b.col,              b.row + cfg.size.h)

        nvgSave(vg_)

        if groundImgId then
            -- 用 nvgImagePattern 将贴图映射到包围盒，再以菱形 path 裁出菱形区域
            local bbX = math.min(x0, x1, x2, x3)
            local bbY = math.min(y0, y1, y2, y3)
            local bbW = math.max(x0, x1, x2, x3) - bbX
            local bbH = math.max(y0, y1, y2, y3) - bbY
            local pat = nvgImagePattern(vg_, bbX, bbY, bbW, bbH, 0, groundImgId, 1.0)
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, x0, y0) nvgLineTo(vg_, x1, y1)
            nvgLineTo(vg_, x2, y2) nvgLineTo(vg_, x3, y3)
            nvgClosePath(vg_)
            nvgFillPaint(vg_, pat)
            nvgFill(vg_)
        else
            -- 回退：纯色填充
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, x0, y0) nvgLineTo(vg_, x1, y1)
            nvgLineTo(vg_, x2, y2) nvgLineTo(vg_, x3, y3)
            nvgClosePath(vg_)
            nvgFillColor(vg_, nvgRGBA(72, 48, 18, 245))
            nvgFill(vg_)
        end

        -- 菱形外框
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, x0, y0) nvgLineTo(vg_, x1, y1)
        nvgLineTo(vg_, x2, y2) nvgLineTo(vg_, x3, y3)
        nvgClosePath(vg_)
        nvgStrokeColor(vg_, nvgRGBA(40, 26, 8, 200))
        nvgStrokeWidth(vg_, math.max(1.0, zoom_ * 1.2))
        nvgStroke(vg_)

        nvgRestore(vg_)
    end

    -- 建筑底部阴影
    drawBuildingShadow(b, cfg)

    -- 建造动画期间：计算基础 alpha
    local buildProgress = b.buildProgress or 1.0
    local baseAlpha = 1.0
    if b.type == "WALL" and buildProgress < 1.0 then
        drawWallBuildAnim(b, cfg, buildProgress)
        if buildProgress >= 0.65 then
            baseAlpha = (buildProgress - 0.65) / 0.35
        else
            baseAlpha = 0.0
        end
    end

    if imgId and baseAlpha > 0.01 then
        nvgSave(vg_)
        nvgGlobalAlpha(vg_, baseAlpha)
        drawBuildingImage(b, cfg, imgId, hpRatio)
        nvgRestore(vg_)
    elseif not imgId then
        drawIsoCubeFallback(b, cfg)
    end

    -- WALL V1.5 叠加层
    if b.type == "WALL" and buildProgress >= 1.0 then
        local mask = b.wallMask or 0
        if WallTiling.IsJunction(mask) then
            drawWallOverlay(b, cfg, bldImgs_["WALL_CORNER_POST"], 1.0)
        end
        local runLen = b.wallRunLen or 0
        if runLen >= 4 and (mask == 5 or mask == 10) then
            local decoKey = WallTiling.GetDecoKey(b.col, b.row)
            if decoKey then
                drawWallOverlay(b, cfg, bldImgs_[decoKey], 0.85)
            end
        end
        drawWallDamageOverlay(b, cfg, hpRatio)
        if (b.infect or 0) >= 50 then
            drawWallInfection(b, cfg, b.infect)
        end
    end

    -- HQ 呼吸光效
    if b.type == "HQ" then
        drawHQGlow(b, cfg, nightAlpha)
    end

    -- 农场 worker 槽位状态（底部小圆点）
    if b.type == "FARM" then
        local farmCfg  = Config.BUILDINGS["FARM"]
        local slots    = farmCfg.workerSlots or 2
        local workers  = b.workers or {}
        local count    = #workers
        -- 圆点排在建筑底角正下方
        local x2, y2 = MapRenderer.IsoToScreen(b.col + cfg.size.w, b.row + cfg.size.h)
        local x3, y3 = MapRenderer.IsoToScreen(b.col,              b.row + cfg.size.h)
        local dotCx   = (x2 + x3) * 0.5
        local dotCy   = y2 + 6 * zoom_
        local dotR    = math.max(3, 4 * zoom_)
        local spacing = dotR * 2.8
        local totalW  = (slots - 1) * spacing
        for si = 1, slots do
            local dx = (si - 1) * spacing - totalW * 0.5
            local filled = si <= count
            nvgBeginPath(vg_)
            nvgCircle(vg_, dotCx + dx, dotCy, dotR)
            if filled then
                nvgFillColor(vg_, nvgRGBA(100, 230, 80, 230))
            else
                nvgFillColor(vg_, nvgRGBA(60, 60, 60, 160))
            end
            nvgFill(vg_)
            nvgStrokeColor(vg_, nvgRGBA(30, 30, 30, 180))
            nvgStrokeWidth(vg_, 1.0)
            nvgStroke(vg_)
        end
    end

    -- 血条
    if hpRatio < 1.0 then
        local midCol = b.col + cfg.size.w * 0.5
        local midRow = b.row + cfg.size.h * 0.5
        local tx, ty = MapRenderer.IsoToScreen(midCol, midRow)
        local bw = ztw() * cfg.size.w * 0.6
        local bx = tx - bw * 0.5
        local by = ty - 28 * zoom_
        local barH = math.max(3, math.floor(5 * zoom_))
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw, barH)
        nvgFillColor(vg_, nvgRGBA(0,0,0,140))
        nvgFill(vg_)
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw * hpRatio, barH)
        local gr = math.floor(200 * hpRatio)
        nvgFillColor(vg_, nvgRGBA(200 - gr, gr, 20, 255))
        nvgFill(vg_)
    end
end

-- ===================== 单位绘制辅助函数 =====================

-- 以图片绘制单位，居中于等距坐标
local function drawUnitImage(sx, sy, imgId, size, infect)
    local half = size * 0.5
    if infect and infect > 30 then
        local alpha = math.floor(infect * 1.5)
        nvgBeginPath(vg_)
        nvgCircle(vg_, sx, sy, half + 4)
        nvgFillColor(vg_, nvgRGBA(200, 50, 200, math.min(200, alpha)))
        nvgFill(vg_)
    end
    local paint = nvgImagePattern(vg_, sx - half, sy - size, size, size, 0, imgId, 1.0)
    nvgBeginPath(vg_)
    nvgRect(vg_, sx - half, sy - size, size, size)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
end

-- 单位脚下等距投影椭圆阴影
local function drawFootShadow(sx, sy, size)
    local rx = size * 0.42
    local ry = rx * 0.32
    nvgBeginPath(vg_)
    nvgEllipse(vg_, sx, sy, rx, ry)
    local shadow = nvgRadialGradient(vg_, sx, sy, rx * 0.2, rx,
        nvgRGBA(0, 0, 0, 90),
        nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(vg_, shadow)
    nvgFill(vg_)
end

-- 单位脚下等距圆环（阵营颜色）
local function drawTeamRing(sx, sy, size, team)
    local rx = size * 0.50
    local ry = rx * 0.35
    local r, g, b, a
    if team == "friendly" then
        r, g, b, a = 80, 140, 255, 200
    elseif team == "selected" then
        r, g, b, a = 255, 200, 50, 230
    else
        r, g, b, a = 200, 40, 40, 180
    end
    nvgBeginPath(vg_)
    nvgEllipse(vg_, sx, sy, rx, ry)
    nvgStrokeWidth(vg_, math.max(1.5, 2.0 * zoom_))
    nvgStrokeColor(vg_, nvgRGBA(r, g, b, a))
    nvgStroke(vg_)
    nvgBeginPath(vg_)
    nvgEllipse(vg_, sx, sy, rx * 0.85, ry * 0.85)
    nvgStrokeWidth(vg_, math.max(0.8, 1.0 * zoom_))
    nvgStrokeColor(vg_, nvgRGBA(r, g, b, math.floor(a * 0.4)))
    nvgStroke(vg_)
end

-- 后备圆圈（无图片时）
local function drawUnitCircle(sx, sy, r, c, icon, infect)
    if infect and infect > 30 then
        nvgBeginPath(vg_)
        nvgCircle(vg_, sx, sy, r + 3)
        nvgFillColor(vg_, nvgRGBA(200, 50, 200, math.floor(infect * 1.5)))
        nvgFill(vg_)
    end
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy, r)
    nvgFillColor(vg_, nvgRGBA(c[1],c[2],c[3],c[4] or 255))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBA(0,0,0,100))
    nvgStrokeWidth(vg_, 1)
    nvgStroke(vg_)
    nvgFontFace(vg_, "map-sans")
    nvgFontSize(vg_, r * 1.2)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, nvgRGBA(255,255,255,230))
    nvgText(vg_, sx, sy, icon)
end

-- ===================== 单个士兵绘制 =====================

local function drawOneSoldier(s, nightAlpha)
    local cfg = Config.SOLDIERS[s.type]
    if not cfg then return end

    local sx, sy = MapRenderer.IsoToScreen(s.col, s.row)
    -- 农民工作中切换为劳作姿态图
    local imgKey = (s.type == "FARMER" and s.isWorking) and "s_FARMER_WORKING" or ("s_" .. s.type)
    local imgId  = unitImgs_[imgKey]
    local uSize  = math.max(12, math.floor(32 * zoom_))

    drawFootShadow(sx, sy, uSize)
    drawTeamRing(sx, sy, uSize, "friendly")

    if imgId then
        drawUnitImage(sx, sy, imgId, uSize, s.infect)
        if nightAlpha and nightAlpha > 0.2 then
            local glowA = math.floor(nightAlpha * 160)
            local half = uSize * 0.5
            nvgBeginPath(vg_)
            nvgRect(vg_, sx - half, sy - uSize, uSize, uSize)
            nvgStrokeWidth(vg_, math.max(1.5, 2 * zoom_))
            nvgStrokeColor(vg_, nvgRGBA(100, 180, 255, glowA))
            nvgStroke(vg_)
        end
    else
        local r = math.max(5, math.floor(8 * zoom_))
        drawUnitCircle(sx, sy - r, r, cfg.color, cfg.icon, s.infect)
    end

    if s.hp < cfg.maxHp then
        local bw  = math.max(10, math.floor(20 * zoom_))
        local bx  = sx - bw * 0.5
        local by  = sy - uSize - 6
        local barH = math.max(2, math.floor(3 * zoom_))
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw, barH)
        nvgFillColor(vg_, nvgRGBA(0,0,0,140))
        nvgFill(vg_)
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw * (s.hp / cfg.maxHp), barH)
        nvgFillColor(vg_, nvgRGBA(80, 220, 80, 255))
        nvgFill(vg_)
    end
end

-- ===================== 单个僵尸绘制 =====================

local function drawOneZombie(z, nightAlpha)
    local cfg = Config.ZOMBIES[z.type]
    if not cfg then return end

    local sx, sy = MapRenderer.IsoToScreen(z.col, z.row)
    local imgId  = unitImgs_["z_" .. z.type]
    local baseSize = cfg.isBoss and 48 or (z.type == "FAT" and 38 or 28)
    local size   = math.max(10, math.floor(baseSize * zoom_))

    drawFootShadow(sx, sy, size)
    drawTeamRing(sx, sy, size, "enemy")

    if imgId then
        drawUnitImage(sx, sy, imgId, size, nil)
        if nightAlpha and nightAlpha > 0.2 then
            local glowA = math.floor(nightAlpha * 140)
            local half = size * 0.5
            nvgBeginPath(vg_)
            nvgRect(vg_, sx - half, sy - size, size, size)
            nvgStrokeWidth(vg_, math.max(1.5, 2 * zoom_))
            nvgStrokeColor(vg_, nvgRGBA(255, 80, 60, glowA))
            nvgStroke(vg_)
        end
    else
        local r = size * 0.5
        drawUnitCircle(sx, sy - r, r, cfg.color, "☠", nil)
    end

    if cfg.isBoss then
        nvgFontFace(vg_, "map-sans")
        nvgFontSize(vg_, math.max(7, 9 * zoom_))
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg_, nvgRGBA(255,80,80,255))
        nvgText(vg_, sx, sy - size - 2, "BOSS")
    end

    if cfg.isBoss and z.hp < cfg.maxHp then
        local bw   = math.max(20, math.floor(30 * zoom_))
        local bx   = sx - bw * 0.5
        local by   = sy - size - 14 * zoom_
        local barH = math.max(3, math.floor(4 * zoom_))
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw, barH)
        nvgFillColor(vg_, nvgRGBA(0,0,0,140))
        nvgFill(vg_)
        nvgBeginPath(vg_)
        nvgRect(vg_, bx, by, bw * (z.hp / cfg.maxHp), barH)
        nvgFillColor(vg_, nvgRGBA(220, 60, 60, 255))
        nvgFill(vg_)
    end
end

-- ===================== 混合 Z 排序绘制（画家算法）=====================
-- 建筑、士兵、僵尸统一排序后绘制，真正实现 2.5D 层次遮挡
--
-- sortKey 计算规则：
--   建筑: col + size.w + row + size.h  （占地最远角，即最靠近观察者的边缘）
--   单位: col + row + 1.0              （脚点 + 微小偏移让单位优先显示于同深度建筑之前）
--   排序: sortKey 升序 → 越小越"远"越先画，越大越"近"越后画（遮挡前景）

local function drawSceneZSorted(buildings, soldiers, zombies, nightAlpha)
    local items = {}

    if buildings then
        for _, b in ipairs(buildings) do
            local cfg = Config.BUILDINGS[b.type]
            if cfg then
                -- 建筑前缘 = 占地最远角（col+w, row+h），是最靠近观察者的顶点
                local sortKey = (b.col + cfg.size.w) + (b.row + cfg.size.h)
                table.insert(items, { kind="building", obj=b, key=sortKey })
            end
        end
    end

    if soldiers then
        for _, s in ipairs(soldiers) do
            -- 单位脚点 + 小偏移，保证同格时单位画在建筑前方
            table.insert(items, { kind="soldier", obj=s, key=s.col + s.row + 0.9 })
        end
    end

    if zombies then
        for _, z in ipairs(zombies) do
            table.insert(items, { kind="zombie", obj=z, key=z.col + z.row + 0.9 })
        end
    end

    -- sortKey 升序：小=远=先画，大=近=后画（后画者遮挡先画者）
    table.sort(items, function(a, b) return a.key < b.key end)

    for _, item in ipairs(items) do
        if item.kind == "building" then
            drawOneBuilding(item.obj, nightAlpha)
        elseif item.kind == "soldier" then
            drawOneSoldier(item.obj, nightAlpha)
        else
            drawOneZombie(item.obj, nightAlpha)
        end
    end
end
-- ===================== 特效 =====================

-- 添加一个 Decal
-- dtype   : "BLOOD" | "SCORCH" | "INFECT" | "TOXIC" | "CORPSE"
-- col/row : 地图格坐标（支持小数，表示格内偏移）
-- opts    : 可选表 { permanent=true, radiusX=n, radiusY=n, angle=n }
function MapRenderer.AddDecal(dtype, col, row, opts)
    local cfg = DECAL_CFG[dtype]
    if not cfg then return end
    opts = opts or {}

    -- 默认半径：一格的等距宽度的一半左右，带随机抖动
    local baseR = tw * 0.45 + math.random() * tw * 0.2
    local radiusX = opts.radiusX or (baseR * (0.8 + math.random() * 0.4))
    local radiusY = opts.radiusY or (radiusX * 0.55)   -- 等距视角压扁
    local angle   = opts.angle   or (math.random() * math.pi * 2)

    local permanent = opts.permanent
    if permanent == nil then permanent = (cfg.duration < 0) end

    local duration = permanent and -1 or cfg.duration
    local decal = {
        type    = dtype,
        col     = col + (math.random() - 0.5) * 0.3,  -- 轻微随机偏移，避免完全对齐
        row     = row + (math.random() - 0.5) * 0.3,
        timer   = duration > 0 and duration or -1,
        maxTimer= duration > 0 and duration or -1,
        radiusX = radiusX,
        radiusY = radiusY,
        angle   = angle,
    }
    table.insert(decals_, decal)
end

-- 清空所有 Decal（关卡重置时调用）
function MapRenderer.ClearDecals()
    decals_ = {}
end

function MapRenderer.AddEffect(etype, col, row)
    local sx, sy = MapRenderer.IsoToScreen(col, row)
    table.insert(effects_, {type=etype, sx=sx, sy=sy, timer=0.3})
end

local function drawEffects(dt)
    for i = #effects_, 1, -1 do
        local e = effects_[i]
        e.timer = e.timer - (dt or 0.016)
        local alpha = math.max(0, math.floor(e.timer / 0.3 * 200))
        if e.type == "hit" then
            nvgBeginPath(vg_)
            nvgCircle(vg_, e.sx, e.sy, 6 * (1 - e.timer/0.3) + 3)
            nvgFillColor(vg_, nvgRGBA(255,100,50,alpha))
            nvgFill(vg_)
        elseif e.type == "explosion" then
            nvgBeginPath(vg_)
            nvgCircle(vg_, e.sx, e.sy, 20 * (1 - e.timer/0.3) + 5)
            nvgFillColor(vg_, nvgRGBA(255,200,50,alpha))
            nvgFill(vg_)
        end
        if e.timer <= 0 then
            table.remove(effects_, i)
        end
    end
end

-- ===================== 建造预览 =====================

-- ===== 建造预览辅助 =====

-- 绘制单个格子的高亮菱形（填充+描边）
local function drawPreviewTile(col, row, r, g, b, fillA, strokeA)
    local sx, sy   = MapRenderer.IsoToScreen(col, row)
    local ptw, pth = ztw(), zth()
    -- 填充
    drawDiamondFill(sx, sy, ptw, pth, r, g, b, fillA)
    -- 描边（亮边）
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, sx,            sy - pth*0.5)
    nvgLineTo(vg_, sx + ptw*0.5,  sy)
    nvgLineTo(vg_, sx,            sy + pth*0.5)
    nvgLineTo(vg_, sx - ptw*0.5,  sy)
    nvgClosePath(vg_)
    nvgStrokeColor(vg_, nvgRGBA(math.min(255,r+60), math.min(255,g+60), math.min(255,b+60), strokeA))
    nvgStrokeWidth(vg_, math.max(1.0, ztw() * 0.03))
    nvgStroke(vg_)
end

-- 绘制底座投影（建筑占地区域的阴影椭圆）
local function drawFootprintShadow(col, row, sw, sh)
    -- 占地中心屏幕坐标（等距菱形中心）
    local cx = col + sw * 0.5
    local cy = row + sh * 0.5
    local sx, sy = MapRenderer.IsoToScreen(cx, cy)
    -- 椭圆半径：横向 = 格宽×占地宽/2，纵向压扁为横向的40%
    local rx = ztw() * (sw + sh) * 0.25   -- 等距菱形横向半径
    local ry = rx * 0.38                   -- 纵向压扁贴地
    -- 径向渐变从中心透明到边缘淡出
    local grad = nvgRadialGradient(vg_,
        sx, sy,
        rx * 0.05, rx * 1.1,
        nvgRGBA(0, 0, 0, 70),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg_)
    nvgEllipse(vg_, sx, sy, rx, ry)
    nvgFillPaint(vg_, grad)
    nvgFill(vg_)
end

-- 绘制建筑幽灵预览图（canBuild 控制颜色）
local function drawGhostImage(col, row, btype, canBuild)
    local cfg = Config.BUILDINGS[btype]
    if not cfg then return end

    local imgId = bldImgs_[btype]
    if btype == "WALL" then imgId = bldImgs_["WALL_0"] end
    if not imgId then return end

    local iCol = math.floor(col + 0.5)
    local iRow = math.floor(row + 0.5)
    local x0p, y0p = MapRenderer.IsoToScreen(iCol, iRow)
    local x1p, _   = MapRenderer.IsoToScreen(iCol + cfg.size.w, iRow)
    local x3p, _   = MapRenderer.IsoToScreen(iCol, iRow + cfg.size.h)
    local imgW          = x1p - x3p
    local buildingVisualH = imgW * 0.85
    local drawX = x3p
    local drawY = y0p - buildingVisualH * 0.5

    -- 不可放：先画红色色调底层（不受 GlobalAlpha 影响）
    if not canBuild then
        nvgBeginPath(vg_)
        nvgRect(vg_, drawX, drawY, imgW, imgW)
        nvgFillColor(vg_, nvgRGBA(220, 60, 60, 70))
        nvgFill(vg_)
    end
    -- 图片层：canBuild→60% alpha；不可放→50% alpha（叠在红色上）
    nvgSave(vg_)
    nvgGlobalAlpha(vg_, canBuild and 0.62 or 0.50)
    local paint = nvgImagePattern(vg_, drawX, drawY, imgW, imgW, 0, imgId, 1.0)
    nvgBeginPath(vg_)
    nvgRect(vg_, drawX, drawY, imgW, imgW)
    nvgFillPaint(vg_, paint)
    nvgFill(vg_)
    nvgRestore(vg_)
end

-- 主预览函数（普通建筑单格点击模式）
-- canPlaceFn(btype, col, row) → bool  整体可建检查
-- occupiedFn(col, row) → bool         单格占用检查（用于逐格染色）
local function drawBuildPreview(smoothCol, smoothRow, btype, canPlaceFn, occupiedFn)
    if not btype then return end
    local cfg = Config.BUILDINGS[btype]
    if not cfg then return end

    -- 取整坐标（用于格子高亮和阴影）
    local iCol = math.floor(smoothCol + 0.5)
    local iRow = math.floor(smoothRow + 0.5)

    -- 整体是否可建（位置+边界+所有子格均空闲）
    local canBuild = canPlaceFn and canPlaceFn(btype, iCol, iRow) or false

    -- 整体色调：蓝绿 = 可放，红 = 不可放
    local r = canBuild and 60  or 220
    local g = canBuild and 180 or 60
    local b = canBuild and 240 or 60

    -- 1. 地面投影阴影（最底层）
    drawFootprintShadow(iCol, iRow, cfg.size.w, cfg.size.h)

    -- 2. 占地格高亮（逐格独立判断，含描边）
    for dc = 0, cfg.size.w - 1 do
        for dr = 0, cfg.size.h - 1 do
            -- 单格被占 → 红色；否则用整体色调
            local occ = occupiedFn and occupiedFn(iCol+dc, iRow+dr)
            local tr = occ and 220 or r
            local tg = occ and 60  or g
            local tb = occ and 60  or b
            drawPreviewTile(iCol+dc, iRow+dr, tr, tg, tb, 90, 180)
        end
    end

    -- 3. 建筑幽灵图（平滑坐标，跟鼠标走，给人"正在移动"的感觉）
    drawGhostImage(smoothCol, smoothRow, btype, canBuild)
end

-- 围墙拖拽路径预览
local function drawWallDragPreview(path, canPlaceFn)
    if not path or #path == 0 then return end
    for _, tile in ipairs(path) do
        local canBuild = canPlaceFn and canPlaceFn("WALL", tile.col, tile.row) or false
        local r = canBuild and 60  or 220
        local g = canBuild and 200 or 60
        local b = canBuild and 255 or 60
        drawPreviewTile(tile.col, tile.row, r, g, b, 100, 200)
        -- 幽灵图（只在路径≤20格时渲染，避免卡顿）
        if #path <= 20 then
            drawGhostImage(tile.col, tile.row, "WALL", canBuild)
        end
    end
end

-- ===================== 农民 hover tooltip =====================

local function drawFarmerTooltip(s, msx, msy)
    local sx, sy = MapRenderer.IsoToScreen(s.col, s.row)
    local uSize  = math.max(12, math.floor(32 * zoom_))

    local cfg    = Config.SOLDIERS and Config.SOLDIERS["FARMER"]
    local name   = (cfg and cfg.name) or "农民"
    local maxHp  = (cfg and cfg.maxHp) or 80
    local lines  = {}
    table.insert(lines, string.format("%s  HP %d/%d", name, math.floor(s.hp or maxHp), maxHp))

    local farmerState = s.farmerState or ""
    if farmerState == "working" or s.isWorking then
        table.insert(lines, "状态：正在耕种")
        table.insert(lines, "每天产出 +1 粮食")
    elseif farmerState == "walk_to_farm" then
        table.insert(lines, "状态：前往农场...")
    elseif farmerState == "exiting" or farmerState == "exit_farm" then
        table.insert(lines, "状态：撤离农场")
    elseif farmerState == "idle" or farmerState == "" then
        table.insert(lines, "状态：待机中")
        table.insert(lines, "（需要农场才能工作）")
    else
        table.insert(lines, "状态：" .. farmerState)
    end
    if (s.infect or 0) > 0 then
        table.insert(lines, string.format("⚠ 感染度 %d%%", math.floor(s.infect)))
    end

    local fontSize = math.max(10, math.floor(11 * zoom_))
    local lineH    = fontSize + 4
    local padX, padY = 8, 6
    local maxW = 0
    nvgFontSize(vg_, fontSize)
    nvgFontFace(vg_, "sans")
    for _, line in ipairs(lines) do
        local lw = nvgTextBounds(vg_, 0, 0, line)
        if lw > maxW then maxW = lw end
    end
    local boxW = maxW + padX * 2
    local boxH = #lines * lineH + padY * 2

    local tx = msx + 14
    local ty = msy - boxH - 8
    if tx + boxW > screenW_ - 4 then tx = msx - boxW - 14 end
    if ty < 4 then ty = msy + 14 end

    -- 背景框
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, tx, ty, boxW, boxH, 5)
    nvgFillColor(vg_, nvgRGBA(10, 10, 20, 210))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBA(120, 200, 120, 180))
    nvgStrokeWidth(vg_, 1.2)
    nvgStroke(vg_)

    -- 顶部标题条
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, tx, ty, boxW, lineH + padY, 5)
    nvgFillColor(vg_, nvgRGBA(40, 100, 40, 200))
    nvgFill(vg_)

    -- 文字
    nvgFontSize(vg_, fontSize)
    nvgFontFace(vg_, "sans")
    for i, line in ipairs(lines) do
        local lx = tx + padX
        local ly = ty + padY + (i - 1) * lineH + fontSize
        if i == 1 then
            nvgFillColor(vg_, nvgRGBA(180, 255, 160, 255))
        elseif line:find("^⚠") then
            nvgFillColor(vg_, nvgRGBA(255, 180, 60, 255))
        else
            nvgFillColor(vg_, nvgRGBA(210, 210, 210, 240))
        end
        nvgText(vg_, lx, ly, line)
    end

    -- 连接线到单位头顶
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, tx + 6, ty + boxH)
    nvgLineTo(vg_, sx, sy - uSize - 2)
    nvgStrokeColor(vg_, nvgRGBA(120, 200, 120, 100))
    nvgStrokeWidth(vg_, 1.0)
    nvgStroke(vg_)
end

-- ===================== 夜晚叠加 =====================

local function drawNightOverlay(alpha)
    if alpha <= 0 then return end
    local c = Config.COLORS.NIGHT_OVL
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, screenW_, screenH_)
    nvgFillColor(vg_, nvgRGBA(c[1],c[2],c[3], math.floor(alpha * (c[4] or 140))))
    nvgFill(vg_)
end

-- ===================== 天空背景 =====================

local function drawSkyBg(skyColor)
    local c = skyColor or Config.COLORS.DAY_SKY
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, screenW_, screenH_)
    nvgFillColor(vg_, nvgRGBA(c[1],c[2],c[3],255))
    nvgFill(vg_)
end

-- ===================== 主绘制入口 =====================

-- previewState = { smoothCol, smoothRow, wallDragPath, wallDragActive }
-- canPlaceFn(btype, col, row) → bool
function MapRenderer.Draw(dt, buildings, soldiers, zombies,
                          nightAlpha, skyColor, hoveredTile, selectedBldType,
                          occupiedFn, canPlaceFn, previewState)
    if not vg_ then return end

    -- 平滑缩放：每帧向目标值靠近
    local t = math.min(1.0, dt * ZOOM_SMOOTH)
    zoom_ = zoom_ + (zoomTarget_ - zoom_) * t

    -- 更新动画计时器（供呼吸光/脉冲效果使用）
    animTimer_ = animTimer_ + (dt or 0.016)

    -- ── 渲染层级 ──────────────────────────────────
    drawSkyBg(skyColor)                          -- Layer -1: 天空背景
    drawGround()                                  -- Layer 0:  地面底图

    -- 查找 HQ 位置，用于密度分层和平台定位
    local hqCX, hqCY = nil, nil
    if buildings then
        for _, b in ipairs(buildings) do
            if b.type == "HQ" then
                local cfg = Config.BUILDINGS["HQ"]
                if cfg then
                    hqCX = b.col + cfg.size.w * 0.5
                    hqCY = b.row + cfg.size.h * 0.5
                end
                break
            end
        end
    end

    drawGroundDensityMask(hqCX, hqCY)            -- Layer 1:  地面细节密度蒙版
    drawHQGround(buildings)                       -- Layer 2:  HQ 地面底座贴图
    drawDecals(dt)                                -- Layer 3:  地面贴花（血迹/烧痕/感染）

    -- 建造预览
    if selectedBldType then
        local ps = previewState or {}
        if ps.wallDragActive and ps.wallDragPath then
            -- 围墙拖拽：绘制路径预览
            drawWallDragPreview(ps.wallDragPath, canPlaceFn)
        elseif hoveredTile then
            -- 普通建筑：绘制单格/多格幽灵预览（使用平滑坐标）
            local sc = ps.smoothCol or hoveredTile.col
            local sr = ps.smoothRow or hoveredTile.row
            drawBuildPreview(sc, sr, selectedBldType, canPlaceFn, occupiedFn)
        end
    end

    -- Layer 4-6: 建筑 + 士兵 + 僵尸 混合 Z 排序（画家算法）
    -- 按 sortKey 升序绘制，保证前景遮住后景，实现真正的 2.5D 层次感
    drawSceneZSorted(buildings, soldiers, zombies, nightAlpha)

    drawEffects(dt)                               -- Layer 7:  特效（爆炸/命中）
    drawNightOverlay(nightAlpha)                  -- Layer 8:  夜晚全屏叠加

    -- Layer 9: 单位 hover tooltip（最顶层，不受夜晚遮罩影响）
    local ps = previewState or {}
    local msx = ps.mouseScreenX or 0
    local msy = ps.mouseScreenY or 0
    if msx > 0 and msy > 0 and soldiers then
        -- 找最近的农民（屏幕像素距离 < 30px）
        local bestSoldier = nil
        local bestDist    = 30 * zoom_ + 12
        for _, s in ipairs(soldiers) do
            if s.type == "FARMER" then
                local sx, sy = MapRenderer.IsoToScreen(s.col, s.row)
                local dx = sx - msx
                local dy = sy - msy
                local d  = math.sqrt(dx*dx + dy*dy)
                if d < bestDist then
                    bestDist    = d
                    bestSoldier = s
                end
            end
        end
        if bestSoldier then
            drawFarmerTooltip(bestSoldier, msx, msy)
        end
    end
end

-- ===================== 相机拖拽 =====================

function MapRenderer.BeginDrag(mx, my)
    dragging_ = true
    dragSX_ = mx;  dragSY_ = my
    dragCX_ = camX_; dragCY_ = camY_
end

function MapRenderer.UpdateDrag(mx, my)
    if not dragging_ then return end
    camX_ = dragCX_ + (mx - dragSX_)
    camY_ = dragCY_ + (my - dragSY_)
end

function MapRenderer.EndDrag()
    dragging_ = false
end

return MapRenderer
