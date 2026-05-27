---
name: memory-system
description: >
  AI 跨会话持久记忆系统（元 skill）。在以下场景自动触发：
  (1) 每次会话开始/首条消息（会话恢复、记忆加载、人格加载、跨项目唤醒检测）
  (2) 用户说「部署记忆系统」「添加记忆」「初始化记忆」「开始」
  (3) 用户希望 AI 跨会话记住项目上下文/决策/偏好
  (4) 用户提到 POST 步骤/记忆巩固/会话恢复
  (5) 用户想让 AI 具有持久记忆和自维护能力
  (6) 用户切换到新项目时希望保留之前的偏好和经验
  (7) 用户说出唤醒词（存储在 .agent/memory-runtime/preferences.json 的 wake_word 字段）。
  MUST trigger when: 安装后首次使用时自动部署——检测到项目无 CLAUDE.md 即视为首次，
  无需用户确认直接执行完整部署流程（创建记忆文件、人格初始化）。
  支持唤醒词：用户首次部署时可设置专属唤醒词（如助手昵称），跨项目时说出唤醒词即可唤醒助手、恢复全部记忆。
  支持跨项目随行记忆，通过 .agent/memory-runtime/ 独立目录跨项目持久，多项目并行时自动合并（追加去重/latest-wins）。
  支持 skill 钩子系统：自动发现并整合其他 workflow skill（如 knowledge-base）的生命周期需求，统一调度同步和上下文加载。
  适用于任何类型的项目（不限于游戏开发）。
---

# AI 记忆系统 v3.9.1

> 元 skill：安装即生效，跨会话持久记忆 + 跨项目人格陪伴 + 唤醒词跨项目唤醒 + skill 钩子系统。

---

## 首次激活（安装后自动执行）

**安装 skill 后，用户发送任何消息即触发首次激活。无需用户主动说"部署"。**

检测条件：项目根目录无 `CLAUDE.md`，或 `CLAUDE.md` 无"恢复指令"段落。

    用户发送任何消息
      ↓
    检查项目 CLAUDE.md
      → 不存在或不完整 → 首次激活（以下全部自动执行）：
        1. 创建 docs/ 目录结构
        2. 复制模板文件
        3. 创建项目 CLAUDE.md
        4. 检查随行记忆 → 有则恢复，无则人格初始化
        5. 人格初始化时设置唤醒词（见下方）
        6. git init + commit（如非 git 仓库）
        7. 告知用户"记忆系统已自动部署"，展示完成状态
        8. 然后处理用户的原始请求
      → 存在且完整 → 正常会话恢复（见下方）

---

## 唤醒词系统

### 什么是唤醒词

唤醒词是用户为助手设置的专属名字或暗号。用户在任何安装了本 skill 的项目中说出唤醒词，即可触发助手记忆恢复。

典型场景：

    用户在新项目中说："小星，帮我看看这个项目"
      ↓
    skill 触发条件 (7) 匹配唤醒词"小星"
      ↓
    触发跨项目唤醒
      ↓
    助手恢复用户画像和偏好："你好！我记得你喜欢简洁沟通、先规划再动手…"

### 设置时机

**首次部署时**（人格初始化第 4 个问题）：

    "你想给我起个名字吗？之后在新项目里叫这个名字就能唤醒我。"
      → 用户取名 → 保存到 .agent/memory-runtime/preferences.json 的 wake_word
      → 用户跳过 → wake_word 设为 null，后续可随时设置

**随时更改**：
用户说"改唤醒词"、"换个名字" → 更新 preferences.json + docs/persona.md

### 存储位置

    // .agent/memory-runtime/preferences.json
    {
      "wake_word": "小星",
      ...
    }

同时记录在 `docs/persona.md` 基础画像的唤醒词字段。

### 跨项目唤醒流程

    用户在新项目说出唤醒词
      ↓
    skill 触发条件 (7) 匹配 → 自动激活
      ↓
    检测项目 CLAUDE.md 不存在 → 跨项目唤醒
      ↓
    恢复随行记忆（画像 + 抗体 + 偏好）
      ↓
    助手用唤醒词对应的身份回应："我在！让我先看看这个新项目…"

