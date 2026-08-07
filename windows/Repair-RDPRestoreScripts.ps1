#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\MacLowLatencyRDP\backups'
if (-not (Test-Path -LiteralPath $root)) { throw "Backup root not found: $root" }
$repaired = 0

$frameRestore = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BackupFile)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'frame-rate-backup.json'}
$state=Get-Content -LiteralPath $BackupFile -Raw|ConvertFrom-Json
if([bool]$state.Existed){New-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -PropertyType DWord -Value ([int]$state.Value) -Force|Out-Null}
else{Remove-ItemProperty -Path $state.RegistryPath -Name $state.ValueName -ErrorAction SilentlyContinue}
Write-Host "RDP frame-rate setting restored from: $BackupFile" -ForegroundColor Green
Write-Host 'Restart Windows before reconnecting.' -ForegroundColor Yellow
'@

$hardwareRestore = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BackupFile)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'policy-backup.json'}
$state=Get-Content -LiteralPath $BackupFile -Raw|ConvertFrom-Json
New-Item -Path $state.PolicyPath -Force|Out-Null
foreach($entry in $state.Values){
  if([bool]$entry.Existed){New-ItemProperty -Path $state.PolicyPath -Name $entry.Name -PropertyType DWord -Value ([int]$entry.Value) -Force|Out-Null}
  else{Remove-ItemProperty -Path $state.PolicyPath -Name $entry.Name -ErrorAction SilentlyContinue}
}
gpupdate.exe /target:computer /force
Write-Host "RDP hardware policy restored from: $BackupFile" -ForegroundColor Green
Write-Host 'Restart Windows before reconnecting.' -ForegroundColor Yellow
'@

$powerRestore = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BackupFile)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($BackupFile)){$BackupFile=Join-Path $PSScriptRoot 'power-plan-backup.json'}
$state=Get-Content -LiteralPath $BackupFile -Raw|ConvertFrom-Json
& powercfg.exe /setactive ([string]$state.ActiveSchemeGuid)
if($LASTEXITCODE -ne 0){throw 'Failed to restore the original power scheme.'}
Write-Host "Restored power scheme: $($state.ActiveSchemeText)" -ForegroundColor Green
'@

foreach ($backup in Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'frame-rate-backup.json') {
    Set-Content -LiteralPath (Join-Path $backup.DirectoryName 'Restore-RDP60FPS.ps1') -Value $frameRestore -Encoding UTF8
    $repaired++
}
foreach ($backup in Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'policy-backup.json') {
    Set-Content -LiteralPath (Join-Path $backup.DirectoryName 'Restore-RDPVideoHardware.ps1') -Value $hardwareRestore -Encoding UTF8
    $repaired++
}
foreach ($backup in Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'power-plan-backup.json') {
    Set-Content -LiteralPath (Join-Path $backup.DirectoryName 'Restore-RDPPowerPlan.ps1') -Value $powerRestore -Encoding UTF8
    $repaired++
}

Write-Host "SUCCESS: repaired $repaired rollback script(s) under $root" -ForegroundColor Green

