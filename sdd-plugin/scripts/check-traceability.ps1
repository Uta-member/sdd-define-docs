# SDD 発見的チェック: .feature の @AC タグとテストコードの AC 参照の乖離を報告する。
# ブロックしない補助ツール。git管理下のファイルのみを対象にする。

$ErrorActionPreference = 'SilentlyContinue'

$tracked = & git ls-files
if ($LASTEXITCODE -ne 0 -or -not $tracked) {
    Write-Output 'gitリポジトリではないか、追跡ファイルがありません。'
    exit 0
}

$featureAcs = @{}   # AC番号 -> .featureファイル一覧
$testAcs    = @{}   # AC番号 -> テストファイル一覧

foreach ($f in $tracked) {
    if (-not (Test-Path -LiteralPath $f)) { continue }

    if ($f -match '\.feature$') {
        $matches2 = Select-String -LiteralPath $f -Pattern '@AC-(\d+)' -AllMatches
        foreach ($m in $matches2) {
            foreach ($g in $m.Matches) {
                $id = $g.Groups[1].Value
                if (-not $featureAcs.ContainsKey($id)) { $featureAcs[$id] = @() }
                if ($featureAcs[$id] -notcontains $f) { $featureAcs[$id] += $f }
            }
        }
    }
    elseif ($f -match '(^|/)(tests?|spec|__tests__)(/|\.)' -or $f -match '(test|spec|Tests?)\.[a-z]+$' -or $f -match '(^|/)test_[^/]+$') {
        $matches2 = Select-String -LiteralPath $f -Pattern 'AC[-_](\d+)' -AllMatches
        foreach ($m in $matches2) {
            foreach ($g in $m.Matches) {
                $id = $g.Groups[1].Value
                if (-not $testAcs.ContainsKey($id)) { $testAcs[$id] = @() }
                if ($testAcs[$id] -notcontains $f) { $testAcs[$id] += $f }
            }
        }
    }
}

Write-Output "=== SDD トレーサビリティチェック ==="
Write-Output (".feature 内のAC: {0}件 / テストが参照するAC: {1}件" -f $featureAcs.Count, $testAcs.Count)
Write-Output ''

$missing = $featureAcs.Keys | Where-Object { -not $testAcs.ContainsKey($_) } | Sort-Object { [int]$_ }
if ($missing) {
    Write-Output "【重大】テストの無いAC（回帰の穴の候補。統合テストへの吸収が絶対条件）:"
    foreach ($id in $missing) {
        Write-Output ("  AC-{0}  <- {1}" -f $id, ($featureAcs[$id] -join ', '))
    }
}
else {
    Write-Output "テストの無いAC: なし"
}
Write-Output ''

$orphan = $testAcs.Keys | Where-Object { -not $featureAcs.ContainsKey($_) } | Sort-Object { [int]$_ }
if ($orphan) {
    Write-Output "【注意】.feature に存在しないACを参照するテスト（タグ漏れ or 廃止済みIDの残骸）:"
    foreach ($id in $orphan) {
        Write-Output ("  AC-{0}  <- {1}" -f $id, ($testAcs[$id] -join ', '))
    }
}
else {
    Write-Output ".feature に無いACを指すテスト: なし"
}
