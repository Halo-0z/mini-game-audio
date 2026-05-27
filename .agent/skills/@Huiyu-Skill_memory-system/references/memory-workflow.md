# 记忆系统工作流准则

> SKILL.md 的详细补充。仅在需要深入了解规则时阅读。

---

## 执行保障机制 🔴

> POST 丢失的根因：上下文被冲时 AI 已不"知道"有 POST 要做。
> 解决方案：任务开始时就把 POST 写入 TodoWrite，而不是完成后再写。

### TodoWrite 前置原则

**收到任何非纯讨论的任务后，第一个动作**是用 TodoWrite 创建包含 POST 的完整工作流：

```
TodoWrite([
  { content: "DEV: [具体任务描述]", status: "in_progress" },
  { content: "POST-1 更新记忆：CLAUDE.md + memory-index.md + persona.md", status: "pending" },
  { content: "POST-2 持久化：versions.md + git commit", status: "pending" },
  { content: "POST-3 同步随行记忆：.agent/memory-runtime/", status: "pending" }
])
```

**为什么前置而非后置**：
- 后置 = 完成编码后才写 TodoWrite → 如果上下文在"编码完成"和"写 TodoWrite"之间被冲 → POST 丢失
- 前置 = 收到任务就写 TodoWrite → TodoWrite 是引擎内置工具，不依赖 skill 上下文 → 即使上下文被冲，未完成的 POST 条目仍驱动 AI 执行

### 强制判定原则

所有 POST 步骤遵循：**强制出现 → 强制判定 → 允许跳过**。

1. **强制出现**：POST-1/2/3 必须出现在 TodoWrite 中，不可预先删除
2. **强制判定**：执行到该步骤时，必须做"执行/跳过"决策
3. **允许跳过**：判定为跳过时，在 TodoWrite 中标注理由后标记完成

**禁止行为**：
- ❌ 直接从 TodoWrite 删除 POST 条目来"跳过"
- ❌ 不做判定就跳过（"感觉不需要"不是理由）
- ❌ 因为"上次跳过了"这次也跳过（每次必须重新判定）

**跳过的正确做法**：
```
// 标记完成时修改 content 注明理由
{ content: "POST-3 [判定跳过: 小调整，无跨项目信息变更]", status: "completed" }
```

---

## POST 详细规则

POST 是记忆存活的唯一入口。每次完成任务（无论大小）后必须执行。

### POST-1: 更新记忆

**CLAUDE.md**（项目状态快照，≤40行正文）：
- 刷新"当前状态"（版本、进度、上次交付）
- 更新 likely_next_task（必填）
- 更新避雷清单（新踩的坑追加，过时的删除）
- 更新用户画像摘要（从 persona.md 蒸馏关键特征）

**memory-index.md**（项目详细上下文）：
- 记录本次变更：改了什么、为什么改
- 更新代码结构索引（关键文件、模块关系）
- 超过 60 行 → 将旧内容归档到 `docs/archive/`

**persona.md**（用户画像）：
- 检查本次协作中是否发现新的用户特征
- 显式偏好：用户明确表达的（直接记录）
- 隐式偏好：AI 观察到的模式（标记 `[observed]`）
- 漂移检测：已知特征与当前行为不一致（标记 `[drift]`）

### POST-2: 持久化

**versions.md 追加**（git commit 前）：
- 在 `docs/versions.md` 表头（表头行下方第一行）插入新版本行
- 格式：`| vX.X.X | YYYY-MM-DD | 变更摘要 |`
- 最新版本始终在最上面

```
git add -A
git commit -m "描述本次交付内容"
```

如果项目不使用 git，跳过 git 步骤但仍更新 versions.md。

### POST-3: 同步随行记忆 + 执行 skill 钩子

将跨项目通用的记忆**合并写入**两个位置：
`.agent/memory-runtime/`（独立于 skill 目录，跨项目共享）。

合并流程（每个文件都是：读全局 → 合并 → 写回全局 + 本地）：

    persona.md:
      基础画像/工作特征 → latest-wins（当前项目值覆盖）
      项目足迹 → 追加去重（按项目名）
      观察笔记 → 追加合并计数（同描述合并出现次数）

    antibodies.md:
      → 追加去重（按条目内容，忽略编号）
      仅同步标记 [跨项目] 的条目

    preferences.json:
      标量字段（wake_word 等）→ latest-wins
      对象字段（code_preferences 等）→ 深度合并，当前值优先
      数组字段（explicit_preferences 等）→ 合并去重

### POST 的简化判断

| 场景 | POST 范围 | 强制判定 |
|------|----------|---------|
| 完成新功能/修复 bug | 完整 POST（3 步全做） | 3 步都执行 |
| 小调整（改参数、改文案） | POST-1 简写 + POST-2 | POST-3 判定跳过并标注理由 |
| 纯讨论/问答 | 不需要 POST | 不创建 TodoWrite |
| 上下文即将压缩 | 完整 POST（紧急保护） | 3 步都执行 |

---

## 会话恢复详细流程

每次新会话，按项目 CLAUDE.md 的"恢复指令"执行：

    1. CLAUDE.md 自动注入（无需操作）
       ↓
    2. 读项目 CLAUDE.md → 获取项目状态
       ↓
    3. 读 docs/memory-index.md → 恢复项目上下文
    4. 读 docs/persona.md → 加载用户画像和偏好
       ↓
    5. 自测三问（内部执行，不需要输出）：
       - 项目核心是什么？关键文件？
       - 上次交付了什么？下一步？
       - 关键约束和避雷？
       → 全部清楚 → 开始工作
       → 有模糊 → 按需多读 decisions/ 或源代码
       ↓
    6. 简要告知用户记忆恢复情况

