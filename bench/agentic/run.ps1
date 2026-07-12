# run.ps1 — エージェントベンチ実行器
#
#   .\run.ps1 -Arm fable-t -K 3            # 120B + 規律(FableT 本体)
#   .\run.ps1 -Arm opus -K 1               # Claude Opus(クレジット消費!)
#   .\run.ps1 -Arm raw-gptoss -K 3         # 素の gpt-oss(規律なし。対照群)
#   .\run.ps1 -Arm fable-t -K 3 -Task interval-merge
#
# 各試行は tasks/<名前>/repo を一時ディレクトリへ複製した上で行う。エージェントには
# prompt.txt だけを渡し、隠しテスト(verify.py)は見せない。試行は互いに独立で、
# 前の試行の結果を次に渡さない(これが pass@k の定義であり、best-of-N の前提)。
#
# アームを追加・変更したら bench/agentic/README.md の表も直すこと。
# タスクを追加したら selftest.ps1 を必ず通すこと。

param(
    # 比較アーム。ローカル(無料)/ Anthropic(クレジット)/ OpenAI(API課金)の3系統。
    #   fable-t      120B + Reasoning:high + 思考規律(= FableT 本体)
    #   fable-t-mid   30B + 思考規律
    #   raw-gptoss   120B、規律なし・Reasoning は既定(medium)  ← 「規律の効果」の対照群
    #   raw-qwen      30B、規律なし                            ← 同上
    #   opus         Claude Opus 4.8(本物の Anthropic)
    #   sonnet       Claude Sonnet(本物の Anthropic)
    #   gpt / gpt-mini  OpenAI モデル(fcc 経由。OPENAI_API_KEY が必要)
    [ValidateSet("fable-t", "fable-t-mid", "raw-gptoss", "raw-qwen", "opus", "sonnet", "gpt", "gpt-mini")]
    [string]$Arm = "fable-t",

    [int]$K = 1,
    [string]$Task = "",
    [int]$TimeoutSec = 1800,

    # エージェントに与える権限。
    #   edit   (既定) — 編集は自動承認、Bash は与えない。採点は外部の verify.py が行うので、
    #                   タスクを解くのに Bash は要らない。ホストで任意コマンドが走らない。
    #   bypass         — 全権限を素通し。**ホスト上で任意のコマンドが実行される。**
    #                   使い捨てのサンドボックスでのみ使うこと。
    # 権限モードが違う結果は比較しないこと(解ける範囲が変わる)。
    [ValidateSet("edit", "bypass")]
    [string]$Permissions = "edit"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here "..\..")

# --- アームの定義 -------------------------------------------------------------
# local     : g24 の Ollama を fcc 経由で使う(無料)
# anthropic : 本物の Anthropic API(クレジット消費)
# openai    : OpenAI API(課金。fcc 経由で Claude Code ハーネスから叩く)
# discipline: fable-coding.txt(思考規律)を --append-system-prompt で注入するか
$arms = @{
    "fable-t"     = @{ backend = "local";     model = "anthropic/ollama/fable-t";     discipline = $true;  note = "120B + Reasoning:high + 規律" }
    "fable-t-mid" = @{ backend = "local";     model = "anthropic/ollama/fable-t-mid"; discipline = $true;  note = "30B + 規律" }
    # 注意: fcc が公開する ID をそのまま書くこと(綴りが違うと黙って Default に落ちる)。
    # raw-* は :latest 付きの形でしか公開されない。また fcc はモデル一覧を起動時にキャッシュ
    # するので、g24 にモデルを作ったら fcc-server を再起動しないと見えない(2026-07-12 に遭遇)。
    "raw-gptoss"  = @{ backend = "local";     model = "anthropic/ollama/raw-gptoss:latest"; discipline = $false; note = "素の gpt-oss:120b(規律なし)" }
    "raw-qwen"    = @{ backend = "local";     model = "anthropic/ollama/raw-qwen:latest";   discipline = $false; note = "素の qwen3:30b(規律なし)" }
    "opus"        = @{ backend = "anthropic"; model = "opus";                         discipline = $false; note = "Claude Opus 4.8" }
    "sonnet"      = @{ backend = "anthropic"; model = "sonnet";                       discipline = $false; note = "Claude Sonnet" }
    "gpt"         = @{ backend = "openai";    model = "anthropic/openai/gpt-5.4";      discipline = $false; note = "OpenAI gpt-5.4" }
    "gpt-mini"    = @{ backend = "openai";    model = "anthropic/openai/gpt-5.4-mini"; discipline = $false; note = "OpenAI gpt-5.4-mini" }
}

