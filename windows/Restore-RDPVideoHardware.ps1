#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackupFile
)

$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\MacLowLatencyRDP\backups'

if ([string]::IsNullOrWhiteSpace($BackupFile)) {
    $BackupFile = Get-ChildItem -Path $root -Filter 'policy-backup.json' -Recurse -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path -LiteralPath $BackupFile)) {
    throw "Backup file not found: $BackupFile"
}

$state = Get-Content -LiteralPath $BackupFile -Raw | ConvertFrom-Json
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
