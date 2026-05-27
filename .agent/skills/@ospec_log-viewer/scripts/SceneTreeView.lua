-- ============================================================================
-- 场景层级树视图 (SceneTreeView)
-- 功能：
--   1. 显示当前 3D 场景从 Scene 开始的所有子节点层级树
--   2. 每个节点显示：名称(类型)，可展开/折叠
--   3. 组件作为叶子节点显示在父节点下
--   4. 上半区域：可滚动的树列表（含锁定/显隐按钮）
--   5. 下半区域：选中节点/组件的属性详情面板（含编辑功能）
-- ============================================================================

local UI = require("urhox-libs/UI")

local SceneTreeView = {}

-- ============================================================================
-- 主题色（与 LogViewerUI 保持一致）
-- ============================================================================
local T = {
    TEXT_PRIMARY   = { 245, 230, 211, 255 },
    TEXT_SECONDARY = { 195, 175, 145, 255 },
    TEXT_HINT      = { 130, 115,  90, 255 },
    BG_DARK        = {  18,  14,  10, 255 },
    BG_CARD        = {  30,  26,  20, 255 },
    BG_ROW_HOVER   = {  45,  40,  32, 255 },
    BG_SELECTED    = {  55,  45,  25, 255 },
    BORDER         = {  80,  65,  45, 200 },
    ACCENT         = { 200, 160,  60, 255 },
    SECTION_BG     = {  25,  22,  16, 255 },
    SECTION_BORDER = {  60,  50,  38, 180 },
    COLOR_GREEN    = {  80, 200,  80, 255 },
    COLOR_RED      = { 200,  80,  80, 255 },
    COLOR_BLUE     = { 100, 160, 230, 255 },
    COLOR_YELLOW   = { 220, 180,  80, 255 },
    COLOR_CYAN     = { 100, 200, 200, 255 },
    COLOR_ORANGE   = { 230, 160,  60, 255 },
}

local ROW_H       = 30
local INDENT_PX   = 16
local FONT_FAMILY = "sans"
local FONT_SIZE   = 11

--- ApplyScale 占位：常量保持原始设计值，使用点通过 S() 包裹
--- （避免 S(FONT_SIZE) 双重缩放）
function SceneTreeView.ApplyScale() end

-- ============================================================================
-- 节点类型 emoji
-- ============================================================================
local NODE_EMOJI     = "\xE2\x97\x86"  -- ◆
local SCENE_EMOJI    = "\xF0\x9F\x8C\x8D"  -- 🌍
local COMP_EMOJI_MAP = {
    -- 渲染
    StaticModel      = "\xF0\x9F\x93\xA6",  -- 📦
    AnimatedModel    = "\xF0\x9F\x8F\x83",  -- 🏃
    AnimationController = "\xF0\x9F\x8E\xAC", -- 🎬
    BillboardSet     = "\xF0\x9F\x93\x8B",  -- 📋
    ParticleEmitter  = "\xE2\x9C\xA8",      -- ✨
    CustomGeometry   = "\xF0\x9F\x94\xB6",  -- 🔶
    DecalSet         = "\xF0\x9F\x8E\xA8",  -- 🎨
    Terrain          = "\xE2\x9B\xB0",       -- ⛰
    Skybox           = "\xE2\x98\x80",       -- ☀
    -- 物理
    RigidBody        = "\xE2\x9A\x99",       -- ⚙
    CollisionShape   = "\xF0\x9F\x9B\xA1",  -- 🛡
    RigidBody2D      = "\xE2\x9A\x99",       -- ⚙
    CollisionBox2D   = "\xF0\x9F\x9B\xA1",  -- 🛡
    CollisionCircle2D= "\xF0\x9F\x9B\xA1",  -- 🛡
    CollisionPolygon2D="\xF0\x9F\x9B\xA1",  -- 🛡
    CollisionEdge2D  = "\xF0\x9F\x9B\xA1",  -- 🛡
    CollisionChain2D = "\xF0\x9F\x9B\xA1",  -- 🛡
    -- 光源
    Light            = "\xF0\x9F\x92\xA1",  -- 💡
    Zone             = "\xF0\x9F\x8C\xAB",  -- 🌫
    -- 相机
    Camera           = "\xF0\x9F\x93\xB7",  -- 📷
    -- 音频
    SoundSource      = "\xF0\x9F\x94\x8A",  -- 🔊
    SoundSource3D    = "\xF0\x9F\x94\x8A",  -- 🔊
    SoundListener    = "\xF0\x9F\x91\x82",  -- 👂
    -- 2D
    StaticSprite2D   = "\xF0\x9F\x96\xBC",  -- 🖼
    AnimatedSprite2D = "\xF0\x9F\x8E\x9E",  -- 🎞
    -- 脚本
    LuaScriptInstance= "\xF0\x9F\x93\x9C",  -- 📜
    ScriptInstance   = "\xF0\x9F\x93\x9C",  -- 📜
    -- 导航
    Navigable        = "\xF0\x9F\x97\xBA",  -- 🗺
    NavigationMesh   = "\xF0\x9F\x97\xBA",  -- 🗺
    CrowdManager     = "\xF0\x9F\x91\xA5",  -- 👥
    -- 网络
    NetworkPriority  = "\xF0\x9F\x93\xA1",  -- 📡
    -- Octree
    Octree           = "\xF0\x9F\x8C\xB2",  -- 🌲
    DebugRenderer    = "\xF0\x9F\x94\x8D",  -- 🔍
    PhysicsWorld     = "\xE2\x9A\x99",       -- ⚙
    PhysicsWorld2D   = "\xE2\x9A\x99",       -- ⚙
}
local DEFAULT_COMP_EMOJI = "\xF0\x9F\x94\xA7"  -- 🔧

-- ============================================================================
-- 光源类型映射
-- ============================================================================
local LIGHT_TYPE_NAMES = { [0] = "Directional", [1] = "Spot", [2] = "Point" }

-- ============================================================================
-- 内部状态
-- ============================================================================
local parentContainer_ = nil
local treeScroll_      = nil
local detailScroll_    = nil
local treeInner_       = nil
local detailInner_     = nil
local expanded_        = {}    -- path -> bool
local lockedPaths_     = {}    -- path -> bool  锁定状态
local selectedItem_    = nil   -- 当前选中的 node 或 component
local selectedPath_    = ""    -- 当前选中的 path
local selectedIsComp_  = false -- 选中的是否是组件
-- 颜色选择器状态
local expandedColorKey_  = nil   -- 当前展开颜色选择器的 key（nil = 无展开）
local expandedTreeNodes_ = {}    -- 资源树展开状态 { ["geom_0"]=true, ["mat_0"]=true, ... }
local previewTexKey_     = nil   -- 当前预览大图的贴图 key（nil = 无预览）
-- 搜索过滤
local filterText_           = ""   -- 当前搜索关键字
-- 自动刷新
local AUTO_REFRESH_INTERVAL = 2.0
local autoRefresh_          = false
local autoRefreshTimer_     = 0
local autoRefreshBtn_       = nil
local refreshBtn_           = nil
local tabActive_            = false

-- 悬浮摘要缓存（避免每0.5秒全场景递归遍历）
local SUMMARY_CACHE_INTERVAL = 2.0
local lastSummaryTime_       = -999
local cachedSummary_         = { totalNodes = 0, totalComps = 0, maxDepth = 0, disabledCount = 0 }

-- ============================================================================
-- 常见组件类型列表（模块级常量，用于逐类型查询）
-- ============================================================================
local KNOWN_COMP_TYPES = {
    "Octree", "DebugRenderer", "PhysicsWorld", "PhysicsWorld2D",
    "Camera", "Light", "Zone", "Skybox", "Terrain",
    "StaticModel", "AnimatedModel", "AnimationController",
    "CustomGeometry", "BillboardSet", "ParticleEmitter", "DecalSet",
    "RigidBody", "CollisionShape",
    "RigidBody2D", "CollisionBox2D", "CollisionCircle2D",
    "CollisionPolygon2D", "CollisionEdge2D", "CollisionChain2D",
    "StaticSprite2D", "AnimatedSprite2D",
    "SoundSource", "SoundSource3D", "SoundListener",
    "LuaScriptInstance", "ScriptInstance",
    "Navigable", "NavigationMesh", "CrowdManager", "NetworkPriority",
}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 安全检查 node/component 是否有效
local function isAlive(obj)
    if not obj then return false end
    local ok = pcall(function() local _ = obj:GetTypeName() end)
    return ok
end

local function fmtVec3(v)
    if not v then return "nil" end
    return string.format("(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
end

local function fmtQuat(q)
    if not q then return "nil" end
    local ok, euler = pcall(function() return q:EulerAngles() end)
    if not ok or not euler then return "nil" end
    return string.format("(%.1f, %.1f, %.1f)", euler.x, euler.y, euler.z)
end

local function fmtColor(c)
    if not c then return "nil" end
    return string.format("(%.2f, %.2f, %.2f, %.2f)", c.r, c.g, c.b, c.a)
end

local function fmtFloat(v, decimals)
    if v == nil then return "nil" end
    return string.format("%." .. (decimals or 2) .. "f", v)
end

local function fmtBool(v)
    if v == nil then return "nil" end
    return v and "true" or "false"
end

local function makePathKey(parentPath, index)
    if parentPath == "" then return tostring(index) end
    return parentPath .. "." .. tostring(index)
end

--- 安全获取属性值
local function safeGet(obj, getter, ...)
    local args = { ... }
    local ok, val = pcall(function() return getter(obj, table.unpack(args)) end)
    if ok then return val end
    return nil
end

--- 获取节点标签
local function getNodeLabel(node)
    local name = ""
    pcall(function() name = node:GetName() end)
    local id = 0
    pcall(function() id = node:GetID() end)
    if name and name ~= "" then
        return NODE_EMOJI .. " " .. name
    end
    return NODE_EMOJI .. " Node #" .. tostring(id)
end

--- 获取组件标签
local function getCompLabel(comp)
    local typeName = "Component"
    pcall(function() typeName = comp:GetTypeName() end)
    local emoji = COMP_EMOJI_MAP[typeName] or DEFAULT_COMP_EMOJI
    return emoji .. " " .. typeName
end

-- ============================================================================
-- 树构建
-- ============================================================================

--- 获取场景（从 renderer viewport 获取，不依赖全局变量）
local function getScene()
    local vp = renderer:GetViewport(0)
    if vp then
        local s = vp:GetScene()
        if s then return s end
    end
    return nil
end

--- 收集节点的所有组件（安全迭代，逐类型查询）
local function getNodeComponents(node)
    local comps = {}
    local ok, num = pcall(function() return node:GetNumComponents() end)
    if not ok or not num or num == 0 then return comps end

    local seen = {}
    for _, typeName in ipairs(KNOWN_COMP_TYPES) do
        local ok3, cs = pcall(function() return node:GetComponents(typeName, false) end)
        if ok3 and cs then
            for j = 1, #cs do
                local c = cs[j]
                local cid = 0
                pcall(function() cid = c:GetID() end)
                if not seen[cid] then
                    seen[cid] = true
                    comps[#comps + 1] = c
                end
            end
        end
    end
    return comps
end

--- 递归构建树行数据
local function buildTreeRows(node, depth, parentPath, rows, showComps)
    local children = {}
    pcall(function() children = node:GetChildren(false) end)

    for i = 1, #children do
        local child = children[i]
        local path = makePathKey(parentPath, i)

        local childChildren = {}
        pcall(function() childChildren = child:GetChildren(false) end)
        local comps = showComps and getNodeComponents(child) or {}
        local hasChildren = #childChildren > 0 or #comps > 0
        local isExpanded = expanded_[path] == true
        local isEnabled = true
        pcall(function() isEnabled = child:IsEnabled() end)

        rows[#rows + 1] = {
            depth       = depth,
            item        = child,
            path        = path,
            hasChildren = hasChildren,
            isExpanded  = isExpanded,
            isComp      = false,
            isEnabled   = isEnabled,
            isRoot      = false,
        }

        if hasChildren and isExpanded then
            for ci = 1, #comps do
                local compPath = path .. ".C" .. ci
                local compEnabled = true
                pcall(function() compEnabled = comps[ci]:IsEnabled() end)
                rows[#rows + 1] = {
                    depth       = depth + 1,
                    item        = comps[ci],
                    path        = compPath,
                    hasChildren = false,
                    isExpanded  = false,
                    isComp      = true,
                    isEnabled   = compEnabled,
                    isRoot      = false,
                }
            end
            buildTreeRows(child, depth + 1, path, rows, showComps)
        end
    end
end

--- 递归收集所有子路径（含组件路径，用于锁定/显隐级联）
local function collectChildPaths(node, parentPath, result)
    -- 收集当前节点的组件路径（与 buildTreeRows 一致，使用 getNodeComponents）
    local comps = getNodeComponents(node)
    for ci = 1, #comps do
        result[#result + 1] = parentPath .. ".C" .. ci
    end
    -- 收集子节点及其组件
    local children = {}
    pcall(function() children = node:GetChildren(false) end)
    for i = 1, #children do
        local path = makePathKey(parentPath, i)
        result[#result + 1] = path
        collectChildPaths(children[i], path, result)
    end
end



-- ============================================================================
-- 搜索过滤辅助
-- ============================================================================

--- 预扫描场景树，收集匹配搜索文本的路径及其祖先路径
--- @return table visible 需要显示的路径集合 (path->true)
--- @return table directMatch 直接命中的路径集合 (path->true)
local function preFilterScan(scn, filterLower)
    local directMatch = {}
    local visible     = {}

    local function scanNode(node, parentPath)
        local anyMatch = false
        local children = {}
        pcall(function() children = node:GetChildren(false) end)
        local comps = getNodeComponents(node)

        -- 检查组件
        for ci = 1, #comps do
            local compPath = parentPath .. ".C" .. ci
            local label = getCompLabel(comps[ci])
            if string.find(string.lower(label), filterLower, 1, true) then
                directMatch[compPath] = true
                visible[compPath] = true
                anyMatch = true
            end
        end

        -- 检查子节点（递归）
        for i = 1, #children do
            local child = children[i]
            local path = makePathKey(parentPath, i)
            local label = getNodeLabel(child)
            local selfMatch = string.find(string.lower(label), filterLower, 1, true) ~= nil
            local descendantMatch = scanNode(child, path)
            if selfMatch then
                directMatch[path] = true
                visible[path] = true
                anyMatch = true
            elseif descendantMatch then
                visible[path] = true
                anyMatch = true
            end
        end

        return anyMatch
    end

    local rootMatch = scanNode(scn, "S")
    if rootMatch then visible["S"] = true end

    return visible, directMatch
end

--- 构建过滤后的树行（仅保留可见路径，自动展开祖先节点）
local function buildFilteredTreeRows(node, depth, parentPath, rows, showComps, visible, directMatch)
    local children = {}
    pcall(function() children = node:GetChildren(false) end)

    for i = 1, #children do
        local child = children[i]
        local path = makePathKey(parentPath, i)

        if not visible[path] then goto continue end

        local childChildren = {}
        pcall(function() childChildren = child:GetChildren(false) end)
        local comps = showComps and getNodeComponents(child) or {}

        -- 检查在过滤视图中是否有可见子项
        local hasVisibleChild = false
        for j = 1, #childChildren do
            if visible[makePathKey(path, j)] then hasVisibleChild = true; break end
        end
        if not hasVisibleChild and showComps then
            for ci = 1, #comps do
                if visible[path .. ".C" .. ci] then hasVisibleChild = true; break end
            end
        end

        local isEnabled = true
        pcall(function() isEnabled = child:IsEnabled() end)

        rows[#rows + 1] = {
            depth       = depth,
            item        = child,
            path        = path,
            hasChildren = hasVisibleChild,
            isExpanded  = hasVisibleChild,
            isComp      = false,
            isEnabled   = isEnabled,
            isRoot      = false,
            isMatch     = directMatch[path] or false,
        }

        -- 组件：仅显示匹配的
        if showComps then
            for ci = 1, #comps do
                local compPath = path .. ".C" .. ci
                if visible[compPath] then
                    local compEnabled = true
                    pcall(function() compEnabled = comps[ci]:IsEnabled() end)
                    rows[#rows + 1] = {
                        depth       = depth + 1,
                        item        = comps[ci],
                        path        = compPath,
                        hasChildren = false,
                        isExpanded  = false,
                        isComp      = true,
                        isEnabled   = compEnabled,
                        isRoot      = false,
                        isMatch     = directMatch[compPath] or false,
                    }
                end
            end
        end

        buildFilteredTreeRows(child, depth + 1, path, rows, showComps, visible, directMatch)

        ::continue::
    end
end

-- ============================================================================
-- 详情面板
-- ============================================================================
local rebuildTree   -- forward declare
local rebuildDetail -- forward declare

local function addDetailRow(label, value, valueColor)
    if not detailInner_ then return end
    detailInner_:AddChild(UI.Panel {
        width = "100%", height = S(26),
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = S(10),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 80 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            UI.Label {
                text = tostring(value), fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = valueColor or T.TEXT_PRIMARY,
                flexGrow = 1, flexShrink = 1,
                numberOfLines = 1, overflow = "hidden",
            },
        },
    })
end

local function addDetailSection(title)
    if not detailInner_ then return end
    detailInner_:AddChild(UI.Panel {
        width = "100%", height = S(28),
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = S(8),
        backgroundColor = T.SECTION_BG,
        borderBottomWidth = S(1), borderColor = T.SECTION_BORDER,
        children = {
            UI.Label {
                text = title, fontSize = S(12), fontFamily = FONT_FAMILY,
                fontColor = T.ACCENT,
            },
        },
    })
end

-- ============================================================================
-- 通用单轴编辑行:  AxisLabel [-] [TextField] [+]
-- ============================================================================
local AXIS_COLORS = {
    X = { 220, 80, 80, 255 },
    Y = { 80, 200, 80, 255 },
    Z = { 100, 140, 230, 255 },
}

--- 创建单轴编辑控件（内联，固定宽度）
---@param axisName string "X"|"Y"|"Z"
---@param value number 当前值
---@param onApply fun(newVal: number) 应用新值回调
---@param step number 微调步长
local function makeAxisWidget(axisName, value, onApply, step)
    step = step or 0.5
    local isLocked = lockedPaths_[selectedPath_] == true
    local axisColor = AXIS_COLORS[axisName] or T.TEXT_PRIMARY
    local valStr = string.format("%.2f", value)

    return UI.Panel {
        width = S(120), height = S(22),
        flexDirection = "row", alignItems = "center",
        flexShrink = 0,
        children = {
            -- 轴标签
            UI.Label {
                text = axisName, fontSize = S(10), fontFamily = FONT_FAMILY,
                fontColor = axisColor, width = S(12), flexShrink = 0,
                fontWeight = "bold",
            },
            -- 减少按钮
            UI.Button {
                text = "-", fontSize = S(11), fontFamily = FONT_FAMILY,
                height = S(18), width = S(18), borderRadius = S(3),
                variant = "ghost", paddingHorizontal = 0,
                disabled = isLocked,
                backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                onClick = isLocked and nil or function(self)
                    pcall(function() onApply(value - step) end)
                    rebuildDetail()
                end,
            },
            -- 数值输入框
            UI.TextField {
                value = valStr,
                fontSize = S(10), fontFamily = FONT_FAMILY,
                height = S(18), flexGrow = 1,
                paddingHorizontal = S(2),
                disabled = isLocked,
                backgroundColor = isLocked and { 22, 18, 14, 255 } or { 35, 30, 22, 255 },
                borderWidth = S(1),
                borderColor = isLocked and { 50, 42, 30, 150 } or { 70, 58, 38, 200 },
                borderRadius = S(3),
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_PRIMARY,
                onSubmit = isLocked and nil or function(self, text)
                    local num = tonumber(text)
                    if num then
                        pcall(function() onApply(num) end)
                        rebuildDetail()
                    end
                end,
            },
            -- 增加按钮
            UI.Button {
                text = "+", fontSize = S(11), fontFamily = FONT_FAMILY,
                height = S(18), width = S(18), borderRadius = S(3),
                variant = "ghost", paddingHorizontal = 0,
                disabled = isLocked,
                backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                onClick = isLocked and nil or function(self)
                    pcall(function() onApply(value + step) end)
                    rebuildDetail()
                end,
            },
        },
    }
end

--- 添加可编辑的 Vec3（标签 + 3轴内联，自动换行）
local function addEditableVec3Row(label, vec, setter, step)
    if not detailInner_ or not vec then
        addDetailRow(label, fmtVec3(vec))
        return
    end
    step = step or 0.5
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            makeAxisWidget("X", vec.x, function(v)
                setter(Vector3(v, vec.y, vec.z))
            end, step),
            makeAxisWidget("Y", vec.y, function(v)
                setter(Vector3(vec.x, v, vec.z))
            end, step),
            makeAxisWidget("Z", vec.z, function(v)
                setter(Vector3(vec.x, vec.y, v))
            end, step),
        },
    })
