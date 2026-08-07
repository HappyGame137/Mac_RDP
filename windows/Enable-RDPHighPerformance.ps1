#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\MacLowLatencyRDP'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $root "backups\power-plan-$stamp"
$backupFile = Join-Path $backupDirectory 'power-plan-backup.json'
$restoreFile = Join-Path $backupDirectory 'Restore-RDPPowerPlan.ps1'
$activeText = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
$match = [regex]::Match($activeText, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
if (-not $match.Success) { throw "Unable to parse active power scheme: $activeText" }
$activeGuid = $match.Value

New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
[pscustomobject]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    ActiveSchemeGuid = $activeGuid
    ActiveSchemeText = $activeText
} | ConvertTo-Json -Depth 4 | Set-Content -Path $backupFile -Encoding UTF8

@'
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BackupFile)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'power-plan-backup.json'}
$state=Get-Content -LiteralPath $BackupFile -Raw|ConvertFrom-Json
& powercfg.exe /setactive ([string]$state.ActiveSchemeGuid)
if($LASTEXITCODE -ne 0){throw 'Failed to restore the original power scheme.'}
Write-Host "Restored power scheme: $($state.ActiveSchemeText)" -ForegroundColor Green
'@ | Set-Content -Path $restoreFile -Encoding UTF8

& powercfg.exe /setactive SCHEME_MIN
if ($LASTEXITCODE -ne 0) {
    throw 'High performance (SCHEME_MIN) is not available. No power-plan change was applied.'
}
$newActive = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()

Write-Host "Original: $activeText" -ForegroundColor Cyan
Write-Host "A/B active: $newActive" -ForegroundColor Green
Write-Host "Backup: $backupFile" -ForegroundColor Cyan
Write-Host "Rollback: $restoreFile" -ForegroundColor Cyan
Write-Host 'No restart is required. Compare the same RDP workload, then restore if heat or fan noise increases.' -ForegroundColor Yellow