---

## 压缩保护

当对话上下文即将压缩时（高轮次、系统提示接近限制）：

1. 立即执行完整 POST
2. 确保 CLAUDE.md 的 likely_next_task 准确
3. 确保 memory-index.md 包含当前任务状态
4. 同步随行记忆

---

## 人格捕获详细规则

### 自然发现（不搞问卷）

首次交互时只问 4 个问题：
1. "你希望我怎么称呼你？"（同时介绍助手自称）
2. "你喜欢什么风格的沟通？"
3. "你的技术背景是什么？"
4. "你想给我起个名字吗？之后在新项目里叫这个名字就能唤醒我。"

其他维度通过协作自然发现，不要一次性问完。

### 唤醒词设置与维护

**首次设置**：人格初始化第 4 个问题。用户可以：
- 起名 → 保存到 `.agent/memory-runtime/preferences.json` 的 `wake_word` 字段
- 跳过 → `wake_word` 设为 `null`，后续可随时设置

**更改唤醒词**：用户说"改唤醒词"、"换个名字"、"我想叫你 XX" → 更新两处：
1. `docs/persona.md` 基础画像的唤醒词字段
2. `.agent/memory-runtime/preferences.json` 的 `wake_word`

**跨项目唤醒**：用户在新项目说出唤醒词 → skill 触发条件 (7) 匹配 → 恢复记忆。

### 隐式捕获流程

    观察到用户特征
      ↓
    记录到 persona.md 观察笔记，标记 [observed]，记录出现次数
      ↓
    同类观察 ≥ 3 次
      ↓
    在合适时机向用户确认：
      "我注意到你倾向于 X，是这样吗？"
      ↓
    确认 → 迁移到对应维度（去掉 [observed]）
    否定 → 删除该观察

### 漂移检测

    已知画像: 用户喜欢详细解释
    当前行为: 连续 3 次要求"简短点"
      ↓
    标记 [drift] 在观察笔记
      ↓
    连续出现
      ↓
    "我注意到你最近更倾向简洁回复，要更新偏好吗？"
      ↓
    确认 → 更新基础画像
    否定 → 删除 [drift]（可能只是临时状态）

### 项目足迹更新

每个项目结束（或切换到新项目）时：
- 在 persona.md 项目足迹表追加一行
- 记录：项目名、类型、关键经验、技能成长
- 这些信息随 .agent/memory-runtime/ 迁移到下一个项目

---

## 随行记忆同步规则

### 同步时机
- 每次 POST-3（合并写入全局 + 本地）
- 上下文压缩前（紧急保护）
- 项目结束/切换时

### 同步内容

| 源文件 | 目标 | 同步策略 |
|--------|------|---------|
| persona.md | .agent/memory-runtime/ | 按章节合并（画像latest-wins，足迹追加去重，观察合并计数） |
| CLAUDE.md 避雷清单 [跨项目] 条目 | .agent/memory-runtime/antibodies.md | 追加去重 |
| 用户偏好（含唤醒词） | .agent/memory-runtime/preferences.json | 字段级合并（标量latest-wins，数组合并去重） |
| portable-knowledge/ (via 钩子) | {skill}/portable-knowledge/ | index 追加去重，entries 按文件同步 |

### scope 标记与同步

POST-3 同步 persona.md 时，保留每条记录的 scope 标记：

    persona.md 合并规则（含 scope）：
      基础画像/工作特征 → latest-wins，保留 scope 标记
      项目足迹 → 追加去重（按项目名）
      观察笔记 → 追加合并计数，保留 scope 标记

跨项目加载时按 scope 过滤：
- 无标记 → 自动应用
- [scope:gamedev] → 仅游戏项目自动应用
- [scope:project] → 展示但不自动应用，询问用户

### 跨项目唤醒详细流程

当 skill 在新项目首次触发（项目 CLAUDE.md 不存在），触发方式包括：
- skill 自动检测到无 CLAUDE.md
- 用户说出唤醒词（skill 触发条件 7）

    0. 检查 .agent/memory-runtime/
       → 存在？读取随行记忆
       → 不存在？全新用户
       ↓
    1. 有 persona.md？
       → 有：复制到 docs/persona.md
            告知用户"我记得你的偏好（来自之前的项目协作）"
            展示关键画像信息（含唤醒词身份）
            询问"要沿用这些设定吗？"
       → 无：首次使用，执行人格初始化（4个基础问题，含唤醒词）
       ↓
    2. 有 antibodies.md？
       → 有：合并到新项目 CLAUDE.md 避雷清单
       → 无：跳过
       ↓
    3. 有 preferences.json？
       → 有：恢复用户偏好设置（含唤醒词）
       → 无：跳过
       ↓
    4. 继续部署流程（创建目录、初始化文件等）

---

## 记忆健康维护

定期（约每 5 次 POST 或用户主动要求时）检查：
- memory-index.md 是否过长（>60行 → 归档旧内容）
- persona.md 是否有积压的 [observed] 待确认
- CLAUDE.md 状态是否与实际一致
- 避雷清单是否有过时条目
- 随行记忆是否已同步最新版本
- 唤醒词是否在 persona.md 和 preferences.json 中一致
- skill 钩子是否正常执行（检查最近 POST 的钩子日志）
- 已整合 skill 的版本号是否与 frontmatter 一致（不一致 → 触发重新整合）
- 已整合 skill 的跨项目数据是否已同步（如 portable-knowledge/）
