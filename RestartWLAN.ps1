#requires -Version 5.1
# RestartWLAN v3.0 - 网卡重启小工具
# 启动: 双击 RestartWLAN.bat, 或
#   powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
# 可选参数:
#   -Adapter <名称>        指定网卡, 默认 WLAN; 默认名不存在时自动识别无线网卡
#   -PingCount <次数>      丢包测试包数, 默认 20
#   -PingIntervalMs <毫秒> 丢包测试间隔, 默认 500
#   -DryRun                只读演练: 不修改省电模式, 不重启网卡
#   -NoElevate             跳过自提权(当前需已是管理员, 或仅做只读检查)
param(
    [string]$Adapter = 'WLAN',
    [ValidateRange(1, 200)][int]$PingCount = 20,
    [ValidateRange(10, 5000)][int]$PingIntervalMs = 500,
    [switch]$DryRun,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Continue'
try { $Host.UI.RawUI.WindowTitle = '网卡重启小工具 v3.0' } catch { }

$script:Sites = @(
    'www.baidu.com'
    'www.bilibili.com'
    'www.qq.com'
    'www.taobao.com'
    'www.163.com'
    'www.jd.com'
    'www.aliyun.com'
    'www.douyin.com'
)
$script:TotalSteps = 7
$script:PingCount = $PingCount
$script:PingIntervalMs = $PingIntervalMs
$script:DryRun = [bool]$DryRun
$script:Toggled = $false
$script:Restarted = $false
$script:ExitCode = 0
$script:PowerChange = $null
$script:TranscriptStarted = $false
$script:LogPath = $null

# ---------- 网卡识别 ----------
$adapterExplicit = $PSBoundParameters.ContainsKey('Adapter')
$adapterCandidates = @(Get-NetAdapter -Name $Adapter -ErrorAction SilentlyContinue)

if ($adapterCandidates.Count -gt 1) {
    Write-Host ('网卡名 "' + $Adapter + '" 匹配到多块网卡, 请用 -Adapter 写完整名称:')
    $adapterCandidates | ForEach-Object { Write-Host ('   - ' + $_.Name) }
    Read-Host '   按 Enter 键退出'
    exit 1
}

if ($adapterCandidates.Count -eq 0) {
    if ($adapterExplicit) {
        Write-Host ('找不到指定网卡: ' + $Adapter)
        Read-Host '   按 Enter 键退出'
        exit 1
    }

    $adapterCandidates = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.NdisPhysicalMedium -eq 9 })

    if ($adapterCandidates.Count -eq 0) {
        Write-Host '找不到无线网卡, 无法继续。'
        Read-Host '   按 Enter 键退出'
        exit 1
    }
    if ($adapterCandidates.Count -gt 1) {
        Write-Host '检测到多块无线网卡, 请用 -Adapter 指定:'
        $adapterCandidates | ForEach-Object { Write-Host ('   - ' + $_.Name + '  (' + $_.InterfaceDescription + ')') }
        Read-Host '   按 Enter 键退出'
        exit 1
    }
}

$script:AdapterName = $adapterCandidates[0].Name

# ---------- 自提权 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate -and -not $DryRun) {
    Write-Host '本工具需要管理员权限, 请在弹出的窗口中点击"是"。'
    $elevateArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"'),
        '-Adapter', ('"' + $script:AdapterName + '"'),
        '-PingCount', ([string]$PingCount),
        '-PingIntervalMs', ([string]$PingIntervalMs)
    )
    try {
        $elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevateArgs -PassThru -Wait -ErrorAction Stop
        exit $elevated.ExitCode
    } catch {
        Write-Host ('提权失败或已取消: ' + $_.Exception.Message)
        Read-Host '   按 Enter 键退出'
        exit 1
    }
}

# ---------- 辅助函数 ----------
function Show-Step([int]$n, [string]$title) {
    Write-Host ''
    Write-Host ' ------------------------------------------------'
    Write-Host ('  [{0}/{1}] {2}' -f $n, $script:TotalSteps, $title)
    Write-Host ' ------------------------------------------------'
}

function Ask([string]$prompt) {
    $answer = (Read-Host $prompt).Trim().ToLowerInvariant()
    return $answer -in @('y', 'yes', '是')
}

