# run.ps1 — エージェントベンチ実行器
#
#   .\run.ps1 -Agent fablet -K 3          # FableT(ローカル・無料)で pass@3
#   .\run.ps1 -Agent claude -K 1          # 素の claude(クレジット消費!)で pass@1
#   .\run.ps1 -Agent fablet -K 3 -Task interval-merge
#
# 各試行は tasks/<名前>/repo を一時ディレクトリへ複製した上で行う。エージェントには
# prompt.txt だけを渡し、隠しテスト(verify.py)は見せない。試行は互いに独立で、
# 前の試行の結果を次に渡さない(これが pass@k の定義であり、best-of-N の前提)。
#
# 前提: g24 の GPU に空きがあること。他ユーザーが VRAM を占有していると
# モデルがロードできず、全試行が即 FAIL する(./vram.sh で先に確認すること)。

param(
    [ValidateSet("fablet", "claude")]
    [string]$Agent = "fablet",
    [int]$K = 1,
    [string]$Task = "",
    [int]$TimeoutSec = 1800,

    # エージェントに与える権限。
    #   edit   (既定) — 編集は自動承認、Bash は与えない。採点は外部の verify.py が行うので、
    #                   タスクを解くのに Bash は要らない。ホストで任意コマンドが走らない。
    #   bypass         — 全権限を素通し(エージェントが自分でテストを回せる)。
    #                   **ホスト上で任意のコマンドが実行される。** 使い捨てのサンドボックス
    #                   でのみ使うこと。両モードの結果を混ぜて比較しないこと。
    [ValidateSet("edit", "bypass")]
    [string]$Permissions = "edit"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here "..\..")

if ($Permissions -eq "bypass") {
    Write-Host "警告: -Permissions bypass はエージェントの権限確認を全て素通しする。" -ForegroundColor Red
    Write-Host "      作業ディレクトリは一時領域だが、Bash はホスト上で走る。使い捨て環境でのみ使うこと。" -ForegroundColor Red
    Start-Sleep -Seconds 5
}

if ($Agent -eq "claude") {
    Write-Host "警告: --Agent claude は本物の Anthropic API を叩き、クレジットを消費する。" -ForegroundColor Yellow
    Write-Host "      比較測定の意図がなければ Ctrl+C で中止すること。5秒後に開始する。" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

# VRAM プリフライト。g24 は共用機で、他ユーザーが VRAM を握っているとモデルがロードできず
# 全試行が即 FAIL する。それを「合格率0%」と記録してしまうと測定として無意味なので、先に止める
# (2026-07-12: 空き 0GiB で全試行 9 秒 FAIL、という無意味な結果を実際に出した)。
if ($Agent -eq "fablet") {
    try {
        # 22GiB あれば既定の 30B は 100% GPU に載る(実測)。それ未満は測定にならない。
        $freeMiB = [int](ssh g24 "nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits" | Select-Object -First 1)
        if ($freeMiB -lt 22000) {
            Write-Host ("中止: g24 の GPU 空きが {0}GiB しかない。モデルがロードできず、測定結果が意味を持たない。" -f [math]::Round($freeMiB / 1024, 0)) -ForegroundColor Red
            Write-Host "      ./vram.sh で誰が使っているか確認し、空いてから再実行すること。" -ForegroundColor Red
            exit 1
        }
        Write-Host ("[OK] GPU 空き {0}GiB" -f [math]::Round($freeMiB / 1024, 0)) -ForegroundColor Green
    } catch {
        Write-Host "[--] VRAM 確認をスキップ(ssh 応答なし)" -ForegroundColor DarkGray
    }
}

$tasksDir = Join-Path $here "tasks"
$taskDirs = if ($Task) { @(Join-Path $tasksDir $Task) } else { Get-ChildItem $tasksDir -Directory | ForEach-Object { $_.FullName } }
if (-not $taskDirs) { throw "タスクが見つからない: $tasksDir" }

$runId = "{0}-k{1}-{2}" -f $Agent, $K, (Get-Date -Format "yyyyMMdd-HHmmss")
$resultsDir = Join-Path $here "results"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$workRoot = Join-Path ([IO.Path]::GetTempPath()) "fablet-bench\$runId"

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

        Write-Host "[$taskName] try $i/$K ..." -NoNewline
        $t0 = Get-Date
        $timedOut = $false
        Push-Location $work
        try {
            $agentArgs = if ($Permissions -eq "bypass") {
                @("-p", $prompt, "--dangerously-skip-permissions")
            } else {
                # 編集は自動承認するが Bash は与えない。採点は外部の verify.py が行うため、
                # タスクを解くのにシェルは不要で、ホスト上で任意コマンドが走る余地を残さない。
                @("-p", $prompt, "--permission-mode", "acceptEdits",
                  "--disallowedTools", "Bash")
            }
            # 注意: エージェントの出力は *> でログファイルへ丸ごと落とす。PowerShell 5.1 で
            # native コマンドの stderr をパイプラインに混ぜる(2>&1)と各行が ErrorRecord に
            # 包まれ、受け側の扱い次第で本文が丸ごと消える。エラー本文はベンチの命綱なので、
            # ストリームを触らずファイルに出す。
            $log = Join-Path $workRoot "$taskName-try$i.log"
            $job = if ($Agent -eq "fablet") {
                Start-Job -ScriptBlock {
                    param($launcher, $work, $agentArgs, $log)
                    $ErrorActionPreference = "Continue"
                    Set-Location $work
                    & $launcher @agentArgs *> $log
                } -ArgumentList (Join-Path $repoRoot "fablet.ps1"), $work, $agentArgs, $log
            } else {
                Start-Job -ScriptBlock {
                    param($work, $agentArgs, $log)
                    $ErrorActionPreference = "Continue"
                    Set-Location $work
                    & claude @agentArgs *> $log
                } -ArgumentList $work, $agentArgs, $log
            }
            if (Wait-Job $job -Timeout $TimeoutSec) {
                # [string] で受けること。Get-Content -Raw の戻り値には PS のノートプロパティが
                # 付いており、そのまま ConvertTo-Json するとオブジェクトとして書き出される。
                $agentOut = if (Test-Path $log) { [string](Get-Content $log -Raw) } else { "(no output)" }
            } else {
                $timedOut = $true
                Stop-Job $job
                $agentOut = "(timeout after ${TimeoutSec}s)"
            }
            Remove-Job $job -Force
        } finally {
            Pop-Location
        }
        $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)

        # 隠しテストを実行する。verify.py は work の外にあり、エージェントは触れていない。
        Push-Location $work
        try {
            $verifyOut = & python $verify 2>&1
            $passed = ($LASTEXITCODE -eq 0) -and (-not $timedOut)
        } finally {
            Pop-Location
        }

        Write-Host (" {0}  ({1}s)" -f $(if ($passed) { "PASS" } else { "FAIL" }), $elapsed) -ForegroundColor $(if ($passed) { "Green" } else { "Red" })

        $records += [pscustomobject]@{
            task       = $taskName
            try        = $i
            agent      = $Agent
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
    agent      = $Agent
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
