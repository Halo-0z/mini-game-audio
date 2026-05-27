#\!/bin/bash
# git_save.sh - 一键保存代码到本地+远程仓库
# 用法: bash git_save.sh "提交信息"
# 示例: bash git_save.sh "feat(V0.39): 新增背包系统"

set -e

cd /workspace

# ── 参数检查 ──
COMMIT_MSG="${1:-auto: 自动保存 $(date '+%Y-%m-%d %H:%M:%S')}"

# ── 颜色定义 ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[Git Save]${NC} 开始保存..."

# ── 检查是否为 git 仓库 ──
if [ \! -d .git ]; then
    echo -e "${RED}[错误]${NC} 当前目录不是 git 仓库，请先初始化"
    exit 1
fi

# ── 检查是否有变更 ──
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo -e "${YELLOW}[提示]${NC} 没有需要提交的变更"
    exit 0
fi

# ── 显示变更摘要 ──
echo -e "${GREEN}[变更摘要]${NC}"
echo "  修改: $(git diff --name-only 2>/dev/null | wc -l) 个文件"
echo "  新增: $(git ls-files --others --exclude-standard 2>/dev/null | wc -l) 个文件"

# ── 提交 ──
git add -A
git commit -m "$COMMIT_MSG"
echo -e "${GREEN}[已提交]${NC} $COMMIT_MSG"

# ── 推送到远程（如果配置了 origin）──
if git remote get-url origin &>/dev/null; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "${GREEN}[推送中]${NC} → origin/$BRANCH"
    if git push origin "$BRANCH" 2>&1; then
        echo -e "${GREEN}[完成]${NC} 已推送到远程仓库"
    else
        echo -e "${YELLOW}[警告]${NC} 推送失败，代码已保存到本地"
        echo "  可能原因: 网络问题或凭据过期"
        echo "  本地提交已保存，稍后可手动推送: git push origin $BRANCH"
    fi
else
    echo -e "${YELLOW}[提示]${NC} 未配置远程仓库，代码仅保存到本地"
    echo "  配置远程仓库请提供: 仓库地址 + 克隆账号 + 克隆密码"
fi

# ── 显示最近提交 ──
echo ""
echo -e "${GREEN}[最近提交]${NC}"
git log --oneline -3
