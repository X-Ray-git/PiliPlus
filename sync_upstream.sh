#!/bin/bash
# [CUSTOM] Merge upstream locally; review and validate before committing/pushing.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]] || git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "工作区有未提交改动或未完成的合并，请先处理。" >&2
  exit 1
fi

BRANCH=feature/custom-enhancements
git show-ref --verify --quiet "refs/heads/$BRANCH"
git fetch --no-tags upstream
git branch "codex/backup-custom-$(date +%Y%m%d-%H%M%S)" "$BRANCH"
git checkout main
git merge --ff-only upstream/main
git checkout "$BRANCH"
if ! git merge --no-commit --no-ff main; then
  echo "合并未完成：请检查 Git 输出；若有冲突，保留定制功能并逐项处理。" >&2
  exit 1
fi

cat <<'NEXT'
下一步：
1. 检查相对 main 的差异，保留收藏、稍后再看、桌面快捷方式和媒体控制定制。
2. 使用 pubspec.yaml 指定的 Flutter 精确版本和独立 PUB_CACHE。
3. 按 README 的构建说明给 Flutter SDK 和 material_ui 打补丁。
4. 运行 flutter analyze --no-pub、flutter test --no-pub 和 Android arm64 release 构建。
5. 验证通过后完成 merge commit；versionCode = 提交数 + 407。
6. 确认需要同步远程时，再执行 git push origin main feature/custom-enhancements。
7. 发版时在验证过的 custom 提交创建标签并推送到 origin。
   不要向 upstream 推送，不要用尚不存在的 tag 手动触发发布。
本脚本不会推送、打标签或发布。应用内检查更新的来源保持不变。
NEXT
