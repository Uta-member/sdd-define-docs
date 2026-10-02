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
#
# 【性能】毎ターン走るので、ここと check-traceability.sh のプロセス数がそのまま
# ターン終了の待ち時間になる（Windows では 1プロセス 80〜150ms）。
# 本体は --missing-only で呼び、規律チェック（design.md / implements: / supersede）は
# 走らせない。それらは /sdd:trace 側だけの関心事。
#
# 【非ASCIIパス】git は既定（core.quotepath=true）で日本語などを含むパスを引用符付きの
# 8進エスケープで出力し、テストファイル判定が外れる。git 呼び出しはこの関数を通す。
git() { command git -c core.quotepath=false "$@"; }

raw=$(cat)

# Stop フックのループ防止：フック起因の再開ではもう鳴らさない
case "$raw" in
    *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

script_dir=$(dirname "$0")

# --- 1. ブランチ基点を求める（refの探索は for-each-ref 1回で済ませる）---------
# 非gitリポジトリならここが空になり、そのまま沈黙する。
# 「.feature が追跡下にあるか」は別途見ない：無ければ 3. が何も返さないので同じこと。
base=''
for sha in $(git for-each-ref --format='%(refname:short) %(objectname)' \
                refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master \
                refs/heads/main refs/heads/master 2>/dev/null \
             | awk '{ sha[$1] = $2 }
                    END { split("origin/HEAD origin/main origin/master main master", pref, " ")
                          for (i = 1; i <= 5; i++) { r = pref[i]
                              if ((r in sha) && !seen[sha[r]]++) print sha[r] } }'); do
    base=$(git merge-base HEAD "$sha" 2>/dev/null) && [ -n "$base" ] && break
done
[ -n "$base" ] || exit 0

# --- 2. ブランチ差分にテストファイルが含まれるか ------------------------------
# `git diff <commit>` は作業ツリーと commit の比較なので、staged/unstaged の両方を含む。
# 追跡外の新規テストだけ ls-files --others で足す。
# check-traceability.sh と同じ「テストらしきファイル」判定を使う（grep 版なのでバックスラッシュは1つ）
{ git diff --name-only "$base" 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
} | grep -Eq '(^|/)(tests?|spec|__tests__)(/|\.)|(test|spec|Tests?)\.[a-z]+$|(^|/)test_[^/]+$' || exit 0

# --- 3. テストの無いAC が残っているか ---------------------------------------
# --missing-only は「【重大】…」見出し＋AC行、または「テストの無いAC: なし」だけを返す
out=$(sh "$script_dir/check-traceability.sh" --missing-only 2>/dev/null) || exit 0

missing=$(printf '%s\n' "$out" | sed -n 's/^  *\(AC-[a-z0-9-]*\)  *<-.*/\1/p')
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
