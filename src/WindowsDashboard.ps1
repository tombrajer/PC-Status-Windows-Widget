param(
    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\AppSettings.ps1"
. "$PSScriptRoot\SystemStats.ps1"

$script:AppName = 'PC Status'
$script:SettingsPath = if ($ValidateOnly) {
    Join-Path ([IO.Path]::GetTempPath()) "WindowsDashboard\validation-settings-$PID.json"
}
else {
    Get-AppSettingsPath
}
$script:Settings = Get-AppSettings -Path $script:SettingsPath

function Get-AppLogPath {
    $logDirectory = Join-Path ([IO.Path]::GetTempPath()) 'WindowsDashboard'
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    return (Join-Path $logDirectory 'app.log')
}

function Write-AppLog {
    param([Parameter(Mandatory = $true)] [string] $Message)

    $line = "{0:u} {1}" -f (Get-Date), $Message
    Add-Content -Path (Get-AppLogPath) -Value $line -Encoding UTF8
}

function Hide-ConsoleWindow {
    if ($ValidateOnly) {
        return
    }

    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class NativeConsoleWindow
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

    $handle = [NativeConsoleWindow]::GetConsoleWindow()
    if ($handle -ne [IntPtr]::Zero) {
        [NativeConsoleWindow]::ShowWindow($handle, 0) | Out-Null
    }
}

Hide-ConsoleWindow

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:StatusBrushes = @{
    Normal = '#1F8A70'
    Warm = '#BF7B24'
    Hot = '#C43930'
    Unavailable = '#80827E'
}

$script:StatusBackgrounds = @{
    Normal = '#EEF8F4'
    Warm = '#FFF7E8'
    Hot = '#FFEFED'
    Unavailable = '#F4F5F2'
}

function Get-StatusBrush {
    param([string] $Status)

    if ($script:StatusBrushes.ContainsKey($Status)) {
        return $script:StatusBrushes[$Status]
    }

    return $script:StatusBrushes.Unavailable
}

function Get-StatusBackground {
    param([string] $Status)

    if ($script:CurrentPalette) {
        switch ($Status) {
            'Normal' { return $script:CurrentPalette.NormalBackground }
            'Warm' { return $script:CurrentPalette.WarmBackground }
            'Hot' { return $script:CurrentPalette.HotBackground }
            default { return $script:CurrentPalette.UnavailableBackground }
        }
    }

    if ($script:StatusBackgrounds.ContainsKey($Status)) {
        return $script:StatusBackgrounds[$Status]
    }

    return $script:StatusBackgrounds.Unavailable
}

function Set-WpfText {
    param(
        [Parameter(Mandatory = $true)] $Element,
        [string] $Text
    )

    $Element.Text = $Text
}

function New-TrayIcon {
    $bitmap = New-Object System.Drawing.Bitmap(64, 64)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $outerBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(31, 138, 112))
    $outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(19, 95, 78), 2)
    $pulsePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 5)
    $pulsePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pulsePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pulsePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $graphics.FillEllipse($outerBrush, 6, 6, 52, 52)
    $graphics.DrawEllipse($outlinePen, 6, 6, 52, 52)
    $graphics.DrawLines($pulsePen, @(
        (New-Object System.Drawing.Point(16, 34)),
        (New-Object System.Drawing.Point(24, 34)),
        (New-Object System.Drawing.Point(29, 24)),
        (New-Object System.Drawing.Point(36, 42)),
        (New-Object System.Drawing.Point(41, 34)),
        (New-Object System.Drawing.Point(49, 34))
    ))

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $graphics.Dispose()
    $outerBrush.Dispose()
    $outlinePen.Dispose()
    $pulsePen.Dispose()
    $icon
}

$xaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="RootBorder"
        CornerRadius="22"
        Background="#FBFBFA"
        BorderBrush="#DEE0DC"
        BorderThickness="1"
        SnapsToDevicePixels="True"
        UseLayoutRounding="True">
    <Border.Resources>
        <SolidColorBrush x:Key="ControlBackgroundBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="ControlForegroundBrush" Color="#191919"/>
        <SolidColorBrush x:Key="ControlSecondaryForegroundBrush" Color="#60625E"/>
        <SolidColorBrush x:Key="ControlBorderBrush" Color="#DEE0DC"/>
        <SolidColorBrush x:Key="ControlHoverBrush" Color="#EDEEEB"/>
        <SolidColorBrush x:Key="ControlAccentBrush" Color="#1F8A70"/>
        <SolidColorBrush x:Key="ControlCheckBrush" Color="#FFFFFF"/>

        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="Foreground" Value="{DynamicResource ControlForegroundBrush}"/>
            <Setter Property="Background" Value="{DynamicResource ControlBackgroundBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}"/>
            <Setter Property="MinHeight" Value="36"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="{x:Type ComboBoxItem}">
                        <Setter Property="Foreground" Value="{DynamicResource ControlForegroundBrush}"/>
                        <Setter Property="Background" Value="{DynamicResource ControlBackgroundBrush}"/>
                        <Setter Property="Padding" Value="10,6"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="{x:Type ComboBoxItem}">
                                    <Border x:Name="ItemRoot"
                                            Background="{TemplateBinding Background}"
                                            Padding="{TemplateBinding Padding}">
                                        <ContentPresenter/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsHighlighted" Value="True">
                                            <Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource ControlHoverBrush}"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="ItemRoot" Property="Background" Value="{DynamicResource ControlHoverBrush}"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="Foreground" Value="{DynamicResource ControlForegroundBrush}"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="MinHeight" Value="24"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type CheckBox}">
                        <Grid Background="Transparent" MinHeight="24">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="24"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border x:Name="CheckBoxFrame"
                                    Width="18"
                                    Height="18"
                                    CornerRadius="4"
                                    BorderThickness="1"
                                    BorderBrush="{DynamicResource ControlBorderBrush}"
                                    Background="{DynamicResource ControlBackgroundBrush}"
                                    HorizontalAlignment="Left"
                                    VerticalAlignment="Center">
                                <Path x:Name="CheckMark"
                                      Visibility="Collapsed"
                                      Stroke="{DynamicResource ControlCheckBrush}"
                                      StrokeThickness="2"
                                      StrokeStartLineCap="Round"
                                      StrokeEndLineCap="Round"
                                      Data="M 4 9 L 8 13 L 14 5"/>
                            </Border>
                            <ContentPresenter Grid.Column="1"
                                              Margin="6,1,0,1"
                                              VerticalAlignment="Center"
                                              RecognizesAccessKey="True"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CheckBoxFrame" Property="BorderBrush" Value="{DynamicResource ControlAccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="CheckBoxFrame" Property="Background" Value="{DynamicResource ControlAccentBrush}"/>
                                <Setter TargetName="CheckBoxFrame" Property="BorderBrush" Value="{DynamicResource ControlAccentBrush}"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Border.Resources>
    <Border.Effect>
        <DropShadowEffect BlurRadius="22"
                          ShadowDepth="4"
                          Opacity="0.22"
                          Color="#000000"/>
    </Border.Effect>
    <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="80"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="60"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="24,0,18,0">
                <Ellipse x:Name="StatusDot" Width="18" Height="18" Fill="#80827E" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                <StackPanel Margin="36,17,48,0">
                    <TextBlock x:Name="HeaderTitle" Text="PC Status" FontSize="20" FontWeight="SemiBold" Foreground="#191919"/>
                    <TextBlock x:Name="MessageText" Text="Collecting hardware stats" Margin="0,2,0,0" FontSize="13" Foreground="#60625E"/>
                </StackPanel>
                <Border x:Name="CloseAction"
                        Width="32"
                        Height="32"
                        CornerRadius="10"
                        HorizontalAlignment="Right"
                        VerticalAlignment="Center"
                        Background="Transparent"
                        Cursor="Hand">
                    <TextBlock x:Name="HeaderActionText"
                               Text="x"
                               HorizontalAlignment="Center"
                               VerticalAlignment="Center"
                               FontSize="16"
                               Foreground="#60625E"/>
                </Border>
            </Grid>

            <Border Grid.Row="0" VerticalAlignment="Bottom" Height="1" Background="#ECEDEA"/>

            <StackPanel x:Name="MainPage" Grid.Row="1" Margin="24,18,24,14">
                <Border x:Name="HeroCard"
                        CornerRadius="16"
                        Background="#F4F5F2"
                        BorderBrush="#E2E3DF"
                        BorderThickness="1"
                        Padding="22,16"
                        Height="124">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="140"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="Battery + Power" FontSize="15" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock x:Name="HeroValue" Text="Unavailable" Margin="0,10,0,0" FontSize="40" FontWeight="Bold" Foreground="#80827E"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock x:Name="HeroStatus" Text="No sensor" FontSize="15" FontWeight="SemiBold" Foreground="#80827E" TextAlignment="Right"/>
                            <TextBlock x:Name="HeroDetail" Text="Sensor unavailable" Margin="0,4,0,0" FontSize="11" Foreground="#60625E" TextAlignment="Right" TextWrapping="Wrap"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <UniformGrid x:Name="UsageGrid" Columns="3" Rows="1" Margin="0,16,0,0">
                    <Border x:Name="CpuCard" CornerRadius="14" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="16" Margin="0,0,10,0">
                        <StackPanel>
                            <TextBlock Text="CPU Usage" FontSize="13" Foreground="#60625E"/>
                            <TextBlock x:Name="CpuUsageValue" Text="Unavailable" Margin="0,8,0,0" FontSize="24" FontWeight="SemiBold" Foreground="#191919"/>
                            <ProgressBar x:Name="CpuUsageProgress" Height="6" Margin="0,12,0,0" Minimum="0" Maximum="100"/>
                        </StackPanel>
                    </Border>
                    <Border x:Name="RamCard" CornerRadius="14" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="16" Margin="5,0,5,0">
                        <StackPanel>
                            <TextBlock Text="Memory" FontSize="13" Foreground="#60625E"/>
                            <TextBlock x:Name="RamValue" Text="Unavailable" Margin="0,8,0,0" FontSize="24" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock x:Name="RamDetail" Text="" Margin="0,8,0,0" FontSize="11" Foreground="#60625E" TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                    </Border>
                    <Border x:Name="GpuCard" CornerRadius="14" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="16" Margin="10,0,0,0">
                        <StackPanel>
                            <TextBlock Text="GPU Usage" FontSize="13" Foreground="#60625E"/>
                            <TextBlock x:Name="GpuUsageValue" Text="Unavailable" Margin="0,8,0,0" FontSize="24" FontWeight="SemiBold" Foreground="#191919"/>
                            <ProgressBar x:Name="GpuUsageProgress" Height="6" Margin="0,12,0,0" Minimum="0" Maximum="100"/>
                        </StackPanel>
                    </Border>
                </UniformGrid>

                <Border x:Name="ProcessCard" CornerRadius="14" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,12" Margin="0,14,0,0">
                    <StackPanel>
                        <TextBlock Text="Top CPU Processes" FontSize="13" FontWeight="SemiBold" Foreground="#191919"/>
                        <Grid Margin="0,8,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="74"/>
                                <ColumnDefinition Width="74"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="22"/>
                                <RowDefinition Height="22"/>
                                <RowDefinition Height="22"/>
                            </Grid.RowDefinitions>
                            <TextBlock x:Name="Process1Name" Grid.Row="0" Grid.Column="0" Text="Collecting" Foreground="#191919" FontSize="12" TextTrimming="CharacterEllipsis"/>
                            <TextBlock x:Name="Process1Cpu" Grid.Row="0" Grid.Column="1" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                            <TextBlock x:Name="Process1Memory" Grid.Row="0" Grid.Column="2" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                            <TextBlock x:Name="Process2Name" Grid.Row="1" Grid.Column="0" Text="" Foreground="#191919" FontSize="12" TextTrimming="CharacterEllipsis"/>
                            <TextBlock x:Name="Process2Cpu" Grid.Row="1" Grid.Column="1" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                            <TextBlock x:Name="Process2Memory" Grid.Row="1" Grid.Column="2" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                            <TextBlock x:Name="Process3Name" Grid.Row="2" Grid.Column="0" Text="" Foreground="#191919" FontSize="12" TextTrimming="CharacterEllipsis"/>
                            <TextBlock x:Name="Process3Cpu" Grid.Row="2" Grid.Column="1" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                            <TextBlock x:Name="Process3Memory" Grid.Row="2" Grid.Column="2" Text="" Foreground="#60625E" FontSize="12" TextAlignment="Right"/>
                        </Grid>
                    </StackPanel>
                </Border>
            </StackPanel>

            <ScrollViewer x:Name="SettingsPage" Grid.Row="1" Margin="24,14,24,10" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                <StackPanel>
                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Appearance" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Choose how the flyout should adapt to Windows." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <ComboBox x:Name="ThemeModeCombo" Margin="0,10,0,0" Height="36">
                                <ComboBoxItem Content="Auto"/>
                                <ComboBoxItem Content="Light"/>
                                <ComboBoxItem Content="Dark"/>
                            </ComboBox>
                        </StackPanel>
                    </Border>

                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Startup" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Control whether PC Status starts with Windows." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <CheckBox x:Name="StartWithWindowsCheck" Content="Start with Windows" Margin="0,10,0,0" Foreground="#191919"/>
                        </StackPanel>
                    </Border>

                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Performance" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Eco uses less polling. Fast updates more often." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <ComboBox x:Name="RefreshPresetCombo" Margin="0,10,0,0" Height="36">
                                <ComboBoxItem Content="Eco"/>
                                <ComboBoxItem Content="Balanced"/>
                                <ComboBoxItem Content="Fast"/>
                            </ComboBox>
                        </StackPanel>
                    </Border>

                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Dashboard Cards" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Hide anything you do not want in the compact flyout." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <UniformGrid Columns="2" Margin="0,10,0,0">
                                <CheckBox x:Name="ShowBatteryPowerCheck" Content="Battery + Power" Margin="0,0,8,8" Foreground="#191919"/>
                                <CheckBox x:Name="ShowCpuCheck" Content="CPU usage" Margin="8,0,0,8" Foreground="#191919"/>
                                <CheckBox x:Name="ShowMemoryCheck" Content="Memory" Margin="0,0,8,8" Foreground="#191919"/>
                                <CheckBox x:Name="ShowGpuCheck" Content="GPU usage" Margin="8,0,0,8" Foreground="#191919"/>
                                <CheckBox x:Name="ShowTopProcessesCheck" Content="Top processes" Margin="0,0,8,0" Foreground="#191919"/>
                            </UniformGrid>
                        </StackPanel>
                    </Border>

                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Tray" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Choose whether the tray hover text shows live stats." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <CheckBox x:Name="DetailedTooltipCheck" Content="Detailed tray tooltip" Margin="0,10,0,0" Foreground="#191919"/>
                        </StackPanel>
                    </Border>

                    <Border CornerRadius="16" Background="#FFFFFF" BorderBrush="#E2E3DF" BorderThickness="1" Padding="18,14">
                        <StackPanel>
                            <TextBlock Text="Diagnostics" FontSize="14" FontWeight="SemiBold" Foreground="#191919"/>
                            <TextBlock Text="Troubleshoot or reset the widget." Margin="0,3,0,0" FontSize="11" Foreground="#60625E"/>
                            <UniformGrid Columns="3" Margin="0,12,0,0">
                                <Button x:Name="OpenLogsButton" Content="Open Logs" Height="32" Margin="0,0,6,0"/>
                                <Button x:Name="ResetDefaultsButton" Content="Reset Defaults" Height="32" Margin="3,0,3,0"/>
                                <Button x:Name="QuitButton" Content="Quit" Height="32" Margin="6,0,0,0"/>
                            </UniformGrid>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <Border x:Name="MainFooter" Grid.Row="2" Background="#F6F6F4" CornerRadius="0,0,22,22" BorderBrush="#E2E3DF" BorderThickness="0,1,0,0">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Border x:Name="SettingsAction"
                            Width="132"
                            Height="36"
                            CornerRadius="12"
                            Background="Transparent"
                            Cursor="Hand"
                            Margin="0,0,12,0">
                        <TextBlock Text="Settings"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"
                                   Foreground="#191919"
                                   FontSize="14"/>
                    </Border>
                    <Border x:Name="TaskManagerAction"
                            Width="150"
                            Height="36"
                            CornerRadius="12"
                            Background="Transparent"
                            Cursor="Hand">
                        <TextBlock Text="Task Manager"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"
                                   Foreground="#191919"
                                   FontSize="14"/>
                    </Border>
                </StackPanel>
            </Border>
    </Grid>
</Border>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml] $xaml)
$rootContent = [Windows.Markup.XamlReader]::Load($reader)