end

--- 添加可编辑的 Vec2（标签 + 2轴内联，自动换行）
local function addEditableVec2Row(label, vec, setter, step)
    if not detailInner_ or not vec then
        addDetailRow(label, vec and string.format("(%.2f, %.2f)", vec.x, vec.y) or "nil")
        return
    end
    step = step or 0.5
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            makeAxisWidget("X", vec.x, function(v)
                setter(Vector2(v, vec.y))
            end, step),
            makeAxisWidget("Y", vec.y, function(v)
                setter(Vector2(vec.x, v))
            end, step),
        },
    })
end

--- 添加可编辑的 Quaternion（以欧拉角显示，标签 + 3轴内联，自动换行）
local function addEditableQuatRow(label, quat, setter, step)
    if not detailInner_ or not quat then
        addDetailRow(label, fmtQuat(quat))
        return
    end
    step = step or 5.0
    local ok, euler = pcall(function() return quat:EulerAngles() end)
    if not ok or not euler then
        addDetailRow(label, "nil")
        return
    end
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            makeAxisWidget("X", euler.x, function(v)
                pcall(function()
                    setter(Quaternion.new(v, euler.y, euler.z))
                end)
            end, step),
            makeAxisWidget("Y", euler.y, function(v)
                pcall(function()
                    setter(Quaternion.new(euler.x, v, euler.z))
                end)
            end, step),
            makeAxisWidget("Z", euler.z, function(v)
                pcall(function()
                    setter(Quaternion.new(euler.x, euler.y, v))
                end)
            end, step),
        },
    })
end

--- 创建浮点值编辑控件（内联，固定宽度，与 makeAxisWidget 风格一致）
local function makeFloatWidget(value, onApply, step)
    step = step or 0.1
    local isLocked = lockedPaths_[selectedPath_] == true
    local valStr = string.format("%.2f", value)

    return UI.Panel {
        width = S(120), height = S(22),
        flexDirection = "row", alignItems = "center",
        flexShrink = 0,
        children = {
            -- 减少按钮
            UI.Button {
                text = "-", fontSize = S(11), fontFamily = FONT_FAMILY,
                height = S(18), width = S(18), borderRadius = S(3),
                variant = "ghost", paddingHorizontal = 0,
                disabled = isLocked,
                backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                onClick = isLocked and nil or function(self)
                    pcall(function() onApply(value - step) end)
                    rebuildDetail()
                end,
            },
            -- 数值输入框
            UI.TextField {
                value = valStr,
                fontSize = S(10), fontFamily = FONT_FAMILY,
                height = S(18), flexGrow = 1,
                paddingHorizontal = S(2),
                disabled = isLocked,
                backgroundColor = isLocked and { 22, 18, 14, 255 } or { 35, 30, 22, 255 },
                borderWidth = S(1),
                borderColor = isLocked and { 50, 42, 30, 150 } or { 70, 58, 38, 200 },
                borderRadius = S(3),
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_PRIMARY,
                onSubmit = isLocked and nil or function(self, text)
                    local num = tonumber(text)
                    if num then
                        pcall(function() onApply(num) end)
                        rebuildDetail()
                    end
                end,
            },
            -- 增加按钮
            UI.Button {
                text = "+", fontSize = S(11), fontFamily = FONT_FAMILY,
                height = S(18), width = S(18), borderRadius = S(3),
                variant = "ghost", paddingHorizontal = 0,
                disabled = isLocked,
                backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                onClick = isLocked and nil or function(self)
                    pcall(function() onApply(value + step) end)
                    rebuildDetail()
                end,
            },
        },
    }
end

--- 添加可编辑的浮点值行（标签 + 固定宽度编辑控件，与坐标轴控件风格一致）
local function addEditableFloatRow(label, value, setter, step)
    if not detailInner_ then return end
    step = step or 0.1
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            makeFloatWidget(value, setter, step),
        },
    })
end

--- 添加可编辑的颜色行（色块预览 + hex 输入 + 点击展开 ColorPicker）
--- @param label string
--- @param color Color 引擎 Color 对象 (RGBA 0~1 浮点)
--- @param setter function(Color) 设置新颜色的回调
--- @param colorKey string 用于标识当前颜色选择器展开状态的唯一键
--- @param readOnly boolean|nil 只读模式（如有效颜色，不可编辑）
local function addEditableColorRow(label, color, setter, colorKey, readOnly)
    if not detailInner_ or not color then return end
    local r8 = math.floor(math.min(color.r * 255, 255))
    local g8 = math.floor(math.min(color.g * 255, 255))
    local b8 = math.floor(math.min(color.b * 255, 255))
    local a8 = math.floor(math.min(color.a * 255, 255))
    local hexStr = string.format("#%02X%02X%02X", r8, g8, b8)
    local isExpanded = (expandedColorKey_ == colorKey)
    local isLocked = readOnly or lockedPaths_[selectedPath_] == true

    -- 色块和文本引用（供 ColorPicker onChange 实时更新，不 rebuildDetail）
    local swatchRef_ = nil
    local infoRef_   = nil

    -- 主行：标签 + 色块 + hex
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            -- 色块预览（可点击展开 ColorPicker）
            (function()
                swatchRef_ = UI.Panel {
                    width = S(20), height = S(20),
                    borderRadius = S(3), borderWidth = S(1),
                    borderColor = isExpanded and T.COLOR_ORANGE or { 70, 58, 38, 200 },
                    backgroundColor = { r8, g8, b8, a8 },
                    cursor = isLocked and nil or "pointer",
                    onClick = isLocked and nil or function(self)
                        if expandedColorKey_ == colorKey then
                            expandedColorKey_ = nil
                        else
                            expandedColorKey_ = colorKey
                        end
                        rebuildDetail()
                    end,
                }
                return swatchRef_
            end)(),
            -- RGBA 文本
            (function()
                infoRef_ = UI.Label {
                    text = hexStr .. string.format("  (%.2f,%.2f,%.2f,%.2f)", color.r, color.g, color.b, color.a),
                    fontSize = S(9), fontFamily = FONT_FAMILY,
                    fontColor = T.TEXT_SECONDARY,
                    marginLeft = S(6), flexShrink = 1,
                }
                return infoRef_
            end)(),
        },
    })

    -- 展开的 ColorPicker
    if isExpanded and not isLocked then
        local ColorPicker = require("urhox-libs/UI/Widgets/ColorPicker")
        local cpSwatchRef = swatchRef_   -- 色块预览引用（onChange 时更新）
        ---@type UIElement|nil
        local cpHexRef    = nil         -- hex 输入框引用（onChange 时同步）
        local cpInfoRef   = infoRef_   -- RGBA 文本引用
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            paddingHorizontal = S(10), paddingTop = S(6), paddingBottom = S(14),
            backgroundColor = { 35, 30, 22, 255 },
            borderBottomWidth = S(1), borderColor = { 60, 50, 35, 150 },
            flexDirection = "column", gap = S(4),
            children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = "颜色选择 - " .. label,
                            fontSize = S(10), fontFamily = FONT_FAMILY,
                            fontColor = T.COLOR_ORANGE,
                        },
                        UI.Button {
                            text = "收起", fontSize = S(10), fontFamily = FONT_FAMILY,
                            height = S(22), paddingHorizontal = S(6), borderRadius = S(3),
                            variant = "ghost", fontColor = T.TEXT_HINT,
                            onClick = function(self)
                                expandedColorKey_ = nil
                                rebuildDetail()
                            end,
                        },
                    },
                },
                ColorPicker.WithAlpha {
                    value = { r = r8, g = g8, b = b8, a = a8 },
                    size = "sm",
                    pickerSize = S(140),
                    showInput = false,
                    presets = {
                        "#FFFFFF", "#F44336", "#E91E63", "#9C27B0",
                        "#3F51B5", "#2196F3", "#00BCD4", "#4CAF50",
                        "#FFEB3B", "#FF9800", "#FF5722", "#000000",
                    },
                    onChange = function(self, value)
                        local vr = math.floor(value.r)
                        local vg = math.floor(value.g)
                        local vb = math.floor(value.b)
                        local va = math.floor(value.a)
                        -- 应用颜色到组件
                        pcall(function() setter(Color(vr / 255, vg / 255, vb / 255, va / 255)) end)
                        -- 同步更新 hex 输入框（不 rebuildDetail，保持 ColorPicker 存活）
                        if cpHexRef then
                            cpHexRef:SetStyle({ value = string.format("#%02X%02X%02X%02X", vr, vg, vb, va) })
                        end
                        -- 同步更新色块预览
                        if cpSwatchRef then
                            cpSwatchRef:SetStyle({ backgroundColor = { vr, vg, vb, va } })
                        end
                        -- 同步更新 RGBA 文本
                        if cpInfoRef then
                            cpInfoRef:SetStyle({ text = string.format("(%.2f,%.2f,%.2f,%.2f)", vr/255, vg/255, vb/255, va/255) })
                        end
                    end,
                },
                -- HEX 输入框
                (function()
                    local initHex = string.format("#%02X%02X%02X%02X", r8, g8, b8, a8)
                    local hexRow = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = S(6),
                        width = "100%", paddingTop = S(4),
                        children = {
                            UI.Label {
                                text = "HEX:", fontSize = S(10), fontFamily = FONT_FAMILY,
                                fontColor = T.TEXT_SECONDARY, flexShrink = 0, width = S(32),
                            },
                            (function()
                                cpHexRef = UI.TextField {
                                    value = initHex,
                                    height = S(26), fontSize = S(11), fontFamily = FONT_FAMILY,
                                    borderRadius = S(3), flexGrow = 1, flexShrink = 1,
                                    backgroundColor = { 35, 30, 22, 255 },
                                    borderWidth = S(1), borderColor = { 70, 58, 38, 200 },
                                    paddingHorizontal = S(6),
                                    fontColor = T.TEXT_PRIMARY,
                                    onSubmit = function(self, text)
                                        local hex = text:gsub("^#", ""):upper()
                                        local nr, ng, nb, na
                                        if #hex == 8 then
                                            nr = tonumber(hex:sub(1, 2), 16)
                                            ng = tonumber(hex:sub(3, 4), 16)
                                            nb = tonumber(hex:sub(5, 6), 16)
                                            na = tonumber(hex:sub(7, 8), 16)
                                        elseif #hex == 6 then
                                            nr = tonumber(hex:sub(1, 2), 16)
                                            ng = tonumber(hex:sub(3, 4), 16)
                                            nb = tonumber(hex:sub(5, 6), 16)
                                            na = a8
                                        end
                                        if nr and ng and nb and na then
                                            pcall(function() setter(Color(nr/255, ng/255, nb/255, na/255)) end)
                                            self:SetStyle({ value = string.format("#%02X%02X%02X%02X", nr, ng, nb, na) })
                                            if cpSwatchRef then
                                                cpSwatchRef:SetStyle({ backgroundColor = { nr, ng, nb, na } })
                                            end
                                            if cpInfoRef then
                                                cpInfoRef:SetStyle({ text = string.format("(%.2f,%.2f,%.2f,%.2f)", nr/255, ng/255, nb/255, na/255) })
                                            end
                                        else
                                            self:SetStyle({ value = initHex })
                                        end
                                    end,
                                }
                                return cpHexRef
                            end)(),
                        },
                    }
                    return hexRow
                end)(),
            },
        })
    end
