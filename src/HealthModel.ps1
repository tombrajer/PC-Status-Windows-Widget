function Get-TemperatureStatus {
    param([Nullable[double]] $Value)

    if ($null -eq $Value) {
        return 'Unavailable'
    }

    if ($Value -ge 90) {
        return 'Hot'
    }

    if ($Value -ge 75) {
        return 'Warm'
    }

    return 'Normal'
}

function Get-LoadStatus {
    param([Nullable[double]] $Value)

    if ($null -eq $Value) {
        return 'Unavailable'
    }

    if ($Value -ge 95) {
        return 'Hot'
    }

    if ($Value -ge 80) {
        return 'Warm'
    }

    return 'Normal'
}

function New-HealthMetric {
    param(
        [Parameter(Mandatory = $true)] [string] $Label,
        [Nullable[double]] $Value,
        [string] $Unit = '',
        [Parameter(Mandatory = $true)] [string] $Status,
        [string] $Detail = ''
    )

    [pscustomobject]@{
        Label = $Label
        Value = $Value
        Unit = $Unit
        Status = $Status
        Detail = $Detail
        Available = ($Status -ne 'Unavailable')
    }
}

function Get-StatusSeverity {
    param([string] $Status)

    switch ($Status) {
        'Hot' { return 3 }
        'Warm' { return 2 }
        'Normal' { return 1 }
        default { return 0 }
    }
}

function Get-OverallHealthStatus {
    param([Parameter(Mandatory = $true)] [object[]] $Metrics)

    $highest = 0
    foreach ($metric in $Metrics) {
        $severity = Get-StatusSeverity $metric.Status
        if ($severity -gt $highest) {
            $highest = $severity
        }
    }

    switch ($highest) {
        3 { return 'Hot' }
        2 { return 'Warm' }
        1 { return 'Normal' }
        default { return 'Unavailable' }
    }
}

function Format-MetricValue {
    param([Parameter(Mandatory = $true)] $Metric)

    if (-not $Metric.Available -or $null -eq $Metric.Value) {
        return 'Unavailable'
    }

    $rounded = [Math]::Round([double] $Metric.Value, 0)
    if ($Metric.Unit -eq '%') {
        return "$rounded%"
    }

    if ([string]::IsNullOrWhiteSpace($Metric.Unit)) {
        return "$rounded"
    }

    return "$rounded $($Metric.Unit)"
}

function Get-HealthMessage {
    param(
        [Parameter(Mandatory = $true)] [string] $Status,
        [bool] $HasUnavailable = $false
    )

    switch ($Status) {
        'Hot' { return 'Hardware needs attention' }
        'Warm' { return 'Running warm' }
        'Normal' {
            if ($HasUnavailable) {
                return 'Some sensors unavailable'
            }

            return 'All systems normal'
        }
        default { return 'Some sensors unavailable' }
    }
}
