# PC Status

A small Windows tray status widget with a OneDrive-style flyout. It runs as a PowerShell 5.1 WinForms/WPF app, so it does not require a .NET SDK build step.

## Run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WindowsDashboard.ps1
```

The app adds a tray icon. Click the icon to open or hide the hardware popup.

The widget relaunches itself as administrator by default for broader Windows performance-counter access. For development-only runs without elevation, add `-NoElevate`.

Settings are stored in `%LOCALAPPDATA%\PCStatus\settings.json`.

## What It Shows

- Battery percentage and power source.
- One-line PC status based on current load.
- CPU usage.
- RAM usage and used/total memory.
- GPU usage when Windows exposes GPU performance counters.
- Top CPU processes with current CPU and memory use.

Missing stats are shown as `Unavailable` instead of failing.

## Settings

- Light, Dark, or Auto theme.
- Start with Windows.
- Run elevated on launch.
- Eco, Balanced, or Fast refresh preset.
- Show or hide Battery + Power.
- Show or hide CPU usage.
- Show or hide Memory.
- Show or hide GPU usage.
- Show or hide top CPU processes.
- Detailed or minimal tray tooltip.
- Open logs, reset defaults, or quit from the settings page.

## Test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\HealthModel.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\AppSettings.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\SystemStats.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\StatsWorker.Smoke.Tests.ps1
```
