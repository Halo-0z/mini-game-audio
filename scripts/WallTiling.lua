-- =====================================================
-- WallTiling.lua  围墙自动拼接系统 V1.5
-- =====================================================
-- Bitmask 定义（遵循用户规格）：
--   up    = bit 0 (值 1) — 上/北 (row-1)
--   right = bit 1 (值 2) — 右/东 (col+1)
--   down  = bit 2 (值 4) — 下/南 (row+1)
--   left  = bit 3 (值 8) — 左/西 (col-1)
--
-- mask = (up<<0) | (right<<1) | (down<<2) | (left<<3)
-- 结果 0~15，对应 16 种素材
-- =====================================================
-- Bitmask → 贴图 Key 映射（WALL_<mask>）：
--   0  = wall_single       8  = wall_end_W
--   1  = wall_end_N        9  = wall_corner_NW
--   2  = wall_end_E        10 = wall_h
--   3  = wall_corner_NE    11 = wall_T_S
--   4  = wall_end_S        12 = wall_corner_SW
--   5  = wall_v            13 = wall_T_E
--   6  = wall_corner_SE    14 = wall_T_N
--   7  = wall_T_W          15 = wall_cross
-- =====================================================

local WallTiling = {}

-- 四方向检测配置
local DIRS = {
    { dc = 0,  dr = -1, bit = 1  },   -- up/北   bit 0
    { dc = 1,  dr =  0, bit = 2  },   -- right/东 bit 1
    { dc = 0,  dr =  1, bit = 4  },   -- down/南 bit 2
    { dc = -1, dr =  0, bit = 8  },   -- left/西 bit 3
}

-- 装饰类型列表（顺序固定，用于哈希取模）
local DECO_KEYS = { "WALL_DECO_WIRE", "WALL_DECO_LIGHT", "WALL_DECO_BANNER", "WALL_DECO_DAMAGE" }

-- ──────────────────────────────────────────────────
-- 计算单格 bitmask（需要 isWallFn(col, row) → bool）
-- ──────────────────────────────────────────────────
function WallTiling.ComputeMask(col, row, isWallFn)
    local mask = 0
    for _, d in ipairs(DIRS) do
        if isWallFn(col + d.dc, row + d.dr) then
            mask = mask | d.bit
        end
    end
    return mask
end

-- ──────────────────────────────────────────────────
-- 统计 mask 中连接数量（1~4）
-- ──────────────────────────────────────────────────
function WallTiling.CountConnections(mask)
    local n = 0
    if (mask & 1)  > 0 then n = n + 1 end
    if (mask & 2)  > 0 then n = n + 1 end
    if (mask & 4)  > 0 then n = n + 1 end
    if (mask & 8)  > 0 then n = n + 1 end
    return n
end

-- ──────────────────────────────────────────────────
-- 判断是否为"节点"（角柱位置）：连接数≥2 且非直线
--   直线：mask==5（N+S 纵）或 mask==10（E+W 横）
-- ──────────────────────────────────────────────────
function WallTiling.IsJunction(mask)
    if mask == nil then return false end
    local n = WallTiling.CountConnections(mask)
    if n < 2 then return false end
    if mask == 5 or mask == 10 then return false end  -- 纯直线不算节点
    return true
end

-- ──────────────────────────────────────────────────
-- 计算直线段长度（仅对 mask==5 或 mask==10 有意义）
--   isWallFn       : function(col,row)→bool
--   getWallMaskAt  : function(col,row)→mask|nil
-- 返回该格所在直线段的总格数
-- ──────────────────────────────────────────────────
function WallTiling.GetStraightRunLen(col, row, mask, isWallFn, getWallMaskAt)
    if mask ~= 5 and mask ~= 10 then return 0 end
    -- mask 5 = N+S → 沿 dr 方向延伸；mask 10 = E+W → 沿 dc 方向延伸
    local dc = (mask == 10) and 1 or 0
    local dr = (mask == 5)  and 1 or 0

    local count = 1
    -- 正向延伸
    local c, r = col + dc, row + dr
    while isWallFn(c, r) and getWallMaskAt(c, r) == mask do
        count = count + 1
        c = c + dc; r = r + dr
    end
    -- 反向延伸
    c, r = col - dc, row - dr
    while isWallFn(c, r) and getWallMaskAt(c, r) == mask do
        count = count + 1
        c = c - dc; r = r - dr
    end
    return count
end

-- ──────────────────────────────────────────────────
-- 确定性装饰 key（按坐标哈希，总概率约 20%）
-- 只对位于长直线中间位置的墙格返回装饰 key
-- 返回 nil 表示不加装饰
-- ──────────────────────────────────────────────────
function WallTiling.GetDecoKey(col, row)
    -- 简单整数哈希（Lua 5.4 位运算，无溢出问题）
    local h = math.abs((col * 73856093) ~ (row * 19349663)) % 100
    if h >= 80 then  -- 20% 概率
        return DECO_KEYS[(h % 4) + 1]
    end
    return nil
end

-- ──────────────────────────────────────────────────
-- 刷新指定位置及其四个邻格的围墙 bitmask + runLen
-- 在放置/拆除围墙后调用
--   buildings     : BuildingManager.GetBuildings()
--   isWallFn      : function(col,row)→bool
--   getWallMaskAt : function(col,row)→mask（可 nil，不传则跳过 runLen 计算）
--   changedCol/Row: 刚发生变化的格子坐标
-- ──────────────────────────────────────────────────
function WallTiling.RefreshAround(buildings, isWallFn, changedCol, changedRow, getWallMaskAt)
    local targets = {
        { changedCol,     changedRow     },
        { changedCol,     changedRow - 1 },
        { changedCol + 1, changedRow     },
        { changedCol,     changedRow + 1 },
        { changedCol - 1, changedRow     },
    }
    local targetSet = {}
    for _, pos in ipairs(targets) do
        targetSet[pos[1] .. "," .. pos[2]] = true
    end

    for _, b in ipairs(buildings) do
        if b.type == "WALL" then
            local key = b.col .. "," .. b.row
            if targetSet[key] then
                b.wallMask = WallTiling.ComputeMask(b.col, b.row, isWallFn)
                -- 更新直线段长度（需要 getWallMaskAt）
                if getWallMaskAt then
                    local mask = b.wallMask
                    if mask == 5 or mask == 10 then
                        b.wallRunLen = WallTiling.GetStraightRunLen(
                            b.col, b.row, mask, isWallFn, getWallMaskAt)
                    else
                        b.wallRunLen = 0
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────
-- 全量刷新所有围墙的 bitmask + runLen（初始化时用）
-- ──────────────────────────────────────────────────
function WallTiling.RefreshAll(buildings, isWallFn, getWallMaskAt)
    -- 先计算所有 mask
    for _, b in ipairs(buildings) do
        if b.type == "WALL" then
            b.wallMask = WallTiling.ComputeMask(b.col, b.row, isWallFn)
        end
    end
    -- 再计算 runLen（此时所有 mask 已就绪）
    if getWallMaskAt then
        for _, b in ipairs(buildings) do
            if b.type == "WALL" then
                local mask = b.wallMask
                if mask == 5 or mask == 10 then
                    b.wallRunLen = WallTiling.GetStraightRunLen(
                        b.col, b.row, mask, isWallFn, getWallMaskAt)
                else
                    b.wallRunLen = 0
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────
-- 根据 bitmask 返回对应的贴图 Key（用于 MapRenderer）
-- ──────────────────────────────────────────────────
function WallTiling.GetImageKey(mask)
    return "WALL_" .. (mask or 0)
end

return WallTiling
