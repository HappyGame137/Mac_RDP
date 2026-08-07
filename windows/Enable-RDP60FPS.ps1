#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$winStationsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
$registryPath = 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
$valueName = 'DWMFRAMEINTERVAL'
$targetValue = 15
$root = 'C:\ProgramData\MacLowLatencyRDP'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $root "backups\frame-rate-$stamp"
$backupFile = Join-Path $backupDirectory 'frame-rate-backup.json'
$restoreFile = Join-Path $backupDirectory 'Restore-RDP60FPS.ps1'

New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
$existing = Get-ItemProperty -Path $winStationsPath -ErrorAction Stop
$existed = $existing.PSObject.Properties.Name -contains $valueName
$oldValue = if ($existed) { [int](Get-ItemPropertyValue -Path $winStationsPath -Name $valueName) } else { $null }

[pscustomobject]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    RegistryPath = $winStationsPath
    ValueName = $valueName
    Existed = $existed
    Value = $oldValue
} | ConvertTo-Json -Depth 4 | Set-Content -Path $backupFile -Encoding UTF8

@'
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BackupFile)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($BackupFile)) { $BackupFile = Join-Path $PSScriptRoot 'frame-rate-backup.json' }
$state = Get-Content -LiteralPath $BackupFile -Raw | ConvertFrom-Json
if ([bool]$state.Existed) {
    New-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -PropertyType DWord -Value ([int]$state.Value) -Force | Out-Null
} else {
    Remove-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -ErrorAction SilentlyContinue
}
Write-Host "RDP frame-rate limit restored from: $BackupFile" -ForegroundColor Green
Write-Host 'Restart Windows before reconnecting.' -ForegroundColor Yellow
'@ | Set-Content -Path $restoreFile -Encoding UTF8

& reg.exe add $registryPath /v $valueName /t REG_DWORD /d $targetValue /f | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to set $valueName" }
$actual = [int](Get-ItemPropertyValue -Path $winStationsPath -Name $valueName -ErrorAction Stop)
if ($actual -ne $targetValue) { throw "$valueName verification failed: $actual" }

Write-Host "Applied $valueName=$actual (60 FPS maximum)." -ForegroundColor Green
Write-Host "Backup: $backupFile" -ForegroundColor Cyan
Write-Host "Rollback: $restoreFile" -ForegroundColor Cyan
Write-Host 'Restart Windows before the 60 FPS A/B test.' -ForegroundColor Yellow
