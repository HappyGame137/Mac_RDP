#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Inspect', 'Publish', 'Restore')][string]$Mode = 'Inspect',
    [string]$ProgramPath = (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
)

$ErrorActionPreference = 'Stop'
$root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList'
$apps = Join-Path $root 'Applications'
$alias = 'MacRDPVSCode'
$key = Join-Path $apps $alias
$owner = 'MacLowLatencyRDP-VSCode'
$program = Get-Item -LiteralPath $ProgramPath -ErrorAction SilentlyContinue
$policy = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue

if ($Mode -eq 'Inspect') {
    [pscustomobject]@{
        Alias = "||$alias"
        ProgramPath = $ProgramPath
        ProgramExists = ($null -ne $program -and !$program.PSIsContainer)
        AllowListEnabled = ($null -ne $policy -and $policy.fDisabledAllowList -eq 0)
        AliasExists = (Test-Path -LiteralPath $key)
    }
    if (Test-Path -LiteralPath $apps) {
        Get-ChildItem -LiteralPath $apps | ForEach-Object {
            Get-ItemProperty -LiteralPath $_.PSPath |
                Select-Object @{Name='Alias'; Expression={$_.PSChildName}}, Name, Path, CommandLineSetting
        } | Format-Table -AutoSize
    }
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Publish or Restore from an elevated Windows PowerShell.'
}

if ($Mode -eq 'Restore') {
    if (!(Test-Path -LiteralPath $key)) { Write-Output "||$alias is absent."; return }
    $current = Get-ItemProperty -LiteralPath $key
    if ($current.MacRDPTestOwner -ne $owner -or @(Get-ChildItem -LiteralPath $key).Count -ne 0) {
        throw 'Alias ownership or structure changed; refusing removal.'
    }
    if ($PSCmdlet.ShouldProcess($key, 'Remove this VS Code alias')) {
        Remove-Item -LiteralPath $key
        Write-Output "Removed ||$alias."
    }
    return
}

if ($null -eq $program -or $program.PSIsContainer -or $program.Name -ne 'Code.exe') {
    throw "VS Code executable not found at '$ProgramPath'. Pass the full path to Code.exe."
}
if ($null -eq $policy -or $policy.fDisabledAllowList -ne 0) {
    throw 'An enabled TSAppAllowList is required; its policy will not be changed.'
}
if (Test-Path -LiteralPath $key) { throw "||$alias already exists; refusing to overwrite." }
$signature = Get-AuthenticodeSignature -LiteralPath $program.FullName
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)') {
    throw 'Code.exe must have a valid Microsoft Authenticode signature.'
}
if (!$PSCmdlet.ShouldProcess($key, "Publish VS Code from $($program.FullName)")) { return }

if (!(Test-Path -LiteralPath $apps)) { New-Item -Path $apps | Out-Null }
New-Item -Path $key | Out-Null
try {
    New-ItemProperty -LiteralPath $key -Name MacRDPTestOwner -Value $owner -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $key -Name Name -Value 'Visual Studio Code' -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $key -Name Path -Value $program.FullName -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $key -Name VPath -Value $program.FullName -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $key -Name CommandLineSetting -Value 0 -PropertyType DWord | Out-Null
    New-ItemProperty -LiteralPath $key -Name RequiredCommandLine -Value '' -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $key -Name ShowInTSWA -Value 0 -PropertyType DWord | Out-Null
} catch {
    Remove-Item -LiteralPath $key
    throw
}
Get-ItemProperty -LiteralPath $key | Select-Object Name, Path, VPath, CommandLineSetting
Write-Output "Published ||$alias. Leave the RemoteApp command line and working directory blank."