function Start-Log {
    try {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }
        $dir = Join-Path $base 'RestartWLAN\logs'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $script:LogPath = Join-Path $dir ('RestartWLAN_{0:yyyyMMdd_HHmmss_fff}.log' -f (Get-Date))
        Start-Transcript -Path $script:LogPath -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        $script:LogPath = $null
        $script:TranscriptStarted = $false
    }
}

function Get-NetshValue([string[]]$lines, [string]$pattern) {
    $match = $lines | Select-String -Pattern $pattern | Select-Object -First 1
    if (-not $match) { return '' }
    return (($match.Line -replace '^[^:：]*[:：]\s*', '').Trim())
}

function Get-PowerSavingProperty {
    Get-NetAdapterAdvancedProperty -Name $script:AdapterName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.RegistryKeyword -eq 'LowPowerEnable' -or
            $_.DisplayName -match '省电|节能|Power\s*Saving|PowerSave'
        } |
        Select-Object -First 1
}

function Get-PowerSavingText {
    $p = Get-PowerSavingProperty
    if ($p) { return $p.DisplayValue }
    return '(驱动未报告)'
}

function Convert-PrefixToMask([int]$prefix) {
    if ($prefix -lt 0 -or $prefix -gt 32) { return '' }
    $bits = ('1' * $prefix) + ('0' * (32 - $prefix))
    $octets = for ($i = 0; $i -lt 32; $i += 8) {
        [Convert]::ToInt32($bits.Substring($i, 8), 2)
    }
    return ($octets -join '.')
}

function Get-DefaultGateway {
    $cfg = Get-NetIPConfiguration -InterfaceAlias $script:AdapterName -ErrorAction SilentlyContinue
    if (-not $cfg) { return $null }
    $gw = @($cfg.IPv4DefaultGateway) | Select-Object -First 1
    if ($gw) { return $gw.NextHop }
    return $null
}

function Show-AdapterInfo {
    try {
        $a = Get-NetAdapter -Name $script:AdapterName -ErrorAction Stop
        Write-Host ('   硬件名称 : ' + $a.InterfaceDescription)
        Write-Host ('   驱动版本 : ' + $a.DriverVersion + '  (' + ('{0:yyyy-MM-dd}' -f $a.DriverDate) + ')')
        Write-Host ('   网卡状态 : ' + $a.Status)

        $bands = @(Get-NetAdapterAdvancedProperty -Name $script:AdapterName -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'GHz' } |
            Sort-Object DisplayName |
            ForEach-Object { $_.DisplayName.Substring(0, $_.DisplayName.IndexOf('GHz') + 3) } |
            Select-Object -Unique)
        if ($bands.Count -gt 0) {
            Write-Host ('   支持频段 : ' + ($bands -join '  '))
        } else {
            Write-Host '   支持频段 : (驱动未报告)'
        }

        Write-Host ('   省电模式 : ' + (Get-PowerSavingText))

        $i = @(netsh wlan show interfaces 2>$null)
        $ssid = Get-NetshValue $i '^\s*SSID\s*[:：]'
        $band = Get-NetshValue $i 'GHz'
        $type = Get-NetshValue $i '802\.11'
        $sig  = Get-NetshValue $i '\d+%'
        $rssi = Get-NetshValue $i '\bRssi\b'

        $sigText = ''
        if ($sig -and $rssi) { $sigText = '信号 ' + $sig + ' (' + $rssi + ' dBm)' }
        elseif ($sig) { $sigText = '信号 ' + $sig }
        elseif ($rssi) { $sigText = 'RSSI ' + $rssi + ' dBm' }

        $parts = @($ssid, $band, $type, $sigText) | Where-Object { $_ }
        if (@($parts).Count -gt 0) {
            Write-Host ('   当前连接 : ' + ($parts -join ', '))
        } else {
            Write-Host '   当前连接 : (未连接或无 WLAN 服务)'
        }
    } catch {
        Write-Host ('   读取网卡信息失败: ' + $_.Exception.Message)
    }
}

