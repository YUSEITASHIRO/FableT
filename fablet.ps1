# fablet.ps1 — FableT Office セッションランチャ
# 経路(SSHトンネル → fcc-server)の生存を確認してから Claude Code を起動する。
# 黙って IPv6 に逃げる事故(IMPLEMENTATION.md Phase 3)を再発させないため、
# 確認は全て 127.0.0.1 に対して行う。
#
#   fablet              通常起動。終了時に g24 のモデルを自動アンロードする
#   fablet -Shutdown    Windows 側の常駐(fcc-server とトンネル)も落として完全に片付ける
#
# fcc-server は窓を出さない。UI は持っておらず(HTTP は 401 を返す API プロキシ)、
# 窓はログが流れるだけだったため。ログは $env:TEMP\fablet-fcc.log に出る。

param(
    [switch]$Shutdown
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fccLog = Join-Path $env:TEMP "fablet-fcc.log"

# g24 上でロードされている FableT のモデルをアンロードする。VRAM を握ったままにしないための、
# このプロジェクトの最重要の後始末(g24 は共用機)。
function Release-G24 {
    Write-Host "`n[..] g24 のモデルを解放中..." -ForegroundColor DarkGray
    try {
        $ol = "OLLAMA_HOST=127.0.0.1:11500 `$HOME/ollama-dist/bin/ollama"
        ssh g24 "for m in fable-t fable-t-mid fable-t-o fablet-fast fablet-chat; do $ol stop `$m 2>/dev/null; done; $ol ps" | Out-Null
        $remaining = (ssh g24 "$ol ps" | Select-Object -Skip 1) -join ""
        if ([string]::IsNullOrWhiteSpace($remaining)) {
            Write-Host "[OK] g24 のモデルをアンロードした(VRAM 解放済み)" -ForegroundColor Green
        } else {
            Write-Host "[!] まだロード中のモデルがある: $remaining" -ForegroundColor Yellow
            Write-Host "    ./cleanup.sh で確認すること" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] g24 への接続に失敗した。手動で ./cleanup.sh を実行すること" -ForegroundColor Red
    }
}

# Windows 側の常駐を落とす(-Shutdown 用)。GPU は使っていないので通常は残してよいが、
# 「全部消したい」ときのために明示的な出口を用意する。
function Stop-LocalServices {
    Get-Process fcc-server -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" |
        Where-Object { $_.CommandLine -match "11500:localhost:11500" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host "[OK] fcc-server と SSH トンネルを停止した" -ForegroundColor Green
}

if ($Shutdown) {
    Release-G24
    Stop-LocalServices
    exit 0
}

function Test-Endpoint($url, $name, $hint, $headers) {
    try {
        if ($null -eq $headers) { $headers = @{} }
        Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 3 | Out-Null
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
    # fable-t がモデル一覧に居るか(居なければローカル Ollama を見ている疑い)
    $tags = (Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/tags" -UseBasicParsing -TimeoutSec 5).Content
    if ($tags -notmatch "fable-t") {
        Write-Host "[NG] fable-t が見えない — トンネルの先が違うか、モデル未作成 (IMPLEMENTATION.md Phase 2)" -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "[OK] fable-t visible" -ForegroundColor Green
    }
} else { $ok = $false }

# 1-b. VRAM の空きを見る。g24 は共用機で、他ユーザーのジョブが VRAM を握っていると
#      120B(fable-t, 約69GiB)はロードされても CPU へスピルし、数十倍遅くなる
#      (2026-07-12 実際に発生: 他ユーザーが 75GiB 占有 → fable-t が 31% GPU)。
#      落とさず警告に留める。30B(fable-t-mid, 約22GiB)だけなら問題なく動く。
if ($ok) {
    try {
        $freeMiB = [int](ssh g24 "nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits" | Select-Object -First 1)
        $freeGiB = [math]::Round($freeMiB / 1024, 0)
        # 閾値は実測に合わせる: 空き 22.3GiB で 30B は 100% GPU に載った(2026-07-12)。
        # 余裕を見て 22GiB を下限とする。
        if ($freeMiB -lt 22000) {
            Write-Host "[!!] GPU 空き ${freeGiB}GiB — 30B(fable-t-mid, 22GiB)も載らない。他ユーザーの使用状況を ./vram.sh で確認すること" -ForegroundColor Red
        } elseif ($freeMiB -lt 72000) {
            Write-Host "[!] GPU 空き ${freeGiB}GiB — 30B(既定)は動くが、120B(fable-t, 69GiB)は CPU へスピルして激遅になる。/office のフル予算は空くまで待つこと" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] GPU 空き ${freeGiB}GiB (120B/30B とも常駐可)" -ForegroundColor Green
        }
    } catch {
        Write-Host "[--] VRAM 確認をスキップ(ssh 応答なし)" -ForegroundColor DarkGray
    }
}

# 2. fcc-server — 落ちていたら自動起動する。窓は出さない(UI は持たず、ログが流れるだけの
#    コンソールだった)。ログは $fccLog に出るので、不調時はそれを読む。
#    注意: /v1/models は認証必須。ヘッダなしで叩くと 401 が返り「生きているのに死んだ」と
#    誤判定し、二重起動→ポート衝突の連鎖になる(2026-07-11 実際に発生)。
$fccHeaders = @{ "x-api-key" = "fablet-local" }
try {
    Invoke-WebRequest -Uri "http://127.0.0.1:8082/v1/models" -Headers $fccHeaders -UseBasicParsing -TimeoutSec 2 | Out-Null
} catch {
    Write-Host "[..] fcc-server 未起動 — 自動起動する(窓なし。ログ: $fccLog)" -ForegroundColor Yellow
    Start-Process fcc-server -WindowStyle Hidden -RedirectStandardOutput $fccLog -RedirectStandardError "$fccLog.err"
    foreach ($i in 1..10) {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:8082/v1/models" -Headers $fccHeaders -UseBasicParsing -TimeoutSec 2 | Out-Null
            break
        } catch {}
    }
}
if (-not (Test-Endpoint "http://127.0.0.1:8082/v1/models" "fcc-server (:8082)" `
    "自動起動も失敗。別ターミナルで fcc-server を実行し、エラー出力を確認すること" $fccHeaders)) { $ok = $false }

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

# /model を fable の3名称に固定する。availableModels + enforceAvailableModels
# (fablet.settings.json) により、Opus/Sonnet/Haiku 等の組込みエントリは選択不能になり、
# Default も allowlist 先頭(fable-t-mid)へ解決される。--settings はこのセッション
# 限りなので、素の claude(本物のAnthropic)には影響しない。
# 注意: allowlist は fcc が /v1/models で公開する ID と1対1で合わせる(CLAUDE.md 参照)。
# bare 名だけだと「利用可能なエントリなし」でenforcementがスキップされ Default が素の Opus に
# 化ける(2026-07-11)。prefixed と bare の併記は :latest 付きの重複行を生む(2026-07-12)。
# --model のピンも allowlist に載っている ID と同一文字列にする。bare 名でピンすると
# enforcement に弾かれて Default(opus tier = 120B)へ黙って落ちる(2026-07-12 実際に発生)。
$fableSettings = Join-Path $here "fablet.settings.json"

# /office と7エージェントはプラグインとして注入する。--plugin-dir はセッション限りなので、
# どのプロジェクトディレクトリから起動しても .claude\ のコピー無しで /office が使える。
$fablePlugin = Join-Path $here "plugin"

Write-Host "`nFableT Office 起動。/office <依頼> で会議モード、/model を開いて一覧からモデル切替。" -ForegroundColor Cyan
Write-Host "終了(/exit や Ctrl+C)で g24 のモデルは自動解放される。窓を×で強制終了した場合は" -ForegroundColor DarkGray
Write-Host "g24 側の keep_alive(10分)が解放するので、VRAM が残り続けることはない。`n" -ForegroundColor DarkGray

# claude をどう抜けても(正常終了・Ctrl+C・エラー)g24 を解放する。
# ただし窓の × による強制終了(プロセス kill)では finally は走らない。その保険が
# g24 側の OLLAMA_KEEP_ALIVE=10m である(start.sh)。両輪で「VRAM を握ったまま放置」を防ぐ。
try {
    claude --settings $fableSettings --plugin-dir $fablePlugin --model "anthropic/ollama/fable-t-mid" --append-system-prompt $fableCore @args
} finally {
    Release-G24
}
