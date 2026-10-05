@echo off
setlocal EnableDelayedExpansion
title 网卡重启小工具 v1.5
set ROUTER=192.168.0.1
set TOGGLED=0
set RESTARTED=0

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 本工具需要管理员权限, 请在弹出的窗口中点击"是"。
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  ================================================
echo              网 卡 重 启 小 工 具  v1.5
echo        丢包检测  /  网站连通  /  网卡重启  /  省电切换
echo  ================================================

echo.
echo  ------------------------------------------------
echo   [1/6] 网卡信息
echo  ------------------------------------------------
powershell -NoProfile -Command "try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936); $a = Get-NetAdapter -Name WLAN -ErrorAction Stop; '   硬件名称 : ' + $a.InterfaceDescription; '   驱动版本 : ' + $a.DriverVersion + '  (' + ('{0:yyyy-MM-dd}' -f $a.DriverDate) + ')'; $b = @(Get-NetAdapterAdvancedProperty -Name WLAN | Where-Object { $_.DisplayName -match 'GHz' } | Sort-Object DisplayName | ForEach-Object { $_.DisplayName.Substring(0, $_.DisplayName.IndexOf('GHz') + 3) }); '   支持频段 : ' + ($b -join '  '); $i = @(netsh wlan show interfaces); $ssid = (($i | Select-String '^\s*SSID' | Select-Object -First 1).Line -replace '.*: *', ''); if (-not $ssid) { $ssid = '(未连接)' }; $band = (($i | Select-String 'GHz' | Select-Object -First 1).Line -replace '.*: *', ''); $type = (($i | Select-String '802\.11' | Select-Object -First 1).Line -replace '.*: *', ''); $sig = (($i | Select-String '%%' | Select-Object -First 1).Line -replace '.*: *', ''); $rssi = (($i | Select-String 'Rssi' | Select-Object -First 1).Line -replace '.*: *', ''); '   当前连接 : ' + $ssid + ', ' + $band + ', ' + $type + ', 信号 ' + $sig + ' (' + $rssi + ' dBm)' } catch { '   读取网卡信息失败: ' + $_.Exception.Message }"
echo.
set "ANS="
set /p "ANS=   >> 继续? (y=继续, 回车或N=退出): "
if /i not "!ANS!"=="y" goto END

echo.
echo  ------------------------------------------------
echo   [2/6] 丢包测试 - 前
echo  ------------------------------------------------
echo   目标: 路由器 %ROUTER%, 发送 20 个包
set LOSTF=0
call :TESTLOSS
if errorlevel 1 set LOSTF=1
if "!LOSTF!"=="1" (
    echo      × 结论: 链路异常, 建议重启网卡。
) else (
    echo      √ 结论: 链路正常, 本次也许不用重启。
)
echo.
echo   国内网站连通性 (8 个网站, 各 4 个包, 汇总如下):
call :SITETEST !LOSTF!
echo.
set "ANS="
set /p "ANS=   >> 继续? (y=继续, 回车或N=退出): "
if /i not "!ANS!"=="y" goto END

echo.
echo  ------------------------------------------------
echo   [3/6] 省电模式切换 (可选)
echo  ------------------------------------------------
echo   当前值见第 1 步输出。两种模式说明:
echo      已禁用 : 日常推荐, 本机实测 0 丢包
echo      Auto   : 已知会丢包, 仅用于验证系统更新是否修复
set "ANS="
set /p "ANS=   >> 切换? (y=切换, 回车或N=保持现状): "
if /i "!ANS!"=="y" call :TOGGLE
echo.
set "ANS="
set /p "ANS=   >> 继续? (y=继续, 回车或N=退出): "
if /i not "!ANS!"=="y" goto END

echo.
echo  ------------------------------------------------
echo   [4/6] 重启网卡 WLAN
echo  ------------------------------------------------
echo   WiFi 会闪断几秒后自动重连。
set "ANS="
set /p "ANS=   >> 确定重启? (y=重启, 回车或N=退出): "
if /i not "!ANS!"=="y" goto END
powershell -NoProfile -Command "try { Restart-NetAdapter -Name WLAN -ErrorAction Stop; '   网卡重启命令已执行' } catch { '   重启失败: ' + $_.Exception.Message; exit 1 }"
if not errorlevel 1 set RESTARTED=1

