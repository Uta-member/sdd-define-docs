#!/usr/bin/env sh
# SDD 発見的チェック: .feature の @AC タグとテストコードの AC 参照の乖離を報告する。
# ブロックしない補助ツール。git管理下のファイル + 未トラックの新規ファイル（.gitignore対象は除く）を対象にする。
# 依存は git と POSIX 標準コマンドのみ。
#
# 【未トラックファイルも対象】新規ユニットは実装/テストが git add される前に
# /sdd:trace や trace-guard.sh から呼ばれることが多い。git grep はデフォルトで
# 追跡済みファイルしか見ないため、素の `git grep` だと新規ファイルのACが
# 「テストの無いAC」に誤検知される。`--untracked` を付けて回避する
#（.gitignore 対象は従来どおり除外される）。
#
# 使い方:
#   check-traceability.sh                 全6項目を報告する（/sdd:trace 用）
#   check-traceability.sh --missing-only  「テストの無いAC」だけを報告する（Stopフック用）
#
# 【対象は機能AC（AC-<n>）のみ】NFR（NFR-<n>）は意図的に対象外。
# NFRは機能回帰網でなく負荷試験/監視/診断の別トラックで担保するため、
# ここで「テストの無いAC」として報告するとノイズになる（→ 11 NFR検証ライフサイクル）。
# 別プレフィックスにより下の @AC-/AC_ マッチが NFR-* を自然に拾わない。
# NFR-* を追跡対象に加えないこと。
#
# 【性能：プロセス数がすべて】Windows のプロセス生成は 1回あたり 80〜150ms かかる。
# 本スクリプトは Stop フック（trace-guard.sh）から毎ターン呼ばれるので、
# 「ファイルごと」「AC-IDごと」にコマンドを起こす構造を書くと即座に数十秒に膨らむ
# （実際、per-file grep 版は実測 33 秒だった）。走査は git grep 一発、集計は awk 一発に
# まとめること。ループを足したくなったら awk の中に入れる。

mode=full
[ "$1" = '--missing-only' ] && mode=missing

# リポジトリルートで実行する。git ls-files はカレント相対のパスを返すため、
# ここを揃えないと ls-tree（常にルート相対）との突き合わせがずれる。
root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
    [ "$mode" = full ] && echo 'gitリポジトリではありません。'
    exit 0
fi
cd "$root" 2>/dev/null || exit 0

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
feature_list="$work/feature"   # "<AC番号> <ファイル>" 形式
test_list="$work/test"

# テストらしきファイルの判定（元の PowerShell 版と同じ、trace-guard.sh とも同じ）。
# awk へ -v で渡す動的正規表現なので、文字列エスケープの分だけバックスラッシュを二重にする
# （`\.` のままだと awk が「escape sequence treated as plain」警告を stderr に吐く）。
test_path_re='(^|/)(tests?|spec|__tests__)(/|\\.)|(test|spec|Tests?)\\.[a-z]+$|(^|/)test_[^/]+$'

# --- AC参照の収集：リポジトリ全体を git grep 一発でなめて awk で仕分ける ------
# .feature 側は @AC-<slug>-<n>（'@' 必須）、テスト側は AC-<slug>-<n> / AC_<slug>_<n>。
# 先に '@?' を付けた1本のパターンで拾い、パスを見て振り分ける。
git grep -I --no-color --untracked -oE '@?AC[-_][a-z0-9]+[-_][0-9]+' 2>/dev/null | awk \
    -v tre="$test_path_re" -v flist="$feature_list" -v tlist="$test_list" '
    {
        # "<path>:<match>" を最後の ":" で割る（パスに ":" があっても壊れないように）
        i = length($0)
        while (i > 0 && substr($0, i, 1) != ":") i--
        if (i == 0) next
        path = substr($0, 1, i - 1)
        m    = substr($0, i + 1)

        if (path ~ /\.feature$/) {
            if (substr(m, 1, 1) != "@") next          # .feature 内はタグ（@付き）だけが宣言
            id = substr(m, 5)                         # "@AC-" の4文字を落とす
            if (id !~ /^[a-z0-9]+-[0-9]+$/) next
            print id " " path > (flist)
        } else if (path ~ tre) {
            if (substr(m, 1, 1) == "@") m = substr(m, 2)
            id = substr(m, 4)                         # "AC-" / "AC_" の3文字を落とす
            gsub(/_/, "-", id)                        # 区切りを "-" に正規化して比較する
            print id " " path > (tlist)
        }
    }'
[ -f "$feature_list" ] || : > "$feature_list"
[ -f "$test_list" ] || : > "$test_list"
sort -u -o "$feature_list" "$feature_list"
sort -u -o "$test_list" "$test_list"

