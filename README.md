# FableT

**Claude のクレジットを1円も消費せずに、Claude Code のフル機能でコーディングする環境。**

Claude Code CLI をローカルプロキシ経由で共有 GPU 機 g24 の Ollama に接続し、推論をすべてローカルモデル(gpt-oss:120b / qwen3:30b-a3b)で行う。さらに7役のエージェントが議論して方針を固めてから実装する「オフィス型」ワークフローを備える。

## なぜ FableT か

- **💰 クレジット消費ゼロ** — リクエストは Anthropic に一切届かない。`ANTHROPIC_BASE_URL` がローカルプロキシ(`127.0.0.1:8082`)を指し、認証もダミートークン。推論は全て g24 の GPU。何時間使っても、何万トークン吐いても、Claude の利用枠は減らない
- **🔒 コードが外に出ない** — 業務コード・機密リポジトリをクラウドに送信せずエージェンティックコーディングできる
- **🛠 Claude Code のフル機能** — Read/Edit/Bash/Glob などのツール群、検証ループ、サブエージェント、コンパクションはすべて本物のハーネス。モデルだけがローカル
- **🏢 オフィス型マルチエージェント** — 提案者・新規提案・クライアント・ファクトチェック・効率厨・保守運用・作業者の7役が議論し、受入条件を固定してから実装・検収する
- **⚡ 実測性能** — プレフィル約5,000 tok/s、生成150 tok/s(2026-07-11 実測)。日常応答は数秒

## クイックスタート

必要な手順は **1コマンド** :

```powershell
cd C:\Users\yusei\Desktop\FableT
.\fablet.ps1
```

これだけで、SSHトンネル(g24へ)と fcc-server(プロキシ)を自動起動・自動検査し、FABLE.md の思考規律を注入した Claude Code セッションが立ち上がる。3つの `[OK]` が並べば準備完了。

```
[OK] Ollama (g24 :11500 via tunnel)
[OK] fablet-code visible
[OK] fcc-server (:8082)
```

唯一の手動復旧ポイントは g24 側の Ollama が落ちている場合(起動時に赤字で指摘される):

```powershell
ssh g24 "setsid nohup ~/ollama-dist/start.sh > ~/ollama-dist/server.log 2>&1 < /dev/null &"
```

## モデル構成 — 二段構え

| tier | モデル | 実体 | 使いどころ |
|---|---|---|---|
| sonnet / haiku(既定) | `fablet-mid` | qwen3:30b-a3b(MoE) | 日常のコーディング。速い(1往復2〜5秒) |
| opus | `fablet-code` | gpt-oss:120b | 難しい設計判断・複雑な実装。賢いが待つ |

セッション内での切替:

```
/model opus                 # 難所の前に120Bへ
/model sonnet               # 終わったら戻す
/model ollama/fablet-code   # ゲートウェイのモデル名を直接指定してもよい
```

両モデル合計 ~87GB は 96GB VRAM に同時常駐でき、切替でロード待ちは発生しない。tier の割り当ては `~/.fcc/.env` の3行(`MODEL_OPUS` 等)で一元管理される。

## オフィス会議モード

方針が割れそうな重いタスクは `/office` に掛ける:

```
/office ログイン処理をセッショントークン方式に移行して
```

進行(詳細は [.claude/commands/office.md](.claude/commands/office.md)):

1. **クライアント**が受入条件を3〜5個に固定(以後の唯一の合否基準)
2. **提案者**が方針A、**新規提案**が前提の異なる対案Bを提出
3. **ファクトチェック**(事実主張の検証)・**効率厨**(工数と過剰設計)・**保守運用**(半年後に壊れないか)が両案を審査
4. PM(主セッション)が統合判断 → **作業者**が実装と検証ループ → クライアントが検収

書込み権限を持つのは作業者だけ。レビュー役は読取専用なので、構造的に暴走できない。自明なタスク(typo修正など)は会議を自動省略して直行する。

⏱ **注意: 会議は重い。** 1回でローカルモデルを7回以上起こすため、軽微な修正に使うと数十分かかる。日常タスクは普通に依頼するだけでよい。

## クレジットについて(重要)

| 起動方法 | 接続先 | クレジット消費 |
|---|---|---|
| `.\fablet.ps1` | ローカルプロキシ → g24 | **なし(ゼロ)** |
| 素の `claude` | 本物の Anthropic API | **あり** |

