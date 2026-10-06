# RestartWLAN v2.0 - 网卡重启小工具 (PowerShell 版, 自 cmd 批处理迁移)
# 启动: 双击 RestartWLAN.bat, 或
#   powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
# 测试开关: -NoElevate 跳过自提权检查(仅用于免提权演练)
param([switch]$NoElevate)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
$Host.UI.RawUI.WindowTitle = '网卡重启小工具 v2.0'
$Sites = 'www.baidu.com','www.bilibili.com','www.qq.com','www.taobao.com',
         'www.163.com','www.jd.com','www.aliyun.com','www.douyin.com'
$script:Toggled = $false
$script:Restarted = $false

# ---------- 自提权 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Write-Host '本工具需要管理员权限, 请在弹出的窗口中点击"是"。'
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
    exit
}

function Show-Step([int]$n, [string]$title) {
    Write-Host ''
    Write-Host ' ------------------------------------------------'
    Write-Host ('  [{0}/7] {1}' -f $n, $title)
    Write-Host ' ------------------------------------------------'
}

function Ask([string]$prompt) {
    (Read-Host $prompt) -eq 'y'
}

function Show-AdapterInfo {
    try {
        $a = Get-NetAdapter -Name WLAN -ErrorAction Stop
        Write-Host ('   硬件名称 : ' + $a.InterfaceDescription)
        Write-Host ('   驱动版本 : ' + $a.DriverVersion + '  (' + ('{0:yyyy-MM-dd}' -f $a.DriverDate) + ')')
        $bands = @(Get-NetAdapterAdvancedProperty -Name WLAN -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'GHz' } |
            Sort-Object DisplayName |
            ForEach-Object { $_.DisplayName.Substring(0, $_.DisplayName.IndexOf('GHz') + 3) })
        Write-Host ('   支持频段 : ' + ($bands -join '  '))
        $i = @(netsh wlan show interfaces)
        $ssid = (($i | Select-String '^\s*SSID' | Select-Object -First 1).Line) -replace '.*: *', ''
        if (-not $ssid) { $ssid = '(未连接)' }
        $band = (($i | Select-String 'GHz'     | Select-Object -First 1).Line) -replace '.*: *', ''
        $type = (($i | Select-String '802\.11' | Select-Object -First 1).Line) -replace '.*: *', ''
        $sig  = (($i | Select-String '%'       | Select-Object -First 1).Line) -replace '.*: *', ''
        $rssi = (($i | Select-String 'Rssi'    | Select-Object -First 1).Line) -replace '.*: *', ''
        Write-Host ('   当前连接 : ' + $ssid + ', ' + $band + ', ' + $type + ', 信号 ' + $sig + ' (' + $rssi + ' dBm)')
    } catch {
        Write-Host ('   读取网卡信息失败: ' + $_.Exception.Message)
    }
}

function Get-V4([object]$val) {
    # 从字符串或数组中筛出纯 IPv4 地址, 去重
    @($val) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -Unique
}

function Get-NetConfig {
    # 运行 ipconfig /all, 解析「无线局域网适配器 WLAN」节为哈希表
    $out = @(ipconfig /all)
    $start = -1
    for ($k = 0; $k -lt $out.Count; $k++) {
        if ($out[$k] -match '^无线局域网适配器 WLAN:') { $start = $k; break }
    }
    $result = @{}
    if ($start -lt 0) { return $result }
    $lastKey = ''
    for ($k = $start + 1; $k -lt $out.Count; $k++) {
        if ($out[$k] -match '^\S') { break }   # 下一节标题(顶格)
        $ln = $out[$k]
        if ($ln -match '^\s{2,}(.+?)\s*(?:\.\s*)+:\s*(.*)$') {
            $key = $Matches[1].Trim()
            $val = ($Matches[2].Trim() -replace '\(首选\)', '') -replace '\(过期\)', ''
            if ($result.ContainsKey($key)) { $result[$key] = @($result[$key]) + $val }
            else { $result[$key] = @($val) }
            $lastKey = $key
        } elseif ($lastKey -and $ln -match '^\s{20,}(\S.*?)\s*$') {
            $val = ($Matches[1] -replace '\(首选\)', '') -replace '\(过期\)', ''
            $result[$lastKey] = @($result[$lastKey]) + $val
        }
    }
    return $result
}