end

--- 添加可切换的布尔值行
local function addEditableBoolRow(label, value, setter)
    if not detailInner_ then return end
    local isLocked = lockedPaths_[selectedPath_] == true
    detailInner_:AddChild(UI.Panel {
        width = "100%", height = S(26),
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = S(10),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 80 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            UI.Label {
                text = fmtBool(value), fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = value and T.COLOR_GREEN or T.COLOR_RED,
                flexGrow = 1, flexShrink = 1,
            },
            UI.Button {
                text = value and "Off" or "On", fontSize = S(9), fontFamily = FONT_FAMILY,
                height = S(20), width = S(30), borderRadius = S(3),
                variant = "ghost", paddingHorizontal = 0,
                disabled = isLocked,
                backgroundColor = isLocked and { 30, 26, 20, 255 } or { 50, 35, 20, 255 },
                fontColor = isLocked and T.TEXT_HINT or T.COLOR_ORANGE,
                onClick = isLocked and nil or function(self)
                    pcall(function() setter(not value) end)
                    rebuildDetail()
                    rebuildTree()
                end,
            },
        },
    })
end

-- ============================================================================
-- 组件专属属性展示
-- ============================================================================

-- ── 贴图单元名称映射 ──
local TEX_UNIT_NAMES = {
    [0] = "Diffuse/Albedo",
    [1] = "Normal",
    [2] = "Specular/Metallic",
    [3] = "Emissive",
    [4] = "Environment",
}
local TEX_UNIT_COUNT = 8  -- 检查 0~7（覆盖常用贴图单元）

-- ── 顶点语义名称 ──
local SEM_NAMES = {
    { enum = "SEM_POSITION",     label = "Position" },
    { enum = "SEM_NORMAL",       label = "Normal" },
    { enum = "SEM_TANGENT",      label = "Tangent" },
    { enum = "SEM_TEXCOORD",     label = "UV" },
    { enum = "SEM_COLOR",        label = "Color" },
    { enum = "SEM_BLENDWEIGHTS", label = "BlendWeights" },
    { enum = "SEM_BLENDINDICES", label = "BlendIndices" },
}

--- 安全获取文件短名（去掉路径前缀）
local function shortName(fullPath)
    if not fullPath or fullPath == "" then return "(无)" end
    return fullPath:match("[^/\\]+$") or fullPath
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 资源关联树：Geom → Material → Texture / Shader（可折叠、可预览）
-- ═══════════════════════════════════════════════════════════════════════════

--- 树节点缩进颜色
local TREE_INDENT_COLORS = {
    { 90, 160, 220, 180 },   -- L1 蓝
    { 180, 140, 60, 160 },   -- L2 金
    { 120, 200, 140, 150 },  -- L3 绿
    { 180, 120, 180, 140 },  -- L4 紫
}

--- 渲染一条树节点行
--- @param depth number 缩进层级 (0=根)
--- @param icon string 图标
--- @param label string 标签
--- @param value string 值
--- @param opts table|nil { expandKey, expanded, valueColor, onClick, children }
local function addTreeRow(depth, icon, label, value, opts)
    if not detailInner_ then return end
    opts = opts or {}
    local indent = S(10) + depth * S(16)
    local barColor = TREE_INDENT_COLORS[math.min(depth + 1, #TREE_INDENT_COLORS)]
    local isExpandable = opts.expandKey ~= nil
    local isExpanded = opts.expanded or false

    -- 构建子元素数组，避免 nil 空洞（Lua 表首元素为 nil 会导致 #t 不确定）
    local rowChildren = {}
    if depth > 0 then
        rowChildren[#rowChildren + 1] = UI.Panel {
            width = S(2), height = "100%", position = "absolute",
            left = S(10) + (depth - 1) * S(16) + S(7),
            backgroundColor = barColor,
        }
    end
    rowChildren[#rowChildren + 1] = UI.Label {
        text = isExpandable and (isExpanded and "- " or "+ ") or "  ",
        fontSize = S(13), fontFamily = FONT_FAMILY,
        fontColor = isExpandable and T.ACCENT or T.TEXT_HINT,
        width = S(16), flexShrink = 0,
    }
    local iconFontSize = opts.iconSize or 10
    rowChildren[#rowChildren + 1] = UI.Label {
        text = icon .. " ", fontSize = S(iconFontSize), fontFamily = FONT_FAMILY,
        fontColor = T.TEXT_SECONDARY, flexShrink = 0,
    }
    rowChildren[#rowChildren + 1] = UI.Label {
        text = label, fontSize = S(10), fontFamily = FONT_FAMILY,
        fontColor = T.TEXT_SECONDARY, marginRight = S(6), flexShrink = 0,
    }
    rowChildren[#rowChildren + 1] = UI.Label {
        text = value, fontSize = S(10), fontFamily = FONT_FAMILY,
        fontColor = opts.valueColor or T.TEXT_PRIMARY,
        flexGrow = 1, flexShrink = 1,
        numberOfLines = 1, overflow = "hidden",
    }

    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", alignItems = "center",
        paddingLeft = indent, paddingRight = S(6), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
        cursor = isExpandable and "pointer" or nil,
        onClick = isExpandable and function(self)
            expandedTreeNodes_[opts.expandKey] = not expandedTreeNodes_[opts.expandKey]
            rebuildDetail()
        end or opts.onClick,
        children = rowChildren,
    })
end

--- 收集单个材质的贴图列表
local function collectTextures(mat)
    local textures = {}
    if not mat then return textures end
    for u = 0, TEX_UNIT_COUNT - 1 do
        local tex = nil
        pcall(function() tex = mat:GetTexture(u) end)
        if tex then
            local texName = ""
            pcall(function() texName = tex:GetName() end)
            local w, h = 0, 0
            pcall(function() w = tex:GetWidth(); h = tex:GetHeight() end)
            local sRGB = false
            pcall(function() sRGB = tex:GetSRGB() end)
            local levels = 0
            pcall(function() levels = tex:GetLevels() end)
            textures[#textures + 1] = {
                unit = u,
                unitName = TEX_UNIT_NAMES[u] or ("Unit " .. u),
                tex = tex,
                name = texName,
                width = w, height = h,
                sRGB = sRGB,
                levels = levels,
            }
        end
    end
    return textures
end

