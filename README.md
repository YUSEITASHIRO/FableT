# FableT

**Claude のクレジットを1円も消費せずに、Claude Code のフル機能でコーディングする環境。**

Claude Code CLI をローカルプロキシ経由で GPU 機の Ollama に接続し、推論をすべてローカルモデル(gpt-oss:120b / qwen3:30b-a3b)で行う。さらに7役のエージェントが議論して方針を固めてから実装する「オフィス型」ワークフローを備える。

## はじめに(初めての方へ)

FableT は「Windows PC(Claude Code を動かす手元機)+ SSH でつながる GPU を積んだ Linux 機」という作者自身の構成をもとに作られた実例である。ドキュメント中に出てくる次の2つは**作者の環境の実値**であり、あなたの環境に読み替える必要がある:

- **`g24`** — 作者が自分の `~/.ssh/config` に張った GPU 機への SSH エイリアス名。**最も手軽なのは、あなた自身の GPU 機にも同じ名前 `g24` でエイリアスを作ることである**(スクリプトを一切書き換えずに済む)。別の名前にしたい場合は `fablet.ps1` / `cleanup.sh` / `vram.sh` 内の `g24` という文字列をあなたのエイリアス名に置き換えればよい
- **`C:\Users\yusei\Desktop\FableT`** — 作者の実際のクローン先パス。あなたが `git clone` した先のパスに読み替えること

前提条件:

