# FableT

**Claude Code のハーネスをローカル LLM(gpt-oss:120b on g24)で駆動し、
オフィス型マルチエージェントでタスクを遂行する環境。**

Anthropic Messages API を喋るローカルプロキシ([free-claude-code](https://github.com/Alishahryar1/free-claude-code))を介して、Claude Code CLI の全機能(ツール、エージェンティックループ、サブエージェント)を共有 GPU 機 g24 上の Ollama で動かす。人格・思考規律は FABLE.md から3層で供給する。

```
[Windows PC]                                  [g24 (RTX PRO 6000 96GB)]

  Claude Code CLI (fablet.ps1 で起動)
       │ ANTHROPIC_BASE_URL=http://127.0.0.1:8082
       ▼
  fcc-server (Anthropic API 互換プロキシ)
       │ tier 解決: opus/sonnet → fablet-code(120B) / haiku → fablet-fast(20B)
       ▼
  127.0.0.1:11500 ──[ssh -N -L 11500:localhost:11500 g24]──▶ ユーザー空間 Ollama
```

## ドキュメント

| ファイル | 内容 |
|---|---|
| [DESIGN.md](DESIGN.md) | 基本設計。方針転換の経緯、アーキテクチャ、モデル定義、tier ルーティング |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | 実装手順書。g24 のユーザー空間 Ollama 構築、プロキシ導入、動作検証、トラブルシューティング |
| [OFFICE.md](OFFICE.md) | オフィス型マルチエージェント設計。監査で見つけた問題(P1〜P5)とその対処記録を含む |
| [CLAUDE.md](CLAUDE.md) | Claude Code セッションのプロジェクト規約 |
| [FABLE.md](FABLE.md) | 人格・思考規律の原典(122KB)。抽出物が `fable-*.txt` |

## 使い方

```powershell
# 1. SSH トンネル(別ターミナルで維持)
ssh -o ExitOnForwardFailure=yes -N -L 127.0.0.1:11500:localhost:11500 g24

# 2. プロキシ(別ターミナル)
fcc-server

# 3. FableT セッション起動(経路の生存確認 → FABLE.md 思考規律を注入して claude を起動)
.\fablet.ps1
```

セッション内:

- `/office <依頼>` — 7役のエージェント会議で方針を固めてから実装する(下記)
- `/model ollama/fablet-code` — セッションの主モデルを切替(ゲートウェイのモデル一覧から選択可)
- 作業後は `./cleanup.sh` で g24 の VRAM を解放する(**共用機。後始末は機能要件**)

## オフィス — 7役のエージェント

`.claude/agents/` に定義。主セッションが PM(司会)を務め、書込み権限は作業者のみ。

| 役 | 責務 |
|---|---|
| 提案者 proposer | 実装方針の第一案(コードを読んだ根拠付き) |
| 新規提案 innovator | 意図的に異なる前提の対案。前提を疑う |
| クライアント client | 受入条件の固定と検収。技術論に立ち入らない |
| ファクトチェック fact-checker | 提案内の事実主張をコードと実行で検証 |
| 効率厨 optimizer | 工数・実行効率・過剰設計の審査。YAGNI の番人 |
| 保守運用 maintainer | 半年後に壊れないか。失敗モード・ロールバック |
| 作業者 worker | 合意方針の実装と検証ループ(唯一の書込み役) |

会議プロトコル(受入条件 → 提案A/対案B → 3観点審査 → PM 統合判断 → 実装 → 検収)は
[.claude/commands/office.md](.claude/commands/office.md) を参照。自明なタスクは会議を自動省略する。

## セキュリティ上の注意

- プロキシは第三者製で**全プロンプトが通過する**。本物の Anthropic/OpenAI API キーをこの環境に置かない(`ANTHROPIC_AUTH_TOKEN` はダミー)。導入はコミット固定(OFFICE.md P2)
- シークレットは `.gitignore` で除外済み。`.env` をコミットしない(OFFICE.md P1 の事故記録を参照)
- クラウド無料枠へ tier を切り替えるとコードが外部送信される。業務コードでは戻し忘れに注意(DESIGN.md 4.1)

## 動作環境

- Windows 11 + Claude Code CLI + uv
- g24: ユーザー空間 Ollama **0.20 以上**(`~/ollama-dist`、`:11500`)、`fablet-code`(gpt-oss:120b, 131k ctx)/ `fablet-fast`(gpt-oss:20b, 64k ctx)
- 空き VRAM 目安: 120B 単体 70GiB、20B 併用 80GiB 以上
