import Foundation

enum WindowsRDPHardware {
    static let enablePowerShell = #"""
    # Run in Windows PowerShell as Administrator.
    $ErrorActionPreference = 'Stop'
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    $root = 'C:\ProgramData\MacLowLatencyRDP'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $root "backups\hardware-video-$stamp"
    $backup = Join-Path $dir 'policy-backup.json'
    $restore = Join-Path $dir 'Restore-RDPVideoHardware.ps1'
    $names = @('bEnumerateHWBeforeSW','AVCHardwareEncodePreferred','AVC444ModePreferred')
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    $old = Get-ItemProperty -Path $policy -ErrorAction SilentlyContinue
    $values = foreach ($name in $names) {
      $exists = $null -ne $old -and $old.PSObject.Properties.Name -contains $name
      [pscustomobject]@{Name=$name; Existed=$exists; Value=if($exists){[int]$old.$name}else{$null}}
    }
    [pscustomobject]@{SchemaVersion=1; CreatedAt=(Get-Date).ToString('o'); ComputerName=$env:COMPUTERNAME; PolicyPath=$policy; Values=@($values)} |
      ConvertTo-Json -Depth 5 | Set-Content -Path $backup -Encoding UTF8
    @'
    #Requires -RunAsAdministrator
    param([string]$BackupFile)
    $ErrorActionPreference='Stop'
    if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'policy-backup.json'}
    $state=Get-Content -Path $BackupFile -Raw|ConvertFrom-Json
    New-Item -Path $state.PolicyPath -Force|Out-Null
    foreach($entry in $state.Values){
      if([bool]$entry.Existed){New-ItemProperty -Path $state.PolicyPath -Name $entry.Name -PropertyType DWord -Value ([int]$entry.Value) -Force|Out-Null}
      else{Remove-ItemProperty -Path $state.PolicyPath -Name $entry.Name -ErrorAction SilentlyContinue}
    }
    gpupdate.exe /target:computer /force
    Write-Host "Restored from $BackupFile" -ForegroundColor Green
    Write-Host 'Restart Windows before reconnecting.' -ForegroundColor Yellow
    '@ | Set-Content -Path $restore -Encoding UTF8
    gpupdate.exe /target:computer /force
    New-Item -Path $policy -Force | Out-Null
    $regPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    foreach ($name in $names) {
      & reg.exe add $regPath /v $name /t REG_DWORD /d 1 /f | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "Failed to set $name" }
    }
    foreach ($name in $names) {
      $actual = Get-ItemPropertyValue -Path $policy -Name $name -ErrorAction Stop
      if ([int]$actual -ne 1) { throw "$name verification failed: $actual" }
    }
    Get-ItemProperty -Path $policy | Select-Object bEnumerateHWBeforeSW,AVCHardwareEncodePreferred,AVC444ModePreferred | Format-List
    Write-Host "Backup: $backup" -ForegroundColor Cyan
    Write-Host "Rollback: $restore" -ForegroundColor Cyan
    Write-Host 'SUCCESS: restart Windows, reconnect, then validate RDP events 170 and 162.' -ForegroundColor Green
    """#

    static let restoreLatestPowerShell = #"""
    # Run in Windows PowerShell as Administrator.
    $restore = Get-ChildItem 'C:\ProgramData\MacLowLatencyRDP\backups' -Filter 'Restore-RDPVideoHardware.ps1' -Recurse |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $restore) { throw 'No MacLowLatencyRDP rollback script was found.' }
    & $restore.FullName
    """#
}
