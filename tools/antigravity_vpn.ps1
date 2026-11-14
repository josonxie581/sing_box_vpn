# Run Antigravity CLI through the local Gsou HTTP proxy without restarting VPN.
# Example: .\tools\antigravity_vpn.ps1
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$ProxyPort = 7890,
    [string]$CliPath,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArguments = @()
)

$ErrorActionPreference = 'Stop'

if (-not $CliPath) {
    $command = Get-Command agy.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) {
        $CliPath = $command.Source
    } else {
        $CliPath = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
    }
}
if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
    throw "Antigravity CLI not found. Specify -CliPath with the path to agy.exe."
}

$client = New-Object System.Net.Sockets.TcpClient
try {
    if (-not $client.ConnectAsync('127.0.0.1', $ProxyPort).Wait(3000)) {
        throw "Gsou proxy is not reachable on 127.0.0.1:$ProxyPort."
    }
} finally {
    $client.Dispose()
}

# Scope proxy variables to this invocation; restore the caller's environment.
$savedEnvironment = @{}
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $proxyUrl = "http://127.0.0.1:$ProxyPort"
    [Environment]::SetEnvironmentVariable('HTTP_PROXY', $proxyUrl, 'Process')
    [Environment]::SetEnvironmentVariable('HTTPS_PROXY', $proxyUrl, 'Process')
    # Do not inherit a wildcard or Google bypass from the parent shell.
    [Environment]::SetEnvironmentVariable('NO_PROXY', 'localhost,127.0.0.1,::1', 'Process')
    Write-Host "Antigravity proxy: $proxyUrl"
    & $CliPath @CliArguments
    $cliExitCode = $LASTEXITCODE
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
exit $cliExitCode
