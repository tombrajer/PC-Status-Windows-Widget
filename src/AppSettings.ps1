function Get-AppSettingsPath {
    $baseDirectory = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'PCStatus'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'PCStatus'
    }

    return (Join-Path $baseDirectory 'settings.json')
}

function New-DefaultAppSettings {
    [pscustomobject]@{
        ThemeMode = 'Auto'
        StartWithWindows = $false
        RefreshPreset = 'Balanced'
        ShowBatteryPower = $true
        ShowCpuUsage = $true
        ShowMemoryUsage = $true
        ShowGpuUsage = $true
        ShowTopProcesses = $true
        ShowDetailedTrayTooltip = $true
    }
}

function Normalize-ThemeMode {
    param([string] $ThemeMode)

    if ($ThemeMode -in @('Light', 'Dark', 'Auto')) {
        return $ThemeMode
    }

    return 'Auto'
}

function Normalize-RefreshPreset {
    param([string] $Preset)

    if ($Preset -in @('Eco', 'Balanced', 'Fast')) {
        return $Preset
    }

    return 'Balanced'
}

function ConvertTo-BoolSetting {
    param(
        $Value,
        [bool] $Default
    )

    if ($null -eq $Value) {
        return $Default
    }

    try {
        return [bool] $Value
    }
    catch {
        return $Default
    }
}

function Normalize-AppSettings {
    param($Settings)

    $defaults = New-DefaultAppSettings
    if ($null -eq $Settings) {
        return $defaults
    }

    [pscustomobject]@{
        ThemeMode = Normalize-ThemeMode $Settings.ThemeMode
        StartWithWindows = ConvertTo-BoolSetting -Value $Settings.StartWithWindows -Default $defaults.StartWithWindows
        RefreshPreset = Normalize-RefreshPreset $Settings.RefreshPreset
        ShowBatteryPower = ConvertTo-BoolSetting -Value $Settings.ShowBatteryPower -Default $defaults.ShowBatteryPower
        ShowCpuUsage = ConvertTo-BoolSetting -Value $Settings.ShowCpuUsage -Default $defaults.ShowCpuUsage
        ShowMemoryUsage = ConvertTo-BoolSetting -Value $Settings.ShowMemoryUsage -Default $defaults.ShowMemoryUsage
        ShowGpuUsage = ConvertTo-BoolSetting -Value $Settings.ShowGpuUsage -Default $defaults.ShowGpuUsage
        ShowTopProcesses = ConvertTo-BoolSetting -Value $Settings.ShowTopProcesses -Default $defaults.ShowTopProcesses
        ShowDetailedTrayTooltip = ConvertTo-BoolSetting -Value $Settings.ShowDetailedTrayTooltip -Default $defaults.ShowDetailedTrayTooltip
    }
}

function Get-AppSettings {
    param([string] $Path = (Get-AppSettingsPath))

    if (-not (Test-Path -LiteralPath $Path)) {
        return (New-DefaultAppSettings)
    }

    try {
        $json = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return (New-DefaultAppSettings)
        }

        return (Normalize-AppSettings ($json | ConvertFrom-Json -ErrorAction Stop))
    }
    catch {
        return (New-DefaultAppSettings)
    }
}

function Save-AppSettings {
    param(
        [Parameter(Mandatory = $true)] $Settings,
        [string] $Path = (Get-AppSettingsPath)
    )

    $normalized = Normalize-AppSettings $Settings
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $normalized | ConvertTo-Json -Depth 4 | Set-Content -Path $Path -Encoding UTF8
    return $normalized
}

function Reset-AppSettings {
    param([string] $Path = (Get-AppSettingsPath))

    return (Save-AppSettings -Settings (New-DefaultAppSettings) -Path $Path)
}

function Get-RefreshPresetIntervals {
    param([string] $Preset)

    switch (Normalize-RefreshPreset $Preset) {
        'Eco' {
            return [pscustomobject]@{
                CoreMilliseconds = 3000
                GpuMilliseconds = 8000
                ProcessMilliseconds = 15000
            }
        }
        'Fast' {
            return [pscustomobject]@{
                CoreMilliseconds = 750
                GpuMilliseconds = 2000
                ProcessMilliseconds = 4000
            }
        }
        default {
            return [pscustomobject]@{
                CoreMilliseconds = 1000
                GpuMilliseconds = 3000
                ProcessMilliseconds = 6000
            }
        }
    }
}

