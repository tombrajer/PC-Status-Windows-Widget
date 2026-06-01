. "$PSScriptRoot\HealthModel.ps1"

function Get-OptionalCommandPath {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-CpuUsagePercent {
    try {
        $sample = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples | Select-Object -First 1
        if ($sample -and $null -ne $sample.CookedValue) {
            return [Math]::Round([double] $sample.CookedValue, 0)
        }
    }
    catch {
    }

    try {
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $processor.LoadPercentage) {
            return [double] $processor.LoadPercentage
        }
    }
    catch {
    }

    try {
        $processor = Get-WmiObject -Class Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $processor.LoadPercentage) {
            return [double] $processor.LoadPercentage
        }
    }
    catch {
    }

    return $null
}

function Get-MemorySnapshot {
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $info = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        $totalGb = [Math]::Round($info.TotalPhysicalMemory / 1GB, 1)
        $availableGb = [Math]::Round($info.AvailablePhysicalMemory / 1GB, 1)
        $usedGb = [Math]::Round($totalGb - $availableGb, 1)

        if ($totalGb -gt 0) {
            return [pscustomobject]@{
                UsedGb = $usedGb
                TotalGb = $totalGb
                Percent = [Math]::Round(($usedGb / $totalGb) * 100, 0)
            }
        }
    }
    catch {
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalGb = [Math]::Round(($os.TotalVisibleMemorySize * 1KB) / 1GB, 1)
        $freeGb = [Math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
        $usedGb = [Math]::Round($totalGb - $freeGb, 1)

        if ($totalGb -le 0) {
            return $null
        }

        [pscustomobject]@{
            UsedGb = $usedGb
            TotalGb = $totalGb
            Percent = [Math]::Round(($usedGb / $totalGb) * 100, 0)
        }
    }
    catch {
    }

    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $totalGb = [Math]::Round(($os.TotalVisibleMemorySize * 1KB) / 1GB, 1)
        $freeGb = [Math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
        $usedGb = [Math]::Round($totalGb - $freeGb, 1)

        if ($totalGb -le 0) {
            return $null
        }

        [pscustomobject]@{
            UsedGb = $usedGb
            TotalGb = $totalGb
            Percent = [Math]::Round(($usedGb / $totalGb) * 100, 0)
        }
    }
    catch {
    }

    return $null
}

function Get-AcpiThermalZoneTemperature {
    try {
        $zones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        $values = @()

        foreach ($zone in $zones) {
            if ($null -ne $zone.CurrentTemperature -and $zone.CurrentTemperature -gt 0) {
                $celsius = ([double] $zone.CurrentTemperature / 10) - 273.15
                if ($celsius -gt 0 -and $celsius -lt 130) {
                    $values += $celsius
                }
            }
        }

        if ($values.Count -gt 0) {
            return [Math]::Round(($values | Measure-Object -Average).Average, 0)
        }
    }
    catch {
        return $null
    }

    return $null
}

function Select-BestCpuTemperature {
    param([Parameter(Mandatory = $true)] [object[]] $Sensors)

    $cpuTemperatureSensors = @($Sensors | Where-Object {
        $_.HardwareType -eq 'Cpu' -and
        $_.SensorType -eq 'Temperature' -and
        $null -ne $_.Value -and
        [double] $_.Value -gt 0 -and
        [double] $_.Value -lt 130
    })

    if ($cpuTemperatureSensors.Count -eq 0) {
        return $null
    }

    $preferred = @($cpuTemperatureSensors | Where-Object {
        $_.Name -match 'package|tdie|tctl|cpu'
    } | Sort-Object -Property @{
        Expression = {
            if ($_.Name -match 'package') { 0 }
            elseif ($_.Name -match 'tdie|tctl') { 1 }
            else { 2 }
        }
    }, Name | Select-Object -First 1)

    if ($preferred.Count -gt 0) {
        return $preferred[0]
    }

    return ($cpuTemperatureSensors | Sort-Object -Property Value -Descending | Select-Object -First 1)
}

