param(
    [string]$HostAddress = '154.31.116.184',
    [int]$Port = 22,
    [string]$ServiceId = '159947',
    [string]$AdminUser = 'root',
    [Parameter(Mandatory = $true)]
    [string]$AdminIdentityFile,
    [Parameter(Mandatory = $true)]
    [string]$AdminKnownHostsFile,
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'Gsou\dmit\ssh')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments
    )
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $AdminIdentityFile -PathType Leaf)) {
    throw "Administrator SSH identity does not exist: $AdminIdentityFile"
}
if (-not (Test-Path -LiteralPath $AdminKnownHostsFile -PathType Leaf)) {
    throw "Known-hosts file does not exist: $AdminKnownHostsFile"
}
if ($HostAddress -notmatch '^[A-Za-z0-9.-]{1,253}$' -or
    $ServiceId -notmatch '^\d+$' -or
    $AdminUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$' -or
    $Port -lt 1 -or $Port -gt 65535) {
    throw 'Invalid SSH monitor parameters'
}

$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$scp = (Get-Command scp.exe -ErrorAction Stop).Source
$sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
$icacls = (Get-Command icacls.exe -ErrorAction Stop).Source
$state = [IO.Path]::GetFullPath($StateDirectory)
$identity = Join-Path $state 'id_ed25519'
$publicIdentity = "$identity.pub"
$knownHosts = Join-Path $state 'known_hosts'
$config = Join-Path (Split-Path $state -Parent) 'ssh-monitor.json'
$monitorSource = Join-Path $PSScriptRoot 'gsou_monitor_status.py'
$installerSource = Join-Path $PSScriptRoot 'install_gsou_monitor.sh'

New-Item -ItemType Directory -Path $state -Force | Out-Null
if (-not (Test-Path -LiteralPath $identity)) {
    Invoke-Checked $sshKeygen @('-q', '-t', 'ed25519', '-N', '', '-C', 'gsou-monitor', '-f', $identity)
}
if (-not (Test-Path -LiteralPath $publicIdentity)) {
    throw 'SSH monitor public key is missing'
}

$principal = "$env:USERDOMAIN\$env:USERNAME"
Invoke-Checked $icacls @($identity, '/inheritance:r', '/grant:r', "${principal}:(R)")
Copy-Item -LiteralPath $AdminKnownHostsFile -Destination $knownHosts -Force

$scpCommon = @(
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$AdminKnownHostsFile",
    '-o', 'ConnectTimeout=8',
    '-i', $AdminIdentityFile,
    '-P', $Port.ToString()
)
$token = [Guid]::NewGuid().ToString('N')
$remoteMonitor = "/tmp/gsou-monitor-$token.py"
$remoteInstaller = "/tmp/gsou-monitor-$token.sh"
$remoteKey = "/tmp/gsou-monitor-$token.pub"
$destination = "$AdminUser@$HostAddress"

Invoke-Checked $scp ($scpCommon + @($monitorSource, "${destination}:$remoteMonitor"))
Invoke-Checked $scp ($scpCommon + @($installerSource, "${destination}:$remoteInstaller"))
Invoke-Checked $scp ($scpCommon + @($publicIdentity, "${destination}:$remoteKey"))

$sshCommon = @(
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$AdminKnownHostsFile",
    '-o', 'ConnectTimeout=8',
    '-i', $AdminIdentityFile,
    '-p', $Port.ToString(),
    $destination
)
$remoteCommand = "set -eu; chmod 700 $remoteInstaller; exec $remoteInstaller $remoteMonitor $remoteKey"
Invoke-Checked $ssh ($sshCommon + @($remoteCommand))

$configValue = [ordered]@{
    version = 1
    serviceId = $ServiceId
    host = $HostAddress
    port = $Port
    user = 'gsou-monitor'
    identityFile = $identity
    knownHostsFile = $knownHosts
}
$temporary = "$config.tmp"
[IO.File]::WriteAllText(
    $temporary,
    (($configValue | ConvertTo-Json -Depth 3 -Compress) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)
Move-Item -LiteralPath $temporary -Destination $config -Force

Write-Output "config=$config"
Write-Output "identity=$identity"
Write-Output 'server_user=gsou-monitor'
Write-Output 'setup=ok'
