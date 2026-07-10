# fablet.ps1 — FableT Office セッションランチャ
# 経路(SSHトンネル → fcc-server)の生存を確認してから Claude Code を起動する。
# 黙って IPv6 に逃げる事故(IMPLEMENTATION.md Phase 3)を再発させないため、
# 確認は全て 127.0.0.1 に対して行う。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Endpoint($url, $name, $hint) {
    try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 | Out-Null
        Write-Host "[OK] $name" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[NG] $name — $hint" -ForegroundColor Red
        return $false
    }
}

$ok = $true

# 1. SSH トンネル → g24 ユーザー空間 Ollama
#    落ちていたら自動で張る。ssh -N は「転送だけして返ってこない」のが正常動作なので
#    隠しプロセスとして起動する(鍵認証が前提。パスワード認証だと失敗する)。
try {
    Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/version" -UseBasicParsing -TimeoutSec 2 | Out-Null
} catch {
    Write-Host "[..] トンネル未接続 — 自動起動を試みる" -ForegroundColor Yellow
    Start-Process ssh -ArgumentList "-o","ExitOnForwardFailure=yes","-N","-L","127.0.0.1:11500:localhost:11500","g24" -WindowStyle Hidden
    foreach ($i in 1..8) {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/version" -UseBasicParsing -TimeoutSec 2 | Out-Null
            break
        } catch {}
    }
}
if (Test-Endpoint "http://127.0.0.1:11500/api/version" "Ollama (g24 :11500 via tunnel)" `
    "自動起動も失敗。g24側のOllamaが停止している可能性: ssh g24 で入り setsid nohup ~/ollama-dist/start.sh を実行 (IMPLEMENTATION.md)") {
    # fablet-code がモデル一覧に居るか(居なければローカル Ollama を見ている疑い)
    $tags = (Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/tags" -UseBasicParsing -TimeoutSec 5).Content
    if ($tags -notmatch "fablet-code") {
        Write-Host "[NG] fablet-code が見えない — トンネルの先が違うか、モデル未作成 (IMPLEMENTATION.md Phase 2)" -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "[OK] fablet-code visible" -ForegroundColor Green
    }
} else { $ok = $false }

# 2. fcc-server
if (-not (Test-Endpoint "http://127.0.0.1:8082/v1/models" "fcc-server (:8082)" `
    "別ターミナルで: fcc-server")) { $ok = $false }

if (-not $ok) {
    Write-Host "`n経路が死んでいる。上の指示で復旧してから再実行すること。" -ForegroundColor Yellow
    exit 1
}

# 3. FABLE.md 思考規律 (L1) を system prompt に追記して起動
$fableCore = Get-Content (Join-Path $here "fable-coding.txt") -Raw

$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:8082"
$env:ANTHROPIC_AUTH_TOKEN = "fablet-local"
$env:CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1"
$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "80000"    # 131kまで使えるが、プレフィル時間はターン毎に文脈長に比例して伸びる。80kで頭打ちにする

Write-Host "`nFableT Office 起動。/office <依頼> で会議モード、/model でモデル切替。`n" -ForegroundColor Cyan
claude --append-system-prompt $fableCore @args
