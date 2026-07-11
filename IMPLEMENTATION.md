# FableT 実装手順書 — Claude Code × ローカル gpt-oss:120b

対象: Windows PC(プロキシとClaude Code)+ g24 (RTX PRO 6000 96GB / Ollama 0.13.2)
前提ドキュメント: [DESIGN.md](DESIGN.md)

> **本書は作者自身の開発ログである。** `g24` は作者が自分の GPU 機に張った SSH エイリアス名、`C:\Users\yusei\...` 等のパスやVRAM値は作者の実環境の実例であり、読者は自分の環境の値に読み替えること。初めてセットアップする場合は、まず [README.md](README.md) の「はじめに」を読むこと。

成果物一覧:

| ファイル / 成果物 | 場所 | 役割 |
|---|---|---|
| `Modelfile.fable-t` | ローカル → g24 | `fable-t` の定義(SYSTEMなし・131k ctx) |
| `Modelfile.fable-t-mid` | ローカル → g24 | `fable-t-mid` の定義(SYSTEMなし・65k ctx) |
| `Modelfile.fast` | ローカル → g24 | `fablet-fast` の定義(Haiku tier用) |
| `fable-t` / `fable-t-mid` / `fable-t-o` / `fable-t-mid-o` / `fablet-fast` | g24 | Ollamaモデル(`-o` は `ollama cp` による別名タグ) |
| `fcc-server` | Windows | Anthropic API 互換プロキシ |
| `~/.fcc/.env` | Windows | ルーティングと接続設定 |
| `fablet-chat`(旧 `fablet`) | g24 | チャット用途に残す人格モデル |
| `cleanup.sh` | ローカル | 使用後の RAM/VRAM 解放・派生モデル削除(Phase 9) |

旧成果物の `fable-system.txt` / `build-modelfile.sh` / `fable-*.txt` は `fablet-chat` の再生成に使うので**削除しない**。

---

## ⚠️ 前提: system の Ollama は GPU を使えない(2026-07-09 発覚・回避済み)

**g24 の system Ollama(`/usr/local/bin/ollama`, `:11434`)は GPU を一切使えない。** FableT は代わりに**ユーザー空間 Ollama(`~/ollama-dist`, `:11500`)**を使う。以下は原因と回避手順の記録である。**すべてのコマンドで `OLLAMA_HOST=127.0.0.1:11500` を指定すること。** 忘れると壊れた方に繋がる。

### 症状

```
$ ollama ps
NAME                  SIZE     PROCESSOR    CONTEXT
fable-t:latest    70 GB    100% CPU     131072      ← GPU に載っていない
```

VRAM は 90GB 空いており、`num_ctx` の問題ではない(既定 8192 の `gpt-oss:120b` でも `100% CPU`)。原因は特定済みで、**Ollama の GPU ランナーライブラリが消えている**。

```
$ ls /usr/local/lib/ollama
（空）

$ OLLAMA_DEBUG=1 ollama serve
msg="inference compute" id=cpu library=cpu ...      ← CUDA デバイスが検出されない
```

GPU ドライバ自体は正常(`libcuda.so.1` 存在、driver 570.133.07、compute cap 12.0、`/dev/nvidia*` は `crw-rw-rw-`)。Ollama に同梱される CUDA ランナー(`libggml-cuda.so` 等)だけが `/usr/local/lib/ollama` から失われている。**ディスクが 100% に達した際の容量回収で削除された可能性が高い。**

この状態では推論は CPU で走り、`gpt-oss:120b` は RAM を 64GB 占有して 1 応答に数分かかる。sudo での再インストールが本来の修復だが、**`sudo` にパスワードが要り、共用機のシステム全体に影響する**ため採らない。

### 採用した回避策(B案): ユーザー空間 Ollama

`/usr/local/bin/ollama` のバイナリ自体は無傷で、失われたのは `OLLAMA_LIBRARY_PATH` が指すランナー群だけである。したがって**配布物を自分のホームに展開し、そこから起動すれば sudo なしで GPU が使える**。

