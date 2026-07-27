#!/usr/bin/env sh
# SDD Stop hook: trace（回帰網の穴の検知）の実行をプロンプトではなく仕組みで担保する。
#
# 狙い：AIが /sdd:trace を呼び忘れても、「テストの無いAC」が残ったままターンを終える状況を
# 人間の目に見えるようにする。ブロックはしない（trace の非ブロック方針は維持）。
#
# 発火条件（ノイズを避けるため全部満たしたときだけ警告する）：
#   1. gitリポジトリで、追跡下に .feature がある
#   2. デフォルトブランチとの差分に「テストらしきファイル」が含まれる
#      → 実装が始まっている作業単位でだけ鳴る。要件定義フェーズ（テスト未着手）では鳴らない
#   3. check-traceability.sh が「テストの無いAC」を報告した
#
# 判定不能な場合は常に沈黙する（fail-open）。依存は git と POSIX 標準コマンドのみ。

raw=$(cat)

# Stop フックのループ防止：フック起因の再開ではもう鳴らさない
case "$raw" in
    *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

script_dir=$(dirname "$0")

# --- 1. .feature が追跡下にあるか -------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git ls-files -- '*.feature' 2>/dev/null | head -n 1 | grep -q . || exit 0

# --- 2. ブランチ差分にテストファイルが含まれるか ------------------------------
base=''
for ref in origin/HEAD origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
        base=$(git merge-base HEAD "$ref" 2>/dev/null) && [ -n "$base" ] && break
    fi
done
[ -n "$base" ] || exit 0

changed=$(git diff --name-only "$base" 2>/dev/null; git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
# check-traceability.sh と同じ「テストらしきファイル」判定を使う
printf '%s\n' "$changed" \
    | grep -Eq '(^|/)(tests?|spec|__tests__)(/|\.)|(test|spec|Tests?)\.[a-z]+$|(^|/)test_[^/]+$' || exit 0

# --- 3. テストの無いAC が残っているか ---------------------------------------
out=$(sh "$script_dir/check-traceability.sh" 2>/dev/null) || exit 0

# 「【重大】テストの無いAC」見出しから、次の空行までの AC 行を拾う
missing=$(printf '%s\n' "$out" | awk '
    /^【重大】テストの無いAC/ { grab=1; next }
    grab && /^ *AC-/ { gsub(/^ +/, ""); sub(/ +<-.*/, ""); print }
    grab && !/^ *AC-/ { grab=0 }
')
[ -n "$missing" ] || exit 0

ids=$(printf '%s\n' "$missing" | tr '\n' ' ' | sed 's/ *$//')
count=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')

msg="[SDD] テストの無いACが ${count} 件残っています: ${ids} — 統合テストへの吸収は【不変条件】です。/sdd:trace で詳細を確認してください（ブロックはしません）。"

if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage: $m}'
else
    # ID一覧に " と \ は現れない（AC-<slug>-<n> の形）ためそのまま埋め込める
    printf '{"systemMessage":"%s"}\n' "$msg"
fi
exit 0
