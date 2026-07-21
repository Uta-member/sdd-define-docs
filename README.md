# sdd-define-docs

SDD（仕様駆動開発）方法論の定義ドキュメントと、それを実プロジェクトに展開するための Claude Code プラグイン。

- [docs/SDD全体フロー.md](docs/SDD全体フロー.md) — 確定した方法論の全体像（1枚）
- [rationale/](rationale/) — 壁打ちドキュメント（`001`〜`013`。各方針の根拠）
- [sdd-plugin/](sdd-plugin/) — 実行用プラグイン（skills / agents / hooks / scripts）。導入方法は [sdd-plugin/README.md](sdd-plugin/README.md)

## クイックスタート（別プロジェクトへの導入）

```
/plugin marketplace add Uta-member/sdd-define-docs
/plugin install sdd@sdd-define-docs
/sdd:init
```

ローカルにクローン済みのリポジトリから入れる場合は `Uta-member/sdd-define-docs` の代わりにそのパスを指定する。詳細は [sdd-plugin/README.md](sdd-plugin/README.md) を参照。
