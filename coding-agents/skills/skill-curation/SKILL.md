---
name: skill-curation
description: 'この dotfiles 環境で agent skill を探す/選ぶ/採用するための meta-skill。ユーザーが明示的に「skill を追加したい」「〜の skill はある?」と言ったとき、または採用前に候補を評価するときだけ起動する——通常作業では auto-invoke しない。catalog-first（references/catalog.md を先に読んでから外を探す）→ 段階的なクロスソース探索 → 7軸ルーブリック → 必須の waxa audit/eval ゲート → coding-agents/vendor/manifest.tsv に pin して採用（vendor 機構。この環境は APM を使わない）。'
---

# skill-curation

このリポジトリ向けに skill を **探す → 選ぶ → 採用する** ための meta-skill。
mizchi の skill-selector / skill-finder の思想を、この環境(APM 不使用・vendor 機構で
全 CLI 配布)に合わせて1つに畳んだもの。

skill を足すのは disk 上は安いが context は食う。**意図的に選ぶ**こと。

## いつ呼ぶか

明示的な要求のときだけ(自動発火しない meta-skill):

- 「`<X>` の skill ある?」「`<X>` 用の skill 探して」
- 「この skill 入れるべき?」「`<owner/repo>` を採用前に評価して」
- 「skill を追加したい」

呼ばない:

- 一度きりのタスク → skill 化せず inline で解く
- 既に vendor 済み(`coding-agents/vendor/manifest.tsv` にある)→ まず再確認

## Phase 1 — catalog-first

`references/catalog.md`(この環境の stack 向けに vetting 済み)を**先に見る**。

1. `references/catalog.md` を読む。
2. project signal を3源から拾う: repo ファイル(`package.json` / `astro.config.*` /
   `svelte.config.*` / `CMakeLists.txt` / `pyproject.toml` / `.github/workflows/` 等)、
   ユーザーの明示意図、`CLAUDE.md` の mandate。
3. ヒットしたら **install 行を提示して停止**(野良検索に進まない)。ユーザーに提案 →
   引き算してもらう。default は少なめ。
4. catalog に無く、かつ**反復する**ニーズなら Phase 2 へ。30 秒スキャンして無ければ
   迷わずエスカレーション(逆に「近いけど違う」を無理に catalog に押し込まない)。

## Phase 2 — cross-source search(catalog ミス時のみ)

優先 tier を**上から**。上位でヒットしたら下位は見ない。

| Tier | ソース | 備考 |
|---|---|---|
| 1 | `anthropics/skills` | 一次・最高信頼。`skills/<name>` 配下 |
| 1 | `anthropics/claude-plugins-official` | 公式プラグイン marketplace |
| 2 | `majiayu000/claude-skill-registry` | 日次クロール・security scan 済みの横断 index。発見に最適 |
| 2 | `VoltAgent/awesome-agent-skills` | org 別 awesome-list(MIT・活発) |
| 3 | `ComposioHQ/awesome-claude-skills` | 緩めの curation。候補止まり |
| 3 | `obra/superpowers` | 方法論寄り・高品質だが opinionated |
| 4 | GitHub `topic:claude-skill` / `topic:agent-skills` / `path:**/SKILL.md` | 最後の手段。star でなく更新日でソート |
| NG | `agent-skills.cc` | SEO スクレイプ。GitHub repo への alias 引きにのみ使い、推薦根拠にしない |

## ルーブリック(7軸・全部 acceptable で合格)

- **Fit** — skill の "Use when…" が実タスクに本当に合うか(title でなく description を読む)
- **非冗長** — 既存の導入済み skill 群と被らないか(被るなら reject)
- **メンテ** — 直近 commit / upstream の活性
- **License** — SPDX があり consuming project と互換か(payload は gitignore なので
  vendoring 自体は再配布でないが、明示が無いものは記録)
- **Frontmatter** — `name` が dir と一致・`description` が ≤1024 でトリガー条件形
- **本文品質** — "When NOT to use" がある・具体的か
- **Footprint** — 本文長・demand-load か・他 skill 依存

## ゲート(採用前に必須)

1. `npx @mizchi/waxa audit <candidate-dir>` で構造的問題を安く検出。
2. `waxa` eval を収束(2連続で unclear ゼロ)まで回す。詳しい操作は `waxa-eval` skill。
   2反復して unclear が減らなければ **divergent = reject**。
3. ルーブリックの**非冗長**で落ちる候補は、Fit ✓ でも reject(理由を
   `references/rejection-log.md` に記録)。

## 採用 = vendor で pin(APM は使わない)

この環境は APM を使わない。採用は **vendor 機構**で:

1. `coding-agents/vendor/manifest.tsv` に追記:
   - 既存 repo(例 `mizchi/skills`)由来なら、その `REPO`/`PIN` ブロックに
     `<local-name><TAB><upstream-path>` を1行足す。
   - 別 repo 由来なら新しい `REPO=` / `PIN=`(eval を通した commit SHA)/ `LICENSE=`
     ブロックを足してから skill 行。
2. `coding-agents/vendor/fetch.sh` で取得(payload は gitignore)。
3. `coding-agents/install.sh` で全 CLI に symlink。
4. **eval を通した ref で pin**。floating ref(`main`/`HEAD`)禁止 ——
   `gh api repos/<owner>/<repo>/commits/HEAD --jq .sha` 等で SHA 解決。

プラグイン marketplace 形式のソースは、cross-CLI が要らないなら
`claude plugin marketplace add <repo>` + `claude plugin install` でも可(Claude 限定)。
原則は vendor(全 CLI 共通)を優先。

## 候補が無いとき

ルーブリックを通る既存 skill が無ければ、**自作**する。新規作成は `skill-creator`
(公式プラグイン)を使う(CLAUDE.md のルール)。運用しながらの継続チューニングは
`empirical-prompt-tuning` + `waxa`。

## Related

- `references/catalog.md` — この環境の curated catalog(Phase 1 の対象)
- `references/rejection-log.md` — reject 理由の記録(再評価の無駄を防ぐ)
- `waxa-eval` — 採用ゲートの eval 実体
- `retrospective-codify` — 教訓を skill 化する入口(skill 化したら skill-creator で作成)