function Show-NetworkInfo {
    try {
        $cfg = Get-NetIPConfiguration -InterfaceAlias $script:AdapterName -ErrorAction Stop
    } catch {
        Write-Host ('   读取网络配置失败: ' + $_.Exception.Message)
        return $null
    }

    $ipObj = @($cfg.IPv4Address) | Select-Object -First 1
    $gwObj = @($cfg.IPv4DefaultGateway) | Select-Object -First 1
    $dns = @($cfg.DNSServer |
        Where-Object { $_.AddressFamily -eq 2 } |
        ForEach-Object { $_.ServerAddresses } |
        Select-Object -Unique)
    $wmi = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex=$($cfg.InterfaceIndex)" -ErrorAction SilentlyContinue) |
        Select-Object -First 1

    $desc = if ($cfg.InterfaceDescription) { $cfg.InterfaceDescription }
            elseif ($cfg.NetAdapter) { $cfg.NetAdapter.InterfaceDescription }
            else { '(未知)' }
    $mac = if ($cfg.NetAdapter) { $cfg.NetAdapter.MacAddress } else { '(未知)' }

    Write-Host ('   主机名    : ' + $env:COMPUTERNAME)
    Write-Host ('   描述      : ' + $desc)
    Write-Host ('   物理地址  : ' + $mac)

    if ($ipObj) {
        $mask = Convert-PrefixToMask ([int]$ipObj.PrefixLength)
        Write-Host ('   IPv4 地址 : ' + $ipObj.IPAddress + '  /  ' + $mask + ' (/' + $ipObj.PrefixLength + ')')
    } else {
        Write-Host '   IPv4 地址 : (未获取到)'
    }

    if ($gwObj) {
        Write-Host ('   默认网关  : ' + $gwObj.NextHop + '   (丢包测试目标)')
    } else {
        Write-Host '   默认网关  : (未获取到)'
    }

    if ($wmi) {
        $dhcpText = if ($wmi.DHCPEnabled) { '已启用' } else { '已禁用' }
        $srvText = if ($wmi.DHCPServer) { '  (服务器 ' + $wmi.DHCPServer + ')' } else { '' }
        Write-Host ('   DHCP      : ' + $dhcpText + $srvText)
        if ($wmi.DHCPLeaseObtained -and $wmi.DHCPLeaseExpires) {
            $leaseStart = '{0:yyyy-MM-dd HH:mm:ss}' -f $wmi.DHCPLeaseObtained
            $leaseEnd = '{0:yyyy-MM-dd HH:mm:ss}' -f $wmi.DHCPLeaseExpires
            Write-Host ('   租约      : ' + $leaseStart + '  ~  ' + $leaseEnd)
        }
    } else {
        Write-Host '   DHCP      : (读取失败)'
    }

    if ($dns.Count -gt 0) {
        Write-Host ('   DNS服务器 : ' + ($dns -join ', '))
    } else {
        Write-Host '   DNS服务器 : (未获取到 IPv4 DNS)'
    }

    if ($gwObj) { return $gwObj.NextHop }
    return $null
}

function Test-Loss([string]$target) {
    if (-not $target) {
        Write-Host '   (无测试目标, 跳过)'
        return [pscustomobject]@{ Sent = 0; Received = 0; Loss = 0; Avg = $null; Max = $null; Jitter = $null }
    }

    $ping = [System.Net.NetworkInformation.Ping]::new()
    $times = [System.Collections.Generic.List[int]]::new()
    $sent = $script:PingCount
    try {
        for ($i = 0; $i -lt $sent; $i++) {
            try {
                $reply = $ping.Send($target, 1000)
                if ($reply.Status -eq 'Success') { $times.Add([int]$reply.RoundtripTime) }
            } catch { }
            if ($i -lt $sent - 1 -and $script:PingIntervalMs -gt 0) {
                Start-Sleep -Milliseconds $script:PingIntervalMs
            }
        }
    } finally {
        $ping.Dispose()
    }

    $received = $times.Count
    $loss = $sent - $received
    $avg = $null
    $max = $null
    $jitter = $null
    if ($received -gt 0) {
        $stats = $times | Measure-Object -Average -Maximum -Minimum
        $avg = [math]::Round($stats.Average)
        $max = $stats.Maximum
        $jitter = $stats.Maximum - $stats.Minimum
    }

    Write-Host ('   丢包 : {0}/{1}' -f $loss, $sent)
    if ($null -ne $avg) {
        Write-Host ('   RTT  : 平均 {0} ms, 最大 {1} ms, 波动 {2} ms' -f $avg, $max, $jitter)
    }

    return [pscustomobject]@{
        Sent = $sent
        Received = $received
        Loss = $loss
        Avg = $avg
        Max = $max
        Jitter = $jitter
    }
}