function Get-LibreHardwareMonitorDllPath {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\lib\LibreHardwareMonitorLib.dll'),
        (Join-Path $PSScriptRoot 'LibreHardwareMonitorLib.dll'),
        (Join-Path $env:ProgramFiles 'LibreHardwareMonitor\LibreHardwareMonitorLib.dll'),
        (Join-Path ${env:ProgramFiles(x86)} 'LibreHardwareMonitor\LibreHardwareMonitorLib.dll'),
        (Join-Path $env:LOCALAPPDATA 'LibreHardwareMonitor\LibreHardwareMonitorLib.dll')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-CpuTemperatureUnavailableSource {
    param(
        [bool] $HasLibreHardwareMonitor,
        [bool] $IsAdministrator
    )

    if (-not $HasLibreHardwareMonitor) {
        return 'Install CPU temperature support from Settings'
    }

    if (-not $IsAdministrator) {
        return 'Run as administrator for CPU temperature'
    }

    return 'Elevated, but CPU temperature values are not readable'
}

function Import-LibreHardwareMonitorAssemblies {
    $dllPath = Get-LibreHardwareMonitorDllPath
    if (-not $dllPath) {
        return $null
    }

    $libRoot = Split-Path -Parent $dllPath
    $dependencyOrder = @(
        'System.Buffers.dll',
        'System.Numerics.Vectors.dll',
        'System.Runtime.CompilerServices.Unsafe.dll',
        'System.Memory.dll',
        'System.Security.Principal.Windows.dll',
        'System.Security.AccessControl.dll',
        'System.CodeDom.dll',
        'System.Management.dll',
        'System.Threading.AccessControl.dll',
        'HidSharp.dll',
        'DiskInfoToolkit.dll',
        'RAMSPDToolkit-NDD.dll',
        'LibreHardwareMonitorLib.dll'
    )

    foreach ($dllName in $dependencyOrder) {
        $candidate = Join-Path $libRoot $dllName
        if (Test-Path $candidate) {
            [System.Reflection.Assembly]::LoadFrom((Resolve-Path $candidate).Path) | Out-Null
        }
    }

    return $dllPath
}

function Get-LibreHardwareMonitorCpuTemperature {
    $dllPath = Import-LibreHardwareMonitorAssemblies
    if (-not $dllPath) {
        return $null
    }

    try {
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer
        $computer.IsCpuEnabled = $true
        $computer.Open()

        $sensors = @()
        foreach ($hardware in $computer.Hardware) {
            $hardware.Update()
            foreach ($subHardware in $hardware.SubHardware) {
                $subHardware.Update()
            }

            foreach ($sensor in $hardware.Sensors) {
                $sensors += [pscustomobject]@{
                    HardwareType = $hardware.HardwareType.ToString()
                    SensorType = $sensor.SensorType.ToString()
                    Name = $sensor.Name
                    Value = $sensor.Value
                }
            }
        }

        $best = Select-BestCpuTemperature -Sensors $sensors
        if ($best) {
            return [pscustomobject]@{
                Value = [Math]::Round([double] $best.Value, 0)
                Source = "LibreHardwareMonitor: $($best.Name)"
            }
        }

        $cpuTemperatureSensorCount = @($sensors | Where-Object {
            $_.HardwareType -eq 'Cpu' -and $_.SensorType -eq 'Temperature'
        }).Count

        if ($cpuTemperatureSensorCount -gt 0) {
            return [pscustomobject]@{
                Value = $null
                Source = Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $true -IsAdministrator (Test-IsAdministrator)
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Value = $null
            Source = 'LibreHardwareMonitor could not read CPU temperature'
        }
    }
    finally {
        if ($computer) {
            $computer.Close()
        }
    }

    return $null
}

function Get-CpuTemperatureSnapshot {
    $hasLibreHardwareMonitor = $null -ne (Get-LibreHardwareMonitorDllPath)
    $isAdministrator = Test-IsAdministrator

    if ($hasLibreHardwareMonitor -and -not $isAdministrator) {
        return [pscustomobject]@{
            Value = $null
            Source = Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $true -IsAdministrator $false
        }
    }

    $libreHardwareMonitor = Get-LibreHardwareMonitorCpuTemperature
    if ($libreHardwareMonitor) {
        return $libreHardwareMonitor
    }

    $acpiTemperature = Get-AcpiThermalZoneTemperature
    if ($null -ne $acpiTemperature) {
        return [pscustomobject]@{
            Value = $acpiTemperature
            Source = 'ACPI thermal zone'
        }
    }

    return [pscustomobject]@{
        Value = $null
        Source = Get-CpuTemperatureUnavailableSource -HasLibreHardwareMonitor $hasLibreHardwareMonitor -IsAdministrator $isAdministrator
    }
}

function Get-NvidiaSmiSnapshot {
    $nvidiaSmi = Get-OptionalCommandPath 'nvidia-smi.exe'
    if (-not $nvidiaSmi) {
        $candidate = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path $candidate) {
            $nvidiaSmi = $candidate
        }
    }

    if (-not $nvidiaSmi) {
        return $null
    }

    try {
        $output = & $nvidiaSmi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($output)) {
            return $null
        }

        $parts = $output -split ','
        if ($parts.Count -lt 2) {
            return $null
        }

        [pscustomobject]@{
            Temperature = [double] ($parts[0].Trim())
            Usage = [double] (($parts[1].Trim()) -replace '[^\d\.]', '')
            Source = 'nvidia-smi'
        }
    }
    catch {
        return $null
    }
}