function Get-WindowsAppsUseLightTheme {
    try {
        $personalize = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        return [int] $personalize.AppsUseLightTheme
    }
    catch {
        return $null
    }
}

function Resolve-EffectiveThemeMode {
    param(
        [string] $ThemeMode,
        [Nullable[int]] $WindowsAppsUseLightTheme = (Get-WindowsAppsUseLightTheme)
    )

    $normalized = Normalize-ThemeMode $ThemeMode
    if ($normalized -eq 'Light' -or $normalized -eq 'Dark') {
        return $normalized
    }

    if ($null -eq $WindowsAppsUseLightTheme) {
        return 'Light'
    }

    if ($WindowsAppsUseLightTheme -eq 0) {
        return 'Dark'
    }

    return 'Light'
}

function Get-ThemePalette {
    param([string] $EffectiveThemeMode)

    if ($EffectiveThemeMode -eq 'Dark') {
        return [pscustomobject]@{
            Mode = 'Dark'
            ShellBackground = '#111312'
            FooterBackground = '#171918'
            CardBackground = '#1B1E1C'
            HeroNeutralBackground = '#17211E'
            Border = '#30342F'
            Divider = '#272B27'
            PrimaryText = '#F3F4F1'
            SecondaryText = '#A8ADA7'
            MutedText = '#7E857E'
            HoverBackground = '#252A26'
            ShadowOpacity = 0.42
            NormalBackground = '#13241F'
            WarmBackground = '#2A2112'
            HotBackground = '#2A1715'
            UnavailableBackground = '#20231F'
        }
    }

    return [pscustomobject]@{
        Mode = 'Light'
        ShellBackground = '#FBFBFA'
        FooterBackground = '#F6F6F4'
        CardBackground = '#FFFFFF'
        HeroNeutralBackground = '#F4F5F2'
        Border = '#DEE0DC'
        Divider = '#ECEDEA'
        PrimaryText = '#191919'
        SecondaryText = '#60625E'
        MutedText = '#80827E'
        HoverBackground = '#EDEEEB'
        ShadowOpacity = 0.22
        NormalBackground = '#EEF8F4'
        WarmBackground = '#FFF7E8'
        HotBackground = '#FFEFED'
        UnavailableBackground = '#F4F5F2'
    }
}

function Get-StartupShortcutPath {
    $startupDirectory = [Environment]::GetFolderPath('Startup')
    return (Join-Path $startupDirectory 'PC Status.lnk')
}

function Get-StartupLauncherPath {
    $baseDirectory = Split-Path -Parent (Get-AppSettingsPath)
    return (Join-Path $baseDirectory 'Launch-PCStatus.vbs')
}

function New-StartupLauncher {
    param(
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [Parameter(Mandatory = $true)] [string] $LauncherPath
    )

    $directory = Split-Path -Parent $LauncherPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $workingDirectory = (Split-Path -Parent $ScriptPath) -replace '"', '""'
    $escapedScriptPath = $ScriptPath -replace '"', '""'
    $content = @"
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = "$workingDirectory"
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$escapedScriptPath""", 0, False
"@

    Set-Content -Path $LauncherPath -Value $content -Encoding ASCII
}

function Set-StartWithWindows {
    param(
        [Parameter(Mandatory = $true)] [bool] $Enabled,
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [string] $ShortcutPath = (Get-StartupShortcutPath),
        [string] $LauncherPath = (Get-StartupLauncherPath)
    )

    if (-not $Enabled) {
        if (Test-Path -LiteralPath $ShortcutPath) {
            Remove-Item -LiteralPath $ShortcutPath -Force
        }
        if (Test-Path -LiteralPath $LauncherPath) {
            Remove-Item -LiteralPath $LauncherPath -Force
        }
        return
    }

    $directory = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    New-StartupLauncher -ScriptPath $ScriptPath -LauncherPath $LauncherPath

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = 'wscript.exe'
    $shortcut.Arguments = "`"$LauncherPath`""
    $shortcut.WorkingDirectory = Split-Path -Parent $LauncherPath
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,13"
    $shortcut.Save()
}