---

## 会话启动（每次新会话）

    Step 1: Read 项目 CLAUDE.md
      → 不存在 → 首次激活 / 跨项目唤醒
      → 存在 → Step 2

    Step 2: 执行恢复指令
      → 读 docs/memory-index.md + docs/persona.md
      → 自测：项目是什么？上次做了什么？下一步？
      → 不够清楚 → 多读文件补充
      → 足够 → 开始工作

    Step 3: 简要告知记忆恢复状态，处理用户请求

### 跨项目唤醒

CLAUDE.md 不存在 + 随行记忆存在 = 老用户进新项目。

    
    检测随行记忆（优先全局，降级本地）：
      → 有 persona.md → 复制到项目 docs/，展示画像摘要，询问"要沿用吗？"
      → 有 antibodies.md → 合并到 CLAUDE.md 避雷清单
      → 有 preferences.json → 恢复偏好（含唤醒词）
      → 全局和本地都无 → 全新用户，执行人格初始化

`{self}` = 本 skill 目录（Glob `**/skills/memory-system/SKILL.md` 定位）。

---

## 记忆文件

| 文件 | 作用 | 更新时机 |
|------|------|---------|
| `CLAUDE.md` | 项目状态快照（自动注入） | 每次 POST |
| `docs/memory-index.md` | 项目详细上下文 | 每次 POST |
| `docs/persona.md` | 用户画像（三层） | 持续观察更新 |
| `docs/decisions/` | 重要决策记录（可选） | 按需 |
| `docs/archive/` | 冷存储 | memory-index 过长时归档 |

---

## POST（每次交付后必做）

POST 是记忆存活的唯一入口。每次完成任务后 3 步：

    POST-1: 更新记忆
      → CLAUDE.md：状态 + likely_next_task + 避雷清单
      → memory-index.md：记录变更、更新结构索引
      → persona.md：捕获新发现的用户特征（如有）

    POST-2: 持久化
      → docs/versions.md：追加版本行到表头（最新在最上面）
      → git add + commit

    POST-3: 同步随行记忆
      → 合并写入 .agent/memory-runtime/
      → persona.md → 合并写入（按章节合并，保留各项目积累的观察和足迹）
      → 避雷清单 [跨项目] → 追加去重写入 antibodies.md
      → preferences.json → 字段级合并（latest-wins + 数组合并去重）
      详见下方"随行记忆合并策略"

### 执行保障 🔴

**TodoWrite 前置**：收到非纯讨论任务后，第一个动作就是创建包含 POST 的 TodoWrite：
```
TodoWrite([
  { content: "DEV: [任务]", status: "in_progress" },
  { content: "POST-1 更新记忆", status: "pending" },
  { content: "POST-2 持久化", status: "pending" },
  { content: "POST-3 同步随行记忆", status: "pending" }
])
```
**强制判定**：每个 POST 步骤必须做执行/跳过判定，跳过需在条目中标注理由。禁止直接删除 POST 条目。

详见：`references/memory-workflow.md` → "执行保障机制"

| 场景 | POST 范围 | 强制判定 |
|------|----------|---------|
| 完成功能/修复 | 完整 3 步 | 3 步都执行 |
| 小调整 | POST-1 简写 + POST-2 | POST-3 判定跳过并标注理由 |
| 纯讨论 | 不需要 | 不创建 TodoWrite |
| 上下文压缩前 | 完整 3 步（紧急） | 3 步都执行 |


---

## 人格系统

助手跨项目陪伴用户，人格持续成长。

### 三层画像

**基础画像**（首次交互自然了解）：
- 称呼：用户怎么叫、助手怎么自称
- 唤醒词：用户为助手设置的专属名字
- 沟通风格：简洁 vs 详细、严肃 vs 轻松
- 技术背景：经验水平、擅长领域

**工作特征**（跨项目逐渐发现）：
- 决策风格：稳健保守 vs 快速试错
- 代码偏好：命名习惯、架构倾向
- 反馈偏好：直接批评 vs 温和建议
- 工作习惯：先规划 vs 直接动手
- 审美倾向：UI 风格、配色偏好

