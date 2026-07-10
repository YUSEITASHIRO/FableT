#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if grep -q '"""' fable-system.txt; then
  echo 'ERROR: fable-system.txt contains """ — fix before building' >&2; exit 1
fi
{
  echo 'FROM gpt-oss:120b'
  echo
  echo 'SYSTEM """'
  cat fable-system.txt
  echo '"""'
  echo
  echo 'PARAMETER num_ctx 65536'
  echo 'PARAMETER temperature 1.0'
} > Modelfile
echo "Modelfile generated: $(wc -c < Modelfile) bytes"