function Test-Site([string]$site) {
    $dnsOk = $false
    $tcpOk = $false
    $ms = $null
    $ip = $null

    try {
        $records = @(Resolve-DnsName -Name $site -Type A -DnsOnly -QuickTimeout -ErrorAction Stop)
        $ip = $records | Where-Object { $_.IPAddress } | Select-Object -First 1 -ExpandProperty IPAddress
        $dnsOk = [bool]$ip
    } catch {
        $dnsOk = $false
    }

    if ($dnsOk) {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $tcpOk = $tcp.ConnectAsync($ip, 443).Wait(1500) -and $tcp.Connected
            if ($tcpOk) { $ms = $sw.ElapsedMilliseconds }
        } catch {
            $tcpOk = $false
        } finally {
            $sw.Stop()
            $tcp.Dispose()
        }
    }

    return [pscustomobject]@{
        Site = $site
        IP = $ip
        Dns = $dnsOk
        Tcp = $tcpOk
        Ms = $ms
    }
}

function Test-Sites {
    Write-Host ('   网站连通性 (DNS + TCP 443, {0} 个网站):' -f $script:Sites.Count)
    Write-Host '   网站               IPv4              DNS      443       耗时'
    $results = foreach ($s in $script:Sites) { Test-Site $s }

    foreach ($r in $results) {
        $ipText = if ($r.IP) { $r.IP } else { '-' }
        $dnsText = if ($r.Dns) { 'DNS OK' } else { 'DNS 失败' }
        $tcpText = if ($r.Tcp) { '443 OK' } else { '443 失败' }
        $msText = if ($null -ne $r.Ms) { ('{0} ms' -f $r.Ms) } else { '-' }
        Write-Host ('   {0,-18} {1,-16} {2,-8} {3,-9} {4}' -f $r.Site, $ipText, $dnsText, $tcpText, $msText)
    }

    $ok = @($results | Where-Object { $_.Tcp }).Count
    $dnsFail = @($results | Where-Object { -not $_.Dns }).Count
    $tcpFail = @($results | Where-Object { $_.Dns -and -not $_.Tcp }).Count
    Write-Host ('   汇总 : {0}/{1} 网站可达' -f $ok, $script:Sites.Count)

    return [pscustomobject]@{
        Total = $script:Sites.Count
        Ok = $ok
        Fail = $script:Sites.Count - $ok
        DnsFail = $dnsFail
        TcpFail = $tcpFail
        Results = $results
    }
}

function Show-SiteHint([int]$loss, [object]$sites) {
    if ($loss -eq 0 -and $sites.Fail -gt 0) {
        Write-Host ''
        Write-Host ('   [i] 注意: 网关 0 丢包, 但有 ' + $sites.Fail + ' 个网站不可达。这不是网卡丢包, 可能原因:')
        if ($sites.DnsFail -gt 0) {
            Write-Host '       - DNS 解析失败, 可尝试公共 DNS 如 223.5.5.5'
        }
        if ($sites.TcpFail -gt 0) {
            Write-Host '       - 目标 443 端口被拦截或网站不可达'
        }
        Write-Host '       - 运营商骨干网局部异常'
        Write-Host '       - 本机安全软件或代理设置拦截'
    }
}

function Toggle-PowerSaving {
    $p = Get-PowerSavingProperty
    if (-not $p) {
        Write-Host '   未找到省电模式属性, 此驱动可能不支持, 已跳过。'
        return
    }

    $current = $p.DisplayValue
    $values = @($p.ValidDisplayValues)
    if ($values.Count -lt 2) {
        Write-Host ('   该属性只有取值 "' + $current + '", 无法切换。')
        return
    }

    $disabled = $values | Where-Object { $_ -match '已禁用|禁用|Disabled|Off' } | Select-Object -First 1
    if ($disabled -and $current -ne $disabled) {
        $target = $disabled
    } else {
        $target = $values | Where-Object { $_ -ne $current } | Select-Object -First 1
    }

    if (-not $target) {
        Write-Host '   找不到可切换的目标值。'
        return
    }

    if ($script:DryRun) {
        Write-Host ('   [DryRun] 将切换省电模式: ' + $current + ' -> ' + $target)
        return
    }

    try {
        Set-NetAdapterAdvancedProperty -InputObject $p -DisplayValue $target -ErrorAction Stop
        $newValue = (Get-PowerSavingProperty).DisplayValue
        if ($newValue -eq $current) {
            Write-Host '   驱动未接受修改, 当前值未变化。'
        } else {
            Write-Host ('   已切换: ' + $current + ' -> ' + $newValue)
            $script:Toggled = $true
            $script:PowerChange = $current + ' -> ' + $newValue
        }
    } catch {
        Write-Host ('   切换失败: ' + $_.Exception.Message)
    }
}