**バージョン要件: Ollama 0.20 以上。** fcc は Ollama の**ネイティブ Anthropic `/v1/messages` エンドポイント**を叩く。system の 0.13.2 にはこれが無く `404 page not found` を返す。0.20.2 で存在を確認済み。

```bash
# 2-a. 配布物を展開(v0.20.2。約4.7GB)
#      新しいリリースの資産は .tar.zst 形式。g24 に zstd バイナリは無いが tar --zstd は
#      それを呼ぶだけなので使えない。python の zstandard で展開する。
ssh g24 "python3 -m pip install --user --quiet zstandard"
ssh g24 "mkdir -p ~/ollama-dist && cd ~/ollama-dist \
  && curl -fsSL -o ollama.tar.zst https://github.com/ollama/ollama/releases/download/v0.20.2/ollama-linux-amd64.tar.zst \
  && python3 -c \"
import zstandard, tarfile
with open('ollama.tar.zst','rb') as f:
    with zstandard.ZstdDecompressor().stream_reader(f) as r:
        with tarfile.open(fileobj=r, mode='r|') as t: t.extractall('.')
\" && rm -f ollama.tar.zst && ls lib/ollama | grep cuda"
```

`lib/ollama/cuda_v12` と `cuda_v13` が現れれば良い。**`ollama --version` は稼働中サーバの値を返すので、入れたバイナリの版を確かめる用途には使えない。** `curl :11500/api/version` で見る。

```bash
# 2-b. モデルストアを組む。blob は共有ディレクトリへの symlink(追加ディスク消費ゼロ)
ssh g24 'M=$HOME/ollama-models; SRC=/usr/share/ollama/.ollama/models
  mkdir -p $M/blobs
  cp -r $SRC/manifests $M/
  ln -sfn $SRC/blobs/* $M/blobs/
  du -sh --exclude=blobs $M'      # → 84K
```

blob は他ユーザー所有(0644)なのでハードリンクは `protected_hardlinks` に阻まれうる。**symlink を使う。**同一パーティション上で 119GB の重みをそのまま再利用でき、`ollama create` で作る新レイヤーだけが自分のホームに書かれる。

```bash
# 2-c. 起動スクリプトを置いて setsid で切り離す
ssh g24 "cat > ~/ollama-dist/start.sh << 'EOS'
#!/bin/bash
export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=\$HOME/ollama-models
export OLLAMA_KEEP_ALIVE=2h
export OLLAMA_MAX_LOADED_MODELS=2
exec \$HOME/ollama-dist/bin/ollama serve
EOS
chmod +x ~/ollama-dist/start.sh
setsid nohup ~/ollama-dist/start.sh > ~/ollama-dist/server.log 2>&1 < /dev/null &"
```

> `ssh` 越しに `nohup ... &` だけで起こすと、セッション終了に巻き込まれて起動しないことがある。`setsid` で確実に切り離す。また `pkill -f 'ollama serve'` は**自分の ssh コマンド文字列にマッチして自滅する**ので、`'[o]llama serve'` と書く。

### 検証(2026-07-09 実測)

```bash
ssh g24 "curl -s http://127.0.0.1:11500/api/version"                            # → {"version":"0.20.2"}
ssh g24 "grep 'inference compute' ~/ollama-dist/server.log | tail -1"
# → library=CUDA compute=12.0 ... total="95.6 GiB" available="95.0 GiB"   ✅ GPU 認識

ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama run fable-t 'Reply with exactly: ready'; \
         OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama ps"
# → fable-t  70 GB  100% GPU  131072      ✅ 131k ctx が全載せ(VRAM 67GB 使用 / 30GB 空き)
# → ロード 約18秒

ssh g24 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:11500/v1/messages -d '{}'"
# → 400 (=エンドポイント存在)。404 なら Ollama が古い
```

