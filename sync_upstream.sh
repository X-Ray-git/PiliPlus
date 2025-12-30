#!/bin/bash

# PiliPlus 自定义版本同步脚本
# 用于同步原作者的更新并保持自己的修改

set -e  # 遇到错误立即退出

echo "📥 开始同步流程..."
echo ""

# 1. 获取原作者的最新更新
echo "🔍 获取原作者(upstream)的最新代码..."
git fetch upstream

# 2. 切换到main分支并合并原作者的更新
echo "🔄 更新本地main分支..."
git checkout main
git merge upstream/main

echo "✅ main分支已更新"
echo ""

# 3. (可选) 推送更新的main到您的fork
read -p "是否推送更新的main分支到您的GitHub fork? (y/n): " push_main
if [ "$push_main" = "y" ]; then
    echo "⬆️ 推送main到origin..."
    git push origin main
fi

echo ""

# 4. 将更新合并到功能分支
echo "🔀 更新功能分支 feature/desktop-shortcuts..."
git checkout feature/desktop-shortcuts

read -p "使用 rebase 还是 merge? (r/m): " merge_method
if [ "$merge_method" = "r" ]; then
    echo "🔄 使用 rebase 方式..."
    git rebase main
else
    echo "🔄 使用 merge 方式..."
    git merge main
fi

echo ""
echo "✅ 功能分支已更新！"
echo ""

# 5. 提示推送
echo "📝 下一步操作："
echo "1. 测试应用是否正常工作"
echo "2. 如果一切正常，推送到您的fork："
if [ "$merge_method" = "r" ]; then
    echo "   git push origin feature/desktop-shortcuts --force-with-lease"
else
    echo "   git push origin feature/desktop-shortcuts"
fi
echo ""
echo "✅ 同步完成！"