function Show-NetworkInfo {
    # 显示整理后的网络信息; 返回检测到的默认网关(仅此一个返回值)
    $c = Get-NetConfig
    if ($c.Count -eq 0) {
        Write-Host '   解析 ipconfig /all 失败, 无法获取网络信息。'
        return $null
    }
    $hostn = (@(ipconfig /all) | Select-String '主机名' | Select-Object -First 1).Line -replace '.*:\s*', ''
    Write-Host ('   主机名    : ' + $hostn)
    Write-Host ('   描述      : ' + @($c['描述'])[0])
    Write-Host ('   物理地址  : ' + @($c['物理地址'])[0])
    $ip   = Get-V4 $c['IPv4 地址'] | Select-Object -First 1
    $mask = @($c['子网掩码'])[0]
    Write-Host ('   IPv4 地址 : ' + $ip + '  /  ' + $mask)
    $gw = Get-V4 $c['默认网关'] | Select-Object -First 1
    Write-Host ('   默认网关  : ' + $gw + '   (丢包测试目标)')
    $dhcpSrv = Get-V4 $c['DHCP 服务器'] | Select-Object -First 1
    Write-Host ('   DHCP      : ' + @($c['DHCP 已启用'])[0] + $(if ($dhcpSrv) { '  (服务器 ' + $dhcpSrv + ')' }))
    $dns = Get-V4 $c['DNS 服务器'] -join ', '
    Write-Host ('   DNS服务器 : ' + $(if ($dns) { $dns } else { '(未获取到 IPv4 DNS)' }))
    $lease1 = @($c['获得租约的时间'])[0]
    $lease2 = @($c['租约过期的时间'])[0]
    if ($lease1) { Write-Host ('   租约      : ' + $lease1 + '  ~  ' + $lease2) }
    return $gw
}

function Test-Loss([string]$router) {
    $r = @(Test-Connection -ComputerName $router -Count 20 -ErrorAction SilentlyContinue)
    Write-Host ('   丢包 : ' + (20 - $r.Count) + '/20')
    if ($r.Count -eq 20) { return 0 } else { return 1 }
}

function Test-Sites([int]$lossFlag) {
    $fail = 0
    foreach ($s in $Sites) {
        $r = @(Test-Connection -ComputerName $s -Count 4 -ErrorAction SilentlyContinue)
        if ($r.Count -gt 0) {
            $avg = [math]::Round(($r | Measure-Object -Property ResponseTime -Average).Average)
            Write-Host ('   {0,-18} {1}/4 通, 平均 {2} ms' -f $s, $r.Count, $avg)
        } else {
            $fail++
            Write-Host ('   {0,-18} 0/4 通 (超时或域名解析失败)' -f $s)
        }
    }
    if ($lossFlag -eq 0 -and $fail -gt 0) {
        Write-Host ''
        Write-Host ('   [i] 注意: 链路 0 丢包, 但有 ' + $fail + ' 个网站不通。这不是网卡丢包, 可能原因:')
        Write-Host '       - DNS 解析失败, 最常见, 可尝试公共 DNS 如 223.5.5.5'
        Write-Host '       - 目标网站禁用 ping 或防火墙拦截 ICMP'
        Write-Host '       - 运营商骨干网局部异常'
        Write-Host '       - 本机安全软件拦截'
    }
}

