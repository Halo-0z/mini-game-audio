---
name: "调试助手"
description: "游戏运行时调试工具集：日志查看、性能监控、场景树检视、界面树检视。悬浮按钮一键打开，支持单机/多人自动适配。
Use when users need to (1) 安装调试助手, (2) 查看运行日志, (3) 查看性能数据/FPS/DrawCall/内存, (4) 检视场景节点树/组件属性, (5) 检视 UI 界面树/布局属性, (6) 升级 log-viewer。"
---

## 如何使用

对 AI 说：

> **帮我安装调试助手**

AI 会根据项目状态自动完成以下操作：

1. 将 `LogCapture.lua`、`LogViewerUI.lua`、`PerfProfiler.lua`、`LogBroadcast.lua`、`SceneTreeView.lua`、`UITreeView.lua`、`ScaleHelper.lua` 同步到项目的 `scripts/LogViewer/` 目录
2. 如果项目已经接入旧版 log-viewer，只追加缺失更新，保留不冲突的项目定制
3. 在项目入口文件的 `Start()` 函数中补齐初始化代码（`LogViewerUI.Init()` + `LogViewerUI.Mount()`）
4. 如果是多人项目，在服务端入口中补齐 `LogBroadcast.Install()`
5. 构建项目

安装完成后，游戏画面右下角会出现一个悬浮日志按钮，点击即可打开全屏日志面板，查看运行时日志和实时性能数据。

---

# 调试助手

> 游戏运行时一站式调试工具，通过悬浮按钮打开全屏面板，提供四大功能模块：
> - **日志** — 拦截 `print()` + 引擎 `LogMessage`，五级过滤（INFO/NET/WARNING/ERROR/ENGINE），多人模式自动接收服务端日志
> - **性能** — 帧率图表、DrawCall、内存、网络、渲染等 50+ 指标实时监控
> - **场景** — 运行时场景节点树检视，支持节点选中高亮、组件属性查看/编辑、材质与纹理预览、锁定/显隐级联控制
> - **界面** — 运行时 UI 树检视，支持组件选中高亮、Yoga 布局属性查看、字体/颜色预览、锁定/显隐级联控制

---

## 更新说明

<details>
<summary>2.1.0</summary>

- 新增 `ScaleHelper.lua`，为 `LogViewer` 提供独立的 UI 缩放补偿能力
  - 兼容 `UIScaleHelper` / 自定义 `UI.Init({ scale = ... })` 场景，解决调试面板在设计分辨率缩放项目中过小的问题
  - `LogViewerUI` 在加载子模块前先注入全局 `S()`，并在 `Init()` 时统一重算尺寸常量
- `SceneTreeView.lua` 与 `UITreeView.lua` 同步为缩放友好写法
  - 保留设计值常量，在具体 UI 属性处再套 `S()`，避免二次缩放
  - 对外暴露 `ApplyScale()`，由 `LogViewerUI` 初始化阶段统一刷新
- 安装文件从 6 个增加到 7 个（新增 `ScaleHelper.lua`）

</details>

<details>
<summary>2.0.2</summary>

- 修复 CS 常驻服（persistent world）模式下用户昵称显示"未知"的问题
  - 客户端 `GetUserNickname` 在 CS 模式下因 `lobby` 对象不可用会静默失败（不调任何回调），无法获取昵称
  - 新增 LogBroadcast 昵称查询服务：客户端检测到有 `serverConnection` 时直接通过 `LogViewerNicknameReq` 远程事件向服务端请求，服务端从 `connection.identity["user_id"]` 获取 userId 后调用 `GetUserNickname`（服务端同步），通过 `LogViewerNicknameRes` 返回
  - CS 模式下跳过客户端 `GetUserNickname`，直接走 LogBroadcast 通道；单机模式仍走客户端直连
  - 零外部依赖：昵称查询完全通过 LogViewer 自有的 LogBroadcast 模块实现，不依赖 GMTools 等业务代码
- 悬浮窗所有数值显示取整，去除小数（FPS、帧时间、内存、网络流量、渲染批次等）

</details>

<details>
<summary>2.0.1</summary>

- 界面/场景 Tab 新增搜索过滤功能：在 filterRow 搜索框中输入关键字可实时过滤树节点
  - UITreeView：按控件类型或文本搜索，匹配项高亮显示（金色背景 + 强调色文字）
  - SceneTreeView：按节点名称或组件类型搜索，支持组件级别匹配
  - 搜索时自动展开匹配节点的祖先链，无匹配时显示空结果提示
  - 清除按钮（×）一键重置过滤
