# selftest.ps1 — ベンチ自身の健全性を確認する
#
# 各タスクについて2方向を確かめる:
#   1. repo/ (壊れた状態) で verify.py が FAIL すること
#      → 落ちないテストは何も検証していない
#   2. repo/ に solution/ を上書きした状態で verify.py が PASS すること
#      → 通せないテストは解けない問題であり、モデルの性能ではなくタスクの欠陥を測ってしまう
#
# GPU もモデルも使わない(python だけ)。タスクを追加したら必ずこれを通すこと。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tasksDir = Join-Path $here "tasks"

$ok = 0
$ng = 0

foreach ($taskDir in (Get-ChildItem $tasksDir -Directory | Sort-Object Name)) {
    $name = $taskDir.Name
    $verify = Join-Path $taskDir.FullName "verify.py"
    $repo = Join-Path $taskDir.FullName "repo"
    $solution = Join-Path $taskDir.FullName "solution"

    $problems = @()
    foreach ($required in @($verify, $repo, $solution, (Join-Path $taskDir.FullName "prompt.txt"))) {
        if (-not (Test-Path $required)) { $problems += "欠品: $(Split-Path $required -Leaf)" }
    }
    if ($problems) {
        Write-Host ("[NG] {0,-16} {1}" -f $name, ($problems -join ", ")) -ForegroundColor Red
        $ng++
        continue
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) "fablet-selftest\$name"
    if (Test-Path $work) { Remove-Item -Recurse -Force $work }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Copy-Item -Recurse -Force (Join-Path $repo "*") $work

    # 1. 壊れた状態では落ちるべき
    Push-Location $work
    & python $verify *> $null
    $brokenCode = $LASTEXITCODE
    Pop-Location

    # 2. 参照解答を上書きすると通るべき
    Copy-Item -Recurse -Force (Join-Path $solution "*") $work
    Push-Location $work
    $fixedOut = & python $verify 2>&1
    $fixedCode = $LASTEXITCODE
    Pop-Location

    if ($brokenCode -eq 0) { $problems += "壊れた状態なのに PASS した(検証器が何も見ていない)" }
    if ($fixedCode -ne 0) { $problems += "参照解答でも FAIL した: $($fixedOut -join ' ')" }

    if ($problems) {
        Write-Host ("[NG] {0,-16} {1}" -f $name, ($problems -join " / ")) -ForegroundColor Red
        $ng++
    } else {
        Write-Host ("[OK] {0,-16} 壊れた状態=FAIL, 参照解答=PASS" -f $name) -ForegroundColor Green
        $ok++
    }

    Remove-Item -Recurse -Force $work
}

Write-Host ""
Write-Host ("タスク {0} 件: OK {1} / NG {2}" -f ($ok + $ng), $ok, $ng) -ForegroundColor Cyan
if ($ng -gt 0) { exit 1 }
