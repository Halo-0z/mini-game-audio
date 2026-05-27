# 阿里云效 Codeup 远程仓库配置指南

## 用户操作步骤（在浏览器中完成）

### 第一步：登录云效 Code

1. 访问 https://codeup.aliyun.com/
2. 使用阿里云账号登录

### 第二步：创建空仓库

1. 点击「新建代码库」
2. 填写仓库名称（如游戏项目名）
3. **不要**勾选"使用 README 初始化"（保持空仓库）
4. 点击「确认创建」
5. 在仓库首页复制 **HTTPS 地址**，形如：
   ```
   https://codeup.aliyun.com/64369e40f3f04f60e055c9de/my-game.git
   ```

### 第三步：设置克隆账号密码

1. 点击右上角头像 → 「个人设置」
2. 左侧菜单找到「HTTPS 密码」（或「个人访问令牌」）
3. 设置一个**克隆账号**和**克隆密码**
4. 记下账号和密码

### 第四步：提供给 AI 助手

将以下三项信息发送到对话框：
```
仓库地址: https://codeup.aliyun.com/xxxxx/my-game.git
克隆账号: your-clone-username
克隆密码: your-clone-password
```

## AI 端配置流程

收到用户提供的三项信息后，执行以下操作：

### 1. URL 编码特殊字符

常见需要编码的字符：

| 字符 | 编码 |
|------|------|
| `@` | `%40` |
| `:` | `%3A` |
| `#` | `%23` |
| `$` | `%24` |
| `&` | `%26` |
| `+` | `%2B` |
| `/` | `%2F` |
| `=` | `%3D` |
| `?` | `%3F` |
| ` ` | `%20` |

### 2. 配置远程仓库

```bash
cd /workspace

# 配置代理
git config --local http.proxy http://127.0.0.1:1080
git config --local https.proxy http://127.0.0.1:1080

# 配置用户信息（如果尚未配置）
git config --local user.name "Maker"
git config --local user.email "maker@example.com"

# 拼接带凭据的 URL
# https://<账号>:<密码>@codeup.aliyun.com/<org>/<repo>.git
REMOTE_URL="https://${ENCODED_USERNAME}:${ENCODED_PASSWORD}@codeup.aliyun.com/${ORG_ID}/${REPO_NAME}.git"

# 检查 origin 是否已存在
if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$REMOTE_URL"
    echo "已更新远程仓库地址"
else
    git remote add origin "$REMOTE_URL"
    echo "已添加远程仓库"
fi
```

### 3. 首次推送

```bash
git add -A
git commit -m "init: 项目初始化"
git push -u origin master
```

如果远程仓库非空导致冲突：
```bash
git pull origin master --allow-unrelated-histories
git push -u origin master
```

### 4. 验证

```bash
git remote -v
git log --oneline -3
```

## 常见问题

### Q: push 报 403 / Authentication failed
- 检查克隆账号和密码是否正确
- 检查密码中的特殊字符是否已 URL 编码
- 确认已在云效个人设置中开启 HTTPS 密码

### Q: push 超时 / 网络不可达
- 确认已设置代理：`git config --local http.proxy http://127.0.0.1:1080`
- 确认代理服务正常运行

### Q: remote origin already exists
- 使用 `git remote set-url origin <新URL>` 替换现有地址

### Q: 推送被拒绝(non-fast-forward)
- 远程有新的提交，先 `git pull origin master --rebase` 再推送
