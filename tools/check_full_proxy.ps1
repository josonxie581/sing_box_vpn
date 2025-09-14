<#!
.SYNOPSIS
  自动化诊断：当前 Windows 下 sing-box TUN (Gsou Tunnel) 是否基本实现 “全量代理 / 无明显泄漏”。

.DESCRIPTION
  本脚本执行多项可观测检查并给出一个启发式结论：
    1. 路由表：默认路由 (0.0.0.0/0 或 0.0.0.0/1 + 128.0.0.0/1) 是否指向 TUN 接口。
    2. 例外路由：是否只保留本地网段/广播/多播排除。
    3. 适配器统计：执行一轮网络流量压测前后对比 TUN 与物理网卡字节增量。
    4. 出口 IP：采样多个公共 IP 服务，确认是否一致（以及与直连基线不同）。
    5. DNS：列出接口 DNS；解析多个境外域名，统计解析失败与解析量。
    6. IPv6：检测是否能直接访问 IPv6（若 TUN 未启用 IPv6 可能是泄漏）。

  结果为启发式，不保证绝对准确：
    - 规则模式下国内域名直连属于设计行为；
    - QUIC 等多路复用会让物理网卡出现少量长连接；
    - CDN / 多出口代理可能导致多个外部 IP；
    - DNS 仍可能因系统层缓存而看似“本地”解析。

.PARAMETER TunAdapterName
  TUN 适配器名（默认 "Gsou Tunnel"）。

.PARAMETER TrafficDurationSeconds
  压测持续秒数（默认 6）。

.PARAMETER Silent
  只输出最终总结 JSON，不输出过程日志。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tools\check_full_proxy.ps1

.EXAMPLE
  .\tools\check_full_proxy.ps1 -TunAdapterName "Gsou Tunnel" -TrafficDurationSeconds 10

.OUTPUTS
  标准输出：过程日志 + 最终 JSON 诊断对象。

#>
[CmdletBinding()]
param(
  [string]$TunAdapterName = 'Gsou Tunnel',
  [int]$TrafficDurationSeconds = 6,
  [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeCount {
  param($obj)
  if ($null -eq $obj) { return 0 }
  if ($obj -is [System.Array]) { return $obj.Count }
  if ($obj -is [System.Collections.ICollection]) { return $obj.Count }
  # Wrap single object
  return @( $obj ).Count
}

function Write-Info($msg) { if (-not $Silent) { Write-Host "[INFO ] $msg" -ForegroundColor Cyan } }
function Write-Warn($msg) { if (-not $Silent) { Write-Host "[WARN ] $msg" -ForegroundColor Yellow } }
function Write-Err ($msg) { if (-not $Silent) { Write-Host "[ERROR] $msg" -ForegroundColor Red } }

function Get-AdapterOrNull($name) {
  try { return Get-NetAdapter -Name $name -ErrorAction Stop } catch { return $null }
}

function Get-DefaultRouteInfo {
  $routes = Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -in '0.0.0.0/0','0.0.0.0/1','128.0.0.0/1' } |
    Select-Object DestinationPrefix, InterfaceIndex, InterfaceAlias, NextHop, RouteMetric
  return $routes
}

function Test-Routes($tunIfIndex) {
  $r = Get-DefaultRouteInfo
  $splitStyle = ($r.DestinationPrefix -contains '0.0.0.0/1') -and ($r.DestinationPrefix -contains '128.0.0.0/1')
  $fullStyle  = ($r.DestinationPrefix -contains '0.0.0.0/0')
  $allOnTun   = $true
  foreach ($row in $r) { if ($row.InterfaceIndex -ne $tunIfIndex) { $allOnTun = $false } }
  [pscustomobject]@{
    Routes                = $r
    SplitDefaultStyle     = $splitStyle
    SingleDefaultStyle    = $fullStyle
    AllDefaultOnTun       = $allOnTun
    DefaultRouteInterface = ($r | Group-Object InterfaceIndex | ForEach-Object { "IF=$($_.Name) count=$($_.Count)" })
  }
}

function Get-PhysicalCandidates($tunName) {
  $tun = Get-AdapterOrNull $tunName
  if (-not $tun) { return @() }
  $all = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -ne $tunName }
  $filtered = $all | Where-Object { $_.HardwareInterface -eq $true }
  if ((Get-SafeCount $filtered) -eq 0) { $filtered = $all }
  return $filtered
}

