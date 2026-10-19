#!/usr/bin/env bash
#
# 日本語版を upstream（英語原文）と照合する。
#   - 各章の見出し数とコードブロック区切り数が原文と一致すること
#   - upstream の章がすべてサブディレクトリに配置されていること
#   - ルート直下に英語版の章が残っていないこと
#   - Go のコード・go.mod・go.sum が upstream と同一であること
#
# 使い方: scripts/verify-translation.sh [upstream の ref（既定: upstream/main）]

set -euo pipefail

ref="${1:-upstream/main}"
cd "$(git rev-parse --show-toplevel)"

# 章ではないルート直下の Markdown
NON_CHAPTERS="CLAUDE.md LICENSE.md README.md SUMMARY.md gb-readme.md pdf-cover.md template.md"
CHAPTER_DIRS="go-fundamentals testing-fundamentals build-an-application questions-and-answers meta"
# 原文はインデント形式、訳文はフェンス形式でコードブロックを書いているため区切り数を比較しない章
FENCE_EXCEPTIONS="meta/why.md"

is_non_chapter() {
    case " $NON_CHAPTERS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_fence_exception() {
    case " $FENCE_EXCEPTIONS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

count_fences() {
    grep -c '^ *```' || true
}

count_headings() {
    awk '/^ *```/ { in_code = !in_code; next } !in_code && /^#/' | wc -l | tr -d ' '
}

status=0
fail() {
    echo "NG: $*"
    status=1
}

# 1. 章ごとの構造の一致
for dir in $CHAPTER_DIRS; do
    for ja in "$dir"/*.md; do
        en="$(basename "$ja")"
        if ! git cat-file -e "${ref}:$en" 2>/dev/null; then
            echo "skip: ${ja}（upstream に $en がない）"
            continue
        fi
        en_fences="$(git show "${ref}:$en" | count_fences)"
        ja_fences="$(count_fences < "$ja")"
        en_headings="$(git show "${ref}:$en" | count_headings)"
        ja_headings="$(count_headings < "$ja")"
        if [ "$en_fences" != "$ja_fences" ] && ! is_fence_exception "$ja"; then
            fail "${ja}: コードブロック区切り数が不一致（原文 ${en_fences} / 訳 ${ja_fences}）"
        fi
        if [ "$en_headings" != "$ja_headings" ]; then
            fail "${ja}: 見出し数が不一致（原文 ${en_headings} / 訳 ${ja_headings}）"
        fi
    done
done

# 2. upstream の章がすべて訳されていること
for en in $(git ls-tree --name-only "$ref" | grep '\.md$'); do
    is_non_chapter "$en" && continue
    found=""
    for dir in $CHAPTER_DIRS; do
        [ -f "$dir/$en" ] && found=1
    done
    [ -n "$found" ] || fail "${en}: 対応する日本語版の章がない"
done

# 3. ルート直下に英語版の章が残っていないこと
for f in *.md; do
    is_non_chapter "$f" || fail "${f}: ルート直下に章が残っている（サブディレクトリに移すか削除する）"
done

# 4. Go のコードが upstream と同一であること
if ! git diff --quiet "$ref" HEAD -- '*.go' go.mod go.sum; then
    git diff --stat "$ref" HEAD -- '*.go' go.mod go.sum
    fail "Go のコードが upstream と異なる"
fi

if [ "$status" -eq 0 ]; then
    echo "OK: すべての検証に合格しました"
fi
exit "$status"
