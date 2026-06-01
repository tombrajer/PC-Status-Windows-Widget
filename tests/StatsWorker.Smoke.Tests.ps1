$ErrorActionPreference = 'Stop'

$snapshotPath = Join-Path $PSScriptRoot "worker-smoke-$PID.json"
if (Test-Path -LiteralPath $snapshotPath) {
    Remove-Item -LiteralPath $snapshotPath -Force
}

$workerPath = (Resolve-Path (Join-Path $PSScriptRoot '..\src\StatsWorker.ps1')).Path
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $workerPath,
    '-OutputPath', $snapshotPath,
    '-IntervalMilliseconds', '1000',
    '-GpuIntervalMilliseconds', '3000',
    '-ProcessIntervalMilliseconds', '6000',
    '-IncludeGpu:$false',
    '-IncludeTopProcesses:$false'
)

$workerProcess = Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru

try {
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $snapshotPath)) {
        Start-Sleep -Milliseconds 250
    }

    if (-not (Test-Path -LiteralPath $snapshotPath)) {
        if ($workerProcess.HasExited) {
            throw "Worker exited before writing snapshot with code $($workerProcess.ExitCode)"
        }

        throw 'Worker did not write snapshot'
    }

    $snapshot = Get-Content -Path $snapshotPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($snapshot.HealthLine)) {
        throw 'Snapshot missing health line'
    }

    $labels = @($snapshot.Metrics | ForEach-Object { $_.Label })
    if ($labels -contains 'GPU Usage') {
        throw 'Snapshot should hide GPU metric when disabled'
    }

    if (@($snapshot.TopProcesses).Count -ne 0) {
        throw 'Snapshot should hide top processes when disabled'
    }
}
finally {
    if ($workerProcess -and -not $workerProcess.HasExited) {
        Stop-Process -Id $workerProcess.Id -Force
    }

    if (Test-Path -LiteralPath $snapshotPath) {
        Remove-Item -LiteralPath $snapshotPath -Force
    }
}

Write-Host 'StatsWorker smoke passed'