tool-calling も API レベルで確認済み(`/api/chat` に `tools` を渡すと正しい `tool_calls` を返す)。

なお共用機には他ユーザー(`ykanzaki`)の `ollama serve` プロセスが 2月から 3つ残留している。ポート衝突には注意する。

---

## Phase 0: 事前確認(5分)

```bash
ssh g24 "nvidia-smi --query-gpu=memory.free --format=csv,noheader; df -h / | tail -1"
ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama show gpt-oss:120b | head -12"
ssh g24 "pgrep -u \$(whoami) -f 'bin/ollama serve' >/dev/null && echo 'user-space ollama: 稼働中' || echo 'user-space ollama: 停止中 → ~/ollama-dist/start.sh'"
```

チェックポイント:

- 空きVRAM **≥ 80 GiB**(120B + 20B の同時常駐を狙うため。120B単体なら70GiBで足りる)
- `Capabilities` に **`tools`** があること。これが無いモデルでは Claude Code は動かない
- Claude Code CLI がローカルにインストール済みであること(`claude --version`)
- ユーザー空間 Ollama が `:11500` で稼働していること(停止していたら `setsid nohup ~/ollama-dist/start.sh > ~/ollama-dist/server.log 2>&1 < /dev/null &`)

## Phase 1: 既存 `fablet` の改名(2分)

旧方針の成果物を退避し、名前を用途に合わせる。レイヤーは共有されるのでディスク消費はほぼゼロ。

```bash
ssh g24 "ollama cp fablet fablet-chat && ollama rm fablet && ollama list | grep fablet"
```

> `fablet` という名前を空けておく。Claude Code 用のモデルと人格モデルが同名だと事故る。

## Phase 2: `fable-t` の作成(10分)

**SYSTEM を持たないこと**が要件である。Claude Code が自前の system prompt を送るため、Modelfile 側の SYSTEM は二重定義になり、特に旧 `fablet` の「You have NO external tools」はツール呼び出しを阻害する(DESIGN.md 3章)。

### 2-1. Modelfile を書く

```bash
cd /c/Users/yusei/Desktop/FableT

cat > Modelfile.fable-t << 'EOF'
FROM gpt-oss:120b

# SYSTEM は意図的に定義しない。Claude Code が system prompt を供給する。

PARAMETER num_ctx 131072
PARAMETER temperature 1.0
EOF

cat > Modelfile.fable-t-mid << 'EOF'
FROM qwen3:30b-a3b

# SYSTEM は意図的に定義しない。Claude Code が system prompt を供給する。

PARAMETER num_ctx 65536
PARAMETER temperature 0.7
EOF

cat > Modelfile.fast << 'EOF'
FROM gpt-oss:20b

# 32768 では Claude Code の Haiku tier 内部処理が黙って切り捨てられうる(OFFICE.md P4)
PARAMETER num_ctx 65536
PARAMETER temperature 1.0
EOF
```

### 2-2. 転送してビルド

ユーザー空間 Ollama(`:11500`)に対して作成する。**命名規則**: 主セッション(opus/sonnet/haiku tier)は `fable-t` / `fable-t-mid`、`/office` 会議のサブエージェント専用に同じ重みを `-o` サフィックスで複製する(`ollama cp` はレイヤーを共有するため追加ディスク消費ゼロ)。

```bash
ssh g24 "mkdir -p ~/fablet"
scp Modelfile.fable-t Modelfile.fable-t-mid Modelfile.fast g24:~/fablet/
ssh g24 "export OLLAMA_HOST=127.0.0.1:11500; cd ~/fablet \
  && ~/ollama-dist/bin/ollama create fable-t -f Modelfile.fable-t \
  && ~/ollama-dist/bin/ollama create fable-t-mid -f Modelfile.fable-t-mid \
  && ~/ollama-dist/bin/ollama create fablet-fast -f Modelfile.fast \
  && ~/ollama-dist/bin/ollama cp fable-t fable-t-o \
  && ~/ollama-dist/bin/ollama cp fable-t-mid fable-t-mid-o \
  && ~/ollama-dist/bin/ollama list | grep fable"
```

