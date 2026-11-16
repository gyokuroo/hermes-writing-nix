# 長期執筆ワークフロー

## 開始

人が目標、完了条件、対象章または scene、避ける表現を指定する。最初の対話で `progress/goal.md` に保存し、Cron job はその内容を読む。

## 一回の writer job

1. `progress/goal.md` と `progress/checkpoint.md`、直近の本文を読む。
2. 前回の未完了箇所から一 scene の設計を決める。
3. 専用 worktree の指定範囲だけを編集する。
4. 読み戻し、人物・時系列・文体・完了条件を確認する。
5. `hermes-writing-checkpoint` で変更内容、判断、次の一手を記録する。
6. `hermes-writing-commit` で進捗と本文の変更を commit する。merge や push はしない。
7. 目標が完了したと判断できる場合だけ Cron job を自分で削除し、Discord へ完了報告する。

quota、認証、矛盾、未回答の質問、作業範囲の不足がある場合は本文を広げず、checkpoint と質問を残して次回へ渡す。