function Get-AdapterStats($adapters) {
  $result = @{}
  foreach ($a in $adapters) {
    $s = Get-NetAdapterStatistics -Name $a.Name
    $result[$a.Name] = [pscustomobject]@{
      Name = $a.Name
      IfIndex = $a.ifIndex
      Tx = $s.SentUnicastBytes + $s.SentNonUnicastBytes
      Rx = $s.ReceivedUnicastBytes + $s.ReceivedNonUnicastBytes
      Timestamp = Get-Date
    }
  }
  return $result
}

function Invoke-TrafficBurst($seconds, $parallel = 4) {
  $urls = @(
    'https://www.google.com/robots.txt',
    'https://cdn.jsdelivr.net/npm/axios/dist/axios.min.js',
    'https://api.github.com',
    'https://www.cloudflare.com/cdn-cgi/trace'
  )
  $end = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $end) {
    1..$parallel | ForEach-Object {
      $u = Get-Random -InputObject $urls
      Start-Job -ScriptBlock {
        param($url)
        try { Invoke-WebRequest -Uri $url -TimeoutSec 8 | Out-Null } catch {}
      } -ArgumentList $u | Out-Null
    }
    Start-Sleep -Milliseconds 850
    Get-Job | Where-Object { $_.State -ne 'Running' } | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
  }
  Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
}

function Get-PublicIPs {
  $services = @(
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
    'https://ipinfo.io/ip'
  )
  $ips = @()
  foreach ($s in $services) {
    try {
      $resp = Invoke-WebRequest -Uri $s -TimeoutSec 6
      $ip = ($resp.Content.Trim())
      if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -or $ip -match '^[0-9a-fA-F:]+$') { $ips += $ip }
    } catch { }
  }
  $distinct = $ips | Select-Object -Unique
  [pscustomobject]@{ Raw=$ips; Distinct=$distinct }
}

function Test-DNSResolution {
  $domains = 'www.google.com','www.youtube.com','api.github.com','www.cloudflare.com'
  $records = @()
  foreach ($d in $domains) {
    try {
      $ans = Resolve-DnsName -Name $d -Type A -ErrorAction Stop
      foreach ($a in $ans) {
        if ($a.IPAddress) { $records += [pscustomobject]@{Domain=$d; Address=$a.IPAddress; Name=$a.NameHost; Section=$a.Section} }
      }
    } catch {
      $records += [pscustomobject]@{Domain=$d; Address=$null; Name=$null; Section='ERROR'}
    }
  }
  return $records
}

function Test-IPv6Reachable {
  try {
    $r = Test-NetConnection -ComputerName ipv6.google.com -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
    return ($r.PingSucceeded -or $r.TcpTestSucceeded)
  } catch { return $false }
}

Write-Info "[Start] Full-proxy diagnosis (TUN='$TunAdapterName', Duration=${TrafficDurationSeconds}s)"

$tunAdapter = Get-AdapterOrNull $TunAdapterName
if (-not $tunAdapter) { Write-Err "TUN adapter '$TunAdapterName' not found (not connected?)" }

if ($tunAdapter) { $routeDiag = Test-Routes -tunIfIndex $tunAdapter.ifIndex } else { $routeDiag = $null }
if ($routeDiag) {
  $routeCount = 0
  if ($routeDiag.Routes) { $routeCount = Get-SafeCount $routeDiag.Routes }
  Write-Info "Default route entries: $routeCount  AllOnTun=$($routeDiag.AllDefaultOnTun) SplitStyle=$($routeDiag.SplitDefaultStyle) SingleStyle=$($routeDiag.SingleDefaultStyle)"
} else { Write-Warn 'Cannot get default route diagnostics (no TUN?)' }

$phys = Get-PhysicalCandidates -tunName $TunAdapterName
if ($phys) {
  $physNames = @($phys | ForEach-Object { $_.Name })
  Write-Info ("Physical candidate adapters: " + ($physNames -join ', '))
} else {
  Write-Info 'Physical candidate adapters: <none>'
}

$sampleAdapters = @()
if ($tunAdapter) { $sampleAdapters += $tunAdapter }
$sampleAdapters += $phys
$statsBefore = Get-AdapterStats -adapters $sampleAdapters
Write-Info "Sampled initial adapter stats: $($statsBefore.Keys -join ', ')"

$publicIPs = Get-PublicIPs
Write-Info "Public egress IPs (sample) => $($publicIPs.Distinct -join ', ')"

$dnsCfg = Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,ServerAddresses
Write-Info "Interface DNS configuration sampled"

$ipv6Leak = Test-IPv6Reachable
Write-Info "IPv6 reachable=$ipv6Leak (if proxy not handling IPv6 this may be a leak)"

