$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\src\AppSettings.ps1"

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

$settingsPath = Join-Path $PSScriptRoot "settings-test-$PID.json"
if (Test-Path -LiteralPath $settingsPath) {
    Remove-Item -LiteralPath $settingsPath -Force
}

try {
    $defaults = Get-AppSettings -Path $settingsPath
    Assert-Equal 'Auto' $defaults.ThemeMode 'Default theme mode'
    Assert-Equal $false $defaults.StartWithWindows 'Default startup setting'
    Assert-Equal $true $defaults.RunElevatedOnLaunch 'Default elevation setting'
    Assert-Equal 'Balanced' $defaults.RefreshPreset 'Default refresh preset'
    Assert-Equal $true $defaults.ShowBatteryPower 'Default battery card setting'
    Assert-Equal $true $defaults.ShowCpuUsage 'Default CPU card setting'
    Assert-Equal $true $defaults.ShowMemoryUsage 'Default memory card setting'
    Assert-Equal $true $defaults.ShowGpuUsage 'Default GPU setting'
    Assert-Equal $true $defaults.ShowTopProcesses 'Default top processes setting'
    Assert-Equal $true $defaults.ShowDetailedTrayTooltip 'Default detailed tooltip setting'

    $defaults.ThemeMode = 'Dark'
    $defaults.StartWithWindows = $true
    $defaults.RefreshPreset = 'Fast'
    $defaults.ShowBatteryPower = $false
    $defaults.ShowCpuUsage = $false
    $defaults.ShowMemoryUsage = $false
    $defaults.ShowGpuUsage = $false
    Save-AppSettings -Settings $defaults -Path $settingsPath | Out-Null

    $loaded = Get-AppSettings -Path $settingsPath
    Assert-Equal 'Dark' $loaded.ThemeMode 'Saved theme mode'
    Assert-Equal $true $loaded.StartWithWindows 'Saved startup setting'
    Assert-Equal 'Fast' $loaded.RefreshPreset 'Saved refresh preset'
    Assert-Equal $false $loaded.ShowBatteryPower 'Saved battery card setting'
    Assert-Equal $false $loaded.ShowCpuUsage 'Saved CPU card setting'
    Assert-Equal $false $loaded.ShowMemoryUsage 'Saved memory card setting'
    Assert-Equal $false $loaded.ShowGpuUsage 'Saved GPU setting'

    Set-Content -Path $settingsPath -Value '{ invalid json' -Encoding UTF8
    $fallback = Get-AppSettings -Path $settingsPath
    Assert-Equal 'Auto' $fallback.ThemeMode 'Invalid JSON falls back to defaults'

    $eco = Get-RefreshPresetIntervals -Preset 'Eco'
    Assert-Equal 3000 $eco.CoreMilliseconds 'Eco core interval'
    Assert-Equal 8000 $eco.GpuMilliseconds 'Eco GPU interval'
    Assert-Equal 15000 $eco.ProcessMilliseconds 'Eco process interval'

    $balanced = Get-RefreshPresetIntervals -Preset 'Balanced'
    Assert-Equal 1000 $balanced.CoreMilliseconds 'Balanced core interval'
    Assert-Equal 3000 $balanced.GpuMilliseconds 'Balanced GPU interval'
    Assert-Equal 6000 $balanced.ProcessMilliseconds 'Balanced process interval'

    $fast = Get-RefreshPresetIntervals -Preset 'Fast'
    Assert-Equal 750 $fast.CoreMilliseconds 'Fast core interval'
    Assert-Equal 2000 $fast.GpuMilliseconds 'Fast GPU interval'
    Assert-Equal 4000 $fast.ProcessMilliseconds 'Fast process interval'

    Assert-Equal 'Balanced' (Normalize-RefreshPreset 'Unknown') 'Unknown preset normalizes to Balanced'
    Assert-Equal 'Auto' (Normalize-ThemeMode 'Unexpected') 'Unknown theme normalizes to Auto'
    Assert-Equal 'Light' (Resolve-EffectiveThemeMode -ThemeMode 'Auto' -WindowsAppsUseLightTheme $null) 'Auto fallback theme'
    Assert-Equal 'Dark' (Resolve-EffectiveThemeMode -ThemeMode 'Auto' -WindowsAppsUseLightTheme 0) 'Auto dark Windows theme'
    Assert-Equal 'Light' (Resolve-EffectiveThemeMode -ThemeMode 'Auto' -WindowsAppsUseLightTheme 1) 'Auto light Windows theme'
    Assert-Equal 'Dark' (Resolve-EffectiveThemeMode -ThemeMode 'Dark' -WindowsAppsUseLightTheme 1) 'Manual dark overrides Windows theme'

    $theme = Get-ThemePalette -EffectiveThemeMode 'Dark'
    Assert-Equal '#111312' $theme.ShellBackground 'Dark shell background'
    Assert-True (-not [string]::IsNullOrWhiteSpace($theme.PrimaryText)) 'Dark palette primary text'
}
finally {
    if (Test-Path -LiteralPath $settingsPath) {
        Remove-Item -LiteralPath $settingsPath -Force
    }
}

Write-Host 'AppSettings.Tests passed'
