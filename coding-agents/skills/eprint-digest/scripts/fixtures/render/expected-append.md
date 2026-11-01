
## 追加分（2026-10-30 実行）

### 今週の流行

- 署名方式の実装安全性の論文が目立つ（2 件）: 2026/2601, 2026/2588
- カテゴリ別: PROTOCOLS 1 / FOUNDATIONS 0 / PUBLICKEY 1 / ATTACKS 1 / IMPLEMENTATION 0 / APPLICATIONS 0 / SECRETKEY 2（計 5 件、うち PQC 関連 3 件）

### ピックアップ

#### ML-DSA のマスキング実装を高速化

- [2026/2601](https://eprint.iacr.org/2026/2601) · PUBLICKEY · PQC
- 原題: ML-DSA & Masking: Faster

ML-DSA のマスキング実装で、乗算回数を減らす新しいガジェットを提案する。
従来の 2 次マスキングより 30% 高速で、安全性は probing モデルで証明している。

#### FHE のブートストラップ高速化

- [2026/2590](https://eprint.iacr.org/2026/2590) · PROTOCOLS
- 原題: FHE Bootstrapping Speedup

FHE のブートストラップを 2 倍高速化する。
鍵サイズは変わらない。

### 用語解説

- **マスキング**: 秘密値を乱数で分割して計算し、電力などの漏洩から秘密を推測されにくくするサイドチャネル対策。
- **ブートストラップ**: FHE で計算とともに増えるノイズを、暗号文のまま減らして計算を続けられるようにする処理。
