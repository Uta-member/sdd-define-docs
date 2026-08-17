#!/usr/bin/env sh
# SDD AC索引: 現在有効なAC（＋回帰網の穴）を「1行1件」で一覧する。
# 影響範囲調査の第1段。AIが .feature 本体を読み回らずに当たりを付けるための索引を作る。
# 依存は git と POSIX 標準コマンドのみ。git管理下 + 未トラックの新規ファイルを対象にする。
#
# 使い方:
#   list-acs.sh                      現在有効なAC（live / NOTEST）を一覧する
#   list-acs.sh --path <部分文字列>   .feature のパスで絞る（例: --path src/checkout）
#   list-acs.sh --grep <正規表現>     AC-ID とシナリオ名で絞る（大文字小文字を無視）
#   list-acs.sh --all                supersede 済み（dead）も状態列付きで表示する
#   list-acs.sh --tests              各ACを担ぐテストファイルも表示する（既定は非表示）
#   list-acs.sh --full               件数が多くてもAC行を全部出す（既定は名前空間サマリに畳む）
#
# 状態列:
#   live    テスト網が担いでいる ＝ 現在有効なAC（→ 04 トレーサビリティ「現在有効なACの導出」）
#   NOTEST  .feature にあるがテストが参照していない ＝ 回帰の穴の候補 or 実装前
#   dead    supersedes: 宣言で置き換えられた旧AC。既定では表示しない
#
# 【これは索引であって仕様書ではない】出力はキャッシュであり正本ではない（正本は .feature と
# テストコード）。索引で候補を絞ってから、必要な数件だけ .feature を読むこと。
# 全ACを予防的に読み込む運用はしない（→ 16 影響範囲調査のコスト設計）。
#
# 【対象は機能AC（AC-<slug>-<n>）のみ】NFR-<slug>-<n> は回帰網外なので意図的に対象外
# （check-traceability.sh と同じ方針。→ 11 NFR検証ライフサイクル）。
#
# 【性能：プロセス数がすべて】Windows のプロセス生成は1回 80〜150ms かかる。走査は
# git grep 3発・集計は awk にまとめる。「ファイルごと」「ACごと」にコマンドを起こさないこと。

# 絞り込み無しでこの件数を超えたら、AC行の代わりに名前空間（slug）別サマリを出す。
# 索引がそれ自体で数千トークンに育っては本末転倒なので、「まず地図、次に詳細」に畳む。
SUMMARY_THRESHOLD=120

path_filter=''
grep_filter=''
show_dead=0
show_tests=0
show_full=0

while [ $# -gt 0 ]; do
    case "$1" in
        --path)  path_filter="$2"; shift 2 || exit 1 ;;
        --grep)  grep_filter="$2"; shift 2 || exit 1 ;;
        --all)   show_dead=1; shift ;;
        --tests) show_tests=1; shift ;;
        --full)  show_full=1; shift ;;
        -h|--help)
            # 先頭コメントブロックをそのまま使う（行番号を決め打ちすると編集で壊れる）
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0 ;;
        *)
            echo "不明な引数: $1（--help で使い方）" >&2
            exit 1 ;;
    esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
    echo 'gitリポジトリではありません。'
    exit 0
