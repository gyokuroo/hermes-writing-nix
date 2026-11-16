# Hermes Writing Nix

Nous Research Hermes Agent v0.23.1 を、Home Manager の外部モジュールとして
NixOS の小説執筆環境へ組み込むための Flake。

## 使い方

ホスト側の Flake input として追加する。

```nix
inputs.hermes-writing.url = "github:gyokuroo/hermes-writing-nix";
inputs.hermes-writing.inputs.nixpkgs.follows = "nixpkgs";
inputs.hermes-writing.inputs.home-manager.follows = "home-manager";
```

Home Manager の `imports` に明示的に追加し、保存先などのホスト固有値を渡す。

```nix
imports = [ inputs.hermes-writing.homeManagerModules.default ];

services.hermes-writing = {
  enable = true;
  hermesHome = "/mnt/sda1/private/writing/hermes";
  workingDirectory = "/mnt/sda1/private/writing/worktrees/hermes";
  repository = "/mnt/sda1/private/writing/novel";
  storageMount = "/mnt/sda1";
  environmentFiles = [ "/mnt/sda1/private/writing/hermes.env" ];
  github.home = "/mnt/sda1/private/writing/hermes/github";
  github.user = "gyokuroo";
  github.authorEmail = "357243118+gyokuroo@users.noreply.github.com";
};
```

GitHub の初回認証は、対象ホスト上で専用ラッパーを使って行う。
認証情報、原稿、Hermes の実行状態はこのリポジトリへ保存しない。

## 主な公開インターフェース

- `homeManagerModules.default`
- `services.hermes-writing.*`
- `packages.<system>.hermes-writing-backup`

既定のプロバイダは `openai-codex`、モデルは `gpt-6-sol`。GitHubユーザーと
コミット作者メールはmodule optionから変更できる。

Hermes本体は upstream v0.23.1 の Flake が固定する nixpkgs で評価する。
これにより、ホスト側の nixpkgs pin に含まれる `fetchPnpmDeps` やビルドツールの
差異が、upstream lockfile の固定出力 package に影響しない。Home Manager の
module評価と執筆用ヘルパーはホスト側の `pkgs` を使う。Hermes upstream を更新する
ときは、upstream lockfile の nixpkgs 変更も確認する。
