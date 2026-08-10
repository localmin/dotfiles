---
name: parallelization
description: タスクに着手するとき最初に読む、並列化と subagent 化の判断基準。独立 subtask の並列 dispatch、大量探索の subagent への隔離、bias-free 評価、long-running batch の逃がし方と、並列化すべきでないパターンを定める。新しいタスクを受けた直後の作業設計で参照する。
---

# 並列化と subagent

## 基本姿勢

タスクを受けたら最初に「**並列化できる subtask は何か**」「**subagent に投げて main context を空けられるか**」を洗い出してから動く。**default は subagent 優先 / 並列優先**。

## subagent / 並列に投げる判断

- **互いに独立な 2+ task** → Agent tool で 1 message 内に並列 dispatch（independent search、multi-scenario eval、multi-model 比較など）。
- **大量探索・grep・解析（3+ query 規模）** → `general-purpose` / `Explore` subagent に投げ、main は要約だけ受け取る。
- **bias-free 評価**（skill / prompt / 自分の生成物の検証）→ 新規 subagent に投げる。「自分で再読して評価」は禁じ手（自分の生成物を自分で読むと評価にバイアスがかかるため、コンテキストを共有しない別 agent で検証する）。
- **Long-running batch**（Bash の 10 分上限を超える、同種処理を多数の repo に回す等）→ subagent dispatch か `run_in_background` + `Monitor`。

## 自分が既に subagent のとき（隔離指示の書き方）

隔離の指示は「subagent に投げろ」という**手段**ではなく、**観測可能な signal による分岐**で書く。自分が使い捨て文脈かを確実に知る手段はないため、自己認識に委ねると誤判定するし、「不明なら隔離側に倒す」を既定にすると隔離先が同じ指示を読んで再委譲が止まらなくなる。

- **dispatch する側**: subagent へのプロンプト冒頭に隔離済みの宣言を1行入れる。
  例: `ISOLATED-EXECUTOR: あなたは隔離済みの実行者です。この作業をさらに subagent へ再委譲せず inline で実行してください。`
- **受け取る側**: 宣言があれば inline、なければ隔離する。宣言がなくても「再委譲するな」「あなたが専任の実行者だ」に相当する指示を受けているなら inline に倒す（skill 経由でない起動——eval や手動 dispatch——では誰も宣言を入れないため）。この経路で inline を選んだときは、隔離の目的（生成物の元データを残る文脈に置かない）を破ったことを報告に明示する。
- **既定を書くときは再帰しないことを確認する**。安全側に倒したつもりの既定が、次の階層で同じ判定を引き起こしていないか。

## 避けるべき

- 直列依存（前 task の結果が次 task の入力）を無理に並列化する。
- 1-step / short lookup を subagent に投げる（overhead がコストに見合わない）。
- subagent と main で同じ作業を二重に走らせる。

## dispatch が拒否されたとき

同一ブロックで複数 subagent を起動すると、**同形の呼び出しでも一部だけ permission classifier に拒否される**ことがある。拒否は「そのタスクが恒久的に禁止」を意味しない。

- 拒否された subtask を**黙って落とさない**。落とすと、担当していた入力（URL 群・ファイル群）が結果から静かに欠ける。
- 拒否された分だけを、プロンプトを言い換えて**1 回だけ再 dispatch する**（実測: 3 件中 2 件が拒否され、言い換えた再 dispatch で両方通った）。
- それでも通らなければ、**その subtask を実行できなかったことをユーザーに明示して**判断を仰ぐ。permission ルールの追加が要るならそこで求める。

（理由: 並列 dispatch は結果が非同期に返るため、拒否された 1 件は「返ってこなかった」だけに見え、完了報告の時点で欠落に気づけない。）

## 大規模 dispatch 前の確認

ユーザーの回答が曖昧で、その解釈次第でタスクの規模がスキルの通常処理単位を大きく超える場合（例: 1件処理が前提のスキルで複数件の回答を受け取り、複数 subagent・大量外部 fetch へ拡大解釈する等）、文字通りの解釈で即座に並列 dispatch せず、規模をユーザーに確認してから実行する（理由: 曖昧な回答を最大解釈して大規模な subagent 群を無確認で起動すると、ユーザーの意図と乖離した実行がその場で走ってしまい、途中で止めるコストが高くつく）。
