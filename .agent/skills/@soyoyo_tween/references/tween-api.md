# tween.lua v2.1.1 — 完整 API 参考

> 源码: `scripts/tween.lua` (368 行)
> 仓库: https://github.com/kikito/tween.lua
> 许可: MIT (Enrique García Cota, Yuichi Tateno, Emmanuel Oga)

---

## 模块级 API

### `tween.new(duration, subject, target [, easing]) → Tween`

创建并返回一个 Tween 实例。

**参数**:

| # | 名称 | 类型 | 必填 | 说明 |
|---|------|------|------|------|
| 1 | `duration` | `number` | ✓ | 动画总时长（秒），必须 > 0 |
| 2 | `subject` | `table \| userdata` | ✓ | 被插值的对象，其数值属性将被修改 |
| 3 | `target` | `table` | ✓ | 目标值。结构须为 subject 的子集，叶子必须为 number |
| 4 | `easing` | `string \| function` | ✗ | 缓动函数，默认 `"linear"`。字符串自动从 `tween.easing` 表查找 |

**内部行为** (源码 L356-L365):
1. 若 easing 为 string，通过 `getEasingFunction()` 从 `tween.easing` 表查找
2. `checkNewParams()` 校验所有参数类型
3. `checkSubjectAndTargetRecursively()` 递归验证 target 的每个叶子在 subject 中存在且为 number
4. 返回 `setmetatable({duration, subject, target, easing, clock=0}, Tween_mt)`

**异常**:
- `duration` 非正数 → `"duration must be a positive number. Was ..."`
- `subject` 非 table/userdata → `"subject must be a table or userdata. Was ..."`
- `target` 非 table → `"target must be a table. Was ..."`
- `easing` 非函数 → `"easing must be a function. Was ..."`
- target 中有键在 subject 中缺失或不是 number → `"Parameter 'x/y/z' is missing from subject or isn't a number"`
- easing 字符串不在 `tween.easing` 中 → `"The easing function name '...' is invalid"`

**示例**:
```lua
local tween = require "tween"

-- 基础用法
local obj = { x = 0, y = 0 }
local tw = tween.new(1.0, obj, { x = 100, y = 200 }, "outQuad")

-- 默认 linear
local tw2 = tween.new(2.0, obj, { x = 50 })

-- 传入函数引用
local tw3 = tween.new(1.0, obj, { x = 100 }, tween.easing.outBounce)

-- 嵌套 table
local complex = { pos = { x = 0, y = 0 }, color = { r = 255, g = 0, b = 0 } }
local tw4 = tween.new(1.0, complex, {
    pos = { x = 100 },
    color = { r = 0, g = 255 }
})
-- 注意：只会动画 pos.x, color.r, color.g — pos.y, color.b 不受影响
```

---

### `tween.easing` (table)

包含所有 41 种缓动函数的查找表。键为字符串名称，值为函数。

**所有键**:
```
linear
inQuad     outQuad     inOutQuad     outInQuad
inCubic    outCubic    inOutCubic    outInCubic
inQuart    outQuart    inOutQuart    outInQuart
inQuint    outQuint    inOutQuint    outInQuint
inSine     outSine     inOutSine     outInSine
inExpo     outExpo     inOutExpo     outInExpo
inCirc     outCirc     inOutCirc     outInCirc
inElastic  outElastic  inOutElastic  outInElastic
inBack     outBack     inOutBack     outInBack
inBounce   outBounce   inOutBounce   outInBounce
```

可直接引用：`tween.easing.outBounce`（返回 function）。

---

## Tween 实例方法

### `tw:update(dt) → boolean`

推进内部时钟，更新 subject 的所有目标属性。

**参数**:

| 名称 | 类型 | 说明 |
|------|------|------|
| `dt` | `number` | 时间增量（秒）。可为负值（倒放） |

**返回**: `true` 当且仅当 `clock >= duration`（动画完成）

**内部行为** (源码 L348-L351):
1. 调用 `self:set(self.clock + dt)`

**注意**:
- dt 为负值时时钟回退，可实现倒放
- 超过 duration 的部分被截断（clock 被钳位到 duration）
- 低于 0 的部分被截断（clock 被钳位到 0）
- 即使已完成，继续调用 update 不会出错，只是持续返回 true

### `tw:set(clock) → boolean`

直接将时钟设置到指定时间点，更新 subject。

**参数**:

| 名称 | 类型 | 说明 |
|------|------|------|
| `clock` | `number` | 目标时间点（秒），0 = 起点，duration = 终点 |

**返回**: `true` 当且仅当 `clock >= duration`

**内部行为** (源码 L319-L342):
1. **首次调用时**（`self.initial == nil`），深拷贝 subject 当前值作为 initial 快照
2. clock <= 0 → 将 subject 恢复为 initial 值（深拷贝）
3. clock >= duration → 将 subject 设为 target 值（深拷贝）
4. 0 < clock < duration → 对每个 target 键递归调用 easing 函数：
   `subject[k] = easing(clock, initial[k], target[k] - initial[k], duration)`

**关键细节**:
- **initial 快照延迟**: 不在 `tween.new()` 时快照，而在首次 `set()`/`update()` 时
- **边界处理**: 到达端点时使用 `copyTables` 直接赋值，不走 easing 函数，避免浮点误差
- **metatable 保留**: `copyTables` 会传递源 table 的 metatable

### `tw:reset() → boolean`

将时钟重置为 0，恢复 subject 到初始值。

**返回**: `false`（因为 `0 >= duration` 对任何有效 duration 都不成立）

**内部行为** (源码 L344-L346):
- 等同于 `self:set(0)`

---

## 缓动函数签名

所有缓动函数共享同一签名（Robert Penner 标准）：

