# AGENTS.md

このリポジトリは、Hermes Agent のNix moduleと執筆用ヘルパーを管理する。

## ルール

- 日本語で応答する。
- 秘密情報、認証トークン、原稿、実行時状態をコミットしない。
- ホスト固有の保存先・マウントポイント・ユーザーは `services.hermes-writing` の
  optionから渡し、module内に固定しない。
- 変更後は shell syntax、Nix評価、既存テストを実行する。
- HermesのNix packageを変更した場合は、Linux CIで `hermes-agent` packageの実ビルドと
  `hermes --version`、同梱node/pythonの起動確認まで行う。
- Hermes package は upstream Flake の nixpkgs を使い、module とヘルパーはホスト側の
  `pkgs` を使う。upstream lockfile の nixpkgs を更新するときは、固定出力 package の
  再現性と host module 評価を別々に確認する。
- コミットメッセージは Conventional Commits と絵文字を使う。

詳細な利用方法は `README.md` を参照する。