- 修复面板切换时 perfContent_ 的 paddingBottom 导致界面/场景 Tab 顶部出现间隙的问题
- 界面/场景 Tab 下隐藏 filterRow 底部边框，视觉更紧凑

</details>
<details>
<summary>2.0.0</summary>

- 新增「场景」Tab（SceneTreeView.lua）：运行时 3D 场景节点树检视器
  - 树形展示场景全部节点与组件，支持展开/折叠
  - 节点选中高亮（半透明叠加材质），点击即定位
  - 组件属性面板：Transform（位置/旋转/缩放）、Light、Camera、RigidBody、StaticModel 等
  - 材质属性查看与实时编辑（颜色选择器）
  - 纹理缩略图预览
  - 节点锁定/显隐级联控制（父子联动，可单独解锁子节点）
  - 搜索过滤节点名称
- 新增「界面」Tab（UITreeView.lua）：运行时 UI 树检视器
  - 树形展示 UI 层级结构（Panel/Label/Button/Image 等）
  - 组件选中高亮（边框叠加）
  - Yoga Flexbox 布局属性查看（width/height/margin/padding/flex 等）
  - 样式属性查看（fontSize/fontFamily/color/backgroundColor 等）
  - 字体族预览、颜色色块预览
  - 节点锁定/显隐级联控制
  - 搜索过滤组件类型或文本
- 悬浮按钮新增场景/界面摘要视图（节点数、组件数等）
- 底部 Tab 栏从 2 个扩展为 4 个（日志/性能/场景/界面）
- 安装文件从 4 个增加到 6 个（新增 SceneTreeView.lua、UITreeView.lua）
- 移除所有业务逻辑依赖（Config 等），仅依赖引擎 API，可跨项目复用

</details>

<details>
<summary>1.2.0</summary>

- 新增 `PerfProfiler.lua` 性能数据采集模块（环形缓冲 600 帧 ≈10 秒）
- 悬浮窗新增"帧率"Tab，支持 4 个子视图切换（帧率/内存/网络/渲染）
- 全屏面板新增"帧率"Tab，含 7 个折叠分区（帧率图表/内存/网络/渲染/屏幕/系统/其它）
- DrawCall 双层自校准机制：悬浮窗 RemoveChild/AddChild 3 帧测量 + 面板 preOpenBaseline 持续追踪
- 安装文件从 3 个增加到 4 个（新增 PerfProfiler.lua）

</details>

<details>
<summary>1.1.1</summary>

- `LogViewerUI.lua` 追加账号栏展示，面板标题区显示 `昵称 | ID:xxx`
- Web 预览环境缺少 `lobby` 时直接回退显示 `"未知"`，避免预览阶段因为昵称查询失败而反复重试
- 昵称请求改为在 `LogViewerUI.Show()` 时触发，并在面板显示期间轮询补拉；`Init()` 和 `SetCurrentUserId()` 不再提前请求

</details>

---

## AI 写日志时使用此 API

> **当 AI 需要在游戏代码中输出日志时，优先使用 LogCapture 的公开方法，而非裸 `print()`**。
> 这样日志会自动带上正确的等级颜色，在面板中清晰可见。
>
> **补充约束**：
> - `print()` 被自动接管只是为了兼容历史代码和第三方输出，不代表新代码可以继续写 `print()`
> - AI 修改游戏运行时代码时，应把新增日志默认写成 `LogCapture.Info/Warn/Error/Net(...)`
> - 只有 `scripts/LogViewer/LogCapture.lua` 这类日志底座内部，才允许保留与 `print hook` 相关实现

```lua
local LogCapture = require("LogViewer.LogCapture")

LogCapture.Info("用户登录成功")       -- 蓝色
LogCapture.Warn("连接超时，重试中")    -- 黄色
LogCapture.Error("请求失败: " .. msg) -- 红色
LogCapture.Net("← request OK")       -- 绿色（网络专用）
```

---

## Enable 开关

`LogViewerUI.Enable`（默认 `true`）控制是否启用日志面板。正式上线前设为 `false`：

```lua
local LogViewerUI = require("LogViewer.LogViewerUI")
LogViewerUI.Enable = false   -- 关闭后 Init/Mount/Show/Hide 均无效，零开销
```

