$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\src\SystemStats.ps1"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    if (-not $Condition) {
        throw $Name
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Actual,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    if ($Expected -ne $Actual) {
        throw "$Name expected '$Expected' but got '$Actual'"
    }
}

$snapshot = Get-SystemHealthSnapshot
$labels = @($snapshot.Metrics | ForEach-Object { $_.Label })

Assert-True ($null -ne $snapshot.Power) 'Snapshot should include power summary'
Assert-True (-not [string]::IsNullOrWhiteSpace($snapshot.HealthLine)) 'Snapshot should include health line'
Assert-True ($null -ne $snapshot.TopProcesses) 'Snapshot should include top processes'
Assert-True ($labels -contains 'CPU Usage') 'Snapshot should include CPU usage'
Assert-True ($labels -contains 'RAM') 'Snapshot should include RAM'
Assert-True ($labels -contains 'GPU Usage') 'Snapshot should include GPU usage'
Assert-True (-not ($labels -contains 'CPU Temp')) 'Snapshot should not include CPU temperature'
Assert-True (-not ($labels -contains 'GPU Temp')) 'Snapshot should not include GPU temperature'
Assert-Equal 3 $labels.Count 'Snapshot metric count'
Assert-True ($snapshot.TopProcesses.Count -le 3) 'Snapshot should include at most three top processes'
foreach ($process in $snapshot.TopProcesses) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($process.Name)) 'Top process should include name'
    Assert-True (-not [string]::IsNullOrWhiteSpace($process.ProcessName)) 'Top process should include raw process name'
    Assert-True ($process.MemoryMb -ge 0) 'Top process should include memory'
    Assert-True ($process.CpuPercent -ge 0) 'Top process should include sampled CPU percent'
}

Assert-Equal 'Microsoft Edge' (Get-ProcessDisplayName -ProcessName 'msedge') 'Edge process display name'
Assert-Equal 'Windows Service Host' (Get-ProcessDisplayName -ProcessName 'svchost') 'Service host process display name'
Assert-Equal 'Windows Search' (Get-ProcessDisplayName -ProcessName 'SearchHost') 'Search host process display name'
Assert-Equal 'My Custom App' (Get-ProcessDisplayName -ProcessName 'myCustomApp') 'Fallback process display name'

$cachedProcesses = @(
    [pscustomobject]@{ Name = 'Cached App'; ProcessName = 'cachedapp'; CpuPercent = 12.3; MemoryMb = 456; ProcessCount = 2 }
)
$fastSnapshot = Get-SystemHealthSnapshot -TopProcesses $cachedProcesses -SkipTopProcessRefresh
$fastTopProcesses = @($fastSnapshot.TopProcesses)
Assert-Equal 1 $fastTopProcesses.Count 'Fast snapshot should reuse cached top process rows'
Assert-Equal 'Cached App' $fastTopProcesses[0].Name 'Fast snapshot should preserve cached process display name'
Assert-Equal 12.3 $fastTopProcesses[0].CpuPercent 'Fast snapshot should preserve cached process CPU'
$emptyFastSnapshot = Get-SystemHealthSnapshot -SkipTopProcessRefresh
Assert-Equal 0 @($emptyFastSnapshot.TopProcesses).Count 'Fast snapshot without cache should not emit null process rows'
$cachedGpu = [pscustomobject]@{ Temperature = $null; Usage = 42; Source = 'Cached GPU sample' }
$cachedGpuSnapshot = Get-SystemHealthSnapshot -GpuSnapshot $cachedGpu -SkipGpuRefresh -SkipTopProcessRefresh
$cachedGpuMetric = $cachedGpuSnapshot.Metrics | Where-Object Label -eq 'GPU Usage' | Select-Object -First 1
Assert-Equal 42 $cachedGpuMetric.Value 'Fast snapshot should reuse cached GPU usage'
Assert-Equal 'Cached GPU sample' $cachedGpuMetric.Detail 'Fast snapshot should preserve cached GPU source'
$hiddenGpuSnapshot = Get-SystemHealthSnapshot -IncludeGpu:$false -IncludeTopProcesses:$false
$hiddenLabels = @($hiddenGpuSnapshot.Metrics | ForEach-Object { $_.Label })
Assert-True (-not ($hiddenLabels -contains 'GPU Usage')) 'Hidden GPU should remove GPU metric'
Assert-True (-not ($hiddenGpuSnapshot.HealthLine -match 'GPU')) 'Hidden GPU should remove GPU from health line'
Assert-Equal 0 @($hiddenGpuSnapshot.TopProcesses).Count 'Hidden top processes should remove process rows'

$sensorObjects = @(
    [pscustomobject]@{ HardwareType = 'Cpu'; SensorType = 'Temperature'; Name = 'Core #1'; Value = 61 },
    [pscustomobject]@{ HardwareType = 'Cpu'; SensorType = 'Temperature'; Name = 'CPU Package'; Value = 66 },
    [pscustomobject]@{ HardwareType = 'GpuNvidia'; SensorType = 'Temperature'; Name = 'GPU Core'; Value = 55 }
)

$bestCpuTemp = Select-BestCpuTemperature -Sensors $sensorObjects
Assert-Equal 66 $bestCpuTemp.Value 'CPU package temperature is preferred over core sensors'
Assert-Equal 'CPU Package' $bestCpuTemp.Name 'CPU package sensor name is preserved'
Assert-Equal 'Run as administrator for CPU temperature' (Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $true -IsAdministrator $false) 'Non-admin temperature guidance'
Assert-Equal 'Elevated, but CPU temperature values are not readable' (Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $true -IsAdministrator $true) 'Elevated unavailable temperature guidance'
Assert-Equal 'Install CPU temperature support from Settings' (Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $false -IsAdministrator $false) 'Missing library temperature guidance'
Assert-Equal 'Healthy' (Get-SystemHealthScore -CpuUsage 25 -RamUsage 40 -GpuUsage 20) 'Healthy score'
Assert-Equal 'Busy' (Get-SystemHealthScore -CpuUsage 70 -RamUsage 50 -GpuUsage 20) 'Busy score'
Assert-Equal 'Heavy Load' (Get-SystemHealthScore -CpuUsage 95 -RamUsage 50 -GpuUsage 20) 'Heavy load score'

Write-Host 'SystemStats.Tests passed'