--- 收集单个材质的 Technique → Pass → Shader 信息
local function collectShaders(mat)
    local result = {}
    if not mat then return result end
    local numTech = 0
    pcall(function() numTech = mat:GetNumTechniques() end)
    for ti = 0, numTech - 1 do
        local tech = nil
        pcall(function() tech = mat:GetTechnique(ti) end)
        if tech then
            local techName = ""
            pcall(function() techName = tech:GetName() end)
            local passes = {}
            local passNames = { "base", "litbase", "light", "prepass", "material", "deferred", "depth", "shadow", "refract" }
            for _, pn in ipairs(passNames) do
                local hasP = false
                pcall(function() hasP = tech:HasPass(pn) end)
                if hasP then
                    local pass = nil
                    pcall(function() pass = tech:GetPass(pn) end)
                    if pass then
                        local vs, ps, vsDefines, psDefines = "", "", "", ""
                        pcall(function() vs = pass:GetVertexShader() end)
                        pcall(function() ps = pass:GetPixelShader() end)
                        pcall(function() vsDefines = pass:GetVertexShaderDefines() end)
                        pcall(function() psDefines = pass:GetPixelShaderDefines() end)
                        passes[#passes + 1] = {
                            name = pn, vs = vs, ps = ps,
                            vsDefines = vsDefines, psDefines = psDefines,
                        }
                    end
                end
            end
            result[#result + 1] = { techIdx = ti, name = techName, passes = passes }
        end
    end
    return result
end

--- 收集材质渲染属性（含编辑元数据）
--- type: "enum" | "bool" | "int" | "color"
local function collectMaterialProps(mat)
    local props = {}
    if not mat then return props end

    -- 剔除模式（enum）
    local cullMode = safeGet(mat, mat.GetCullMode)
    if cullMode ~= nil then
        local cullNames = { [0] = "None", [1] = "CCW", [2] = "CW" }
        props[#props + 1] = {
            label = "剔除模式", value = cullNames[cullMode] or tostring(cullMode),
            type = "enum", current = cullMode,
            options = { { v = 0, n = "None" }, { v = 1, n = "CCW" }, { v = 2, n = "CW" } },
            setter = function(v) mat:SetCullMode(v) end,
        }
    end

    -- 填充模式（enum）
    local fillMode = safeGet(mat, mat.GetFillMode)
    if fillMode ~= nil then
        local fillNames = { [0] = "Solid", [1] = "Wireframe", [2] = "Point" }
        props[#props + 1] = {
            label = "填充模式", value = fillNames[fillMode] or tostring(fillMode),
            type = "enum", current = fillMode,
            options = { { v = 0, n = "Solid" }, { v = 1, n = "Wireframe" }, { v = 2, n = "Point" } },
            setter = function(v) mat:SetFillMode(v) end,
        }
    end

    -- 渲染顺序（int）
    local renderOrder = safeGet(mat, mat.GetRenderOrder)
    if renderOrder then
        props[#props + 1] = {
            label = "渲染顺序", value = tostring(renderOrder),
            type = "int", current = renderOrder,
            setter = function(v) mat:SetRenderOrder(v) end,
        }
    end

    -- AlphaToCoverage（bool）
    local alphaToCov = safeGet(mat, mat.GetAlphaToCoverage)
    if alphaToCov ~= nil then
        props[#props + 1] = {
            label = "AlphaToCov", value = fmtBool(alphaToCov),
            type = "bool", current = alphaToCov,
            setter = function(v) mat:SetAlphaToCoverage(v) end,
        }
    end

    -- 遮挡（bool）
    local occlusion = safeGet(mat, mat.GetOcclusion)
    if occlusion ~= nil then
        props[#props + 1] = {
            label = "遮挡", value = fmtBool(occlusion),
            type = "bool", current = occlusion,
            setter = function(v) mat:SetOcclusion(v) end,
        }
    end

    -- 行抗锯齿（bool）
    local lineAA = safeGet(mat, mat.GetLineAntiAlias)
    if lineAA ~= nil then
        props[#props + 1] = {
            label = "线抗锯齿", value = fmtBool(lineAA),
            type = "bool", current = lineAA,
            setter = function(v) mat:SetLineAntiAlias(v) end,
        }
    end

    -- 尝试探测常见 Shader 参数（颜色类）
    local shaderColorParams = {
        { name = "MatDiffColor",     label = "漫反射色" },
        { name = "MatSpecColor",     label = "高光色" },
        { name = "MatEmissiveColor", label = "自发光色" },
    }
    for _, sp in ipairs(shaderColorParams) do
        local ok, val = pcall(function() return mat:GetShaderParameter(sp.name) end)
        if ok and val then
            -- Variant → 颜色 (尝试 GetColor)
            local cOk, c = pcall(function() return val:GetColor() end)
            if cOk and c then
                props[#props + 1] = {
                    label = sp.label, value = string.format("%.2f,%.2f,%.2f,%.2f", c.r, c.g, c.b, c.a),
                    type = "color", current = c, paramName = sp.name,
                    setter = function(newColor)
                        pcall(function() mat:SetShaderParameter(sp.name, Variant(newColor)) end)
                    end,
                }
            end
        end
    end

    -- 尝试探测 Roughness / Metallic 等浮点参数
    local shaderFloatParams = {
        { name = "Roughness",  label = "粗糙度" },
        { name = "Metallic",   label = "金属度" },
    }
    for _, sp in ipairs(shaderFloatParams) do
        local ok, val = pcall(function() return mat:GetShaderParameter(sp.name) end)
        if ok and val then
            local fOk, f = pcall(function() return val:GetFloat() end)
            if fOk and f then
                props[#props + 1] = {
                    label = sp.label, value = string.format("%.3f", f),
                    type = "float", current = f, paramName = sp.name,
                    setter = function(v)
                        pcall(function() mat:SetShaderParameter(sp.name, Variant(v)) end)
                    end,
                    step = 0.05, min = 0, max = 1,
                }
            end
        end
    end

    return props
end

--- 在树缩进中渲染可编辑属性行
local function addEditableTreeProp(depth, prop)
    if not detailInner_ then return end
    local indent = S(10) + depth * S(16)
    local barColor = TREE_INDENT_COLORS[math.min(depth + 1, #TREE_INDENT_COLORS)]

    if prop.type == "bool" then
        -- 布尔切换行
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingLeft = indent, paddingRight = S(6), paddingVertical = S(2),
            borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
            children = {
                depth > 0 and UI.Panel {
                    width = S(2), height = "100%", position = "absolute",
                    left = S(10) + (depth - 1) * S(16) + S(7), backgroundColor = barColor,
                } or nil,
                UI.Label { text = "  ", fontSize = S(9), width = S(14), flexShrink = 0 },
                UI.Label { text = "⚙️ ", fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_SECONDARY, flexShrink = 0 },
                UI.Label { text = prop.label, fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_HINT, width = S(68), flexShrink = 0 },
                UI.Label {
                    text = fmtBool(prop.current), fontSize = S(10), fontFamily = FONT_FAMILY,
                    fontColor = prop.current and T.COLOR_GREEN or T.COLOR_RED, flexGrow = 1,
                },
                UI.Button {
                    text = prop.current and "Off" or "On", fontSize = S(8), fontFamily = FONT_FAMILY,
                    height = S(18), width = S(28), borderRadius = S(3),
                    variant = "ghost", paddingHorizontal = 0,
                    backgroundColor = { 50, 35, 20, 255 }, fontColor = T.COLOR_ORANGE,
                    onClick = function(self)
                        pcall(function() prop.setter(not prop.current) end)
                        rebuildDetail()
                    end,
                },
            },
        })

    elseif prop.type == "enum" then
        -- 枚举循环切换
        local nextIdx = 0
        for oi, opt in ipairs(prop.options) do
            if opt.v == prop.current then nextIdx = oi % #prop.options + 1; break end
        end
        local nextOpt = prop.options[nextIdx] or prop.options[1]
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingLeft = indent, paddingRight = S(6), paddingVertical = S(2),
            borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
            children = {
                depth > 0 and UI.Panel {
                    width = S(2), height = "100%", position = "absolute",
                    left = S(10) + (depth - 1) * S(16) + S(7), backgroundColor = barColor,
                } or nil,
                UI.Label { text = "  ", fontSize = S(9), width = S(14), flexShrink = 0 },
                UI.Label { text = "⚙️ ", fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_SECONDARY, flexShrink = 0 },
                UI.Label { text = prop.label, fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_HINT, width = S(68), flexShrink = 0 },
                UI.Label {
                    text = prop.value, fontSize = S(10), fontFamily = FONT_FAMILY,
                    fontColor = T.COLOR_CYAN, flexGrow = 1,
                },
                UI.Button {
                    text = "→" .. nextOpt.n, fontSize = S(8), fontFamily = FONT_FAMILY,
                    height = S(18), paddingHorizontal = S(4), borderRadius = S(3),
                    variant = "ghost",
                    backgroundColor = { 50, 35, 20, 255 }, fontColor = T.COLOR_ORANGE,
                    onClick = function(self)
                        pcall(function() prop.setter(nextOpt.v) end)
                        rebuildDetail()
                    end,
                },
            },
        })

    elseif prop.type == "int" then
        -- 整数步进
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingLeft = indent, paddingRight = S(6), paddingVertical = S(2),
            borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
            children = {
                depth > 0 and UI.Panel {
                    width = S(2), height = "100%", position = "absolute",
                    left = S(10) + (depth - 1) * S(16) + S(7), backgroundColor = barColor,
                } or nil,
                UI.Label { text = "  ", fontSize = S(9), width = S(14), flexShrink = 0 },
                UI.Label { text = "⚙️ ", fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_SECONDARY, flexShrink = 0 },
                UI.Label { text = prop.label, fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_HINT, width = S(68), flexShrink = 0 },
                UI.Button {
                    text = "-", fontSize = S(10), fontFamily = FONT_FAMILY,
                    height = S(18), width = S(18), borderRadius = S(3), variant = "ghost",
                    backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                    onClick = function(self)
                        pcall(function() prop.setter(prop.current - 1) end)
                        rebuildDetail()
                    end,
                },
                UI.Label {
                    text = tostring(prop.current), fontSize = S(10), fontFamily = FONT_FAMILY,
                    fontColor = T.TEXT_PRIMARY, width = S(30), textAlign = "center",
                },
                UI.Button {
                    text = "+", fontSize = S(10), fontFamily = FONT_FAMILY,
                    height = S(18), width = S(18), borderRadius = S(3), variant = "ghost",
                    backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                    onClick = function(self)
                        pcall(function() prop.setter(prop.current + 1) end)
                        rebuildDetail()
                    end,
                },
            },
        })

    elseif prop.type == "float" then
        -- 浮点滑块式步进
        local step = prop.step or 0.1
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingLeft = indent, paddingRight = S(6), paddingVertical = S(2),
            borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
            children = {
                depth > 0 and UI.Panel {
                    width = S(2), height = "100%", position = "absolute",
                    left = S(10) + (depth - 1) * S(16) + S(7), backgroundColor = barColor,
                } or nil,
                UI.Label { text = "  ", fontSize = S(9), width = S(14), flexShrink = 0 },
                UI.Label { text = "🔢 ", fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_SECONDARY, flexShrink = 0 },
                UI.Label { text = prop.label, fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_HINT, width = S(68), flexShrink = 0 },
                UI.Button {
                    text = "-", fontSize = S(10), fontFamily = FONT_FAMILY,
                    height = S(18), width = S(18), borderRadius = S(3), variant = "ghost",
                    backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                    onClick = function(self)
                        local nv = math.max(prop.min or -999, prop.current - step)
                        pcall(function() prop.setter(nv) end)
                        rebuildDetail()
                    end,
                },
                UI.Label {
                    text = string.format("%.3f", prop.current), fontSize = S(10), fontFamily = FONT_FAMILY,
                    fontColor = T.COLOR_YELLOW, width = S(44), textAlign = "center",
                },
                UI.Button {
                    text = "+", fontSize = S(10), fontFamily = FONT_FAMILY,
                    height = S(18), width = S(18), borderRadius = S(3), variant = "ghost",
                    backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                    onClick = function(self)
                        local nv = math.min(prop.max or 999, prop.current + step)
                        pcall(function() prop.setter(nv) end)
                        rebuildDetail()
                    end,
                },
            },
        })

    elseif prop.type == "color" then
        -- 颜色预览 + 展开编辑器
        local c = prop.current
        local r255 = math.floor((c.r or 0) * 255 + 0.5)
        local g255 = math.floor((c.g or 0) * 255 + 0.5)
        local b255 = math.floor((c.b or 0) * 255 + 0.5)
        local a255 = math.floor((c.a or 1) * 255 + 0.5)
        local colorKey = "matcolor_" .. (prop.paramName or prop.label)
        local isExpanded = expandedTreeNodes_[colorKey]
        detailInner_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingLeft = indent, paddingRight = S(6), paddingVertical = S(2),
            borderBottomWidth = S(1), borderColor = { 40, 35, 28, 40 },
            cursor = "pointer",
            onClick = function(self)
                expandedTreeNodes_[colorKey] = not expandedTreeNodes_[colorKey]
                rebuildDetail()
            end,
            children = {
                depth > 0 and UI.Panel {
                    width = S(2), height = "100%", position = "absolute",
                    left = S(10) + (depth - 1) * S(16) + S(7), backgroundColor = barColor,
                } or nil,
                UI.Label {
                    text = isExpanded and "- " or "+ ", fontSize = S(13), fontFamily = FONT_FAMILY,
                    fontColor = T.ACCENT, width = S(16), flexShrink = 0,
                },
                UI.Label { text = "🎨 ", fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_SECONDARY, flexShrink = 0 },
                UI.Label { text = prop.label, fontSize = S(10), fontFamily = FONT_FAMILY, fontColor = T.TEXT_HINT, width = S(68), flexShrink = 0 },
                -- 色块
                UI.Panel {
                    width = S(16), height = S(16), borderRadius = S(3), borderWidth = S(1), marginRight = S(6), flexShrink = 0,
                    borderColor = { 80, 68, 48, 200 },
                    backgroundColor = { r255, g255, b255, a255 },
                },
                UI.Label {
                    text = string.format("%.2f, %.2f, %.2f", c.r, c.g, c.b),
                    fontSize = S(9), fontFamily = FONT_FAMILY, fontColor = T.TEXT_PRIMARY, flexGrow = 1,
                },
            },
        })
        -- 展开 RGBA 分量编辑
        if isExpanded then
            local channels = { { n = "R", k = "r" }, { n = "G", k = "g" }, { n = "B", k = "b" }, { n = "A", k = "a" } }
            for _, ch in ipairs(channels) do
                local cv = c[ch.k] or 0
                local chStep = 0.05
                local innerIndent = indent + S(16)
                detailInner_:AddChild(UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = innerIndent, paddingRight = S(6), paddingVertical = S(1),
                    borderBottomWidth = S(1), borderColor = { 40, 35, 28, 30 },
                    children = {
                        UI.Panel {
                            width = S(2), height = "100%", position = "absolute",
                            left = S(10) + depth * S(16) + S(7),
                            backgroundColor = TREE_INDENT_COLORS[math.min(depth + 2, #TREE_INDENT_COLORS)],
                        },
                        UI.Label {
                            text = ch.n, fontSize = S(10), fontFamily = FONT_FAMILY,
                            fontColor = T.TEXT_HINT, width = S(16), flexShrink = 0,
                        },
                        UI.Button {
                            text = "-", fontSize = S(10), fontFamily = FONT_FAMILY,
                            height = S(16), width = S(16), borderRadius = S(3), variant = "ghost",
                            backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                            onClick = function(self)
                                local nc = Color(c.r, c.g, c.b, c.a)
                                nc[ch.k] = math.max(0, cv - chStep)
                                pcall(function() prop.setter(nc) end)
                                rebuildDetail()
                            end,
                        },
                        -- 色值条（模拟进度）
                        UI.Panel {
                            height = S(10), flexGrow = 1, marginHorizontal = S(4),
                            borderRadius = S(5), backgroundColor = { 25, 22, 16, 255 },
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = string.format("%.0f%%", math.min(cv, 1) * 100),
                                    height = "100%", borderRadius = S(5),
                                    backgroundColor = ch.k == "r" and { 220, 80, 80, 255 }
                                        or ch.k == "g" and { 80, 200, 80, 255 }
                                        or ch.k == "b" and { 80, 120, 220, 255 }
                                        or { 180, 180, 180, 255 },
                                },
                            },
                        },
                        UI.Label {
                            text = string.format("%.2f", cv), fontSize = S(9), fontFamily = FONT_FAMILY,
                            fontColor = T.TEXT_PRIMARY, width = S(32), textAlign = "right", flexShrink = 0,
                        },
                        UI.Button {
                            text = "+", fontSize = S(10), fontFamily = FONT_FAMILY,
                            height = S(16), width = S(16), borderRadius = S(3), variant = "ghost",
                            backgroundColor = { 45, 38, 25, 255 }, fontColor = T.TEXT_SECONDARY,
                            onClick = function(self)
                                local nc = Color(c.r, c.g, c.b, c.a)
                                nc[ch.k] = math.min(ch.k == "a" and 1 or 10, cv + chStep)
                                pcall(function() prop.setter(nc) end)
                                rebuildDetail()
                            end,
                        },
                    },
                })
            end
        end

    else
        -- 只读回退
        addTreeRow(depth, "⚙️", prop.label, prop.value)
    end
end

--- 显示贴图预览大图面板
local function addTexturePreview(texInfo, previewKey)
    if not detailInner_ or not texInfo then return end
    local texPath = texInfo.name or ""
    local w, h = texInfo.width or 0, texInfo.height or 0

    -- 计算预览尺寸（最大宽度限制在面板内）
    local maxPreviewW = S(200)
    local previewW = math.min(w, maxPreviewW)
    local previewH = (w > 0 and h > 0) and math.floor(previewW * h / w) or previewW
    if previewH > S(200) then previewH = S(200); previewW = math.floor(previewH * w / h) end

    detailInner_:AddChild(UI.Panel {
        width = "100%",
        paddingHorizontal = S(20), paddingVertical = S(6),
        alignItems = "center",
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 60 },
        backgroundColor = { 20, 18, 14, 255 },
        children = {
            -- 棋盘格背景 + 图片
            UI.Panel {
                width = previewW + S(4), height = previewH + S(4),
                borderRadius = S(4), borderWidth = S(1),
                borderColor = { 80, 68, 48, 200 },
                backgroundColor = { 40, 36, 28, 255 },
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Panel {
                        width = previewW, height = previewH,
                        backgroundImage = texPath,
                        backgroundFit = "contain",
                    },
                },
            },
            -- 信息
            UI.Label {
                text = shortName(texPath) .. "  " .. w .. "x" .. h
                    .. (texInfo.sRGB and " sRGB" or "")
                    .. (texInfo.levels > 1 and (" Mip:" .. texInfo.levels) or ""),
                fontSize = S(9), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, marginTop = S(4), textAlign = "center",
            },
            -- 关闭按钮
            UI.Button {
                text = "关闭预览", fontSize = S(9), fontFamily = FONT_FAMILY,
                height = S(20), paddingHorizontal = S(12), marginTop = S(4),
                variant = "ghost", borderRadius = S(3),
                backgroundColor = { 50, 42, 30, 255 },
                fontColor = T.TEXT_SECONDARY,
                onClick = function(self)
                    previewTexKey_ = nil
                    rebuildDetail()
                end,
            },
        },
    })
end

-- (弹窗方案已移除，资源树直接内联渲染到详情面板)

