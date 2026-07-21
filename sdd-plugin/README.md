# sdd プラグイン

[SDD全体フロー](../正式ドキュメント/SDD全体フロー.md) を Claude Code 上で実行するためのプラグイン。スキル・エージェント・フックを任意のプロジェクトに展開する。

## インストール（各プロジェクトで）

Claude Code のセッション内で：

```
/plugin marketplace add c:\Users\sugan\source\repos\sdd-define-docs
/plugin install sdd@sdd-define-docs
```

（このリポジトリをGitHub等に置いた場合は `/plugin marketplace add <owner>/<repo>` でも可）

### DevContainer / WSL の場合

コンテナ内からは Windows 側のローカルパスが見えないので、**GitHub 経由で入れる**：

```
/plugin marketplace add Uta-member/sdd-define-docs
/plugin install sdd@sdd-define-docs
```

コンテナを作り直すたびに手で打ちたくない場合は、対象プロジェクトの `.claude/settings.json` に書いておくと起動時に自動で解決される：

```json
{
  "extraKnownMarketplaces": {
    "sdd-define-docs": {
      "source": { "source": "github", "repo": "Uta-member/sdd-define-docs" }
    }
  },
  "enabledPlugins": { "sdd@sdd-define-docs": true }
}
```

コンテナ側の要件は `git` と `bash` のみ（`jq` があれば使うが必須ではない）。`.devcontainer/devcontainer.json` で Claude Code 自体を入れている場合は、その後段でこの設定が効く。

プラグイン本体を編集しながら使いたい場合は、リポジトリをコンテナにマウントしてローカルパスで `marketplace add` してもよい：

```jsonc
// .devcontainer/devcontainer.json
"mounts": [
  "source=${localWorkspaceFolder}/../sdd-define-docs,target=/workspaces/sdd-define-docs,type=bind"
]
```

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
| 4b. テスト妥当性ゲート → 人間ゲート（軽め・ブロック） | `sdd-test-reviewer` エージェント — 実テストと.featureを突き合わせ、空虚なテスト・期待値の実装由来（curve-fitting）・網羅の穴を検出。生命線なので通過必須 |
| 5. 受入テスト | `/sdd:accept` — エビデンス凍結・tasks.md削除・PR仕上げ |
| トレーサビリティ（随時） | `/sdd:trace` ＋ `scripts/check-traceability.sh` |
| 現在仕様書の再生成（必要時） | `/sdd:regen` |
| ゲート前セルフチェック（要件/設計） | `sdd-gate-reviewer` エージェント（人間ゲートの代替ではない） |
| ゲート前セルフチェック（テスト妥当性） | `sdd-test-reviewer` エージェント（実テストを読む・実行しない。人間ゲートの代替ではない） |
| write-once の強制 | `hooks/hooks.json` ＋ `scripts/guard-frozen.sh` — マージ済みスナップショット（docs/units・docs/adr・*.feature）への編集をブロック |

## 各プロジェクトに生まれる構造（/sdd:init 後）

```
CLAUDE.md                       ← SDDルール節（マーカー管理・再実行で更新可）
docs/
  architecture.md               ← living（唯一維持する散文）
  adr/ADR-<slug>-<n>-<title>.md ← 不変・supersedeで追記（slugで名前空間化）
  units/<スラッグ>/              ← 作業単位スナップショット（開始日は requirements.md 冒頭に記録）
    requirements.md             ← REQ/AC定義（write-once）
    design.md                   ← 詳細設計（write-once）
    evidence.md                 ← 受入結果（write-once）
    tasks.md                    ← 廃棄可能（マージ前に削除）
  generated/                    ← 再生成キャッシュ（正本ではない）
<テストと同じ場所>/*.feature     ← Gherkin記法・タグのみ・step定義なし
```

## 注意

- フック/スクリプトは **POSIX sh + git のみに依存**。Windows / macOS / Linux / DevContainer で同じものが動く（Windows では Git 同梱の `bash` が使われる）。
- フックは「デフォルトブランチに存在する＝マージ済み」をもって凍結と判定する。マージ前の同一ブランチ内では自由に手戻りできる（レビューゲート＝コミットポイントの方針どおり）。
- 方法論そのものの根拠は壁打ちドキュメント 003〜008 を参照。
