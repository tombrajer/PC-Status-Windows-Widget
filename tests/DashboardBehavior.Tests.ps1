$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    if (-not $Condition) {
        throw $Name
    }
}

$dashboardPath = Join-Path $PSScriptRoot '..\src\WindowsDashboard.ps1'
$source = Get-Content -Path $dashboardPath -Raw

$hideDashboardMatch = [regex]::Match($source, 'function\s+Hide-Dashboard\s*\{(?<body>.*?)\r?\n\}', 'Singleline')
Assert-True $hideDashboardMatch.Success 'Hide-Dashboard function exists'
Assert-True (-not ($hideDashboardMatch.Groups['body'].Value -match '\$timer\.Stop\s*\(')) 'Hidden dashboard keeps snapshot timer running for tray status updates'
Assert-True ($source -match 'Update-Dashboard\s*\r?\n\s*if\s*\(-not\s+\$ValidateOnly\)\s*\{\s*\r?\n\s*Start-DashboardRefreshTimer') 'Dashboard refresh timer starts during normal tray app initialization'

Write-Host 'DashboardBehavior.Tests passed'