$window = New-Object System.Windows.Window
$window.Width = 450
$window.Height = 560
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar = $false
$window.Topmost = $true
$window.SnapsToDevicePixels = $true
$window.UseLayoutRounding = $true
$window.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
$window.Content = $rootContent

$names = @(
    'RootBorder', 'HeaderTitle', 'StatusDot', 'MessageText', 'CloseAction', 'HeaderActionText',
    'MainPage', 'SettingsPage', 'MainFooter', 'UsageGrid', 'HeroCard', 'HeroValue', 'HeroStatus', 'HeroDetail',
    'CpuCard', 'CpuUsageValue', 'CpuUsageProgress', 'RamCard', 'RamValue', 'RamDetail', 'GpuCard', 'GpuUsageValue', 'GpuUsageProgress',
    'Process1Name', 'Process1Cpu', 'Process1Memory', 'Process2Name', 'Process2Cpu', 'Process2Memory',
    'Process3Name', 'Process3Cpu', 'Process3Memory', 'ProcessCard',
    'SettingsAction', 'TaskManagerAction', 'ThemeModeCombo', 'StartWithWindowsCheck',
    'RefreshPresetCombo', 'ShowBatteryPowerCheck', 'ShowCpuCheck', 'ShowMemoryCheck', 'ShowGpuCheck', 'ShowTopProcessesCheck', 'DetailedTooltipCheck',
    'OpenLogsButton', 'ResetDefaultsButton', 'QuitButton'
)

