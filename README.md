# FableT

**Claude のクレジットを1円も消費せずに、Claude Code のフル機能でコーディングする環境。**

Claude Code CLI をローカルプロキシ経由で共有 GPU 機 g24 の Ollama に接続し、推論をすべてローカルモデル(gpt-oss:120b / qwen3:30b-a3b)で行う。さらに7役のエージェントが議論して方針を固めてから実装する「オフィス型」ワークフローを備える。

## なぜ FableT か

- **💰 クレジット消費ゼロ** — リクエストは Anthropic に一切届かない。`ANTHROPIC_BASE_URL` がローカルプロキシ(`127.0.0.1:8082`)を指し、認証もダミートークン。推論は全て g24 の GPU。何時間使っても、何万トークン吐いても、Claude の利用枠は減らない
- **🔒 コードが外に出ない** — 業務コード・機密リポジトリをクラウドに送信せずエージェンティックコーディングできる
- **🛠 Claude Code のフル機能** — Read/Edit/Bash/Glob などのツール群、検証ループ、サブエージェント、コンパクションはすべて本物のハーネス。モデルだけがローカル
- **🏢 オフィス型マルチエージェント** — 提案者・新規提案・クライアント・ファクトチェック・効率厨・保守運用・作業者の7役が議論し、受入条件を固定してから実装・検収する
- **⚡ 実測性能** — プレフィル約5,000 tok/s、生成150 tok/s(2026-07-11 実測)。日常応答は数秒
- **📊 ベンチ実証済み** — 350問ベンチ(2026-07-11)で fablet-code は **89.7%**。OpenAI フラッグシップ gpt-5.4(88.3%)と Claude Sonnet(86.0%)を追加コストゼロで上回った。詳細は下記「[ベンチマーク結果](#ベンチマーク結果)」

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

## 作業ディレクトリの変更

`fablet.ps1` は自分の置き場所(`Desktop\FableT`)から思考規律ファイルを読むため、**どのディレクトリから呼んでも動く**。Claude Code は「呼び出した時点のカレントディレクトリ」を作業対象として開くので、別プロジェクトで使うにはそのプロジェクトへ `cd` してからフルパスで起動するだけでよい:

```powershell
cd C:\path\to\your\project
& C:\Users\yusei\Desktop\FableT\fablet.ps1
```

毎回フルパスを打つのが面倒なら、PowerShell プロファイルに関数を1つ足す(以後どこでも `fablet` の4文字で起動できる):

```powershell
# notepad $PROFILE で開いて追記(ファイルが無ければ New-Item $PROFILE -Force で作る)
function fablet { & "C:\Users\yusei\Desktop\FableT\fablet.ps1" @args }
```

補足:

- **ゼロクレジット接続と FABLE 思考規律はどこで起動しても有効**(環境変数と `--append-system-prompt` はランチャが注入するため、場所に依存しない)
- **`/office` と7エージェントは FableT のプロジェクト設定**(`.claude\agents\` と `.claude\commands\office.md`)。他プロジェクトでも使いたい場合は、この2つをそのプロジェクトの `.claude\` へコピーする。全プロジェクト共通にしたければ `C:\Users\yusei\.claude\agents\` / `...\commands\` に置く
- セッションを開いたまま別ディレクトリも触りたいときは、セッション内で `/add-dir <パス>` を使う

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

## ベンチマーク結果

2026-07-11、独立ベンチ基盤で MMLU / GSM8K / JMMLU / MGSM / JCommonsenseQA の **350問/モデル** を機械採点(temperature=0)で比較した。詳細な方法・タスク別内訳・考察は [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) を参照。

| モデル | 正答率 | 平均レイテンシ | コスト |
|---|---:|---:|---:|
| qwen3:30b-a3b(生) | 90.6% | 9.24s | $0 |
| **fablet-code**(120B+思考規律) | **89.7%** | **2.13s** | **$0** |
| **fablet-mid**(30B+思考規律) | **88.9%** | 6.53s | **$0** |
| gpt-5.4(OpenAI フラッグシップ) | 88.3% | 0.97s | $0.229 |
| Claude Sonnet | 86.0% | 5.70s | サブスク枠 |
| gpt-5.4-mini | 80.3% | 0.84s | $0.079 |

要点:

- **FableT の2モデルは、有償クラウドのフラッグシップと統計的に同水準**(上位グループの差は±3ptの誤差範囲)。追加コストゼロでこの品質が出ることがベンチで裏付けられた
- **fablet-code(opus tier)は精度・速度の両方で FableT 内の最上位**。平均2.13秒/問はクラウド並みに速い
- GSM8K(英数学)では fablet 両モデルが **98%** で gpt-5.4(82%)を圧倒。逆に **JMMLU(日本語の専門知識)は全モデル共通の弱点**(80%前後)
- 本ベンチは単発QA形式であり、エージェンティックコーディング性能そのものではない点に注意(ツール呼び出しは別途動作検証済み)

## 理想的な使い方

ベンチ結果と実測を踏まえた推奨ワークフロー:

1. **起動は常に `.\fablet.ps1`**(素の `claude` はクレジットを消費する)。3つの `[OK]` を確認
2. **日常のコーディングは既定(fablet-mid)のまま**。ツール呼び出し中心の連続作業では応答が軽く、往復のテンポがよい
3. **難所では出し惜しみせず `/model opus`(fablet-code)**。ベンチでは精度・レイテンシとも FableT 最上位で、しかも無料。設計判断・複雑なバグ・アルゴリズムはむしろ opus を既定と考えてよい。両モデルは VRAM に同時常駐しており、**切替のロード待ちはゼロ**
4. **数学・ロジック系は安心して任せる**(GSM8K 98%)。一方 **日本語の専門知識は鵜呑みにしない**(JMMLU 80%が全モデルの上限)。ドメイン知識が要る作業は一次資料をファイルや URL でセッションに読み込ませ、モデルの記憶に頼らせないこと
5. **方針が割れる大改修だけ `/office`**。会議はローカルモデルを7回以上起こすため重い。軽微な修正に使わない
6. **終わったら g24 の後始末**: `./cleanup.sh`(VRAM 解放)。これは礼儀ではなく機能要件

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
| [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) | 性能検証結果(350問ベンチ・8モデル比較・考察) |
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