function Get-GpuCounterUsagePercent {
    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        $engines = $samples | Where-Object {
            $_.InstanceName -notmatch '_total' -and $_.CookedValue -gt 0
        }

        if (-not $engines) {
            return 0
        }

        $sum = ($engines | Measure-Object -Property CookedValue -Sum).Sum
        return [Math]::Min(100, [Math]::Round($sum, 0))
    }
    catch {
        return $null
    }
}

function Get-GpuSnapshot {
    $nvidia = Get-NvidiaSmiSnapshot
    if ($nvidia) {
        return $nvidia
    }

    $usage = Get-GpuCounterUsagePercent
    if ($null -ne $usage) {
        return [pscustomobject]@{
            Temperature = $null
            Usage = $usage
            Source = 'Windows GPU counters'
        }
    }

    return [pscustomobject]@{
        Temperature = $null
        Usage = $null
        Source = 'Unavailable'
    }
}

function Get-PowerSnapshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
        $percent = $null
        if ($powerStatus.BatteryLifePercent -ge 0) {
            $percent = [Math]::Round($powerStatus.BatteryLifePercent * 100, 0)
        }

        $lineStatus = $powerStatus.PowerLineStatus.ToString()
        $mode = if ($lineStatus -eq 'Online') { 'Plugged in' } elseif ($lineStatus -eq 'Offline') { 'On battery' } else { 'Power unknown' }
        $batteryText = if ($null -ne $percent) { "$percent%" } else { 'Battery unknown' }
        $detail = if ($lineStatus -eq 'Online') { 'AC power connected' } elseif ($lineStatus -eq 'Offline') { 'Running on battery' } else { 'Power source unavailable' }

        return [pscustomobject]@{
            Percent = $percent
            Mode = $mode
            BatteryText = $batteryText
            Detail = $detail
            Status = if ($null -eq $percent) { 'Unavailable' } elseif ($percent -le 15 -and $lineStatus -eq 'Offline') { 'Hot' } elseif ($percent -le 35 -and $lineStatus -eq 'Offline') { 'Warm' } else { 'Normal' }
        }
    }
    catch {
        return [pscustomobject]@{
            Percent = $null
            Mode = 'Power unavailable'
            BatteryText = 'Unavailable'
            Detail = 'Windows power status unavailable'
            Status = 'Unavailable'
        }
    }
}

