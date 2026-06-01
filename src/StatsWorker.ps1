param(
    [Parameter(Mandatory = $true)] [string] $OutputPath,
    [int] $IntervalMilliseconds = 1000,
    [int] $GpuIntervalMilliseconds = 3000,
    [int] $ProcessIntervalMilliseconds = 6000,
    $IncludeGpu = $true,
    $IncludeTopProcesses = $true,
    [switch] $Once
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\SystemStats.ps1"

function ConvertTo-WorkerBoolean {
    param(
        $Value,
        [bool] $Default
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return $Value
    }

    $text = $Value.ToString().Trim()
    if ($text -match '^(true|1|\$true)$') {
        return $true
    }

    if ($text -match '^(false|0|\$false)$') {
        return $false
    }

    return $Default
}

$IncludeGpu = ConvertTo-WorkerBoolean -Value $IncludeGpu -Default $true
$IncludeTopProcesses = ConvertTo-WorkerBoolean -Value $IncludeTopProcesses -Default $true

function Write-Snapshot {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        $GpuSnapshot = $null,
        [switch] $SkipGpuRefresh,
        [object[]] $TopProcesses = $null,
        [switch] $SkipTopProcessRefresh,
        [bool] $IncludeGpu = $true,
        [bool] $IncludeTopProcesses = $true
    )

    $snapshot = Get-SystemHealthSnapshot `
        -GpuSnapshot $GpuSnapshot `
        -SkipGpuRefresh:$SkipGpuRefresh `
        -TopProcesses $TopProcesses `
        -SkipTopProcessRefresh:$SkipTopProcessRefresh `
        -IncludeGpu:$IncludeGpu `
        -IncludeTopProcesses:$IncludeTopProcesses
    $json = $snapshot | ConvertTo-Json -Depth 6 -Compress
    $tempPath = "$Path.tmp"
    Set-Content -Path $tempPath -Value $json -Encoding UTF8
    Move-Item -Path $tempPath -Destination $Path -Force
}

if ($Once) {
    Write-Snapshot -Path $OutputPath -IncludeGpu:$IncludeGpu -IncludeTopProcesses:$IncludeTopProcesses
    return
}

$topProcesses = @()
$gpuSnapshot = $null
$lastProcessRefresh = [DateTime]::MinValue
$lastGpuRefresh = [DateTime]::MinValue

while ($true) {
    try {
        $now = Get-Date
        $needsGpuRefresh = $IncludeGpu -and ($null -eq $gpuSnapshot -or (($now - $lastGpuRefresh).TotalMilliseconds -ge $GpuIntervalMilliseconds))
        if ($needsGpuRefresh) {
            $gpuSnapshot = Get-GpuSnapshot
            $lastGpuRefresh = Get-Date
        }

        $needsProcessRefresh = $IncludeTopProcesses -and ($topProcesses.Count -eq 0 -or (($now - $lastProcessRefresh).TotalMilliseconds -ge $ProcessIntervalMilliseconds))
        if ($needsProcessRefresh) {
            $topProcesses = @(Get-TopCpuProcesses -Count 3)
            $lastProcessRefresh = Get-Date
        }

        Write-Snapshot -Path $OutputPath -GpuSnapshot $gpuSnapshot -SkipGpuRefresh -TopProcesses $topProcesses -SkipTopProcessRefresh -IncludeGpu:$IncludeGpu -IncludeTopProcesses:$IncludeTopProcesses
    }
    catch {
        $errorSnapshot = [pscustomobject]@{
            Metrics = @()
            Power = $null
            TopProcesses = @($topProcesses)
            HealthScore = 'Unavailable'
            HealthLine = 'Unable to refresh stats'
            OverallStatus = 'Unavailable'
            Message = 'Unable to refresh stats'
            Tooltip = 'PC Status'
            UpdatedAt = Get-Date
        }
        $errorSnapshot | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $OutputPath -Encoding UTF8
    }

    Start-Sleep -Milliseconds $IntervalMilliseconds
}