function Wait-Reconnect {
    Write-Host '   等待网卡重连并拿到可用网关 (最多 45 秒)...'
    $start = Get-Date
    $deadline = $start.AddSeconds(45)
    $lastStatus = ''
    $ping = [System.Net.NetworkInformation.Ping]::new()

    try {
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $adapter = Get-NetAdapter -Name $script:AdapterName -ErrorAction SilentlyContinue
            $status = if ($adapter) { [string]$adapter.Status } else { '(未找到)' }
            $gw = Get-DefaultGateway
            $pingOk = $false
            if ($gw) {
                try { $pingOk = $ping.Send($gw, 800).Status -eq 'Success' } catch { }
            }
            $elapsed = ((Get-Date) - $start).TotalSeconds

            if ($status -eq 'Up' -and $gw -and $pingOk -and $elapsed -ge 6) {
                Write-Host ('   已重连: 网卡 Up, 网关 ' + $gw + ' 可达。')
                return $true
            }

            if ($status -ne $lastStatus) {
                $gwText = if ($gw) { '网关 ' + $gw } else { '网关未就绪' }
                Write-Host ('   状态: 网卡 ' + $status + ', ' + $gwText)
                $lastStatus = $status
            }
        }
    } finally {
        $ping.Dispose()
    }

    Write-Host '   × 等待超时: 网卡或网关仍不可用, 复测结果可能不准确。'
    return $false
}

function Show-Summary([object]$beforeLoss, [object]$beforeSites, [object]$afterLoss, [object]$afterSites, [bool]$connected) {
    Write-Host ''
    Write-Host ' ------------------------------------------------'
    Write-Host '   结果汇总'
    Write-Host ' ------------------------------------------------'
    Write-Host ('   网关丢包 : ' + $beforeLoss.Loss + '/' + $beforeLoss.Sent + '  ->  ' + $afterLoss.Loss + '/' + $afterLoss.Sent)
    Write-Host ('   网站可达 : ' + $beforeSites.Ok + '/' + $beforeSites.Total + '  ->  ' + $afterSites.Ok + '/' + $afterSites.Total)
    if ($script:PowerChange) {
        Write-Host ('   省电模式 : ' + $script:PowerChange)
    }

    $beforeBad = ($beforeLoss.Loss -gt 0 -or $beforeSites.Fail -gt 0)

    if ($afterLoss.Loss -eq 0 -and $afterSites.Fail -eq 0) {
        if ($beforeBad) {
            Write-Host '   结论     : 重启网卡后恢复正常 (0 丢包, 网站全部可达)。'
        } else {
            Write-Host '   结论     : 检测正常, 重启前后均无明显异常。'
        }
    } elseif (-not $connected) {
        Write-Host '   结论     : 网络未完全恢复, 建议检查 Wi-Fi 连接或路由器后重试。'
    } elseif ($afterLoss.Loss -gt 0) {
        Write-Host '   结论     : 仍有丢包, 重启网卡没有解决。'
        Write-Host '              建议用 PingPlotter / Wireshark 进一步定位, 或联系运营商。'
    } else {
        Write-Host '   结论     : 网关 0 丢包, 但仍有网站不可达, 更像 DNS / 代理 / 网站侧问题。'
    }
}

