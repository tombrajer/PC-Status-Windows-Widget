$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\src\HealthModel.ps1"

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

Assert-Equal 'Unavailable' (Get-TemperatureStatus $null) 'Null temperature'
Assert-Equal 'Normal' (Get-TemperatureStatus 58) 'Normal temperature'
Assert-Equal 'Warm' (Get-TemperatureStatus 78) 'Warm temperature'
Assert-Equal 'Hot' (Get-TemperatureStatus 91) 'Hot temperature'

Assert-Equal 'Normal' (Get-LoadStatus 34) 'Normal load'
Assert-Equal 'Warm' (Get-LoadStatus 82) 'Warm load'
Assert-Equal 'Hot' (Get-LoadStatus 96) 'Hot load'

$metrics = @()
$metrics += New-HealthMetric -Label 'CPU Temp' -Value 58 -Unit 'C' -Status 'Normal' -Detail 'CPU package'
$metrics += New-HealthMetric -Label 'RAM' -Value 88 -Unit '%' -Status 'Warm' -Detail '14.1 / 16 GB'
$metrics += New-HealthMetric -Label 'GPU Temp' -Value $null -Unit 'C' -Status 'Unavailable' -Detail 'No sensor'

Assert-Equal 'Warm' (Get-OverallHealthStatus $metrics) 'Overall status selects highest available severity'
Assert-Equal '58 C' (Format-MetricValue $metrics[0]) 'Formatted available metric'
Assert-Equal '88%' (Format-MetricValue $metrics[1]) 'Formatted percent metric'
Assert-Equal 'Unavailable' (Format-MetricValue $metrics[2]) 'Formatted unavailable metric'
Assert-Equal 'Some sensors unavailable' (Get-HealthMessage -Status 'Normal' -HasUnavailable $true) 'Normal status with missing sensors'
Assert-Equal 'Running warm' (Get-HealthMessage -Status 'Warm' -HasUnavailable $true) 'Warm status takes priority over missing sensors'

Write-Host 'HealthModel.Tests passed'