$ui = @{}
foreach ($name in $names) {
    $ui[$name] = $rootContent.FindName($name)
}

$script:CurrentPalette = $null
$script:IsSettingsPage = $false
$script:UpdatingSettingsControls = $false
$script:SuppressStartupSettingUpdate = $false

function New-SolidBrush {
    param([Parameter(Mandatory = $true)] [string] $Color)

    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color)
}

function Get-VisualChildren {
    param($Parent)

    $children = @()
    if ($null -eq $Parent) {
        return $children
    }

    try {
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            $children += $child
            $children += Get-VisualChildren -Parent $child
        }
    }
    catch {
    }

    return $children
}

function Get-LogicalChildren {
    param($Parent)

    $children = @()
    if ($null -eq $Parent) {
        return $children
    }

    try {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Parent)) {
            if ($child -is [System.Windows.DependencyObject]) {
                $children += $child
                $children += Get-LogicalChildren -Parent $child
            }
        }
    }
    catch {
    }

    return $children
}

function Get-ThemeElements {
    $seen = @{}
    $elements = @()

    foreach ($element in @($rootContent) + (Get-LogicalChildren -Parent $rootContent) + (Get-VisualChildren -Parent $rootContent)) {
        if ($null -eq $element) {
            continue
        }

        $hash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($element)
        if (-not $seen.ContainsKey($hash)) {
            $seen[$hash] = $true
            $elements += $element
        }
    }

    return $elements
}

function Set-ControlThemeResources {
    param(
        [Parameter(Mandatory = $true)] $Resources,
        [Parameter(Mandatory = $true)] $Palette
    )

    $Resources['ControlBackgroundBrush'] = New-SolidBrush $Palette.CardBackground
    $Resources['ControlForegroundBrush'] = New-SolidBrush $Palette.PrimaryText
    $Resources['ControlSecondaryForegroundBrush'] = New-SolidBrush $Palette.SecondaryText
    $Resources['ControlBorderBrush'] = New-SolidBrush $Palette.Border
    $Resources['ControlHoverBrush'] = New-SolidBrush $Palette.HoverBackground
    $Resources['ControlAccentBrush'] = New-SolidBrush (Get-StatusBrush 'Normal')
    $Resources['ControlCheckBrush'] = New-SolidBrush '#FFFFFF'

    $Resources[[System.Windows.SystemColors]::WindowBrushKey] = New-SolidBrush $Palette.CardBackground
    $Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = New-SolidBrush $Palette.PrimaryText
    $Resources[[System.Windows.SystemColors]::ControlBrushKey] = New-SolidBrush $Palette.CardBackground
    $Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = New-SolidBrush $Palette.PrimaryText
    $Resources[[System.Windows.SystemColors]::HighlightBrushKey] = New-SolidBrush $Palette.HoverBackground
    $Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = New-SolidBrush $Palette.PrimaryText
}

function Apply-Theme {
    $effectiveTheme = Resolve-EffectiveThemeMode -ThemeMode $script:Settings.ThemeMode
    $palette = Get-ThemePalette -EffectiveThemeMode $effectiveTheme
    $script:CurrentPalette = $palette

    Set-ControlThemeResources -Resources $ui.RootBorder.Resources -Palette $palette
    Set-ControlThemeResources -Resources $ui.ThemeModeCombo.Resources -Palette $palette
    Set-ControlThemeResources -Resources $ui.RefreshPresetCombo.Resources -Palette $palette

    $ui.RootBorder.Background = New-SolidBrush $palette.ShellBackground
    $ui.RootBorder.BorderBrush = New-SolidBrush $palette.Border
    if ($ui.RootBorder.Effect) {
        $ui.RootBorder.Effect.Opacity = [double] $palette.ShadowOpacity
    }

    foreach ($element in (Get-ThemeElements)) {
        if ($element -is [System.Windows.Controls.Border]) {
            if ($element.Name -eq 'RootBorder') {
                $element.Background = New-SolidBrush $palette.ShellBackground
                $element.BorderBrush = New-SolidBrush $palette.Border
            }
            elseif ($element.Name -eq 'CheckBoxFrame' -or $element.Name -eq 'ItemRoot') {
                continue
            }
            elseif ($element.Name -eq 'MainFooter') {
                $element.Background = New-SolidBrush $palette.FooterBackground
                $element.BorderBrush = New-SolidBrush $palette.Border
            }
            elseif ($element.Name -eq 'HeroCard') {
                $element.BorderBrush = New-SolidBrush $palette.Border
            }
            elseif ($element.Height -eq 1) {
                $element.Background = New-SolidBrush $palette.Divider
            }
            elseif ($element.Name -match 'Action$') {
                $element.Background = [System.Windows.Media.Brushes]::Transparent
            }
            else {
                $element.Background = New-SolidBrush $palette.CardBackground
                $element.BorderBrush = New-SolidBrush $palette.Border
            }
        }
        elseif ($element -is [System.Windows.Controls.TextBlock]) {
            $secondaryNames = @('MessageText', 'HeaderActionText', 'HeroDetail', 'RamDetail', 'Process1Cpu', 'Process1Memory', 'Process2Cpu', 'Process2Memory', 'Process3Cpu', 'Process3Memory')
            if ($secondaryNames -contains $element.Name) {
                $element.Foreground = New-SolidBrush $palette.SecondaryText
            }
            elseif ($element.FontSize -le 13 -and $element.FontWeight -ne [System.Windows.FontWeights]::SemiBold) {
                $element.Foreground = New-SolidBrush $palette.SecondaryText
            }
            else {
                $element.Foreground = New-SolidBrush $palette.PrimaryText
            }
        }
        elseif ($element -is [System.Windows.Controls.CheckBox]) {
            $element.Foreground = New-SolidBrush $palette.PrimaryText
            $element.Background = [System.Windows.Media.Brushes]::Transparent
        }
        elseif ($element -is [System.Windows.Controls.ComboBox]) {
            $element.Foreground = New-SolidBrush $palette.PrimaryText
            $element.Background = New-SolidBrush $palette.CardBackground
            $element.BorderBrush = New-SolidBrush $palette.Border
            foreach ($item in $element.Items) {
                if ($item -is [System.Windows.Controls.ComboBoxItem]) {
                    $item.Foreground = New-SolidBrush $palette.PrimaryText
                    $item.Background = New-SolidBrush $palette.CardBackground
                    $item.BorderBrush = New-SolidBrush $palette.Border
                }
            }
        }
        elseif ($element -is [System.Windows.Controls.Button]) {
            $element.Foreground = New-SolidBrush $palette.PrimaryText
            $element.Background = New-SolidBrush $palette.FooterBackground
            $element.BorderBrush = New-SolidBrush $palette.Border
        }
        elseif ($element -is [System.Windows.Controls.ProgressBar]) {
            $element.Background = New-SolidBrush $palette.Border
        }
    }

    Update-Dashboard
}