function Main {
    Start-Log

    Write-Host ''
    Write-Host ' ================================================'
    Write-Host '            网 卡 重 启 小 工 具  v3.0'
    Write-Host '   丢包检测 / 网站连通 / 网卡重启 / 省电切换'
    Write-Host ' ================================================'
    $modeText = if ($script:DryRun) { '   [DryRun 演练模式]' } else { '' }
    Write-Host ('   网卡: ' + $script:AdapterName + $modeText)

    Show-Step 1 '网卡信息'
    Show-AdapterInfo
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 2 '当前网络信息'
    $router = Show-NetworkInfo
    if (-not $router) {
        Write-Host '   × 无法确定默认网关, 丢包测试无法进行。'
        $script:ExitCode = 1
        return
    }
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 3 ('丢包测试 - 前 (目标 ' + $router + ')')
    $beforeLoss = Test-Loss $router
    if ($beforeLoss.Loss -eq 0) {
        Write-Host '      √ 结论: 链路正常, 本次也许不用重启。'
    } else {
        Write-Host '      × 结论: 链路异常, 建议重启网卡。'
    }
    Write-Host ''
    $beforeSites = Test-Sites
    Show-SiteHint ($beforeLoss.Loss) $beforeSites
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 4 '省电模式切换 (可选)'
    $p = Get-PowerSavingProperty
    if ($p) {
        Write-Host ('   当前值 : ' + $p.DisplayValue)
        $vals = @($p.ValidDisplayValues)
        if ($vals.Count -gt 0) {
            Write-Host ('   可选值 : ' + ($vals -join '  |  '))
        }
    } else {
        Write-Host '   当前驱动未报告省电模式属性。'
    }
    Write-Host '   日常推荐禁用省电; 部分驱动在省电模式下会丢包。'
    if (Ask '   >> 切换? (y=切换, 回车或N=保持现状)') {
        Toggle-PowerSaving
    }
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 5 ('重启网卡 ' + $script:AdapterName)
    Write-Host '   WiFi 会闪断几秒后自动重连。'
    if ($script:DryRun) {
        Write-Host '   [DryRun] 跳过重启网卡, 不执行第 6/7 步。'
        Write-Host ''
        Write-Host ('   [DryRun] 演练结束: 丢包 ' + $beforeLoss.Loss + '/' + $beforeLoss.Sent +
                    ', 网站 ' + $beforeSites.Ok + '/' + $beforeSites.Total + ' 可达; 未修改任何设置。')
        return
    }
    if (-not (Ask '   >> 确定重启? (y=重启, 回车或N=退出)')) { return }

    try {
        Restart-NetAdapter -Name $script:AdapterName -ErrorAction Stop
        Write-Host '   网卡重启命令已执行'
        $script:Restarted = $true
    } catch {
        Write-Host ('   重启失败: ' + $_.Exception.Message)
        $script:ExitCode = 1
        return
    }

    Show-Step 6 '等待 WiFi 重连'
    $connected = Wait-Reconnect

    $newRouter = Get-DefaultGateway
    if ($newRouter -and $newRouter -ne $router) {
        Write-Host ('   网关已变化: ' + $router + ' -> ' + $newRouter)
        $router = $newRouter
    } elseif (-not $newRouter) {
        Write-Host '   × 重启后仍未获取到默认网关, 沿用旧目标复测。'
    }

    Show-Step 7 ('丢包测试 - 后 (目标 ' + $router + ')')
    $afterLoss = Test-Loss $router
    if ($afterLoss.Loss -eq 0) {
        Write-Host '      √ 结论: 0 丢包。'
    } else {
        Write-Host '      × 结论: 仍有丢包。'
        Write-Host '        建议用 PingPlotter / Wireshark 进一步定位, 或联系运营商。'
    }
    Write-Host ''
    $afterSites = Test-Sites
    Show-SiteHint ($afterLoss.Loss) $afterSites

    Show-Summary $beforeLoss $beforeSites $afterLoss $afterSites $connected

    if ($afterLoss.Loss -gt 0 -or $afterSites.Fail -gt 0) {
        $script:ExitCode = 1
    }
}

# ---------- 主流程 ----------
try {
    Main
} catch {
    Write-Host ''
    Write-Host ('   × 发生未处理的错误: ' + $_.Exception.Message)
    $script:ExitCode = 1
}

Write-Host ''
if ($script:Toggled -and -not $script:Restarted) {
    Write-Host ' [i] 省电模式已修改但尚未生效, 下次重启网卡后生效。'
}

if ($script:TranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
}
if ($script:LogPath) {
    Write-Host (' [i] 本次日志: ' + $script:LogPath)
}

Write-Host ''
Write-Host ' ------------------------------------------------'
Read-Host '   按 Enter 键退出'
exit $script:ExitCode
