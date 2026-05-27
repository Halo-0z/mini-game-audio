# 记忆生命周期管理

> 记忆文件的创建、维护和清理规则。

---

## 记忆文件层次

    CLAUDE.md              ← 自动注入，最重要，≤40行正文
    docs/memory-index.md   ← 详细上下文，≤60行，超出归档
    docs/persona.md        ← 用户画像，持续成长
    docs/decisions/        ← 重要决策记录（可选）
    docs/archive/          ← 冷存储

## 创建规则

**CLAUDE.md**：部署时从模板创建，后续由 POST 自动更新。
- 关键字段：当前状态、用户画像摘要、likely_next_task、恢复指令、避雷清单
- 恢复指令中必须引用 memory-system skill

**memory-index.md**：部署时从模板创建，记录项目上下文。
- 包含：代码结构、关键文件、最近变更、模块关系
- 每次 POST-1 更新

**persona.md**：部署时从模板创建或从随行记忆恢复。
- 三层画像：基础 → 工作特征 → 成长记录
- 持续观察更新，不是一次性填写

**decisions/**：当做出重要技术决策时创建。
- 格式：`YYYY-MM-DD-决策标题.md`
- 内容：背景、选项、决定、理由

## 检索规则

新会话恢复时的阅读顺序：
1. CLAUDE.md（自动注入，无需手动读取）
2. memory-index.md（必读）
3. persona.md（必读）
4. decisions/（按需，CLAUDE.md 或 memory-index 引用时才读）
5. archive/（极少，仅需要历史信息时）

## 巩固规则

POST-1 时执行记忆巩固：
- **蒸馏**：将详细信息压缩为关键摘要写入 CLAUDE.md
- **索引**：在 memory-index.md 建立指向详细文件的索引
- **归档**：memory-index.md 超过 60 行时，旧内容移入 archive/

## 归档规则

    memory-index.md 行数检查：
      ≤ 60行 → 正常
      > 60行 → 将最旧的条目移到 docs/archive/YYYY-MM.md
               保留最近的条目，压缩到 ≤ 50行

归档时保留 memory-index.md 中的：
- 避雷清单（永不归档）
- 最近 5 次变更记录
- 当前代码结构索引

## CLAUDE.md 维护规则

CLAUDE.md 是最重要的记忆文件，维护要求：
- 正文 ≤ 40 行（不含模板段落如 POST 速查）
- 每次 POST 必须更新 likely_next_task
- 避雷清单只保留活跃条目（过时的删除）
- 用户画像摘要从 persona.md 蒸馏关键特征（1-3 行）

## 遗忘规则

主动清理不再相关的记忆：
- 已修复的 bug 从避雷清单移除
- 已废弃的模块从 memory-index 移除
- 过时的决策记录移入 archive/
- 已确认的 persona 观察整理到对应维度
