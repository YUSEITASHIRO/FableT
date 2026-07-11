# FableT Office — プロジェクト規約

このディレクトリは「Claude Code ハーネス + ローカル gpt-oss:120b」で駆動される
オフィス型マルチエージェント環境である。設計は OFFICE.md、経路は DESIGN.md /
IMPLEMENTATION.md を参照。

## 動作原則

- 思考規律は fable-coding.txt(起動時に system prompt へ追記される)に従う:
  読んでから書く、最小の変更、検証ループを閉じる、検証した/していないを分けて報告。
- 方針が割れうる規模のタスクは `/office <依頼>` の会議プロトコルに掛ける。
  自明なタスクは直接こなしてよい(判定規準は .claude/commands/office.md 冒頭)。
- サブエージェントは逐次で呼ぶ。バックエンドの Ollama は並列度1。

## 環境の注意(過去の事故から)

- Ollama は g24 のユーザー空間版(:11500、SSHトンネル経由)。:11434 は
  Windows ローカルの別物。疎通確認は必ず `127.0.0.1` で行う(localhost は
  IPv6 に逃げて別物を見ることがある)。
- モデルは4種: `fable-t`(120B)/ `fable-t-mid`(30B)/ `fable-t-o`・`fable-t-mid-o`
  (同じ重みの `/office` 専用エイリアス)。主セッションは opus → `fable-t`、
  sonnet/haiku → `fable-t-mid`(fcc の tier 割り当ては ~/.fcc/.env)。
  `.claude/agents/*.md` の各役は `model:` に `ollama/fable-t-o` /
  `ollama/fable-t-mid-o` を直接指定し、主セッションと別枠で動く。
- `.env` などのシークレットをコミット・表示・外部送信しない。
- **g24 は共用 GPU 機。汚さないことは機能要件である。** セッション終了時は必ず
  ./cleanup.sh を実行し、モデルのアンロード(VRAM/RAM解放)まで確認する。
  一時ファイルを g24 に置いたら作業終了時に消す。恒常的に必要なデータは
  g24 に置かず、ローカル(このPC)へ scp で取得して参照する。