### 2-3. SYSTEM が空であることの確認

新方針の要である。ここが空でないと Claude Code の system prompt と二重になる。

```bash
ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama show fable-t --system"   # → 何も出ない
ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama show fablet-chat --system | head -3"  # → 人格プロンプト
```

### 2-4. VRAM 実測(最重要チェック)

131k context の KV キャッシュが VRAM に収まるかを確認する。CPU オフロードが出ると 1 応答に数分かかり実用にならない。

```bash
ssh g24 "export OLLAMA_HOST=127.0.0.1:11500; ~/ollama-dist/bin/ollama run fable-t 'Say only: ready'; ~/ollama-dist/bin/ollama ps"
```

チェックポイント: PROCESSOR 列が **`100% GPU`**。`XX%/XX% CPU/GPU` と出たら `num_ctx` を 131072 → 65536 に下げて 2-1 からやり直す。

> 2026-07-09 実測では `70 GB / 100% GPU / CONTEXT 131072`、VRAM 67GB 使用・30GB 空き。同時常駐(`OLLAMA_MAX_LOADED_MODELS=2`)は `start.sh` で既に設定済みで、`fablet-fast`(13GB)を足しても 95.6GiB に収まる。

## Phase 3: SSH ポートフォワード(1分)

Windows 側の `127.0.0.1:11500` を、g24 のユーザー空間 Ollama(`:11500`)に繋ぐ。**このトンネルは作業中ずっと張っておく**(別ターミナルで実行し、閉じない)。

```bash
ssh -o ExitOnForwardFailure=yes -N -L 127.0.0.1:11500:localhost:11500 g24
```

> ⚠️ **手元のポートに 11434 を使ってはならない。** Windows にも Ollama が入っており 11434 を掴んでいる。そこへトンネルを張ろうとすると `ssh` は IPv4 のバインドに失敗するが **IPv6(`::1`)には成功して黙って動き続ける**。結果、`localhost:11434` は g24 に、`127.0.0.1:11434` はローカル Ollama に繋がるという最悪の状態になり、「モデルが見つからない」という無関係なエラーで数十分溶かすことになる。`ExitOnForwardFailure=yes` はこの沈黙を防ぐ。

疎通確認(**`127.0.0.1` で確認すること**。`localhost` だと IPv6 に逃げて別物を見ている可能性がある):

```bash
curl -s http://127.0.0.1:11500/api/tags | grep fable-t
```

## Phase 4: free-claude-code プロキシ(15分)

### 4-1. 最小導入(Windows PowerShell)

公式の `install.ps1` は Claude Code に加え **Codex CLI と Python 3.14 も入れる**。既に Claude Code と `uv` があるなら、プロキシ本体だけを入れれば足りる。

```powershell
# コミット固定で導入する(git main 追従は全プロンプトが通過するソフトでは危険。OFFICE.md P2)
uv tool install --python 3.14 "git+https://github.com/Alishahryar1/free-claude-code.git@1278d00873666c7aa7a8f6c7aa38666239f66a9a"
# → fcc-claude, fcc-codex, fcc-init, fcc-server, free-claude-code
```

> ⚠️ 第三者製ソフトであり、**Claude Code の全プロンプトが通過する**位置に座る。バージョン固定なしで git main から取得する点にも注意。本物の Anthropic API キーをこの環境に置いてはならない。
> 依存に `sentry-sdk` が入るが、コード内に初期化はなくテレメトリ送信は行われない(2026-07-09 時点の 3.4.15 で確認)。

### 4-2. 設定(`~/.fcc/.env`)

Admin UI(`http://127.0.0.1:8082/admin`)からでも設定できるが、ファイルを直接書くほうが確実で差分も追える。

