# gpt-proxy.ps1 — GPT アーム用の中継プロキシ(LiteLLM)を :8083 に立てる
#
#   .\gpt-proxy.ps1            # 起動(この窓は開いたままにする。閉じれば止まる)
#   .\gpt-proxy.ps1 -Check     # 起動せず、疎通と公開モデルだけ確認する
#
# なぜ fcc ではないのか:
#   fcc は "free-claude-code" の名のとおり無料プロバイダ専用で、OPENAI_API_KEY を受け付ける
#   設定項目が存在しない(対応は NIM / OpenRouter / Gemini / DeepSeek / Groq など)。
#   2026-07-12 にキーを渡して実機確認したが、OpenAI モデルは /v1/models に一切出なかった。
#   ベンチの前提は「全アームが同じ Claude Code ハーネスで走る」ことなので、Anthropic 形式を
#   話せて OpenAI へ中継できるプロキシを別に立てる。それが LiteLLM である。
#
# キーの扱い:
#   Bench\.env の OPENAI_API_KEY を **このプロセスの環境変数にだけ**渡す。画面に出さない、
#   ファイルに書かない、コミットしない。プロキシはローカル(127.0.0.1)にのみ口を開く。
#   測定が終わったらこの窓を閉じること(キーを持ったプロセスを放置しない)。

param(
    [switch]$Check,
    [int]$Port = 8083,
    [string]$EnvFile = "C:\Users\yusei\Desktop\Bench\.env"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Join-Path $here "litellm.gpt.yaml"
$base = "http://127.0.0.1:$Port"

function Show-Models {
    try {
        $r = Invoke-WebRequest -Uri "$base/v1/models" -Headers @{ "x-api-key" = "fablet-local" } `
            -UseBasicParsing -TimeoutSec 5
        Write-Host "[OK] 中継プロキシ稼働中 ($base)" -ForegroundColor Green
        ($r.Content | ConvertFrom-Json).data | ForEach-Object { "  - $($_.id)" }
        return $true
    } catch {
        Write-Host "[NG] $base が応答しない" -ForegroundColor Red
        return $false
    }
}

if ($Check) {
    if (Show-Models) { exit 0 } else { exit 1 }
}

# --- キーの読み込み(表示しない) ---
if (-not (Test-Path $EnvFile)) { throw "キーの置き場が無い: $EnvFile" }
$line = Get-Content $EnvFile | Where-Object { $_ -match "^OPENAI_API_KEY=" }
$key = ($line -replace "^OPENAI_API_KEY=", "").Trim()
if (-not $key) { throw "OPENAI_API_KEY が空: $EnvFile" }
$env:OPENAI_API_KEY = $key
Write-Host "[OK] OPENAI_API_KEY を読み込んだ(このプロセス限り。長さ $($key.Length))" -ForegroundColor Green

# --- LiteLLM の導入確認 ---
# uv 管理下に入れる(このプロジェクトは fcc も uv tool で入れている)。
# --python 3.12 を指定すること: uv の既定(3.14)にはビルド済みホイールが無く、Rust 拡張の
# ソースビルドに落ちて失敗する(2026-07-12 実際に発生)。
if (-not (Get-Command litellm -ErrorAction SilentlyContinue)) {
    Write-Host "[..] litellm が無い — uv tool でインストールする" -ForegroundColor Yellow
    uv tool install --python 3.12 "litellm[proxy]"
    if (-not (Get-Command litellm -ErrorAction SilentlyContinue)) {
        throw 'litellm のインストールに失敗した。手動で: uv tool install --python 3.12 "litellm[proxy]"'
    }
}

# litellm は起動バナーにブロック文字(U+2588)を出す。日本語 Windows の既定の標準出力は
# cp932 なので、そのままだと UnicodeEncodeError で起動に失敗する(2026-07-12 実際に発生)。
# Python の I/O を UTF-8 に固定して回避する。
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"

Write-Host "`nGPT 中継プロキシを起動する: $base" -ForegroundColor Cyan
Write-Host "この窓を閉じると止まる(キーを持ったプロセスを放置しないこと)。`n" -ForegroundColor DarkGray
Write-Host "別の窓で次を実行する:" -ForegroundColor DarkGray
Write-Host "  .\run.ps1 -Arm gpt -K 1" -ForegroundColor DarkGray
Write-Host "  .\run.ps1 -Arm gpt-mini -K 1`n" -ForegroundColor DarkGray

# --host 127.0.0.1 でローカル限定。外に口を開けない。
litellm --config $config --host 127.0.0.1 --port $Port