function Toggle-PowerSaving {
    try {
        $d = (Get-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -ErrorAction Stop).DisplayValue
        if ($d -eq '已禁用') {
            Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue 'Auto' -ErrorAction Stop
            Write-Host '   已切换: 已禁用 -> Auto'
        } else {
            Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue '已禁用' -ErrorAction Stop
            Write-Host '   已切换: Auto -> 已禁用'
        }
        $script:Toggled = $true
    } catch {
        Write-Host ('   切换失败: ' + $_.Exception.Message)
    }
}

function Wait-Reconnect {
    $i = 0
    while (((Get-NetAdapter -Name WLAN -ErrorAction SilentlyContinue).Status -ne 'Up') -and ($i -lt 15)) {
        Start-Sleep -Seconds 2; $i++
    }
    Start-Sleep -Seconds 3
    Write-Host ('   当前状态: ' + (Get-NetAdapter -Name WLAN -ErrorAction SilentlyContinue).Status)
}

function Main {
    Write-Host ''
    Write-Host ' ================================================'
    Write-Host '            网 卡 重 启 小 工 具  v2.0'
    Write-Host '   丢包检测 / 网站连通 / 网卡重启 / 省电切换'
    Write-Host ' ================================================'

    Show-Step 1 '网卡信息'
    Show-AdapterInfo
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 2 '当前网络信息 (来自 ipconfig /all)'
    $Router = Show-NetworkInfo
    if (-not $Router) {
        Write-Host '   × 无法确定默认网关, 丢包测试无法进行。'
        return
    }
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 3 ('丢包测试 - 前 (目标 ' + $Router + ')')
    $loss = Test-Loss $Router
    if ($loss -eq 1) { Write-Host '      × 结论: 链路异常, 建议重启网卡。' }
    else { Write-Host '      √ 结论: 链路正常, 本次也许不用重启。' }
    Write-Host ''
    Write-Host '   国内网站连通性 (8 个网站, 各 4 个包, 汇总如下):'
    Test-Sites $loss
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 4 '省电模式切换 (可选)'
    Write-Host '   当前值见第 1 步输出。两种模式说明:'
    Write-Host '      已禁用 : 日常推荐, 本机实测 0 丢包'
    Write-Host '      Auto   : 已知会丢包, 仅用于验证系统更新是否修复'
    if (Ask '   >> 切换? (y=切换, 回车或N=保持现状)') { Toggle-PowerSaving }
    if (-not (Ask '   >> 继续? (y=继续, 回车或N=退出)')) { return }

    Show-Step 5 '重启网卡 WLAN'
    Write-Host '   WiFi 会闪断几秒后自动重连。'
    if (-not (Ask '   >> 确定重启? (y=重启, 回车或N=退出)')) { return }
    try {
        Restart-NetAdapter -Name WLAN -ErrorAction Stop
        Write-Host '   网卡重启命令已执行'
        $script:Restarted = $true
    } catch {
        Write-Host ('   重启失败: ' + $_.Exception.Message)
        return
    }

    Show-Step 6 '等待 WiFi 重连 (最多 30 秒)'
    Wait-Reconnect

    Show-Step 7 ('丢包测试 - 后 (目标 ' + $Router + ')')
    $loss = Test-Loss $Router
    if ($loss -eq 1) {
        Write-Host '      × 结论: 仍有丢包, 重启网卡没有解决。'
        Write-Host '        建议: 使用专业网络诊断工具, 如 PingPlotter 或 Wireshark;'
        Write-Host '        或联系运营商 / 寻求专业技术支持。'
    } else {
        Write-Host '      √ 结论: 0 丢包, 修复成功。'
    }
    Write-Host ''
    Write-Host '   国内网站连通性 (重启后复测, 8 个网站, 各 4 个包):'
    Test-Sites $loss
}

Main

Write-Host ''
if ($script:Toggled -and -not $script:Restarted) {
    Write-Host ' [i] 省电模式已修改但尚未生效, 下次重启网卡后生效。'
}
Write-Host ''
Write-Host ' ------------------------------------------------'
Read-Host '   按 Enter 键退出'
exit 0