--- 资源关联树：内联显示到详情面板（使用 addTreeRow / addTexturePreview）
--- 构建一行树节点的 UI.Panel（不 AddChild，仅返回 Panel）
local function showResourceTree(comp, mdl)
    if not detailInner_ or not comp or not mdl then return end
    local numGeom = 0
    pcall(function() numGeom = mdl:GetNumGeometries() end)
    if numGeom == 0 then return end
    local compNumGeom = safeGet(comp, comp.GetNumGeometries) or 0

    -- 总统计
    local sumVerts, sumTris, sumMats = 0, 0, 0
    for gi = 0, numGeom - 1 do
        local geom = nil
        pcall(function() geom = mdl:GetGeometry(gi, 0) end)
        if geom then
            local vc, ic = 0, 0
            pcall(function() vc = geom:GetVertexCount() end)
            pcall(function() ic = geom:GetIndexCount() end)
            sumVerts = sumVerts + vc
            sumTris = sumTris + math.floor(ic / 3)
        end
        local mat = nil
        if gi < compNumGeom then
            pcall(function() mat = comp:GetMaterial(gi) end)
        end
        if mat then sumMats = sumMats + 1 end
    end

    local summaryText = string.format("%d几何  %d顶点  %d三角  %d材质", numGeom, sumVerts, sumTris, sumMats)

    -- 使用已知可靠的 addDetailSection 做标题
    addDetailSection("📦 网格材质贴图  " .. summaryText)

    -- 逐行添加
    for gi = 0, numGeom - 1 do
        local geom = nil
        pcall(function() geom = mdl:GetGeometry(gi, 0) end)

        local vCount, iCount, tCount = 0, 0, 0
        if geom then
            pcall(function() vCount = geom:GetVertexCount() end)
            pcall(function() iCount = geom:GetIndexCount() end)
            tCount = math.floor(iCount / 3)
        end

        -- Geom 行（可展开）
        local geomKey = "rt_geom_" .. gi
        local geomExpanded = expandedTreeNodes_[geomKey]
        addTreeRow(0, "🔺", "Geom[" .. gi .. "]",
            string.format("顶点:%d  三角:%d", vCount, tCount),
            { expandKey = geomKey, expanded = geomExpanded, valueColor = T.COLOR_BLUE })

        if not geomExpanded then goto continue_geom end

        -- 顶点属性
        if geom then
            local attrs = {}
            local vb = nil
            pcall(function() vb = geom:GetVertexBuffer(0) end)
            if vb then
                for _, sem in ipairs(SEM_NAMES) do
                    local has = false
                    pcall(function()
                        local semVal = _G[sem.enum]
                        if semVal ~= nil then has = vb:HasElement(semVal) end
                    end)
                    if has then attrs[#attrs + 1] = sem.label end
                end
                if #attrs > 0 then
                    addTreeRow(1, "📋", "属性", table.concat(attrs, " | "))
                end
                local vSize = 0
                pcall(function() vSize = vb:GetVertexSize() end)
                if vSize > 0 then
                    addTreeRow(1, "📏", "步长", vSize .. " bytes/vertex")
                end
            end
            local ib = nil
            pcall(function() ib = geom:GetIndexBuffer() end)
            if ib then
                local iSize = 0
                pcall(function() iSize = ib:GetIndexSize() end)
                addTreeRow(1, "🔢", "索引", (iSize == 2) and "16-bit" or "32-bit")
            end
        end

        -- 关联材质
        if gi < compNumGeom then
            local mat = nil
            pcall(function() mat = comp:GetMaterial(gi) end)
            if mat then
                local matName = ""
                pcall(function() matName = mat:GetName() end)
                local matKey = "rt_mat_" .. gi
                local matExpanded = expandedTreeNodes_[matKey]
                addTreeRow(1, "🎨", "材质[" .. gi .. "]", shortName(matName), {
                    expandKey = matKey, expanded = matExpanded, valueColor = T.COLOR_ORANGE,
                })

                if matExpanded then
                    local matProps = collectMaterialProps(mat)
                    for _, prop in ipairs(matProps) do
                        local valStr = tostring(prop.value)
                        if prop.type == "bool" then
                            valStr = prop.value and "是" or "否"
                        elseif prop.type == "color" then
                            local c = prop.current  -- current 是 Color 对象
                            if c then
                                valStr = string.format("(%.2f, %.2f, %.2f, %.2f)", c.r or 0, c.g or 0, c.b or 0, c.a or 0)
                            end
                        elseif prop.type == "enum" then
                            local idx = tonumber(prop.current) or 0
                            local entry = prop.options and prop.options[idx + 1]
                            valStr = (type(entry) == "table" and entry.n) or (type(entry) == "string" and entry) or tostring(prop.value)
                        end
                        addTreeRow(2, "⚙️", prop.label, valStr)
                    end

                    local textures = collectTextures(mat)
                    for ti, texInfo in ipairs(textures) do
                        local texKey = "rt_tex_" .. gi .. "_" .. texInfo.unit
                        local isPreview = (previewTexKey_ == texKey)
                        local valText = shortName(texInfo.name) .. "  [点击预览]"
                        addTreeRow(2, "🖼️", texInfo.unitName, valText, {
                            valueColor = T.TEXT_PRIMARY,
                            iconSize = 14,
                            onClick = function(self)
                                if previewTexKey_ == texKey then
                                    previewTexKey_ = nil
                                else
                                    previewTexKey_ = texKey
                                end
                                rebuildDetail()
                            end,
                        })
                        if isPreview then
                            addTexturePreview(texInfo, texKey)
                        end
                    end

                    local shaders = collectShaders(mat)
                    for _, techInfo in ipairs(shaders) do
                        local shaderKey = "rt_shader_" .. gi .. "_" .. techInfo.techIdx
                        local shaderExpanded = expandedTreeNodes_[shaderKey]
                        addTreeRow(2, "💎", "Shader技术", shortName(techInfo.name), {
                            expandKey = shaderKey, expanded = shaderExpanded, valueColor = T.COLOR_CYAN,
                        })
                        if shaderExpanded then
                            for _, p in ipairs(techInfo.passes) do
                                addTreeRow(3, "🔧", "Pass:" .. p.name, "")
                                addTreeRow(4, "VS", "Vertex", shortName(p.vs))
                                addTreeRow(4, "PS", "Pixel", shortName(p.ps))
                                if p.vsDefines and p.vsDefines ~= "" then
                                    addTreeRow(4, "📝", "VS Defines", p.vsDefines)
                                end
                                if p.psDefines and p.psDefines ~= "" then
                                    addTreeRow(4, "📝", "PS Defines", p.psDefines)
                                end
                            end
                        end
                    end
                end
            else
                addTreeRow(1, "⚠️", "材质", "(未关联)", { valueColor = T.TEXT_HINT })
            end
        end

        ::continue_geom::
    end
end

--- 显示骨骼摘要
local function showSkeletonSummary(mdl)
    if not mdl then return end
    local skel = nil
    pcall(function() skel = mdl:GetSkeleton() end)
    if not skel then return end
    local numBones = 0
    pcall(function() numBones = skel:GetNumBones() end)
    if numBones == 0 then return end
    addDetailSection("骨骼 (Skeleton)")
    addDetailRow("骨骼数", numBones)
    local rootBone = nil
    pcall(function() rootBone = skel:GetRootBone() end)
    if rootBone then
        local boneName = ""
        pcall(function() boneName = rootBone.name end)
        if boneName ~= "" then addDetailRow("根骨骼", boneName) end
    end
end

--- 添加可编辑的整数行（无小数位）
local function addEditableIntRow(label, value, setter, step)
    if not detailInner_ then return end
    step = step or 1
    local isLocked = lockedPaths_[selectedPath_] == true
    local valStr = tostring(math.floor(value))
    detailInner_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(3),
        borderBottomWidth = S(1), borderColor = { 40, 35, 28, 50 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT, width = S(90), flexShrink = 0,
            },
            UI.Panel {
                width = S(120), height = S(22),
                flexDirection = "row", alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Button {
                        text = "-", fontSize = S(11), fontFamily = FONT_FAMILY,
                        height = S(18), width = S(18), borderRadius = S(3),
                        variant = "ghost", paddingHorizontal = 0,
                        disabled = isLocked,
                        backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                        fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                        onClick = isLocked and nil or function(self)
                            pcall(function() setter(math.floor(value - step)) end)
                            rebuildDetail()
                        end,
                    },
                    UI.TextField {
                        value = valStr,
                        fontSize = S(10), fontFamily = FONT_FAMILY,
                        height = S(18), flexGrow = 1,
                        paddingHorizontal = S(2),
                        disabled = isLocked,
                        backgroundColor = isLocked and { 22, 18, 14, 255 } or { 35, 30, 22, 255 },
                        borderWidth = S(1),
                        borderColor = isLocked and { 50, 42, 30, 150 } or { 70, 58, 38, 200 },
                        borderRadius = S(3),
                        fontColor = isLocked and T.TEXT_HINT or T.TEXT_PRIMARY,
                        onSubmit = isLocked and nil or function(self, text)
                            local num = tonumber(text)
                            if num then
                                pcall(function() setter(math.floor(num)) end)
                                rebuildDetail()
                            end
                        end,
                    },
                    UI.Button {
                        text = "+", fontSize = S(11), fontFamily = FONT_FAMILY,
                        height = S(18), width = S(18), borderRadius = S(3),
                        variant = "ghost", paddingHorizontal = 0,
                        disabled = isLocked,
                        backgroundColor = isLocked and { 30, 26, 20, 255 } or { 45, 38, 25, 255 },
                        fontColor = isLocked and T.TEXT_HINT or T.TEXT_SECONDARY,
                        onClick = isLocked and nil or function(self)
                            pcall(function() setter(math.floor(value + step)) end)
                            rebuildDetail()
                        end,
                    },
                },
            },
        },
    })
end

-- ── Drawable 通用属性（StaticModel/AnimatedModel 共用）──
local function showDrawableCommon(comp)
    local castShadows = safeGet(comp, comp.GetCastShadows)
    if castShadows ~= nil then
        addEditableBoolRow("投射阴影", castShadows, function(v) comp:SetCastShadows(v) end)
    end
    local drawDist = safeGet(comp, comp.GetDrawDistance)
    if drawDist then addEditableFloatRow("绘制距离", drawDist, function(v) comp:SetDrawDistance(v) end, 1) end
    local shadowDist = safeGet(comp, comp.GetShadowDistance)
    if shadowDist then addEditableFloatRow("阴影距离", shadowDist, function(v) comp:SetShadowDistance(v) end, 1) end
    local lodBias = safeGet(comp, comp.GetLodBias)
    if lodBias then addEditableFloatRow("LOD偏移", lodBias, function(v) comp:SetLodBias(v) end, 0.1) end
    local occluder = safeGet(comp, comp.IsOccluder)
    if occluder ~= nil then addEditableBoolRow("遮挡器", occluder, function(v) comp:SetOccluder(v) end) end
    local occludee = safeGet(comp, comp.IsOccludee)
    if occludee ~= nil then addEditableBoolRow("可遮挡", occludee, function(v) comp:SetOccludee(v) end) end
    local viewMask = safeGet(comp, comp.GetViewMask)
    if viewMask then addDetailRow("视图掩码", string.format("0x%X", viewMask)) end
    local lightMask = safeGet(comp, comp.GetLightMask)
    if lightMask then addDetailRow("光照掩码", string.format("0x%X", lightMask)) end
    local shadowMask = safeGet(comp, comp.GetShadowMask)
    if shadowMask and shadowMask ~= 0xFFFFFFFF then addDetailRow("阴影掩码", string.format("0x%X", shadowMask)) end
    local zoneMask = safeGet(comp, comp.GetZoneMask)
    if zoneMask and zoneMask ~= 0xFFFFFFFF then addDetailRow("区域掩码", string.format("0x%X", zoneMask)) end
    local maxLights = safeGet(comp, comp.GetMaxLights)
    if maxLights and maxLights ~= 0 then addDetailRow("最大灯光", tostring(maxLights)) end
end

local function showStaticModelDetail(comp)
    addDetailSection("StaticModel 属性")

    -- 模型资源
    local mdl = nil
    local modelName = ""
    pcall(function() mdl = comp:GetModel(); if mdl then modelName = mdl:GetName() end end)
    addDetailRow("模型", shortName(modelName))

    -- 包围盒
    local bbSize
    pcall(function() bbSize = comp.boundingBox.size end)
    if bbSize then addDetailRow("包围盒", fmtVec3(bbSize)) end

    -- 遮挡 LOD
    local occLod = safeGet(comp, comp.GetOcclusionLodLevel)
    if occLod then addEditableIntRow("遮挡LOD", occLod, function(v) comp:SetOcclusionLodLevel(v) end, 1) end

    -- Drawable 通用
    showDrawableCommon(comp)

    -- 资源关联树（网格 + 材质 + 贴图 + Shader）
    showResourceTree(comp, mdl)
end

local function showAnimatedModelDetail(comp)
    addDetailSection("AnimatedModel 属性")

    -- 模型资源
    local mdl = nil
    local modelName = ""
    pcall(function() mdl = comp:GetModel(); if mdl then modelName = mdl:GetName() end end)
    addDetailRow("模型", shortName(modelName))

    -- 包围盒
    local bbSize
    pcall(function() bbSize = comp.boundingBox.size end)
    if bbSize then addDetailRow("包围盒", fmtVec3(bbSize)) end

    -- 动画特有属性
    local numAnims = safeGet(comp, comp.GetNumAnimationStates) or 0
    addDetailRow("动画状态数", numAnims)
    local animLodBias = safeGet(comp, comp.GetAnimationLodBias)
    if animLodBias then addEditableFloatRow("动画LOD偏移", animLodBias, function(v) comp:SetAnimationLodBias(v) end, 0.1) end
    local updateInvis = safeGet(comp, comp.GetUpdateInvisible)
    if updateInvis ~= nil then addEditableBoolRow("不可见时更新", updateInvis, function(v) comp:SetUpdateInvisible(v) end) end
    local isMaster = safeGet(comp, comp.IsMaster)
    if isMaster ~= nil then addDetailRow("主模型", fmtBool(isMaster)) end
    local numMorphs = safeGet(comp, comp.GetNumMorphs) or 0
    if numMorphs > 0 then addDetailRow("变形目标数", numMorphs) end

    -- Drawable 通用
    showDrawableCommon(comp)

    -- 骨骼摘要
    if mdl then showSkeletonSummary(mdl) end

    -- 资源关联树（网格 + 材质 + 贴图 + Shader）
    showResourceTree(comp, mdl)
end

local function showAnimControllerDetail(comp)
    addDetailSection("AnimationController 属性")
    local numAnims = safeGet(comp, comp.GetNumAnimations) or 0
    addDetailRow("动画数", numAnims)

    -- 逐动画详情
    for ai = 0, numAnims - 1 do
        local anim = nil
        pcall(function() anim = comp:GetAnimation(ai) end)
        if anim then
            local animName = ""
            pcall(function() animName = anim.name end)
            local shortAnim = shortName(animName)
            addDetailSection("动画 [" .. ai .. "] " .. shortAnim)

            local speed = safeGet(anim, function(a) return a.speed end)
            if speed then addDetailRow("速度", fmtFloat(speed)) end
            local targetW = safeGet(anim, function(a) return a.targetWeight end)
            if targetW then addDetailRow("目标权重", fmtFloat(targetW)) end
            local fadeT = safeGet(anim, function(a) return a.fadeTime end)
            if fadeT then addDetailRow("淡入时间", fmtFloat(fadeT)) end
            local autoFadeT = safeGet(anim, function(a) return a.autoFadeTime end)
            if autoFadeT and autoFadeT > 0 then addDetailRow("自动淡出", fmtFloat(autoFadeT)) end
            local removeOnComp = safeGet(anim, function(a) return a.removeOnCompletion end)
            if removeOnComp ~= nil then addDetailRow("完成时移除", fmtBool(removeOnComp)) end

            -- 通过 AnimationController 方法获取更多运行时信息
            if animName ~= "" then
                local layer = safeGet(comp, comp.GetLayer, animName)
                if layer then addDetailRow("层", tostring(layer)) end
                local weight = safeGet(comp, comp.GetWeight, animName)
                if weight then addDetailRow("当前权重", fmtFloat(weight)) end
                local animTime = safeGet(comp, comp.GetTime, animName)
                local animLen = safeGet(comp, comp.GetLength, animName)
                if animTime and animLen then
                    addDetailRow("时间", fmtFloat(animTime) .. " / " .. fmtFloat(animLen) .. "s")
                end
                local playing = safeGet(comp, comp.IsPlaying, animName)
                if playing ~= nil then addDetailRow("播放中", fmtBool(playing), playing and T.COLOR_GREEN or T.TEXT_HINT) end
                local looped = safeGet(comp, comp.IsLooped, animName)
                if looped ~= nil then addDetailRow("循环", fmtBool(looped)) end
                local atEnd = safeGet(comp, comp.IsAtEnd, animName)
                if atEnd then addDetailRow("已结束", fmtBool(atEnd), T.COLOR_ORANGE) end
                local fadingIn = safeGet(comp, comp.IsFadingIn, animName)
                if fadingIn then addDetailRow("淡入中", fmtBool(fadingIn), T.COLOR_CYAN) end
                local fadingOut = safeGet(comp, comp.IsFadingOut, animName)
                if fadingOut then addDetailRow("淡出中", fmtBool(fadingOut), T.COLOR_CYAN) end
                local blendMode = safeGet(comp, comp.GetBlendMode, animName)
                if blendMode then
                    local blendNames = { [0] = "Lerp", [1] = "Additive" }
                    addDetailRow("混合模式", blendNames[blendMode] or tostring(blendMode))
                end
            end
        end
    end
