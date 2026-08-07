import Foundation

enum WindowsRDPFrameRate {
    static let enable60FPSPowerShell = #"""
    # Run in Windows PowerShell as Administrator.
    $ErrorActionPreference='Stop'
    $path='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
    $regPath='HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
    $root='C:\ProgramData\MacLowLatencyRDP'
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir=Join-Path $root "backups\frame-rate-$stamp"
    $backup=Join-Path $dir 'frame-rate-backup.json'
    $restore=Join-Path $dir 'Restore-RDP60FPS.ps1'
    New-Item -Path $dir -ItemType Directory -Force|Out-Null
    $old=Get-ItemProperty -Path $path
    $existed=$old.PSObject.Properties.Name -contains 'DWMFRAMEINTERVAL'
    $value=if($existed){[int](Get-ItemPropertyValue -Path $path -Name DWMFRAMEINTERVAL)}else{$null}
    [pscustomobject]@{SchemaVersion=1;CreatedAt=(Get-Date).ToString('o');ComputerName=$env:COMPUTERNAME;RegistryPath=$path;ValueName='DWMFRAMEINTERVAL';Existed=$existed;Value=$value}|
      ConvertTo-Json -Depth 4|Set-Content -Path $backup -Encoding UTF8
    @'
    #Requires -RunAsAdministrator
    param([string]$BackupFile)
    $ErrorActionPreference='Stop'
    if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'frame-rate-backup.json'}
    $state=Get-Content -LiteralPath $BackupFile -Raw|ConvertFrom-Json
    if([bool]$state.Existed){New-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -PropertyType DWord -Value ([int]$state.Value) -Force|Out-Null}
    else{Remove-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -ErrorAction SilentlyContinue}
    Write-Host "Restored from $BackupFile" -ForegroundColor Green
    Write-Host 'Restart Windows before reconnecting.' -ForegroundColor Yellow
    '@|Set-Content -Path $restore -Encoding UTF8
    & reg.exe add $regPath /v DWMFRAMEINTERVAL /t REG_DWORD /d 15 /f|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Failed to set DWMFRAMEINTERVAL'}
    $actual=[int](Get-ItemPropertyValue -Path $path -Name DWMFRAMEINTERVAL)
    if($actual -ne 15){throw "DWMFRAMEINTERVAL verification failed: $actual"}
    Write-Host 'SUCCESS: RDP maximum is 60 FPS after restart.' -ForegroundColor Green
    Write-Host "Backup: $backup" -ForegroundColor Cyan
    Write-Host "Rollback: $restore" -ForegroundColor Cyan
    """#
}
