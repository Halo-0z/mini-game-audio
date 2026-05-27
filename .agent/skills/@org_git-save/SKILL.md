---
name: git-save
description: >
  Git 版本管理与阿里云效 Codeup 远程仓库集成。
  Use when: (1) 用户说"保存代码"、"提交代码"、"git save"、"git提交"、"保存进度"、"备份代码",
  (2) 用户要求配置远程仓库、连接 Codeup、设置 git,
  (3) 用户提供了仓库地址+克隆账号+克隆密码要求配置,
  (4) 开发前/验收后需要保存版本节点,
  (5) 用户说 /git-save 或 /commit。
---

# Git Save — 版本管理与远程仓库

## 工作流程

```
初始化(仅首次)          日常开发
───────────            ──────────
1. 初始化本地仓库        1. 开发前: git save (快照当前状态)
2. 配置远程仓库          2. 开发中: 正常编码
3. 首次推送             3. 验收后: git save (保存成果)
```

## 1. 初始化本地仓库

检查 `/workspace` 是否已有 git 仓库，没有则初始化：

```bash
cd /workspace
git init
git config user.name "Maker"
git config user.email "maker@example.com"
```

确保 `.gitignore` 包含必要的排除项：

```gitignore
.build/
dist/
.tmp/
node_modules/
logs/build/
```

## 2. 配置远程仓库(阿里云效 Codeup)

**前置条件**：用户需提供三个信息：
- **仓库 HTTPS 地址**: 形如 `https://codeup.aliyun.com/<org_id>/<repo_name>.git`
- **克隆账号**: 在云效个人设置中创建的 HTTPS 克隆账号
- **克隆密码**: 对应的克隆密码

**配置命令**（将凭据嵌入 URL）：

```bash
# 设置代理（沙箱环境必须）
git config --local http.proxy http://127.0.0.1:1080
git config --local https.proxy http://127.0.0.1:1080

# 配置远程仓库（凭据嵌入 URL，避免交互式输入）
# 格式: https://<账号>:<密码>@codeup.aliyun.com/<org_id>/<repo>.git
git remote add origin "https://<账号>:<密码>@codeup.aliyun.com/<org_id>/<repo>.git"

# 如果 origin 已存在，用 set-url 替换
git remote set-url origin "https://<账号>:<密码>@codeup.aliyun.com/<org_id>/<repo>.git"
```

**重要**：账号和密码中的特殊字符需 URL 编码（如 `@` → `%40`）。

首次推送：

```bash
git add -A
git commit -m "init: 项目初始化"
git push -u origin master
```

详细的 Codeup 配置步骤见 [references/aliyun-codeup-guide.md](references/aliyun-codeup-guide.md)。

## 3. 日常保存(git save)

执行 `scripts/git_save.sh` 脚本，自动完成 add → commit → push：

```bash
bash /workspace/.claude/skills/git-save/scripts/git_save.sh "提交信息"
```

**提交信息规范**：

| 时机 | 前缀 | 示例 |
|------|------|------|
| 开发前保存 | `backup:` | `backup: V0.39 开发前备份` |
| 功能完成 | `feat(版本):` | `feat(V0.39): 新增背包系统` |
| BUG修复 | `fix:` | `fix: 修复商店刷新bug` |
| 验收通过 | `feat(版本):` | `feat(V0.39): 全量验收通过` |

## 4. 触发时机

| 场景 | 操作 |
|------|------|
| 用户说"保存/提交/备份代码" | 执行 git save |
| 开始新一轮开发前 | 先执行 `backup:` 保存 |
| 功能开发+验收完成后 | 执行 `feat:` 保存 |
| 用户提供仓库地址+账号密码 | 执行远程仓库配置 |

## 5. 注意事项

- 沙箱环境**必须配置代理** `http://127.0.0.1:1080` 才能访问外网
- 凭据嵌入 URL 中，不依赖 credential helper（沙箱无持久化凭据存储）
- 只提交 `scripts/`、`docs/`、`assets/` 等用户代码目录；引擎目录由 `.gitignore` 排除
- 推送失败时检查：代理配置、凭据正确性、仓库是否已创建
