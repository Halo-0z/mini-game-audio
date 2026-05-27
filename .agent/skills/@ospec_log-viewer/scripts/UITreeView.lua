-- ============================================================================
-- UI 层级树视图 (UITreeView)
-- 功能：
--   1. 显示当前 UI 系统从 Root 开始的所有子节点层级树
--   2. 每个节点显示：名称(UI类型)，可展开/折叠
--   3. 点击节点：展开/折叠 + 选中，下方显示属性详情
--   4. 上半区域：可滚动的树列表
--   5. 下半区域：选中节点的属性详情面板（支持字段修改器）
-- ============================================================================

local UI = require("urhox-libs/UI")

local UITreeView = {}

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
    EDITOR_BG      = {  35,  30,  22, 255 },
    EDITOR_BORDER  = {  70,  58,  40, 200 },
}

local ROW_H       = 32
local INDENT_PX   = 18
local FONT_FAMILY = "sans"
local FONT_SIZE   = 11

--- ApplyScale 占位：常量保持原始设计值，使用点通过 S() 包裹
--- （避免 S(FONT_SIZE) 双重缩放）
function UITreeView.ApplyScale() end

-- ============================================================================
-- 内部状态
-- ============================================================================
local parentContainer_ = nil
local treeScroll_      = nil
local detailScroll_    = nil
local treeInner_       = nil
local detailInner_     = nil
local expanded_        = {}    -- path -> bool
local selectedWidget_  = nil   -- 当前选中的 widget
local selectedPath_    = ""    -- 当前选中的 path
local refs_            = {}    -- { panel, btn, scrollDownBtn }

-- LogViewer 自身节点 id 集合
local SELF_IDS = {
    logViewerPanel    = true,
    logViewerBtn      = true,
    logViewerFloating = true,
    uiTreeContent     = true,
    uiTreeScroll      = true,
    uiTreeDetail      = true,
}

-- 组件类型 → emoji 映射
local TYPE_EMOJI = {
    Panel      = "\xF0\x9F\x93\xA6",  -- 📦
    Label      = "\xF0\x9F\x8F\xB7",  -- 🏷
    Button     = "\xF0\x9F\x94\x98",  -- 🔘
    TextField  = "\xE2\x9C\x8F",      -- ✏
    TextArea   = "\xF0\x9F\x93\x9D",  -- 📝
    ScrollView = "\xF0\x9F\x93\x9C",  -- 📜
    Slider     = "\xF0\x9F\x8E\x9A",  -- 🎚
    Dropdown   = "\xF0\x9F\x94\xBD",  -- 🔽
    Checkbox   = "\xE2\x98\x91",      -- ☑
    Switch     = "\xF0\x9F\x94\x80",  -- 🔀
    Image      = "\xF0\x9F\x96\xBC",  -- 🖼
    List       = "\xF0\x9F\x93\x8B",  -- 📋
    VirtualList= "\xF0\x9F\x93\x8B",  -- 📋
    Tab        = "\xF0\x9F\x93\x91",  -- 📑
    Modal      = "\xF0\x9F\xAA\x9F",  -- 🪟
    Toast      = "\xF0\x9F\x92\xAC",  -- 💬
    Progress   = "\xF0\x9F\x93\x8A",  -- 📊
    Badge      = "\xF0\x9F\x94\xB4",  -- 🔴
    Avatar     = "\xF0\x9F\x91\xA4",  -- 👤
    Divider    = "\xE2\x94\x80",      -- ─
    Spacer     = "\xE2\xAC\x9C",      -- ⬜
}
local DEFAULT_EMOJI = "\xE2\x97\xBB"  -- ◻

-- 锁定和隐藏状态
local lockedPaths_  = {}   -- path -> bool  锁定状态
local hiddenPaths_  = {}   -- path -> bool  隐藏状态

-- 搜索过滤
local filterText_           = ""   -- 当前搜索关键字

-- 自动刷新
local AUTO_REFRESH_INTERVAL = 2.0
local autoRefresh_          = false
local autoRefreshTimer_     = 0
local autoRefreshBtn_       = nil
local refreshBtn_           = nil
local tabActive_            = false

-- 内联展开状态
local expandedColorKey_  = nil   -- 当前展开颜色选择器的 prop key（nil = 无展开）
local expandedImageKey_  = nil   -- 当前展开图片浏览器的 prop key（nil = 无展开）
local cpHexField_        = nil   -- ColorPicker 内联 hex 输入框引用

-- ============================================================================
-- 工具函数
-- ============================================================================

local function isLogViewerSelf(widget)
    if not widget or not widget.props then return false end
    local id = widget.props.id
    if id and SELF_IDS[id] then return true end
    if refs_.btn and widget == refs_.btn then return true end
    if refs_.scrollDownBtn and widget == refs_.scrollDownBtn then return true end
    if refs_.panel and widget == refs_.panel then return true end
    return false
end

--- 检查 widget 是否仍然有效（未被销毁）
local function isWidgetAlive(widget)
    if not widget then return false end
    -- 检查关键属性是否可访问
    local ok, cls = pcall(function() return widget._className end)
    if not ok or not cls then return false end
    return true
end

--- 将字符串中的真实换行符替换为可见的转义表示
local function escapeNewlines(s)
    s = s:gsub("\r\n", "\\n")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function getNodeLabel(widget)
    local cls = widget._className or "Widget"
    local emoji = TYPE_EMOJI[cls] or DEFAULT_EMOJI
    local id  = widget.props and widget.props.id or nil
    local name = id or ""
    if name ~= "" then
        return emoji .. " " .. escapeNewlines(name) .. " (" .. cls .. ")"
    end
    if widget.props and widget.props.text then
        local txt = tostring(widget.props.text)
        txt = escapeNewlines(txt)
        if #txt > 16 then txt = txt:sub(1, 16) .. ".." end
        return emoji .. ' "' .. txt .. '" (' .. cls .. ")"
    end
    return emoji .. " (" .. cls .. ")"
end

local function makePathKey(parentPath, index)
    if parentPath == "" then return tostring(index) end
    return parentPath .. "." .. tostring(index)
end

