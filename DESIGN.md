# FableT 設計図 — Claude Code のハーネスをローカルLLMで駆動する

作成日: 2026-07-09 / 更新: 2026-07-09(**基本方針を一新**: free-claude-code 方式へ転換) / 対象ホスト: `ssh g24`

参照: [free-claude-code (Alishahryar1)](https://github.com/Alishahryar1/free-claude-code)

---

## 0. 方針転換の要旨

旧方針は「FABLE.md の人格をOllamaのModelfile SYSTEMに焼き込んだ `fablet` を作り、aider/Cline から使う」だった。しかしこの方針は自身の設計文書(旧6.5節)の中で既に致命的な矛盾を認めていた——**エージェンティックなコーディングクライアントは自前のsystem promptを送るため、焼き込んだ人格はほぼ上書きされる**。つまり主用途(コーディング)において、プロジェクトの中心的な成果物である `fablet` の人格プロンプトは効かない。旧設計はこれを「割り切り」として受容していたが、それは「人格移植プロジェクトの主用途には人格が効かない」という自己否定に等しい。

free-claude-code は、この矛盾を裏側から解消する。**人格をモデルに移植するのをやめ、ハーネスごと本物を使う。**

具体的には、Anthropic Messages API を喋るローカルプロキシを立て、Claude Code CLI をそこへ向ける。Claude Code は自分が本物のAPIと話していると認識してフル機能(ツール、エージェンティックループ、サブエージェント、compaction)で動作し、その裏で推論しているのは g24 の `gpt-oss:120b` である。

| | 旧方針 | 新方針 |
|---|---|---|
| 人格・振る舞いの供給元 | Modelfile の SYSTEM(FABLE.md抽出) | **Claude Code 本体のsystem prompt** |
| ループ・ツールの供給元 | aider / Cline のハーネス | **Claude Code 本体のハーネス** |
| ローカルモデルの役割 | 人格を演じる主体 | **推論エンジン(brain)** |
| loop_engineering | プロンプトで「そう振る舞え」と指示 | **ハーネスの実装そのもの** |
| コーディング時に人格は効くか | ❌ 効かない | ✅ 効く(Claude Codeの規範として) |

loop_engineering は、もはやプロンプトに書いて祈る規範ではない。Claude Code の Read/Edit/Bash/検証ループとして**コードで実装済みのもの**を借りる。これが今回の転換の本質である。

## 1. 実機環境(2026-07-09 再実測)

前回計測から状況が大きく好転している。旧設計の最大制約だったディスクとVRAMは、いずれも解消した。

- GPU: NVIDIA RTX PRO 6000 Blackwell Max-Q, 97,887 MiB VRAM
- **VRAM 空き: 97,249 MiB(ほぼ全空き。他ユーザーのジョブなし)**
- **ディスク `/`: 1.8TB中 197GB 空き(89%使用)** — 旧記載「空き0・100%」から回復
- Ollama: v0.13.2
- 既存モデル: `fablet`(65GB / 旧方針の成果物)、`gpt-oss:120b`(65GB)、`gpt-oss:20b`(13GB)、`qwen3:30b-a3b`(18GB)、`gemma3:27b`(17GB)、`qwen3-vl:8b-instruct`、`qwen2.5vl:7b`

### ベースモデルの適合性(`ollama show gpt-oss:120b` 実測)

```
architecture     gptoss
parameters       116.8B
context length   131072
quantization     MXFP4
Capabilities     completion, tools, thinking
```

**`tools` と `thinking` を持ち、context length が 131,072。** Claude Code のハーネスを駆動する最低要件(tool-calling必須、大きなsystem prompt + ツール定義を飲める文脈長)を満たしている。これが新方針の実現可能性を担保する最重要事実である。

## 2. アーキテクチャ

```
[Windows PC]                              [g24 (Linux)]

  Claude Code CLI
       │ Anthropic Messages API
       │ (ANTHROPIC_BASE_URL=http://localhost:8082)
       ▼
  fcc-server (FastAPI proxy)
       │ /v1/messages を OpenAI互換 に変換
       │ MODEL=ollama/fablet-code
       ▼
  localhost:11434 ──[ssh -N -L 11434:localhost:11434 g24]──▶ Ollama
                                                              └ gpt-oss:120b
```

構成要素は3つだけである。**Claude Code CLI**(ハーネス。人格・ループ・ツールの供給元)、**fcc-server**(Anthropic API プロトコルを喋るローカルプロキシ。モデルtierのルーティングを担う)、**Ollama on g24**(推論エンジン)。プロキシは Windows 側で動かし、g24 の Ollama へは SSH ポートフォワードで到達する。プロキシを g24 側に置く構成も可能だが、Admin UI が `127.0.0.1` バインド固定のため Windows 側に置くほうが素直である。

## 3. モデルの再定義 — 3つに分ける

旧方針の `fablet`(人格焼き込み済み)は**コーディング用途では有害**である。その SYSTEM には「You have NO external tools: no web search, no file creation, no code execution」と明記されている。一方 Claude Code は Read/Write/Edit/Bash/WebSearch のフルセットを渡してくる。この2つは真正面から矛盾し、モデルは「ツールを持っていない」と主張しながらツール呼び出しを求められる。ツール幻覚の抑止のために入れた一文が、ハーネスを載せた瞬間にツール**拒否**の原因に反転する。

したがってモデルを用途別に分離する。

| モデル | ベース | SYSTEM | num_ctx | 用途 |
|---|---|---|---|---|
| **`fablet-code`**(新規・主役) | gpt-oss:120b | **なし**(Claude Codeが供給) | 131072 | Claude Code 経由のコーディング |
| `fablet-chat`(旧 `fablet` を改名) | gpt-oss:120b | FABLE.md抽出人格 | 65536 | Open WebUI等での相談・文章 |
| `fablet-fast`(任意) | gpt-oss:20b | なし | 65536 | Haiku tier(要約・分類等の雑務)。32768 では内部処理が黙って切り捨てられうる(OFFICE.md P4) |

`fablet-code` の Modelfile は SYSTEM を持たず、`num_ctx` と生成パラメータだけを設定する薄い派生である。**Modelfile が SYSTEM を持つと Ollama はそれを会話先頭に挿入し、Claude Code が送る本物の system prompt と二重になる**ため、明示的に空でなければならない。

FABLE.md 由来の資産(`fable-system.txt` 等)は捨てない。`fablet-chat` として生かす。ただし**プロジェクトの主軸からは降ろす**。コーディングにおける「Fable 5らしさ」は、今後は Claude Code のsystem promptとハーネスが供給する。

## 4. モデルルーティング(tier分割)

fcc-server は Claude Code が要求する Opus/Sonnet/Haiku の3 tier を、それぞれ別バックエンドに振り分けられる。これを使って**ローカルとクラウド無料枠のハイブリッド**を組む。

| tier | 割り当て | 理由 |
|---|---|---|
| `MODEL_OPUS` | `ollama/fablet-code`(g24) | 主計画・実装・最終判断。ローカルで完結。プライバシーとレート制限なし |
| `MODEL_SONNET` | `ollama/fablet-code` | 同上(当面は同一) |
| `MODEL_HAIKU` | `ollama/fablet-fast`(gpt-oss:20b) | Claude Codeが内部的に多用する軽量処理。120Bを毎回起こすと遅い |

### 4.1 ローカルとクラウド無料枠の使い分け

`gpt-oss:120b` は 2025年のモデルであり、2026年時点の開放重みフロンティア(Kimi K2.6、DeepSeek V4、GLM-5.1 — いずれも1Tクラス MoE)とは**世代が1つ違う**。とくに Kimi K2.6 は Terminal-Bench 2.0(実ターミナルで出力を読みエラーに対処し反復する能力)で 66.7% を出しており、これは Claude Code のループそのものを測るベンチである。エージェンティックなコーディングにおける差は、まさに本設計が関門とする**ツール呼び出しの忠実度**に現れる。

> 各種ベンチの絶対値は情報源によって食い違いが大きい(DeepSeek V4 Pro の SWE-bench Verified を 80.6% とする記事と 91.2% とする記事が併存する)。数値ではなく「世代が違う」という構図のみを設計判断に使う。

重要な前提として、**これらをローカルに持ってくる道はない**。1Tクラスは 96GB VRAM に載らない。したがって選択は「ローカルの `gpt-oss:120b`」対「クラウド無料枠の Kimi/DeepSeek/GLM」であり、両立しない。

無料枠には性能表に出ないコストがある。**コードが外部に送信される**(無料枠はしばしば入力の学習利用と引き換え)。**レート制限が Claude Code と相性が悪い**(1タスクで数十回APIを叩き、Haiku tier の内部処理も乗る。分あたり数リクエストの枠ではループが途中で止まる)。**量子化版や旧世代に静かにルーティングされる**ことがあり、ベンチ値がそのまま出るとは限らない。

よって運用は用途で切り替える。

| 対象 | バックエンド | 理由 |
|---|---|---|
| 業務コード・機密を含むリポジトリ | `ollama/fablet-code`(ローカル) | 外部送信なし、レート制限なし |
| 公開リポジトリ・個人プロジェクトの本気の作業 | クラウド無料枠(Kimi K2.6 / GLM 系) | ツール忠実度と推論力が明確に上 |
| g24 が他ユーザーに占有されている時 | クラウド無料枠 | 可用性のフォールバック |

切り替えは Admin UI で `MODEL_OPUS` を差し替えるだけで済む。**戻し忘れが最大の事故要因**なので、業務コードに入る前に必ず現在の tier 割り当てを確認する。

`MODEL_HAIKU` を 20B に振ることには副作用がある。Ollama は要求モデルを都度ロードするため、120Bと20Bが交互に呼ばれるとスワップが頻発しうる。合計 78GB は 97GB に収まるので、`OLLAMA_MAX_LOADED_MODELS=2` と十分な `keep_alive` で**両方を常駐**させ、スワップを回避する。これは旧設計10章が「同時常駐は不安定」と結論した点だが、VRAMが全空きになった今は成立する。

## 5. コンテキストと VRAM の見積もり

Claude Code は system prompt + ツール定義だけで 10〜15k トークンを消費し、実作業では会話とファイル内容が積み上がる。`num_ctx` が不足すると、プロキシは HTTP 400 を返すか、Ollama が黙って古い文脈を切り捨てて**モデルが自分の指示を忘れる**。後者は原因が見えにくいので、最初から最大を取る。

- `num_ctx 131072`(モデル上限)を第一候補とする
- gpt-oss は交互層に sliding window attention を使うため、KVキャッシュは同規模のdenseモデルより小さい。65GB + KV が 97GB に収まる見込み
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` は 190,000 ではなく **実 `num_ctx` より小さい値**(例 `120000`)に設定する。上限を超えてから圧縮しても手遅れなため
- 検証は `ollama ps` の PROCESSOR 列が `100% GPU` であること。CPUオフロードが出たら 65536 へ落とす

## 6. 評価基準の更新

旧評価は「箇条書きを乱発しないか」等のフォーマット規律が中心だった。これは Claude Code 経由では**ハーネスが保証する**ので測る意味が薄い。新しい評価軸は、ローカルモデルが**ハーネスの要求に応えられるか**である。

1. **ツール呼び出しの正確さ** — Read/Edit/Bash を正しいJSONスキーマで呼べるか。Editの `old_string` 完全一致に耐えるか(ここが 120B クラスの最大の難所)
2. **ループの完走** — 実リポジトリで「バグ修正 → テスト実行 → 失敗を読んで修正 → 再実行」を人手介入なしに閉じられるか
3. **長文脈の保持** — 30ターン後も CLAUDE.md の指示と最初の要件を保持しているか
4. **暴走しないこと** — 無限ループ、同一ファイルの反復編集、不要なファイル作成をしないか
5. **速度** — 1ターンの体感。MoE(アクティブ5.1B)なので生成は速いが、reasoning が長いと待ち時間が伸びる

合格ラインは「Fable 5 と同等」ではない。**「人手より速く、放っておいて壊れない」**である。旧評価表の項目3・4・6(トーン、拒否時のbullet、公平性)は `fablet-chat` の評価として残す。

## 7. リスクと制約

**最大リスクは tool-calling の忠実度**である。Claude Code の Edit ツールは `old_string` の完全一致を要求し、Bash はエスケープに厳格で、ツール定義は数十個ある。フロンティアモデルはこれを前提に訓練されているが、`gpt-oss:120b` がどこまで耐えるかは未知数で、**これは設計では解決できず実測するしかない**。破綻した場合の退避先は、tier を丸ごとクラウド無料枠に振り替えること(Nemotron 120B や Kimi K2 系はエージェンティック用途で訓練されている)。

次点は**プロキシの変換忠実度**。free-claude-code は Anthropic Messages ↔ OpenAI Chat を相互変換するが、thinking ブロックやツール結果の往復で情報が欠ける可能性がある。README も「Not all providers support Claude's thinking syntax」と認めている。gpt-oss は `thinking` capability を持つので、マッピングが効くかを初期に確認する。

**プロキシは Ollama のネイティブ Anthropic `/v1/messages` エンドポイントを叩く**ため、**Ollama 0.20 以上が必須**である(g24 の system 版 0.13.2 には存在しない)。`ollama/` プレフィクスのモデル解決、`OLLAMA_BASE_URL` に `/v1` を付けない、といった細かい規約もハマりどころである。

環境そのものにも罠がある。g24 の system Ollama は GPU ランナーを失っており CPU でしか動かない(ユーザー空間 Ollama で回避)。Windows 側もローカル Ollama が 11434 を占有しており、そこへ SSH トンネルを張ると **IPv4 のバインドだけ失敗して IPv6 で黙って通る**という切り分け困難な状態になる。詳細は IMPLEMENTATION.md に記録した。またこのプロキシは **`curl | sh` でインストールする第三者製ソフトウェアであり、`ANTHROPIC_AUTH_TOKEN` を含む全プロンプトが通過する**。本物のAnthropic APIキーはこの環境に置かない(プロキシ用のダミートークンのみ)。

ディスクとVRAMは当面の制約ではなくなったが、g24 は共用機なので投入前の `vram.sh` 確認は習慣として残す。

## 8. 廃止した設計(記録)

以下は旧DESIGN.mdの中心だったが、新方針では不要または有害なので廃止する。判断の履歴として残す。

- **Modelfile SYSTEM への人格焼き込みを主軸とすること** — コーディング用途で上書きされる。`fablet-chat` として周辺に降格
- **aider / Cline を主クライアントとすること** — Claude Code 本体がハーネスとして上位互換
- **「NO external tools」宣言** — ハーネスを載せると逆効果。`fablet-code` からは除去
- **自己認識をどう名乗らせるかの A案/B案** — Claude Code 経由では Claude Code の system prompt が自己認識を規定するため、争点でなくなった
- **マルチモデル協調(旧10章)を自作オーケストレータで組むこと** — tier routing とサブエージェント機構がハーネス側に既にある。クロスレビューが要るなら Claude Code の Agent ツールで足りる

## 9. 将来拡張

- `fablet-code` のベースを GLM-4.5-Air 等へ差し替え(ディスク197GB空きにより pull 可能になった)。Modelfile の `FROM` 差し替えのみ
- `fcc-codex` による Codex CLI の併用(同一プロキシで両対応)
- Discord/Telegram ボット経由でのリモートセッション(free-claude-code の同梱機能)
- 相談用 UI として Open WebUI + `fablet-chat`