$cfg = $arms[$Arm]
Write-Host ("アーム: {0}  ({1})" -f $Arm, $cfg.note) -ForegroundColor Cyan

if ($cfg.backend -eq "anthropic") {
    Write-Host "警告: このアームは本物の Anthropic API を叩き、クレジット(利用枠)を消費する。" -ForegroundColor Yellow
    Write-Host "      比較測定の意図がなければ Ctrl+C で中止すること。5秒後に開始する。" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}
if ($cfg.backend -eq "openai") {
    if (-not $env:OPENAI_API_KEY) {
        Write-Host "中止: OPENAI_API_KEY が設定されていない。" -ForegroundColor Red
        Write-Host "      このアームは fcc-server 経由で OpenAI を叩くため、fcc にキーを渡す必要がある。" -ForegroundColor Red
        Write-Host "      fcc は全プロンプトが通過する第三者製プロキシである点を理解した上で、" -ForegroundColor Red
        Write-Host "      使い捨ての・上限を絞ったキーだけを使うこと(README の注意を読むこと)。" -ForegroundColor Red
        exit 1
    }
    Write-Host "警告: このアームは OpenAI API に課金される。5秒後に開始する。" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}
if ($Permissions -eq "bypass") {
    Write-Host "警告: -Permissions bypass はエージェントの権限確認を全て素通しする。" -ForegroundColor Red
    Write-Host "      作業ディレクトリは一時領域だが、Bash はホスト上で走る。使い捨て環境でのみ使うこと。" -ForegroundColor Red
    Start-Sleep -Seconds 5
}

# --- 経路プリフライト ----------------------------------------------------------
# ローカル/OpenAI アームは fcc 経由なので、トンネルと fcc-server が生きている必要がある。
# 落ちていれば起動する(fablet.ps1 と同じ手順)。Anthropic アームには不要。
if ($cfg.backend -ne "anthropic") {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/version" -UseBasicParsing -TimeoutSec 2 | Out-Null
    } catch {
        Write-Host "[..] SSH トンネル未接続 — 起動する" -ForegroundColor Yellow
        Start-Process ssh -ArgumentList "-o","ExitOnForwardFailure=yes","-N","-L","127.0.0.1:11500:localhost:11500","g24" -WindowStyle Hidden
        foreach ($i in 1..8) {
            Start-Sleep -Seconds 2
            try { Invoke-WebRequest -Uri "http://127.0.0.1:11500/api/version" -UseBasicParsing -TimeoutSec 2 | Out-Null; break } catch {}
        }
    }

    $fccHeaders = @{ "x-api-key" = "fablet-local" }
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:8082/v1/models" -Headers $fccHeaders -UseBasicParsing -TimeoutSec 2 | Out-Null
    } catch {
        Write-Host "[..] fcc-server 未起動 — 起動する" -ForegroundColor Yellow
        Start-Process fcc-server -WindowStyle Hidden -RedirectStandardOutput (Join-Path $env:TEMP "fablet-fcc.log") -RedirectStandardError (Join-Path $env:TEMP "fablet-fcc.log.err")
        foreach ($i in 1..10) {
            Start-Sleep -Seconds 2
            try { Invoke-WebRequest -Uri "http://127.0.0.1:8082/v1/models" -Headers $fccHeaders -UseBasicParsing -TimeoutSec 2 | Out-Null; break } catch {}
        }
    }

    try {
        $models = (Invoke-WebRequest -Uri "http://127.0.0.1:8082/v1/models" -Headers $fccHeaders -UseBasicParsing -TimeoutSec 5).Content
    } catch {
        Write-Host "中止: fcc-server が応答しない。$env:TEMP\fablet-fcc.log を読むこと。" -ForegroundColor Red
        exit 1
    }
    # 使うモデルが本当に公開されているか(ID の綴り違いは黙って Default に落ちる)
    $bare = $cfg.model -replace "^anthropic/", ""
    if ($models -notmatch [regex]::Escape($bare)) {
        Write-Host "中止: fcc が $($cfg.model) を公開していない。" -ForegroundColor Red
        if ($cfg.backend -eq "local") {
            Write-Host "      g24 にモデルが無い可能性: ollama list で確認し、IMPLEMENTATION.md の手順で作ること。" -ForegroundColor Red
        } else {
            Write-Host "      fcc が OpenAI モデルを公開していない。OPENAI_API_KEY を fcc プロセスが見えているか確認すること。" -ForegroundColor Red
        }
        exit 1
    }
    Write-Host "[OK] fcc 経路 (:8082) — $($cfg.model) を確認" -ForegroundColor Green
}

