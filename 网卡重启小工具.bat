@echo off
title 网卡重启小工具
set ROUTER=192.168.0.1

rem ---- 检查管理员权限,不足则自动提权重启自己 ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 首次运行需要管理员权限,请在弹出的窗口中点击"是"。
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ==============================================
echo              网 卡 重 启 小 工 具
echo ==============================================
echo.
echo [1/5] 当前网卡状态:
powershell -NoProfile -Command "Get-NetAdapter -Name WLAN | Format-Table Name, Status, LinkSpeed -AutoSize"
powershell -NoProfile -Command "Get-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' | Format-Table DisplayName, DisplayValue -AutoSize"
echo.
echo [2/5] 重启前丢包测试 (10 个包发往路由器):
powershell -NoProfile -Command "$r = @(ping -n 10 %ROUTER% | Select-String 'TTL='); if ($r.Count -eq 10) { '      结果: 0/10 丢包,链路正常,本次也许不用重启' } else { '      结果: {0}/10 丢包,链路异常,继续重启' -f (10 - $r.Count) }"
echo.
echo [3/5] 正在重启网卡 WLAN ...
powershell -NoProfile -Command "try { Restart-NetAdapter -Name WLAN -ErrorAction Stop; '      网卡重启命令已执行' } catch { '      [!] 网卡重启失败: ' + $_.Exception.Message }"
echo.
echo [4/5] 等待 WiFi 重连(最多 30 秒)...
powershell -NoProfile -Command "$i = 0; while ((Get-NetAdapter -Name WLAN).Status -ne 'Up' -and $i -lt 15) { Start-Sleep -Seconds 2; $i++ }; Start-Sleep -Seconds 3; '      当前状态: ' + (Get-NetAdapter -Name WLAN).Status"
echo.
echo [5/5] 重启后丢包测试 (10 个包发往路由器):
powershell -NoProfile -Command "$r = @(ping -n 10 %ROUTER% | Select-String 'TTL='); if ($r.Count -eq 10) { '      结果: 0/10 丢包,修复成功!' } else { '      结果: {0}/10 丢包,仍有问题,请找我深入排查' -f (10 - $r.Count) }"
echo.
echo ==============================================
echo   全部完成。按任意键关闭本窗口。
echo ==============================================
pause >nul