```bash
mkdir -p ~/.fcc && cat > ~/.fcc/.env << 'EOF'
PORT=8082
ANTHROPIC_AUTH_TOKEN="fablet-local"

# g24 のユーザー空間 Ollama(:11500)へ SSH トンネル経由で到達する。
# 末尾に /v1 を付けてはならない(fcc が起動時に拒否する)。
OLLAMA_BASE_URL="http://127.0.0.1:11500"

MODEL=ollama/fable-t-mid
MODEL_OPUS=ollama/fable-t
MODEL_SONNET=ollama/fable-t-mid
MODEL_HAIKU=ollama/fable-t-mid
EOF
```

> `/office` 会議のサブエージェント(`.claude/agents/*.md`)は tier を介さず、`model:` に `ollama/fable-t-o` / `ollama/fable-t-mid-o` を直接指定して呼ばれる。主セッションの tier 割り当てとは独立している。

クラウド無料枠へ切り替える場合は `NVIDIA_NIM_API_KEY` 等を足し、`MODEL_OPUS` だけを差し替える。**業務コードでは既定でローカル(`ollama/`)のみを使い、戻し忘れに注意する**([DESIGN.md 4.1](DESIGN.md))。

### 4-3. サーバ起動

```powershell
fcc-server
```

`/v1/models` が 200 を返し、`ollama/fable-t` が並べば良い。

```bash
curl -s -H "x-api-key: fablet-local" http://127.0.0.1:8082/v1/models | head -c 200
```

## Phase 5: Claude Code を接続(5分)

### 5-1. ランチャ経由(推奨)

```powershell
fcc-claude
```

Admin UI のポートと auth token を毎回自動で読み、環境変数を注入して Claude Code を起動する。

### 5-2. 手動接続(VS Code 等から使う場合)

```powershell
$env:ANTHROPIC_BASE_URL = "http://localhost:8082"
$env:ANTHROPIC_AUTH_TOKEN = "<Admin UI の auth token>"
$env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1"
$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "120000"
claude
```

> `CLAUDE_CODE_AUTO_COMPACT_WINDOW` は README の例では 190000 だが、**`num_ctx` より小さい値**にする。131072 で構築したなら `120000`、65536 に落としたなら `56000` 程度。文脈上限を超えてから圧縮しても手遅れになる。

## Phase 6: 動作検証

小さく確認してから実タスクへ上げる。**Phase 6-2 が新方針の成否を分ける関門**である。

### 6-0. 経路全体の事前テスト(Claude Code を起動せずに確認できる)

**Claude Code を立ち上げる前にこれを通す。** Anthropic Messages API 形式でツール定義を渡し、`tool_use` が返るかを見る。ここが通れば、経路(Anthropic API → プロキシ → トンネル → g24 の GPU)とモデルの tool-calling が両方生きている。

```bash
curl -s -N http://127.0.0.1:8082/v1/messages \
  -H "content-type: application/json" -H "x-api-key: fablet-local" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":512,
       "messages":[{"role":"user","content":"Read the file /etc/hostname using the Read tool."}],
       "tools":[{"name":"Read","description":"Read a file from the filesystem",
                 "input_schema":{"type":"object","properties":{"file_path":{"type":"string"}},"required":["file_path"]}}]}'
```

レスポンスは **SSE ストリーム**で返る(プロキシは常にストリーミングする)。期待する内容:

```
content_block_start ... {"type": "thinking"}          ← gpt-oss の reasoning が Anthropic 形式に写像されている
content_block_start ... {"type": "tool_use", "name": "Read"}
input_json_delta ... {"file_path":"/etc/hostname"}
message_delta ... "stop_reason": "tool_use"           ← ✅ これが出れば合格
```

2026-07-09 実測で `stop_reason: tool_use` / `Read {"file_path":"/etc/hostname"}` を確認済み。

### 6-1. 疎通(1分)