**成长记录**（跨项目积累）：
- 项目足迹：做过的项目、关键经验
- 技能成长：从项目中学到的能力
- 反复模式：常见需求、常犯的错

### 人格初始化

首次使用，自然对话（不搞问卷）：
1. "你希望我怎么称呼你？"
2. "你喜欢什么风格的沟通？"
3. "你的技术背景是什么？"
4. "你想给我起个名字吗？之后在新项目里叫这个名字就能唤醒我。"

其他维度在协作中自然发现。

### 隐式捕获与漂移检测

- 观察到用户特征 → 记录 `[observed]`，计数
- 同类 ≥ 3 次 → 向用户确认 → 确认则正式记录
- 行为与已知画像不一致 → 标记 `[drift]` → 连续出现则询问更新

---

## 随行记忆

    .agent/memory-runtime/              ← 跨项目共享存储（独立于 skill 目录，永远干净）
    ├── persona.md
    ├── antibodies.md
    └── preferences.json

运行时数据存储在 `.agent/memory-runtime/`，与 skill 目录分离，skill 目录可直接分发。

同步时机：每次 POST-3 / 上下文压缩前 / 项目切换时。

### 项目隔离（scope 标记）

随行记忆记录所有观察到的用户特征和偏好，但并非所有条目都适用于每个项目。
通过 `[scope:X]` 标记区分适用范围，跨项目加载时按 scope 过滤。

**scope 类型**：

| scope | 含义 | 加载行为 |
|-------|------|---------|
| （无标记） | 通用，所有项目适用 | 自动应用 |
| `[scope:project]` | 来源项目的专属配置 | 跨项目时展示但不自动应用，询问是否沿用 |
| `[scope:gamedev]` | 游戏开发项目适用 | 仅在游戏项目中自动应用，其他项目忽略 |

**标记位置**：
- `persona.md`：标记在具体条目行尾，如 `- 协作方式: ... [scope:project]`
- `preferences.json`：`scoped_preferences` 字段按 scope 分组存储

**跨项目加载逻辑**：
```
加载随行记忆到新项目
  ↓
解析每条偏好/配置的 scope
  ├─ 无标记 → 自动应用（通用）
  ├─ [scope:gamedev] + 当前是游戏项目 → 自动应用
  ├─ [scope:gamedev] + 当前非游戏项目 → 跳过
  └─ [scope:project] → 展示给用户："上个项目中你设置了 X，要在这个项目沿用吗？"
```

### 随行记忆合并策略

POST-3 不是简单覆盖，而是**读取全局已有内容 → 合并 → 写回**。

| 文件 | 合并方式 | 说明 |
|------|---------|------|
| persona.md | 画像 latest-wins，足迹追加去重，观察合并计数 | 保留所有项目积累 |
| antibodies.md | 追加去重 | 只增不减 |
| preferences.json | 标量 latest-wins，对象深度合并，数组合并去重 | 最新值优先 |

冲突原则：足迹/抗体只增不减，画像/偏好取最新，同一用户所以 latest-wins 可接受。

---

## Skill 钩子系统

记忆系统作为元 skill，**主动发现并整合**其他 workflow skill 的生命周期需求。

### 设计原则

- **主动整合**：记忆系统负责发现新 skill、分析需求、生成钩子——skill 作者无需额外配置
- **安全隔离**：单个 skill 钩子失败不影响记忆系统核心流程
- **执行日志**：每次钩子执行记录到 memory-index.md

### 生命周期事件

| 事件 | 触发时机 | 典型用途 |
|------|---------|---------|
| `on_session_start` | 会话恢复后（Step 2.5） | 加载 skill 上下文、展示状态摘要 |
| `on_post` | POST-3 同步阶段（3b） | 同步 skill 的跨项目数据 |
| `on_first_activate` | 首次部署 / 跨项目唤醒时（4.5） | 初始化 skill 数据、从全局恢复 |