fi
cd "$root" 2>/dev/null || exit 0

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# --- 1. .feature からタグ→シナリオ名を収集 ------------------------------------
# タグ行・Scenario行・Feature行だけを git grep で抜き、awk の状態機械で対応づける。
# タグ行とシナリオ行の間の空行・コメントは git grep の時点で落ちているため、
# 行番号の連続性は前提にしない（Gherkin はタグとシナリオの間に空行を許す）。
# Feature 行でタグ保留をクリアするのは、ファイル冒頭の Feature レベルタグが
# 先頭シナリオへ誤って紐づくのを防ぐため。
# 日本語 Gherkin（機能:／シナリオ:）も拾う。
git grep -n -I --no-color --untracked -E \
    '@AC-[a-z0-9]+-[0-9]+|^[[:space:]]*(Feature|Scenario Outline|Scenario Template|Scenario|Example|機能|シナリオアウトライン|シナリオテンプレート|シナリオ|例)[[:space:]]*:' \
    -- '*.feature' 2>/dev/null | awk '
    function flush(   i) {           # 保留中のタグをシナリオ名なしで吐く
        for (i = 1; i <= np; i++) print pend[i] "\t" "\t" pfile ":" pline[i]
        np = 0
    }
    {
        if (!match($0, /:[0-9]+:/)) next
        path = substr($0, 1, RSTART - 1)
        lineno = substr($0, RSTART + 1, RLENGTH - 2)
        body = substr($0, RSTART + RLENGTH)

        if (path != pfile) { flush(); pfile = path }

        if (body ~ /^[[:space:]]*(Feature|機能)[[:space:]]*:/) { flush(); next }

        if (body ~ /^[[:space:]]*(Scenario Outline|Scenario Template|Scenario|Example|シナリオアウトライン|シナリオテンプレート|シナリオ|例)[[:space:]]*:/) {
            title = body
            sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", title)
            gsub(/[[:space:]]+$/, "", title)
            for (i = 1; i <= np; i++) print pend[i] "\t" title "\t" pfile ":" pline[i]
            np = 0
            next
        }

        # タグ行：1行に複数の @AC タグがありうるので全部拾う
        rest = body
        while (match(rest, /@AC-[a-z0-9]+-[0-9]+/)) {
            id = substr(rest, RSTART + 4, RLENGTH - 4)   # "@AC-" の4文字を落とす
            np++; pend[np] = id; pline[np] = lineno
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    END { flush() }
' > "$work/ac"

# --- 2. テスト網が参照しているAC-IDを収集 --------------------------------------
# 判定条件は check-traceability.sh と同一（テストらしきパス × AC-<slug>-<n> / AC_<slug>_<n>）。
test_path_re='(^|/)(tests?|spec|__tests__)(/|\\.)|(test|spec|Tests?)\\.[a-z]+$|(^|/)test_[^/]+$'
git grep -I --no-color --untracked -oE 'AC[-_][a-z0-9]+[-_][0-9]+' 2>/dev/null | awk \
    -v tre="$test_path_re" '
    {
        i = length($0)
        while (i > 0 && substr($0, i, 1) != ":") i--
        if (i == 0) next
        path = substr($0, 1, i - 1)
        if (path !~ tre) next
        id = substr($0, i + 4)        # "AC-" / "AC_" の3文字を落とす
        gsub(/_/, "-", id)
        print id "\t" path
    }' | sort -u > "$work/tests"

# --- 3. supersede 済みの旧AC-IDを収集 ------------------------------------------
git grep -I --no-color --untracked -hoE 'supersedes:.*' \
    -- 'units/*/requirements.md' '*/units/*/requirements.md' 2>/dev/null \
    | grep -oE 'AC-[a-z0-9]+-[0-9]+' | sed 's/^AC-//' | sort -u > "$work/dead"

# --- 4. 突き合わせて出力 -------------------------------------------------------
# 並びは slug昇順・番号昇順（自然順）。素の辞書順だと AC-mod7-10 が AC-mod7-2 より前に来る。
# ソートキーをゼロ埋めで前置し、比較後に落とす（区切りの "|" は slug に現れない文字）。
sort -u "$work/ac" | awk -F'\t' '
    { id = $1
      num = id; sub(/^.*-/, "", num)
      slug = id; sub(/-[0-9]+$/, "", slug)
      printf "%s|%06d\t%s\n", slug, num, $0 }' \
    | sort -k1,1 | cut -f2- > "$work/ac_sorted"

awk -F'\t' \
    -v deadfile="$work/dead" -v testfile="$work/tests" \
    -v pathf="$path_filter" -v grepf="$grep_filter" \
    -v showdead="$show_dead" -v showtests="$show_tests" \
    -v showfull="$show_full" -v threshold="$SUMMARY_THRESHOLD" '
    FILENAME == deadfile { dead[$0] = 1; next }
    FILENAME == testfile {
        n = split($0, a, "\t")
        tested[a[1]] = 1
        tfiles[a[1]] = (a[1] in tfiles) ? tfiles[a[1]] ", " a[2] : a[2]
        tcount[a[1]]++
        next
    }
    {
        id = $1; title = $2; loc = $3
        if (id == "") next
        total++

        state = (id in dead) ? "dead" : ((id in tested) ? "live" : "NOTEST")
        cnt[state]++
        if (state == "dead" && !showdead) next

        if (pathf != "" && index(loc, pathf) == 0) next
        if (grepf != "") {
            hay = tolower("AC-" id " " title)
            if (hay !~ tolower(grepf)) next
        }

        shown++
        ids[shown] = id; titles[shown] = title; locs[shown] = loc; states[shown] = state
        w = length(id) + 3
        if (w > idw) idw = w
    }
    END {
        printf "=== SDD AC索引 === live %d / NOTEST %d / dead %d（母集団: .feature 定義の機能AC %d件）\n",
               cnt["live"], cnt["NOTEST"], cnt["dead"], total
        if (!showdead && cnt["dead"] > 0) print "  ※ dead（supersede済み）は非表示。--all で表示"
        if (pathf != "" || grepf != "")
            printf "  絞り込み: %s%s%s → %d件\n", (pathf != "" ? "--path " pathf : ""),
                   (pathf != "" && grepf != "" ? " / " : ""), (grepf != "" ? "--grep " grepf : ""), shown
        print ""
        if (!shown) {
            # 「絞り込んだ結果ゼロ」と「そもそもACが無い」を区別して伝える
            print (total == 0 ? ".feature に定義されたACがまだありません（Phase 0 直後や未導入のリポジトリ）。" \
                              : "該当するACはありません。条件を緩めるか、絞り込み無しで全体を見る。")
            exit
        }

        # 件数が多いときは名前空間（slug＝作業単位）別のサマリに畳んで、絞り込みを促す。
        # 索引を読ませること自体がコストなので、まず地図を出して当たりを付けさせる。
        if (!showfull && pathf == "" && grepf == "" && shown > threshold) {
            for (i = 1; i <= shown; i++) {
                s = ids[i]; sub(/-[0-9]+$/, "", s)
                if (!(s in seenslug)) { seenslug[s] = 1; order[++sn] = s }
                sstate[s "|" states[i]]++
                f = locs[i]; sub(/:[0-9]+$/, "", f)
                if (!((s "|" f) in seenfile)) { seenfile[s "|" f] = 1; nf[s]++
                    if (nf[s] <= 2) sfile[s] = (s in sfile) ? sfile[s] ", " f : f }
                if (length(s) + 3 > sw) sw = length(s) + 3
            }
            printf "%d件は一覧に出すには多いので、名前空間（slug＝作業単位）別のサマリに畳んだ。\n", shown
            print "--path / --grep で絞ってから読むこと（例: --path src/checkout、--grep 決済）。--full で全件表示。"
            print ""
            if (sw < 14) sw = 14
            printf "%-*s %6s %7s%s  定義元\n", sw, "slug", "live", "NOTEST",
                   (showdead ? "   dead" : "")
            for (i = 1; i <= sn; i++) {
                s = order[i]
                printf "%-*s %6d %7d%s  %s%s\n", sw, s, sstate[s "|live"], sstate[s "|NOTEST"],
                       (showdead ? sprintf("%7d", sstate[s "|dead"]) : ""),
                       sfile[s], (nf[s] > 2 ? sprintf(" 他%d件", nf[s] - 2) : "")
            }
            print ""
            print "※ この索引はキャッシュであり正本ではない（正本は .feature とテストコード）。"
            exit
        }

        # タイトルは全角混じりで桁が揃わないのでパディングせず "<-" 区切りにする
        # （check-traceability.sh の報告形式に合わせる）。半角のID列だけ揃える。
        if (idw < 12) idw = 12
        for (i = 1; i <= shown; i++) {
            printf "%-6s %-*s %s  <- %s\n", states[i], idw, "AC-" ids[i],
                   (titles[i] == "" ? "(シナリオ名なし)" : titles[i]), locs[i]
            if (showtests && (ids[i] in tfiles))
                printf "%*s tests: %s\n", 6 + idw, "", tfiles[ids[i]]
        }
        print ""
        print "※ この索引はキャッシュであり正本ではない（正本は .feature とテストコード）。"
        print "  候補を絞ってから、必要な数件だけ .feature を読むこと。"
        if (cnt["NOTEST"] > 0 && !pathf && !grepf)
            print "※ NOTEST は「回帰の穴の候補 or 実装前」。詳細は /sdd:trace で判定する。"
    }
' "$work/dead" "$work/tests" "$work/ac_sorted"
