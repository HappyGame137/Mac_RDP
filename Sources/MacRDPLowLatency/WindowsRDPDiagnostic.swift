import Foundation

enum WindowsRDPDiagnostic {
    static let powerShell = #"""
    $ErrorActionPreference = 'Continue'
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    $winStations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
    $eventLog = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTs/Operational'

    '=== GPU ==='
    Get-CimInstance Win32_VideoController |
      Select-Object Name, DriverVersion, VideoProcessor, AdapterRAM |
      Format-Table -AutoSize

    '=== RDP graphics policy (read only) ==='
    if (Test-Path $policy) {
      Get-ItemProperty $policy |
        Select-Object bEnumerateHWBeforeSW, AVCHardwareEncodePreferred, AVC444ModePreferred, SelectTransport |
        Format-List
    } else {
      'No machine RDP policy key; Windows defaults are in effect.'
    }

    '=== RDP maximum frame-rate override ==='
    $frameState = Get-ItemProperty $winStations
    if ($frameState.PSObject.Properties.Name -contains 'DWMFRAMEINTERVAL') {
      $interval = Get-ItemPropertyValue -Path $winStations -Name DWMFRAMEINTERVAL
      "DWMFRAMEINTERVAL=$interval (15 means a 60 FPS maximum)"
    } else {
      'DWMFRAMEINTERVAL is absent; the Windows default frame-rate limit applies.'
    }

    '=== Latest RDP graphics events: 170=hardware encoder, 162=codec profile ==='
    Get-WinEvent -FilterHashtable @{LogName=$eventLog; Id=162,170; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue |
      Select-Object -First 12 TimeCreated, Id, Message |
      Format-List

    '=== UDP 3389 listener ==='
    Get-NetUDPEndpoint -LocalPort 3389 -ErrorAction SilentlyContinue |
      Format-Table LocalAddress, LocalPort, OwningProcess -AutoSize

    '=== Enabled inbound UDP 3389 firewall rules ==='
    Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
      ForEach-Object {
        $rule = $_
        $port = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        if ($port.Protocol -eq 'UDP' -and $port.LocalPort -eq '3389') {
          [pscustomobject]@{Name=$rule.DisplayName; Profile=$rule.Profile; Enabled=$rule.Enabled}
        }
      } | Format-Table -AutoSize

    'Event 170 should contain "AVC hardware encoder enabled: 1".'
    'Event 162 should contain "Avc444FullScreenProfile" for full-screen AVC video encoding.'
    """#
}
