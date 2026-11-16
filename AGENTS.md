# AGENTS.md

このリポジトリは、Hermes Agent のNix moduleと執筆用ヘルパーを管理する。

## ルール

- 日本語で応答する。
- 秘密情報、認証トークン、原稿、実行時状態をコミットしない。
- ホスト固有の保存先・マウントポイント・ユーザーは `services.hermes-writing` の
  optionから渡し、module内に固定しない。
- 変更後は shell syntax、Nix評価、既存テストを実行する。
- コミットメッセージは Conventional Commits と絵文字を使う。

詳細な利用方法は `README.md` を参照する。