end

local function showLightDetail(comp)
    addDetailSection("Light 属性")
    local lt = safeGet(comp, comp.GetLightType)
    addDetailRow("类型", lt ~= nil and (LIGHT_TYPE_NAMES[lt] or tostring(lt)) or "?")
    local col = safeGet(comp, comp.GetColor)
    if col then addEditableColorRow("颜色", col, function(c) comp:SetColor(c) end, "light_color") end
    local effCol = safeGet(comp, comp.GetEffectiveColor)
    if effCol and col then
        local diff = false
        pcall(function() diff = math.abs(effCol.r - col.r) > 0.01 or math.abs(effCol.g - col.g) > 0.01 or math.abs(effCol.b - col.b) > 0.01 end)
        if diff then addEditableColorRow("有效颜色", effCol, nil, "light_eff_color", true) end
    end
    local brightness = safeGet(comp, comp.GetBrightness)
    if brightness then addEditableFloatRow("亮度", brightness, function(v) comp:SetBrightness(v) end, 0.1) end
    local range = safeGet(comp, comp.GetRange)
    if range then addEditableFloatRow("范围", range, function(v) comp:SetRange(v) end, 1) end
    local fov = safeGet(comp, comp.GetFov)
    if fov and lt == 1 then addEditableFloatRow("FOV", fov, function(v) comp:SetFov(v) end, 5) end
    local specI = safeGet(comp, comp.GetSpecularIntensity)
    if specI then addEditableFloatRow("高光强度", specI, function(v) comp:SetSpecularIntensity(v) end, 0.1) end
    local effSpecI = safeGet(comp, comp.GetEffectiveSpecularIntensity)
    if effSpecI and specI and math.abs(effSpecI - specI) > 0.01 then
        addDetailRow("有效高光", fmtFloat(effSpecI), T.COLOR_ORANGE)
    end
    local temp = safeGet(comp, comp.GetTemperature)
    if temp then addEditableFloatRow("色温(K)", temp, function(v) comp:SetTemperature(v) end, 100) end
    local usePhys = safeGet(comp, comp.GetUsePhysicalValues)
    if usePhys ~= nil then addEditableBoolRow("物理光照", usePhys, function(v) comp:SetUsePhysicalValues(v) end) end
    local radius = safeGet(comp, comp.GetRadius)
    if radius then addEditableFloatRow("半径", radius, function(v) comp:SetRadius(v) end, 0.1) end
    local length = safeGet(comp, comp.GetLength)
    if length then addEditableFloatRow("长度", length, function(v) comp:SetLength(v) end, 0.1) end
    if lt == 1 then -- Spot
        local aspect = safeGet(comp, comp.GetAspectRatio)
        if aspect then addEditableFloatRow("宽高比", aspect, function(v) comp:SetAspectRatio(v) end, 0.1) end
    end
    local castShadows = safeGet(comp, comp.GetCastShadows)
    if castShadows ~= nil then addEditableBoolRow("投射阴影", castShadows, function(v) comp:SetCastShadows(v) end) end
    if castShadows then
        local shadowIntensity = safeGet(comp, comp.GetShadowIntensity)
        if shadowIntensity then addEditableFloatRow("阴影强度", shadowIntensity, function(v) comp:SetShadowIntensity(v) end, 0.05) end
        local shadowRes = safeGet(comp, comp.GetShadowResolution)
        if shadowRes then addEditableFloatRow("阴影分辨率", shadowRes, function(v) comp:SetShadowResolution(v) end, 0.25) end
        local shadowNFR = safeGet(comp, comp.GetShadowNearFarRatio)
        if shadowNFR then addEditableFloatRow("阴影近远比", shadowNFR, function(v) comp:SetShadowNearFarRatio(v) end, 0.01) end
        local shadowFadeDist = safeGet(comp, comp.GetShadowFadeDistance)
        if shadowFadeDist then addEditableFloatRow("阴影淡出距离", shadowFadeDist, function(v) comp:SetShadowFadeDistance(v) end, 1) end
        local shadowMaxExt = safeGet(comp, comp.GetShadowMaxExtrusion)
        if shadowMaxExt then addEditableFloatRow("阴影最大延伸", shadowMaxExt, function(v) comp:SetShadowMaxExtrusion(v) end, 10) end
        -- ShadowBias
        local bias = safeGet(comp, comp.GetShadowBias)
        if bias then
            addDetailRow("  恒定偏移", fmtFloat(bias.constantBias, 5))
            addDetailRow("  斜率偏移", fmtFloat(bias.slopeScaledBias, 3))
            addDetailRow("  法线偏移", fmtFloat(bias.normalOffset, 3))
        end
        if lt == 0 then -- Directional
            local numSplits = safeGet(comp, comp.GetNumShadowSplits)
            if numSplits then addDetailRow("级联分割数", tostring(numSplits)) end
            -- CascadeParameters
            local cascade = safeGet(comp, comp.GetShadowCascade)
            if cascade then
                addDetailRow("  淡入开始", fmtFloat(cascade.fadeStart))
                addDetailRow("  偏移自适应", fmtFloat(cascade.biasAutoAdjust))
            end
            -- FocusParameters
            local focus = safeGet(comp, comp.GetShadowFocus)
            if focus then
                addDetailRow("  聚焦", fmtBool(focus.focus))
                addDetailRow("  非均匀", fmtBool(focus.nonUniform))
                addDetailRow("  自动尺寸", fmtBool(focus.autoSize))
            end
        end
    end
    local perVertex = safeGet(comp, comp.GetPerVertex)
    if perVertex ~= nil then addEditableBoolRow("逐顶点", perVertex, function(v) comp:SetPerVertex(v) end) end
    local negative = safeGet(comp, comp.GetNegative)
    if negative ~= nil then addDetailRow("负光源", fmtBool(negative)) end
    local fadeDistance = safeGet(comp, comp.GetFadeDistance)
    if fadeDistance then addEditableFloatRow("淡出距离", fadeDistance, function(v) comp:SetFadeDistance(v) end, 1) end
    -- 纹理引用
    local rampTex = safeGet(comp, comp.GetRampTexture)
    if rampTex then
        local rName = ""
        pcall(function() rName = rampTex:GetName() end)
        addDetailRow("渐变纹理", shortName(rName), T.COLOR_CYAN)
    end
    local shapeTex = safeGet(comp, comp.GetShapeTexture)
    if shapeTex then
        local sName = ""
        pcall(function() sName = shapeTex:GetName() end)
        addDetailRow("形状纹理", shortName(sName), T.COLOR_CYAN)
    end
end

local function showCameraDetail(comp)
    addDetailSection("Camera 属性")
    local fov = safeGet(comp, comp.GetFov)
    if fov then addEditableFloatRow("FOV", fov, function(v) comp:SetFov(v) end, 5) end
    local nearClip = safeGet(comp, comp.GetNearClip)
    if nearClip then addEditableFloatRow("近裁面", nearClip, function(v) comp:SetNearClip(v) end, 0.1) end
    local farClip = safeGet(comp, comp.GetFarClip)
    if farClip then addEditableFloatRow("远裁面", farClip, function(v) comp:SetFarClip(v) end, 10) end
    local ortho = safeGet(comp, comp.IsOrthographic)
    if ortho ~= nil then addEditableBoolRow("正交", ortho, function(v) comp:SetOrthographic(v) end) end
    if ortho then
        local orthoSize = safeGet(comp, comp.GetOrthoSize)
        if orthoSize then addEditableFloatRow("正交大小", orthoSize, function(v) comp:SetOrthoSize(v) end, 1) end
    end
    local zoom = safeGet(comp, comp.GetZoom)
    if zoom then addEditableFloatRow("缩放", zoom, function(v) comp:SetZoom(v) end, 0.1) end
    local aspect = safeGet(comp, comp.GetAspectRatio)
    if aspect then addEditableFloatRow("宽高比", aspect, function(v) comp:SetAspectRatio(v) end, 0.1) end
    local autoAspect = safeGet(comp, comp.GetAutoAspectRatio)
    if autoAspect ~= nil then addEditableBoolRow("自动宽高比", autoAspect, function(v) comp:SetAutoAspectRatio(v) end) end
    local halfView = safeGet(comp, comp.GetHalfViewSize)
    if halfView then addDetailRow("半视口大小", fmtFloat(halfView)) end
    local projOff = safeGet(comp, comp.GetProjectionOffset)
    if projOff then addDetailRow("投影偏移", string.format("(%.3f, %.3f)", projOff.x, projOff.y)) end
    local useRefl = safeGet(comp, comp.GetUseReflection)
    if useRefl ~= nil then addEditableBoolRow("使用反射", useRefl, function(v) comp:SetUseReflection(v) end) end
    local useClip = safeGet(comp, comp.GetUseClipping)
    if useClip ~= nil then addEditableBoolRow("使用裁剪", useClip, function(v) comp:SetUseClipping(v) end) end
    local viewMask = safeGet(comp, comp.GetViewMask)
    if viewMask then addDetailRow("视图掩码", string.format("0x%X", viewMask)) end
    local lodBias = safeGet(comp, comp.GetLodBias)
    if lodBias then addEditableFloatRow("LOD偏移", lodBias, function(v) comp:SetLodBias(v) end, 0.1) end
    local fillMode = safeGet(comp, comp.GetFillMode)
    if fillMode then
        local fillNames = { [0] = "Solid", [1] = "Wireframe", [2] = "Point" }
        addDetailRow("填充模式", fillNames[fillMode] or tostring(fillMode))
    end
end

local function showRigidBodyDetail(comp)
    addDetailSection("RigidBody 属性")
    local mass = safeGet(comp, comp.GetMass)
    if mass then addEditableFloatRow("质量", mass, function(v) comp:SetMass(v) end, 0.5) end
    local friction = safeGet(comp, comp.GetFriction)
    if friction then addEditableFloatRow("摩擦力", friction, function(v) comp:SetFriction(v) end, 0.1) end
    local rollingFriction = safeGet(comp, comp.GetRollingFriction)
    if rollingFriction then addEditableFloatRow("滚动摩擦", rollingFriction, function(v) comp:SetRollingFriction(v) end, 0.05) end
    local restitution = safeGet(comp, comp.GetRestitution)
    if restitution then addEditableFloatRow("弹性", restitution, function(v) comp:SetRestitution(v) end, 0.1) end
    local linDamp = safeGet(comp, comp.GetLinearDamping)
    if linDamp then addEditableFloatRow("线性阻尼", linDamp, function(v) comp:SetLinearDamping(v) end, 0.05) end
    local angDamp = safeGet(comp, comp.GetAngularDamping)
    if angDamp then addEditableFloatRow("角阻尼", angDamp, function(v) comp:SetAngularDamping(v) end, 0.05) end
    local linVel = safeGet(comp, comp.GetLinearVelocity)
    if linVel then addDetailRow("线速度", fmtVec3(linVel), T.COLOR_BLUE) end
    local angVel = safeGet(comp, comp.GetAngularVelocity)
    if angVel then addDetailRow("角速度", fmtVec3(angVel), T.COLOR_BLUE) end
    local linFactor = safeGet(comp, comp.GetLinearFactor)
    if linFactor then addDetailRow("线性因子", fmtVec3(linFactor)) end
    local angFactor = safeGet(comp, comp.GetAngularFactor)
    if angFactor then addDetailRow("角因子", fmtVec3(angFactor)) end
    local kinematic = safeGet(comp, comp.IsKinematic)
    if kinematic ~= nil then addEditableBoolRow("运动学", kinematic, function(v) comp:SetKinematic(v) end) end
    local trigger = safeGet(comp, comp.IsTrigger)
    if trigger ~= nil then addEditableBoolRow("触发器", trigger, function(v) comp:SetTrigger(v) end) end
    local useGravity = safeGet(comp, comp.GetUseGravity)
    if useGravity ~= nil then addEditableBoolRow("使用重力", useGravity, function(v) comp:SetUseGravity(v) end) end
    local gravOverride = safeGet(comp, comp.GetGravityOverride)
    if gravOverride and (gravOverride.x ~= 0 or gravOverride.y ~= 0 or gravOverride.z ~= 0) then
        addDetailRow("重力覆盖", fmtVec3(gravOverride), T.COLOR_ORANGE)
    end
    local active = safeGet(comp, comp.IsActive)
    if active ~= nil then addDetailRow("活跃", fmtBool(active), active and T.COLOR_GREEN or T.COLOR_RED) end
    local centerOfMass = safeGet(comp, comp.GetCenterOfMass)
    if centerOfMass then addDetailRow("质心", fmtVec3(centerOfMass)) end
    local ccdRadius = safeGet(comp, comp.GetCcdRadius)
    if ccdRadius then addEditableFloatRow("CCD半径", ccdRadius, function(v) comp:SetCcdRadius(v) end, 0.01) end
    local ccdThreshold = safeGet(comp, comp.GetCcdMotionThreshold)
    if ccdThreshold then addEditableFloatRow("CCD阈值", ccdThreshold, function(v) comp:SetCcdMotionThreshold(v) end, 0.1) end
    local linRestThresh = safeGet(comp, comp.GetLinearRestThreshold)
    if linRestThresh then addEditableFloatRow("线性休眠阈", linRestThresh, function(v) comp:SetLinearRestThreshold(v) end, 0.1) end
    local angRestThresh = safeGet(comp, comp.GetAngularRestThreshold)
    if angRestThresh then addEditableFloatRow("角休眠阈值", angRestThresh, function(v) comp:SetAngularRestThreshold(v) end, 0.1) end
    local anisoFriction = safeGet(comp, comp.GetAnisotropicFriction)
    if anisoFriction then addDetailRow("各向异性摩擦", fmtVec3(anisoFriction)) end
    local contactThresh = safeGet(comp, comp.GetContactProcessingThreshold)
    if contactThresh then addEditableFloatRow("接触处理阈", contactThresh, function(v) comp:SetContactProcessingThreshold(v) end, 0.1) end
    local collEventMode = safeGet(comp, comp.GetCollisionEventMode)
    if collEventMode then
        local modeNames = { [0] = "Never", [1] = "WhenActive", [2] = "Always" }
        addDetailRow("碰撞事件模式", modeNames[collEventMode] or tostring(collEventMode))
    end
    local layer = safeGet(comp, comp.GetCollisionLayer)
    if layer then addEditableIntRow("碰撞层", layer, function(v) comp:SetCollisionLayer(v) end, 1) end
    local mask = safeGet(comp, comp.GetCollisionMask)
    if mask then addEditableIntRow("碰撞掩码", mask, function(v) comp:SetCollisionMask(v) end, 1) end
end

