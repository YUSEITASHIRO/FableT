# FableT

**Claude のクレジットを1円も消費せずに、Claude Code のフル機能でコーディングする環境。**

仕組みは1行で言うと——Claude Code の接続先を、Anthropic ではなく手元のプロキシに差し替え、推論を SSH 先の GPU 機で動くローカルモデルにやらせる。Claude Code のツール・検証ループ・サブエージェントはすべて本物のまま、モデルだけがローカルになる。

```
あなた → Claude Code → プロキシ(このPC:8082) → SSHトンネル → GPU機の Ollama
                        ここから先、Anthropic には一切繋がらない = クレジット消費ゼロ
```

## 使い方は3ステップ

セットアップ済みなら、毎日やることはこれだけ:

```powershell
cd C:\path\to\your-project     # ① 作業したいプロジェクトへ移動
fablet                          # ② 起動([OK]が3つ並ぶのを確認)
```

```
/office ログイン処理をセッショントークン方式に移行して    # ③ 依頼する
```

- 設計や実装をともなう依頼は `/office <依頼>` に投げる(下記「オフィスモード」)
- ちょっとした質問や確認は、普通にそのまま話しかけてよい
- 終わったら `cleanup.sh` で GPU を解放する(下記「終わったら」)

`fablet` コマンドは PowerShell プロファイルに1行足すと使えるようになる(セットアップ手順に含まれる)。

## オフィスモード(`/office`)とは

`/office <依頼>` と打つと、**7人の担当者が会議をしてから実装する**。あなたが7人を個別に操作する必要はない——依頼文を1回書けば、あとは自動で進む。`/office` はランチャがプラグインとして注入する(`--plugin-dir`)ため、**どのプロジェクトのディレクトリから起動してもコピー不要でそのまま使える**。

| 順番 | 担当 | やること |
|---|---|---|
| 1 | クライアント | あなたの依頼を「合格条件3〜5個」に翻訳して固定する |
| 2 | 提案者 / 新規提案 | 実装方針のA案と、前提の異なるB案を出す |
| 3 | ファクトチェック / 効率厨 / 保守運用 | 両案を「事実が正しいか」「過剰設計でないか」「半年後に壊れないか」で審査 |
| 4 | PM(主セッション) | 審査を踏まえてどちらかに決める |
| 5 | 作業者 | 決まった方針を実装し、テストして検証する |
| 6 | クライアント | 最初に決めた合格条件で検収する |

ポイント:

- **7人全員が同じモデル(`fable-t-o` = 120B)で発言する。** 役ごとに賢さは変わらない。役割(視点)だけが違う
- **コードを書き換えられるのは作業者だけ。** 他の6人は読み取り専用なので、会議が暴走してコードを壊すことは構造的にない
- **自明な依頼(typo修正・1行変更)は会議を自動スキップ**して直接実装される。些末な依頼で数十分待たされることはない
- ただし**フル会議は重い**(モデルを7回以上呼ぶため数十分かかることがある)。急ぎで答えだけ欲しいときは `/office` を付けずに普通に依頼してよい

### 品質は「試行回数」で買う

ローカル推論はクレジットを消費しない。だから FableT は、**一発の名答で勝とうとせず、
何度も試して機械に選ばせる**。オフィスには3段階の予算がある:

| 予算 | いつ | 何をするか |
|---|---|---|
| 即答 | typo・1行変更 | 会議を飛ばして直接実装 |
| **標準**(既定) | 通常の実装依頼 | 受入テストを先に書いてから実装し、緑を確認して検収 |
| フル | 難題・急がない依頼 | 実装を**3案**作り、受入テストの通過数で勝者を選び、批評ループで詰める |

フルを使うには依頼にそう書く: `/office じっくりで。認証をトークン方式に移行して`

どの予算でも共通の規律が1つある——**「動くはず」は完了ではない。テストの緑のログだけが完了の証拠**。
実行痕跡のない完了報告は差し戻される。

> フル予算は 120B を何度も呼ぶ。GPU が空いていないと激遅になるので、起動時の `[OK] GPU 空き` 行を見てから使うこと。

## モデルは実質2つ + 会議用1つ

| 名前 | 実体 | いつ使われるか |
|---|---|---|
| `fable-t-mid` | qwen3:30b-a3b(30B) | **既定。** 普通に話しかけるとこれが応える。速い |
| `fable-t` | gpt-oss:120b(120B) | 難しい設計判断・複雑なバグ向け。賢い |
| `fable-t-o` | `fable-t` と同じ重み | `/office` の7役が自動で使う。**自分で選ぶ必要はない** |

