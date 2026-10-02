#!/usr/bin/env sh
# SDD PreToolUse hook: マージ済みスナップショット（write-once文書）への Edit/Write をブロックする。
# 対象: docs配下の units/ と adr/、および *.feature のうち、デフォルトブランチに既に存在するファイル。
# 判定不能な場合は常に許可（fail-open）。stdin に Claude Code のフックJSONを受け取る。
# 依存は git と POSIX 標準コマンドのみ（Windows は Git 同梱の bash で動作する）。
#
# 【非ASCIIパス】git は既定（core.quotepath=true）で日本語などを含むパスを引用符付きの
# 8進エスケープで出力し、パス判定と cat-file が外れて素通しになる。git 呼び出しはこの関数を通す。
git() { command git -c core.quotepath=false "$@"; }

raw=$(cat)
[ -n "$raw" ] || exit 0

# tool_input.file_path を取り出す。jq があれば使い、無ければ sed でフォールバックする。
if command -v jq >/dev/null 2>&1; then
    file_path=$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
    file_path=$(printf '%s' "$raw" \
        | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1)
    # JSON のエスケープを戻す（Windows パスの \\ など）
    file_path=$(printf '%s' "$file_path" | sed 's/\\\\/\\/g')
fi
[ -n "$file_path" ] || exit 0

# Windows 形式の区切りを git が扱える形に正規化する
file_path=$(printf '%s' "$file_path" | tr '\\' '/')

# git管理下の相対パスを得る（未追跡 = この作業単位で作成中 → 許可）
rel=$(git ls-files --full-name -- "$file_path" 2>/dev/null | head -n 1)
[ -n "$rel" ] || exit 0

# スナップショット領域かどうか
if ! printf '%s' "$rel" | grep -Eq '(^|/)docs?/units/|(^|/)docs?/adr/|\.feature$'; then
    exit 0
fi

# デフォルトブランチ（マージ済み履歴）に存在するか
frozen=0
for ref in origin/HEAD origin/main origin/master main master; do
    if git cat-file -e "${ref}:${rel}" 2>/dev/null; then
        frozen=1
        break
    fi
done
[ "$frozen" -eq 1 ] || exit 0

reason="[SDD] ${rel} はマージ済みのスナップショット（write-once）のため変更できません。振る舞いを変える場合は新しい作業単位で新IDを採番し、supersedes 宣言で置き換えてください（/sdd:req）。"

if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
else
    # reason に " と \ は含まれない前提（上のリテラル）なのでそのまま埋め込む
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
exit 0
