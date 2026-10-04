@echo off
setlocal EnableDelayedExpansion
title 网卡重启小工具 v3
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
echo               网 卡 重 启 小 工 具  v3
echo           丢包检测  /  网卡重启  /  省电切换
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
echo   目标: 路由器 %ROUTER%, 发送 10 个包
call :TESTLOSS
if errorlevel 1 (
    echo      × 结论: 链路异常, 建议重启网卡。
) else (
    echo      √ 结论: 链路正常, 本次也许不用重启。
)
echo.
set "ANS="
set /p "ANS=   >> 继续? (y=继续, 回车或N=退出): "
if /i not "!ANS!"=="y" goto END

echo.
echo  ------------------------------------------------
echo   [3/6] 省电模式切换 (可选)
echo  ------------------------------------------------
echo   当前值见第 1 步输出。已禁用 = 日常推荐;
echo   Auto = 已知会丢包, 一般只在验证系统更新修复时临时使用。
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
call :TESTLOSS
if errorlevel 1 (
    echo      × 结论: 仍有丢包, 这次没有修好, 请把本窗口截图后找我深入排查。
) else (
    echo      √ 结论: 0 丢包, 修复成功。
)
goto END

:TOGGLE
powershell -NoProfile -Command "try { $d = (Get-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -ErrorAction Stop).DisplayValue; if ($d -eq '已禁用') { Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue 'Auto' -ErrorAction Stop; '   已切换: 已禁用 -> Auto' } else { Set-NetAdapterAdvancedProperty -Name WLAN -DisplayName '省电' -DisplayValue '已禁用' -ErrorAction Stop; '   已切换: Auto -> 已禁用' } } catch { '   切换失败: ' + $_.Exception.Message; exit 1 }"
if not errorlevel 1 set TOGGLED=1
goto :eof

:TESTLOSS
powershell -NoProfile -Command "$r = @(ping -n 10 %ROUTER% | Select-String 'TTL='); if ($r.Count -eq 10) { '   丢包 : 0/10'; exit 0 } else { '   丢包 : ' + (10 - $r.Count) + '/10'; exit 1 }"
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