Claude Code 上で `hello` と入力。応答が返れば経路は生きている。応答中に別ターミナルで確認:

```bash
ssh g24 "OLLAMA_HOST=127.0.0.1:11500 ~/ollama-dist/bin/ollama ps"   # 100% GPU であること
```

### 6-2. ツール呼び出しの忠実度(最重要)

Claude Code は Read/Edit/Bash 等を厳格なスキーマで呼ぶ。`gpt-oss:120b` がこれに耐えるかを段階的に試す。

| # | 入力 | 合格基準 |
|---|---|---|
| 1 | `このディレクトリのファイルを一覧して` | Bash か Glob を**実際に呼ぶ**。「一覧できません」と言わない |
| 2 | `DESIGN.md の1章を読んで要約して` | Read ツールを呼び、実内容に基づいて要約する(捏造しない) |
| 3 | 小さな `.py` を作り `print` を1行足させる | **Edit の `old_string` 完全一致に成功する**。ここが最大の難所 |
| 4 | わざと失敗するテストを置き `直して` | 編集 → 実行 → 失敗を読む → 再修正、のループを人手介入なしに閉じる |
| 5 | 30ターン程度の作業を続ける | 最初の要件と CLAUDE.md の指示を保持している |

3 が通らない(`old_string` 不一致を繰り返す)場合、そのモデルは Claude Code のハーネスに対して力不足である。`num_ctx` 不足でないことを確認した上で、Phase 7 のフォールバックへ。

### 6-3. 暴走の監視

初回は必ず**使い捨てのリポジトリ**で試す。ローカルモデルは Claude Code ほど自制的ではないので、同一ファイルの反復編集、不要ファイルの大量生成、破壊的コマンドの実行がないかを観察する。パーミッションモードは既定(都度確認)のまま運用する。

## Phase 7: トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `ollama ps` で CPU オフロード | `num_ctx` 過大。131072 → 65536。`CLAUDE_CODE_AUTO_COMPACT_WINDOW` も併せて下げる |
| HTTP 400 が返る | 文脈長超過が最有力。`num_ctx` を上げるか compact window を下げる |
| モデルが「ツールを使えません」と言う | Modelfile に SYSTEM が残っている。`ollama show fable-t --system` が**空**であることを確認 |
| 突然 `100% CPU` になった | 壊れた system Ollama(`:11434`)に繋がっている。`OLLAMA_HOST=127.0.0.1:11500` とトンネルの右辺を確認 |
| `ollama serve` が起動しない | `ssh` の `nohup ... &` はセッション終了に巻き込まれる。`setsid` を使う |
| Edit の `old_string` 不一致を繰り返す | ベースモデルの限界。`MODEL_OPUS` をクラウドの agentic 訓練済みモデルへ切り替える |
| 1ターンが極端に遅い | reasoning が長い。Ollama の thinking 強度を下げるか、`fablet-fast` を Haiku tier に確実に振る |
| 応答が来ない / 接続拒否 | Phase 3 のトンネルが切れている。`curl http://127.0.0.1:11500/api/tags` で確認 |
| モデル名が解決されない | `ollama/` プレフィクス漏れ、または `OLLAMA_BASE_URL` に `/v1` を付けている |
| `Upstream provider OLLAMA returned HTTP 404` / `404 page not found` | Ollama が古く `/v1/messages` が無い。**0.20 以上**が必要。`curl :11500/api/version` で確認 |
| `model 'fable-t' not found` なのに `ollama list` には在る | トンネルが張れておらず**ローカル Windows の Ollama**を叩いている。Phase 3 の IPv4/IPv6 の注意を参照。`127.0.0.1` と `localhost` で `/api/tags` を比べると一発で分かる |
| `tar --zstd` が `zstd: Cannot exec` | `tar` は外部 `zstd` を呼ぶだけ。g24 に無い。python の `zstandard` で展開する(Phase 2-a) |
| 120B と 20B のロードが往復して遅い | Phase 2-4 の `OLLAMA_MAX_LOADED_MODELS=2` 未設定。設定できないなら全 tier を `fable-t` に統一 |