### Enable 与 NET 级别日志

`LogViewerUI.Enable` 同时提供给外部模块查询，用于控制是否输出详细的网络请求/响应日志。

- **Enable = true**：外部模块可以将 RPC 请求和响应以 NET 级别输出到 LogCapture
- **Enable = false**：外部模块跳过日志输出，避免序列化的性能开销

外部模块判断方式示例：
```lua
local function isVerboseLog()
    local ok, viewer = pcall(require, "LogViewer.LogViewerUI")
    return ok and viewer and viewer.Enable
end
```

---

## 安装

将技能目录 `scripts/` 中的七个文件复制到项目 `scripts/LogViewer/`：

```
scripts/
└── LogViewer/
    ├── LogCapture.lua      <- 从技能 scripts/LogCapture.lua 复制
    ├── LogViewerUI.lua     <- 从技能 scripts/LogViewerUI.lua 复制
    ├── PerfProfiler.lua    <- 从技能 scripts/PerfProfiler.lua 复制
    ├── LogBroadcast.lua    <- 从技能 scripts/LogBroadcast.lua 复制
    ├── SceneTreeView.lua   <- 从技能 scripts/SceneTreeView.lua 复制
    ├── UITreeView.lua      <- 从技能 scripts/UITreeView.lua 复制
    └── ScaleHelper.lua     <- 从技能 scripts/ScaleHelper.lua 复制
```

复制后 require 路径为：
- `require("LogViewer.LogCapture")`
- `require("LogViewer.LogViewerUI")`
- `require("LogViewer.PerfProfiler")`
- `require("LogViewer.LogBroadcast")`
- `require("LogViewer.SceneTreeView")`
- `require("LogViewer.UITreeView")`
- `require("LogViewer.ScaleHelper")`

## 追加安装 / 升级

- 如果项目还没有 `scripts/LogViewer/`，按"安装"执行全量复制
- 如果项目已经有旧版 `scripts/LogViewer/`，优先覆盖同步这七个通用脚本，再检查入口是否缺少初始化调用
- 只在缺失时追加 `require("LogViewer.LogViewerUI")`、`LogViewerUI.Init()`、`LogViewerUI.Mount()`、`LogBroadcast.Install()`
- 不改动项目业务脚本里与日志查看器无关的逻辑；如果入口已有自定义 root 切换，只在现有 `UI.SetRoot(...)` 之后追加 `LogViewerUI.Mount()`
- 如果用户已经对 `scripts/LogViewer/*.lua` 做过业务定制，先比对差异；仅在确认冲突可接受时再覆盖或手工合并

---

## 接入

### 单机游戏（3 行集成）

在项目入口 `Start()` 中：

```lua
local LogViewerUI = require("LogViewer.LogViewerUI")

function Start()
    -- 1. UI.Init() 之后，SetRoot() 之前
    UI.Init({ fonts = ..., scale = UI.Scale.DEFAULT })
    LogViewerUI.Init()      -- 安装 LogCapture + PerfProfiler，注册 Update 事件

    -- 2. 每次 SetRoot() 之后重新挂载（切换界面也需要重新调用）
    UI.SetRoot(myRootPanel)
    LogViewerUI.Mount()     -- 将悬浮 LOG 按钮挂到当前 root
end
```

### 多人游戏（C/S 架构）

**客户端入口**（与单机相同）：

```lua
local LogViewerUI = require("LogViewer.LogViewerUI")

function Start()
    UI.Init({ fonts = ..., scale = UI.Scale.DEFAULT })
    LogViewerUI.Init()      -- 自动检测多人模式，启用服务端日志接收

    UI.SetRoot(myRootPanel)
    LogViewerUI.Mount()
end
```

**服务端入口**（新增一行）：

```lua
local LogBroadcast = require("LogViewer.LogBroadcast")

function Start()
    -- ... 服务端初始化 ...
    LogBroadcast.Install()   -- 安装后服务端日志自动广播给所有客户端
end
```

> `Mount()` 必须在每次 `UI.SetRoot()` 之后调用，否则按钮随旧 root 一起销毁。
>
> 悬浮按钮的点击/拖拽使用按钮本体的局部 UI 事件（`onClick/onTap/onPointer*/onPan*`），不再依赖全局鼠标/触摸事件订阅，因此更不容易和其他悬浮工具互相干扰。