local function showCollisionShapeDetail(comp)
    addDetailSection("CollisionShape 属性")
    local shapeType = safeGet(comp, comp.GetShapeType)
    local shapeNames = { [0]="Box", [1]="Sphere", [2]="StaticPlane", [3]="Cylinder",
        [4]="Capsule", [5]="Cone", [6]="TriangleMesh", [7]="ConvexHull", [8]="Terrain" }
    addDetailRow("形状", shapeType and (shapeNames[shapeType] or tostring(shapeType)) or "?")
    local size = safeGet(comp, comp.GetSize)
    if size then addDetailRow("尺寸", fmtVec3(size)) end
    local pos = safeGet(comp, comp.GetPosition)
    if pos then addDetailRow("偏移", fmtVec3(pos)) end
    local rot = safeGet(comp, comp.GetRotation)
    if rot then addDetailRow("旋转", fmtQuat(rot)) end
    local margin = safeGet(comp, comp.GetMargin)
    if margin then addEditableFloatRow("碰撞边距", margin, function(v) comp:SetMargin(v) end, 0.01) end
    local lodLevel = safeGet(comp, comp.GetLodLevel)
    if lodLevel and lodLevel > 0 then addDetailRow("LOD等级", tostring(lodLevel)) end
    -- 网格形状的模型引用
    if shapeType and (shapeType == 6 or shapeType == 7) then
        local shapeMdl = nil
        pcall(function() shapeMdl = comp:GetModel() end)
        if shapeMdl then
            local mName = ""
            pcall(function() mName = shapeMdl:GetName() end)
            addDetailRow("碰撞模型", shortName(mName))
        end
    end
    local bb = safeGet(comp, comp.GetWorldBoundingBox)
    if bb then
        local bbSize = nil
        pcall(function() bbSize = bb.size end)
        if bbSize then addDetailRow("世界包围盒", fmtVec3(bbSize)) end
    end
end

local function showZoneDetail(comp)
    addDetailSection("Zone 属性")
    -- 区域包围盒
    local bb = safeGet(comp, comp.GetBoundingBox)
    if bb then
        local bbMin, bbMax
        pcall(function() bbMin = bb.min; bbMax = bb.max end)
        if bbMin and bbMax then
            addDetailRow("区域最小", fmtVec3(bbMin))
            addDetailRow("区域最大", fmtVec3(bbMax))
        end
    end
    local ambientColor = safeGet(comp, comp.GetAmbientColor)
    if ambientColor then addEditableColorRow("环境光", ambientColor, function(c) comp:SetAmbientColor(c) end, "zone_ambient") end
    local ambientGrad = safeGet(comp, comp.GetAmbientGradient)
    if ambientGrad ~= nil then
        addEditableBoolRow("环境渐变", ambientGrad, function(v) comp:SetAmbientGradient(v) end)
        if ambientGrad then
            local startColor = safeGet(comp, comp.GetAmbientStartColor)
            if startColor then addEditableColorRow("  起始色", startColor, nil, "zone_amb_start", true) end
            local endColor = safeGet(comp, comp.GetAmbientEndColor)
            if endColor then addEditableColorRow("  结束色", endColor, nil, "zone_amb_end", true) end
        end
    end
    local fogColor = safeGet(comp, comp.GetFogColor)
    if fogColor then addEditableColorRow("雾颜色", fogColor, function(c) comp:SetFogColor(c) end, "zone_fog") end
    local fogStart = safeGet(comp, comp.GetFogStart)
    if fogStart then addEditableFloatRow("雾起始", fogStart, function(v) comp:SetFogStart(v) end, 10) end
    local fogEnd = safeGet(comp, comp.GetFogEnd)
    if fogEnd then addEditableFloatRow("雾终止", fogEnd, function(v) comp:SetFogEnd(v) end, 10) end
    local heightFog = safeGet(comp, comp.GetHeightFog)
    if heightFog ~= nil then addEditableBoolRow("高度雾", heightFog, function(v) comp:SetHeightFog(v) end) end
    if heightFog then
        local fogHeight = safeGet(comp, comp.GetFogHeight)
        if fogHeight then addEditableFloatRow("雾高度", fogHeight, function(v) comp:SetFogHeight(v) end, 1) end
        local fogHeightScale = safeGet(comp, comp.GetFogHeightScale)
        if fogHeightScale then addEditableFloatRow("雾高度缩放", fogHeightScale, function(v) comp:SetFogHeightScale(v) end, 0.1) end
    end
    local override = safeGet(comp, comp.GetOverride)
    if override ~= nil then addEditableBoolRow("覆盖模式", override, function(v) comp:SetOverride(v) end) end
    local priority = safeGet(comp, comp.GetPriority)
    if priority then addEditableIntRow("优先级", priority, function(v) comp:SetPriority(v) end, 1) end
    -- Zone 纹理（IBL 环境贴图）
    local zoneTex = nil
    pcall(function() zoneTex = comp:GetZoneTexture() end)
    if zoneTex then
        local ztName = ""
        pcall(function() ztName = zoneTex:GetName() end)
        addDetailRow("环境贴图", shortName(ztName), T.COLOR_CYAN)
    end
end

local function showSoundSourceDetail(comp)
    addDetailSection("SoundSource 属性")
    local playing = safeGet(comp, comp.IsPlaying)
    if playing ~= nil then addDetailRow("播放中", fmtBool(playing), playing and T.COLOR_GREEN or T.TEXT_HINT) end
    -- 音频资源
    local snd = nil
    pcall(function() snd = comp:GetSound() end)
    if snd then
        local sndName = ""
        pcall(function() sndName = snd:GetName() end)
        addDetailRow("音频", shortName(sndName))
        local sndLen = safeGet(snd, snd.GetLength)
        if sndLen then addDetailRow("时长", fmtFloat(sndLen) .. "s") end
        local stereo = safeGet(snd, snd.IsStereo)
        local sixteenBit = safeGet(snd, snd.IsSixteenBit)
        local sndFreq = safeGet(snd, snd.GetIntFrequency)
        local fmtStr = (sixteenBit and "16-bit" or "8-bit") .. " " .. (stereo and "Stereo" or "Mono")
        if sndFreq then fmtStr = fmtStr .. " " .. sndFreq .. "Hz" end
        addDetailRow("格式", fmtStr, T.TEXT_SECONDARY)
        local compressed = safeGet(snd, snd.IsCompressed)
        if compressed then addDetailRow("已压缩", fmtBool(compressed)) end
        local looped = safeGet(snd, snd.IsLooped)
        if looped ~= nil then addDetailRow("循环", fmtBool(looped)) end
    end
    local gain = safeGet(comp, comp.GetGain)
    if gain then addEditableFloatRow("音量", gain, function(v) comp:SetGain(v) end, 0.1) end
    local freq = safeGet(comp, comp.GetFrequency)
    if freq then addEditableFloatRow("播放频率", freq, function(v) comp:SetFrequency(v) end, 100) end
    local panning = safeGet(comp, comp.GetPanning)
    if panning then addEditableFloatRow("声像", panning, function(v) comp:SetPanning(v) end, 0.1) end
    local attenuation = safeGet(comp, comp.GetAttenuation)
    if attenuation then addEditableFloatRow("衰减", attenuation, function(v) comp:SetAttenuation(v) end, 0.1) end
    local timePos = safeGet(comp, comp.GetTimePosition)
    if timePos and playing then addDetailRow("播放位置", fmtFloat(timePos) .. "s") end
    local soundType = safeGet(comp, comp.GetSoundType)
    if soundType and soundType ~= "" then addDetailRow("声音类型", soundType) end
    -- 自动移除模式
    local autoRemove = safeGet(comp, comp.GetAutoRemoveMode)
    if autoRemove ~= nil then
        local removeNames = { [0] = "Disabled", [1] = "Component", [2] = "Node" }
        addDetailRow("自动移除", removeNames[autoRemove] or tostring(autoRemove))
    end
    -- 淡入淡出状态（运行时只读）
    local fadingIn = nil
    pcall(function() fadingIn = comp:IsFadingIn() end)
    if fadingIn ~= nil then addDetailRow("淡入中", fmtBool(fadingIn)) end
    local fadingOut = nil
    pcall(function() fadingOut = comp:IsFadingOut() end)
    if fadingOut ~= nil then addDetailRow("淡出中", fmtBool(fadingOut)) end
    -- declick
    local declick = safeGet(comp, comp.GetDeclickEnabled)
    if declick ~= nil then addEditableBoolRow("消咔", declick, function(v) comp:SetDeclickEnabled(v) end) end
    -- SoundSource3D 特有属性
    local near = safeGet(comp, comp.GetNearDistance)
    if near then addEditableFloatRow("近距离", near, function(v) comp:SetNearDistance(v) end, 0.5) end
    local far = safeGet(comp, comp.GetFarDistance)
    if far then addEditableFloatRow("远距离", far, function(v) comp:SetFarDistance(v) end, 1.0) end
    local innerAngle = safeGet(comp, comp.GetInnerAngle)
    if innerAngle then addEditableFloatRow("内锥角", innerAngle, function(v) comp:SetInnerAngle(v) end, 5.0) end
    local outerAngle = safeGet(comp, comp.GetOuterAngle)
    if outerAngle then addEditableFloatRow("外锥角", outerAngle, function(v) comp:SetOuterAngle(v) end, 5.0) end
    local rolloff = safeGet(comp, comp.GetRolloffFactor)
    if rolloff then addEditableFloatRow("衰减因子", rolloff, function(v) comp:SetRolloffFactor(v) end, 0.1) end
end

--- 组件类型 → 专属详情函数映射
local COMP_DETAIL_FN = {
    StaticModel         = showStaticModelDetail,
    Light               = showLightDetail,
    Camera              = showCameraDetail,
    RigidBody           = showRigidBodyDetail,
    CollisionShape      = showCollisionShapeDetail,
    Zone                = showZoneDetail,
    SoundSource         = showSoundSourceDetail,
    SoundSource3D       = showSoundSourceDetail,
    AnimatedModel       = showAnimatedModelDetail,
    AnimationController = showAnimControllerDetail,
}

-- ============================================================================
-- 详情面板重建
-- ============================================================================

