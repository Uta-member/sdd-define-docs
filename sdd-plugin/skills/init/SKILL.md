---
name: init
description: SDD（仕様駆動開発）をこのプロジェクトに導入する。プロジェクトの言語・テストフレームワークを調査して規約を確定し、docsスケルトンを作成し、CLAUDE.mdにSDDルール節を展開する。「SDDを導入」「SDDセットアップ」「仕様駆動開発を始める」で使用。
---

# /sdd:init — SDDをプロジェクトに展開する

対象プロジェクトのルートで実行する。既存ファイルは上書きせず、マーカーによるマージで展開する。

## 手順

### 1. プロジェクト調査
- 言語・テストフレームワーク・ディレクトリ構成・既存の CLAUDE.md / docs の有無を調べる。
- 既にテスト網があるか（SDD生まれ相当）／無いか（レガシー）を判定する。

### 2. プロジェクト固有規約の決定
テストフレームワークに応じて `{TEST_NAMING}` を具体化する。例：

| フレームワーク | 規約 |
|---|---|
| pytest | `def test_AC_012_card_payment_succeeds():` |
| xUnit (.NET) | メソッド名 `AC_012_カード決済が成功する` または `[Fact(DisplayName = "AC-012 ...")]` |
| Jest / Vitest | `it("AC-012 カード決済が成功する", ...)` |
| JUnit 5 | `@DisplayName("AC-012 ...")` かメソッド名 `AC_012_...` |
| Go testing | `func TestAC012_CardPaymentSucceeds(t *testing.T)` |

`{DOCS_DIR}` は原則 `docs`。既存の文書ディレクトリ規約があればそちらに合わせる。

### 3. スケルトン作成
```
{DOCS_DIR}/
  architecture.md      ← living。Phase 0未実施ならプレースホルダ（「/sdd:phase0 で作成」と記載）
  adr/                 ← .gitkeep
  units/               ← .gitkeep
```

### 4. CLAUDE.md への展開
- テンプレート：このSKILL.mdから見て `../../templates/claude-md-sdd.md`（プラグイン同梱）。
- `{TEST_NAMING}` `{DOCS_DIR}` を手順2の決定値で置換する。
- 対象プロジェクトの CLAUDE.md に `<!-- SDD:BEGIN -->` 〜 `<!-- SDD:END -->` マーカーが**ある場合**：マーカー間だけを置き換える（再実行＝更新）。
- **無い場合**：CLAUDE.md 末尾に追記（CLAUDE.md自体が無ければ新規作成）。
- マーカー外の既存記述には一切触れない。

### 5. 報告
- 決定した規約（テスト命名・docsパス）と作成/更新したファイルの一覧。
- 次のステップ案内：
  - Phase 0（NFR・基盤アーキ・walking skeleton）未実施 → `/sdd:phase0`
  - 実施済み or 既存プロジェクト → `/sdd:req` で最初の作業単位を開始
  - レガシー（テスト網なし）の場合：全面作り直しは不要。触る箇所から characterization test で網を育てる方針（`/sdd:req` 内で扱う）を伝える。
