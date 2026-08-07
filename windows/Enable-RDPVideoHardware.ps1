#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$root = 'C:\ProgramData\MacLowLatencyRDP'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $root "backups\hardware-video-$stamp"
$backupFile = Join-Path $backupDirectory 'policy-backup.json'
$restoreFile = Join-Path $backupDirectory 'Restore-RDPVideoHardware.ps1'
$valueNames = @(
    'bEnumerateHWBeforeSW',
    'AVCHardwareEncodePreferred',
    'AVC444ModePreferred'
)

New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null

$existingPolicy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
$values = foreach ($name in $valueNames) {
    $exists = $null -ne $existingPolicy -and
        $existingPolicy.PSObject.Properties.Name -contains $name
    [pscustomobject]@{
        Name = $name
        Existed = $exists
        Value = if ($exists) { [int]$existingPolicy.$name } else { $null }
    }
}

[pscustomobject]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    PolicyPath = $policyPath
    Values = @($values)
} | ConvertTo-Json -Depth 5 | Set-Content -Path $backupFile -Encoding UTF8

$restoreScript = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackupFile = (Join-Path $PSScriptRoot 'policy-backup.json')
)

$ErrorActionPreference = 'Stop'
$state = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
$policyPath = [string]$state.PolicyPath
New-Item -Path $policyPath -Force | Out-Null

foreach ($entry in $state.Values) {
    if ([bool]$entry.Existed) {
        New-ItemProperty -Path $policyPath -Name $entry.Name -PropertyType DWord -Value ([int]$entry.Value) -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $policyPath -Name $entry.Name -ErrorAction SilentlyContinue
    }
}

gpupdate.exe /target:computer /force | Out-Host
Write-Host "RDP graphics policy restored from: $BackupFile" -ForegroundColor Green
Write-Host 'Restart Windows before testing another RDP session.' -ForegroundColor Yellow
'@
$restoreScript | Set-Content -Path $restoreFile -Encoding UTF8

gpupdate.exe /target:computer /force | Out-Host

New-Item -Path $policyPath -Force | Out-Null
$registryPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
foreach ($name in $valueNames) {
    & reg.exe add $registryPath /v $name /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to set $name" }
}

foreach ($name in $valueNames) {
    $actual = Get-ItemPropertyValue -Path $policyPath -Name $name -ErrorAction Stop
    if ([int]$actual -ne 1) { throw "$name verification failed: $actual" }
}

Write-Host 'Applied RDP hardware video policies:' -ForegroundColor Green
Get-ItemProperty -Path $policyPath |
    Select-Object bEnumerateHWBeforeSW, AVCHardwareEncodePreferred, AVC444ModePreferred |
    Format-List
Write-Host "Backup: $backupFile" -ForegroundColor Cyan
Write-Host "Rollback: $restoreFile" -ForegroundColor Cyan
Write-Host 'Restart Windows before validating events 170 and 162.' -ForegroundColor Yellow
