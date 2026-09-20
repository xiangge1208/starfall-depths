param(
    [int]$Seeds = 1000,
    [string]$Floors = "1",
    [switch]$Full,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$runId = [guid]::NewGuid().ToString("N")
$logDir = Join-Path ([System.IO.Path]::GetTempPath()) ("starfall-gate-" + $runId)
New-Item -ItemType Directory -Path $logDir | Out-Null

function Invoke-GateStep([string]$Name, [scriptblock]$Action, [string]$LogName) {
    $log = Join-Path $logDir $LogName
    Write-Host "GATE $Name START"
    Push-Location $repo
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Keep native stdout/stderr visible while retaining the native exit code.
        # The scriptblock is invoked directly so $LASTEXITCODE remains the code
        # from the final native command (cmd/python/godot).
        & $Action 2>&1 | Tee-Object -FilePath $log | Out-Host
        $rc = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorAction
        Pop-Location
    }
    if ($null -eq $rc) { $rc = 0 }
    if ($rc -ne 0) {
        Write-Host "GATE $Name FAIL rc=$rc"
        throw "gate step '$Name' failed"
    }
    Write-Host "GATE $Name PASS"
    return $log
}

Invoke-GateStep "import" { & $godot --headless --path . --import } "import.log" | Out-Null
$testStartedAt = Get-Date
Invoke-GateStep "tests" { & cmd /c tools\run_tests.cmd } "tests.log" | Out-Null
# 进程 exit 0 之外，再读取本次最新 XML 报告的业务统计，防止 runner 在
# 报告不完整或仅部分套件执行时仍被误判为通过。
$report = $null
for ($attempt = 0; $attempt -lt 30 -and $null -eq $report; $attempt++) {
    $report = Get-ChildItem -Path (Join-Path $repo "reports") -Filter "results.xml" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $testStartedAt.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $report) { Start-Sleep -Milliseconds 250 }
}
if ($null -eq $report) { throw "gate tests report missing" }
[xml]$reportXml = Get-Content -LiteralPath $report.FullName
$suiteRoot = $reportXml.testsuites
$reportFailures = [int]$suiteRoot.failures
$reportErrors = [int]$suiteRoot.errors
$reportSkipped = [int]$suiteRoot.skipped
$reportFlaky = [int]$suiteRoot.flaky
$reportOrphans = [int]$suiteRoot.orphans
$reportTests = [int]$suiteRoot.tests
if ($reportTests -le 0 -or $reportFailures -ne 0 -or $reportErrors -ne 0 -or
    $reportSkipped -ne 0 -or $reportFlaky -ne 0 -or $reportOrphans -ne 0) {
    throw ("gate tests contract failed: tests={0} failures={1} errors={2} skipped={3} flaky={4} orphans={5}" -f
        $reportTests, $reportFailures, $reportErrors, $reportSkipped, $reportFlaky, $reportOrphans)
}
Write-Host ("GATE tests-contract PASS tests={0} failures=0 errors=0 skipped=0 flaky=0 orphans=0 report={1}" -f
    $reportTests, $report.FullName)
Invoke-GateStep "dungeon" { & $godot --headless --path . --script tools/validate_dungeon.gd -- --seeds=$Seeds --floors=$Floors } "dungeon.log" | Out-Null
Invoke-GateStep "art" { & python tools/art_qa_check.py } "art.log" | Out-Null

if ($Full) {
    Invoke-GateStep "perf" { & $godot --headless --path . res://tests/scenes/perf_probe.tscn -- --uncapped } "perf.log" | Out-Null
}

$allLogPaths = @(
    (Join-Path $logDir "import.log"),
    (Join-Path $logDir "dungeon.log"),
    (Join-Path $logDir "art.log")
)
if ($Full) {
    $allLogPaths += (Join-Path $logDir "perf.log")
}
$existingLogs = @($allLogPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
# tests.log 包含大量刻意覆盖失败路径的 ERROR/backtrace 文本；测试进程自身退出码与
# 统计负责判定它。因此这里只扫描固定的非测试步骤日志。
$errorLines = @()
if ($existingLogs.Count -gt 0) {
    $errorLines = @(Select-String -LiteralPath $existingLogs -Pattern '(ERROR:|SCRIPT ERROR|Invalid call|Parse Error|FATAL|GDScript backtrace)' |
        ForEach-Object { "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() })
}
if ($errorLines.Count -gt 0) {
    Write-Host "GATE logs FAIL errors=$($errorLines.Count)"
    $errorLines | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    throw "gate logs contain runtime errors"
}

$status = git -C $repo status --porcelain
if ($status -and -not $AllowDirty) {
    Write-Host "GATE hygiene FAIL dirty_worktree"
    $status | ForEach-Object { Write-Host "  $_" }
    throw "gate requires a clean worktree"
}

Write-Host "GATE logs PASS errors=0"
if ($status) {
    Write-Host "GATE hygiene SKIP dirty_worktree_allowed"
} else {
    Write-Host "GATE hygiene PASS clean_worktree"
}
Write-Host "GATE RESULT=PASS seeds=$Seeds floors=$Floors full=$Full logs=$logDir"
