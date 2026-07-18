# sdd プラグイン

[SDD全体フロー](../正式ドキュメント/SDD全体フロー.md) を Claude Code 上で実行するためのプラグイン。スキル・エージェント・フックを任意のプロジェクトに展開する。

## インストール（各プロジェクトで）

Claude Code のセッション内で：

```
/plugin marketplace add c:\Users\sugan\source\repos\sdd-define-docs
/plugin install sdd@sdd-define-docs
```

（このリポジトリをGitHub等に置いた場合は `/plugin marketplace add <owner>/<repo>` でも可）

インストール後、対象プロジェクトで一度だけ：

```
/sdd:init
```

これがプロジェクトを調査し、テスト命名規約を決め、docsスケルトンを作り、CLAUDE.md にSDDルール節（`<!-- SDD:BEGIN/END -->` マーカー管理）を展開する。

## 構成とフローの対応

| フロー上の工程 | 提供物 |
|---|---|
| 導入（初回） | `/sdd:init` — CLAUDE.md・docsスケルトン展開 |
| Phase 0 | `/sdd:phase0` — イベスト/リバース → NFR → 基盤アーキ＋walking skeleton |
| 1. 要件定義 → 人間ゲート（重点） | `/sdd:req` — REQ/AC採番・.feature作成・ゲートで停止 |
| 2. 詳細設計 → 人間ゲート（軽め） | `/sdd:design` — 局所アーキ・ADR・ゲートで停止 |
| 3. 実装タスク作成（廃棄可能） | `/sdd:tasks` |
| 4. 実装 | `/sdd:implement` — 受入振る舞いを統合テストに吸収、`test_AC_xxx` 命名 |
| 5. 受入テスト | `/sdd:accept` — エビデンス凍結・tasks.md削除・PR仕上げ |
| トレーサビリティ（随時） | `/sdd:trace` ＋ `scripts/check-traceability.ps1` |
| 現在仕様書の再生成（必要時） | `/sdd:regen` |
| ゲート前セルフチェック | `sdd-gate-reviewer` エージェント（人間ゲートの代替ではない） |
| write-once の強制 | `hooks/hooks.json` ＋ `scripts/guard-frozen.ps1` — マージ済みスナップショット（docs/units・docs/adr・*.feature）への編集をブロック |

## 各プロジェクトに生まれる構造（/sdd:init 後）

```
CLAUDE.md                       ← SDDルール節（マーカー管理・再実行で更新可）
docs/
  architecture.md               ← living（唯一維持する散文）
  adr/ADR-<n>-<slug>.md         ← 不変・supersedeで追記
  units/<日付-スラッグ>/         ← 作業単位スナップショット
    requirements.md             ← REQ/AC定義（write-once）
    design.md                   ← 詳細設計（write-once）
    evidence.md                 ← 受入結果（write-once）
    tasks.md                    ← 廃棄可能（マージ前に削除）
  generated/                    ← 再生成キャッシュ（正本ではない）
<テストと同じ場所>/*.feature     ← Gherkin記法・タグのみ・step定義なし
```

## 注意

- フック/スクリプトは **Windows PowerShell 前提**。macOS/Linux で使う場合は `powershell` を `pwsh`（PowerShell 7）に読み替えて `hooks/hooks.json` を修正すること。
- フックは「デフォルトブランチに存在する＝マージ済み」をもって凍結と判定する。マージ前の同一ブランチ内では自由に手戻りできる（レビューゲート＝コミットポイントの方針どおり）。
- 方法論そのものの根拠は壁打ちドキュメント 003〜008 を参照。