rebuildDetail = function()
    if not detailInner_ then return end
    detailInner_:RemoveAllChildren()

    if not selectedItem_ or not isAlive(selectedItem_) then
        detailInner_:AddChild(UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "点击节点查看属性",
                    fontSize = S(12), fontFamily = FONT_FAMILY,
                    fontColor = T.TEXT_HINT,
                },
            },
        })
        return
    end

    local isLocked = lockedPaths_[selectedPath_] == true

    if selectedIsComp_ then
        -- ========== 组件详情 ==========
        local comp = selectedItem_
        addDetailSection("组件信息")
        local typeName = "Component"
        pcall(function() typeName = comp:GetTypeName() end)
        addDetailRow("类型", typeName)
        local cid = 0
        pcall(function() cid = comp:GetID() end)
        addDetailRow("ID", cid)

        local enabled = true
        pcall(function() enabled = comp:IsEnabled() end)
        addEditableBoolRow("启用", enabled, function(v) comp:SetEnabled(v) end)

        -- 所属节点
        local nodeName = ""
        pcall(function() nodeName = comp:GetNode():GetName() end)
        if nodeName ~= "" then addDetailRow("所属节点", nodeName) end

        -- 调用组件专属详情
        local fn = COMP_DETAIL_FN[typeName]
        if fn then
            local ok, err = pcall(fn, comp)
            if not ok then
                log:Write(LOG_ERROR, "[SceneTreeView] COMP_DETAIL_FN[" .. typeName .. "] error: " .. tostring(err))
                -- 在 UI 上显示错误信息
                if detailInner_ then
                    detailInner_:AddChild(UI.Panel {
                        width = "100%", paddingHorizontal = S(8), paddingVertical = S(6),
                        backgroundColor = { 80, 20, 20, 255 },
                        borderWidth = S(1), borderColor = { 200, 60, 60, 200 },
                        borderRadius = S(4), marginTop = S(4),
                        children = {
                            UI.Label {
                                text = "⚠️ " .. typeName .. " 详情渲染出错:",
                                fontSize = S(10), fontFamily = FONT_FAMILY,
                                fontColor = { 255, 120, 120, 255 },
                            },
                            UI.Label {
                                text = tostring(err),
                                fontSize = S(9), fontFamily = FONT_FAMILY,
                                fontColor = { 255, 200, 200, 255 },
                                marginTop = S(2),
                            },
                        },
                    })
                end
            end
        end
    else
        -- ========== 节点详情 ==========
        local node = selectedItem_
        addDetailSection("节点信息")
        local name = ""
        pcall(function() name = node:GetName() end)
        addDetailRow("名称", name ~= "" and name or "(无名称)")
        local id = 0
        pcall(function() id = node:GetID() end)
        addDetailRow("ID", id)

        local enabled = true
        pcall(function() enabled = node:IsEnabled() end)
        addEditableBoolRow("启用", enabled, function(v) node:SetEnabled(v) end)

        -- 变换 Local（可编辑）
        addDetailSection("变换 (Local)")
        local pos = safeGet(node, node.GetPosition)
        addEditableVec3Row("位置", pos, function(v) node:SetPosition(v) end)

        local rot = safeGet(node, node.GetRotation)
        addEditableQuatRow("旋转", rot, function(q) node:SetRotation(q) end)

        local scl = safeGet(node, node.GetScale)
        addEditableVec3Row("缩放", scl, function(v) node:SetScale(v) end)

        -- 变换 World（可编辑）
        addDetailSection("变换 (World)")
        local wpos = safeGet(node, node.GetWorldPosition)
        addEditableVec3Row("位置", wpos, function(v) node:SetWorldPosition(v) end)
        local wrot = safeGet(node, node.GetWorldRotation)
        addEditableQuatRow("旋转", wrot, function(q) node:SetWorldRotation(q) end)
        local wscl = safeGet(node, node.GetWorldScale)
        addEditableVec3Row("缩放", wscl, function(v) node:SetWorldScale(v) end)

        -- 层级信息
        addDetailSection("层级信息")
        local numChildren = 0
        pcall(function() numChildren = node:GetNumChildren(false) end)
        local numChildrenR = 0
        pcall(function() numChildrenR = node:GetNumChildren(true) end)
        addDetailRow("子节点", numChildren)
        addDetailRow("递归子节点", numChildrenR)
        local numComps = 0
        pcall(function() numComps = node:GetNumComponents() end)
        addDetailRow("组件数", numComps)

        -- 组件列表（点击可选中跳转）
        if numComps > 0 then
            addDetailSection("组件列表")
            local comps = getNodeComponents(node)
            for ci = 1, #comps do
                local c = comps[ci]
                local cType = "?"
                pcall(function() cType = c:GetTypeName() end)
                local cEnabled = true
                pcall(function() cEnabled = c:IsEnabled() end)
                local emoji = COMP_EMOJI_MAP[cType] or DEFAULT_COMP_EMOJI
                addDetailRow(emoji .. " " .. cType,
                    cEnabled and "启用" or "禁用",
                    cEnabled and T.COLOR_GREEN or T.COLOR_RED)
            end
        end

        -- 标签
        local tags = {}
        pcall(function()
            local tv = node:GetTags()
            if tv and #tv > 0 then
                for ti = 1, #tv do
                    tags[#tags + 1] = tv[ti]
                end
            end
        end)
        if #tags > 0 then
            addDetailSection("标签")
            addDetailRow("Tags", table.concat(tags, ", "))
        end
    end
end

-- ============================================================================
-- 树重建
-- ============================================================================

rebuildTree = function()
    if not treeInner_ then return end
    treeInner_:RemoveAllChildren()

    local scn = getScene()
    if not scn then
        treeInner_:AddChild(UI.Label {
            text = "Scene 不可用", fontSize = S(12), fontFamily = FONT_FAMILY,
            fontColor = T.TEXT_HINT, marginLeft = S(10), marginTop = S(10),
        })
        return
    end

    local rows = {}
    local hasFilter = filterText_ ~= ""
    local directMatch = {}
    local rootPath = "S"
    if expanded_[rootPath] == nil then expanded_[rootPath] = true end

    if hasFilter then
        -- ── 过滤模式：预扫描匹配，自动展开祖先 ──
        local filterLower = string.lower(filterText_)
        local visible
        visible, directMatch = preFilterScan(scn, filterLower)

        if visible["S"] then
            local rootChildren = {}
            pcall(function() rootChildren = scn:GetChildren(false) end)
            local rootComps = getNodeComponents(scn)

            local rootHasVisible = false
            for j = 1, #rootChildren do
                if visible[makePathKey(rootPath, j)] then rootHasVisible = true; break end
            end
            if not rootHasVisible then
                for ci = 1, #rootComps do
                    if visible[rootPath .. ".C" .. ci] then rootHasVisible = true; break end
                end
            end

            rows[#rows + 1] = {
                depth = 0, item = scn, path = rootPath,
                hasChildren = rootHasVisible, isExpanded = true,
                isComp = false, isEnabled = true, isRoot = true,
                isMatch = false,
            }

            for ci = 1, #rootComps do
                local compPath = rootPath .. ".C" .. ci
                if visible[compPath] then
                    local compEnabled = true
                    pcall(function() compEnabled = rootComps[ci]:IsEnabled() end)
                    rows[#rows + 1] = {
                        depth = 1, item = rootComps[ci], path = compPath,
                        hasChildren = false, isExpanded = false,
                        isComp = true, isEnabled = compEnabled, isRoot = false,
                        isMatch = directMatch[compPath] or false,
                    }
                end
            end

            buildFilteredTreeRows(scn, 1, rootPath, rows, true, visible, directMatch)
        end
    else
        -- ── 正常模式：按展开状态构建 ──
        local rootChildren = {}
        pcall(function() rootChildren = scn:GetChildren(false) end)
        local rootComps = getNodeComponents(scn)
        local rootHasChildren = #rootChildren > 0 or #rootComps > 0
        rows[#rows + 1] = {
            depth = 0, item = scn, path = rootPath,
            hasChildren = rootHasChildren,
            isExpanded = expanded_[rootPath] == true,
            isComp = false, isEnabled = true, isRoot = true,
            isMatch = false,
        }
        if expanded_[rootPath] then
            for ci = 1, #rootComps do
                local compPath = rootPath .. ".C" .. ci
                local compEnabled = true
                pcall(function() compEnabled = rootComps[ci]:IsEnabled() end)
                rows[#rows + 1] = {
                    depth = 1, item = rootComps[ci], path = compPath,
                    hasChildren = false, isExpanded = false,
                    isComp = true, isEnabled = compEnabled, isRoot = false,
                    isMatch = false,
                }
            end
            buildTreeRows(scn, 1, rootPath, rows, true)
        end
    end

    for _, row in ipairs(rows) do
        local label
        if row.isRoot then
            label = SCENE_EMOJI .. " Scene"
        elseif row.isComp then
            label = getCompLabel(row.item)
        else
            label = getNodeLabel(row.item)
        end

        local prefix = ""
        if row.hasChildren then
            prefix = row.isExpanded and "- " or "+ "
        else
            prefix = "  "
        end

        local isSelected = (row.path == selectedPath_)
        local isMatch = row.isMatch or false
        local rowBg = isSelected and T.BG_SELECTED
            or isMatch and { 40, 35, 18, 255 }
            or T.BG_DARK
        local isLocked = lockedPaths_[row.path] == true
        local labelColor = (not row.isEnabled) and T.TEXT_HINT
            or isLocked and T.TEXT_SECONDARY
            or isMatch and T.ACCENT
            or T.TEXT_PRIMARY

        local rowPath = row.path
        local rowItem = row.item
        local rowHasChildren = row.hasChildren
        local rowIsComp = row.isComp
        local rowIsRoot = row.isRoot

        -- 构建行子元素
        local rowChildren = {
            -- 展开/折叠图标
            UI.Label {
                text = prefix, fontSize = S(13), fontFamily = FONT_FAMILY,
                fontColor = row.hasChildren and T.ACCENT or T.TEXT_HINT,
                width = S(16), flexShrink = 0,
            },
            -- 节点名称（可点击选中）
            UI.Panel {
                flexGrow = 1, flexShrink = 1, height = "100%",
                flexDirection = "row", alignItems = "center",
                onClick = function(self)
                    if rowHasChildren then
                        expanded_[rowPath] = not expanded_[rowPath]
                    end
                    selectedItem_   = rowItem
                    selectedPath_   = rowPath
                    selectedIsComp_ = rowIsComp
                    rebuildTree()
                    rebuildDetail()
                end,
                children = {
                    UI.Label {
                        text = label, fontSize = S(12), fontFamily = FONT_FAMILY,
                        fontColor = labelColor,
                        flexShrink = 1, flexGrow = 1,
                        numberOfLines = 1, overflow = "hidden",
                    },
                },
            },
        }

        -- 根节点不显示操作按钮，节点和组件都显示
        if not rowIsRoot then
            -- 锁定按钮
            local lockBtnStyle = {
                height = S(22), width = S(22), borderRadius = S(3),
                fontSize = S(12), fontFamily = FONT_FAMILY,
                variant = "ghost", paddingHorizontal = 0,
                backgroundColor = isLocked and { 60, 45, 25, 255 } or { 0, 0, 0, 0 },
                fontColor = isLocked and T.ACCENT or T.TEXT_HINT,
            }
            rowChildren[#rowChildren + 1] = UI.Button(setmetatable({
                text = isLocked and "\xF0\x9F\x94\x92" or "\xF0\x9F\x94\x93",  -- 🔒 / 🔓
                onClick = function(self)
                    local newState = not lockedPaths_[rowPath]
                    lockedPaths_[rowPath] = newState
                    -- 节点级联到所有子节点，组件无子节点
                    if not rowIsComp and isAlive(rowItem) then
                        local childPaths = {}
                        collectChildPaths(rowItem, rowPath, childPaths)
                        for _, cp in ipairs(childPaths) do
                            lockedPaths_[cp] = newState
                        end
                    end
                    rebuildTree()
                    if selectedPath_ == rowPath then
                        rebuildDetail()
                    end
                end,
            }, { __index = lockBtnStyle }))

            -- 显隐按钮（SetEnabled）
            local isEnabled = row.isEnabled
            local visBtnStyle = {
                height = S(22), width = S(22), borderRadius = S(3),
                fontSize = S(12), fontFamily = FONT_FAMILY,
                variant = "ghost", paddingHorizontal = 0,
                backgroundColor = { 0, 0, 0, 0 },
                fontColor = isEnabled and T.TEXT_HINT or T.COLOR_RED,
            }
            rowChildren[#rowChildren + 1] = UI.Button(setmetatable({
                text = isEnabled and "\xF0\x9F\x91\x81" or "\xF0\x9F\x99\x88",  -- 👁 / 🙈
                onClick = function(self)
                    if isAlive(rowItem) then
                        local newState = not isEnabled
                        pcall(function() rowItem:SetEnabled(newState) end)
                        -- 节点级联到所有子节点及其组件
                        if not rowIsComp then
                            -- 先处理当前节点自身的组件
                            local selfComps = getNodeComponents(rowItem)
                            for ci = 1, #selfComps do
                                pcall(function() selfComps[ci]:SetEnabled(newState) end)
                            end
                            -- 再递归处理所有子节点及子节点的组件
                            local children = {}
                            pcall(function() children = rowItem:GetChildren(true) end)
                            for ci = 1, #children do
                                pcall(function() children[ci]:SetEnabled(newState) end)
                                local childComps = getNodeComponents(children[ci])
                                for ki = 1, #childComps do
                                    pcall(function() childComps[ki]:SetEnabled(newState) end)
                                end
                            end
                        end
                    end
                    rebuildTree()
                    if selectedPath_ == rowPath then
                        rebuildDetail()
                    end
                end,
            }, { __index = visBtnStyle }))
        end

        local rowPanel = UI.Panel {
            width = "100%", height = S(ROW_H),
            flexDirection = "row", alignItems = "center",
            paddingLeft = S(6) + row.depth * S(INDENT_PX),
            paddingRight = S(4),
            backgroundColor = rowBg,
            borderBottomWidth = S(1),
            borderColor = { 40, 35, 28, 100 },
            children = rowChildren,
        }

        treeInner_:AddChild(rowPanel)
    end

    if #rows == 0 then
        local emptyMsg = hasFilter
            and ("未找到与 \"" .. filterText_ .. "\" 相关的节点")
            or "无场景节点"
        treeInner_:AddChild(UI.Label {
            text = emptyMsg, fontSize = S(12), fontFamily = FONT_FAMILY,
            fontColor = T.TEXT_HINT, marginLeft = S(10), marginTop = S(10),
        })
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function SceneTreeView.Create(parentContainer)
    parentContainer_ = parentContainer

    -- 工具栏
    refreshBtn_ = UI.Button {
        text = "刷新", fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
        height = S(26), paddingHorizontal = S(10),
        borderRadius = S(4), variant = "ghost",
        borderWidth = S(1), borderColor = T.BORDER,
        backgroundColor = { 35, 32, 26, 255 },
        fontColor = T.TEXT_SECONDARY,
        onClick = function(self)
            rebuildTree()
            rebuildDetail()
        end,
    }

    local function updateAutoBtn()
        if not autoRefreshBtn_ then return end
        autoRefreshBtn_:SetStyle({
            borderColor = autoRefresh_ and T.ACCENT or T.BORDER,
            backgroundColor = autoRefresh_ and { 50, 42, 20, 255 } or { 35, 32, 26, 255 },
            fontColor = autoRefresh_ and T.ACCENT or T.TEXT_SECONDARY,
        })
    end
    autoRefreshBtn_ = UI.Button {
        text = "自动刷新", fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
        height = S(26), paddingHorizontal = S(10),
        borderRadius = S(4), variant = "ghost",
        borderWidth = S(1),
        onClick = function(self)
            autoRefresh_ = not autoRefresh_
            autoRefreshTimer_ = 0
            updateAutoBtn()
        end,
    }
    updateAutoBtn()

    local toolbar = UI.Panel {
        width = "100%", height = S(34),
        flexDirection = "row", alignItems = "center",
        gap = S(6), paddingHorizontal = S(8),
        backgroundColor = T.SECTION_BG,
        borderBottomWidth = S(1), borderColor = T.BORDER,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "场景层级树", fontSize = S(12), fontFamily = FONT_FAMILY,
                fontColor = T.ACCENT, flexGrow = 1,
            },
            refreshBtn_,
            autoRefreshBtn_,
        },
    }

    -- 上半：树 ScrollView
    treeInner_ = UI.Panel {
        width = "100%", flexDirection = "column",
    }
    treeScroll_ = UI.ScrollView {
        id = "sceneTreeScroll",
        width = "100%", flexGrow = 2, flexBasis = 0,
        backgroundColor = T.BG_DARK,
        children = { treeInner_ },
    }

    -- 分隔条
    local divider = UI.Panel {
        width = "100%", height = S(1),
        backgroundColor = T.BORDER,
        flexShrink = 0,
    }

    -- 下半：详情 ScrollView
    detailInner_ = UI.Panel {
        width = "100%", flexDirection = "column",
    }
    detailScroll_ = UI.ScrollView {
        id = "sceneTreeDetail",
        width = "100%", flexGrow = 3, flexBasis = 0,
        backgroundColor = T.BG_CARD,
        children = { detailInner_ },
    }

    parentContainer:AddChild(toolbar)
    parentContainer:AddChild(treeScroll_)
    parentContainer:AddChild(divider)
    parentContainer:AddChild(detailScroll_)

    rebuildDetail()
end

function SceneTreeView.Rebuild()
    tabActive_ = true
    rebuildTree()
    rebuildDetail()
end

function SceneTreeView.Update(dt)
    if not tabActive_ or not autoRefresh_ then return end
    autoRefreshTimer_ = autoRefreshTimer_ + dt
    if autoRefreshTimer_ >= AUTO_REFRESH_INTERVAL then
        autoRefreshTimer_ = 0
        rebuildTree()
        if isAlive(selectedItem_) then
            rebuildDetail()
        end
    end
end

--- 内部：执行全场景递归统计并更新缓存
local function refreshSummaryCache()
    local scn = getScene()
    local totalNodes = 0
    local totalComps = 0
    local maxDepth = 0
    local disabledCount = 0

    local function countNodes(node, depth)
        local children = {}
        pcall(function() children = node:GetChildren(false) end)
        for _, child in ipairs(children) do
            totalNodes = totalNodes + 1
            if depth > maxDepth then maxDepth = depth end
            local en = true
            pcall(function() en = child:IsEnabled() end)
            if not en then disabledCount = disabledCount + 1 end
            local nc = 0
            pcall(function() nc = child:GetNumComponents() end)
            totalComps = totalComps + nc
            countNodes(child, depth + 1)
        end
    end

    if scn then
        pcall(function() totalComps = totalComps + scn:GetNumComponents() end)
        countNodes(scn, 1)
    end

    cachedSummary_.totalNodes    = totalNodes
    cachedSummary_.totalComps    = totalComps
    cachedSummary_.maxDepth      = maxDepth
    cachedSummary_.disabledCount = disabledCount
    lastSummaryTime_ = time:GetElapsedTime()
end

--- 获取悬浮窗摘要信息（带缓存，避免每次调用都全场景遍历）
function SceneTreeView.GetFloatingSummary()
    local now = time:GetElapsedTime()
    if now - lastSummaryTime_ >= SUMMARY_CACHE_INTERVAL then
        refreshSummaryCache()
    end
    return cachedSummary_
end

function SceneTreeView.SetFilter(text)
    filterText_ = text or ""
    rebuildTree()
end

function SceneTreeView.GetFilter()
    return filterText_
end

function SceneTreeView.SetActive(active)
    tabActive_ = active
    if not active then
        autoRefreshTimer_ = 0
    end
end

function SceneTreeView.Destroy()
    tabActive_      = false
    selectedItem_   = nil
    selectedPath_   = ""
    selectedIsComp_ = false
    parentContainer_ = nil
    treeScroll_     = nil
    detailScroll_   = nil
    treeInner_      = nil
    detailInner_    = nil
    refreshBtn_     = nil
    autoRefreshBtn_ = nil
    autoRefreshTimer_ = 0
    expanded_ = {}
    filterText_ = ""
    -- lockedPaths_ 不清除：用户锁定的节点保持状态
    lastSummaryTime_ = -999
    cachedSummary_ = { totalNodes = 0, totalComps = 0, maxDepth = 0, disabledCount = 0 }
end

return SceneTreeView