echo.
echo  ------------------------------------------------
echo   [5/6] 等待 WiFi 重连 (最多 30 秒)
echo  ------------------------------------------------
powershell -NoProfile -Command "$i = 0; while ((Get-NetAdapter -Name WLAN -ErrorAction SilentlyContinue).Status -ne 'Up' -and $i -lt 15) { Start-Sleep -Seconds 2; $i++ }; Start-Sleep -Seconds 3; '   当前状态: ' + (Get-NetAdapter -Name WLAN -ErrorAction SilentlyContinue).Status"

echo.
echo  ------------------------------------------------
echo   [6/6] 丢包测试 - 后
echo  ------------------------------------------------
echo   目标: 路由器 %ROUTER%, 发送 20 个包
set LOSTF=0
call :TESTLOSS
if errorlevel 1 set LOSTF=1
if "!LOSTF!"=="1" (
    echo      × 结论: 仍有丢包, 重启网卡没有解决。
    echo        建议: 使用专业网络诊断工具, 如 PingPlotter 或 Wireshark;
    echo        或联系运营商 / 寻求专业技术支持。
) else (
    echo      √ 结论: 0 丢包, 修复成功。
)
echo.
echo   国内网站连通性 (重启后复测, 8 个网站, 各 4 个包):
call :SITETEST !LOSTF!
goto END

:TOGGLE
powershell -NoProfile -Command "try { $d = (Get-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -ErrorAction Stop).DisplayValue; if ($d -eq '已禁用') { Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue 'Auto' -ErrorAction Stop; '   已切换: 已禁用 -> Auto' } else { Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue '已禁用' -ErrorAction Stop; '   已切换: Auto -> 已禁用' } } catch { '   切换失败: ' + $_.Exception.Message; exit 1 }"
if not errorlevel 1 set TOGGLED=1
goto :eof

:TESTLOSS
powershell -NoProfile -Command "$r = @(ping -n 20 %ROUTER% | Select-String 'TTL='); if ($r.Count -eq 20) { '   丢包 : 0/20'; exit 0 } else { '   丢包 : ' + (20 - $r.Count) + '/20'; exit 1 }"
goto :eof

:SITETEST
powershell -NoProfile -Command "$loss = %1; $fail = 0; $r = @(); foreach ($s in 'www.baidu.com','www.bilibili.com','www.qq.com','www.taobao.com','www.163.com','www.jd.com','www.aliyun.com','www.douyin.com') { $t = @(ping -n 4 $s | Where-Object { $_ -match 'TTL=' } | ForEach-Object { if ($_ -match '=\s*<*(\d+)\s*ms') { [int]$Matches[1] } }); if ($t.Count -gt 0) { $avg = [math]::Round(($t | Measure-Object -Average).Average); $r += ('   {0,-18} {1}/4 通, 平均 {2} ms' -f $s, $t.Count, $avg) } else { $fail++; $r += ('   {0,-18} 0/4 通 (超时或域名解析失败)' -f $s) } }; $r; ''; if (-not $loss -and $fail -gt 0) { '   [i] 注意: 链路 0 丢包, 但有 ' + $fail + ' 个网站不通。这不是网卡丢包, 可能原因:'; '       - DNS 解析失败, 最常见, 可尝试公共 DNS 如 223.5.5.5'; '       - 目标网站禁用 ping 或防火墙拦截 ICMP'; '       - 运营商骨干网局部异常'; '       - 本机安全软件拦截' }"
goto :eof

:END
echo.
if "!TOGGLED!"=="1" if not "!RESTARTED!"=="1" echo  [i] 省电模式已修改但尚未生效, 下次重启网卡后生效。
echo.
echo  ------------------------------------------------
echo   按 Enter 键退出
echo  ------------------------------------------------
set /p "DUMMY="
exit /b 0