function Get-SelectedComboContent {
    param($ComboBox)

    if ($ComboBox.SelectedItem -and $ComboBox.SelectedItem.Content) {
        return $ComboBox.SelectedItem.Content.ToString()
    }

    return $null
}

function Select-ComboItem {
    param(
        [Parameter(Mandatory = $true)] $ComboBox,
        [Parameter(Mandatory = $true)] [string] $Content
    )

    foreach ($item in $ComboBox.Items) {
        if ($item.Content -eq $Content) {
            $ComboBox.SelectedItem = $item
            return
        }
    }
}

function Update-SettingsControls {
    $script:UpdatingSettingsControls = $true
    try {
        Select-ComboItem -ComboBox $ui.ThemeModeCombo -Content $script:Settings.ThemeMode
        Select-ComboItem -ComboBox $ui.RefreshPresetCombo -Content $script:Settings.RefreshPreset
        $ui.StartWithWindowsCheck.IsChecked = [bool] $script:Settings.StartWithWindows
        $ui.ShowBatteryPowerCheck.IsChecked = [bool] $script:Settings.ShowBatteryPower
        $ui.ShowCpuCheck.IsChecked = [bool] $script:Settings.ShowCpuUsage
        $ui.ShowMemoryCheck.IsChecked = [bool] $script:Settings.ShowMemoryUsage
        $ui.ShowGpuCheck.IsChecked = [bool] $script:Settings.ShowGpuUsage
        $ui.ShowTopProcessesCheck.IsChecked = [bool] $script:Settings.ShowTopProcesses
        $ui.DetailedTooltipCheck.IsChecked = [bool] $script:Settings.ShowDetailedTrayTooltip
    }
    finally {
        $script:UpdatingSettingsControls = $false
    }
}

function Set-CardMargin {
    param(
        [Parameter(Mandatory = $true)] $Card,
        [Parameter(Mandatory = $true)] [int] $Index,
        [Parameter(Mandatory = $true)] [int] $Count
    )

    $left = if ($Index -eq 0) { 0 } else { 6 }
    $right = if ($Index -eq ($Count - 1)) { 0 } else { 6 }
    $Card.Margin = New-Object System.Windows.Thickness($left, 0, $right, 0)
}

