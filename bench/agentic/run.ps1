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
    #   gpt / gpt-mini  OpenAI モデル(gpt-proxy.ps1 が立てる LiteLLM 経由。OPENAI_API_KEY が必要)
    [ValidateSet("fable-t", "fable-t-mid", "fable-t-loop", "fable-t-mid-loop", "raw-gptoss", "raw-qwen", "opus", "sonnet", "gpt", "gpt-mini")]
    [string]$Arm = "fable-t",

    [int]$K = 1,
    [string]$Task = "",
    [int]$TimeoutSec = 1800,

    # エージェントに与える権限。**モードが違う結果を混ぜて比較してはならない**(解ける範囲が変わる)。
    #
    #   python (既定) — 編集を自動承認し、加えて **python の実行だけ**を許す(Bash(python:*))。
    #                   エージェントが自分でテストを書いて回し、失敗を読んで直す
    #                   「検証ループ」を閉じられる。FableT の思考規律はまさにこれを要求しており、
    #                   これを禁じると規律の効果は測れない(2026-07-12 の edit モード実測では
    #                   規律あり/なしで差が出なかった。ループを封じていたため)。
    #                   git・rm・curl 等は許可しないので、ホストで任意コマンドは走らない。
    #   edit          — 編集のみ。Bash なし。「一発書き」の能力を測る。過去の測定はこの条件。
    #   bypass        — 全権限を素通し。**ホスト上で任意のコマンドが実行される。**
    #                   使い捨てのサンドボックスでのみ使うこと。
    [ValidateSet("python", "edit", "bypass")]
    [string]$Permissions = "python"
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
    # loop アーム: モデルが自発的にテストを書かない実測(RESULTS.md 07-20)へのハーネス側対策。
    # test_scratch.py が無ければ書かせ、失敗していれば出力を貼って直させる(最大3ラウンド)。
    # 「品質は賢さではなく試行回数で買う」の -p 単発版。
    "fable-t-loop"     = @{ backend = "local"; model = "anthropic/ollama/fable-t";     discipline = $true; loop = $true; note = "120B + 規律 + 強制検証ループ" }
    "fable-t-mid-loop" = @{ backend = "local"; model = "anthropic/ollama/fable-t-mid"; discipline = $true; loop = $true; note = "30B + 規律 + 強制検証ループ" }
    # 注意: fcc が公開する ID をそのまま書くこと(綴りが違うと黙って Default に落ちる)。
    # raw-* は :latest 付きの形でしか公開されない。また fcc はモデル一覧を起動時にキャッシュ
    # するので、g24 にモデルを作ったら fcc-server を再起動しないと見えない(2026-07-12 に遭遇)。
    "raw-gptoss"  = @{ backend = "local";     model = "anthropic/ollama/raw-gptoss:latest"; discipline = $false; note = "素の gpt-oss:120b(規律なし)" }
    "raw-qwen"    = @{ backend = "local";     model = "anthropic/ollama/raw-qwen:latest";   discipline = $false; note = "素の qwen3:30b(規律なし)" }
    "opus"        = @{ backend = "anthropic"; model = "opus";                         discipline = $false; note = "Claude Opus 4.8" }
    "sonnet"      = @{ backend = "anthropic"; model = "sonnet";                       discipline = $false; note = "Claude Sonnet" }
    # GPT は fcc では叩けない。fcc は "free-claude-code" の名のとおり無料プロバイダ専用で、
    # OPENAI_API_KEY を受け付ける口が無い(NIM/OpenRouter/Gemini/DeepSeek/Groq 等のみ。
    # 2026-07-12 にキーを渡して確認済み: OpenAI モデルは /v1/models に一切出ない)。
    # そこで gpt-proxy.ps1 が LiteLLM を :8083 に立て、Anthropic 形式(/v1/messages)を
    # OpenAI へ中継する。Claude Code から見れば fcc と同じ「Anthropic 互換の口」である。
    "gpt"         = @{ backend = "openai";    model = "gpt-5.4";      discipline = $false; note = "OpenAI gpt-5.4 (LiteLLM 経由)" }
    "gpt-mini"    = @{ backend = "openai";    model = "gpt-5.4-mini"; discipline = $false; note = "OpenAI gpt-5.4-mini (LiteLLM 経由)" }
}

$GPT_PROXY = "http://127.0.0.1:8083"

$cfg = $arms[$Arm]
Write-Host ("アーム: {0}  ({1})" -f $Arm, $cfg.note) -ForegroundColor Cyan

if ($cfg.backend -eq "anthropic") {
    Write-Host "警告: このアームは本物の Anthropic API を叩き、クレジット(利用枠)を消費する。" -ForegroundColor Yellow
    Write-Host "      比較測定の意図がなければ Ctrl+C で中止すること。5秒後に開始する。" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}
