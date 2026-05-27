---
name: tween
description: >
  缓动动画库 tween.lua 完整集成指南与 UrhoX 最佳实践。
  提供 41 种缓动函数、属性插值、链式动画的即用方案。
  Use when users need to (1) 实现 UI 动画/过渡效果,
  (2) 数值滚动/计分板动画,
  (3) 颜色渐变/透明度变化,
  (4) 物体移动/缩放/旋转动画,
  (5) 弹性/弹跳/回弹等物理感动画,
  (6) 用户提到 tween、缓动、easing、动画曲线、插值,
  (7) 需要非线性动画效果。
---

# 缓动动画 — tween.lua

集成 [tween.lua v2.1.1](https://github.com/kikito/tween.lua)（kikito），一个轻量、零依赖的纯 Lua 缓动动画库。
提供 41 种缓动函数（10 族 × 4 变体 + linear），支持任意 table/userdata 属性插值，已适配 Lua 5.4 + UrhoX。

> **数学基础**: Robert Penner 缓动方程（2002），详见 `references/academic-resources.md`。

---

## 安装

单文件，已在 `scripts/tween.lua`：

```
scripts/
└── tween.lua    -- 368 行，零依赖
```

**UrhoX 适配说明**：原库使用 `math.pow`（Lua 5.3+ 已移除），已替换为 `^` 运算符的 polyfill。无其他修改。

---

## 核心概念

### 三要素

| 概念 | 说明 | 示例 |
|------|------|------|
| **Subject** | 被动画的对象（table 或 userdata） | `{ x = 0, y = 0, alpha = 0 }` |
| **Target** | 目标值（table，叶子必须为 number） | `{ x = 100, y = 200, alpha = 1 }` |
| **Easing** | 缓动函数名或函数引用 | `"outBounce"` 或 `tween.easing.outBounce` |

### 工作原理

```
tween.new(duration, subject, target, easing)
  │
  ├── 首次 update/set 时快照 subject 初始值 → initial
  ├── 每帧调用 update(dt)，推进内部时钟
  ├── 对 target 中每个键递归插值：subject[k] = easing(clock, initial[k], target[k] - initial[k], duration)
  └── 时钟 >= duration 时返回 true（完成）
```

---

## API 速查

### `tween.new(duration, subject, target [, easing])`

创建 Tween 实例。

```lua
local tween = require "tween"

local obj = { x = 0, y = 0 }
local tw = tween.new(1.0, obj, { x = 100, y = 200 }, "outQuad")
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `duration` | number | 动画时长（秒），必须 > 0 |
| `subject` | table / userdata | 被插值的对象 |
| `target` | table | 目标值，结构须是 subject 的子集，叶子为 number |
| `easing` | string / function | 缓动函数，默认 `"linear"`。字符串自动查 `tween.easing` 表 |

**返回**: Tween 对象

### `tw:update(dt)`

推进时钟，更新 subject 属性。

```lua
-- 在 HandleUpdate 中每帧调用
local finished = tw:update(dt)
if finished then
    -- 动画完成
end
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `dt` | number | 时间增量（秒），可为负值（倒放） |

**返回**: `boolean` — `true` 表示动画已完成（clock >= duration）

### `tw:set(clock)`

直接跳到指定时间点。

```lua
tw:set(0.5)   -- 跳到 0.5 秒处
tw:set(0)     -- 等同于 reset
```

**返回**: `boolean` — `true` 表示已到终点

### `tw:reset()`

重置到起点（等同于 `tw:set(0)`），恢复 subject 初始值。

---

## 41 种缓动函数

### 总览

| 族（Family） | in | out | inOut | outIn | 数学特征 |
|-------------|-----|------|-------|-------|---------|
| **linear** | — | — | — | — | f(t) = t |
| **quad** | ✓ | ✓ | ✓ | ✓ | t² |
| **cubic** | ✓ | ✓ | ✓ | ✓ | t³ |
| **quart** | ✓ | ✓ | ✓ | ✓ | t⁴ |
| **quint** | ✓ | ✓ | ✓ | ✓ | t⁵ |
| **sine** | ✓ | ✓ | ✓ | ✓ | sin/cos |
| **expo** | ✓ | ✓ | ✓ | ✓ | 2^(10t) |
| **circ** | ✓ | ✓ | ✓ | ✓ | √(1−t²) |
| **elastic** | ✓ | ✓ | ✓ | ✓ | sin 衰减振荡 |
| **back** | ✓ | ✓ | ✓ | ✓ | 超越后回弹 (s=1.70158) |
| **bounce** | ✓ | ✓ | ✓ | ✓ | 分段抛物线弹跳 |

**共 1 + 10 × 4 = 41 种**。

### 变体含义

| 变体 | 行为 | 典型用途 |
|------|------|---------|
| `in` | 慢启动 → 快结束 | 物体加速离开 |
| `out` | 快启动 → 慢结束 | 物体减速到达（**最常用**） |
| `inOut` | 慢 → 快 → 慢 | 平滑过渡 |
| `outIn` | 快 → 慢 → 快 | 中间停顿感 |

### 选型指南

| 场景 | 推荐缓动 | 原因 |
|------|---------|------|
| UI 弹出/消失 | `outBack` | 轻微过冲，有弹性感 |
| 计分板数字滚动 | `outQuad` | 快启慢停，自然 |
| 弹跳落地 | `outBounce` | 模拟物理弹跳 |
| 果冻/弹性效果 | `outElastic` | 弹簧振荡衰减 |
| 相机平滑移动 | `inOutSine` | 两端平滑，无顿挫 |
| 淡入淡出 | `inOutQuad` | 对称加减速 |
| 等速移动 | `linear` | 匀速，无加速 |
| 按钮按下反馈 | `outQuart` | 快速响应，缓慢归位 |

---

## UrhoX 集成模式

### 模式 1：基础属性动画

```lua
local tween = require "tween"

local panel = { x = -200, y = 300, alpha = 0 }
local slideIn = tween.new(0.5, panel, { x = 50, alpha = 1 }, "outBack")

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    slideIn:update(dt)
    -- 用 panel.x, panel.y, panel.alpha 驱动渲染
end
```

### 模式 2：嵌套属性（颜色渐变）

```lua
local obj = {
    pos = { x = 0, y = 0 },
    color = { r = 255, g = 0, b = 0 }
}
local tw = tween.new(1.0, obj, {
    pos = { x = 100, y = 200 },
    color = { r = 0, g = 255, b = 0 }
}, "inOutSine")
```

tween.lua 自动递归处理嵌套 table，只要叶子值是 number 即可。

### 模式 3：链式动画（序列）

```lua
local tweens = {}
local obj = { x = 0, y = 0 }

-- 构建动画序列
tweens[1] = tween.new(0.5, obj, { x = 100 }, "outQuad")
tweens[2] = tween.new(0.3, obj, { y = 200 }, "outBounce")
tweens[3] = tween.new(0.5, obj, { x = 0, y = 0 }, "inOutSine")

local current = 1

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if current <= #tweens then
        local finished = tweens[current]:update(dt)
        if finished then
            current = current + 1
            -- 下一段 tween 会在首次 update/set 时快照当前值作为 initial
        end
    end
end
```

### 模式 4：驱动 UrhoX 节点

```lua
local tween = require "tween"

-- 用代理 table 驱动节点位置
local proxy = { x = 0, y = 5, z = 0 }
local tw = tween.new(2.0, proxy, { x = 10, y = 5, z = 10 }, "inOutQuad")

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    tw:update(dt)
    myNode.position = Vector3(proxy.x, proxy.y, proxy.z)
end
```

> **为什么用代理 table？** tween.lua 的 subject 可以是 userdata（如 Vector3），
> 但 target 必须是 table。用代理 table 最安全、最灵活。

### 模式 5：数字滚动（计分板）

```lua
local tween = require "tween"

local display = { score = 0 }
local scoreTween = nil

function AddScore(points)
    local targetScore = display.score + points
    scoreTween = tween.new(0.8, display, { score = targetScore }, "outQuad")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if scoreTween then
        local done = scoreTween:update(dt)
        if done then scoreTween = nil end
    end
    -- 渲染时取 math.floor(display.score)
end
```

### 模式 6：循环动画（ping-pong）

```lua
local tween = require "tween"

local glow = { alpha = 0.3 }
local glowTw = tween.new(1.0, glow, { alpha = 1.0 }, "inOutSine")
local direction = 1  -- 1=正向, -1=反向

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local finished = glowTw:update(dt * direction)
    if direction == 1 and finished then
        direction = -1   -- 到达终点，开始倒放
    elseif direction == -1 and glowTw.clock <= 0 then
        direction = 1    -- 回到起点，正向播放
    end
end
```

> **原理**: `update(dt)` 支持负值，传入负 dt 即倒放。
> 注意 `set()` 只在 `clock >= duration` 时返回 `true`，
> 倒放到 `clock <= 0` 时返回 `false`，所以需要分别判断两端。

---

## 常见陷阱

### 1. target 必须是 subject 的子集

```lua
local obj = { x = 0 }

-- ❌ 错误：target 有 y，但 subject 没有
tween.new(1, obj, { x = 10, y = 20 }, "linear")
-- → 断言失败: "Parameter 'y' is missing from subject or isn't a number"

-- ✅ 正确：只动画 subject 已有的键
tween.new(1, obj, { x = 10 }, "linear")
```

### 2. 不支持 userdata 作为 target

```lua
-- ❌ 错误：target 不能是 Vector3（userdata）
tween.new(1, node.position, Vector3(10, 5, 0))

-- ✅ 正确：用代理 table
local proxy = { x = 0, y = 0 }
tween.new(1, proxy, { x = 10, y = 5 })
```

### 3. initial 快照时机

tween 在**首次 `update()` 或 `set()` 调用时**快照 subject 当前值作为 `initial`。
如果创建 tween 后、首次 update 前修改了 subject，初始值会不符合预期。

```lua
local obj = { x = 0 }
local tw = tween.new(1, obj, { x = 100 })
obj.x = 50       -- ⚠️ 此时 initial 尚未快照
tw:update(0.01)  -- 此时快照 initial.x = 50，从 50 → 100
```

### 4. 链式动画的 initial 陷阱

链式动画中，后续 tween 的 initial 是首次 update 时的 subject 值。确保上一段动画已完成再推进下一段。

### 5. duration 必须 > 0

```lua
-- ❌ 错误
tween.new(0, obj, target)  -- 断言失败

-- ✅ 用极小值模拟瞬时跳转
tween.new(0.001, obj, target)
-- 或直接赋值，不用 tween
```

---

## TweenManager 工具类（推荐封装）

管理多个并发 tween 的工具类：

```lua
local tween = require "tween"

local TweenManager = {}
TweenManager.__index = TweenManager

function TweenManager.new()
    return setmetatable({ tweens = {} }, TweenManager)
end

--- 添加 tween，返回 id
function TweenManager:add(duration, subject, target, easing, onComplete)
    local id = #self.tweens + 1
    self.tweens[id] = {
        tween = tween.new(duration, subject, target, easing or "linear"),
        onComplete = onComplete,
    }
    return id
end

--- 每帧调用，自动移除已完成的 tween
function TweenManager:update(dt)
    local i = 1
    while i <= #self.tweens do
        local entry = self.tweens[i]
        local finished = entry.tween:update(dt)
        if finished then
            if entry.onComplete then entry.onComplete() end
            table.remove(self.tweens, i)
        else
            i = i + 1
        end
    end
end

--- 清空所有 tween
function TweenManager:clear()
    self.tweens = {}
end

return TweenManager
```

**使用**：

```lua
local TweenManager = require "TweenManager"
local mgr = TweenManager.new()

-- 添加动画
mgr:add(0.5, panel, { x = 100 }, "outBack", function()
    print("slide done\!")
end)

-- HandleUpdate 中
mgr:update(dt)
```

---

## 参考文档

| 文档 | 内容 |
|------|------|
| `references/tween-api.md` | 完整 API 参考（含源码逐行映射） |
| `references/academic-resources.md` | Robert Penner 方程、Bezier 缓动论文、GDC 演讲等学术资源 |