# AC番号 -> 参照ファイルをカンマ区切りで畳んだ表（"<id>\t<files>"）を作る
fold_ids() {    # $1: ペア一覧, $2: 出力先
    awk '{ id=$1; $1=""; sub(/^ /,""); if (id in m) m[id]=m[id] ", " $0; else m[id]=$0 }
         END { for (id in m) print id "\t" m[id] }' "$1" | sort -n > "$2"
}
feature_folded="$work/feature_folded"
test_folded="$work/test_folded"
fold_ids "$feature_list" "$feature_folded"
fold_ids "$test_list" "$test_folded"

# 差集合の報告。AC-IDごとにコマンドを起こさないよう awk 1プロセスで完結させる。
report() {  # $1: 見出し, $2: 無かった場合の文言, $3: 対象の畳んだ表, $4: 除外IDを持つ畳んだ表
    awk -F'\t' -v head="$1" -v none="$2" -v exfile="$4" '
        FILENAME == exfile { excl[$1] = 1; next }
        !($1 in excl) { if (!n++) print head; printf "  AC-%s  <- %s\n", $1, $2 }
        END { if (!n) print none }
    ' "$4" "$3"
}

missing_head='【重大】テストの無いAC（回帰の穴の候補。統合テストへの吸収は【不変条件】）:'

if [ "$mode" = missing ]; then
    # Stopフック用の最小経路。ここから下（規律チェック）はプロセスを食うので走らせない。
    report "$missing_head" "テストの無いAC: なし" "$feature_folded" "$test_folded"
    exit 0
fi

echo "=== SDD トレーサビリティチェック ==="
echo ".feature 内のAC: $(wc -l < "$feature_folded" | tr -d ' ')件 / テストが参照するAC: $(wc -l < "$test_folded" | tr -d ' ')件"
echo ''

report "$missing_head" "テストの無いAC: なし" "$feature_folded" "$test_folded"
echo ''
report '【注意】.feature に存在しないACを参照するテスト（タグ漏れ or 廃止済みIDの残骸）:' \
       '.feature に無いACを指すテスト: なし' "$test_folded" "$feature_folded"
echo ''

# 採番衝突の検出（安全網。→ 12 採番の衝突と直列化）
# 名前空間ID（AC-<slug>-<n>）では衝突は構造的に起きないはずだが、万一
# slugの使い回し等で同一AC-IDが2つ以上の別 .feature に現れたら異常として報告する。
# co-location + 追記型では各AC-IDはただ1つの .feature でだけ定義されるのが正。
awk -F'\t' '
    { split($2, a, ", "); c = 0; delete seen
      for (i in a) if (!seen[a[i]]++) c++
      if (c > 1) { if (!n++) print "【重大】同一AC-IDが複数の .feature に定義（採番衝突の候補。マージ直前の振り直し漏れ）:"
                   printf "  AC-%s  <- %s\n", $1, $2 } }
    END { if (!n) print "採番衝突（同一ACの複数定義）: なし" }
' "$feature_folded"
echo ''

# ---------------------------------------------------------------------------
# 規律チェック（ID宣言の抜け）
#
# 以下3つは以前 /sdd:trace の「AIレビュー（全文検索ベース）」として
# AIに毎回 Grep 探索させていたが、いずれも純粋な grep 判定なのでここに機械化した。
# skill 側は本スクリプトの出力を報告するだけでよく、独自探索は行わない
# （メインセッションのコンテキストを食う割に発見が機械判定と同じだったため）。
# ---------------------------------------------------------------------------

