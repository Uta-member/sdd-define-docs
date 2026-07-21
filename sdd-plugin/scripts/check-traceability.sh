#!/usr/bin/env sh
# SDD 発見的チェック: .feature の @AC タグとテストコードの AC 参照の乖離を報告する。
# ブロックしない補助ツール。git管理下のファイルのみを対象にする。
# 依存は git と POSIX 標準コマンドのみ。
#
# 【対象は機能AC（AC-<n>）のみ】NFR（NFR-<n>）は意図的に対象外。
# NFRは機能回帰網でなく負荷試験/監視/診断の別トラックで担保するため、
# ここで「テストの無いAC」として報告するとノイズになる（→ 11 NFR検証ライフサイクル）。
# 別プレフィックスにより下の @AC-/AC_ マッチが NFR-* を自然に拾わない。
# NFR-* を追跡対象に加えないこと。

tracked=$(git ls-files 2>/dev/null)
if [ -z "$tracked" ]; then
    echo 'gitリポジトリではないか、追跡ファイルがありません。'
    exit 0
fi

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
feature_list="$work/feature"   # "<AC番号> <ファイル>" 形式
test_list="$work/test"
: > "$feature_list"
: > "$test_list"

printf '%s\n' "$tracked" | while IFS= read -r f; do
    [ -f "$f" ] || continue

    case "$f" in
        *.feature)
            grep -oE '@AC-[0-9]+' "$f" 2>/dev/null \
                | sed 's/^@AC-//' \
                | while IFS= read -r id; do printf '%s %s\n' "$id" "$f"; done >> "$feature_list"
            continue
            ;;
    esac

    # テストらしきファイルかどうか（元の PowerShell 版と同じ判定）
    if printf '%s' "$f" | grep -Eq '(^|/)(tests?|spec|__tests__)(/|\.)|(test|spec|Tests?)\.[a-z]+$|(^|/)test_[^/]+$'; then
        grep -oE 'AC[-_][0-9]+' "$f" 2>/dev/null \
            | sed 's/^AC[-_]//' \
            | while IFS= read -r id; do printf '%s %s\n' "$id" "$f"; done >> "$test_list"
    fi
done

sort -u -o "$feature_list" "$feature_list"
sort -u -o "$test_list" "$test_list"

# AC番号 -> 参照ファイルをカンマ区切りで畳む
fold_ids() {
    awk '{ id=$1; $1=""; sub(/^ /,""); if (m[id]) m[id]=m[id] ", " $0; else m[id]=$0 }
         END { for (id in m) print id "\t" m[id] }' "$1" | sort -n
}

feature_ids=$(cut -d' ' -f1 "$feature_list" | sort -u)
test_ids=$(cut -d' ' -f1 "$test_list" | sort -u)
feature_folded=$(fold_ids "$feature_list")
test_folded=$(fold_ids "$test_list")

count() { [ -z "$1" ] && echo 0 || printf '%s\n' "$1" | wc -l | tr -d ' '; }

echo "=== SDD トレーサビリティチェック ==="
echo ".feature 内のAC: $(count "$feature_ids")件 / テストが参照するAC: $(count "$test_ids")件"
echo ''

report() {
    # $1: 見出し, $2: 無かった場合の文言, $3: 対象ID一覧, $4: 除外するID一覧, $5: 畳んだ表
    printf '%s\n' "$3" | sed '/^$/d' | sort > "$work/lhs"
    printf '%s\n' "$4" | sed '/^$/d' | sort > "$work/rhs"
    ids=$(comm -23 "$work/lhs" "$work/rhs" | sort -n)
    if [ -n "$ids" ]; then
        echo "$1"
        printf '%s\n' "$ids" | while IFS= read -r id; do
            files=$(printf '%s\n' "$5" | awk -F'\t' -v i="$id" '$1==i { print $2 }')
            printf '  AC-%s  <- %s\n' "$id" "$files"
        done
    else
        echo "$2"
    fi
}

report "【重大】テストの無いAC（回帰の穴の候補。統合テストへの吸収が絶対条件）:" \
       "テストの無いAC: なし" "$feature_ids" "$test_ids" "$feature_folded"
echo ''
report "【注意】.feature に存在しないACを参照するテスト（タグ漏れ or 廃止済みIDの残骸）:" \
       ".feature に無いACを指すテスト: なし" "$test_ids" "$feature_ids" "$test_folded"
