-- ============================================================================
-- LogViewer 缩放补偿模块 (ScaleHelper)
--
-- 解决的问题：
--   LogViewer 按 UI.Scale.DEFAULT (DPR_DENSITY_ADAPTIVE) 基准设计，
--   但项目可能使用设计分辨率缩放（如 UIScaleHelper 1080×1920），
--   导致 LogViewer 显示过小。
--   此模块提供补偿函数 S()，将设计值转换为当前 scale 下的等效物理尺寸。
--
-- 使用方式：
--   local ScaleHelper = require("LogViewer.ScaleHelper")
--   local S = ScaleHelper.S          -- 缩放补偿函数
--
--   -- 在 UI 属性中使用：
--   UI.Panel { width = S(100), fontSize = S(14), padding = S(8) }
--
--   -- 不需要 S() 的值：颜色、透明度、flex 值、百分比字符串、zIndex
--
-- 初始化：
--   在 UI.Init() 之后调用 ScaleHelper.Init()，自动计算补偿系数。
--   如果 compensate == 1（无需补偿），S(v) 直接返回 v，零开销。
-- ============================================================================

local ScaleHelper = {}

local _compensate = 1

--- 缩放补偿函数：将设计尺寸值转换为当前 scale 下等效物理尺寸
---@param v number 按 DEFAULT scale 设计的尺寸值
---@return number 补偿后的尺寸值
function ScaleHelper.S(v)
    if _compensate == 1 then return v end
    return math.floor(v * _compensate + 0.5)
end

--- 获取当前补偿系数（调试用）
---@return number
function ScaleHelper.GetCompensate()
    return _compensate
end

--- 计算并设置补偿系数
--- 在 UI.Init() 之后调用一次即可
---@return number compensate 计算出的补偿系数（1 表示无需补偿）
function ScaleHelper.Init()
    local UI = require("urhox-libs/UI")
    local dpr = graphics:GetDPR()
    local shortCSS = math.min(graphics:GetWidth(), graphics:GetHeight()) / dpr
    local df = math.max(0.625, math.min(math.sqrt(shortCSS / 720), 1.0))
    local defaultScale = dpr * df
    local curScale = UI.Scale(1)
    if curScale > 0 and math.abs(curScale - defaultScale) > 0.01 then
        _compensate = defaultScale / curScale
    else
        _compensate = 1
    end
    -- 同步全局 S/compensate（兼容已有代码中的全局 S() 调用）
    _lvCompensate = _compensate
    return _compensate
end

return ScaleHelper
