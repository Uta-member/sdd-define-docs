#!/usr/bin/env sh
# SDD Stop hook: tasks.md（作業記憶）が実装に追随しているかを機械で担保する。
#
# 狙い：セッションが重くなって /clear したときに「どこまで実装したか」「実装中に何を見つけたか」
# が消えるのを防ぐ。tasks.md はセッション間の唯一の引き継ぎ媒体なので、
# コード/テストだけが進んで tasks.md が古いままの状態を人間の目に見えるようにする。
#
# 判定：ブランチ差分に含まれるコード/テストの中に、tasks.md より新しいものがあれば「古い」。
# ブロックはしない（systemMessage で促すだけ）。判定不能なら常に沈黙する（fail-open）。
#
# 【性能】毎ターン走る。git 2〜3回 + ls 1回に抑える。

raw=$(cat)

case "$raw" in
    *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# --- 1. 作業中の tasks.md を見つける（追跡下・追跡外の両方）-------------------
tasks=$({ git ls-files --cached --others --exclude-standard 2>/dev/null; } \
        | grep -E '(^|/)tasks\.md$' | head -1)
[ -n "$tasks" ] && [ -f "$tasks" ] || exit 0

# --- 2. ブランチ基点（trace-guard.sh と同じ探索）------------------------------
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

# --- 3. この作業単位で触ったコード/テスト（ドキュメントは除く）----------------
code=$({ git diff --name-only "$base" 2>/dev/null
         git ls-files --others --exclude-standard 2>/dev/null
       } | grep -Ev '\.(md|feature)$' | sort -u)
[ -n "$code" ] || exit 0

# --- 4. tasks.md が最新か（ls -t の先頭が tasks.md なら追随できている）--------
# 存在しないパス（削除されたファイル）は ls が黙って落とすので -- で区切って渡す。
newest=$(ls -t -- $code "$tasks" 2>/dev/null | head -1)
[ -n "$newest" ] || exit 0
[ "$newest" = "$tasks" ] && exit 0

msg="[SDD] ${tasks} がコードの進捗より古いままです。完了したタスクのチェック・実装中に見つかった問題・次の一手を今のターンで追記してください。tasks.md はセッションを切ったあとの唯一の引き継ぎ媒体です（ブロックはしません）。"

if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage: $m}'
else
    printf '{"systemMessage":"%s"}\n' "$msg"
fi
exit 0
