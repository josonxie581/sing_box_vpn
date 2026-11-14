#requires -Version 7.0
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$prefsPath = Join-Path $env:APPDATA 'josonxie\Gsou\shared_preferences.json'
$prefs = Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -AsHashtable
$keys = @($prefs.Keys | Where-Object { $_ -match '^(flutter\.)?vps_exit_management_profile_v1$' })
if ($keys.Count -ne 1) { throw '找不到唯一的已保存 VPS 管理连接。' }
$profile = $prefs[$keys[0]] | ConvertFrom-Json -AsHashtable
if ($profile.version -ne 1 -or
    $profile.host -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$' -or
    $profile.user -notmatch '^[a-z_][a-z0-9_-]{0,31}$' -or
    $profile.port -lt 1 -or $profile.port -gt 65535) { throw 'SSH 管理连接无效。' }
foreach ($path in @($profile.identityFile, $profile.knownHostsFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'SSH 文件路径无效。' }
}
Write-Host "只读核对 VPS：$($profile.host)；不会应用规则、部署服务或重启代理。"
if ($CheckOnly) { Write-Host '连接设置预检通过；未发起 SSH。'; return }

# Only project non-secret exit metadata. Never output the raw proxy config.
$remote = @'
import hashlib,json,pathlib,socket
report={}
def exits(value):
 if not isinstance(value,dict):return {'format':type(value).__name__}
 return {key:({'label':str(value[key].get('label',''))[:100],
               'ip':str(value[key].get('ip',''))[:60]}
              if isinstance(value[key],dict) else {'format':type(value[key]).__name__})
         for key in ('direct','au','sg') if key in value}
try:
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as client:
  client.settimeout(12);client.connect('/run/shaowei-vpn/control.sock')
  client.sendall(b'{"action":"status","actor":"Gsou-readonly-diagnostic"}\n')
  with client.makefile('rb') as stream:data=json.loads(stream.readline(131073))
 report['control_ok']=data.get('ok') is True
 result=data.get('result',{})
 report['reported_exits']=exits(result.get('exits'))
 report['policy_targets']={key:result.get('policy',{}).get(key) for key in ('default','claude','openai')}
except Exception:report['control_read']='failed'
try:
 raw=pathlib.Path('/root/sing-box/config.json').read_bytes()
 config=json.loads(raw)
 report['config_revision']=hashlib.sha256(raw).hexdigest()
 report['configured_outbounds']=[{'tag':str(item.get('tag',''))[:100],
                                 'type':str(item.get('type',''))[:40]}
                                for item in config.get('outbounds',[]) if isinstance(item,dict)]
except Exception:report['config_read']='failed'
try:report['stored_exits']=exits(json.loads(pathlib.Path('/var/lib/shaowei-vpn/exits.json').read_text()))
except Exception:report['metadata_read']='failed'
print(json.dumps(report,ensure_ascii=False))
'@
$quoted = $remote.Replace("'", "'\''")
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command ssh.exe -ErrorAction Stop).Source
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
foreach ($arg in @('-T', '-F', 'NUL', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes', '-o', 'UpdateHostKeys=no',
    '-o', "UserKnownHostsFile=$($profile.knownHostsFile)", '-o', 'GlobalKnownHostsFile=NUL',
    '-o', 'ConnectTimeout=8', '-i', $profile.identityFile, '-p', [string]$profile.port,
    "$($profile.user)@$($profile.host)", "/usr/bin/python3 -c '$quoted'")) {
    $start.ArgumentList.Add($arg)
}
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw '无法启动 SSH。' }
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) { throw '只读 SSH 检查超时。' }
    if ($process.ExitCode -ne 0) {
        $sshError = $errorTask.Result
        $reason = if ($sshError -match '(?s)Load key.*Permission denied') {
            '当前任务账号无权让 OpenSSH 读取该私钥（Load key: Permission denied）'
        } elseif ($sshError -match 'Host key verification failed|REMOTE HOST IDENTIFICATION') {
            'SSH 主机指纹校验失败'
        } elseif ($sshError -match 'Permission denied \(publickey') {
            '服务器拒绝了公钥认证'
        } elseif ($sshError -match '(?i)timed out|refused|unreachable') {
            '无法建立 SSH 网络连接'
        } else { "SSH 失败，退出码 $($process.ExitCode)" }
        throw "$reason；未修改服务器。"
    }
    $output = $outputTask.Result
    if ($output.Length -gt 131072) { throw '诊断响应过长。' }
    $report = $output | ConvertFrom-Json -AsHashtable
    $report['host'] = $profile.host
    $report['capturedAt'] = [DateTime]::UtcNow.ToString('o')
    $directory = Join-Path (Split-Path $PSScriptRoot -Parent) 'build'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $reportPath = Join-Path $directory 'vps-exits-readonly.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    Write-Host "只读结果已保存：$reportPath"
    $report | ConvertTo-Json -Depth 8 | Write-Host
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
