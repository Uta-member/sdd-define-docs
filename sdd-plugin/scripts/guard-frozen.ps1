# SDD PreToolUse hook: マージ済みスナップショット（write-once文書）への Edit/Write をブロックする。
# 対象: docs配下の units/ と adr/、および *.feature のうち、デフォルトブランチに既に存在するファイル。
# 判定不能な場合は常に許可（fail-open）。stdin に Claude Code のフックJSONを受け取る。

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $filePath = $payload.tool_input.file_path
    if (-not $filePath) { exit 0 }

    # git管理下の相対パスを得る（未追跡 = この作業単位で作成中 → 許可）
    $rel = & git ls-files --full-name -- "$filePath" 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $rel) { exit 0 }

    # スナップショット領域かどうか
    $isSnapshot = ($rel -match '(^|/)docs?/units/') -or
                  ($rel -match '(^|/)docs?/adr/') -or
                  ($rel -match '\.feature$')
    if (-not $isSnapshot) { exit 0 }

    # デフォルトブランチ（マージ済み履歴）に存在するか
    $frozen = $false
    foreach ($ref in @('origin/HEAD', 'origin/main', 'origin/master', 'main', 'master')) {
        & git cat-file -e "${ref}:$rel" 2>$null
        if ($LASTEXITCODE -eq 0) { $frozen = $true; break }
    }
    if (-not $frozen) { exit 0 }

    $reason = "[SDD] $rel はマージ済みのスナップショット（write-once）のため変更できません。" +
              "振る舞いを変える場合は新しい作業単位で新IDを採番し、supersedes 宣言で置き換えてください（/sdd:req）。"
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 5
    Write-Output $out
    exit 0
}
catch {
    exit 0
}