function Get-SystemHealthScore {
    param(
        [Nullable[double]] $CpuUsage,
        [Nullable[double]] $RamUsage,
        [Nullable[double]] $GpuUsage
    )

    $values = @($CpuUsage, $RamUsage, $GpuUsage) | Where-Object { $null -ne $_ }
    if ($values.Count -eq 0) {
        return 'Unavailable'
    }

    $max = ($values | Measure-Object -Maximum).Maximum
    if ($max -ge 90) {
        return 'Heavy Load'
    }

    if ($max -ge 65) {
        return 'Busy'
    }

    return 'Healthy'
}

function Get-ProcessDisplayName {
    param([Parameter(Mandatory = $true)] [string] $ProcessName)

    $name = $ProcessName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        return 'Unknown Process'
    }

    $friendlyNames = @{
        'applicationframehost' = 'Application Frame Host'
        'chrome' = 'Google Chrome'
        'code' = 'Visual Studio Code'
        'codex' = 'Codex'
        'dwm' = 'Desktop Window Manager'
        'explorer' = 'File Explorer'
        'firefox' = 'Mozilla Firefox'
        'msedge' = 'Microsoft Edge'
        'onedrive' = 'OneDrive'
        'powershell' = 'PowerShell'
        'pwsh' = 'PowerShell'
        'runtimebroker' = 'Runtime Broker'
        'searchhost' = 'Windows Search'
        'shellexperiencehost' = 'Windows Shell Experience'
        'startmenuexperiencehost' = 'Start Menu'
        'svchost' = 'Windows Service Host'
        'taskmgr' = 'Task Manager'
        'textinputhost' = 'Text Input Host'
        'windowsterminal' = 'Windows Terminal'
        'winlogon' = 'Windows Sign-In'
    }

    $key = $name.ToLowerInvariant()
    if ($friendlyNames.ContainsKey($key)) {
        return $friendlyNames[$key]
    }

    $clean = $name -replace '[_\-]+', ' '
    $clean = $clean -creplace '([a-z0-9])([A-Z])', '$1 $2'
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()

    if ([string]::IsNullOrWhiteSpace($clean)) {
        return 'Unknown Process'
    }

    return (Get-Culture).TextInfo.ToTitleCase($clean.ToLowerInvariant())
}

function Get-TopCpuProcesses {
    param([int] $Count = 3)

    try {
        $processorCount = [Math]::Max(1, [Environment]::ProcessorCount)
        $firstSample = @{}
        foreach ($process in (Get-Process | Where-Object { $null -ne $_.CPU })) {
            $firstSample[$process.Id] = [pscustomobject]@{
                Name = $process.ProcessName
                Cpu = [double] $process.CPU
            }
        }

        Start-Sleep -Milliseconds 750

        $groups = @{}
        foreach ($process in (Get-Process | Where-Object { $null -ne $_.CPU })) {
            $name = $process.ProcessName
            if (-not $groups.ContainsKey($name)) {
                $groups[$name] = [pscustomobject]@{
                    Name = $name
                    CpuDeltaSeconds = 0.0
                    MemoryBytes = 0L
                    ProcessCount = 0
                }
            }

            $groups[$name].MemoryBytes += [int64] $process.WorkingSet64
            $groups[$name].ProcessCount += 1

            if ($firstSample.ContainsKey($process.Id)) {
                $delta = [Math]::Max(0, ([double] $process.CPU - [double] $firstSample[$process.Id].Cpu))
                $groups[$name].CpuDeltaSeconds += $delta
            }
        }

        return @(
            $groups.Values |
                Sort-Object -Property @{ Expression = { $_.CpuDeltaSeconds }; Descending = $true }, @{ Expression = { $_.MemoryBytes }; Descending = $true } |
                Select-Object -First $Count |
                ForEach-Object {
                    [pscustomobject]@{
                        Name = Get-ProcessDisplayName -ProcessName $_.Name
                        ProcessName = $_.Name
                        CpuPercent = [Math]::Round(($_.CpuDeltaSeconds / 0.75 / $processorCount) * 100, 1)
                        MemoryMb = [Math]::Round($_.MemoryBytes / 1MB, 0)
                        ProcessCount = $_.ProcessCount
                    }
                }
        )
    }
    catch {
        return @()
    }
}

