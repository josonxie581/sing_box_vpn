#requires -Version 7.0
param(
    [string]$ReleaseDirectory = (Split-Path $PSScriptRoot -Parent),
    [string]$ServiceId,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$release = [IO.Path]::GetFullPath($ReleaseDirectory)
$prefsPath = Join-Path $env:APPDATA 'josonxie\Gsou\shared_preferences.json'
$state = Join-Path $env:LOCALAPPDATA 'Gsou\dmit'
$monitorPath = Join-Path $state 'ssh-monitor.json'
$snapshotPath = Join-Path $state 'snapshot.json'

foreach ($name in @('Gsou.exe', 'GsouDmitBridge.exe', 'dmit-extension\manifest.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $release $name) -PathType Leaf)) {
        throw "发布包缺少 $name，请完整解压后重试。"
    }
}
if (-not (Test-Path -LiteralPath $prefsPath -PathType Leaf)) {
    throw '找不到已保存的 VPS 管理连接，请先在 Gsou 的 VPS 出口管控页面保存连接。'
}
$prefs = Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -AsHashtable
$profileKeys = @($prefs.Keys | Where-Object { $_ -match '^(flutter\.)?vps_exit_management_profile_v1$' })
if ($profileKeys.Count -ne 1) { throw '没有唯一的 VPS 管理连接，请先在 Gsou 中重新保存连接。' }
$profile = $prefs[$profileKeys[0]] | ConvertFrom-Json -AsHashtable
if ($profile.version -ne 1 -or $profile.user -ne 'root' -or
    $profile.host -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$' -or
    $profile.port -lt 1 -or $profile.port -gt 65535) {
    throw '恢复只读监控需要有效的 root 管理连接，请先检查 VPS 出口管控设置。'
}
foreach ($path in @($profile.identityFile, $profile.knownHostsFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw '管理连接的私钥或 known_hosts 文件不存在，请先修正已保存的文件路径。'
    }
}

$existing = $null
if (Test-Path -LiteralPath $monitorPath -PathType Leaf) {
    try { $existing = Get-Content -LiteralPath $monitorPath -Raw | ConvertFrom-Json -AsHashtable }
    catch { Write-Warning '旧监控配置无法解析，将通过管理连接恢复。' }
}
if (-not $ServiceId -and $existing -and $existing.host -eq $profile.host) {
    $ServiceId = [string]$existing.serviceId
}
if (-not $ServiceId -and (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
    try {
        $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable
        $matchesByHost = @($snapshot.servers | Where-Object { $_.addresses -contains $profile.host })
        if ($matchesByHost.Count -eq 1) { $ServiceId = [string]$matchesByHost[0].serviceId }
    } catch { Write-Warning '没有可用的旧计费快照，请从 DMIT 客户区确认服务编号。' }
}
if ($ServiceId -and $ServiceId -notmatch '^\d+$') { throw 'DMIT 服务编号必须为数字。' }

Write-Host "VPS：$($profile.host):$($profile.port)"
Write-Host "监控配置存在：$(Test-Path -LiteralPath $monitorPath)"
Write-Host "计费快照存在：$(Test-Path -LiteralPath $snapshotPath)"
Write-Host "DMIT 服务编号：$(if ($ServiceId) { $ServiceId } else { '待确认' })"
if ($CheckOnly) {
    Write-Host '只读检查完成，未修改本机或服务器。'
    return
}

if (-not $ServiceId) {
    Write-Host '请打开 DMIT 对应 VPS 的产品详情，复制地址栏中的 id 数字。这里不使用历史默认编号。'
    $answer = (Read-Host '输入服务编号，或粘贴 DMIT 产品详情网址').Trim()
    if ($answer -match '^\d+$') { $ServiceId = $answer }
    else {
        $uri = $null
        if ([Uri]::TryCreate($answer, [UriKind]::Absolute, [ref]$uri) -and
            $uri.Scheme -eq 'https' -and $uri.Host -in @('www.dmit.io', 'dmit.io') -and
            $uri.Query -match '(?:^|[?&])id=(\d+)(?:&|$)') {
            $ServiceId = $Matches[1]
        } else { throw '未获得有效的 DMIT 服务编号，尚未修改配置。' }
    }
}

# Register the supplied bridge in the same Windows account as the app.
& (Join-Path $PSScriptRoot 'register_dmit_billing_bridge.ps1') -ReleaseDirectory $release

$reuse = $existing -and $existing.host -eq $profile.host -and
    $existing.serviceId -eq $ServiceId -and $existing.user -eq 'gsou-monitor' -and
    (Test-Path -LiteralPath $existing.identityFile -PathType Leaf) -and
    (Test-Path -LiteralPath $existing.knownHostsFile -PathType Leaf)
if (-not $reuse) {
    Write-Host '正在恢复受限只读 SSH 监控账号和独立监控密钥…'
    & (Join-Path $PSScriptRoot 'setup_dmit_ssh_monitor.ps1') `
        -HostAddress $profile.host -Port $profile.port -ServiceId $ServiceId `
        -AdminUser $profile.user -AdminIdentityFile $profile.identityFile `
        -AdminKnownHostsFile $profile.knownHostsFile
}

# Confirm a real sample before claiming the SSH monitor has recovered.
$config = Get-Content -LiteralPath $monitorPath -Raw | ConvertFrom-Json -AsHashtable
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command ssh.exe -ErrorAction Stop).Source
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($arg in @('-T', '-F', 'NUL', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes', '-o', "UserKnownHostsFile=$($config.knownHostsFile)",
    '-o', 'GlobalKnownHostsFile=NUL', '-o', 'ConnectTimeout=8',
    '-i', $config.identityFile, '-p', [string]$config.port, "$($config.user)@$($config.host)")) {
    $start.ArgumentList.Add($arg)
}
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw '无法启动 OpenSSH。' }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $lineTask = $process.StandardOutput.ReadLineAsync()
    if (-not $lineTask.Wait(25000)) { throw '未在 25 秒内收到监控数据，请核对 SSH 连接。' }
    $line = $lineTask.Result
    if (-not $line -or $line.Length -gt 16384) { throw 'SSH 未返回有效监控数据。' }
    $sample = $line | ConvertFrom-Json -AsHashtable
    $numericFields = @('cpuPercent', 'memoryTotalBytes', 'memoryAvailableBytes',
        'diskTotalBytes', 'diskAvailableBytes', 'load1', 'uptimeSeconds',
        'rxBytesPerSecond', 'txBytesPerSecond')
    foreach ($field in $numericFields) {
        if ($sample[$field] -isnot [ValueType] -or $sample[$field] -is [bool] -or
            -not [double]::IsFinite([double]$sample[$field]) -or $sample[$field] -lt 0) {
            throw '监控数据校验失败。'
        }
    }
    if ($sample.version -ne 1 -or $sample.cpuPercent -gt 100 -or
        $sample.memoryTotalBytes -le 0 -or $sample.diskTotalBytes -le 0 -or
        $sample.memoryAvailableBytes -gt $sample.memoryTotalBytes -or
        $sample.diskAvailableBytes -gt $sample.diskTotalBytes -or
        $sample.networkInterface.Length -gt 64 -or
        $sample.networkInterface -notmatch '^[A-Za-z0-9_.:-]+$') {
        throw '监控数据校验失败。'
    }
    Write-Host 'SSH 实时监控已收到有效样本。请在新版 Gsou 卡片点击重新连接。' -ForegroundColor Green
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}

Write-Host ''
Write-Host '计费桥接已注册；月度流量还需要浏览器真实同步：'
Write-Host '1. 在 Edge/Chrome 扩展管理中启用已有的 Gsou DMIT 扩展；若扩展丢失，打开开发人员模式并加载下面的文件夹：'
Write-Host (Join-Path $release 'dmit-extension')
Write-Host '2. 保持一个已登录的 https://www.dmit.io/clientarea.php 标签页，点击扩展中的同步按钮。'
Write-Host '出现真实月度数据后，计费同步才算恢复。本脚本不会生成模拟额度。'