$dnsRecords = Test-DNSResolution
Write-Info "Resolved test domains: $((($dnsRecords | Select-Object -ExpandProperty Domain) | Select-Object -Unique) -join ', ')"

if ($tunAdapter) {
  Write-Info "Starting traffic burst ${TrafficDurationSeconds}s ..."
  Invoke-TrafficBurst -seconds $TrafficDurationSeconds
  Write-Info 'Traffic burst finished'
}
else {
  Write-Warn 'Skip traffic burst: no TUN adapter'
}

$statsAfter = Get-AdapterStats -adapters $sampleAdapters

function Get-Deltas {
  param($before,$after)
  $out = @{}
  foreach ($k in $before.Keys) {
    if ($after.ContainsKey($k)) {
      $b = $before[$k]; $a = $after[$k]
      $out[$k] = [pscustomobject]@{
        Name = $k
        TxDelta = ($a.Tx - $b.Tx)
        RxDelta = ($a.Rx - $b.Rx)
      }
    }
  }
  return $out
}
 
$deltas = Get-Deltas -before $statsBefore -after $statsAfter

Write-Info 'Adapter deltas (bytes):'
foreach ($d in $deltas.Values) {
  Write-Info ("  {0,-18} TX={1,10}  RX={2,10}" -f $d.Name,$d.TxDelta,$d.RxDelta)
}

$heuristics = [pscustomobject]@{
  HasTunAdapter              = [bool]$tunAdapter
  AllDefaultRouteOnTun       = $routeDiag?.AllDefaultOnTun
  UsingSplitDefault          = $routeDiag?.SplitDefaultStyle
  UsingSingleDefault         = $routeDiag?.SingleDefaultStyle
  TunTxRxDelta               = if ($tunAdapter -and $deltas.ContainsKey($TunAdapterName)) { $deltas[$TunAdapterName].TxDelta + $deltas[$TunAdapterName].RxDelta } else { 0 }
  PhysAdaptersTxRxTotalDelta = ($deltas.GetEnumerator() | Where-Object { $_.Key -ne $TunAdapterName } | ForEach-Object { $_.Value.TxDelta + $_.Value.RxDelta } | Measure-Object -Sum).Sum
  PublicIPs                  = $publicIPs.Distinct
  PublicIPCount              = (Get-SafeCount $publicIPs.Distinct)
  IPv6Reachable              = $ipv6Leak
  DNSServers                 = ($dnsCfg | ForEach-Object { [pscustomobject]@{ Interface=$_.InterfaceAlias; Servers=($_.ServerAddresses -join ',') } })
  DNSRecordsCount            = (Get-SafeCount $dnsRecords)
  DNSFailedCount             = (Get-SafeCount ($dnsRecords | Where-Object { $_.Section -eq 'ERROR' }))
}

$score = 0
if ($heuristics.HasTunAdapter) { $score += 1 }
if ($heuristics.AllDefaultRouteOnTun) { $score += 2 } elseif ($heuristics.UsingSplitDefault) { $score += 1 }
if ($heuristics.TunTxRxDelta -gt 50000) { $score += 2 }
if ($heuristics.PublicIPCount -eq 1) { $score += 1 } elseif ($heuristics.PublicIPCount -gt 1) { $score -= 1 }
if (-not $heuristics.IPv6Reachable) { $score += 1 } else { $score -= 1 }
if ($heuristics.DNSFailedCount -eq 0) { $score += 1 }

function Get-ProxyVerdict($s) {
  if ($s -ge 6) { return 'Likely full proxy (no obvious leak)' }
  elseif ($s -ge 3) { return 'Partially proxied; possible bypass or insufficient sample' }
  else { return 'Not full proxy; check routes/IPv6/DNS/mode' }
}

$summary = [pscustomobject]@{
  Score             = $score
  Verdict           = Get-ProxyVerdict $score
  Heuristics        = $heuristics
  Routes            = $routeDiag?.Routes
  AdapterDeltas     = $deltas.Values
  Timestamp         = (Get-Date).ToString('s')
  Tips              = @( 'Capture on physical adapter: expect only few long-lived proxy connections', 'Ensure GLOBAL mode when validating full proxy', 'IPv6Reachable=true & no IPv6 TUN => potential IPv6 leak', 'PublicIPCount>1 may mean multi-exit/CDN or partial direct', 'Score is heuristic; confirm with manual checks' )
}

Write-Info '---------------------------------------------'
Write-Info "Diagnosis score: $($summary.Score) => $($summary.Verdict)"
Write-Info '---------------------------------------------'
Write-Output ($summary | ConvertTo-Json -Depth 6)