--- 递归收集指定 widget 的所有后代路径（用于级联锁定/隐藏）
local function collectDescendantPaths(widget, parentPath, result)
    local children = widget:GetChildren()
    if not children then return end
    for i, child in ipairs(children) do
        if not isLogViewerSelf(child) then
            local path = makePathKey(parentPath, i)
            result[#result + 1] = { path = path, widget = child }
            collectDescendantPaths(child, path, result)
        end
    end
end

-- ============================================================================
-- 属性分类定义
-- ============================================================================

local SIZE_KEYS = {
    width=S(1), height=S(1), minWidth=S(1), minHeight=S(1), maxWidth=S(1), maxHeight=S(1),
    position=1, left=S(1), top=S(1), right=S(1), bottom=S(1), aspectRatio=1,
}
local FLEX_KEYS = {
    flexDirection=1, flexGrow=1, flexShrink=1, flexBasis=1, flexWrap=1, flex=1,
    justifyContent=1, alignItems=1, alignSelf=1, alignContent=1,
    gap=S(1), rowGap=1, columnGap=1,
}
local SPACING_KEYS = {
    padding=S(1), paddingLeft=S(1), paddingRight=S(1), paddingTop=S(1), paddingBottom=S(1),
    paddingHorizontal=S(1), paddingVertical=S(1),
    margin=S(1), marginLeft=S(1), marginRight=S(1), marginTop=S(1), marginBottom=S(1),
    marginHorizontal=S(1), marginVertical=S(1),
}
local VISUAL_KEYS = {
    backgroundColor=1, fontColor=1, fontFamily=1, fontSize=1,
    borderColor=1, borderWidth=1, borderRadius=1, opacity=1, overflow=1, zIndex=1,
    borderTopWidth=1, borderBottomWidth=1, borderLeftWidth=1, borderRightWidth=1,
    borderTopColor=1, borderBottomColor=1, borderLeftColor=1, borderRightColor=1,
    borderRadiusTopLeft=1, borderRadiusTopRight=1, borderRadiusBottomRight=1, borderRadiusBottomLeft=1,
    shape=1,
}
local BG_KEYS = {
    backgroundImage=1, backgroundFit=1, backgroundSlice=1, imageTint=1, backgroundGradient=1,
}
local SHADOW_KEYS = {
    backdropBlur=1, boxShadow=1, shadowBlur=1, shadowX=1, shadowY=1, shadowColor=1,
}
local TRANSFORM_KEYS = {
    scale=1, rotate=1, translateX=1, translateY=1, transformOrigin=1, visibility=1,
    transition=1,
}
local BEHAVIOR_KEYS = {
    pointerEvents=1, allowOverflow=1, cursor=1, clipPath=1, stickyOffset=1,
}
-- 基本信息中已单独展示的 key
local BASIC_KEYS = { id=1, text=1, visible=1 }

--- 判断属性是否应该显示
local function shouldShowProp(key, value)
    if type(key) ~= "string" then return false end
    if key:sub(1, 1) == "_" then return false end
    if type(value) == "function" then return false end
    if type(value) == "userdata" then return false end
    if key == "children" then return false end
    return true
end

--- 获取字体族名称列表（引擎内置字体）
local function getRegisteredFontFamilies()
    return { "sans" }
end

--- 推断属性值的编辑类型
--- @return "bool"|"number"|"string"|"color"|"enum"|"readonly"
local function getEditType(key, value)
    local vt = type(value)
    if vt == "boolean" then return "bool" end
    if vt == "number"  then return "number" end
    if vt == "string"  then
        -- 枚举型字段检测
        if key == "flexDirection" or key == "justifyContent" or key == "alignItems"
            or key == "alignSelf" or key == "alignContent" or key == "flexWrap"
            or key == "position" or key == "overflow" or key == "shape"
            or key == "pointerEvents" or key == "visibility" or key == "backgroundFit"
            or key == "cursor" or key == "fontFamily"
            or key == "textAlign" or key == "verticalAlign"
            or key == "display" or key == "fontWeight" then
            return "enum"
        end
        return "string"
    end
    if vt == "table" then
        -- 颜色数组 (4元素 RGBA)
        if #value == 4 and type(value[1]) == "number" then return "color" end
        return "readonly"
    end
    return "readonly"
end

--- 获取枚举型字段的可选值列表
local function getEnumOptions(key)
    local enums = {
        flexDirection  = { "row", "column", "row-reverse", "column-reverse" },
        justifyContent = { "flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly" },
        alignItems     = { "flex-start", "center", "flex-end", "stretch", "baseline" },
        alignSelf      = { "auto", "flex-start", "center", "flex-end", "stretch", "baseline" },
        alignContent   = { "flex-start", "center", "flex-end", "stretch", "space-between", "space-around" },
        flexWrap       = { "nowrap", "wrap", "wrap-reverse" },
        position       = { "relative", "absolute", "sticky" },
        overflow       = { "visible", "hidden", "scroll" },
        shape          = { "rect", "circle" },
        pointerEvents  = { "auto", "none" },
        visibility     = { "visible", "hidden" },
        backgroundFit  = { "fill", "contain", "cover", "none" },
        cursor         = { "default", "pointer", "text", "move", "not-allowed" },
        fontFamily     = getRegisteredFontFamilies(),
        textAlign      = { "left", "center", "right" },
        verticalAlign  = { "top", "middle", "bottom" },
        display        = { "flex", "none" },
        fontWeight     = { "normal", "bold" },
    }
    return enums[key] or {}
end

--- 格式化属性值为字符串
local function formatValue(v)
    local t = type(v)
    if t == "string" then
        if #v > 60 then return '"' .. v:sub(1, 60) .. '..."' end
        return '"' .. v .. '"'
    elseif t == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return string.format("%.2f", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local arr = {}
        for i = 1, math.min(#v, 8) do arr[i] = tostring(v[i]) end
        if #arr > 0 then
            local s = "{ " .. table.concat(arr, ", ") .. " }"
            if #v > 8 then s = s .. " ..." end
            return s
        end
        local parts = {}
        local count = 0
        for k, val in pairs(v) do
            if type(k) == "string" and count < 6 then
                parts[#parts + 1] = k .. "=" .. tostring(val)
                count = count + 1
            end
        end
        if #parts > 0 then
            table.sort(parts)
            return "{ " .. table.concat(parts, ", ") .. " }"
        end
        return "{}"
    end
    return tostring(v)
end

--- 格式化纯显示值（不带引号的 string）
local function formatDisplayValue(v)
    local t = type(v)
    if t == "string" then return v end
    if t == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return string.format("%.2f", v)
    end
    if t == "boolean" then return tostring(v) end
    return formatValue(v)
end

-- ============================================================================
-- 前向声明（解决交叉引用）
-- ============================================================================
local rebuildTree
local rebuildDetail

-- ============================================================================
-- 属性修改应用
-- ============================================================================

--- 将修改后的值应用到 widget
local function applyPropChange(widget, key, newValue)
    if not isWidgetAlive(widget) then return end
    -- 使用 SetStyle 确保 Yoga 布局同步更新
    widget:SetStyle({ [key] = newValue })
end

--- 属性变更后统一刷新（树 + 详情）
local function refreshAfterEdit()
    rebuildTree()
    rebuildDetail()
end

-- ============================================================================
-- 树构建
-- ============================================================================

local function buildTreeRows(widget, depth, parentPath, rows)
    local children = widget:GetChildren()
    if not children then return end
    for i, child in ipairs(children) do
        if not isLogViewerSelf(child) then
            local path = makePathKey(parentPath, i)
            local childChildren = child:GetChildren()
            local hasChildren = childChildren and #childChildren > 0
            local isExpanded = expanded_[path] == true

            rows[#rows + 1] = {
                depth       = depth,
                widget      = child,
                path        = path,
                hasChildren = hasChildren,
                isExpanded  = isExpanded,
            }

            if hasChildren and isExpanded then
                buildTreeRows(child, depth + 1, path, rows)
            end
        end
    end
end

-- ============================================================================
-- 搜索过滤辅助函数
-- ============================================================================

--- 递归扫描 UI 树，找出匹配节点及其祖先链
local function preFilterScan(root, filterLower)
    local directMatch = {}
    local visible     = {}

    local function scanWidget(widget, parentPath)
        local anyMatch = false
        local children = widget:GetChildren()
        if not children then return false end
        for i, child in ipairs(children) do
            if not isLogViewerSelf(child) then
                local path = makePathKey(parentPath, i)
                local label = getNodeLabel(child)
                local selfMatch = string.find(string.lower(label), filterLower, 1, true) ~= nil
                local descendantMatch = scanWidget(child, path)
                if selfMatch then
                    directMatch[path] = true
                    visible[path] = true
                    anyMatch = true
                elseif descendantMatch then
                    visible[path] = true
                    anyMatch = true
                end
            end
        end
        return anyMatch
    end

    local rootMatch = scanWidget(root, "R")
    if rootMatch then visible["R"] = true end
    return visible, directMatch
end

--- 构建过滤后的树行（仅保留可见路径，自动展开祖先节点）
local function buildFilteredTreeRows(widget, depth, parentPath, rows, visible, directMatch)
    local children = widget:GetChildren()
    if not children then return end
    for i, child in ipairs(children) do
        if not isLogViewerSelf(child) then
            local path = makePathKey(parentPath, i)
            if not visible[path] then goto continue end

            -- 检查在过滤视图中是否有可见子项
            local childChildren = child:GetChildren()
            local hasVisibleChild = false
            if childChildren then
                for j, gc in ipairs(childChildren) do
                    if not isLogViewerSelf(gc) and visible[makePathKey(path, j)] then
                        hasVisibleChild = true
                        break
                    end
                end
            end

            rows[#rows + 1] = {
                depth       = depth,
                widget      = child,
                path        = path,
                hasChildren = hasVisibleChild,
                isExpanded  = hasVisibleChild,  -- 过滤模式下自动展开
                isMatch     = directMatch[path] or false,
            }

            if hasVisibleChild then
                buildFilteredTreeRows(child, depth + 1, path, rows, visible, directMatch)
            end
            ::continue::
        end
    end
end

-- ============================================================================
-- 字段编辑器 UI 创建
-- ============================================================================

--- 创建布尔值下拉编辑器
local function createBoolEditor(widget, key, currentValue)
    return UI.Dropdown {
        height = S(24), width = S(80), fontSize = S(10), fontFamily = FONT_FAMILY,
        borderRadius = S(3),
        backgroundColor = T.EDITOR_BG,
        borderWidth = S(1), borderColor = T.EDITOR_BORDER,
        options = {
            { value = true,  label = "true" },
            { value = false, label = "false" },
        },
        value = currentValue,
        maxVisibleItems = 2,
        itemHeight = S(24),
        onChange = function(self, value)
            applyPropChange(widget, key, value)
            refreshAfterEdit()
        end,
    }
end

--- 创建枚举下拉编辑器
local function createEnumEditor(widget, key, currentValue)
    local opts = getEnumOptions(key)
    -- 使用内联选项按钮组（chip selector），避免 Dropdown overlay 底部溢出
    local chips = {}
    for _, v in ipairs(opts) do
        local isActive = (tostring(currentValue) == tostring(v))
        chips[#chips + 1] = UI.Button {
            text = v, fontSize = S(9), fontFamily = FONT_FAMILY,
            height = S(22), paddingHorizontal = S(6), borderRadius = S(3),
            variant = "ghost",
            backgroundColor = isActive and { 80, 65, 40, 255 } or T.EDITOR_BG,
            fontColor = isActive and T.ACCENT or T.TEXT_PRIMARY,
            borderWidth = S(1),
            borderColor = isActive and T.ACCENT or T.EDITOR_BORDER,
            onClick = function(self)
                applyPropChange(widget, key, v)
                refreshAfterEdit()
            end,
        }
    end
    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = S(3),
        flexWrap = "wrap", flexShrink = 1, flexGrow = 1,
        children = chips,
    }
end

--- 创建数值编辑器（输入框 + / - 按钮）
local function createNumberEditor(widget, key, currentValue)
    local displayVal = formatDisplayValue(currentValue)

    -- 根据数值大小自适应步长
    local absVal = math.abs(currentValue)
    local step = 1
    if absVal < 2 then step = 0.1
    elseif absVal < 20 then step = 1
    else step = math.max(1, math.floor(absVal * 0.05))
    end
    -- 小数属性保持小数步长
    if currentValue ~= math.floor(currentValue) then
        step = math.min(step, 0.1)
    end

    ---@type Widget
    local field = nil
    field = UI.TextField {
        value = displayVal,
        height = S(24), width = S(60), fontSize = S(10), fontFamily = FONT_FAMILY,
        borderRadius = S(3),
        backgroundColor = T.EDITOR_BG,
        borderWidth = S(1), borderColor = T.EDITOR_BORDER,
        paddingHorizontal = S(4),
        onSubmit = function(selfW, text)
            local num = tonumber(text)
            if num then
                applyPropChange(widget, key, num)
                refreshAfterEdit()
            else
                field:SetStyle({ value = formatDisplayValue(widget.props[key]) })
            end
        end,
    }

    local btnStyle = {
        height = S(24), width = S(24), borderRadius = S(3),
        fontSize = S(14), fontFamily = FONT_FAMILY,
        backgroundColor = { 40, 35, 28, 255 },
        borderWidth = S(1), borderColor = T.EDITOR_BORDER,
        fontColor = T.TEXT_SECONDARY,
        variant = "ghost",
    }

    local minusBtn = UI.Button(setmetatable({ text = "-",
        onClick = function(self)
            local cur = widget.props[key] or 0
            local newVal = cur - step
            if cur == math.floor(cur) and step >= 1 then
                newVal = math.floor(newVal + 0.5)
            end
            applyPropChange(widget, key, newVal)
            field:SetStyle({ value = formatDisplayValue(newVal) })
            rebuildTree()
        end,
    }, { __index = btnStyle }))

    local plusBtn = UI.Button(setmetatable({ text = "+",
        onClick = function(self)
            local cur = widget.props[key] or 0
            local newVal = cur + step
            if cur == math.floor(cur) and step >= 1 then
                newVal = math.floor(newVal + 0.5)
            end
            applyPropChange(widget, key, newVal)
            field:SetStyle({ value = formatDisplayValue(newVal) })
            rebuildTree()
        end,
    }, { __index = btnStyle }))

    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = S(2),
        flexShrink = 1, flexGrow = 1,
        children = { minusBtn, field, plusBtn },
    }
end

--- 创建字符串编辑器（onChange 实时更新，不必按回车）
local function createStringEditor(widget, key, currentValue)
    return UI.TextField {
        value = tostring(currentValue or ""),
        height = S(24), fontSize = S(10), fontFamily = FONT_FAMILY,
        borderRadius = S(3),
        flexShrink = 1, flexGrow = 1,
        backgroundColor = T.EDITOR_BG,
        borderWidth = S(1), borderColor = T.EDITOR_BORDER,
        paddingHorizontal = S(4),
        onChange = function(self, text)
            applyPropChange(widget, key, text)
        end,
        onSubmit = function(self, text)
            applyPropChange(widget, key, text)
            refreshAfterEdit()
        end,
    }
end

--- 扫描可用图片文件
--- 由于运行时沙箱禁用了 GetCurrentDir / GetResourceFileName / ScanDir 等 API，
--- 改为：遍历当前 UI 树收集所有 backgroundImage 属性值 + cache:Exists 验证
local function scanImageFiles()
    local images = {}
    local seen = {}

    -- 方式1：从 UI 树中收集所有正在使用的 backgroundImage 路径
    local root = UI.GetRoot()
    if root then
        local function collectImages(w)
            if isLogViewerSelf(w) then return end
            local props = w.props
            if props and props.backgroundImage then
                local p = tostring(props.backgroundImage)
                if p ~= "" and not seen[p] then
                    -- 用 cache:Exists 验证资源有效
                    local ok, exists = pcall(function() return cache:Exists(p) end)
                    if ok and exists then
                        seen[p] = true
                        images[#images + 1] = p
                    end
                end
            end
            local children = w:GetChildren()
            if children then
                for _, child in ipairs(children) do
                    collectImages(child)
                end
            end
        end
        collectImages(root)
    end

    -- 方式2：用 cache:Exists 探测已知常见路径模式
    if cache then
        local probeList = {
            -- global
            "image/global/login_enter_button.png",
            "image/global/login_server_popup_panel.png",
            "image/global/button_beige.png",
            "image/global/popup_button_cancel.png",
            "image/global/popup_button_ok.png",
            "image/global/close.png",
            "image/global/panel_bg.png",
            -- lobby icons
            "image/lobby/icons/currency_coin.png",
            "image/lobby/icons/currency_energy.png",
            "image/lobby/icons/currency_jade.png",
            "image/lobby/icons/hero_avatar.png",
            "image/lobby/icons/hero_card_1.png",
            "image/lobby/icons/hero_card_2.png",
            "image/lobby/icons/hero_card_3.png",
            "image/lobby/icons/hero_card_4.png",
            "image/lobby/icons/hero_card_5.png",
            "image/lobby/icons/nav_lock.png",
            "image/lobby/icons/nav_market.png",
            "image/lobby/icons/nav_role.png",
            "image/lobby/icons/nav_sect.png",
            "image/lobby/icons/nav_skill.png",
            "image/lobby/icons/nav_town.png",
            "image/lobby/icons/reward_blue_chest.png",
            "image/lobby/icons/reward_gold_chest.png",
            "image/lobby/icons/reward_purple_chest.png",
            "image/lobby/icons/side_bag.png",
            "image/lobby/icons/side_cave.png",
            "image/lobby/icons/side_event.png",
            "image/lobby/icons/side_fate.png",
            "image/lobby/icons/side_friend.png",
            "image/lobby/icons/side_mail.png",
            "image/lobby/icons/side_rank.png",
            "image/lobby/icons/side_settings.png",
            "image/lobby/icons/side_stage.png",
            "image/lobby/icons/side_task.png",
            -- backgrounds
            "image/loginbg/login_bg.jpg",
        }
        for _, p in ipairs(probeList) do
            if not seen[p] then
                local ok, exists = pcall(function() return cache:Exists(p) end)
                if ok and exists then
                    seen[p] = true
                    images[#images + 1] = p
                end
            end
        end
    end

    table.sort(images)
    return images
end

--- 创建图片路径编辑器（输入框 + 浏览按钮，点击浏览在详情面板内联展开图片列表）
local function createImagePathEditor(widget, key, currentValue)
    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = S(2),
        flexShrink = 1, flexGrow = 1,
        children = {
            UI.TextField {
                value = tostring(currentValue or ""),
                height = S(24), fontSize = S(10), fontFamily = FONT_FAMILY,
                borderRadius = S(3),
                flexShrink = 1, flexGrow = 1,
                backgroundColor = T.EDITOR_BG,
                borderWidth = S(1), borderColor = T.EDITOR_BORDER,
                paddingHorizontal = S(4),
                onSubmit = function(self, text)
                    applyPropChange(widget, key, text)
                    refreshAfterEdit()
                end,
            },
            UI.Button {
                text = "浏览", fontSize = S(10), fontFamily = FONT_FAMILY,
                height = S(24), paddingHorizontal = S(6), borderRadius = S(3),
                variant = "ghost",
                backgroundColor = { 50, 45, 35, 255 },
                borderWidth = S(1), borderColor = T.EDITOR_BORDER,
                fontColor = T.TEXT_SECONDARY,
                onClick = function(self)
                    -- 切换内联展开状态
                    if expandedImageKey_ == key then
                        expandedImageKey_ = nil
                    else
                        expandedImageKey_ = key
                    end
                    rebuildDetail()
                end,
            },
        },
    }
end

--- 解析 hex 颜色字符串为 r,g,b（失败返回 nil）
local function parseHexColor(hex)
    hex = hex:gsub("^#", ""):upper()
    if #hex == 6 then
        local rr = tonumber(hex:sub(1, 2), 16)
        local gg = tonumber(hex:sub(3, 4), 16)
        local bb = tonumber(hex:sub(5, 6), 16)
        if rr and gg and bb then return rr, gg, bb end
    elseif #hex == 3 then
        local rr = tonumber(hex:sub(1, 1) .. hex:sub(1, 1), 16)
        local gg = tonumber(hex:sub(2, 2) .. hex:sub(2, 2), 16)
        local bb = tonumber(hex:sub(3, 3) .. hex:sub(3, 3), 16)
        if rr and gg and bb then return rr, gg, bb end
    end
    return nil
end

--- 创建颜色编辑器（RGBA 色块预览 + hex 输入 + 点击内联展开 ColorPicker）
local function createColorEditor(widget, key, currentValue)
    local r = math.floor(currentValue[1] or 0)
    local g = math.floor(currentValue[2] or 0)
    local b = math.floor(currentValue[3] or 0)
    local a = math.floor(currentValue[4] or 255)
    local hexStr = string.format("#%02X%02X%02X", r, g, b)
    local isExpanded = (expandedColorKey_ == key)
    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = S(4),
        flexShrink = 1, flexGrow = 1,
        children = {
            -- 色块预览（可点击切换展开）
            UI.Panel {
                width = S(20), height = S(20),
                borderRadius = S(3), borderWidth = S(1),
                borderColor = isExpanded and T.ACCENT or T.BORDER,
                backgroundColor = { r, g, b, a },
                cursor = "pointer",
                onClick = function(self)
                    if expandedColorKey_ == key then
                        expandedColorKey_ = nil
                    else
                        expandedColorKey_ = key
                    end
                    rebuildDetail()
                end,
            },
            -- hex 值可编辑输入框
            UI.TextField {
                value = hexStr,
                height = S(22), width = S(72), fontSize = S(10), fontFamily = FONT_FAMILY,
                borderRadius = S(3),
                backgroundColor = T.EDITOR_BG,
                borderWidth = S(1), borderColor = T.EDITOR_BORDER,
                paddingHorizontal = S(4),
                flexShrink = 0,
                onSubmit = function(self, text)
                    local nr, ng, nb = parseHexColor(text)
                    if nr then
                        local newColor = { nr, ng, nb, a }
                        applyPropChange(widget, key, newColor)
                        self:SetStyle({ value = string.format("#%02X%02X%02X", nr, ng, nb) })
                        rebuildTree()
                    else
                        -- 输入无效，恢复原值
                        self:SetStyle({ value = hexStr })
                    end
                end,
            },
            UI.Label {
                text = string.format("(%d,%d,%d,%d)", r, g, b, a),
                fontSize = S(9), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_HINT,
                flexShrink = 1,
            },
        },
    }
end

-- ============================================================================
-- 详情面板构建
-- ============================================================================

local function createSectionHeader(title)
    return UI.Panel {
        width = "100%", height = S(26),
        paddingLeft = S(10), justifyContent = "center",
        backgroundColor = T.SECTION_BG,
        borderBottomWidth = S(1), borderColor = T.SECTION_BORDER,
        flexShrink = 0,
        children = {
            UI.Label {
                text = title, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.ACCENT,
            },
        },
    }
end

--- 创建属性行（含编辑器）
local function createEditablePropRow(widget, key, value, isAlt)
    local editType = getEditType(key, value)
    local editorWidget = nil

    -- 特殊字段编辑器
    if key == "backgroundImage" then
        editorWidget = createImagePathEditor(widget, key, value)
    elseif editType == "bool" then
        editorWidget = createBoolEditor(widget, key, value)
    elseif editType == "number" then
        editorWidget = createNumberEditor(widget, key, value)
    elseif editType == "string" then
        editorWidget = createStringEditor(widget, key, value)
    elseif editType == "enum" then
        editorWidget = createEnumEditor(widget, key, value)
    elseif editType == "color" then
        editorWidget = createColorEditor(widget, key, value)
    else
        -- readonly
        editorWidget = UI.Label {
            text = formatValue(value), fontSize = S(10), fontFamily = FONT_FAMILY,
            fontColor = T.TEXT_PRIMARY,
            flexShrink = 1, flexGrow = 1,
        }
    end

    return UI.Panel {
        width = "100%", minHeight = S(28),
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(2),
        backgroundColor = isAlt and { 28, 24, 18, 255 } or { 22, 18, 14, 255 },
        children = {
            UI.Label {
                text = key, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_SECONDARY,
                width = S(120), flexShrink = 0,
            },
            editorWidget,
        },
    }
end

--- 创建只读属性行
local function createReadonlyPropRow(label, value, isAlt)
    return UI.Panel {
        width = "100%", minHeight = S(24),
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = S(10), paddingVertical = S(2),
        backgroundColor = isAlt and { 28, 24, 18, 255 } or { 22, 18, 14, 255 },
        children = {
            UI.Label {
                text = label, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_SECONDARY,
                width = S(120), flexShrink = 0,
            },
            UI.Label {
                text = tostring(value), fontSize = S(10), fontFamily = FONT_FAMILY,
                fontColor = T.TEXT_PRIMARY,
                flexShrink = 1, flexGrow = 1,
            },
        },
    }
end

--- 重建详情面板
rebuildDetail = function()
    if not detailInner_ then return end
    detailInner_:RemoveAllChildren()

    if not isWidgetAlive(selectedWidget_) then
        selectedWidget_ = nil
        selectedPath_ = ""
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

    local w = selectedWidget_
    local rows = {}
    local alt = false
    local isLocked = lockedPaths_[selectedPath_] == true

    -- 锁定提示条
    if isLocked then
        rows[#rows + 1] = UI.Panel {
            width = "100%", height = S(26),
            paddingHorizontal = S(10), justifyContent = "center",
            backgroundColor = { 60, 45, 25, 255 },
            borderBottomWidth = S(1), borderColor = T.ACCENT,
            flexShrink = 0,
            children = {
                UI.Label {
                    text = "\xF0\x9F\x94\x92 已锁定 - 只读模式",
                    fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                    fontColor = T.ACCENT,
                },
            },
        }
    end

    -- 选择编辑行创建函数：锁定时用只读行
    local function makePropRow(widget, key, value, isAltRow)
        if isLocked then
            return createReadonlyPropRow(key, formatValue(value), isAltRow)
        else
            return createEditablePropRow(widget, key, value, isAltRow)
        end
    end

    -- ===================== 基本信息 =====================
    rows[#rows + 1] = createSectionHeader("基本信息")
    alt = false
    rows[#rows + 1] = createReadonlyPropRow("类型", w._className or "Widget", alt); alt = not alt
    if w.props.id then
        rows[#rows + 1] = createReadonlyPropRow("ID", w.props.id, alt); alt = not alt
    end
    if w.props.text then
        local txt = tostring(w.props.text)
        if #txt > 80 then txt = txt:sub(1, 80) .. "..." end
        rows[#rows + 1] = makePropRow(w, "text", w.props.text, alt); alt = not alt
    end
    local childCount = w:GetChildren() and #w:GetChildren() or 0
    rows[#rows + 1] = createReadonlyPropRow("子节点数", childCount, alt); alt = not alt
    -- visible 使用 bool 编辑器
    rows[#rows + 1] = makePropRow(w, "visible", w.visible ~= false, alt); alt = not alt

    -- ===================== 计算布局 (Layout) - 只读 =====================
    local layout = w:GetLayout()
    if layout then
        rows[#rows + 1] = createSectionHeader("计算布局 (只读)")
        alt = false
        rows[#rows + 1] = createReadonlyPropRow("x", string.format("%.1f", layout.x or 0), alt); alt = not alt
        rows[#rows + 1] = createReadonlyPropRow("y", string.format("%.1f", layout.y or 0), alt); alt = not alt
        rows[#rows + 1] = createReadonlyPropRow("width", string.format("%.1f", layout.w or 0), alt); alt = not alt
        rows[#rows + 1] = createReadonlyPropRow("height", string.format("%.1f", layout.h or 0), alt); alt = not alt
    end

    -- ===================== 绝对布局 (Absolute) - 只读 =====================
    if w.GetAbsoluteLayout then
        local absLayout = w:GetAbsoluteLayout()
        if absLayout and absLayout.w == absLayout.w then
            rows[#rows + 1] = createSectionHeader("绝对布局 (只读)")
            alt = false
            rows[#rows + 1] = createReadonlyPropRow("absX", string.format("%.1f", absLayout.x or 0), alt); alt = not alt
            rows[#rows + 1] = createReadonlyPropRow("absY", string.format("%.1f", absLayout.y or 0), alt); alt = not alt
            rows[#rows + 1] = createReadonlyPropRow("absW", string.format("%.1f", absLayout.w or 0), alt); alt = not alt
            rows[#rows + 1] = createReadonlyPropRow("absH", string.format("%.1f", absLayout.h or 0), alt); alt = not alt
        end
    end

    -- ===================== 分类展示 props =====================
    local sizeProps      = {}
    local flexProps      = {}
    local spacingProps   = {}
    local visualProps    = {}
    local bgProps        = {}
    local shadowProps    = {}
    local transformProps = {}
    local behaviorProps  = {}
    local otherProps     = {}

    for k, v in pairs(w.props) do
        if shouldShowProp(k, v) and not BASIC_KEYS[k] then
            if SIZE_KEYS[k]      then sizeProps[k] = v
            elseif FLEX_KEYS[k]  then flexProps[k] = v
            elseif SPACING_KEYS[k] then spacingProps[k] = v
            elseif VISUAL_KEYS[k]  then visualProps[k] = v
            elseif BG_KEYS[k]     then bgProps[k] = v
            elseif SHADOW_KEYS[k]  then shadowProps[k] = v
            elseif TRANSFORM_KEYS[k] then transformProps[k] = v
            elseif BEHAVIOR_KEYS[k]  then behaviorProps[k] = v
            else otherProps[k] = v
            end
        end
    end

    local function addEditableSection(title, propsTable)
        local keys = {}
        for k in pairs(propsTable) do keys[#keys + 1] = k end
        if #keys == 0 then return end
        table.sort(keys)
        rows[#rows + 1] = createSectionHeader(title)
        alt = false
        for _, k in ipairs(keys) do
            rows[#rows + 1] = makePropRow(w, k, propsTable[k], alt)
            alt = not alt

            -- 内联 ColorPicker 展开（锁定时跳过）
            if not isLocked and expandedColorKey_ == k and getEditType(k, propsTable[k]) == "color" then
                local ColorPicker = require("urhox-libs/UI/Widgets/ColorPicker")
                local rgba = propsTable[k]
                -- 注意：不要 ScrollToBottom，否则 swatch 被推到底部边缘，
                -- ColorPicker popup 向下渲染会超出面板。保持当前滚动位置即可。
                local cpRow = UI.Panel {
                    width = "100%",
                    paddingHorizontal = S(10), paddingTop = S(6), paddingBottom = S(14),
                    backgroundColor = { 35, 30, 22, 255 },
                    borderBottomWidth = S(1), borderColor = T.SECTION_BORDER,
                    flexDirection = "column", gap = S(4),
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%",
                            children = {
                                UI.Label {
                                    text = "颜色选择 - " .. k,
                                    fontSize = S(10), fontFamily = FONT_FAMILY,
                                    fontColor = T.ACCENT,
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
                            value = { r = rgba[1] or 0, g = rgba[2] or 0, b = rgba[3] or 0, a = rgba[4] or 255 },
                            size = "sm",
                            pickerSize = S(140),
                            showInput = false,  -- 隐藏 popup 内只读 NanoVG HEX，用下方真实输入框替代
                            presets = {
                                "#F44336", "#E91E63", "#9C27B0", "#3F51B5",
                                "#2196F3", "#00BCD4", "#4CAF50", "#8BC34A",
                                "#FFEB3B", "#FF9800", "#FF5722", "#000000",
                            },
                            onChange = function(self, value)
                                local vr = math.floor(value.r)
                                local vg = math.floor(value.g)
                                local vb = math.floor(value.b)
                                local va = math.floor(value.a)
                                local newColor = { vr, vg, vb, va }
                                applyPropChange(w, k, newColor)
                                -- 同步更新可编辑 hex 输入框
                                if cpHexField_ then
                                    cpHexField_:SetStyle({
                                        value = string.format("#%02X%02X%02X%02X", vr, vg, vb, va),
                                    })
                                end
                                rebuildTree()
                            end,
                        },
                        -- 可编辑 HEX 输入框（替代 popup 内只读 NanoVG HEX 文本）
                        (function()
                            local initR = math.floor(rgba[1] or 0)
                            local initG = math.floor(rgba[2] or 0)
                            local initB = math.floor(rgba[3] or 0)
                            local initA = math.floor(rgba[4] or 255)
                            local initHex = string.format("#%02X%02X%02X%02X", initR, initG, initB, initA)
                            local hexRow = UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = S(6),
                                width = "100%", paddingTop = S(4),
                                children = {
                                    UI.Label {
                                        text = "HEX:", fontSize = S(10), fontFamily = FONT_FAMILY,
                                        fontColor = T.TEXT_SECONDARY, flexShrink = 0, width = S(32),
                                    },
                                    (function()
                                        cpHexField_ = UI.TextField {
                                            value = initHex,
                                            height = S(26), fontSize = S(11), fontFamily = FONT_FAMILY,
                                            borderRadius = S(3), flexGrow = 1, flexShrink = 1,
                                            backgroundColor = T.EDITOR_BG,
                                            borderWidth = S(1), borderColor = T.EDITOR_BORDER,
                                            paddingHorizontal = S(6),
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
                                                    na = initA
                                                end
                                                if nr and ng and nb and na then
                                                    local newColor = { nr, ng, nb, na }
                                                    applyPropChange(w, k, newColor)
                                                    self:SetStyle({ value = string.format("#%02X%02X%02X%02X", nr, ng, nb, na) })
                                                    rebuildTree()
                                                else
                                                    self:SetStyle({ value = initHex })
                                                end
                                            end,
                                        }
                                        return cpHexField_
                                    end)(),
                                },
                            }
                            return hexRow
                        end)(),
                    },
                }
                rows[#rows + 1] = cpRow
            end

            -- 内联图片浏览器展开（锁定时跳过）
            if not isLocked and expandedImageKey_ == k and k == "backgroundImage" then
                -- 延迟滚动到底部让图片浏览器可见
                if detailScroll_ then
                    SubscribeToEvent("PostUpdate", function()
                        UnsubscribeFromEvent("PostUpdate")
                        if detailScroll_ then
                            detailScroll_:ScrollToBottom()
                        end
                    end)
                end
                local imageFiles = scanImageFiles()
                local imgListChildren = {}
                if #imageFiles == 0 then
                    imgListChildren[1] = UI.Label {
                        text = "image/ 目录下无图片文件",
                        fontSize = S(10), fontFamily = FONT_FAMILY,
                        fontColor = T.TEXT_HINT, padding = S(10),
                    }
                else
                    for _, imgPath in ipairs(imageFiles) do
                        local path = imgPath
                        -- 取最后一级文件名做标签
                        local shortName = path:match("([^/]+)$") or path
                        if #shortName > 16 then shortName = shortName:sub(1, 14) .. ".." end
                        imgListChildren[#imgListChildren + 1] = UI.Panel {
                            width = S(130), height = S(150),
                            flexDirection = "column", alignItems = "center",
                            justifyContent = "center", gap = S(3),
                            padding = S(4), borderRadius = S(4),
                            cursor = "pointer",
                            backgroundColor = T.BG_DARK,
                            borderWidth = S(1), borderColor = T.EDITOR_BORDER,
                            onClick = function(self)
                                applyPropChange(w, k, path)
                                expandedImageKey_ = nil
                                refreshAfterEdit()
                            end,
                            children = {
                                UI.Panel {
                                    width = S(120), height = S(120),
                                    borderRadius = S(3),
                                    backgroundImage = path,
                                    backgroundFit = "contain",
                                    flexShrink = 0,
                                },
                                UI.Label {
                                    text = shortName,
                                    fontSize = S(9), fontFamily = FONT_FAMILY,
                                    fontColor = T.TEXT_SECONDARY,
                                    numberOfLines = 1, overflow = "hidden",
                                    textAlign = "center", width = S(124),
                                },
                            },
                        }
                    end
                end

                local imgBrowserRow = UI.Panel {
                    width = "100%", maxHeight = S(400),
                    backgroundColor = { 30, 26, 20, 255 },
                    borderBottomWidth = S(1), borderColor = T.SECTION_BORDER,
                    flexDirection = "column",
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", paddingHorizontal = S(10), paddingVertical = S(4),
                            backgroundColor = T.SECTION_BG,
                            borderBottomWidth = S(1), borderColor = T.SECTION_BORDER,
                            flexShrink = 0,
                            children = {
                                UI.Label {
                                    text = "选择图片", fontSize = S(10), fontFamily = FONT_FAMILY,
                                    fontColor = T.ACCENT,
                                },
                                UI.Button {
                                    text = "收起", fontSize = S(10), fontFamily = FONT_FAMILY,
                                    height = S(22), paddingHorizontal = S(6), borderRadius = S(3),
                                    variant = "ghost", fontColor = T.TEXT_HINT,
                                    onClick = function(self)
                                        expandedImageKey_ = nil
                                        rebuildDetail()
                                    end,
                                },
                            },
                        },
                        UI.ScrollView {
                            width = "100%", flexGrow = 1, flexBasis = 0,
                            children = {
                                UI.Panel {
                                    width = "100%",
                                    flexDirection = "row", flexWrap = "wrap",
                                    gap = S(4), padding = S(6),
                                    children = imgListChildren,
                                },
                            },
                        },
                    },
                }
                rows[#rows + 1] = imgBrowserRow
            end
        end
    end

    addEditableSection("尺寸 / 定位", sizeProps)
    addEditableSection("Flex 布局", flexProps)
    addEditableSection("间距", spacingProps)
    addEditableSection("外观", visualProps)
    addEditableSection("背景", bgProps)
    addEditableSection("阴影", shadowProps)
    addEditableSection("变换 / 动画", transformProps)
    addEditableSection("行为", behaviorProps)
    addEditableSection("其他属性", otherProps)

    -- ===================== 事件绑定 =====================
    local eventEntries = {}  -- { key, func, source, line }
    for k, v in pairs(w.props) do
        if type(k) == "string" and type(v) == "function" then
            if #k > 2 and k:sub(1, 2) == "on" and k:sub(3, 3):match("[A-Z]") then
                -- 使用 debug.getinfo 获取定义来源
                local info = debug.getinfo(v, "S")
                local src = ""
                local line = 0
                if info then
                    src = info.short_src or info.source or "?"
                    line = info.linedefined or 0
                end
                eventEntries[#eventEntries + 1] = {
                    key  = k,
                    func = v,
                    src  = src,
                    line = line,
                }
            end
        end
    end
    if #eventEntries > 0 then
        table.sort(eventEntries, function(a, b) return a.key < b.key end)
        rows[#rows + 1] = createSectionHeader("事件绑定 (" .. #eventEntries .. ")")
        alt = false
        for _, entry in ipairs(eventEntries) do
            -- 简化源路径显示（去掉 [string "..."] 包装）
            local displaySrc = entry.src
            displaySrc = displaySrc:gsub('^%[string "(.-)"%]$', "%1")
            -- 去掉常见前缀
            displaySrc = displaySrc:gsub("^scripts/", "")
            local location = displaySrc
            if entry.line > 0 then
                location = location .. ":" .. entry.line
            end
            rows[#rows + 1] = UI.Panel {
                width = "100%", minHeight = S(28),
                flexDirection = "row", alignItems = "center",
                paddingHorizontal = S(10), paddingVertical = S(2),
                backgroundColor = alt and { 28, 24, 18, 255 } or { 22, 18, 14, 255 },
                children = {
                    -- 事件名
                    UI.Label {
                        text = entry.key, fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
                        fontColor = T.TEXT_SECONDARY,
                        width = S(120), flexShrink = 0,
                    },
                    -- 来源标签
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = S(4),
                        flexShrink = 1, flexGrow = 1,
                        children = {
                            UI.Label {
                                text = location,
                                fontSize = S(10), fontFamily = FONT_FAMILY,
                                fontColor = { 140, 180, 220, 255 },  -- 蓝色调表示可溯源
                                flexShrink = 1,
                            },
                        },
                    },
                },
            }
            alt = not alt
        end
    end

    for _, row in ipairs(rows) do
        detailInner_:AddChild(row)
    end

    -- 有 ColorPicker/ImageBrowser 展开时，底部增加 spacer 保证滚动空间
    -- ColorPicker popup 向下渲染，需要足够空间避免超出面板
    if expandedColorKey_ then
        detailInner_:AddChild(UI.Panel {
            width = "100%", height = S(400),
            flexShrink = 0,
        })
    elseif expandedImageKey_ then
        detailInner_:AddChild(UI.Panel {
            width = "100%", height = S(260),
            flexShrink = 0,
        })
    end
end

-- ============================================================================
-- 树视图重建
-- ============================================================================

rebuildTree = function()
    if not treeInner_ then return end
    treeInner_:RemoveAllChildren()

    local root = UI.GetRoot()
    if not root then
        treeInner_:AddChild(UI.Label {
            text = "UI Root 不可用", fontSize = S(12), fontFamily = FONT_FAMILY,
            fontColor = T.TEXT_HINT, marginLeft = S(10), marginTop = S(10),
        })
        return
    end

    local rows = {}
    local hasFilter = filterText_ ~= ""
    local directMatch = {}

    if hasFilter then
        -- ── 过滤模式 ──
        local filterLower = string.lower(filterText_)
        local visible
        visible, directMatch = preFilterScan(root, filterLower)
        if visible["R"] then
            -- 根节点本身不作为行，直接构建子树
            buildFilteredTreeRows(root, 0, "R", rows, visible, directMatch)
        end
    else
        -- ── 正常模式 ──
        local rootPath = "R"
        if expanded_[rootPath] == nil then expanded_[rootPath] = true end
        local rootChildren = root:GetChildren()
        local rootHasChildren = rootChildren and #rootChildren > 0
        rows[#rows + 1] = {
            depth       = 0,
            widget      = root,
            path        = rootPath,
            hasChildren = rootHasChildren,
            isExpanded  = expanded_[rootPath] == true,
            isRoot      = true,
        }
        if expanded_[rootPath] then
            buildTreeRows(root, 1, rootPath, rows)
        end
    end

    for _, row in ipairs(rows) do
        local label = row.isRoot and "UIRoot" or getNodeLabel(row.widget)
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

        local rowPath = row.path
        local rowWidget = row.widget
        local rowHasChildren = row.hasChildren
        local isHidden = hiddenPaths_[rowPath] == true
        local isLocked = lockedPaths_[rowPath] == true

        -- 重建时重新同步隐藏状态到实际 widget（面板关闭再打开后恢复）
        if isHidden and isWidgetAlive(rowWidget) then
            rowWidget:SetStyle({ visible = false })
        end

        -- 文本颜色：隐藏时变灰，匹配时高亮
        local labelColor = isHidden and T.TEXT_HINT
            or isMatch and T.ACCENT
            or T.TEXT_PRIMARY

        -- 锁定按钮样式
        local lockBtnStyle = {
            height = S(22), width = S(22), borderRadius = S(3),
            fontSize = S(12), fontFamily = FONT_FAMILY,
            variant = "ghost", paddingHorizontal = 0,
            backgroundColor = isLocked and { 60, 45, 25, 255 } or { 0, 0, 0, 0 },
            fontColor = isLocked and T.ACCENT or T.TEXT_HINT,
        }

        -- 显隐按钮样式
        local visBtnStyle = {
            height = S(22), width = S(22), borderRadius = S(3),
            fontSize = S(12), fontFamily = FONT_FAMILY,
            variant = "ghost", paddingHorizontal = 0,
            backgroundColor = { 0, 0, 0, 0 },
            fontColor = isHidden and { 200, 80, 80, 255 } or T.TEXT_HINT,
        }

        local rowPanel = UI.Panel {
            width = "100%", height = S(ROW_H),
            flexDirection = "row", alignItems = "center",
            paddingLeft = S(6) + row.depth * S(INDENT_PX),
            paddingRight = S(4),
            backgroundColor = rowBg,
            borderBottomWidth = S(1),
            borderColor = { 40, 35, 28, 100 },
            children = (function()
                local rowChildren = {
                    -- 展开/折叠图标
                    UI.Label {
                        text = prefix, fontSize = S(13), fontFamily = FONT_FAMILY,
                        fontColor = row.hasChildren and T.ACCENT or T.TEXT_HINT,
                        width = S(18), flexShrink = 0,
                    },
                    -- 节点名称（可点击选中）
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1, height = "100%",
                        flexDirection = "row", alignItems = "center",
                        onClick = function(self)
                            if rowHasChildren then
                                expanded_[rowPath] = not expanded_[rowPath]
                            end
                            selectedWidget_ = rowWidget
                            selectedPath_   = rowPath
                            rebuildTree()
                            rebuildDetail()
                        end,
                        children = {
                            UI.Label {
                                text = label, fontSize = S(12), fontFamily = FONT_FAMILY,
                                fontColor = labelColor,
                                flexShrink = 1, flexGrow = 1,
                            },
                        },
                    },
                }
                if not row.isRoot then
                    -- 锁定按钮（UIRoot 不显示）
                    rowChildren[#rowChildren + 1] = UI.Button(setmetatable({
                        text = isLocked and "\xF0\x9F\x94\x92" or "\xF0\x9F\x94\x93",  -- 🔒 / 🔓
                        onClick = function(self)
                            local newState = not lockedPaths_[rowPath]
                            lockedPaths_[rowPath] = newState
                            if isWidgetAlive(rowWidget) then
                                local descendants = {}
                                collectDescendantPaths(rowWidget, rowPath, descendants)
                                for _, d in ipairs(descendants) do
                                    lockedPaths_[d.path] = newState
                                end
                            end
                            rebuildTree()
                            if selectedPath_ == rowPath then
                                rebuildDetail()
                            end
                        end,
                    }, { __index = lockBtnStyle }))
                    -- 显隐按钮（UIRoot 不显示）
                    rowChildren[#rowChildren + 1] = UI.Button(setmetatable({
                        text = isHidden and "\xF0\x9F\x99\x88" or "\xF0\x9F\x91\x81",  -- 🙈 / 👁
                        onClick = function(self)
                            local newState = not hiddenPaths_[rowPath]
                            hiddenPaths_[rowPath] = newState
                            if isWidgetAlive(rowWidget) then
                                rowWidget:SetStyle({ visible = not newState })
                            end
                            if isWidgetAlive(rowWidget) then
                                local descendants = {}
                                collectDescendantPaths(rowWidget, rowPath, descendants)
                                for _, d in ipairs(descendants) do
                                    hiddenPaths_[d.path] = newState
                                    if isWidgetAlive(d.widget) then
                                        d.widget:SetStyle({ visible = not newState })
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
                return rowChildren
            end)(),
        }

        treeInner_:AddChild(rowPanel)
    end

    if #rows == 0 then
        local emptyMsg = hasFilter
            and ("未找到与 \"" .. filterText_ .. "\" 相关的节点")
            or "无 UI 子节点"
        treeInner_:AddChild(UI.Label {
            text = emptyMsg, fontSize = S(12), fontFamily = FONT_FAMILY,
            fontColor = T.TEXT_HINT, marginLeft = S(10), marginTop = S(10),
        })
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

local function updateAutoRefreshBtnStyle()
    if not autoRefreshBtn_ then return end
    autoRefreshBtn_:SetStyle({
        backgroundColor = autoRefresh_ and { 45, 70, 45, 255 } or { 35, 32, 26, 255 },
        borderColor     = autoRefresh_ and { 80, 140, 80, 200 } or T.BORDER,
        fontColor       = autoRefresh_ and { 120, 220, 120, 255 } or T.TEXT_SECONDARY,
    })
end

function UITreeView.Create(parentContainer, externalRefs)
    parentContainer_ = parentContainer
    refs_ = externalRefs or {}

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
    autoRefreshBtn_ = UI.Button {
        text = "自动刷新", fontSize = S(FONT_SIZE), fontFamily = FONT_FAMILY,
        height = S(26), paddingHorizontal = S(10),
        borderRadius = S(4), variant = "ghost",
        borderWidth = S(1),
        onClick = function(self)
            autoRefresh_ = not autoRefresh_
            autoRefreshTimer_ = 0
            updateAutoRefreshBtnStyle()
        end,
    }
    updateAutoRefreshBtnStyle()

    local toolbar = UI.Panel {
        width = "100%", height = S(34),
        flexDirection = "row", alignItems = "center",
        gap = S(6), paddingHorizontal = S(8),
        backgroundColor = T.SECTION_BG,
        borderBottomWidth = S(1), borderColor = T.BORDER,
        flexShrink = 0,
        children = {
            UI.Label {
                text = "UI 层级树", fontSize = S(12), fontFamily = FONT_FAMILY,
                fontColor = T.ACCENT, flexGrow = 1,
            },
            refreshBtn_,
            autoRefreshBtn_,
        },
    }

    -- 上半：树 ScrollView（占较小比例，给详情/ColorPicker 更多空间）
    treeInner_ = UI.Panel {
        width = "100%", flexDirection = "column",
    }
    treeScroll_ = UI.ScrollView {
        id = "uiTreeScroll",
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

    -- 下半：详情 ScrollView（占较大比例，确保 ColorPicker popup 有足够空间）
    detailInner_ = UI.Panel {
        width = "100%", flexDirection = "column",
    }
    detailScroll_ = UI.ScrollView {
        id = "uiTreeDetail",
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

function UITreeView.Rebuild()
    tabActive_ = true
    rebuildTree()
    rebuildDetail()
end

function UITreeView.Update(dt)
    if not tabActive_ or not autoRefresh_ then return end
    autoRefreshTimer_ = autoRefreshTimer_ + dt
    if autoRefreshTimer_ >= AUTO_REFRESH_INTERVAL then
        autoRefreshTimer_ = 0
        rebuildTree()
        if isWidgetAlive(selectedWidget_) then
            rebuildDetail()
        end
    end
end

--- 获取悬浮窗摘要信息（供 LogViewerUI 悬浮窗显示）
function UITreeView.GetFloatingSummary()
    local root = UI.GetRoot()
    -- 统计总节点数和最大嵌套深度（排除 LogViewer 自身）
    local totalCount = 0
    local maxDepth = 0
    local function countNodes(w, depth)
        local children = w:GetChildren()
        if not children then return end
        for _, child in ipairs(children) do
            if not isLogViewerSelf(child) then
                totalCount = totalCount + 1
                if depth > maxDepth then maxDepth = depth end
                countNodes(child, depth + 1)
            end
        end
    end
    if root then countNodes(root, 1) end

    -- 统计隐藏节点数
    local hiddenCount = 0
    for _, v in pairs(hiddenPaths_) do
        if v then hiddenCount = hiddenCount + 1 end
    end

    return {
        totalNodes  = totalCount,
        maxDepth    = maxDepth,
        hiddenCount = hiddenCount,
        autoRefresh = autoRefresh_,
    }
end

function UITreeView.SetActive(active)
    tabActive_ = active
    if not active then
        autoRefreshTimer_ = 0
    end
end

function UITreeView.UpdateRefs(externalRefs)
    refs_ = externalRefs or {}
end

function UITreeView.SetFilter(text)
    filterText_ = text or ""
    rebuildTree()
end

function UITreeView.GetFilter()
    return filterText_
end

function UITreeView.Destroy()
    tabActive_    = false
    filterText_   = ""
    selectedWidget_ = nil
    selectedPath_   = ""
    parentContainer_ = nil
    treeScroll_   = nil
    detailScroll_ = nil
    treeInner_    = nil
    detailInner_  = nil
    refreshBtn_   = nil
    autoRefreshBtn_ = nil
    autoRefreshTimer_ = 0
    refs_ = {}
    -- 重置内联展开状态
    expandedColorKey_ = nil
    expandedImageKey_ = nil
    -- lockedPaths_ / hiddenPaths_ 不清除：
    -- 模块级变量跨面板开关保留用户的锁定/隐藏状态
end

return UITreeView
