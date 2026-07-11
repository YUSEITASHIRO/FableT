#!/bin/bash
# FableT クリーンアップ — 使用後に g24 のリソースを解放する
#
#   ./cleanup.sh          ロード中モデルをアンロード(VRAM 解放)。既定・安全
#   ./cleanup.sh --purge  上記に加え、FableT が作成した派生モデルを削除する
#   ./cleanup.sh --stop   上記に加え、ユーザー空間 Ollama サーバ自体を停止する
#
# ベースモデル(gpt-oss:120b, gpt-oss:20b, gemma3:27b 等)には触れない。
# g24 は共用機であり、これらは FableT 以前から存在し他ユーザーも使う。
#
# 注意: FableT は system の ollama(:11434, GPU 不可)ではなく、
#       ユーザー空間 Ollama(:11500, GPU 有効)を使う。ポートを間違えると解放されない。
set -euo pipefail

HOST=g24
PORT=11500
OWNED="fable-t fable-t-mid fable-t-o fable-t-mid-o fablet-fast fablet-chat"   # FableT が作成したモデルのみ
OL="OLLAMA_HOST=127.0.0.1:$PORT \$HOME/ollama-dist/bin/ollama"

echo "=== 現在ロード中(:$PORT)==="
ssh "$HOST" "$OL ps"

echo
echo "=== アンロード(VRAM 解放)==="
for m in $OWNED; do
  ssh "$HOST" "$OL stop $m 2>/dev/null" || true
done
ssh "$HOST" "$OL ps"

if [ "${1:-}" = "--purge" ]; then
  echo
  echo "=== 削除対象(FableT 作成分のみ・ベースモデルは残す)==="
  ssh "$HOST" "$OL list | grep -E '^fablet-' || true"
  echo
  read -r -p "上記を削除してよいか? [y/N] " ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    for m in $OWNED; do
      ssh "$HOST" "$OL rm $m 2>/dev/null" || true
    done
    echo "削除完了。Modelfile.fable-t / Modelfile.fable-t-mid / Modelfile.fast から再作成できる(-o は ollama cp で複製)。"
  else
    echo "中止した。"
  fi
fi

if [ "${1:-}" = "--stop" ]; then
  echo
  echo "=== ユーザー空間 Ollama サーバを停止 ==="
  # 注意: pkill/pgrep の -f は ssh の bash -c 文字列にもマッチする。
  # [o] トリックで自滅を避け、生存確認は API 応答で行う(プロセス名検索は誤検知する)。
  ssh "$HOST" "pkill -u \$(whoami) -f 'ollama-dist/bin/[o]llama serve'" || true
  sleep 2
  ssh "$HOST" "curl -s -m 3 -o /dev/null http://127.0.0.1:$PORT/api/version && echo '停止できず(まだ応答あり)' || echo '停止した'"
fi

echo
echo "=== 残りリソース ==="
ssh "$HOST" "nvidia-smi --query-gpu=memory.free --format=csv,noheader; df -h / | tail -1"