### Skill 发现与自动整合

    每次会话启动时：
      → 扫描 .claude/skills/*/SKILL.md
      → 对比"已整合 skill"表
      → 发现新 skill？
        ├─ 已有 memory_hooks 声明 → 直接采用
        └─ 无声明 → 阅读其 SKILL.md，分析：
            1. 是否有跨项目数据（portable-* 目录）？→ on_post 同步
            2. 是否有需要会话恢复时加载的上下文？→ on_session_start
            3. 是否需要首次部署时初始化？→ on_first_activate
      → 为该 skill 生成 memory_hooks 并写入其 SKILL.md
      → 更新"已整合 skill"表

### 已整合 skill

| skill | version | on_session_start | on_post | on_first_activate |
|-------|---------|-----------------|---------|-------------------|
| **knowledge-base** | 1.0 | 加载知识索引摘要 | 合并同步 portable-knowledge/ | 恢复知识库 |
| **project-manager** | 1.0 | 加载 roadmap + sprint-board 状态 | 同步项目进度到 CLAUDE.md | 创建 docs/project/ 目录结构 |
| **game-design** | 1.0 | 加载 GDD 摘要 | — | — |
| **narrative-team** | 1.0 | 加载 story-bible 摘要 | — | — |
| **dev-team** | 1.0 | 加载 tech-design 摘要 | — | — |
| **art-team** | 1.0 | 加载 style-guide 摘要 | — | — |
| **audio-team** | 1.0 | 加载 audio-design 摘要 | — | — |
| **expert-panel** | 1.1 | — | — | — |

> 此表由记忆系统自动维护。发现新 skill 后自动分析并追加。
> version 列记录整合时的 skill 版本，用于变更检测和回退。

## 部署清单

首次激活或跨项目唤醒时自动执行：

1. `mkdir -p docs/decisions docs/archive docs/templates`
2. 复制模板（从 `assets/templates/`）：
   - `memory-index.md` → `docs/`
   - `persona.md` → `docs/`
   - `versions.md` → `docs/`
   - `decision.md` → `docs/templates/`
   - `antibodies.md` → `.agent/memory-runtime/`（无已有内容时）
   - `preferences.json` → `.agent/memory-runtime/`（无已有内容时）
3. 创建项目 `CLAUDE.md`（从 `claude-md-init.md` 模板）
4. 随行记忆恢复（从 .agent/memory-runtime/）或人格初始化（含唤醒词设置）
4.5 执行 on_first_activate 钩子
  → 扫描已安装 skill 的 on_first_activate 声明
  → 如 knowledge-base：从 {self}/portable-knowledge/ 恢复知识库
5. `git init && git commit`（如非 git 仓库）

---

## 参考文档

- **完整工作流**（POST 细节、人格捕获、随行记忆同步、压缩保护）：
  [references/memory-workflow.md](references/memory-workflow.md)

- **记忆生命周期**（创建/检索/巩固/归档/维护）：
  [references/memory-skill.md](references/memory-skill.md)

## 发布清单（提交审核前必做）

运行时数据已迁移到 `.agent/memory-runtime/`（skill 目录外），skill 目录本身不再包含用户数据，可直接分发。

### 发布前检查

- [ ] 确认 skill 目录内无残留的 `portable-memory/` 目录
- [ ] 确认 `.agent/memory-runtime/` 不在 skill 目录内

### 目录结构

| 目录 | 性质 | 位置 |
|------|------|------|
| `assets/templates/` | 空模板，部署时复制 | skill 内，随 skill 分发 |
| `references/` | 工作流参考文档 | skill 内，随 skill 分发 |
| `.agent/memory-runtime/` | 用户运行时数据 | skill 外，不随 skill 分发 |

---

## 模板文件

| 文件 | 用途 | 目标位置 |
|------|------|---------|
| `claude-md-init.md` | 项目 CLAUDE.md 模板 | 项目根目录 |
| `memory-index.md` | 记忆索引模板 | `docs/` |
| `persona.md` | 用户画像模板（三层） | `docs/` |
| `versions.md` | 版本历史（最新在上） | `docs/` |
| `decision.md` | 决策记录模板 | `docs/templates/` |
| `antibodies.md` | 跨项目抗体模板 | `.agent/memory-runtime/` |
| `preferences.json` | 用户偏好模板（含唤醒词） | `.agent/memory-runtime/` |
