# sdd プラグイン

[SDD全体フロー](../docs/SDD全体フロー.md) を Claude Code 上で実行するためのプラグイン。スキル・エージェント・フックを任意のプロジェクトに展開する。

## 前提：シェル（`bash`）と `git`

フック／スクリプトは **POSIX sh + git のみに依存**する（`jq` は在れば使うが必須ではない）。write-once ガード（`hooks/hooks.json`）は `bash` でスクリプトを起動するため、**`bash` が PATH から到達できること**が前提。

- **Linux / macOS / DevContainer（Linuxベース）**：`sh`/`bash` は標準で存在。通常は何もしなくてよい。
- **Windows**：Git for Windows 同梱の `bash.exe`（`<Git>\bin\bash.exe` か `<Git>\usr\bin\bash.exe`）が PATH に必要。`git` は通るのに `bash` が無い場合、`<Git>\cmd` だけを PATH に通し `<Git>\bin` を通していないのが典型。`bash --version` が通れば OK。

> **重要**：`bash` が PATH に無いと、フック起動が失敗して **write-once ガードと trace ガードが黙って無効になる**（作業は進むがマージ済みスナップショットが保護されず、回帰網の穴も検知されない）。`/sdd:init` は導入時に bash 到達性をプローブし、無効なら大声で警告する。

## 設計方針：強調語ではなく仕組みで縛る

**交渉不可なのは2つだけ**——(1) 要件定義の人間承認を得るまで下流に進まない、(2) 受入レベルの振る舞いを living 統合テストに吸収する。文書中で `【不変条件】` と記した箇所がこれにあたる。

それ以外の手順は通常の指示として書く。すべてを「必須」「絶対」と書くと本当に守るべき2つが埋没するため、強調語は意図的に絞っている。そのぶん、守らせたいものは**プロンプトの強さではなくフックで担保する**：

| 守るもの | 担保する仕組み | ブロック |
|---|---|---|
| マージ済みスナップショットの write-once | PreToolUse フック `scripts/guard-frozen.sh` | する |
| 回帰網の穴（テストの無いAC）の検知 | Stop フック `scripts/trace-guard.sh` | しない（警告のみ） |
| tasks.md の陳腐化（セッション境界での情報消失）の検知 | Stop フック `scripts/tasks-log-guard.sh` | しない（警告のみ） |

## セッション境界とトークン消費

SDDのスナップショット（requirements.md / design.md / .feature / tasks.md）は**そのままセッション間の引き継ぎ媒体**である。会話履歴からしか復元できない情報を残さない設計なので、人間ゲートはそのままコンテキストを捨ててよい地点になる。

機能サイクル1本を**3セッション**に分けて回すことを推奨する：

| セッション | 工程 | 切る理由 |
|---|---|---|
| 1 | `/sdd:req` →（人間ゲート・重点） | 承認済み要件は requirements.md と .feature に凍結される |
| 2 | `/sdd:design` →（人間ゲート・軽め）→ `/sdd:tasks` | 設計文脈は tasks 作成まで使うが、implement には要らない |
| 3 | `/sdd:implement` →（テスト妥当性ゲート）→ **切る** → `/sdd:accept` | implement が最も重い工程。上流の対話ログを背負って入らない |

長いセッションはプロンプトキャッシュが効いていても高くつく（コンテキスト長に比例して毎リクエスト課金される）。分割はSDDの規律を一切緩めずにこれを避けられる、いちばん安い手段である。

コスト面のもう2つの方針：

- **`/sdd:trace` はAI探索をしない。** チェック6項目は全て `scripts/check-traceability.sh` に機械化してある。スキルはスクリプトを走らせて出力を報告するだけ（以前は「AIレビュー（全文検索ベース）」としてメインセッションで無制限に Grep させており、トークン消費の最大要因だった）。
- **エージェントのモデルは用途で分ける。** `sdd-gate-reviewer` は `model: sonnet`（スナップショットの構造チェックが主）。`sdd-test-reviewer` は `model: opus` を明示固定（curve-fitting の検出は不変条件2を実際に検証する唯一の場であり、ここは削らない）。

## インストール（各プロジェクトで）

Claude Code のセッション内で（GitHub 経由が基本）：

```
/plugin marketplace add Uta-member/sdd-define-docs
/plugin install sdd@sdd-define-docs
```

ローカルにクローン済みのリポジトリから入れる場合は、`Uta-member/sdd-define-docs` の代わりにそのパスを指定する（環境依存の絶対パスをそのまま貼らないこと）：

```
/plugin marketplace add <path/to/sdd-define-docs>
/plugin install sdd@sdd-define-docs
```

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
| 4b. テスト妥当性ゲート → 人間ゲート（軽め・ブロック） | `sdd-test-reviewer` エージェント — 実テストと.featureを突き合わせ、空虚なテスト・期待値の実装由来（curve-fitting）・網羅の穴を検出。accept はこの通過が前提 |
| 5. 受入テスト | `/sdd:accept` — エビデンス凍結・tasks.md削除・PR仕上げ |
| トレーサビリティ（随時） | `/sdd:trace` ＋ `scripts/check-traceability.sh` |
| 現在仕様書の再生成（必要時） | `/sdd:regen` |
| ゲート前セルフチェック（要件/設計） | `sdd-gate-reviewer` エージェント（人間ゲートの代替ではない） |
| ゲート前セルフチェック（テスト妥当性） | `sdd-test-reviewer` エージェント（実テストを読む・実行しない。人間ゲートの代替ではない） |
| write-once の強制 | `hooks/hooks.json` ＋ `scripts/guard-frozen.sh` — マージ済みスナップショット（docs/units・docs/adr・*.feature）への編集をブロック |
| trace 実行忘れの検知 | `hooks/hooks.json` ＋ `scripts/trace-guard.sh` — Stop フック。実装済みの作業単位で「テストの無いAC」が残っていたら警告（ブロックしない）。毎ターン走るので `check-traceability.sh --missing-only` の軽量経路だけを使う（発火時 約2秒／非発火時 約1秒） |
| tasks.md の陳腐化の検知 | `hooks/hooks.json` ＋ `scripts/tasks-log-guard.sh` — Stop フック。ブランチ差分のコード/テストが tasks.md より新しければ警告（ブロックしない）。`/clear` を挟んでも進捗・見つかった問題・次の一手が残る状態を保つのが狙い |

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

- フック/スクリプトは **POSIX sh + git のみに依存**し、単一実装が Windows / macOS / Linux / DevContainer で動く。前提となる `bash` の到達性は冒頭「前提：シェル」節を参照（Windows では Git 同梱の `bash` が使われる）。
- フックは「デフォルトブランチに存在する＝マージ済み」をもって凍結と判定する。マージ前の同一ブランチ内では自由に手戻りできる（レビューゲート＝コミットポイントの方針どおり）。
- 方法論そのものの根拠は壁打ちドキュメント 003〜008 を参照。
