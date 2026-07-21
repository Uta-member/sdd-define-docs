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
| pytest | `def test_AC_checkout_3_card_payment_succeeds():` |
| xUnit (.NET) | メソッド名 `AC_checkout_3_カード決済が成功する` または `[Fact(DisplayName = "AC-checkout-3 ...")]` |
| Jest / Vitest | `it("AC-checkout-3 カード決済が成功する", ...)` |
| JUnit 5 | `@DisplayName("AC-checkout-3 ...")` かメソッド名 `AC_checkout_3_...` |
| Go testing | `func TestAC_checkout_3_CardPaymentSucceeds(t *testing.T)` |

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

### 5. bash 到達性のプローブ（write-once ガードの前提確認）
write-once ガード（`hooks/hooks.json`）は `bash` でスクリプトを起動する。bash が PATH に無いとフック起動自体が失敗し、**ガードが黙って無効になる**（スクリプト内の fail-open はそのさらに内側の話で、ここには到達しない）。導入時に一度だけ、フックが打つのと同じ `bash` を実際に起動して確認する。

- `bash -c "exit 0"` を実行する（＝フックの起動経路の到達性を確認）。
- **成功**：ガードは有効。何も追加で言わなくてよい。
- **失敗／bash が見つからない**：セットアップは**中断しない**（docsスケルトン・CLAUDE.md展開はそのまま完了させる）。ただし報告で**大声で**次を伝える：
  - 「**write-once ガードは現在無効です。bash を PATH に通すまで有効化されません。**」
  - 環境別の対処：
    - Linux / macOS / DevContainer（Linuxベース）：通常は `sh`/`bash` があるので、この失敗はまれ。コンテナが極端に最小構成なら bash を入れる。
    - Windows：Git for Windows 同梱の `bash.exe`（`<Git>\bin\bash.exe` か `<Git>\usr\bin\bash.exe`）を PATH に通す。`git` が通って `bash` が無いのは「`<Git>\cmd` だけ通し `<Git>\bin` を通していない」典型パターン。`bash --version` が通れば解消。
  - 背景根拠：黙って消える安全網は無い安全網より悪い（[[013_クロスプラットフォームのシェル依存]] / [[004_トレーサビリティ]]「黙って嘘をつかない」）。

### 6. 報告
- 決定した規約（テスト命名・docsパス）と作成/更新したファイルの一覧。
- 手順5の bash プローブ結果（無効なら対処を再掲）。
- 次のステップ案内：
  - Phase 0（NFR・基盤アーキ・walking skeleton）未実施 → `/sdd:phase0`
  - 実施済み or 既存プロジェクト → `/sdd:req` で最初の作業単位を開始
  - レガシー（テスト網なし）の場合：全面作り直しは不要。触る箇所から characterization test で網を育てる方針（`/sdd:req` 内で扱う）を伝える。