- 見分け方: セッション内で `/model` を開き、`ollama/fablet-code` 等が並んでいればローカル(消費なし)。Opus/Sonnet/Haiku の正規モデルだけなら Anthropic(消費あり)
- `~/.fcc/.env` の tier をクラウド無料枠(NVIDIA NIM 等)へ向けた場合はクレジットこそ減らないが、**コードが外部送信される**。業務コードでは必ずローカル(`ollama/`)に戻すこと([DESIGN.md 4.1](DESIGN.md))

## 注意事項

- **g24 は共用 GPU 機。後始末は機能要件。** 作業を終えたら必ず実行:
  ```bash
  ./cleanup.sh          # ロード中モデルをアンロード(VRAM 65〜87GB を解放)
  ./cleanup.sh --stop   # 加えて Ollama サーバ自体も停止
  ```
  投入前の空き確認は `./vram.sh`。一時ファイルを g24 に置いたら消す。恒常的に必要なデータは g24 に置かず、ローカルへ scp して参照する
- **本物の API キーをこの環境に置かない。** プロキシ(fcc)は第三者製で全プロンプトが通過する。`ANTHROPIC_AUTH_TOKEN` はダミー(`fablet-local`)のまま使う。過去に本物のキーを平文で置いて失効騒ぎになった([OFFICE.md P1](OFFICE.md))
- **fcc の更新はコミット固定で。** `uv tool install "git+…@<sha>"` の形を守る(現在 `1278d008` に固定)。git main 追従は全プロンプトが通る位置のソフトでは危険
- **初回応答は10〜20秒待つ**(モデルのGPUロード)。2回目以降は速い。アイドル2時間でアンロードされ、次回また初回コストがかかる
- **トンネルのプロセスは残る。** fablet.ps1 が張った SSH トンネルと fcc-server(最小化ウィンドウ)は使い終わっても生きている。完全に落とすなら fcc-server の窓を閉じ、タスクマネージャで ssh を終了するか PC を再起動
- **`localhost` ではなく `127.0.0.1`。** 疎通確認で `localhost` を使うと IPv6 に逃げて Windows ローカルの別 Ollama を見ることがある(過去に数十分溶かした事故の記録が [IMPLEMENTATION.md Phase 3](IMPLEMENTATION.md) にある)

## トラブルシューティング(抜粋)

| 症状 | 対処 |
|---|---|
| `[NG] Ollama` のまま | g24 側サーバ停止。クイックスタート末尾のコマンドで起動 |
| `[NG] fcc-server` のまま | 別ターミナルで `fcc-server` を直接実行しエラーを読む |
| 応答が異常に遅い | `ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama ps"` で `100% GPU` を確認。CPU が混ざっていたら [IMPLEMENTATION.md Phase 7](IMPLEMENTATION.md) |
| モデルが見つからない | トンネルの先が違う。`127.0.0.1` と `localhost` で `/api/tags` を比較 |

詳細は [IMPLEMENTATION.md Phase 7](IMPLEMENTATION.md) の対照表を参照。

## ドキュメント

| ファイル | 内容 |
|---|---|
| [DESIGN.md](DESIGN.md) | 基本設計。方針転換の経緯、アーキテクチャ、tier ルーティング |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | 実装手順書。g24 構築、検証、トラブルシューティング |
| [OFFICE.md](OFFICE.md) | オフィス設計と監査記録(P1〜P5 の問題と対処) |
| [CLAUDE.md](CLAUDE.md) | セッションのプロジェクト規約 |
| [FABLE.md](FABLE.md) | 人格・思考規律の原典。抽出物が `fable-*.txt` |

## アーキテクチャ

```
[Windows PC]                                  [g24 (RTX PRO 6000 96GB)]

  Claude Code CLI (fablet.ps1 が起動・環境注入)
       │ ANTHROPIC_BASE_URL=http://127.0.0.1:8082 (ダミートークン)
       ▼
  fcc-server (Anthropic API 互換プロキシ・自動起動)
       │ tier 解決: opus → fablet-code(120B) / sonnet,haiku → fablet-mid(30B)
       ▼
  127.0.0.1:11500 ──[SSHトンネル・自動起動]──▶ ユーザー空間 Ollama (:11500)
```

## 動作環境

- Windows 11 + Claude Code CLI + uv + 鍵認証済みの `ssh g24`
- g24: ユーザー空間 Ollama **0.20 以上**(`~/ollama-dist`、`:11500`、flash attention + KV q8_0)
- モデル: `fablet-code`(gpt-oss:120b, 131k ctx)/ `fablet-mid`(qwen3:30b-a3b, 64k ctx)/ `fablet-fast`(gpt-oss:20b, 64k ctx・予備)/ `fablet-chat`(人格入り・相談用)