# --- デフォルトブランチ（マージ済み履歴）の把握 -------------------------------
# guard-frozen.sh と同じ ref 群を、for-each-ref 1回でまとめて解決する。
frozen_paths="$work/frozen"
: > "$frozen_paths"
shas=$(git for-each-ref --format='%(refname:short) %(objectname)' \
        refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master \
        refs/heads/main refs/heads/master 2>/dev/null \
    | awk '{ sha[$1] = $2 }
           END { split("origin/HEAD origin/main origin/master main master", pref, " ")
                 for (i = 1; i <= 5; i++) { r = pref[i]
                     if ((r in sha) && !seen[sha[r]]++) print sha[r] } }')
base=''
for sha in $shas; do
    [ -n "$base" ] || base=$(git merge-base HEAD "$sha" 2>/dev/null)
    git ls-tree -r --name-only "$sha" 2>/dev/null >> "$frozen_paths"
done
sort -u -o "$frozen_paths" "$frozen_paths"

# --- A. design.md の節に上流ID宣言が無い -------------------------------------
# 規約: `## <見出し> [REQ-<slug>-<n>, AC-<slug>-<n>]`（下流が上流を自分の本文に書く）
#
# 【凍結済みは対象外】マージ済みの design.md は write-once で guard-frozen.sh が
# Edit/Write を deny するため、宣言漏れを指摘しても構造的に直せない。ユニットが増える
# ほど積み増して、唯一重要な「テストの無いAC」のシグナルを希釈するだけになる。
# よって未凍結（＝デフォルトブランチにまだ存在しない）design.md だけを見る。
git ls-files --cached --others --exclude-standard -- 'units/*/design.md' '*/units/*/design.md' 2>/dev/null | sort -u > "$work/design_all"
comm -23 "$work/design_all" "$frozen_paths" > "$work/design_live"
frozen_design=$(( $(wc -l < "$work/design_all") - $(wc -l < "$work/design_live") ))

: > "$work/nodecl"
if [ -s "$work/design_live" ]; then
    # コードフェンス内の "## " はMarkdown見出しではないので除外する。
    # 複数ファイルを1プロセスの awk でまとめて読む（FNR==1 でフェンス状態をリセット）。
    tr '\n' '\0' < "$work/design_live" | xargs -0 awk '
        FNR == 1 { fence = 0 }
        /^```/   { fence = !fence; next }
        fence    { next }
        /^## /   { if ($0 !~ /(REQ|AC)-[a-z0-9]+-[0-9]+/) print FILENAME "\t" $0 }
    ' 2>/dev/null >> "$work/nodecl"
fi
skipped=''
[ "$frozen_design" -gt 0 ] && skipped="（凍結済み ${frozen_design} 件は変更不可のため対象外）"
if [ -s "$work/nodecl" ]; then
    echo "【注意】上流ID宣言の無い design.md の節（逆引き検索にヒットしなくなる）${skipped}:"
    awk -F'\t' '{ printf "  %s  <- %s\n", $2, $1 }' "$work/nodecl"
else
    echo "design.md の節のID宣言漏れ: なし${skipped}"
fi
echo ''

# --- B. 変更ソースファイルの implements: 宣言漏れ -----------------------------
# デフォルトブランチとの差分に含まれる「テストでもドキュメントでもない」ファイルの
# 先頭コメントに `implements:` があるか。ブランチ基点が取れないときは黙って飛ばす。
if [ -n "$base" ]; then
    { git diff --name-only "$base" 2>/dev/null
      git diff --name-only 2>/dev/null
      git ls-files --others --exclude-standard 2>/dev/null
    } | awk -v tre="$test_path_re" '
        !$0 { next }
        # ドキュメント類とテストファイルは対象外（implements: はプロダクションコード側の規約）
        /\.(md|feature|json|ya?ml|toml|txt|lock)$/ { next }
        $0 ~ tre { next }
        !seen[$0]++ { print }
    ' | sort > "$work/cand"

    # 削除済み（差分には出るが手元に無い）ファイルを外す。[ -f ] はシェル組み込みなので
    # このループはプロセスを起こさない。
    : > "$work/exist"
    while IFS= read -r f; do
        [ -f "$f" ] && printf '%s\n' "$f" >> "$work/exist"
    done < "$work/cand"

    : > "$work/noimpl"
    if [ -s "$work/exist" ]; then
        # 先頭20行（shebang・license ヘッダ・import 前のコメント帯）に implements: があるか
        tr '\n' '\0' < "$work/exist" | xargs -0 awk '
            FNR <= 20 && /implements:/ && !seen[FILENAME]++ { print FILENAME }
        ' 2>/dev/null | sort -u > "$work/has_impl"
        comm -23 "$work/exist" "$work/has_impl" > "$work/noimpl"
    fi
    if [ -s "$work/noimpl" ]; then
        echo '【注意】先頭に implements: 宣言の無い変更ソースファイル:'
        sed 's/^/  /' "$work/noimpl"
    else
        echo '変更ソースの implements: 宣言漏れ: なし'
    fi
else
    echo '変更ソースの implements: 宣言漏れ: 判定不能（ブランチ基点が取れないためスキップ）'
fi
echo ''

# --- C. supersede 済みの旧AC-IDをまだ担いでいるテスト --------------------------
# living テストは常に最新IDを担ぐ。旧IDはスナップショット内にだけ残るのが正。
git grep -I --no-color --untracked -hoE 'supersedes:.*' -- 'units/*/requirements.md' '*/units/*/requirements.md' 2>/dev/null \
    | grep -oE 'AC-[a-z0-9]+-[0-9]+' | sed 's/^AC-//' | sort -u > "$work/sup"
if [ -s "$work/sup" ]; then
    awk -F'\t' -v exfile="$work/sup" '
        FILENAME == exfile { old[$1] = 1; next }
        ($1 in old) { if (!n++) print "【注意】supersede 済みの旧AC-IDをまだ参照しているテスト（新IDへ付け替える）:"
                      printf "  AC-%s  <- %s\n", $1, $2 }
        END { if (!n) print "supersede 済み旧IDを担ぐテスト: なし" }
    ' "$work/sup" "$test_folded"
else
    echo 'supersede 済み旧IDを担ぐテスト: なし（supersedes 宣言そのものが無い）'
fi
