# Controlled 25-second full-screen motion workload for RDP codec A/B tests.
# It changes every remote pixel at roughly 60 Hz and closes automatically.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework

$window = New-Object System.Windows.Window
$window.Title = 'RDP 4K Motion Stress Test'
$window.WindowStyle = 'None'
$window.WindowState = 'Maximized'
$window.ResizeMode = 'NoResize'
$window.Topmost = $true

$grid = New-Object System.Windows.Controls.Grid
$label = New-Object System.Windows.Controls.TextBlock
$label.Text = 'RDP 4K motion stress test'
$label.FontSize = 54
$label.FontWeight = 'Bold'
$label.Foreground = [System.Windows.Media.Brushes]::White
$label.HorizontalAlignment = 'Center'
$label.VerticalAlignment = 'Center'
$grid.Children.Add($label) | Out-Null
$window.Content = $grid

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(16)
$started = Get-Date
$frame = 0

$timer.Add_Tick({
    $script:frame++
    $phase = $script:frame / 10.0
    $red = [byte](127.5 + 127.5 * [Math]::Sin($phase))
    $green = [byte](127.5 + 127.5 * [Math]::Sin($phase + 2.094))
    $blue = [byte](127.5 + 127.5 * [Math]::Sin($phase + 4.189))
    $color = [System.Windows.Media.Color]::FromRgb($red, $green, $blue)
    $grid.Background = [System.Windows.Media.SolidColorBrush]::new($color)
    $label.Text = "RDP 4K motion stress · frame $script:frame"

    if (((Get-Date) - $started).TotalSeconds -ge 25) {
        $timer.Stop()
        $window.Close()
    }
})

$window.Add_KeyDown({
    if ($_.Key -eq 'Escape') {
        $timer.Stop()
        $window.Close()
    }
})

$timer.Start()
$window.ShowDialog() | Out-Null
