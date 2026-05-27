# 缓动动画 — 学术资源与参考文献

缓动函数（Easing Functions）的理论根基和工程实践参考。

---

## 核心参考文献

### 1. Robert Penner — 缓动方程奠基人

**原始出处**:
- **书籍**: Penner, R. (2002). *Programming Macromedia Flash MX*. McGraw-Hill. Chapter 7: "Motion, Tweening, and Easing"
- **个人网站**: http://robertpenner.com/easing/

**核心贡献**:
- 定义了缓动函数的标准签名 `f(t, b, c, d)` — 时间、起始值、变化量、总时长
- 提出 11 族缓动曲线（quad, cubic, quart, quint, sine, expo, circ, elastic, back, bounce）
- 每族 4 种变体（easeIn, easeOut, easeInOut, easeOutIn）的对称构造法
- 开源了 ActionScript 实现，后被移植到几乎所有编程语言

**数学洞见**:
Penner 指出缓动本质上是**时间重映射**（time remapping）：将线性时间 t ∈ [0,1] 通过非线性函数 f 映射到新的进度值，再用该进度对属性进行线性插值。这使得同一套缓动函数可以应用于任意可插值属性（位置、颜色、透明度等）。

```
property(t) = start + (end - start) × f(t/duration)
```

其中 f(0) = 0, f(1) = 1（除 elastic/back 等允许过冲的族）。

> **对 tween.lua 的影响**: tween.lua 的 41 个缓动函数直接源自 Emmanuel Oga 对 Penner 方程的 Lua 移植。函数签名与 Penner 原版完全一致。

---

### 2. Emmanuel Oga — Lua 移植版本

**仓库**: https://github.com/EmmanuelOga/easing (Lua)

tween.lua 源码注释明确标注：
```
-- Adapted from https://github.com/EmmanuelOga/easing. See LICENSE.txt for credits.
```

Emmanuel Oga 将 Penner 的 ActionScript 方程忠实移植为 Lua 实现，保持了相同的参数约定和数学精度。

---

### 3. Bézier 曲线与缓动函数的统一理论

**论文**: Correia, S. & Samavati, F. (2016). "Easing Functions in the New Form Based on Bézier Curves"
- **平台**: ResearchGate
- **DOI**: 可在 ResearchGate 上检索

**核心观点**:
- 证明了 Penner 的所有多项式族缓动函数（quad, cubic, quart, quint）可以用**三次 Bézier 曲线**精确表示
- 提出了用 Bézier 控制点参数化缓动曲线的方法
- 三次 Bézier 缓动公式：`B(t) = 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³`（P0=0, P3=1）
- 为 CSS `cubic-bezier()` 函数提供了理论基础

**实践意义**:
当 tween.lua 的 41 种预设不够用时，可以通过自定义 Bézier 控制点生成任意缓动曲线：

```lua
-- 自定义三次 Bézier 缓动（类似 CSS cubic-bezier）
local function cubicBezierEasing(x1, y1, x2, y2)
    -- 返回符合 Penner 签名的缓动函数
    return function(t, b, c, d)
        local p = t / d  -- 归一化时间
        -- 用牛顿法求解 B_x(u) = p 得到 u
        -- 然后计算 B_y(u) 作为进度
        local u = p  -- 初始猜测
        for _ = 1, 8 do
            local bx = 3*(1-u)^2*u*x1 + 3*(1-u)*u^2*x2 + u^3 - p
            local dbx = 3*(1-u)^2*x1 + 6*(1-u)*u*(x2-x1) + 3*u^2*(1-x2)
            if math.abs(dbx) < 1e-12 then break end
            u = u - bx / dbx
        end
        local by = 3*(1-u)^2*u*y1 + 3*(1-u)*u^2*y2 + u^3
        return b + c * by
    end
end

-- 用法：CSS ease 等效
local ease = cubicBezierEasing(0.25, 0.1, 0.25, 1.0)
local tw = tween.new(1.0, obj, { x = 100 }, ease)
```

---

### 4. CSS Easing 规范

**规范**: W3C CSS Easing Functions Level 2
- **链接**: https://www.w3.org/TR/css-easing-2/

**与 tween.lua 的对应关系**:

| CSS 预设 | cubic-bezier 控制点 | tween.lua 近似 |
|----------|-------------------|---------------|
| `ease` | (0.25, 0.1, 0.25, 1.0) | `outQuad`（近似） |
| `ease-in` | (0.42, 0, 1.0, 1.0) | `inCubic`（近似） |
| `ease-out` | (0, 0, 0.58, 1.0) | `outCubic`（近似） |
| `ease-in-out` | (0.42, 0, 0.58, 1.0) | `inOutCubic`（近似） |
| `linear` | (0, 0, 1, 1) | `linear`（精确） |

> CSS 使用三次 Bézier 曲线，tween.lua 使用解析函数，因此只是"近似"而非精确等价。

---

## GDC 演讲与工程实践

### 5. "Math for Game Programmers: Fast and Funky 1D Nonlinear Transformations"

**来源**: GDC (Game Developers Conference) 演讲系列
**演讲者**: Squirrel Eiserloh