- **選べるのはこの3つだけ。** 起動時に `fablet.settings.json` の allowlist(`availableModels` + `enforceAvailableModels`)が適用され、`Opus` / `Sonnet` / `Haiku` といった紛らわしい組込みエントリは一覧から消える
- 切替は `/model` を開いて一覧から選ぶ。名前で指定する場合は一覧と同じ完全なIDで: `/model anthropic/ollama/fable-t`(120Bへ)/ `/model anthropic/ollama/fable-t-mid`(30Bへ戻す)。短い名前(`ollama/fable-t` 等)は allowlist に一致せず Default に落ちるので使わない
- 組込みの `Default` 行だけは消せず、表示上は Opus 4.8 のままになることがある。**ただし fablet セッションは接続先自体がローカルプロキシなので、どれを選んでもクレジットは消費されない**(Default は opus 枠 = `fable-t` に変換される)
- この制限は `fablet` で起動したセッション限り。素の `claude`(本物のAnthropic)には影響しない
- 両モデルは GPU に同時常駐するので、切替でロード待ちは発生しない(96GB VRAM の場合)

## 終わったら

GPU 機は共用である。**使い終わったら必ず解放する**:

```bash
./cleanup.sh          # ロード中モデルをアンロード(VRAM 解放)。通常はこれだけ
./cleanup.sh --stop   # 長期間使わないなら Ollama サーバごと停止
```

使う前の空き確認は `./vram.sh`。

## セットアップ(初回のみ)

### 前提