```lua
function easing(t, b, c, d) → number
```

| 参数 | 含义 | 范围 |
|------|------|------|
| `t` | 当前时间（已过时间） | `[0, d]` |
| `b` | 起始值（begin） | 任意 number |
| `c` | 变化量（change = target - begin） | 任意 number |
| `d` | 总时长（duration） | `> 0` |

**返回**: 插值后的当前值

**自定义缓动函数**:
```lua
-- 自定义缓动：先慢后快的指数函数
local function myEasing(t, b, c, d)
    t = t / d
    return b + c * t * t * t  -- 等同于 inCubic
end

local tw = tween.new(1.0, obj, { x = 100 }, myEasing)
```

---

## 各族缓动函数数学公式

以下用归一化时间 `p = t/d`（p ∈ [0,1]），输出归一化为 `f(p)` ∈ [0,1]。
实际计算: `result = b + c * f(p)`

### 多项式族

| 函数 | 公式 |
|------|------|
| **linear** | `f(p) = p` |
| **inQuad** | `f(p) = p²` |
| **inCubic** | `f(p) = p³` |
| **inQuart** | `f(p) = p⁴` |
| **inQuint** | `f(p) = p⁵` |

`out` 变体: `f(p) = 1 - in(1-p)`
`inOut` 变体: 前半段用 `in(2p)/2`，后半段用 `1 - in(2-2p)/2`
`outIn` 变体: 前半段用 `out(2p)/2`，后半段用 `0.5 + in(2p-1)/2`

### 三角函数族

| 函数 | 公式 |
|------|------|
| **inSine** | `f(p) = 1 - cos(p × π/2)` |
| **outSine** | `f(p) = sin(p × π/2)` |
| **inOutSine** | `f(p) = (1 - cos(p × π)) / 2` |

### 指数族

| 函数 | 公式 | 备注 |
|------|------|------|
| **inExpo** | `f(p) = 2^(10(p-1)) - 0.001` | p=0 时特判返回 0 |
| **outExpo** | `f(p) = 1.001 × (1 - 2^(-10p))` | p=1 时特判返回 1 |

> 0.001/1.001 系数用于平滑 p=0 处的不连续性。

### 圆族

| 函数 | 公式 |
|------|------|
| **inCirc** | `f(p) = 1 - √(1 - p²)` |
| **outCirc** | `f(p) = √(1 - (p-1)²)` |

### Elastic（弹性）

```
f(p) = -a × 2^(10(p-1)) × sin((p×d - s) × 2π / period)
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `a` (amplitude) | `c` | 振幅，< |c| 时自动调整 |
| `p` (period) | `d × 0.3` | 振荡周期 |
| `s` (phase shift) | `p/4` 或 `p/(2π) × asin(c/a)` | 相位偏移 |

> **注意**: elastic 和 back 的底层函数接受额外参数 (a, p) 和 (s)，
> 但通过 `tween.new()` 使用时**无法传入这些额外参数**，只使用默认值。
> 如需自定义，请直接传入自定义缓动函数。

### Back（回弹）

```
f(p) = p² × ((s+1)×p - s)
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `s` (overshoot) | `1.70158` | 过冲量。值越大，回弹越明显 |

> s = 1.70158 时，inBack 会先回退到约 -10%。

### Bounce（弹跳）

outBounce 为基础实现，分 4 段抛物线：

```
t < 1/2.75:    7.5625 × t²
t < 2/2.75:    7.5625 × (t - 1.5/2.75)² + 0.75
t < 2.5/2.75:  7.5625 × (t - 2.25/2.75)² + 0.9375
else:           7.5625 × (t - 2.625/2.75)² + 0.984375
```

inBounce = `1 - outBounce(1-p)`

---

## 内部函数

以下函数不对外暴露，仅用于理解源码。

### `copyTables(destination, keysTable [, valuesTable])`

深拷贝 table。用于 initial 快照和边界赋值。
- 传递 metatable
- 递归处理嵌套 table
- 若 `valuesTable` 省略，使用 `keysTable` 自身

### `checkSubjectAndTargetRecursively(subject, target [, path])`

递归验证 target 结构在 subject 中存在。
- 叶子必须为 number
- 路径用 `/` 拼接用于错误消息

### `getEasingFunction(easing)`

将 string 名称转为函数引用。nil 默认为 `"linear"`。

### `performEasingOnSubject(subject, target, initial, clock, duration, easing)`

核心插值引擎。递归遍历 target 键：
- table → 递归
- number → `subject[k] = easing(clock, initial[k], target[k] - initial[k], duration)`

---

## Tween 对象内部字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `duration` | number | 总时长 |
| `subject` | table/userdata | 被插值对象的引用 |
| `target` | table | 目标值 |
| `easing` | function | 缓动函数 |
| `clock` | number | 当前时钟（0 ~ duration） |
| `initial` | table / nil | subject 初始值快照，首次 set/update 时创建 |

> 这些字段可直接读取（如 `tw.clock`），但**不建议直接修改**。

---

## 边界行为汇总

| 场景 | 行为 |
|------|------|
| `update(dt)` dt > 剩余时间 | clock 被钳位到 duration，subject 设为 target 精确值 |
| `update(dt)` dt < 0 | 时钟回退，clock 可降到 0 以下（被钳位到 0） |
| `set(clock)` clock < 0 | clock 设为 0，subject 恢复为 initial |
| `set(clock)` clock > duration | clock 设为 duration，subject 设为 target |
| 完成后继续 `update` | 无副作用，持续返回 true |
| 未调用 update 直接读 subject | 值未变（initial 尚未快照） |
| subject 被外部修改 | 下次 update 会基于被修改的值计算（但 initial 不变） |
