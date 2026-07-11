# FableT Office — マルチエージェント設計書

作成日: 2026-07-11 / 前提: [DESIGN.md](DESIGN.md)(fcc経路)は稼働済みであること

> **本書は作者自身の開発ログである。** `g24` 等の実値は作者の環境の実例であり、読者は自分の環境の値に読み替えること。初めてセットアップする場合は、まず [README.md](README.md) の「はじめに」を読むこと。

## 0. 本書の位置づけ

DESIGN.md は「Claude Code のハーネスをローカル LLM で駆動する」までを達成した。
本書はその上に2つを積む。

1. **FABLE.md 準拠の思考の復活** — 現行構成の残存矛盾(下記1章)の解消
2. **オフィス型マルチエージェント** — 提案者・作業者・クライアント・保守運用・
   ファクトチェック・効率厨・新規提案の7役が議論して方針を固めてから実装する運用

## 1. 現行構成の重大な問題(2026-07-11 監査)

### 🔴 P1: 生きた OpenAI API キーが平文で放置されている

`FableT/.env` に本物の `OPENAI_API_KEY`(sk-proj-…)が置かれている。

- プロジェクト内のどのファイル・手順からも**参照されていない孤児シークレット**
- DESIGN.md 7章・IMPLEMENTATION.md Phase 10 が自ら定めた
  「本物の API キーをこの環境に置かない」という規約に真っ向から違反
- fcc-server(第三者製・全プロンプト通過)と同居しており、
  誤って `~/.fcc/.env` にマージすればコードとキーがまとめて外部流出する
- git 管理下ではないが、`git init` した瞬間にコミットされる典型事故コース

**対処: このキーを platform.openai.com で即時失効させ、ファイルを削除する。**
必要なら OS のクレデンシャルストアか、少なくとも FableT の外に置く。

> **対処状況(2026-07-11)**: `.env` は削除済み。`.gitignore` で `.env` を恒久除外。
> **キーの失効のみ人間の作業として残っている**(platform.openai.com → API keys)。
> キーは既に平文で存在した時点で漏洩前提で扱うこと。削除だけでは解決にならない。

### 🔴 P2: サプライチェーン — fcc はバージョン未固定の第三者コード

`uv tool install "git+…free-claude-code.git"` は **git main の最新を無検証で取る**。
全プロンプト・auth token が通過する位置にいるソフトが、更新のたびに別物になりうる。
対処: コミットハッシュで固定する(`git+…@<sha>`)。更新は差分を見てから。

> **対処状況(2026-07-11)**: `1278d008`(v3.4.15 相当・当日の HEAD)に固定して
> 再導入済み。更新時は上流の差分を確認してから sha を進める。

### 🟠 P3: 「人格は効く ✅」は自己欺瞞 — FABLE.md はコーディング経路に乗っていない

DESIGN.md 0章の表は新方針で「人格が効く」と結論するが、そこで効いているのは
**Claude Code ハーネスの一般規範であって FABLE.md の人格ではない**。
`fable-t` は SYSTEM 空、Claude Code の system prompt は Anthropic 製の汎用文。
つまり「人格移植プロジェクトの主用途に人格が効かない」という旧方針の自己否定が、
形を変えてそのまま残っている。→ 本書2章で解消する。

> **対処状況(2026-07-11)**: 2章の3層供給を実装済み(fablet.ps1 が L1 を注入、
> `.claude/agents/` が L2 を保持、L3 は fablet-chat のまま)。

### 🟠 P4: Haiku tier の 32k ctx は黙って切り捨てられる

Claude Code が Haiku tier に投げる内部処理(要約・会話タイトル・サブエージェント)は
32k を超えることがあり、Ollama は超過分を**黙って**切り捨てる。DESIGN.md 5章自身が
「黙って切り捨ては原因が見えにくいので最初から最大を取る」と警告しながら、
`Modelfile.fast` は 32768 を採用している。gpt-oss:20b の上限 131072 まで上げても
13GB モデルなら VRAM は余る。→ `num_ctx 65536` 以上へ引き上げる。

> **対処状況(2026-07-11)**: `Modelfile.fast` を 65536 に変更し、g24 上で
> `fablet-fast` を再ビルド・`ollama show` で反映確認済み。DESIGN.md /
> IMPLEMENTATION.md の該当記載も更新した。

### 🟡 P5: バージョン管理がない

設計文書 16万字のプロジェクトに履歴がない。`.gitignore`(`.env` を除外)を書いた上で
`git init` するべき。P1 の解決が先(キーが履歴に入ってからでは遅い)。

> **対処状況(2026-07-11)**: P1 の `.env` 削除後に `git init` し、
> https://github.com/YUSEITASHIRO/FableT へ push 済み。

## 2. FABLE.md 思考の供給 — 3層で入れる

122KB の FABLE.md 全文をローカル 131k ctx に注ぐのは自殺行為(作業文脈が消える)。
**用途別に濃度を変えて3層で供給する。**

| 層 | 供給物 | 供給経路 | 効く範囲 |
|---|---|---|---|
| L1 | `fable-coding.txt`(1.4KB・loop工学の核) | 起動スクリプトが `--append-system-prompt` で注入 | セッション全体 |
| L2 | 各エージェントの人格断片(役割ごとに FABLE.md から抽出) | `.claude/agents/*.md` の本文 | そのエージェント |
| L3 | FABLE.md 全文 | `fablet-chat`(従来どおり) | 相談・文章用途 |