- Windows 11 + PowerShell、[Claude Code CLI](https://docs.claude.com/claude-code) インストール済み
- GPU を持つ Linux 機への **SSH 鍵認証アクセス**(パスワード認証不可。`~/.ssh/config` に `Host g24` エイリアスを用意)
- そのLinux機に **Ollama 0.20 以上をユーザー空間で導入**できること(sudo不要な手順が [IMPLEMENTATION.md](IMPLEMENTATION.md) Phase 2 にある)
- 目安 VRAM: `fable-t`(120B相当)単体なら **70GiB 前後**、`fable-t-mid`(30B相当)と同時常駐させるなら **90GiB 前後**。作者の実機は RTX PRO 6000(96GB)だが、これより小さいGPUでも **`fable-t-mid` 系(30B以下)のみを opus/sonnet/haiku 全tierに割り当てる**構成にすれば動く(下記「モデル構成」参照)

**初回セットアップの全手順**(SSHトンネル、Ollamaのユーザー空間導入、モデル作成、プロキシ設定)は [IMPLEMENTATION.md](IMPLEMENTATION.md) の Phase 0〜5 にまとまっている。以下のクイックスタートは、そのセットアップが完了した後の**日常の起動手順**である。

## なぜ FableT か

- **💰 クレジット消費ゼロ** — リクエストは Anthropic に一切届かない。`ANTHROPIC_BASE_URL` がローカルプロキシ(`127.0.0.1:8082`)を指し、認証もダミートークン。推論は全て g24 の GPU。何時間使っても、何万トークン吐いても、Claude の利用枠は減らない
- **🔒 コードが外に出ない** — 業務コード・機密リポジトリをクラウドに送信せずエージェンティックコーディングできる
- **🛠 Claude Code のフル機能** — Read/Edit/Bash/Glob などのツール群、検証ループ、サブエージェント、コンパクションはすべて本物のハーネス。モデルだけがローカル
- **🏢 オフィス型マルチエージェント** — 提案者・新規提案・クライアント・ファクトチェック・効率厨・保守運用・作業者の7役が議論し、受入条件を固定してから実装・検収する
- **⚡ 実測性能** — プレフィル約5,000 tok/s、生成150 tok/s(2026-07-11 実測)。日常応答は数秒
- **📊 ベンチ実証済み** — 350問ベンチ(2026-07-11)で fable-t は **89.7%**。OpenAI フラッグシップ gpt-5.4(88.3%)と Claude Sonnet(86.0%)を追加コストゼロで上回った。詳細は下記「[ベンチマーク結果](#ベンチマーク結果)」

## クイックスタート

初回だけリポジトリを取得する:

```powershell
git clone https://github.com/YUSEITASHIRO/FableT.git
```

以後の起動は、**使いたいプロジェクトのディレクトリに `cd` してから、クローンした FableT の `fablet.ps1` をフルパスで呼ぶ**のが基本の使い方である(FableT は「どこか一箇所に置いて、そこから全プロジェクトを起動する司令塔」として使う設計):

```powershell
cd C:\path\to\your-project
& C:\path\to\FableT\fablet.ps1
```

毎回フルパスを打つのが面倒なら、PowerShell プロファイルに関数を1つ足しておく(以後どのプロジェクトでも `fablet` の4文字で起動できる):

```powershell
# notepad $PROFILE で開いて追記(ファイルが無ければ New-Item $PROFILE -Force で作る)
function fablet { & "C:\path\to\FableT\fablet.ps1" @args }
```

```powershell
cd C:\path\to\your-project
fablet
```

起動すると SSHトンネル(GPU機へ)と fcc-server(プロキシ)を自動起動・自動検査し、FABLE.md の思考規律を注入した Claude Code セッションが立ち上がる。3つの `[OK]` が並べば準備完了。**セッションが開いたら、まず `/office <依頼>` から使い始めるのが基本の使い方**(詳細は下記「オフィス会議モード」)。

```
[OK] Ollama (g24 :11500 via tunnel)
[OK] fable-t visible
[OK] fcc-server (:8082)
```

唯一の手動復旧ポイントは GPU機側の Ollama が落ちている場合(起動時に赤字で指摘される):

```powershell
ssh g24 "setsid nohup ~/ollama-dist/start.sh > ~/ollama-dist/server.log 2>&1 < /dev/null &"
```

補足:

- **ゼロクレジット接続と FABLE 思考規律はどこで起動しても有効**(環境変数と `--append-system-prompt` はランチャが注入するため、カレントディレクトリに依存しない)
- **`/office` と7エージェントは FableT のプロジェクト設定**(`.claude\agents\` と `.claude\commands\office.md`)。作業先プロジェクトでも使うには、この2つをそのプロジェクトの `.claude\` へコピーする。全プロジェクト共通にしたければユーザーホームの `.claude\agents\` / `.claude\commands\` に置く
- セッションを開いたまま別ディレクトリも触りたいときは、セッション内で `/add-dir <パス>` を使う

## モデル構成 — 4つの名前

Claude Code の `/model` ピッカーは仕様上 `Opus` / `Sonnet` / `Haiku` という組込みラベルを常に表示し、これを非表示にする設定は存在しない(調査確認済み)。そこで FableT は、**中身が何であるかを紛らわしくしないために、tier とは別に固有の名前を4つ用意する**:

| モデル名 | 実体 | 呼ばれる場面 |
|---|---|---|
| `fable-t` | gpt-oss:120b | 主セッションの opus tier。難しい設計判断・複雑な実装 |
| `fable-t-mid` | qwen3:30b-a3b(MoE) | 主セッションの sonnet / haiku tier(既定)。日常のコーディング。速い |
| `fable-t-o` | `fable-t` と同じ重み | `/office` 会議の提案者・新規提案・作業者(書込み権限を持つ役) |
| `fable-t-mid-o` | `fable-t-mid` と同じ重み | `/office` 会議のクライアント・ファクトチェック・効率厨・保守運用(審査役) |

`-o` は tier 経由ではなく、`.claude/agents/*.md` の `model:` にゲートウェイ名(`ollama/fable-t-o` 等)を直書きして呼ばれる。`ollama cp` で重みを共有した別名タグなので、追加のディスク・VRAM消費はない。**あなたが `/model` で直接選ぶのは `fable-t` / `fable-t-mid` の2つ**で、`-o` の2つは `/office` 実行中に裏で自動的に使われる。

セッション内での切替:

```
/model opus                 # 難所の前に120Bへ
/model sonnet               # 終わったら戻す
/model ollama/fable-t       # ゲートウェイのモデル名を直接指定してもよい(Opus/Sonnet表記より紛らわしくない)
```

両モデル合計 ~87GB は 96GB VRAM に同時常駐でき、切替でロード待ちは発生しない(作者の実機基準)。tier の割り当ては `~/.fcc/.env`(GPU機側に自分で作成する設定ファイル。リポジトリには含まれない)で一元管理される:

```
MODEL_OPUS=ollama/fable-t
MODEL_SONNET=ollama/fable-t-mid
MODEL_HAIKU=ollama/fable-t-mid
```

**VRAMが90GBに満たない場合**は、`MODEL_OPUS` も `fable-t-mid` に振れば、120Bモデルを常駐させずに済む。速度は落ちるが、追加コストゼロの原則は変わらない。

## ベンチマーク結果

2026-07-11、独立ベンチ基盤で MMLU / GSM8K / JMMLU / MGSM / JCommonsenseQA の **350問/モデル** を機械採点(temperature=0)で比較した。詳細な方法・タスク別内訳・考察は [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) を参照。

| モデル | 正答率 | 平均レイテンシ | コスト |
|---|---:|---:|---:|
| qwen3:30b-a3b(生) | 90.6% | 9.24s | $0 |
| **fable-t**(120B+思考規律) | **89.7%** | **2.13s** | **$0** |
| **fable-t-mid**(30B+思考規律) | **88.9%** | 6.53s | **$0** |
| gpt-5.4(OpenAI フラッグシップ) | 88.3% | 0.97s | $0.229 |
| Claude Sonnet | 86.0% | 5.70s | サブスク枠 |
| gpt-5.4-mini | 80.3% | 0.84s | $0.079 |

要点:

- **FableT の2モデルは、有償クラウドのフラッグシップと統計的に同水準**(上位グループの差は±3ptの誤差範囲)。追加コストゼロでこの品質が出ることがベンチで裏付けられた
- **fable-t(opus tier)は精度・速度の両方で FableT 内の最上位**。平均2.13秒/問はクラウド並みに速い
- GSM8K(英数学)では FableT の両モデルが **98%** で gpt-5.4(82%)を圧倒。逆に **JMMLU(日本語の専門知識)は全モデル共通の弱点**(80%前後)
- 本ベンチは単発QA形式であり、エージェンティックコーディング性能そのものではない点に注意(ツール呼び出しは別途動作検証済み)

## オフィス会議モード(基本の使い方)

FableT の基本ワークフローは、**作業したいプロジェクトへ `cd` → `fablet` 起動 → `/office <依頼>`** である。方針が割れうる依頼はもちろん、日常の実装依頼もまず `/office` に投げるのが既定だと考えてよい:

```powershell
cd C:\path\to\your-project
fablet
```

```
/office ログイン処理をセッショントークン方式に移行して
```

進行(詳細は [.claude/commands/office.md](.claude/commands/office.md)):

1. **クライアント**(`fable-t-mid-o`)が受入条件を3〜5個に固定(以後の唯一の合否基準)
2. **提案者**(`fable-t-o`)が方針A、**新規提案**(`fable-t-o`)が前提の異なる対案Bを提出
3. **ファクトチェック**・**効率厨**・**保守運用**(いずれも `fable-t-mid-o`)が両案を審査
4. PM(主セッション)が統合判断 → **作業者**(`fable-t-o`)が実装と検証ループ → クライアントが検収

書込み権限を持つのは作業者だけ。レビュー役は読取専用なので、構造的に暴走できない。**自明なタスク(typo修正・1行変更など)は会議を自動省略し、PM(主セッション)が直接実装する**ので、些末な依頼まで会議を挟んで待たされることはない。

⏱ **注意: フル会議は重い。** 1回でローカルモデルを7回以上起こすため、軽微とは言えない修正でも数十分かかることがある。急ぎで結論が要る/自明と分かっている作業は、`/office` を使わず直接依頼してよい。

## 理想的な使い方

ベンチ結果と実測を踏まえた推奨ワークフロー:

1. **作業対象のプロジェクトディレクトリへ `cd` してから `fablet` を起動する**(FableTのフォルダの中で作業しない)。3つの `[OK]` を確認したら `/office <依頼>` から始める
2. **会議のPM判断後、作業者(`fable-t-o`)は実質 opus 相当の重さで動く**。ベンチでは精度・レイテンシともFableT最上位。設計判断・複雑なバグ・アルゴリズムはここに任せてよい
3. **数学・ロジック系は安心して任せる**(GSM8K 98%)。一方 **日本語の専門知識は鵜呑みにしない**(JMMLU 80%が全モデルの上限)。ドメイン知識が要る作業は一次資料をファイルや URL でセッションに読み込ませ、モデルの記憶に頼らせないこと
4. **本当に自明な作業(typo・1行変更等)は会議が自動省略される**ので、律儀に毎回 `/office` を使わなくても構造は壊れない。迷ったら `/office` に投げるのが安全側
5. **終わったら GPU機の後始末**: `./cleanup.sh`(VRAM 解放)。これは礼儀ではなく機能要件

## クレジットについて(重要)

| 起動方法 | 接続先 | クレジット消費 |
|---|---|---|
| `.\fablet.ps1` | ローカルプロキシ → g24 | **なし(ゼロ)** |
| 素の `claude` | 本物の Anthropic API | **あり** |

- 見分け方: セッション内で `/model` を開き、`ollama/fable-t` 等が並んでいればローカル(消費なし)。Opus/Sonnet/Haiku の正規モデルだけなら Anthropic(消費あり)
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

> DESIGN.md / IMPLEMENTATION.md / OFFICE.md は作者自身の開発ログとして書かれている。`g24` やパスの実値は作者の環境のものなので、読者は自分の環境に読み替えること。初めてのセットアップは、まず本README「はじめに」を読んでから進めるとよい。

## アーキテクチャ

```
[Windows PC]                        [GPU機(例: SSHエイリアス g24。作者実機: RTX PRO 6000 96GB)]

  Claude Code CLI (fablet.ps1 が起動・環境注入)
       │ ANTHROPIC_BASE_URL=http://127.0.0.1:8082 (ダミートークン)
       ▼
  fcc-server (Anthropic API 互換プロキシ・自動起動)
       │ tier 解決: opus → fable-t(120B) / sonnet,haiku → fable-t-mid(30B)
       ▼
  127.0.0.1:11500 ──[SSHトンネル・自動起動]──▶ ユーザー空間 Ollama (:11500)
```

## 動作環境

- Windows 11 + Claude Code CLI + uv + 鍵認証済みの `ssh g24`
- g24: ユーザー空間 Ollama **0.20 以上**(`~/ollama-dist`、`:11500`、flash attention + KV q8_0)
- モデル: `fable-t`(gpt-oss:120b, 131k ctx)/ `fable-t-mid`(qwen3:30b-a3b, 64k ctx)/ `fable-t-o`・`fable-t-mid-o`(同重み・`/office`専用エイリアス)/ `fablet-fast`(gpt-oss:20b, 64k ctx・予備)/ `fablet-chat`(人格入り・相談用)
