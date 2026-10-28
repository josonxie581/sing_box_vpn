param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$release = [IO.Path]::GetFullPath($ReleaseDirectory)
$bridge = Join-Path $release 'GsouDmitBridge.exe'
$extension = Join-Path $release 'dmit-extension\manifest.json'
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) {
    throw "DMIT bridge is missing: $bridge"
}
if (-not (Test-Path -LiteralPath $extension -PathType Leaf)) {
    throw "DMIT extension is missing: $extension"
}

$state = Join-Path $env:LOCALAPPDATA 'Gsou\dmit'
New-Item -ItemType Directory -Path $state -Force | Out-Null
$manifestPath = Join-Path $state 'native-host.json'
$manifest = [ordered]@{
    name = 'io.gsou.dmit'
    description = 'Gsou DMIT read-only billing bridge'
    path = $bridge
    type = 'stdio'
    allowed_origins = @('chrome-extension://gndepdbhjnecffdppjakdjikfnchkmaa/')
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

reg.exe add 'HKCU\Software\Google\Chrome\NativeMessagingHosts\io.gsou.dmit' /ve /t REG_SZ /d $manifestPath /f | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to register the Chrome native host' }
reg.exe add 'HKCU\Software\Microsoft\Edge\NativeMessagingHosts\io.gsou.dmit' /ve /t REG_SZ /d $manifestPath /f | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to register the Edge native host' }

Write-Output "DMIT billing bridge registered: $manifestPath"
