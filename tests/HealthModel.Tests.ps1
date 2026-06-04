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

$normalIcon = Get-TrayIconPalette -Status 'Normal'
Assert-Equal 31 $normalIcon.OuterRed 'Normal tray icon outer red'
Assert-Equal 138 $normalIcon.OuterGreen 'Normal tray icon outer green'
Assert-Equal 112 $normalIcon.OuterBlue 'Normal tray icon outer blue'

$warmIcon = Get-TrayIconPalette -Status 'Warm'
Assert-Equal 191 $warmIcon.OuterRed 'Warm tray icon outer red'
Assert-Equal 123 $warmIcon.OuterGreen 'Warm tray icon outer green'
Assert-Equal 36 $warmIcon.OuterBlue 'Warm tray icon outer blue'

$hotIcon = Get-TrayIconPalette -Status 'Hot'
Assert-Equal 196 $hotIcon.OuterRed 'Hot tray icon outer red'
Assert-Equal 57 $hotIcon.OuterGreen 'Hot tray icon outer green'
Assert-Equal 48 $hotIcon.OuterBlue 'Hot tray icon outer blue'

$unknownIcon = Get-TrayIconPalette -Status 'Unexpected'
Assert-Equal 128 $unknownIcon.OuterRed 'Unknown tray icon falls back to unavailable red'
Assert-Equal 130 $unknownIcon.OuterGreen 'Unknown tray icon falls back to unavailable green'
Assert-Equal 126 $unknownIcon.OuterBlue 'Unknown tray icon falls back to unavailable blue'

Write-Host 'HealthModel.Tests passed'