# --- VRAM プリフライト ---------------------------------------------------------
# g24 は共用機で、他ユーザーが VRAM を握っているとモデルがロードできず全試行が即 FAIL する。
# それを「合格率0%」と記録すると測定として無意味なので、先に止める
# (2026-07-12: 空き 0GiB で全試行 9 秒 FAIL、という無意味な結果を実際に出した)。
if ($cfg.backend -eq "local") {
    $need = if ($cfg.model -match "fable-t$|raw-gptoss") { 72000 } else { 22000 }   # 120B は 69GiB、30B は 22GiB
    try {
        $freeMiB = [int](ssh g24 "nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits" | Select-Object -First 1)
        if ($freeMiB -lt $need) {
            Write-Host ("中止: GPU 空き {0}GiB < 必要 {1}GiB。CPU へスピルして測定にならない。" -f `
                [math]::Round($freeMiB / 1024, 0), [math]::Round($need / 1024, 0)) -ForegroundColor Red
            Write-Host "      ./vram.sh で使用状況を確認し、空いてから再実行すること。" -ForegroundColor Red
            exit 1
        }
        Write-Host ("[OK] GPU 空き {0}GiB" -f [math]::Round($freeMiB / 1024, 0)) -ForegroundColor Green
    } catch {
        Write-Host "[--] VRAM 確認をスキップ(ssh 応答なし)" -ForegroundColor DarkGray
    }
}

$tasksDir = Join-Path $here "tasks"
$taskDirs = if ($Task) { @(Join-Path $tasksDir $Task) } else { Get-ChildItem $tasksDir -Directory | Sort-Object Name | ForEach-Object { $_.FullName } }
if (-not $taskDirs) { throw "タスクが見つからない: $tasksDir" }

$runId = "{0}-k{1}-{2}" -f $Arm, $K, (Get-Date -Format "yyyyMMdd-HHmmss")
$resultsDir = Join-Path $here "results"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$workRoot = Join-Path ([IO.Path]::GetTempPath()) "fablet-bench\$runId"

$disciplineFile = Join-Path $repoRoot "fable-coding.txt"
$records = @()

foreach ($taskDir in $taskDirs) {
    $taskName = Split-Path $taskDir -Leaf
    $prompt = Get-Content (Join-Path $taskDir "prompt.txt") -Raw
    $verify = Join-Path $taskDir "verify.py"
    if (-not (Test-Path $verify)) { throw "verify.py が無い: $taskDir" }

    for ($i = 1; $i -le $K; $i++) {
        $work = Join-Path $workRoot "$taskName\try-$i"
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        Copy-Item -Recurse -Force (Join-Path $taskDir "repo\*") $work

        Write-Host ("[{0}] try {1}/{2} ..." -f $taskName, $i, $K) -NoNewline
        $t0 = Get-Date
        $timedOut = $false

        # 権限。採点は外部の verify.py が行うため、タスクを解くのにシェルは要らない。
        $permArgs = if ($Permissions -eq "bypass") {
            @("--dangerously-skip-permissions")
        } else {
            @("--permission-mode", "acceptEdits", "--disallowedTools", "Bash")
        }

        $agentArgs = @("-p", $prompt) + $permArgs + @("--model", $cfg.model)
        if ($cfg.discipline) {
            $agentArgs += @("--append-system-prompt", (Get-Content $disciplineFile -Raw))
        }

        # ローカル/OpenAI アームは fcc 経由。Anthropic アームは素の claude(本物)。
        $envVars = @{}
        if ($cfg.backend -ne "anthropic") {
            $envVars["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:8082"
            $envVars["ANTHROPIC_AUTH_TOKEN"] = "fablet-local"
            $envVars["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
        }

        # 注意: エージェントの出力は *> でログファイルへ丸ごと落とす。PowerShell 5.1 で native
        # コマンドの stderr をパイプラインに混ぜる(2>&1)と各行が ErrorRecord に包まれ、
        # 受け側の扱い次第で本文が丸ごと消える。エラー本文はベンチの命綱なのでファイルに出す。
        $log = Join-Path $workRoot "$taskName-try$i.log"
        $job = Start-Job -ScriptBlock {
            param($work, $agentArgs, $log, $envVars)
            $ErrorActionPreference = "Continue"
            foreach ($k in $envVars.Keys) { Set-Item -Path "env:$k" -Value $envVars[$k] }
            Set-Location $work
            & claude @agentArgs *> $log
        } -ArgumentList $work, $agentArgs, $log, $envVars

        if (Wait-Job $job -Timeout $TimeoutSec) {
            # [string] で受けること。Get-Content -Raw の戻り値には PS のノートプロパティが付いており、
            # そのまま ConvertTo-Json するとオブジェクトとして書き出される。
            $agentOut = if (Test-Path $log) { [string](Get-Content $log -Raw) } else { "(no output)" }
        } else {
            $timedOut = $true
            Stop-Job $job
            $agentOut = "(timeout after ${TimeoutSec}s)"
        }
        Remove-Job $job -Force

        $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)

        # 隠しテストを実行する。verify.py は work の外にあり、エージェントは触れていない。
        Push-Location $work
        try {
            $verifyOut = & python $verify 2>&1
            $passed = ($LASTEXITCODE -eq 0) -and (-not $timedOut)
        } finally {
            Pop-Location
        }

        Write-Host (" {0}  ({1}s)" -f $(if ($passed) { "PASS" } else { "FAIL" }), $elapsed) `
            -ForegroundColor $(if ($passed) { "Green" } else { "Red" })

        $records += [pscustomobject]@{
            task       = $taskName
            try        = $i
            arm        = $Arm
            model      = $cfg.model
            discipline = $cfg.discipline
            passed     = $passed
            timed_out  = $timedOut
            elapsed_s  = $elapsed
            verify_out = ($verifyOut -join "`n")
            agent_out  = $agentOut
        }
    }
}

# 集計: pass@1 は全試行の平均、pass@k はタスクごとに1回でも通ったか
$byTask = $records | Group-Object task
$passAt1 = [math]::Round((($records | Where-Object passed).Count / $records.Count) * 100, 1)
$passAtK = [math]::Round((($byTask | Where-Object { $_.Group | Where-Object passed }).Count / $byTask.Count) * 100, 1)

$summary = [pscustomobject]@{
    run_id     = $runId
    arm        = $Arm
    model      = $cfg.model
    discipline = $cfg.discipline
    backend    = $cfg.backend
    k          = $K
    tasks      = $byTask.Count
    trials     = $records.Count
    pass_at_1  = $passAt1
    pass_at_k  = $passAtK
    median_s   = [math]::Round((($records.elapsed_s | Sort-Object)[[int]($records.Count / 2)]), 1)
    records    = $records
}

$outFile = Join-Path $resultsDir "$runId.json"
$summary | ConvertTo-Json -Depth 6 | Out-File $outFile -Encoding utf8

Write-Host ""
Write-Host "=== $runId ===" -ForegroundColor Cyan
Write-Host ("タスク {0} / 試行 {1}" -f $byTask.Count, $records.Count)
Write-Host ("pass@1 : {0}%   (1回で通る確率)" -f $passAt1)
Write-Host ("pass@{0} : {1}%   (k回のうち1回でも通る確率)" -f $K, $passAtK)
Write-Host ("中央値レイテンシ: {0}s" -f $summary.median_s)
Write-Host "詳細: $outFile"
Write-Host ""
Write-Host "作業ディレクトリを削除する: Remove-Item -Recurse -Force '$workRoot'" -ForegroundColor DarkGray