**核心内容**:
- 将缓动函数视为 [0,1] → [0,1] 的**转换函数（Transfer Functions）**
- 提出 **SmoothStart** (= easeIn 多项式族) 和 **SmoothStop** (= easeOut 多项式族) 的命名法
- 展示了通过**混合（Blend）**和**交叉淡入淡出（Crossfade）**组合基础函数生成新曲线的技巧
- 用简单乘法近似复杂缓动：`SmoothStartN(t) = t^N`，`SmoothStopN(t) = 1 - (1-t)^N`

**映射到 tween.lua**:

| GDC 术语 | tween.lua 等价 |
|----------|---------------|
| SmoothStart2 | `inQuad` |
| SmoothStart3 | `inCubic` |
| SmoothStop2 | `outQuad` |
| SmoothStop3 | `outCubic` |
| SmoothStep3 | `inOutCubic`（近似） |

**实践价值**: 需要快速自定义缓动时，可以用简单的幂函数混合替代查表：
```lua
-- SmoothStop3 ≈ outCubic
local function smoothStop3(t, b, c, d)
    local p = 1 - (1 - t/d)
    p = 1 - (1-p)^3
    return b + c * p
end
```

---

### 6. "Juice it or Lose it" — 游戏手感的缓动实践

**来源**: GDC / Nordic Game 2012
**演讲者**: Martin Jonasson & Petri Purho

**核心观点**:
- "Juice" = 用过量的视觉/音频反馈让游戏感觉 alive
- 缓动动画是实现 juice 的最基础工具
- **弹跳（bounce）** 用于物体落地/碰撞反馈
- **弹性（elastic）** 用于 UI 元素的夸张出现
- **Back 过冲** 用于按钮点击的"回弹"感

**对 tween.lua 的实践指导**:

| 游戏手感需求 | 推荐缓动 | Juice 效果 |
|-------------|---------|-----------|
| 物体生成 | `outBack` | 从无到有，略微过冲 |
| 物体消失 | `inBack` | 先回缩再飞出 |
| 伤害数字弹出 | `outElastic` | 弹簧般抖动 |
| 得分增加 | `outQuad` | 快速响应，自然减速 |
| 屏幕震动 | `outExpo` | 急剧衰减 |
| 物体落地 | `outBounce` | 物理弹跳感 |

---

## 可视化工具

### 7. easings.net — 缓动函数速查表

**链接**: https://easings.net/

提供所有 Penner 缓动函数的：
- 交互式动画预览
- 曲线图形
- 数学公式
- 多语言代码实现

**与 tween.lua 的对应**: easings.net 展示的函数名采用 `easeInQuad` 格式，tween.lua 采用 `inQuad` 格式（去掉 `ease` 前缀），数学公式完全一致。

### 8. Febucci 缓动可视化教程

**链接**: https://blog.febucci.com/2018/08/easing-functions/

提供清晰的缓动函数 GIF 动画对比，直观展示每种缓动的运动感觉。适合选型时参考。

---

## 理论延伸

### 缓动与物理模拟的关系

| 缓动族 | 对应物理模型 | 说明 |
|--------|-------------|------|
| quad/cubic | 匀加速运动 | s = ½at²（二次方即匀加速） |
| sine | 简谐运动投影 | 圆周运动在轴上的投影 |
| expo | 指数衰减 | RC 电路放电、空气阻力 |
| elastic | 阻尼振荡 | 弹簧-阻尼系统 |
| bounce | 非弹性碰撞 | 每次弹起高度按比例衰减 |
| back | 超越平衡点 | 过冲后回调（PID 控制） |
| circ | 圆弧运动 | 沿圆弧的位移投影 |

### 插值空间的选择

tween.lua 在**属性值空间**做线性插值 + 时间重映射。对于某些属性，可能需要在其他空间插值：

| 属性 | 推荐空间 | 说明 |
|------|---------|------|
| 位置 (x, y, z) | 线性空间 ✅ | tween.lua 直接适用 |
| 颜色 (r, g, b) | 线性空间 ✅ | tween.lua 直接适用，但结果可能不感知均匀 |
| 颜色（感知均匀） | HSL/Lab 空间 | 需先转换到 HSL/Lab，插值后转回 RGB |
| 旋转角度 | 注意绕行方向 | 350° → 10° 应走 20° 而非 -340° |
| 缩放 | 对数空间 | 0.5 → 2.0 的中点应为 1.0，不是 1.25 |

---

## 参考文献汇总

| # | 来源 | 类型 | 年份 |
|---|------|------|------|
| 1 | Penner, R. *Programming Macromedia Flash MX*, Ch.7 | 书籍 | 2002 |
| 2 | Emmanuel Oga, easing (GitHub) | 开源库 | 2011 |
| 3 | Correia & Samavati, "Easing Functions in the New Form Based on Bézier Curves" | 论文 | 2016 |
| 4 | W3C CSS Easing Functions Level 2 | 规范 | 2023 |
| 5 | Eiserloh, "Fast and Funky 1D Nonlinear Transformations" (GDC) | 演讲 | 2015 |
| 6 | Jonasson & Purho, "Juice it or Lose it" | 演讲 | 2012 |
| 7 | easings.net | 工具 | — |
| 8 | Febucci, "Easing functions" | 教程 | 2018 |