function Get-SystemHealthSnapshot {
    param(
        $GpuSnapshot = $null,
        [switch] $SkipGpuRefresh,
        [object[]] $TopProcesses = $null,
        [switch] $SkipTopProcessRefresh,
        [bool] $IncludeGpu = $true,
        [bool] $IncludeTopProcesses = $true
    )

    $cpuUsage = Get-CpuUsagePercent
    $memory = Get-MemorySnapshot
    $gpu = if (-not $IncludeGpu) {
        [pscustomobject]@{
            Temperature = $null
            Usage = $null
            Source = 'Hidden'
        }
    }
    elseif ($SkipGpuRefresh) {
        if ($null -ne $GpuSnapshot) {
            $GpuSnapshot
        }
        else {
            [pscustomobject]@{
                Temperature = $null
                Usage = $null
                Source = 'Unavailable'
            }
        }
    }
    else {
        Get-GpuSnapshot
    }
    $power = Get-PowerSnapshot

    $ramValue = $null
    $ramDetail = 'Unavailable'
    if ($memory) {
        $ramValue = [double] $memory.Percent
        $ramDetail = "$($memory.UsedGb) / $($memory.TotalGb) GB"
    }

    $metrics = @(
        (New-HealthMetric -Label 'CPU Usage' -Value $cpuUsage -Unit '%' -Status (Get-LoadStatus $cpuUsage) -Detail 'Processor load'),
        (New-HealthMetric -Label 'RAM' -Value $ramValue -Unit '%' -Status (Get-LoadStatus $ramValue) -Detail $ramDetail)
    )
    if ($IncludeGpu) {
        $metrics += (New-HealthMetric -Label 'GPU Usage' -Value $gpu.Usage -Unit '%' -Status (Get-LoadStatus $gpu.Usage) -Detail $gpu.Source)
    }

    $overall = Get-OverallHealthStatus $metrics
    $healthScore = Get-SystemHealthScore -CpuUsage $cpuUsage -RamUsage $ramValue -GpuUsage $gpu.Usage
    $hasUnavailable = @($metrics | Where-Object { -not $_.Available }).Count -gt 0
    $healthLine = if ($hasUnavailable) {
        "$healthScore - some stats unavailable"
    }
    elseif ($IncludeGpu) {
        "$healthScore - CPU $(Format-MetricValue $metrics[0]), RAM $(Format-MetricValue $metrics[1]), GPU $(Format-MetricValue $metrics[2])"
    }
    else {
        "$healthScore - CPU $(Format-MetricValue $metrics[0]), RAM $(Format-MetricValue $metrics[1])"
    }
    $processRows = if (-not $IncludeTopProcesses) {
        @()
    }
    elseif ($SkipTopProcessRefresh) {
        if ($null -eq $TopProcesses) {
            @()
        }
        else {
            @($TopProcesses | Where-Object { $null -ne $_ })
        }
    }
    else {
        @(Get-TopCpuProcesses -Count 3)
    }
    $processRows = @($processRows)

    [pscustomobject]@{
        Metrics = $metrics
        Power = $power
        TopProcesses = $processRows
        HealthScore = $healthScore
        HealthLine = $healthLine
        OverallStatus = $overall
        Message = Get-HealthMessage -Status $overall -HasUnavailable $hasUnavailable
        Tooltip = "$($power.Mode) - $($power.BatteryText) - $healthScore"
        UpdatedAt = Get-Date
    }
}