function Apply-DisplaySettings {
    $ui.HeroCard.Visibility = if ($script:Settings.ShowBatteryPower) { 'Visible' } else { 'Collapsed' }
    $ui.CpuCard.Visibility = if ($script:Settings.ShowCpuUsage) { 'Visible' } else { 'Collapsed' }
    $ui.RamCard.Visibility = if ($script:Settings.ShowMemoryUsage) { 'Visible' } else { 'Collapsed' }
    $ui.GpuCard.Visibility = if ($script:Settings.ShowGpuUsage) { 'Visible' } else { 'Collapsed' }

    $visibleUsageCards = @()
    if ($script:Settings.ShowCpuUsage) { $visibleUsageCards += $ui.CpuCard }
    if ($script:Settings.ShowMemoryUsage) { $visibleUsageCards += $ui.RamCard }
    if ($script:Settings.ShowGpuUsage) { $visibleUsageCards += $ui.GpuCard }
    $ui.UsageGrid.Visibility = if ($visibleUsageCards.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $ui.UsageGrid.Columns = [Math]::Max(1, $visibleUsageCards.Count)
    for ($i = 0; $i -lt $visibleUsageCards.Count; $i++) {
        Set-CardMargin -Card $visibleUsageCards[$i] -Index $i -Count $visibleUsageCards.Count
    }

    $ui.ProcessCard.Visibility = if ($script:Settings.ShowTopProcesses) { 'Visible' } else { 'Collapsed' }
}

function Save-SettingsFromControls {
    if ($script:UpdatingSettingsControls) {
        return
    }

    $previous = $script:Settings
    $updated = [pscustomobject]@{
        ThemeMode = Normalize-ThemeMode (Get-SelectedComboContent $ui.ThemeModeCombo)
        StartWithWindows = [bool] $ui.StartWithWindowsCheck.IsChecked
        RefreshPreset = Normalize-RefreshPreset (Get-SelectedComboContent $ui.RefreshPresetCombo)
        ShowBatteryPower = [bool] $ui.ShowBatteryPowerCheck.IsChecked
        ShowCpuUsage = [bool] $ui.ShowCpuCheck.IsChecked
        ShowMemoryUsage = [bool] $ui.ShowMemoryCheck.IsChecked
        ShowGpuUsage = [bool] $ui.ShowGpuCheck.IsChecked
        ShowTopProcesses = [bool] $ui.ShowTopProcessesCheck.IsChecked
        ShowDetailedTrayTooltip = [bool] $ui.DetailedTooltipCheck.IsChecked
    }

    $script:Settings = Save-AppSettings -Settings $updated -Path $script:SettingsPath
    if (-not $script:SuppressStartupSettingUpdate) {
        try {
            Set-StartWithWindows -Enabled $script:Settings.StartWithWindows -ScriptPath $PSCommandPath
        }
        catch {
            Write-AppLog "Startup setting failed: $($_.Exception.ToString())"
        }
    }

    Apply-DisplaySettings
    Apply-Theme

    if ($previous.RefreshPreset -ne $script:Settings.RefreshPreset -or
        $previous.ShowGpuUsage -ne $script:Settings.ShowGpuUsage -or
        $previous.ShowTopProcesses -ne $script:Settings.ShowTopProcesses) {
        Restart-StatsWorker
    }
}

function Show-MainPage {
    $script:IsSettingsPage = $false
    $ui.HeaderTitle.Text = $script:AppName
    $ui.HeaderActionText.Text = 'x'
    $ui.MainPage.Visibility = 'Visible'
    $ui.MainFooter.Visibility = 'Visible'
    $ui.SettingsPage.Visibility = 'Collapsed'
    Update-Dashboard
}

function Show-SettingsPage {
    $script:IsSettingsPage = $true
    $ui.HeaderTitle.Text = 'Settings'
    $ui.HeaderActionText.Text = '<'
    $ui.MainPage.Visibility = 'Collapsed'
    $ui.MainFooter.Visibility = 'Collapsed'
    $ui.SettingsPage.Visibility = 'Visible'
    $ui.MessageText.Text = 'Customize PC Status'
    Update-SettingsControls
    $ui.SettingsPage.UpdateLayout()
    Apply-Theme
    $window.Dispatcher.BeginInvoke([Action]{
        try { Apply-Theme } catch { Write-AppLog "Deferred theme apply failed: $($_.Exception.ToString())" }
    }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
}

function Set-MetricVisual {
    param(
        [Parameter(Mandatory = $true)] $Metric,
        [Parameter(Mandatory = $true)] $ValueElement,
        $DetailElement = $null,
        $ProgressElement = $null
    )

    if ($null -eq $Metric) {
        $Metric = New-HealthMetric -Label 'Unavailable' -Value $null -Unit '' -Status 'Unavailable' -Detail 'Unavailable'
    }

    $ValueElement.Text = Format-MetricValue $Metric
    $ValueElement.Foreground = Get-StatusBrush $Metric.Status

    if ($DetailElement) {
        $DetailElement.Text = $Metric.Detail
    }

    if ($ProgressElement) {
        $ProgressElement.Foreground = Get-StatusBrush $Metric.Status
        if ($null -eq $Metric.Value) {
            $ProgressElement.Value = 0
        }
        else {
            $ProgressElement.Value = [Math]::Max(0, [Math]::Min(100, [double] $Metric.Value))
        }
    }
}

function Get-SnapshotMetric {
    param(
        [Parameter(Mandatory = $true)] $Snapshot,
        [Parameter(Mandatory = $true)] [string] $Label,
        [string] $Unit = '',
        [string] $Detail = 'Unavailable'
    )

    if ($Snapshot -and $Snapshot.Metrics) {
        $metric = $Snapshot.Metrics | Where-Object Label -eq $Label | Select-Object -First 1
        if ($metric) {
            return $metric
        }
    }

    return (New-HealthMetric -Label $Label -Value $null -Unit $Unit -Status 'Unavailable' -Detail $Detail)
}

function Apply-Snapshot {
    param([Parameter(Mandatory = $true)] $Snapshot)

    $overallStatus = if ($Snapshot.OverallStatus) { $Snapshot.OverallStatus } else { 'Unavailable' }
    $message = if ($Snapshot.HealthLine) { $Snapshot.HealthLine } elseif ($Snapshot.Message) { $Snapshot.Message } else { 'Unable to refresh stats' }

    $ui.StatusDot.Fill = Get-StatusBrush $overallStatus
    if (-not $script:IsSettingsPage) {
        $ui.MessageText.Text = $message
    }

    $power = $Snapshot.Power
    $powerStatus = if ($power -and $power.Status) { $power.Status } else { 'Unavailable' }
    $ui.HeroCard.Background = Get-StatusBackground $powerStatus
    $ui.HeroValue.Text = if ($power -and $power.BatteryText) { $power.BatteryText } else { 'Unavailable' }
    $ui.HeroValue.Foreground = Get-StatusBrush $powerStatus
    $ui.HeroStatus.Text = if ($power -and $power.Mode) { $power.Mode } else { 'Power unavailable' }
    $ui.HeroStatus.Foreground = Get-StatusBrush $powerStatus
    $ui.HeroDetail.Text = if ($power -and $power.Detail) { $power.Detail } else { 'Windows power status unavailable' }

    Set-MetricVisual -Metric (Get-SnapshotMetric -Snapshot $Snapshot -Label 'CPU Usage' -Unit '%' -Detail 'Unavailable') -ValueElement $ui.CpuUsageValue -ProgressElement $ui.CpuUsageProgress
    Set-MetricVisual -Metric (Get-SnapshotMetric -Snapshot $Snapshot -Label 'RAM' -Unit '%' -Detail 'Unavailable') -ValueElement $ui.RamValue -DetailElement $ui.RamDetail
    Set-MetricVisual -Metric (Get-SnapshotMetric -Snapshot $Snapshot -Label 'GPU Usage' -Unit '%' -Detail 'Unavailable') -ValueElement $ui.GpuUsageValue -ProgressElement $ui.GpuUsageProgress

    for ($i = 1; $i -le 3; $i++) {
        $process = @($Snapshot.TopProcesses)[$i - 1]
        $ui["Process$($i)Name"].Text = if ($process) { $process.Name } elseif ($i -eq 1) { 'No process data' } else { '' }
        $ui["Process$($i)Cpu"].Text = if ($process) { "$($process.CpuPercent)%" } else { '' }
        $ui["Process$($i)Memory"].Text = if ($process) { "$($process.MemoryMb) MB" } else { '' }
    }

    $tooltip = if (-not $script:Settings.ShowDetailedTrayTooltip) {
        $script:AppName
    }
    elseif ($Snapshot.Tooltip) {
        $Snapshot.Tooltip
    }
    else {
        $script:AppName
    }
    $notifyIcon.Text = $tooltip.Substring(0, [Math]::Min(63, $tooltip.Length))
}

function Read-LatestSnapshot {
    if ([string]::IsNullOrWhiteSpace($script:SnapshotPath)) {
        return $script:LastSnapshot
    }

    if (-not (Test-Path $script:SnapshotPath)) {
        return $script:LastSnapshot
    }

    try {
        $snapshotFile = Get-Item -Path $script:SnapshotPath -ErrorAction Stop
        if ($script:LastSnapshot -and $snapshotFile.LastWriteTimeUtc -eq $script:LastSnapshotWriteTimeUtc) {
            return $script:LastSnapshot
        }

        $json = Get-Content -Path $script:SnapshotPath -Raw
        if ([string]::IsNullOrWhiteSpace($json)) {
            return $script:LastSnapshot
        }

        $snapshot = $json | ConvertFrom-Json
        $script:LastSnapshot = $snapshot
        $script:LastSnapshotWriteTimeUtc = $snapshotFile.LastWriteTimeUtc
        return $snapshot
    }
    catch {
        return $script:LastSnapshot
    }
}

function Update-Dashboard {
    try {
        $snapshot = Read-LatestSnapshot
        if ($snapshot) {
            Apply-Snapshot -Snapshot $snapshot
        }
        else {
            $ui.MessageText.Text = 'Collecting hardware stats'
        }
    }
    catch {
        Write-AppLog "Update-Dashboard failed: $($_.Exception.ToString())"
        $ui.MessageText.Text = 'Unable to refresh stats'
        $ui.StatusDot.Fill = Get-StatusBrush 'Hot'
    }
}

function Start-StatsWorker {
    $snapshotDirectory = Join-Path ([IO.Path]::GetTempPath()) 'WindowsDashboard'
    New-Item -ItemType Directory -Force -Path $snapshotDirectory | Out-Null
    $script:SnapshotPath = Join-Path $snapshotDirectory "snapshot-$PID.json"
    $workerPath = Join-Path $PSScriptRoot 'StatsWorker.ps1'
    $intervals = Get-RefreshPresetIntervals -Preset $script:Settings.RefreshPreset
    $includeGpuArgument = if ($script:Settings.ShowGpuUsage) { '$true' } else { '$false' }
    $includeTopProcessesArgument = if ($script:Settings.ShowTopProcesses) { '$true' } else { '$false' }

    $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$workerPath`" -OutputPath `"$script:SnapshotPath`" -IntervalMilliseconds $($intervals.CoreMilliseconds) -GpuIntervalMilliseconds $($intervals.GpuMilliseconds) -ProcessIntervalMilliseconds $($intervals.ProcessMilliseconds) -IncludeGpu:$includeGpuArgument -IncludeTopProcesses:$includeTopProcessesArgument"
    $process = Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    return $process
}

function Stop-StatsWorker {
    if ($script:StatsWorkerProcess -and -not $script:StatsWorkerProcess.HasExited) {
        $script:StatsWorkerProcess.Kill()
        $script:StatsWorkerProcess.Dispose()
    }
}

function Restart-StatsWorker {
    if ($ValidateOnly) {
        return
    }

    Stop-StatsWorker
    $script:LastSnapshot = $null
    $script:LastSnapshotWriteTimeUtc = [DateTime]::MinValue
    $script:StatsWorkerProcess = Start-StatsWorker
}

function Show-RefreshError {
    if (-not (Read-LatestSnapshot)) {
        $ui.MessageText.Text = 'Unable to refresh stats'
        $ui.StatusDot.Fill = Get-StatusBrush 'Hot'
    }
}

function Show-Dashboard {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $workArea.Right - $window.Width - 12
    $window.Top = $workArea.Bottom - $window.Height - 12
    $window.WindowState = [System.Windows.WindowState]::Normal
    Update-Dashboard
    if (-not $window.IsVisible) {
        $window.Show()
    }

    if (-not $timer.IsEnabled) {
        $timer.Start()
    }

    $window.Topmost = $false
    $window.Topmost = $true
    $window.Activate() | Out-Null
}

function Hide-Dashboard {
    if ($timer.IsEnabled) {
        $timer.Stop()
    }

    $window.Hide()
}

function Show-Settings {
    if (-not $window.IsVisible) {
        Show-Dashboard
    }

    Show-SettingsPage
}

function Add-HoverHandlers {
    param([Parameter(Mandatory = $true)] $Element)

    $Element.Add_MouseEnter({
        try {
            $this.Background = New-SolidBrush $script:CurrentPalette.HoverBackground
        }
        catch {
            Write-AppLog "MouseEnter failed: $($_.Exception.ToString())"
        }
    })
    $Element.Add_MouseLeave({
        try {
            $this.Background = 'Transparent'
        }
        catch {
            Write-AppLog "MouseLeave failed: $($_.Exception.ToString())"
        }
    })
}

Add-HoverHandlers -Element $ui.CloseAction
Add-HoverHandlers -Element $ui.SettingsAction
Add-HoverHandlers -Element $ui.TaskManagerAction

$ui.CloseAction.Add_MouseLeftButtonUp({
    try {
        if ($script:IsSettingsPage) {
            Show-MainPage
        }
        else {
            Hide-Dashboard
        }
    }
    catch { Write-AppLog "Close failed: $($_.Exception.ToString())" }
})
$ui.SettingsAction.Add_MouseLeftButtonUp({
    try { Show-Settings } catch { Write-AppLog "Settings action failed: $($_.Exception.ToString())" }
})
$ui.TaskManagerAction.Add_MouseLeftButtonUp({
    try { Start-Process taskmgr.exe } catch { Write-AppLog "Task Manager action failed: $($_.Exception.ToString())" }
})

$ui.ThemeModeCombo.Add_SelectionChanged({ try { Save-SettingsFromControls } catch { Write-AppLog "Theme setting failed: $($_.Exception.ToString())" } })
$ui.RefreshPresetCombo.Add_SelectionChanged({ try { Save-SettingsFromControls } catch { Write-AppLog "Refresh preset setting failed: $($_.Exception.ToString())" } })

function Add-SettingsCheckHandlers {
    param(
        [Parameter(Mandatory = $true)] $CheckBox,
        [Parameter(Mandatory = $true)] [string] $LogName
    )

    $localLogName = $LogName
    $handler = {
        try {
            Save-SettingsFromControls
        }
        catch {
            Write-AppLog "$localLogName setting failed: $($_.Exception.ToString())"
        }
    }

    $CheckBox.Add_Checked($handler)
    $CheckBox.Add_Unchecked($handler)
}

Add-SettingsCheckHandlers -CheckBox $ui.StartWithWindowsCheck -LogName 'Startup'
Add-SettingsCheckHandlers -CheckBox $ui.ShowBatteryPowerCheck -LogName 'Battery card'
Add-SettingsCheckHandlers -CheckBox $ui.ShowCpuCheck -LogName 'CPU card'
Add-SettingsCheckHandlers -CheckBox $ui.ShowMemoryCheck -LogName 'Memory card'
Add-SettingsCheckHandlers -CheckBox $ui.ShowGpuCheck -LogName 'GPU'
Add-SettingsCheckHandlers -CheckBox $ui.ShowTopProcessesCheck -LogName 'Process'
Add-SettingsCheckHandlers -CheckBox $ui.DetailedTooltipCheck -LogName 'Tooltip'
$ui.OpenLogsButton.Add_Click({
    try {
        $logPath = Get-AppLogPath
        Start-Process (Split-Path -Parent $logPath)
    }
    catch { Write-AppLog "Open logs failed: $($_.Exception.ToString())" }
})
$ui.ResetDefaultsButton.Add_Click({
    try {
        $script:Settings = Reset-AppSettings -Path $script:SettingsPath
        try { Set-StartWithWindows -Enabled $false -ScriptPath $PSCommandPath } catch { Write-AppLog "Reset startup setting failed: $($_.Exception.ToString())" }
        Update-SettingsControls
        Apply-DisplaySettings
        Apply-Theme
        Restart-StatsWorker
        Show-SettingsPage
    }
    catch { Write-AppLog "Reset defaults failed: $($_.Exception.ToString())" }
})
$ui.QuitButton.Add_Click({
    try {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        Stop-StatsWorker
        $window.Close()
        [System.Windows.Application]::Current.Shutdown()
    }
    catch { Write-AppLog "Settings quit failed: $($_.Exception.ToString())" }
})

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = New-TrayIcon
$notifyIcon.Text = $script:AppName
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $contextMenu.Items.Add('Open')
$settingsItem = $contextMenu.Items.Add('Settings')
$quitItem = $contextMenu.Items.Add('Quit')
$openItem.Add_Click({
    try { Show-Dashboard } catch { Write-AppLog "Open failed: $($_.Exception.ToString())" }
})
$settingsItem.Add_Click({
    try { Show-Settings } catch { Write-AppLog "Settings failed: $($_.Exception.ToString())" }
})
$quitItem.Add_Click({
    try {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        Stop-StatsWorker
        $window.Close()
        [System.Windows.Application]::Current.Shutdown()
    }
    catch {
        Write-AppLog "Quit failed: $($_.Exception.ToString())"
    }
})
$notifyIcon.ContextMenuStrip = $contextMenu

$notifyIcon.Add_MouseUp({
    try {
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ($window.IsVisible) {
                Hide-Dashboard
            }
            else {
                Show-Dashboard
            }
        }
    }
    catch {
        Write-AppLog "Tray click failed: $($_.Exception.ToString())"
    }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({ Update-Dashboard })

$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$app.Add_DispatcherUnhandledException({
    Write-AppLog "Dispatcher unhandled exception: $($_.Exception.ToString())"
    $_.Handled = $true
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    Write-AppLog "AppDomain unhandled exception: $($eventArgs.ExceptionObject.ToString())"
})
$script:StatsWorkerProcess = $null
$script:SnapshotPath = $null
$script:LastSnapshot = $null
$script:LastSnapshotWriteTimeUtc = [DateTime]::MinValue

Update-SettingsControls
Apply-DisplaySettings

if ($ValidateOnly) {
    $script:SnapshotPath = Join-Path ([IO.Path]::GetTempPath()) "WindowsDashboard\validation-snapshot-$PID.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SnapshotPath) | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'StatsWorker.ps1') -OutputPath $script:SnapshotPath -Once -IncludeGpu:$($script:Settings.ShowGpuUsage) -IncludeTopProcesses:$($script:Settings.ShowTopProcesses)
}
else {
    $script:StatsWorkerProcess = Start-StatsWorker
}

Apply-Theme
Update-Dashboard

if ($ValidateOnly) {
    Show-Dashboard
    Show-SettingsPage
    $originalSettings = $script:Settings
    $script:SuppressStartupSettingUpdate = $true
    try {
        $ui.ShowCpuCheck.IsChecked = -not [bool] $ui.ShowCpuCheck.IsChecked
        Save-SettingsFromControls
        if ($script:Settings.ShowCpuUsage -ne [bool] $ui.ShowCpuCheck.IsChecked) {
            throw 'Settings checkbox validation failed'
        }
    }
    finally {
        $script:SuppressStartupSettingUpdate = $false
    }
    $script:Settings = $originalSettings
    Save-AppSettings -Settings $script:Settings -Path $script:SettingsPath | Out-Null
    Update-SettingsControls
    Apply-DisplaySettings
    Apply-Theme
    Show-MainPage
    Hide-Dashboard
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if (Test-Path -LiteralPath $script:SettingsPath) {
        Remove-Item -LiteralPath $script:SettingsPath -Force
    }
    'WindowsDashboard validation OK'
    return
}

$app.Run() | Out-Null
