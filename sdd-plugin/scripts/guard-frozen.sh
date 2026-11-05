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

# 【例外】マージ済みADRの「状態」行だけは Edit で書き換えてよい（提案→承認→廃止/置換 の運用のため）。
# 条件: ADR領域 / Edit ツール / replace_all でない / old_string・new_string がともに1行で
# 「状態:」「ステータス:」「Status:」（箇条書き記号・太字可）で始まる / ファイル内に old_string で始まる行が実在する。
# 1つでも満たさなければ通常どおり deny（例外側は fail-closed）。
json_str() {
    # $1 のキーの JSON 文字列値を（エスケープされたまま）取り出す
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -r --arg k "$1" '.tool_input[$k] // empty | tojson | .[1:-1]' 2>/dev/null
    else
        printf '%s' "$raw" | sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\\1/p" | head -n 1
    fi
}
is_status_line() {
    # 改行エスケープを含まない1行で、状態キーで始まる
    case "$1" in *'\n'*|*'\r'*) return 1 ;; esac
    printf '%s' "$1" | grep -Eq '^[[:space:]]*([-*][[:space:]]*)?(\*\*)?(状態|ステータス|[Ss]tatus)(\*\*)?[[:space:]]*(:|：)'
}
if printf '%s' "$rel" | grep -Eq '(^|/)docs?/adr/'; then
    tool=$(printf '%s' "$raw" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1)
    old=$(json_str old_string)
    new=$(json_str new_string)
    if [ "$tool" = "Edit" ] \
        && ! printf '%s' "$raw" | grep -Eq '"replace_all"[[:space:]]*:[[:space:]]*true' \
        && is_status_line "$old" && is_status_line "$new"; then
        # JSON エスケープ（\" と \\）を戻し、先頭空白を除いてファイルの行頭と照合する
        old_plain=$(printf '%s' "$old" | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g' -e 's/^[[:space:]]*//')
        if S="$old_plain" awk 'BEGIN { s = ENVIRON["S"] }
            { l = $0; sub(/\r$/, "", l); sub(/^[ \t]+/, "", l); if (index(l, s) == 1) f = 1 }
            END { exit !f }' "$file_path" 2>/dev/null; then
            exit 0
        fi
    fi
fi

reason="[SDD] ${rel} はマージ済みのスナップショット（write-once）のため変更できません。振る舞いを変える場合は新しい作業単位で新IDを採番し、supersedes 宣言で置き換えてください（/sdd:req）。ADRの状態行（状態: ...）だけは Edit で1行単位なら変更できます。"

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