- Windows 11 + PowerShell、[Claude Code CLI](https://docs.claude.com/claude-code)、`uv`
- GPU を積んだ Linux 機への **SSH 鍵認証**アクセス
- GPU の目安: 120B+30B 同時常駐なら 90GiB 前後、30B のみなら 20GiB 程度でも可(後述)

### 読み替え規約

このリポジトリのドキュメントとスクリプトに出てくる次の2つは**作者の環境の実値**である:

- **`g24`** — 作者の GPU 機の SSH エイリアス名。あなたの `~/.ssh/config` にも **同じ名前 `g24` でエイリアスを作るのが最も手軽**(スクリプト無修正で動く)。別名にする場合は `fablet.ps1` / `cleanup.sh` / `vram.sh` 内の `g24` を置換する
- **`C:\Users\yusei\Desktop\FableT`**(等のパス) — 作者のクローン先。自分のパスに読み替える

### 手順

1. このリポジトリを clone する
2. [IMPLEMENTATION.md](IMPLEMENTATION.md) の Phase 0〜5 を順に実行する(GPU 機へのユーザー空間 Ollama 導入 → モデル作成 → プロキシ導入・設定)
3. PowerShell プロファイルに起動関数を足す:

```powershell
# notepad $PROFILE で開いて追記(ファイルが無ければ New-Item $PROFILE -Force で作る)
function fablet { & "C:\path\to\FableT\fablet.ps1" @args }
```

以後は「使い方は3ステップ」の通り。`fablet` は SSH トンネルとプロキシの起動・検査をすべて自動で行うので、手動で立ち上げるものはない。唯一の例外は GPU 機側の Ollama が落ちているときで、その場合は起動時に赤字で復旧コマンドが表示される:

```powershell
ssh g24 "setsid nohup ~/ollama-dist/start.sh > ~/ollama-dist/server.log 2>&1 < /dev/null &"
```

### VRAM が足りない場合

このPC(Windows側)の `~/.fcc/.env` にある3行がモデルの割り当てである:

```
MODEL_OPUS=ollama/fable-t
MODEL_SONNET=ollama/fable-t-mid
MODEL_HAIKU=ollama/fable-t-mid
```

GPU が小さい場合は `MODEL_OPUS` も `ollama/fable-t-mid` にすれば 120B を持たずに済む(`plugin/agents/*.md` の `model:` も `ollama/fable-t-mid` 相当に合わせる)。品質は落ちるがクレジットゼロの原則は変わらない。

## 性能(実測)

350問ベンチ(MMLU / GSM8K / JMMLU / MGSM / JCommonsenseQA、機械採点、2026-07-11)での比較。詳細は [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md):

| モデル | 正答率 | 平均レイテンシ | コスト |
|---|---:|---:|---:|
| **fable-t**(120B) | **89.7%** | **2.13s** | **$0** |
| **fable-t-mid**(30B) | **88.9%** | 6.53s | **$0** |
| gpt-5.4(OpenAI フラッグシップ) | 88.3% | 0.97s | $0.229 |
| Claude Sonnet | 86.0% | 5.70s | サブスク枠 |
| gpt-5.4-mini | 80.3% | 0.84s | $0.079 |

- 有償クラウドのフラッグシップと統計的に同水準(上位の差は±3ptの誤差範囲)を、追加コストゼロで出せている
- 数学は特に強い(GSM8K 98%)。**日本語の専門知識は弱い**(JMMLU 80%前後)ので、ドメイン知識が要る作業は一次資料をセッションに読み込ませること
- 単発QAのベンチであり、エージェンティックコーディング性能そのものではない点に注意

**エージェント性能**(実際にリポジトリを直せるか)は [bench/agentic](bench/agentic/) で測る。
壊れたコードと隠しテストを与えて機械採点し、`pass@1`(1回で通る確率)と `pass@k`(k回のうち
1回でも通る確率)を出す。FableT の勝ち筋は「**pass@k がクラウドの pass@1 を上回る**」ことで、
無料ゆえに k を好きなだけ上げられるのが根拠である。

```powershell
cd bench\agentic
.\run.ps1 -Agent fablet -K 3      # ローカル・無料。GPU が空いているときに
```

## クレジットについて

| 起動方法 | 接続先 | クレジット消費 |
|---|---|---|
| `fablet` | ローカルプロキシ → GPU機 | **なし(ゼロ)** |
| 素の `claude` | 本物の Anthropic API | **あり** |

見分け方: `/model` を開いて `ollama/fable-t` 等が一覧に並んでいればローカル(消費なし)。並んでいなければ Anthropic に繋がっている(消費あり)。

## 注意事項

- **GPU 機は共用。後始末(`./cleanup.sh`)は必須。** 一時ファイルを GPU 機に置いたら消す。恒常的に必要なデータは GPU 機に置かず、手元へ scp して参照する
- **本物の API キーをこの環境に置かない。** プロキシ(fcc)は第三者製で全プロンプトが通過する。`ANTHROPIC_AUTH_TOKEN` はダミー(`fablet-local`)のまま使う
- **fcc の更新はコミット固定で**(`uv tool install "git+…@<sha>"`、現在 `1278d008` に固定)。全プロンプトが通る位置のソフトを git main 追従にしない
- **初回応答は10〜20秒待つ**(モデルのGPUロード)。2回目以降は速い
- **トンネルと fcc-server のプロセスは使用後も残る**(次回起動が速い)。完全に落とすなら fcc-server の窓を閉じ、ssh プロセスを終了する
- **疎通確認は `localhost` ではなく `127.0.0.1` で。** localhost は IPv6 に逃げて別の Ollama を見ることがある

## 困ったら

| 症状 | 対処 |
|---|---|
| `[NG] Ollama` のまま | GPU機側のサーバ停止。セットアップ末尾の復旧コマンドを実行 |
| `[NG] fcc-server` のまま | 別ターミナルで `fcc-server` を直接実行しエラーを読む |
| 応答が異常に遅い | `ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama ps"` で `100% GPU` を確認 |
| モデルが見つからない | トンネルの先が違う。`127.0.0.1` と `localhost` で `/api/tags` を比較 |

詳細な対照表は [IMPLEMENTATION.md](IMPLEMENTATION.md) Phase 7。

## ドキュメント

| ファイル | 内容 |
|---|---|
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | セットアップ手順書(Phase 0〜5)とトラブルシューティング |
| [DESIGN.md](DESIGN.md) | 設計の経緯とアーキテクチャの詳細 |
| [OFFICE.md](OFFICE.md) | オフィスモードの設計と監査記録 |
| [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) | 350問ベンチ(単発QA)の方法・内訳・考察 |
| [bench/agentic/](bench/agentic/) | エージェント性能(pass@k)を測るベンチと、その土俵の限界 |
| [CLAUDE.md](CLAUDE.md) | セッションのプロジェクト規約 |
| [FABLE.md](FABLE.md) | 思考規律の原典。抽出物 `fable-coding.txt` が起動時に system prompt へ注入される |

> DESIGN.md / IMPLEMENTATION.md / OFFICE.md は作者自身の開発ログとして書かれている。`g24` やパスの実値は「読み替え規約」に従って自分の環境に読み替えること。

## 動作環境(作者の実機)

- Windows 11 + Claude Code CLI + uv + 鍵認証済みの `ssh g24`
- GPU機: RTX PRO 6000(96GB)、ユーザー空間 Ollama **0.20 以上**(`~/ollama-dist`、`:11500`、flash attention + KV q8_0)
- モデル: `fable-t`(gpt-oss:120b, 131k ctx, **Reasoning: high** 固定)/ `fable-t-mid`(qwen3:30b-a3b, 64k ctx)/ `fable-t-o`(`fable-t`と同重み・`/office`用)/ `fablet-fast`(gpt-oss:20b・予備)/ `fablet-chat`(人格入り・相談用)
- **共用機なので VRAM は常に空いているとは限らない。** 他ユーザーが握っていると 120B は CPU へ
  スピルして激遅になる。起動時に空きを表示するので、赤/黄の警告が出たら 30B で作業するか待つこと