L1 はハーネスの system prompt を**置換せず追記**するので、ツール運用と矛盾しない。
これが P3 の解である: 人格は Modelfile ではなく **ハーネスの拡張点**から入れる。

## 3. オフィス — 7役のエージェント

`.claude/agents/` に定義。主セッション(あなたが話している Claude Code 本体)が
**PM(司会)**を務め、Agent ツールで各役を呼ぶ。

| 役 | name | tier | ツール | 責務 |
|---|---|---|---|---|
| 提案者 | `proposer` | opus | 読取のみ | 実装方針の第一案。コードを読んで根拠を持つ |
| 新規提案 | `innovator` | opus | 読取のみ | 第一案と**意図的に異なる**対案。前提を疑う |
| クライアント | `client` | haiku | 読取のみ | 依頼の代弁。受入条件を先に固定し、完成物を検収 |
| ファクトチェック | `fact-checker` | sonnet | 読取のみ | 提案内の事実主張(API仕様・実測値)をコードと実行で検証 |
| 効率厨 | `optimizer` | sonnet | 読取のみ | 工数・実行効率・過剰設計を殺す。YAGNIの番人 |
| 保守運用 | `maintainer` | sonnet | 読取のみ | 半年後に壊れないか。運用手順・ロールバック・監視 |
| 作業者 | `worker` | opus | 全ツール | 合意された方針の実装と検証ループ |

**書けるのは worker だけ**。議論役は全員読取専用にする。ローカルモデルは
フロンティアより自制が弱く(DESIGN.md 6章)、読取専用ならレビュー役の暴走が
構造的に不可能になる。

### 3.1 会議プロトコル(`/office` コマンド)

```
/office <依頼>
  Phase 1  client      受入条件を3〜5個に固定(これが以後の唯一の合否基準)
  Phase 2  proposer    方針A を提出
           innovator   方針B(Aと異なる前提のもの)を提出
  Phase 3  fact-checker A/B の事実主張を検証。誤りは名指しで却下
           optimizer    A/B の工数・複雑性を比較
           maintainer   A/B の運用リスクを比較
  Phase 4  PM(主セッション) 議論を統合し、採用案と理由を1段落で宣言
  Phase 5  worker      実装 → 検証ループ(fable-coding.txt の loop工学)
  Phase 6  client      Phase 1 の受入条件で検収。不合格なら Phase 5 へ差し戻し
  Phase 7  PM          結果報告(採用案・却下案とその理由・検証結果)
```

**逐次実行が原則。** Ollama は既定で並列度1であり、並列に呼んでも直列化されて
文脈だけ焼ける。また全役が同じ 120B を使う以上、「別人格」はプロンプトが作る——
だからこそ各エージェント定義の人格断片(L2)が機能要件になる。

### 3.2 コスト特性と使い分け

会議は1回で 120B を7回以上起こす。軽微な修正に使うのは効率厨が真っ先に却下する
案件なので、**PM は依頼の重さで自動的に省略する**: 自明なタスクは worker 直行、
方針が割れうるタスクだけフル会議。この判断規準は CLAUDE.md に書く。

## 4. `/model` 連携 — 「/model fablet」を実現する仕組み

すでに材料は揃っている。fcc が `/v1/models` で `ollama/fable-t` 等を公開し、
`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`(IMPLEMENTATION.md Phase 5-2)で
Claude Code の `/model` がゲートウェイのモデル一覧を認識する。つまり:

- `/model ollama/fable-t` — セッションの主モデルをローカル 120B に切替
- `/model opus` / `/model haiku` — fcc の tier 割り当て(`~/.fcc/.env`)に従う
- エージェント定義の `model:` フィールド(opus/sonnet/haiku)も同じ tier 表で解決
  されるため、**オフィスの各役がどのローカルモデルで動くかは `~/.fcc/.env` の
  3行で一元管理できる**

将来 GLM-4.5-Air 等を `fable-t2` として作れば `/model ollama/fable-t2` で
即切替できる。Modelfile の追加以外に必要な作業はない。

## 5. 起動手順(まとめ)

```powershell
# 1. トンネル(別ターミナルで維持)
ssh -o ExitOnForwardFailure=yes -N -L 127.0.0.1:11500:localhost:11500 g24
# 2. プロキシ
fcc-server
# 3. FableT セッション(環境変数注入 + FABLE.md L1 を append)
.\fablet.ps1          # ← 本書と同時に作成したランチャ
# 4. 重いタスクは会議に掛ける
/office <依頼内容>
```

`fablet.ps1` は経路(トンネル・プロキシ)の生存確認をしてから Claude Code を起動する。
死んでいる経路があれば起動せずに指摘する(黙った IPv6 事故の再発防止)。

## 6. 残課題

- 会議の質は結局ローカルモデルの議論能力に依存する。7役が全部同じ 120B である
  以上、「多様性」はプロンプト差分のみ。実測して同質化が酷ければ、役ごとに
  temperature を変えた派生 Modelfile(`fablet-critic` 等)を検討する
- worker の書込み権限は Claude Code の permission mode が最後の防波堤。
  初回はデフォルト(都度確認)で運用し、信頼できたら acceptEdits へ
- P1〜P5(1章)は本設計と独立に、先に潰すこと。特に P1 は今日やる
