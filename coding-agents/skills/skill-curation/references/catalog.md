# Curated skill catalog（この環境向け・Phase 1 の対象）

この環境の stack(Astro/Svelte/TS・C/C++・Python・CTF/security・Inkdrop パイプライン)に
合わせて vetting した skill リスト。**ここに行があるものは Phase 1 で即提案してよい**。
無ければ skill-curation の Phase 2(クロスソース探索)へ。

採用は vendor 機構で行う(APM 不使用): `coding-agents/vendor/manifest.tsv` に
`REPO`/`PIN` ブロック + `<local-name><TAB><upstream-path>` を足し、`fetch.sh` →
`install.sh`。`PIN` は eval を通した commit SHA に固定する。

凡例: ✅=導入済み / ⬚=候補(未導入)

## 言語 / runtime

### TypeScript / JavaScript（signal: `package.json` / `tsconfig.json` / `astro.config.*` / `svelte.config.*`）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ⬚ | check-similarity-ts | `mizchi/similarity` | `.claude/skills/check-similarity-ts` | AST 類似度で重複コード検出(TS/JS) |

### Python（signal: `pyproject.toml` / `requirements.txt`）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ⬚ | check-similarity-py | `mizchi/similarity` | `.claude/skills/check-similarity-py` | AST 類似度で重複コード検出(Python) |

### C / C++（signal: `CMakeLists.txt` / `Makefile` / `*.c` `*.cpp`）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| — | (なし) | — | — | clangd LSP プラグインでカバー。skill-shaped ニーズが出たら Phase 2 |

## 静的解析 / lint（signal: `sgconfig.yml` / ESLint で表現できない lint 要求）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ✅ | ast-grep | `ast-grep/agent-skill` | `ast-grep/skills/ast-grep` | ast-grep ルールの書き方・構造検索(権威リファレンス) |
| ✅ | ast-grep-practice | `mizchi/skills` | `tooling/ast-grep-practice` | ast-grep を project lint として運用 |

## Web / テスト（signal: `playwright.config.*` / `e2e/` / 画像差分要求）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ⬚ | playwright-test | `mizchi/skills` | `testing/playwright-test` | **主**: E2E テスト作成・レビュー(fixed wait 禁止) |
| ⬚ | playwright-cli | `mizchi/skills` | `testing/playwright-cli` | 副: CI sharding / codegen / screenshot・pdf が要るとき |
| ⬚ | vrt | `mizchi/vrt` | (repo-root SKILL.md) | Visual Regression + a11y 検証 CLI。要 `apm view` 相当の確認 |

### frontend review（signal: フロント repo で構造化レビューをしたいとき）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ⬚ | frontend-review-ci | `mizchi/skills` | `frontend/review-ci` | CI が遅い/flaky のとき GitHub Actions 最適化 |
| ⬚ | frontend-review-hygiene | `mizchi/skills` | `frontend/review-hygiene` | TS strictness / lint / dead code / 重複 |
| ⬚ | frontend-review-deps | `mizchi/skills` | `frontend/review-deps` | 依存の鮮度・CVE triage |
| ⬚ | frontend-review-testing | `mizchi/skills` | `frontend/review-testing` | test インフラ監査 |
| ⬚ | frontend-review-security | `mizchi/skills` | `frontend/review-security` | HTML sink / token 保管 / route guard / env 露出 |
| ⬚ | frontend-review-performance | `mizchi/skills` | `frontend/review-performance` | レンダリング性能(profiler-first) |
> 注: react-expert 等の観点 sub-skill は React 寄り。Astro/Svelte 主体なら上の汎用行を優先。

## Security / CTF（signal: web アプリの security review 要求）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ⬚ | security-review | `mizchi/security-review` | `skills/security-review` | orchestrator(下記3 sub を順に) |
| ⬚ | security-review-whitebox | `mizchi/security-review` | `skills/security-review-whitebox` | 静的 + ソースレビュー |
| ⬚ | security-review-blackbox | `mizchi/security-review` | `skills/security-review-blackbox` | OWASP ZAP baseline 等 |
| ⬚ | security-review-exploit | `mizchi/security-review` | `skills/security-review-exploit` | 仮説を live HTTP / PoC で確認 |
> 注: Claude には `security-guidance` プラグイン + `/security-review` もある。重複を見てから採用。

## Meta（skill / prompt 運用。導入済み）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ✅ | retrospective-codify | `mizchi/skills` | `meta/retrospective-codify` | 教訓を ast-grep ルール / skill / CLAUDE.md に codify |
| ✅ | empirical-prompt-tuning | `mizchi/skills` | `meta/empirical-prompt-tuning` | 自作 skill の継続チューニング(方法論) |
| ✅ | waxa-eval | `mizchi/skills` | `meta/waxa-eval` | その実測エンジン(waxa CLI) |
| ✅ | optimizing-descriptions | `mizchi/skills` | `meta/optimizing-descriptions` | description(トリガー)精度の調整 |
| ✅ | skill-creator | (plugin) | `claude-plugins-official` | 新規 skill の作成(公式プラグイン) |

## Inkdrop パイプライン（導入済み）
| | skill | repo | upstream path | 用途 |
|---|---|---|---|---|
| ✅ | note-taking | `inkdropapp/skills` | `skills/note-taking` | Inkdrop の markdown 方言(コードブロック属性 / mermaid / KaTeX / `inkdrop://note/<id>` リンク) |
| ⛔ | fill-out-template | `inkdropapp/skills` | `skills/fill-out-template` | 不採用: 計画は `.claude/plans/` に置く方針で `plan-doc` / `planning-workflow` と重複 |
> 注: `note-taking` は model-invoked で、Inkdrop ノートを書くたび発火する。図(mermaid)を能動的に
> 勧めるので、分量を絞る skill 側で優先順位を明示すること(inbox-capture の日次要約が該当)。
> upstream に LICENSE が無い(README も認めている)。payload は gitignore で再配布しない。

## Deliberately not in catalog（この stack に不要 — Phase 2 にも上げない）
| 軸 | 理由 |
|---|---|
| MoonBit / Gleam | この環境で書いてない |
| pkfire / justfile / nix-setup | task runner / 環境構築は現状の運用で足りる |
| flaker | flaky test 検出を今必要としていない |
| Cloudflare / AWS / k8s | デプロイ先でない |
| mnemo(メモリ) | Claude auto-memory + 自前メモリ機構と重複 |
| chezmoi-management | dotfiles は git + symlink 管理(chezmoi 不使用) |
| apm-usage | APM を使わない(vendor 機構で代替) |

## catalog hygiene
- 行を足すのは「実プロジェクトで実際に使い、効いた」skill のみ。
- Phase 2 で見つけた skill は、waxa eval を通し 2 プロジェクトで実用してから昇格。
- upstream(各 repo)が skill を増減したら、この表も同じ編集で同期。