## Phase 8: チャット用途(`fablet-chat`)

FABLE.md 人格が**完全に効く**のはこちらである。相談・調査・文章作成に使う。

Phase 3 のトンネルを張った状態で:

```bash
docker run -d -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --name open-webui --restart always \
  ghcr.io/open-webui/open-webui:main
```

`http://localhost:3000` を開き、モデルに `fablet-chat:latest` を選択。

人格を更新する場合は旧来のフローがそのまま使える:

```bash
./build-modelfile.sh && scp fable-system.txt Modelfile g24:~/fablet/ \
  && ssh g24 "export OLLAMA_HOST=127.0.0.1:11500; cd ~/fablet && ~/ollama-dist/bin/ollama create fablet-chat -f Modelfile"
```

> `build-modelfile.sh` が生成する `Modelfile` は SYSTEM を含む。**`fable-t` のビルドには絶対に使わない**(`Modelfile.fable-t` を使う)。

## Phase 9: 使用後のクリーンアップ(`cleanup.sh`)

g24 は共用機である。`gpt-oss:120b` はロードされている間 **65〜70GB の RAM または VRAM を占有し続ける**(`OLLAMA_KEEP_ALIVE` の間、既定5分)。作業を終えたら明示的に解放する。

```bash
./cleanup.sh            # ロード中モデルをアンロード(RAM/VRAM 解放)。安全・既定
./cleanup.sh --purge    # 加えて FableT が作成した派生モデルを削除(確認プロンプトあり)
```

### ディスク上の「キャッシュ」について

**FableT がディスクに追加した容量は実質ゼロである。** `fable-t` / `fablet-fast` / `fablet-chat` はいずれも派生モデルで、blob(重み本体)をベースモデルと共有し、固有に持つのはマニフェストと `fablet-chat` の SYSTEM レイヤー(数十KB)だけである。したがって `--purge` を実行してもディスクはほぼ減らない。

実際に容量を食っているのは `gpt-oss:120b`(65GB)等の**ベースモデルであり、これらは FableT 以前から存在し他ユーザーも使う**。`cleanup.sh` は意図的にこれらに触れない。ベースモデルを消すのは g24 の管理判断であって、本プロジェクトの後片付けの範囲外である。

解放すべき「キャッシュ」は実質 RAM/VRAM 常駐分であり、それが `cleanup.sh` の既定動作である。

### モデル置き場をローカルに寄せる場合

g24 のディスクを一切汚したくない場合は、ブロッカー復旧案 B(ユーザー空間 Ollama)と組み合わせ、`OLLAMA_MODELS` を自分のホーム配下に向ける。

```bash
export OLLAMA_MODELS=$HOME/ollama-models     # 既定は /usr/share/ollama/.ollama/models
```

blob を再取得せずに済ませるなら、共有ディレクトリ(`/usr/share/ollama/.ollama/models/blobs`、`tashiro` から読み取り可)から**ハードリンクまたはシンボリックリンク**を張る。同一パーティション上なのでハードリンクが使え、追加消費はゼロになる。

## Phase 10: 運用メモ

- **VRAM 確認を習慣に**: g24 は共用機。投入前に `./vram.sh`。120B単体で 70GiB、20B併用で 80GiB 以上の空きが目安
- **トンネルは常時**: Claude Code 使用中は Phase 3 の SSH セッションを閉じない
- **クラウド切替は意識的に**: `MODEL_OPUS` をクラウドに向けた瞬間、**コードが外部送信される**。業務コードでは戻し忘れに注意
- **本物の API キーを置かない**: `ANTHROPIC_AUTH_TOKEN` はプロキシ用のダミー。fcc-server は全プロンプトが通過する位置にいる