if ($cfg.backend -eq "openai") {
    # 中継は gpt-proxy.ps1 が立てる LiteLLM(:8083)。ここでは生きているかだけ見る。
    # キーはプロキシのプロセスが持つので、この run.ps1 はキーを触らない。
    try {
        Invoke-WebRequest -Uri "$GPT_PROXY/health/liveliness" -UseBasicParsing -TimeoutSec 3 | Out-Null
    } catch {
        Write-Host "中止: GPT 中継プロキシ($GPT_PROXY)が動いていない。" -ForegroundColor Red
        Write-Host "      先に別ウィンドウで .\gpt-proxy.ps1 を起動すること。" -ForegroundColor Red
        Write-Host "      (fcc は無料プロバイダ専用で OpenAI を扱えないため、LiteLLM で中継する)" -ForegroundColor Red
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
# ローカルアームは fcc 経由なので、トンネルと fcc-server が生きている必要がある。
# 落ちていれば起動する(fablet.ps1 と同じ手順)。
# Anthropic アーム(本物の claude)と OpenAI アーム(LiteLLM 経由)には不要。
if ($cfg.backend -eq "local") {
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
        Write-Host "      g24 にモデルが無いか、fcc が起動後に作られた可能性(fcc はモデル一覧を" -ForegroundColor Red
        Write-Host "      起動時にキャッシュする)。ollama list で確認し、fcc-server を再起動すること。" -ForegroundColor Red
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

    # 前のアームのモデルが載ったままだと、その VRAM を「他人が占有している」と誤認して中止する
    # (2026-07-12 実際に発生: fable-t-mid を載せたまま raw-qwen を始めようとして空き0GiB判定)。
    # これから使うモデル以外の FableT モデルは先にアンロードして、正味の空きで判断する。
    $target = ($cfg.model -replace "^anthropic/ollama/", "") -replace ":latest$", ""
    $ol = "OLLAMA_HOST=127.0.0.1:11500 `$HOME/ollama-dist/bin/ollama"
    $owned = @("fable-t", "fable-t-mid", "fable-t-o", "raw-gptoss", "raw-qwen", "fablet-fast", "fablet-chat")
    foreach ($m in ($owned | Where-Object { $_ -ne $target })) {
        ssh g24 "$ol stop $m 2>/dev/null" | Out-Null
    }
    Start-Sleep -Seconds 3

    try {
        $freeMiB = [int](ssh g24 "nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits" | Select-Object -First 1)

        # 目的のモデルが既にロード済みなら、その分の VRAM は確保済みなので空きに足して判断する
        $loaded = (ssh g24 "$ol ps") -join "`n"
        if ($loaded -match [regex]::Escape($target)) {
            Write-Host "[OK] $target は既にロード済み(VRAM 確保済み)" -ForegroundColor Green
            $freeMiB += $need
        }

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

        # 権限。python モードは「編集 + python の実行だけ」を許す。
        # allowedTools に Bash(python:*) を挙げつつ acceptEdits にすることで、
        # python 以外のシェル呼び出し(git/rm/curl 等)は承認待ちになり、-p の非対話実行では
        # 通らない。つまりホスト上で任意コマンドは走らないまま、検証ループだけが回る。
        $permArgs = switch ($Permissions) {
            "bypass" { @("--dangerously-skip-permissions") }
            "edit"   { @("--permission-mode", "acceptEdits", "--disallowedTools", "Bash") }
            "python" { @("--permission-mode", "acceptEdits",
                         "--allowedTools", "Read", "Edit", "Write", "Glob", "Grep",
                         "Bash(python:*)", "Bash(python3:*)") }
        }

        $agentArgs = @("-p", $prompt) + $permArgs + @("--model", $cfg.model)
        if ($cfg.discipline) {
            $agentArgs += @("--append-system-prompt", (Get-Content $disciplineFile -Raw))
        }

        # local  : fcc(:8082)経由     openai: LiteLLM(:8083)経由
        # anthropic: 素の claude(本物の Anthropic。環境変数を触らない)
        $envVars = @{}
        if ($cfg.backend -eq "local") {
            $envVars["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:8082"
            $envVars["ANTHROPIC_AUTH_TOKEN"] = "fablet-local"
            $envVars["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
        } elseif ($cfg.backend -eq "openai") {
            $envVars["ANTHROPIC_BASE_URL"] = $GPT_PROXY
            $envVars["ANTHROPIC_AUTH_TOKEN"] = "fablet-local"   # LiteLLM 側のダミーキー
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

        # 強制検証ループ(loop アーム)。ハーネスが「テストの存在と合否」を検査し、
        # 足りなければ修正指示を再投入する。隠しテスト(verify.py)は一切見せない。
        #
        # 30B の実測(RESULTS.md 07-20)で判明した2つの失敗を潰す設計:
        #   (A) テスト名は固定できない(モデルは test_<module>.py 等を勝手に付ける)
        #       → work 内の test*.py / *_test.py を全部拾う。
        #   (B) モデルは「壊れた実装に合わせた誤ったテスト」を書き、緑にして誤魔化す
        #       → 毎ラウンド、課題文の入出力例をそのままアサートせよと明示し、
        #         コードに合わせた期待値の書き換え・docstring改変を禁じる。
        if ($cfg.loop -and -not $timedOut) {
            # 公開例テスト(あれば)。prompt.txt に既に書かれている入出力例だけを
            # 実行可能にしたもので、隠しテスト(verify.py)ではない。モデルが自作テストに
            # 要件を書き漏らしても、ハーネスが公開例で必ず捕まえるための「網羅性の下限」。
            $examplesFile = Join-Path $taskDir "examples.py"
            $hasExamples = Test-Path $examplesFile

            foreach ($round in 1..3) {
                $ruleG = "テストは課題文に書かれた入出力例(エッジケースを含む)を一字一句そのままアサートすること。" +
                         "自分のコードの出力に合わせて期待値を書き換えたり、docstring を壊れた挙動に合わせて書き換えるのは禁止(それは修正ではない)。"

                # (1) 公開例テストを最優先で判定材料にする。ここが緑でないうちは終わらない。
                $exOk = $true; $exOut = ""
                if ($hasExamples) {
                    Push-Location $work
                    try { $o = & python $examplesFile 2>&1; $exOk = ($LASTEXITCODE -eq 0) } finally { Pop-Location }
                    $exOut = ($o | Out-String)
                }

                # (2) モデル自作のテスト(名前は固定できないので広く拾う)。
                $testFiles = @(Get-ChildItem -Path $work -File -Filter "*.py" |
                    Where-Object { $_.Name -match '(^test.*|.*_test)\.py$' })
                $tOk = $true; $tOut = ""
                foreach ($tf in $testFiles) {
                    Push-Location $work
                    try { $o = & python $tf.FullName 2>&1; $ok = ($LASTEXITCODE -eq 0) } finally { Pop-Location }
                    $tOut += "`n# $($tf.Name)`n" + ($o | Out-String)
                    if (-not $ok) { $tOk = $false }
                }

                if ($hasExamples -and -not $exOk) {
                    # 公開例が落ちている = 要件未達が確定。最優先で具体的に差し戻す。
                    $fb = "課題文に書かれた入出力例のうち、まだ満たせていないものがある。落ちた例:`n" + $exOut +
                          "`nこれらを満たすよう実装本体を直し、あなたのテストにもこの入力を全て含めて python で確認すること。$ruleG"
                } elseif ($testFiles.Count -eq 0) {
                    $fb = "テストファイルがまだ無い。課題文の要件(番号付き要件と例を全て)を網羅する test_check.py を書き、python で実行し、全て通るまで実装本体を直すこと。$ruleG"
                } elseif (-not $tOk) {
                    $fb = "テストが失敗している。出力:`n" + $tOut + "`n実装本体を直し、全て通るまで繰り返すこと。$ruleG"
                } else {
                    # 公開例も自作テストも緑。ここで初めて完了とみなす。
                    break
                }
                $fixArgs = @("-p", ($prompt + "`n`n[検証ラウンド $round] " + $fb)) + $permArgs + @("--model", $cfg.model)
                if ($cfg.discipline) { $fixArgs += @("--append-system-prompt", (Get-Content $disciplineFile -Raw)) }
                $job2 = Start-Job -ScriptBlock {
                    param($work, $agentArgs, $log, $envVars)
                    $ErrorActionPreference = "Continue"
                    foreach ($k in $envVars.Keys) { Set-Item -Path "env:$k" -Value $envVars[$k] }
                    Set-Location $work
                    & claude @agentArgs *> $log
                } -ArgumentList $work, $fixArgs, "$log.round$round", $envVars
                if (-not (Wait-Job $job2 -Timeout $TimeoutSec)) { Stop-Job $job2; $timedOut = $true }
                Remove-Job $job2 -Force
                if ($timedOut) { break }
            }
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

        Write-Host (" {0}  ({1}s)" -f $(if ($passed) { "PASS" } else { "FAIL" }), $elapsed) `
            -ForegroundColor $(if ($passed) { "Green" } else { "Red" })

        $records += [pscustomobject]@{
            task        = $taskName
            try         = $i
            arm         = $Arm
            model       = $cfg.model
            discipline  = $cfg.discipline
            permissions = $Permissions
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
    run_id      = $runId
    arm         = $Arm
    model       = $cfg.model
    discipline  = $cfg.discipline
    backend     = $cfg.backend
    permissions = $Permissions   # 条件の違う結果を取り違えないため必ず残す
    k           = $K
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
