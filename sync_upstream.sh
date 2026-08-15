#!/bin/bash

# PiliPlus 自定义版本同步脚本
# 用于同步原作者(upstream)的更新并保留 feature/custom-enhancements 分支的定制修改
#
# 注意事项（合并后必做，详见 AGENT.md）：
# 1. pubspec.yaml 的 environment.flutter 是精确版本约束，需保证本地
#    Flutter SDK 与上游要求完全一致（如 3.47.0）
# 2. 上游会给 Flutter SDK 打补丁（lib/scripts/*.patch），
#    本地 analyze/build 前需先给 SDK 打补丁：
#      FR=$(dirname $(dirname $(readlink -f $(which flutter))))
#      for p in modal_barrier text_selection mouse_cursor image_anim \
#               layout_builder navigation_drawer popup_menu fab \
#               null_safety_for_selectable_region selectable_region \
#               editable_text text_field scroll_position scrollable \
#               scrollable_gesture draggable_scrollable_sheet scaffold \
#               text text_painter sliver refresh_indicator; do
#        git -C "$FR" apply --check "lib/scripts/$p.patch" 2>/dev/null \
#          && git -C "$FR" apply "lib/scripts/$p.patch"
#      done
#    （补丁列表以 lib/scripts/patch.ps1 为准，随上游更新而变化）

set -e  # 遇到错误立即退出

echo "📥 开始同步流程..."
echo ""

# 1. 获取原作者的最新更新
echo "🔍 获取原作者(upstream)的最新代码..."
git fetch upstream

# 2. 切换到main分支并快进合并原作者的更新
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

# 4. 备份并合并更新到功能分支
BRANCH=feature/custom-enhancements
git branch "backup-before-upstream-merge-$(date +%Y%m%d-%H%M%S)" "$BRANCH"

echo "🔀 合并upstream/main到 $BRANCH ..."
git checkout "$BRANCH"
git merge upstream/main

echo ""
echo "⚠️  如有冲突，请保留所有带 [CUSTOM] 标记的定制逻辑后重新 git add 并提交。"
echo ""
echo "✅ 功能分支已更新！"
echo ""

# 5. 提示后续步骤
echo "📝 下一步操作："
echo "1. 确认 pubspec.yaml 版本号递增（如 2.1.0-mod+553N）"
echo "2. 将本地 Flutter SDK 切到 pubspec.yaml 要求的精确版本"
echo "3. 按 lib/scripts/patch.ps1 的列表给 Flutter SDK 打补丁"
echo "4. flutter pub get && flutter analyze"
echo "5. flutter build apk --release --target-platform android-arm64 验证"
echo "6. 验证通过后推送到您的fork：git push origin $BRANCH"
echo "7. 发版：gh workflow run build.yml --ref $BRANCH --repo X-Ray-git/PiliPlus -f build_android=true -f build_ios=false -f build_mac=false -f build_win_x64=false -f build_linux_x64=false -f tag=v2.1.0-mod.N"
echo ""
echo "✅ 同步完成！"