---

## LogCapture API

```lua
local LogCapture = require("LogViewer.LogCapture")

-- 写日志
LogCapture.Info(msg)         -- 蓝色
LogCapture.Warn(msg)         -- 黄色
LogCapture.Error(msg)        -- 红色
LogCapture.Net(msg)          -- 绿色（网络专用）
LogCapture.Log(level, msg)   -- level: "INFO"/"WARN"/"ERROR"/"NET"

-- 查询
LogCapture.GetEntries()      -- 返回 entry[] （内部引用，勿修改）
LogCapture.GetCount()        -- 条目数
LogCapture.Clear()           -- 清空
LogCapture.IsInstalled()     -- 是否已安装

-- 订阅
LogCapture.Subscribe(fn)     -- fn(entry) 实时推送
LogCapture.Unsubscribe(fn)

-- 安装（幂等）
LogCapture.Install()         -- 接管 print + 订阅 LogMessage + 多人自动订阅服务端日志
```

**entry 结构**: `{ id, time, level, msg, source }`

| level | 颜色 | source 值 | 含义 |
|-------|------|-----------|------|
| INFO  | 蓝   | `nil` | 客户端用户代码 |
| WARN  | 黄   | `"engine"` | 客户端引擎日志 |
| ERROR | 红   | `"server"` | 服务端用户代码（经 LogBroadcast 转发） |
| NET   | 绿   | `"server_engine"` | 服务端引擎日志（经 LogBroadcast 转发） |

> level 和 source 是两个独立维度。level 控制颜色，source 标识来源。

---

## PerfProfiler API

```lua
local PerfProfiler = require("LogViewer.PerfProfiler")

PerfProfiler.Init()                     -- 初始化（LogViewerUI.Init 内部自动调用）
PerfProfiler.GetStats()                 -- 返回 50+ 指标 table（帧率/渲染/内存/屏幕/系统/网络）
PerfProfiler.GetChartData(barCount)     -- 返回 number[] 帧时间柱状数据
PerfProfiler.CollectGC()                -- 强制 Lua GC
PerfProfiler.CleanCache()               -- 清理引擎资源缓存
```

---

## 各模块公开 API

```lua
-- LogViewerUI（主控）
local LogViewerUI = require("LogViewer.LogViewerUI")
LogViewerUI.Enable = true       -- false 时完全禁用，零开销
LogViewerUI.Init()              -- UI.Init 之后调用一次
LogViewerUI.Mount()             -- 每次 UI.SetRoot 之后调用
LogViewerUI.Show() / .Hide()    -- 手动开关面板

-- LogBroadcast（服务端专用）
local LogBroadcast = require("LogViewer.LogBroadcast")
LogBroadcast.Install()          -- 服务端日志广播给客户端（幂等）

-- SceneTreeView
local SceneTreeView = require("LogViewer.SceneTreeView")
SceneTreeView.Create(container) -- 创建并挂载
SceneTreeView.Update(dt)        -- 每帧更新（LogViewerUI 自动调用）
SceneTreeView.Destroy()         -- 销毁

-- UITreeView
local UITreeView = require("LogViewer.UITreeView")
UITreeView.Create(container, refs) -- 创建并挂载
UITreeView.Update(dt)              -- 每帧更新（LogViewerUI 自动调用）
UITreeView.Destroy()               -- 销毁
```

---

## 单机与多人自动适配

通过 `IsNetworkMode()` / `IsServerMode()` 自动适配，无需手动配置：

| 场景 | 客户端日志接收 | 服务端日志广播 | 网络指标 |
|------|--------------|--------------|---------|
| 单机 | — | — | — |
| 多人客户端 | 自动注册 | — | 显示 ping/bytes/packets |
| 多人服务端 | — | 需调用 `LogBroadcast.Install()` | — |

---

## 注意事项

1. `UI.Init()` 必须先于 `LogViewerUI.Init()`
2. `Mount()` 必须在每次 `UI.SetRoot()` 之后调用
3. 环形缓冲上限 500 条，超出自动删最旧
4. `print()` 被自动接管仅为兼容历史代码，AI 新增日志应使用 `LogCapture.Info/Warn/Error/Net()`
5. DrawCall 校准在面板开关时自动执行，显示值已扣除面板自身 DC

---

反馈：chaos@ospec.ai
