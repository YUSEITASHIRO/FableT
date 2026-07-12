# FableT Office — プロジェクト規約

このディレクトリは「Claude Code ハーネス + ローカル gpt-oss:120b」で駆動される
オフィス型マルチエージェント環境である。設計は OFFICE.md、経路は DESIGN.md /
IMPLEMENTATION.md を参照。

## 動作原則

- 思考規律は fable-coding.txt(起動時に system prompt へ追記される)に従う:
  読んでから書く、最小の変更、検証ループを閉じる、検証した/していないを分けて報告。
- 方針が割れうる規模のタスクは `/office <依頼>` の会議プロトコルに掛ける。
  自明なタスクは直接こなしてよい(判定規準は plugin/commands/office.md 冒頭)。
- サブエージェントは逐次で呼ぶ。バックエンドの Ollama は並列度1。

## 環境の注意(過去の事故から)

- Ollama は g24 のユーザー空間版(:11500、SSHトンネル経由)。:11434 は
  Windows ローカルの別物。疎通確認は必ず `127.0.0.1` で行う(localhost は
  IPv6 に逃げて別物を見ることがある)。
- モデルは3種: `fable-t`(120B)/ `fable-t-mid`(30B)/ `fable-t-o`
  (`fable-t`と同じ重みの `/office` 専用エイリアス)。fablet.ps1 が
  fablet.settings.json(availableModels + enforceAvailableModels)を
  --settings で注入するため、/model で選べるのはこの3名称のみ。
  Opus/Sonnet/Haiku の組込みエントリは選択不能、Default は fable-t-mid。
  切替は `/model` を開いて一覧から選ぶ(名前指定は allowlist と同一文字列、
  例 `/model anthropic/ollama/fable-t`。bare 名は弾かれ Default へ落ちる)。
  fcc の tier 変換
  (~/.fcc/.env)は内部処理用に維持: opus → `fable-t`、sonnet/haiku →
  `fable-t-mid`。allowlist は fcc が /v1/models で公開する ID に合わせること:
  bare 名だけだと「利用可能なし」で enforcement がスキップされ、逆に prefixed と
  bare を併記すると同一モデルが `:latest` 付きで重複表示される。fcc は各モデルを
  `anthropic/ollama/<名前>` と `…:latest` の両形で公開する(fable-t-o のみ
  :latest 形だけ)ため、fable-t / fable-t-mid は prefixed 形、fable-t-o は
  bare 形(エージェント frontmatter と同一文字列)を1つずつ載せる。
- `/office` と8エージェントは plugin/ ディレクトリ(--plugin-dir で注入)
  にある。どのプロジェクトから fablet を起動しても利用可能。全役が
  `model: ollama/fable-t-o` を直接指定し、役ごとに分けず同じモデルで発言する。
- `/office` は「検証器ファースト」で動く: 受入テストを実装前に固定し、緑のログだけを
  完了の証拠とする。予算は即答/標準/フルの3段(フルは best-of-N=3 + critic ループ)。
  ローカル推論は無料なので、品質は賢さではなく試行回数で買う——これがこのプロジェクトの
  中心的な設計思想である(plugin/commands/office.md)。
- `fable-t` / `fable-t-o` は **Reasoning: high 固定**。gpt-oss の推論量は system メッセージの
  `Reasoning:` 行で決まり、Modelfile の PARAMETER では指定できない(`unknown parameter 'think'`)。
  さらに Ollama サーバは think 未指定のリクエストにも medium を注入するため、TEMPLATE の
  両分岐を high に固定してある(Modelfile.fable-t)。
- **g24 の VRAM は他ユーザーと奪い合いである。** 空きが 70GiB 未満だと 120B は CPU へ
  スピルして激遅になる。fablet 起動時と bench/agentic/run.ps1 が空きを検査して警告・中止する。
  「遅い」と感じたらまず `./vram.sh`。
- `.env` などのシークレットをコミット・表示・外部送信しない。
- **g24 は共用 GPU 機。汚さないことは機能要件である。** セッション終了時は必ず
  ./cleanup.sh を実行し、モデルのアンロード(VRAM/RAM解放)まで確認する。
  一時ファイルを g24 に置いたら作業終了時に消す。恒常的に必要なデータは
  g24 に置かず、ローカル(このPC)へ scp で取得して参照する。
