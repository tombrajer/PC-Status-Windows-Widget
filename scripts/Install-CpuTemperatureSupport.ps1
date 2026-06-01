$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$libRoot = Join-Path $projectRoot 'lib'
$packageRoot = Join-Path $libRoot 'packages'

New-Item -ItemType Directory -Force -Path $libRoot | Out-Null
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

$packages = @(
    @{ Id = 'LibreHardwareMonitorLib'; Version = '0.9.6'; Dll = 'LibreHardwareMonitorLib.dll' },
    @{ Id = 'DiskInfoToolkit'; Version = '1.1.2'; Dll = 'DiskInfoToolkit.dll' },
    @{ Id = 'HidSharp'; Version = '2.6.4'; Dll = 'HidSharp.dll' },
    @{ Id = 'RAMSPDToolkit-NDD'; Version = '1.4.2'; Dll = 'RAMSPDToolkit-NDD.dll' },
    @{ Id = 'System.Management'; Version = '10.0.2'; Dll = 'System.Management.dll' },
    @{ Id = 'System.Memory'; Version = '4.6.3'; Dll = 'System.Memory.dll' },
    @{ Id = 'System.Buffers'; Version = '4.6.1'; Dll = 'System.Buffers.dll' },
    @{ Id = 'System.Numerics.Vectors'; Version = '4.6.1'; Dll = 'System.Numerics.Vectors.dll' },
    @{ Id = 'System.Runtime.CompilerServices.Unsafe'; Version = '6.1.2'; Dll = 'System.Runtime.CompilerServices.Unsafe.dll' },
    @{ Id = 'System.Threading.AccessControl'; Version = '10.0.3'; Dll = 'System.Threading.AccessControl.dll' },
    @{ Id = 'System.Security.AccessControl'; Version = '6.0.0'; Dll = 'System.Security.AccessControl.dll' },
    @{ Id = 'System.Security.Principal.Windows'; Version = '5.0.0'; Dll = 'System.Security.Principal.Windows.dll' },
    @{ Id = 'System.CodeDom'; Version = '10.0.2'; Dll = 'System.CodeDom.dll' }
)

function Save-NuGetPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $Id,
        [Parameter(Mandatory = $true)] [string] $Version
    )

    $downloadPath = Join-Path $packageRoot "$Id.$Version.nupkg"
    $extractPath = Join-Path $packageRoot "$Id.$Version"

    if (-not (Test-Path $downloadPath)) {
        $uri = "https://www.nuget.org/api/v2/package/$Id/$Version"
        Invoke-WebRequest -Uri $uri -OutFile $downloadPath
    }

    if (-not (Test-Path $extractPath)) {
        $zipPath = Join-Path $packageRoot "$Id.$Version.zip"
        Copy-Item $downloadPath $zipPath -Force
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    }

    return $extractPath
}

function Copy-PackageDll {
    param(
        [Parameter(Mandatory = $true)] [string] $PackagePath,
        [Parameter(Mandatory = $true)] [string] $DllName
    )

    $preferredPatterns = @(
        "runtimes\win-x64\lib\net472\$DllName",
        "lib\net472\$DllName",
        "lib\net462\$DllName",
        "lib\net461\$DllName",
        "runtimes\win-x64\lib\netstandard2.0\$DllName",
        "lib\netstandard2.0\$DllName",
        "lib\netstandard2.1\$DllName"
    )

    foreach ($pattern in $preferredPatterns) {
        $candidate = Join-Path $PackagePath $pattern
        if (Test-Path $candidate) {
            $destination = Join-Path $libRoot $DllName
            if (Test-Path $destination) {
                $sourceLength = (Get-Item $candidate).Length
                $destinationLength = (Get-Item $destination).Length
                if ($sourceLength -eq $destinationLength) {
                    return
                }
            }

            Copy-Item $candidate $destination -Force
            return
        }
    }

    $fallback = Get-ChildItem -Path $PackagePath -Recurse -Filter $DllName | Select-Object -First 1
    if ($fallback) {
        $destination = Join-Path $libRoot $DllName
        if (Test-Path $destination) {
            $destinationLength = (Get-Item $destination).Length
            if ($fallback.Length -eq $destinationLength) {
                return
            }
        }

        Copy-Item $fallback.FullName $destination -Force
        return
    }

    throw "Could not find $DllName in $PackagePath"
}

foreach ($package in $packages) {
    $packagePath = Save-NuGetPackage -Id $package.Id -Version $package.Version
    Copy-PackageDll -PackagePath $packagePath -DllName $package.Dll
}

Get-ChildItem -Path $libRoot -Filter *.dll | Select-Object Name, Length
