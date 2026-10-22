#requires -Version 5.1
# RestartWLAN v4.0 - 网卡重启小工具 / WLAN restart tool
# 启动 / Launch: 双击 RestartWLAN.bat, 或 / or
#   powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
# 参数 / Parameters:
#   -Adapter <名称>        指定网卡, 默认 WLAN; 默认名不存在时自动识别无线网卡
#   -PingCount <次数>      丢包测试包数, 默认 20
#   -PingIntervalMs <毫秒> 丢包测试间隔, 默认 500
#   -Lang auto|zh|en       界面语言, 默认跟随 Windows 显示语言
#   -Yes                   自动选择推荐动作, 不询问
#   -NoPause               跳过结尾 Enter
#   -DryRun                只读演练: 不修改省电模式, 不重启网卡
#   -NoLog                 不写日志
#   -NoExitSession         在已有 PowerShell 会话中运行时不关闭会话
#   -Log                   即使在 DryRun 下也写日志
#   -SiteTimeoutMs <毫秒>  单个网站 TCP 超时, 默认 3000
#   -ReconnectTimeoutSec   重连等待秒数, 默认 45
#   -NoElevate             跳过自提权; 非管理员时自动进入只读模式
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Adapter = 'WLAN',
    [ValidateRange(1, 200)][int]$PingCount = 20,
    [ValidateRange(10, 5000)][int]$PingIntervalMs = 500,
    [Alias('Language')]
    [ValidateSet('auto', 'zh', 'en')]
    [string]$Lang = 'auto',
    [switch]$Yes,
    [switch]$NoPause,
    [switch]$DryRun,
    [switch]$NoLog,
    [switch]$NoExitSession,
    [switch]$Log,
    [ValidateRange(500, 15000)][int]$SiteTimeoutMs = 3000,
    [ValidateRange(10, 300)][int]$ReconnectTimeoutSec = 45,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Continue'
$script:OriginalOutputEncoding = $null
try {
    $script:OriginalOutputEncoding = [Console]::OutputEncoding
    $oemCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding($oemCodePage)
} catch { }
$script:Version = '4.0'
$script:TotalSections = 6
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

# ---------- 语言表 / Language tables ----------
$script:LangData = @{
    zh = @{
        Common_AppTitle            = '网卡重启小工具 v{0}'
        Common_BannerTitle         = '            网 卡 重 启 小 工 具  v{0}'
        Common_BannerSub           = '   丢包检测 / 网站连通 / 网卡重启 / 省电切换'
        Common_BannerAdapter       = '   网卡: {0}{1}'
        Common_BadgeDryRun         = '   [DryRun 演练模式]'
        Common_BadgeReadOnly       = '   (只读模式: 未提权)'
        Common_PromptExit          = '   按 Enter 键退出'
        Common_UnhandledError      = '   × 发生未处理的错误: {0}'

        Error_NonInteractive       = '非交互环境且未指定 -Yes 或 -DryRun, 已退出。'
        Error_AdminRequired        = '该操作需要管理员权限, 请用 RestartWLAN.bat 或管理员 PowerShell 运行。'
        ReadOnly_Notice            = '当前未提权: 只执行诊断, 不会修改省电模式或重启网卡。修改请用 RestartWLAN.bat 或管理员 PowerShell。'

        Err_AdapterMultiple        = '网卡名 "{0}" 匹配到多块网卡, 请用 -Adapter 写完整名称:'
        Err_AdapterNotFound        = '找不到指定网卡: {0}'
        Err_NoWlan                 = '找不到无线网卡, 无法继续。'
        Err_MultipleWlan           = '检测到多块无线网卡, 请用 -Adapter 指定:'
        Elevate_NeedAdmin          = '本工具需要管理员权限, 请在弹出的 UAC 窗口中确认。'
        Elevate_Failed             = '提权失败或已取消: {0}'
        Elevate_NoExitCode         = '提权进程已结束, 但无法读取退出码。'

        Section_Adapter            = '网卡信息'
        Section_Network            = '当前网络信息'
        Section_Test               = '连通性测试 (前)'
        Section_Action             = '选择操作'
        Section_Wait               = '等待 WiFi 重连'
        Section_After              = '连通性测试 (后) 与汇总'

        Adapter_Hardware           = '   硬件名称 : {0}'
        Adapter_Driver             = '   驱动版本 : {0}  ({1})'
        Adapter_Status             = '   网卡状态 : {0}'
        Adapter_Bands              = '   支持频段 : {0}'
        Adapter_Power              = '   省电模式 : {0}'
        Adapter_Connection         = '   当前连接 : {0}'
        Adapter_NotReported        = '(驱动未报告)'
        Adapter_NoConnection       = '(未连接或无 WLAN 服务)'
        Adapter_ReadFailed         = '   读取网卡信息失败: {0}'
        Adapter_NotWlan            = '   提示: 所选适配器不是无线网卡, 已跳过 SSID/信号/省电相关检测。'
        Adapter_Signal             = '信号 {0} ({1} dBm)'
        Adapter_SignalOnly         = '信号 {0}'
        Adapter_RssiOnly           = 'RSSI {0} dBm'

        Status_Up                  = '已连接'
        Status_Disconnected        = '未连接'
        Status_Disabled            = '已禁用'
        Status_Missing             = '(网卡未找到)'
        Status_Unknown             = '未知'

        Power_Disabled             = '已禁用'
        Power_Enabled              = '已启用'
        Power_Auto                 = 'Auto'
        Power_Unknown              = '(未知)'
        Power_NoProperty           = '(驱动未报告省电属性)'

        Net_Hostname               = '   主机名    : {0}'
        Net_Description            = '   描述      : {0}'
        Net_Mac                    = '   物理地址  : {0}'
        Net_IPv4                   = '   IPv4 地址 : {0}  /  {1} (/{2})'
        Net_IPv4None               = '   IPv4 地址 : (未获取到)'
        Net_Gateway                = '   默认网关  : {0}   (丢包测试目标)'
        Net_GatewayV6              = '   默认网关  : {0} (IPv6)'
        Net_GatewayNone            = '   默认网关  : (未获取到)'
        Net_Dhcp                   = '   DHCP      : {0}{1}'
        Net_DhcpEnabled            = '已启用'
        Net_DhcpDisabled           = '已禁用'
        Net_DhcpServer             = '  (服务器 {0})'
        Net_Lease                  = '   租约      : {0}  ~  {1}'
        Net_Dns                    = '   DNS服务器 : {0}'
        Net_DnsNone                = '   DNS服务器 : (未获取到 IPv4 DNS)'
        Net_ReadFailed             = '   读取网络配置失败: {0}'
        Net_NoConfigData           = '未返回网络配置数据'
        Net_Unknown                = '(未知)'
        Net_NoGatewayWarn          = '   × 未获取到默认网关; 跳过网关丢包测试, 网站测试仍会执行。'
        Net_DefaultRouteOther      = '   ! 默认路由当前走 "{0}", 不是所选网卡; 网站/丢包测试可能不代表该网卡。'

        Loss_Heading               = '   网关丢包 ({0}, {1} 包, 间隔 {2} ms):'
        Loss_NoTarget              = '   (无网关目标, 跳过丢包测试)'
        Loss_Line                  = '   丢包 : {0}/{1}'
        Loss_Rtt                   = '   RTT  : 平均 {0} ms, 最大 {1} ms, 波动 {2} ms'
        Loss_Normal                = '      √ 链路正常 (0 丢包)。'
        Loss_Lossy                 = '      × 链路有丢包; 建议处理。'
        Loss_MaybeIcmp             = '      [i] 网关 100% 不响应 ICMP; 结合网站测试, 这不一定是网卡丢包。'
        Loss_AfterOk               = '      √ 复测 0 丢包。'
        Loss_SkippedIcmp           = '   (网关 ICMP 被拦截, 跳过丢包复测)'

        Site_Heading               = '   网站连通性 (DNS + TCP 443, {0} 个网站):'
        Site_Summary               = '   汇总 : {0}/{1} 网站可达'
        Site_HintHead              = '   [i] 注意: 网关 0 丢包, 但有 {0} 个网站不可达。这可能不是网卡丢包, 常见原因:'
        Site_HintDns               = '       - DNS 解析失败, 可尝试公共 DNS 如 223.5.5.5'
        Site_HintTcp               = '       - 目标 443 端口被拦截或网站不可达'
        Site_HintNetwork           = '       - 运营商骨干网局部异常'
        Site_HintLocal             = '       - 本机安全软件或代理设置拦截'
        Site_HintIcmp              = '   [i] 网关不响应 ICMP, 但 {0}/{1} 网站可达; 更像路由器禁 ping, 不是网卡故障。'
        Site_HintNoLoss            = '   [i] 未测到网关丢包, 但有 {0} 个网站不可达; 请检查 DNS/代理/网络。'

        Power_Current              = '   当前值 : {0}'
        Power_Valid                = '   可选值 : {0}'
        Power_AlreadyDisabled      = '   省电模式已是禁用状态, 无需修改。'
        Power_AlreadyAuto          = '   省电模式已是 Auto, 无需修改。'
        Power_AlreadyEnabled       = '   省电模式已是启用状态, 无需修改。'
        Power_DisablePlan          = '   [DryRun] 将禁用省电: {0} -> {1}'
        Power_AutoPlan             = '   [DryRun] 将恢复 Auto: {0} -> {1}'
        Power_DisableDone          = '   已禁用省电: {0} -> {1}'
        Power_AutoDone             = '   已恢复 Auto: {0} -> {1}'
        Power_NoTarget             = '   找不到合适的省电目标值, 已跳过。'
        Power_NotAccepted          = '   驱动未接受修改, 当前值未变化。'
        Power_VerifyFailed         = '   设置命令已执行, 但暂时无法读取新值。'
        Power_Failed               = '   设置省电模式失败: {0}'
        Power_NeedsRestart         = '   [i] 省电设置已写入, 重启网卡后生效。'
        Power_AutoWarn             = '   警告: Auto 模式可能重新引入丢包, 仅用于对照测试。'

        Menu_Prompt                = '   请选择操作 (回车=N): '
        Menu_DisableRestart        = '     [d] 禁用省电并重启网卡 (推荐)'
        Menu_DisableRestartAlready = '     [d] 重启网卡 (省电已是禁用状态) (推荐)'
        Menu_DisableRestartNoPower = '     [d] 重启网卡 (未找到省电属性) (推荐)'
        Menu_RestartOnly           = '     [r] 仅重启网卡'
        Menu_PowerOnly             = '     [p] 仅处理省电模式'
        Menu_Cancel                = '     [n] 取消'
        Menu_Invalid               = '   无效选项, 请重新输入。'
        Menu_Canceled              = '   已取消, 未做任何修改。'
        Menu_PowerPrompt           = '   选择省电操作 (回车=K): '
        Menu_PowerDisable          = '     [d] 禁用省电 (推荐)'
        Menu_PowerAuto             = '     [a] 恢复 Auto (测试, 可能丢包)'
        Menu_PowerKeep             = '     [k] 保持现状'
        Menu_PowerKept             = '   保持现状, 未做修改。'
        Menu_DryRunRestart         = '   [DryRun] 将重启网卡 {0}, 不执行复测。'
        Menu_DryRunEnd             = '   [DryRun] 演练结束: 未修改任何设置。'

        Wait_Heading               = '   等待网卡重连并拿到可用网关 (最多 {0} 秒)...'
        Wait_GatewayReady          = '网关 {0}'
        Wait_GatewayNotReady       = '网关未就绪'
        Wait_Success               = '   已重连: 网卡 Up, 网关 {0} 可达。'
        Wait_SuccessIcmp           = '   已重连: 网卡 Up, 网关不响应 ICMP, 但外网 TCP 443 可达。'
        Wait_SuccessNoGateway      = '   已重连: 网卡 Up, 外网 TCP 443 可达 (未获取到网关)。'
        Wait_Progress              = '   仍在等待... 已 {0} 秒 (网卡 {1}, {2})'
        Wait_Timeout               = '   × 等待超时: {0}'
        Wait_ReasonAdapter         = '网卡未 Up'
        Wait_ReasonGateway         = '网关未就绪'
        Wait_ReasonNetwork         = '外网不可达'
        Wait_ControlProbe          = '   网关 ping 无响应, 正在用 TCP 443 对照探测...'
        Wait_ControlProbeNoGateway = '   网关未就绪, 正在用 TCP 443 对照探测...'
        Wait_GatewayChanged        = '   网关已变化: {0} -> {1}'

        Restart_Issued             = '   网卡重启命令已执行。'
        Restart_Failed             = '   重启网卡失败: {0}'

        Summary_Title              = '结果汇总'
        Summary_Loss               = '   网关丢包 : {0}  ->  {1}'
        Summary_Sites              = '   网站可达 : {0}/{1}  ->  {2}/{3}'
        Summary_Power              = '   省电模式 : {0}'
        Summary_Conclusion         = '   结论     : {0}'
        Summary_Advice             = '   建议     : {0}'
        Summary_NotMeasured        = '未测'
        Summary_NotMeasuredIcmp    = '未测 (ICMP 被拦截)'
        Summary_IcmpBlocked        = '{0}/{1} (ICMP 被拦截)'
        Con_Healthy                = '检测正常, 重启前后均无明显异常。'
        Con_Fixed                  = '重启网卡后恢复正常 (0 丢包, 网站全部可达)。'
        Con_StillLoss              = '仍有丢包, 重启网卡没有解决。'
        Con_Advice                 = '用 PingPlotter / Wireshark 进一步定位, 或联系运营商。'
        Con_SitesOnly              = '网关 0 丢包, 但仍有网站不可达, 更像 DNS / 代理 / 网站侧问题。'
        Con_IcmpBlocked            = '网关不响应 ICMP, 但网站可达; 未见网卡故障。'
        Con_IcmpSitesFail          = '网关不响应 ICMP, 且网站不可达; 无法仅凭网关判断链路, 建议检查 Wi-Fi/路由器。'
        Con_NoGatewaySitesOk       = '未获取到网关, 未能测量链路丢包; 网站可达。'
        Con_NoGatewaySitesFail     = '未获取到网关, 且网站不可达; 无法判断是否为网卡问题, 建议检查 Wi-Fi/路由器。'
        Con_NotRecovered           = '网络未完全恢复, 建议检查 Wi-Fi 连接或路由器后重试。'

        Log_File                   = ' [i] 本次日志: {0}'
        Log_StartFailed            = ' [i] 无法写入日志, 本次运行不记录日志。'
    }

    en = @{
        Common_AppTitle            = 'RestartWLAN v{0}'
        Common_BannerTitle         = '            RestartWLAN  v{0}'
        Common_BannerSub           = '   Packet loss / Site connectivity / Adapter restart / Power saving'
        Common_BannerAdapter       = '   Adapter: {0}{1}'
        Common_BadgeDryRun         = '   [DryRun mode]'
        Common_BadgeReadOnly       = '   (read-only: not elevated)'
        Common_PromptExit          = '   Press Enter to exit'
        Common_UnhandledError      = '   × Unhandled error: {0}'

        Error_NonInteractive       = 'Non-interactive session without -Yes or -DryRun; exiting.'
        Error_AdminRequired        = 'This action requires administrator rights; run RestartWLAN.bat or an elevated PowerShell.'
        ReadOnly_Notice            = 'Not elevated: diagnostics only; power saving and adapter restart are skipped. Use RestartWLAN.bat or an elevated PowerShell to make changes.'

        Err_AdapterMultiple        = 'Adapter name "{0}" matched multiple adapters; use -Adapter with the full name:'
        Err_AdapterNotFound        = 'Adapter not found: {0}'
        Err_NoWlan                 = 'No wireless adapter found; cannot continue.'
        Err_MultipleWlan           = 'Multiple wireless adapters detected; use -Adapter to choose:'
        Elevate_NeedAdmin          = 'Administrator privileges are required; confirm the UAC prompt.'
        Elevate_Failed             = 'Elevation failed or was canceled: {0}'
        Elevate_NoExitCode         = 'The elevated process exited, but its exit code is unavailable.'

        Section_Adapter            = 'Adapter information'
        Section_Network            = 'Current network information'
        Section_Test               = 'Connectivity test (before)'
        Section_Action             = 'Choose an action'
        Section_Wait               = 'Waiting for Wi-Fi reconnection'
        Section_After              = 'Connectivity test (after) and summary'

        Adapter_Hardware           = '   Hardware         : {0}'
        Adapter_Driver             = '   Driver version   : {0}  ({1})'
        Adapter_Status             = '   Status           : {0}'
        Adapter_Bands              = '   Supported bands  : {0}'
        Adapter_Power              = '   Power saving     : {0}'
        Adapter_Connection         = '   Connection       : {0}'
        Adapter_NotReported        = '(not reported by driver)'
        Adapter_NoConnection       = '(not connected or WLAN service unavailable)'
        Adapter_ReadFailed         = '   Failed to read adapter information: {0}'
        Adapter_NotWlan            = '   Note: the selected adapter is not a wireless adapter; SSID/signal/power-saving checks were skipped.'
        Adapter_Signal             = 'signal {0} ({1} dBm)'
        Adapter_SignalOnly         = 'signal {0}'
        Adapter_RssiOnly           = 'RSSI {0} dBm'

        Status_Up                  = 'connected'
        Status_Disconnected        = 'disconnected'
        Status_Disabled            = 'disabled'
        Status_Missing             = '(adapter not found)'
        Status_Unknown             = 'unknown'

        Power_Disabled             = 'Disabled'
        Power_Enabled              = 'Enabled'
        Power_Auto                 = 'Auto'
        Power_Unknown              = '(unknown)'
        Power_NoProperty           = '(power-saving property not reported)'

        Net_Hostname               = '   Host name        : {0}'
        Net_Description            = '   Description      : {0}'
        Net_Mac                    = '   MAC address      : {0}'
        Net_IPv4                   = '   IPv4 address     : {0}  /  {1} (/{2})'
        Net_IPv4None               = '   IPv4 address     : (not available)'
        Net_Gateway                = '   Default gateway  : {0}   (packet-loss target)'
        Net_GatewayV6              = '   Default gateway  : {0} (IPv6)'
        Net_GatewayNone            = '   Default gateway  : (not available)'
        Net_Dhcp                   = '   DHCP             : {0}{1}'
        Net_DhcpEnabled            = 'Enabled'
        Net_DhcpDisabled           = 'Disabled'
        Net_DhcpServer             = '  (server {0})'
        Net_Lease                  = '   Lease            : {0}  ~  {1}'
        Net_Dns                    = '   DNS servers      : {0}'
        Net_DnsNone                = '   DNS servers      : (no IPv4 DNS)'
        Net_ReadFailed             = '   Failed to read network configuration: {0}'
        Net_NoConfigData           = 'No network configuration data returned'
        Net_Unknown                = '(unknown)'
        Net_NoGatewayWarn          = '   × No default gateway; gateway loss test skipped, site test will still run.'
        Net_DefaultRouteOther      = '   ! The default route uses "{0}", not the selected adapter; tests may not reflect this adapter.'

        Loss_Heading               = '   Gateway packet loss ({0}, {1} ping(s), {2} ms interval):'
        Loss_NoTarget              = '   (no gateway target; packet loss test skipped)'
        Loss_Line                  = '   Packet loss : {0}/{1}'
        Loss_Rtt                   = '   RTT  : avg {0} ms, max {1} ms, jitter {2} ms'
        Loss_Normal                = '      √ Link looks healthy (0 packet loss).'
        Loss_Lossy                 = '      × Packet loss detected; action recommended.'
        Loss_MaybeIcmp             = '      [i] The gateway did not answer ICMP at all; combined with the site test, this is not necessarily adapter loss.'
        Loss_AfterOk               = '      √ 0 packet loss after the restart.'
        Loss_SkippedIcmp           = '   (gateway ICMP blocked; packet loss retest skipped)'

        Site_Heading               = '   Site connectivity (DNS + TCP 443, {0} site(s)):'
        Site_Summary               = '   Summary : {0}/{1} site(s) reachable'
        Site_HintHead              = '   [i] Note: gateway has 0 packet loss, but {0} site(s) are unreachable. This is probably not adapter loss; common causes:'
        Site_HintDns               = '       - DNS resolution failed; try a public DNS such as 223.5.5.5'
        Site_HintTcp               = '       - TCP 443 is blocked or the site is unreachable'
        Site_HintNetwork           = '       - Carrier backbone issue'
        Site_HintLocal             = '       - Local security software or proxy blocking'
        Site_HintIcmp              = '   [i] The gateway does not answer ICMP, but {0}/{1} sites are reachable; this looks like ICMP filtering, not adapter failure.'
        Site_HintNoLoss            = '   [i] No gateway loss was measured, but {0} site(s) are unreachable; check DNS/proxy/network.'

        Power_Current              = '   Current value : {0}'
        Power_Valid                = '   Valid values  : {0}'
        Power_AlreadyDisabled      = '   Power saving is already disabled; no change needed.'
        Power_AlreadyAuto          = '   Power saving is already Auto; no change needed.'
        Power_AlreadyEnabled       = '   Power saving is already enabled; no change needed.'
        Power_DisablePlan          = '   [DryRun] Would disable power saving: {0} -> {1}'
        Power_AutoPlan             = '   [DryRun] Would restore Auto: {0} -> {1}'
        Power_DisableDone          = '   Power saving disabled: {0} -> {1}'
        Power_AutoDone             = '   Power saving restored to Auto: {0} -> {1}'
        Power_NoTarget             = '   No suitable power-saving target found; skipped.'
        Power_NotAccepted          = '   The driver did not accept the change; value unchanged.'
        Power_VerifyFailed         = '   The set command ran, but the new value could not be read yet.'
        Power_Failed               = '   Failed to set power saving: {0}'
        Power_NeedsRestart         = '   [i] Power-saving setting written; it will take effect after an adapter restart.'
        Power_AutoWarn             = '   Warning: Auto mode may reintroduce packet loss; use only for a control test.'

        Menu_Prompt                = '   Choose an action (Enter=N): '
        Menu_DisableRestart        = '     [d] Disable power saving and restart adapter (recommended)'
        Menu_DisableRestartAlready = '     [d] Restart adapter (power saving is already disabled) (recommended)'
        Menu_DisableRestartNoPower = '     [d] Restart adapter (no power-saving property found) (recommended)'
        Menu_RestartOnly           = '     [r] Restart adapter only'
        Menu_PowerOnly             = '     [p] Power saving only'
        Menu_Cancel                = '     [n] Cancel'
        Menu_Invalid               = '   Invalid choice; try again.'
        Menu_Canceled              = '   Canceled; no changes made.'
        Menu_PowerPrompt           = '   Choose a power-saving action (Enter=K): '
        Menu_PowerDisable          = '     [d] Disable power saving (recommended)'
        Menu_PowerAuto             = '     [a] Restore Auto (test; may cause packet loss)'
        Menu_PowerKeep             = '     [k] Keep current'
        Menu_PowerKept             = '   Keeping current setting; no changes made.'
        Menu_DryRunRestart         = '   [DryRun] Would restart adapter {0}; post-test skipped.'
        Menu_DryRunEnd             = '   [DryRun] Dry run complete: no changes were made.'

        Wait_Heading               = '   Waiting for the adapter and a usable gateway (up to {0} s)...'
        Wait_GatewayReady          = 'gateway {0}'
        Wait_GatewayNotReady       = 'gateway not ready'
        Wait_Success               = '   Reconnected: adapter Up, gateway {0} reachable.'
        Wait_SuccessIcmp           = '   Reconnected: adapter Up; gateway does not answer ICMP, but outbound TCP 443 works.'
        Wait_SuccessNoGateway      = '   Reconnected: adapter Up; outbound TCP 443 works (no gateway reported).'
        Wait_Progress              = '   Still waiting... {0} s elapsed (adapter {1}, {2})'
        Wait_Timeout               = '   × Wait timed out: {0}'
        Wait_ReasonAdapter         = 'adapter not Up'
        Wait_ReasonGateway         = 'gateway not ready'
        Wait_ReasonNetwork         = 'internet unreachable'
        Wait_ControlProbe          = '   Gateway ping failed; probing TCP 443 as a control...'
        Wait_ControlProbeNoGateway = '   Gateway not ready; probing TCP 443 as a control...'
        Wait_GatewayChanged        = '   Gateway changed: {0} -> {1}'

        Restart_Issued             = '   Adapter restart command issued.'
        Restart_Failed             = '   Failed to restart the adapter: {0}'

        Summary_Title              = 'Result summary'
        Summary_Loss               = '   Gateway loss : {0}  ->  {1}'
        Summary_Sites              = '   Sites        : {0}/{1}  ->  {2}/{3}'
        Summary_Power              = '   Power saving : {0}'
        Summary_Conclusion         = '   Conclusion   : {0}'
        Summary_Advice             = '   Advice       : {0}'
        Summary_NotMeasured        = 'N/A'
        Summary_NotMeasuredIcmp    = 'N/A (ICMP blocked)'
        Summary_IcmpBlocked        = '{0}/{1} (ICMP blocked)'
        Con_Healthy                = 'Tests look healthy; no obvious issue before or after the restart.'
        Con_Fixed                  = 'Recovered after adapter restart (0 packet loss, all sites reachable).'
        Con_StillLoss              = 'Packet loss persists after the restart.'
        Con_Advice                 = 'Use PingPlotter / Wireshark for further diagnosis, or contact your ISP.'
        Con_SitesOnly              = 'Gateway loss is 0, but some sites are unreachable; this looks like DNS, proxy, or site-side issues.'
        Con_IcmpBlocked            = 'The gateway does not answer ICMP, but sites are reachable; no adapter failure detected.'
        Con_IcmpSitesFail          = 'The gateway does not answer ICMP and sites are unreachable; check Wi-Fi/router.'
        Con_NoGatewaySitesOk       = 'No gateway was available, so link loss could not be measured; sites are reachable.'
        Con_NoGatewaySitesFail     = 'No gateway and sites are unreachable; unable to determine adapter status. Check Wi-Fi/router.'
        Con_NotRecovered           = 'Network did not fully recover; check the Wi-Fi connection or router and try again.'

        Log_File                   = ' [i] Log file: {0}'
        Log_StartFailed            = ' [i] Unable to write a log; logging disabled for this run.'
    }
}

# ---------- 语言/输出辅助 ----------
function Resolve-LangName([string]$Requested) {
    if ($Requested -ne 'auto') { return $Requested.ToLowerInvariant() }
    $ui = [System.Globalization.CultureInfo]::CurrentUICulture
    if ($ui.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
    return 'en'
}

function Initialize-Language([string]$Requested) {
    $name = Resolve-LangName $Requested
    if (-not $script:LangData.ContainsKey($name)) { $name = 'zh' }
    $script:LangName = $name
    $script:LangTable = $script:LangData[$name]
    $script:BaseLangTable = $script:LangData['zh']
}

function T([string]$Key) {
    $value = $script:LangTable[$Key]
    if ($null -eq $value) { $value = $script:BaseLangTable[$Key] }
    if ($null -eq $value) { return ('[{0}]' -f $Key) }
    return [string]$value
}

function TF([string]$Key, [object[]]$Values) {
    $format = T $Key
    if ($null -eq $Values -or $Values.Count -eq 0) { return $format }
    try { return ($format -f $Values) } catch { return $format }
}

function Say([string]$Key) { Write-Host (T $Key) }
function SayF([string]$Key, [object[]]$Values) { Write-Host (TF $Key $Values) }

function Show-Section([int]$N, [string]$TitleKey) {
    Write-Host ''
    Write-Host ' ------------------------------------------------'
    Write-Host ('  [{0}/{1}] {2}' -f $N, $script:TotalSections, (T $TitleKey))
    Write-Host ' ------------------------------------------------'
}

function Format-AdapterStatus([string]$Status) {
    switch ($Status) {
        'Up'           { return ('{0} ({1})' -f $Status, (T 'Status_Up')) }
        'Disconnected' { return ('{0} ({1})' -f $Status, (T 'Status_Disconnected')) }
        'Disabled'     { return ('{0} ({1})' -f $Status, (T 'Status_Disabled')) }
        'Missing'      { return (T 'Status_Missing') }
        default        { return $Status }
    }
}

function Get-PowerValueRole([string]$Value) {
    switch -Regex ($Value) {
        '^(已禁用|禁用|关闭|Disabled|Off)$' { return 'Disabled' }
        '^(已启用|启用|开启|Enabled|On)$'   { return 'Enabled' }
        '^(Auto|自动)$'                     { return 'Auto' }
        default                              { return 'Unknown' }
    }
}

function Format-PowerValue([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return (T 'Power_Unknown') }
    switch (Get-PowerValueRole $Value) {
        'Disabled' { return (T 'Power_Disabled') }
        'Enabled'  { return (T 'Power_Enabled') }
        'Auto'     { return (T 'Power_Auto') }
        default    { return $Value }
    }
}

function Pause-Exit {
    if ($script:NoPause -or $script:Yes -or -not $script:Interactive) { return }
    try { Read-Host (T 'Common_PromptExit') } catch { }
}

function Restore-OutputEncoding {
    if ($script:OriginalOutputEncoding) {
        try { [Console]::OutputEncoding = $script:OriginalOutputEncoding } catch { }
    }
}

function Stop-WithCode([int]$Code, [switch]$Pause) {
    Restore-OutputEncoding
    if ($Pause) { Pause-Exit }
    if ($script:NoExitSession -or $script:DotSourced) {
        $global:LASTEXITCODE = $Code
        return
    }
    exit $Code
}

function Read-Choice([string]$PromptKey, [string]$Default, [string[]]$Allowed) {
    if ($script:Yes) { return $Default }
    if (-not $script:Interactive) { return $Default }
    while ($true) {
        try { $raw = Read-Host (T $PromptKey) } catch { return $Default }
        if ($null -eq $raw) { return $Default }
        $value = $raw.Trim().ToLowerInvariant()
        if ($value -eq '') { return $Default }
        if ($Allowed -contains $value) { return $value }
        Say 'Menu_Invalid'
    }
}

# ---------- 初始化 ----------
Initialize-Language $Lang
$script:PingCount = $PingCount
$script:PingIntervalMs = $PingIntervalMs
$script:SiteTimeoutMs = $SiteTimeoutMs
$script:ReconnectTimeoutSec = $ReconnectTimeoutSec
$script:DryRun = [bool]$DryRun
$script:Yes = [bool]$Yes
$script:NoPause = [bool]$NoPause
$script:NoLog = [bool]$NoLog
$script:NoExitSession = [bool]$NoExitSession
$script:ForceLog = [bool]$Log
$script:NoElevate = [bool]$NoElevate
$script:ExitCode = 0
$script:ReadOnly = $false
$script:PowerChange = $null
$script:PowerProp = $null
$script:PowerPropLoaded = $false
$script:TranscriptStarted = $false
$script:LogPath = $null
$script:DotSourced = ($MyInvocation.InvocationName -eq '.')
$script:Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

try { $Host.UI.RawUI.WindowTitle = (TF 'Common_AppTitle' @($script:Version)) } catch { }

if (-not $script:Interactive -and -not $script:Yes -and -not $script:DryRun) {
    Say 'Error_NonInteractive'
    Stop-WithCode 2
    return
}

# ---------- 网卡识别 ----------
$adapterExplicit = $PSBoundParameters.ContainsKey('Adapter')
$adapterCandidates = @(Get-NetAdapter -Name $Adapter -ErrorAction SilentlyContinue)

if ($adapterCandidates.Count -gt 1) {
    SayF 'Err_AdapterMultiple' @($Adapter)
    $adapterCandidates | ForEach-Object { Write-Host ('   - ' + $_.Name) }
    Stop-WithCode 1 -Pause
    return
}

if ($adapterCandidates.Count -eq 0) {
    if ($adapterExplicit) {
        SayF 'Err_AdapterNotFound' @($Adapter)
        Stop-WithCode 1 -Pause
        return
    }

    $adapterCandidates = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.NdisPhysicalMedium -in @(1, 9) })

    if ($adapterCandidates.Count -eq 0) {
        Say 'Err_NoWlan'
        Stop-WithCode 1 -Pause
        return
    }
    if ($adapterCandidates.Count -gt 1) {
        Say 'Err_MultipleWlan'
        $adapterCandidates | ForEach-Object { Write-Host ('   - ' + $_.Name + '  (' + $_.InterfaceDescription + ')') }
        Stop-WithCode 1 -Pause
        return
    }
}

$script:AdapterObject = $adapterCandidates[0]
$script:AdapterName = $script:AdapterObject.Name
$script:AdapterIndex = [uint32]$script:AdapterObject.InterfaceIndex
$script:IsWlan = ($script:AdapterObject.NdisPhysicalMedium -in @(1, 9))

# ---------- 自提权 / 权限 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:IsAdmin = $isAdmin

if (-not $isAdmin -and -not $script:DryRun) {
    if (-not $script:NoElevate) {
        Say 'Elevate_NeedAdmin'
        $elevateArgs = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $PSCommandPath + '"'),
            '-Adapter', ('"' + $script:AdapterName + '"'),
            '-PingCount', ([string]$PingCount),
            '-PingIntervalMs', ([string]$PingIntervalMs),
            '-SiteTimeoutMs', ([string]$SiteTimeoutMs),
            '-ReconnectTimeoutSec', ([string]$ReconnectTimeoutSec),
            '-Lang', $script:LangName
        )
        if ($script:Yes) { $elevateArgs += '-Yes' }
        if ($script:NoPause) { $elevateArgs += '-NoPause' }
        if ($script:NoLog) { $elevateArgs += '-NoLog' }
        if ($script:ForceLog) { $elevateArgs += '-Log' }
        try {
            $elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevateArgs -PassThru -Wait -ErrorAction Stop
        } catch {
            SayF 'Elevate_Failed' @($_.Exception.Message)
            Stop-WithCode 1 -Pause
            return
        }
        if ($null -eq $elevated -or -not $elevated.HasExited -or $null -eq $elevated.ExitCode) {
            Say 'Elevate_NoExitCode'
            Stop-WithCode 1 -Pause
            return
        }
        Stop-WithCode ([int]$elevated.ExitCode)
        return
    }

    if ($script:Yes) {
        Say 'Error_AdminRequired'
        Stop-WithCode 2 -Pause
        return
    }

    $script:ReadOnly = $true
}

# ---------- 日志 ----------
function Write-LogHeader {
    Write-Host ('[i] RestartWLAN version={0} lang={1} ui={2} culture={3} admin={4} adapter={5} dryrun={6} readonly={7}' -f
        $script:Version,
        $script:LangName,
        [System.Globalization.CultureInfo]::CurrentUICulture.Name,
        [System.Globalization.CultureInfo]::CurrentCulture.Name,
        $script:IsAdmin,
        $script:AdapterName,
        $script:DryRun,
        $script:ReadOnly)
}

function Start-Log {
    if ($script:NoLog) { return }
    if ($script:DryRun -and -not $script:ForceLog) { return }

    try {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }
        $dir = Join-Path $base 'RestartWLAN\logs'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $script:LogPath = Join-Path $dir ('RestartWLAN_{0:yyyyMMdd_HHmmss_fff}.log' -f (Get-Date))
        Start-Transcript -Path $script:LogPath -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
        Write-LogHeader
        Get-ChildItem -Path $dir -Filter 'RestartWLAN_*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 20 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {
        $script:LogPath = $null
        $script:TranscriptStarted = $false
        Say 'Log_StartFailed'
    }
}

function Stop-Log {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    if ($script:LogPath) { SayF 'Log_File' @($script:LogPath) }
}

# ---------- netsh / 省电解析 ----------
function Get-NetshBlocks([string[]]$Lines, [string[]]$KnownNames) {
    $blocks = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match '^\s*(?<label>[^:：]+?)\s*[:：]\s*(?<value>.+?)\s*$') {
            $label = $Matches['label'].Trim()
            $value = $Matches['value'].Trim()
            $isNameLine = ($KnownNames -contains $value) -and
                ($label -notmatch '^(SSID|AP\s*BSSID|BSSID|配置文件|Profile|Description|说明)$')
            if ($isNameLine) {
                if ($current) { $blocks.Add($current) }
                $current = [pscustomobject]@{
                    Name = $value
                    Lines = New-Object System.Collections.Generic.List[string]
                }
                continue
            }
        }
        if ($current) { $current.Lines.Add($line) }
    }
    if ($current) { $blocks.Add($current) }
    return $blocks
}

function Get-NetshField([string[]]$Lines, [string]$LabelPattern, [string]$ValuePattern) {
    $pairs = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        if ($line -match '^\s*(?<label>[^:：]+?)\s*[:：]\s*(?<value>.*)$') {
            $pairs.Add([pscustomobject]@{
                Label = $Matches['label'].Trim()
                Value = $Matches['value'].Trim()
            })
        }
    }

    foreach ($pair in $pairs) {
        if ($pair.Label -match $LabelPattern) { return $pair.Value }
    }
    if ($ValuePattern) {
        foreach ($pair in $pairs) {
            if ($pair.Label -match '^(SSID|AP\s*BSSID|BSSID|配置文件|Profile)$') { continue }
            if ($pair.Value -match $ValuePattern) { return $pair.Value }
        }
    }
    return ''
}

function Get-WlanInfo {
    if (-not $script:IsWlan) { return $null }
    $lines = @(netsh wlan show interfaces 2>$null)
    $knownNames = @($script:AdapterName)
    $knownNames += @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $blocks = @(Get-NetshBlocks $lines $knownNames)
    if ($blocks.Count -eq 0) { return $null }

    $block = $blocks | Where-Object { $_.Name -eq $script:AdapterName } | Select-Object -First 1
    if (-not $block -and $blocks.Count -eq 1) { $block = $blocks[0] }
    if (-not $block) { return $null }

    return [pscustomobject]@{
        Ssid   = Get-NetshField @($block.Lines) '^SSID$' ''
        Band   = Get-NetshField @($block.Lines) '^(波段|频带|频段|Band)$' '^\d+(?:\.\d+)?\s*GHz$'
        Radio  = Get-NetshField @($block.Lines) '^(无线电类型|Radio\s*type)$' '^802\.11\S*$'
        Signal = Get-NetshField @($block.Lines) '^(信号|Signal)$' '^\d+\s*%$'
        Rssi   = Get-NetshField @($block.Lines) '^(Rssi|RSSI)$' ''
    }
}

function Get-PowerSavingProperty {
    param([switch]$Refresh)
    if (-not $script:IsWlan) { return $null }
    if (-not $script:PowerPropLoaded -or $Refresh) {
        $props = @(Get-NetAdapterAdvancedProperty -Name $script:AdapterName -ErrorAction SilentlyContinue)
        $prop = $props | Where-Object { $_.RegistryKeyword -eq 'LowPowerEnable' } | Select-Object -First 1
        if (-not $prop) {
            $prop = $props |
                Where-Object {
                    $_.DisplayName -match '省电|节能|Power\s*Saving|PowerSave' -and
                    $_.DisplayName -notmatch 'Mimo|TxPower|Transmit'
                } |
                Select-Object -First 1
        }
        $script:PowerProp = $prop
        $script:PowerPropLoaded = $true
    }
    return $script:PowerProp
}

function Resolve-PowerTarget([string]$Mode) {
    $prop = Get-PowerSavingProperty
    if (-not $prop) {
        return [pscustomobject]@{ Property = $null; Ok = $false; Reason = 'NoProperty'; Current = $null; Target = $null; Already = $false }
    }

    $current = $prop.DisplayValue
    $currentRole = Get-PowerValueRole $current
    $values = @($prop.ValidDisplayValues)

    if ($Mode -eq 'Disable') {
        $target = $values | Where-Object { (Get-PowerValueRole $_) -eq 'Disabled' } | Select-Object -First 1
    } else {
        $target = $values | Where-Object { (Get-PowerValueRole $_) -eq 'Auto' } | Select-Object -First 1
        if (-not $target) {
            $target = $values | Where-Object { (Get-PowerValueRole $_) -eq 'Enabled' } | Select-Object -First 1
        }
    }

    if (-not $target) {
        return [pscustomobject]@{ Property = $prop; Ok = $false; Reason = 'NoTarget'; Current = $current; Target = $null; Already = $false }
    }

    $targetRole = Get-PowerValueRole $target
    return [pscustomobject]@{
        Property = $prop
        Ok = $true
        Reason = ''
        Current = $current
        Target = $target
        WantedRole = $targetRole
        Already = ($currentRole -eq $targetRole)
    }
}

function Invoke-PowerChange([string]$Mode) {
    $plan = Resolve-PowerTarget $Mode
    if (-not $plan.Property) {
        Say 'Power_NoProperty'
        return [pscustomobject]@{ Success = $true; Changed = $false; Skipped = $true; Reason = 'NoProperty'; Current = $null; Target = $null }
    }
    if (-not $plan.Ok) {
        Say 'Power_NoTarget'
        return [pscustomobject]@{ Success = $false; Changed = $false; Skipped = $true; Reason = 'NoTarget'; Current = $plan.Current; Target = $null }
    }
    if ($plan.Already) {
        if ($plan.WantedRole -eq 'Disabled') { Say 'Power_AlreadyDisabled' }
        elseif ($plan.WantedRole -eq 'Auto') { Say 'Power_AlreadyAuto' }
        else { Say 'Power_AlreadyEnabled' }
        return [pscustomobject]@{ Success = $true; Changed = $false; Already = $true; Current = $plan.Current; Target = $plan.Target }
    }

    if ($script:DryRun) {
        if ($Mode -eq 'Disable') { SayF 'Power_DisablePlan' @((Format-PowerValue $plan.Current), (Format-PowerValue $plan.Target)) }
        else { SayF 'Power_AutoPlan' @((Format-PowerValue $plan.Current), (Format-PowerValue $plan.Target)) }
        return [pscustomobject]@{ Success = $true; Changed = $false; Preview = $true; Current = $plan.Current; Target = $plan.Target }
    }

    if (-not $script:IsAdmin) {
        Say 'Error_AdminRequired'
        return [pscustomobject]@{ Success = $false; Changed = $false; Reason = 'NotAdmin'; Current = $plan.Current; Target = $plan.Target }
    }

    $prop = $plan.Property
    try {
        $validDisplay = @($prop.ValidDisplayValues)
        $validRegistry = @($prop.ValidRegistryValues)
        $index = -1
        for ($i = 0; $i -lt $validDisplay.Count; $i++) {
            if ($validDisplay[$i] -eq $plan.Target) { $index = $i; break }
        }

        $setParams = @{
            InputObject = $prop
            NoRestart = $true
            Confirm = $false
            ErrorAction = 'Stop'
        }
        if ($index -ge 0 -and $index -lt $validRegistry.Count -and -not [string]::IsNullOrWhiteSpace([string]$validRegistry[$index])) {
            Set-NetAdapterAdvancedProperty @setParams -RegistryValue ([string]$validRegistry[$index])
        } else {
            Set-NetAdapterAdvancedProperty @setParams -DisplayValue $plan.Target
        }
    } catch {
        try {
            Set-NetAdapterAdvancedProperty -InputObject $prop -DisplayValue $plan.Target -Confirm:$false -ErrorAction Stop
        } catch {
            SayF 'Power_Failed' @($_.Exception.Message)
            return [pscustomobject]@{ Success = $false; Changed = $false; Reason = 'SetFailed'; Current = $plan.Current; Target = $plan.Target }
        }
    }

    $newValue = $null
    for ($i = 0; $i -lt 3; $i++) {
        Start-Sleep -Milliseconds 700
        $fresh = Get-PowerSavingProperty -Refresh
        if ($fresh -and -not [string]::IsNullOrWhiteSpace($fresh.DisplayValue)) {
            $newValue = $fresh.DisplayValue
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($newValue)) {
        Say 'Power_VerifyFailed'
        return [pscustomobject]@{ Success = $true; Changed = $false; VerifyFailed = $true; Current = $plan.Current; Target = $plan.Target }
    }

    $newRole = Get-PowerValueRole $newValue
    if ($newRole -ne $plan.WantedRole -and $newValue -ne $plan.Target) {
        Say 'Power_NotAccepted'
        return [pscustomobject]@{ Success = $false; Changed = $false; Reason = 'NotAccepted'; Current = $plan.Current; Target = $plan.Target; New = $newValue }
    }

    if ($Mode -eq 'Disable') {
        SayF 'Power_DisableDone' @((Format-PowerValue $plan.Current), (Format-PowerValue $newValue))
    } else {
        SayF 'Power_AutoDone' @((Format-PowerValue $plan.Current), (Format-PowerValue $newValue))
    }
    $script:PowerChange = (Format-PowerValue $plan.Current) + ' -> ' + (Format-PowerValue $newValue)
    return [pscustomobject]@{ Success = $true; Changed = $true; Current = $plan.Current; Target = $plan.Target; New = $newValue }
}

# ---------- 网络信息 ----------
function Get-GatewayFromConfig($Config) {
    $v4 = @($Config.IPv4DefaultGateway) | Select-Object -First 1
    if ($v4 -and $v4.NextHop) {
        return [pscustomobject]@{ Address = [string]$v4.NextHop; Family = 'IPv4' }
    }
    $v6 = @($Config.IPv6DefaultGateway) | Select-Object -First 1
    if ($v6 -and $v6.NextHop) {
        return [pscustomobject]@{ Address = [string]$v6.NextHop; Family = 'IPv6' }
    }
    return $null
}

function Get-DefaultGateway {
    $cfg = @(Get-NetIPConfiguration -InterfaceIndex $script:AdapterIndex -ErrorAction SilentlyContinue) |
        Select-Object -First 1
    if (-not $cfg) { return $null }
    return Get-GatewayFromConfig $cfg
}

function Convert-PrefixToMask([int]$Prefix) {
    if ($Prefix -lt 0 -or $Prefix -gt 32) { return '' }
    $bits = ('1' * $Prefix) + ('0' * (32 - $Prefix))
    $octets = for ($i = 0; $i -lt 32; $i += 8) {
        [Convert]::ToInt32($bits.Substring($i, 8), 2)
    }
    return ($octets -join '.')
}

function Show-AdapterInfo {
    try {
        $adapter = Get-NetAdapter -Name $script:AdapterName -ErrorAction Stop
        SayF 'Adapter_Hardware' @($adapter.InterfaceDescription)
        SayF 'Adapter_Driver' @($adapter.DriverVersion, ('{0:yyyy-MM-dd}' -f $adapter.DriverDate))
        SayF 'Adapter_Status' @((Format-AdapterStatus ([string]$adapter.Status)))

        $bands = @(Get-NetAdapterAdvancedProperty -Name $script:AdapterName -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.DisplayName -match '(?i)(\d+(?:\.\d+)?\s*GHz)') { $Matches[1] }
            } |
            Sort-Object -Unique)
        if ($bands.Count -gt 0) { SayF 'Adapter_Bands' @(($bands -join '  ')) }
        else { SayF 'Adapter_Bands' @((T 'Adapter_NotReported')) }

        $prop = Get-PowerSavingProperty
        if ($prop) { SayF 'Adapter_Power' @((Format-PowerValue $prop.DisplayValue)) }
        else { SayF 'Adapter_Power' @((T 'Power_NoProperty')) }

        if (-not $script:IsWlan) {
            Say 'Adapter_NotWlan'
            return
        }

        $wlan = Get-WlanInfo
        if ($wlan) {
            $signalText = ''
            if ($wlan.Signal -and $wlan.Rssi) { $signalText = TF 'Adapter_Signal' @($wlan.Signal, $wlan.Rssi) }
            elseif ($wlan.Signal) { $signalText = TF 'Adapter_SignalOnly' @($wlan.Signal) }
            elseif ($wlan.Rssi) { $signalText = TF 'Adapter_RssiOnly' @($wlan.Rssi) }

            $parts = @($wlan.Ssid, $wlan.Band, $wlan.Radio, $signalText) | Where-Object { $_ }
            if (@($parts).Count -gt 0) {
                SayF 'Adapter_Connection' @(($parts -join ', '))
            } else {
                SayF 'Adapter_Connection' @((T 'Adapter_NoConnection'))
            }
        } else {
            SayF 'Adapter_Connection' @((T 'Adapter_NoConnection'))
        }
    } catch {
        SayF 'Adapter_ReadFailed' @($_.Exception.Message)
    }
}

function Show-NetworkInfo {
    try {
        $cfg = @(Get-NetIPConfiguration -InterfaceIndex $script:AdapterIndex -ErrorAction Stop) |
            Select-Object -First 1
        if (-not $cfg) { throw (T 'Net_NoConfigData') }
    } catch {
        SayF 'Net_ReadFailed' @($_.Exception.Message)
        return $null
    }

    $ipObj = @($cfg.IPv4Address) | Select-Object -First 1
    $gateway = Get-GatewayFromConfig $cfg
    $dns = @($cfg.DNSServer |
        Where-Object { $_.AddressFamily -eq 2 } |
        ForEach-Object { $_.ServerAddresses } |
        Select-Object -Unique)
    $wmi = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex=$($cfg.InterfaceIndex)" -ErrorAction SilentlyContinue) |
        Select-Object -First 1

    $desc = if ($cfg.InterfaceDescription) { $cfg.InterfaceDescription }
            elseif ($cfg.NetAdapter) { $cfg.NetAdapter.InterfaceDescription }
            else { T 'Net_Unknown' }
    $mac = if ($cfg.NetAdapter) { $cfg.NetAdapter.MacAddress } else { T 'Net_Unknown' }

    SayF 'Net_Hostname' @($env:COMPUTERNAME)
    SayF 'Net_Description' @($desc)
    SayF 'Net_Mac' @($mac)

    if ($ipObj) {
        $mask = Convert-PrefixToMask ([int]$ipObj.PrefixLength)
        SayF 'Net_IPv4' @($ipObj.IPAddress, $mask, $ipObj.PrefixLength)
    } else {
        Say 'Net_IPv4None'
    }

    if ($gateway) {
        if ($gateway.Family -eq 'IPv6') { SayF 'Net_GatewayV6' @($gateway.Address) }
        else { SayF 'Net_Gateway' @($gateway.Address) }
    } else {
        Say 'Net_GatewayNone'
    }

    if ($wmi) {
        $dhcpText = if ($wmi.DHCPEnabled) { T 'Net_DhcpEnabled' } else { T 'Net_DhcpDisabled' }
        $serverText = if ($wmi.DHCPServer) { TF 'Net_DhcpServer' @($wmi.DHCPServer) } else { '' }
        SayF 'Net_Dhcp' @($dhcpText, $serverText)
        if ($wmi.DHCPLeaseObtained -and $wmi.DHCPLeaseExpires) {
            $start = '{0:yyyy-MM-dd HH:mm:ss}' -f $wmi.DHCPLeaseObtained
            $end = '{0:yyyy-MM-dd HH:mm:ss}' -f $wmi.DHCPLeaseExpires
            SayF 'Net_Lease' @($start, $end)
        }
    } else {
        SayF 'Net_Dhcp' @((T 'Net_Unknown'), '')
    }

    if ($dns.Count -gt 0) { SayF 'Net_Dns' @(($dns -join ', ')) }
    else { Say 'Net_DnsNone' }

    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route -and $route.InterfaceIndex -ne $script:AdapterIndex) {
        $routeAdapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($routeAdapter) { SayF 'Net_DefaultRouteOther' @($routeAdapter.Name) }
    }

    if (-not $gateway) { Say 'Net_NoGatewayWarn' }

    return [pscustomobject]@{
        Gateway = if ($gateway) { $gateway.Address } else { $null }
        GatewayFamily = if ($gateway) { $gateway.Family } else { $null }
    }
}

# ---------- 连通性测试 ----------
function New-SkippedLoss {
    return [pscustomobject]@{ Sent = 0; Received = 0; Loss = 0; Avg = $null; Max = $null; Jitter = $null; Skipped = $true }
}

function Test-Loss([string]$Target) {
    if (-not $Target) {
        Say 'Loss_NoTarget'
        return New-SkippedLoss
    }

    SayF 'Loss_Heading' @($Target, $script:PingCount, $script:PingIntervalMs)
    $ping = [System.Net.NetworkInformation.Ping]::new()
    $times = [System.Collections.Generic.List[int]]::new()
    $sent = $script:PingCount
    try {
        for ($i = 0; $i -lt $sent; $i++) {
            try {
                $reply = $ping.Send($Target, 1000)
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

    SayF 'Loss_Line' @($loss, $sent)
    if ($null -ne $avg) { SayF 'Loss_Rtt' @($avg, $max, $jitter) }

    return [pscustomobject]@{
        Sent = $sent
        Received = $received
        Loss = $loss
        Avg = $avg
        Max = $max
        Jitter = $jitter
        Skipped = $false
    }
}

function Test-Site([string]$Site) {
    $dnsOk = $false
    $tcpOk = $false
    $ms = $null
    $ips = @()

    try {
        $records = @(Resolve-DnsName -Name $Site -Type A -DnsOnly -QuickTimeout -ErrorAction Stop)
        $ips = @($records | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress } | Select-Object -Unique)
        if ($ips.Count -gt 0) { $dnsOk = $true }
    } catch { }

    if ($ips.Count -eq 0) {
        try {
            $records6 = @(Resolve-DnsName -Name $Site -Type AAAA -DnsOnly -QuickTimeout -ErrorAction Stop)
            $ips = @($records6 | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress } | Select-Object -Unique)
            if ($ips.Count -gt 0) { $dnsOk = $true }
        } catch { }
    }

    $usedIp = $null
    $tried = 0
    if ($dnsOk) {
        foreach ($ip in ($ips | Select-Object -First 3)) {
            $tried++
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                if ($tcp.ConnectAsync($ip, 443).Wait($script:SiteTimeoutMs) -and $tcp.Connected) {
                    $tcpOk = $true
                    $ms = $sw.ElapsedMilliseconds
                    $usedIp = $ip
                    break
                }
            } catch {
                $tcpOk = $false
            } finally {
                $sw.Stop()
                $tcp.Dispose()
            }
        }
    }

    return [pscustomobject]@{
        Site = $Site
        IP = if ($usedIp) { $usedIp } elseif ($ips.Count -gt 0) { $ips[0] } else { $null }
        Dns = $dnsOk
        Tcp = $tcpOk
        Ms = $ms
        Tried = $tried
    }
}

function Test-Sites {
    SayF 'Site_Heading' @($script:Sites.Count)
    Write-Host '   Site               IPv4              DNS    443    Time'
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($site in $script:Sites) {
        $result = Test-Site $site
        $results.Add($result)
        $ipText = if ($result.IP) { $result.IP } else { '-' }
        $dnsText = if ($result.Dns) { 'OK' } else { 'FAIL' }
        $tcpText = if ($result.Tcp) { 'OK' } else { 'FAIL' }
        $msText = if ($null -ne $result.Ms) { ('{0} ms' -f $result.Ms) } else { '-' }
        Write-Host ('   {0,-18} {1,-16} {2,-6} {3,-6} {4}' -f $result.Site, $ipText, $dnsText, $tcpText, $msText)
    }

    $ok = @($results | Where-Object { $_.Tcp }).Count
    $dnsFail = @($results | Where-Object { -not $_.Dns }).Count
    $tcpFail = @($results | Where-Object { $_.Dns -and -not $_.Tcp }).Count
    SayF 'Site_Summary' @($ok, $script:Sites.Count)

    return [pscustomobject]@{
        Total = $script:Sites.Count
        Ok = $ok
        Fail = $script:Sites.Count - $ok
        DnsFail = $dnsFail
        TcpFail = $tcpFail
        Results = $results
    }
}

function Test-ControlConnectivity {
    try { return [bool](Test-Site 'www.baidu.com').Tcp } catch { return $false }
}

function Show-SiteHint($Loss, $Sites, [bool]$IcmpBlocked) {
    if ($IcmpBlocked -and $Sites.Ok -gt 0) {
        SayF 'Site_HintIcmp' @($Sites.Ok, $Sites.Total)
        return
    }
    if ($Loss.Skipped -and $Sites.Fail -gt 0) {
        SayF 'Site_HintNoLoss' @($Sites.Fail)
        return
    }
    if (-not $Loss.Skipped -and $Loss.Loss -eq 0 -and $Sites.Fail -gt 0) {
        SayF 'Site_HintHead' @($Sites.Fail)
        if ($Sites.DnsFail -gt 0) { Say 'Site_HintDns' }
        if ($Sites.TcpFail -gt 0) { Say 'Site_HintTcp' }
        Say 'Site_HintNetwork'
        Say 'Site_HintLocal'
    }
}

function Wait-Reconnect {
    SayF 'Wait_Heading' @($script:ReconnectTimeoutSec)
    $start = Get-Date
    $deadline = $start.AddSeconds($script:ReconnectTimeoutSec)
    $lastProgress = $start
    $nextControl = $start.AddSeconds(6)
    $controlAnnounced = $false
    $controlOk = $false
    $status = 'Missing'
    $gateway = $null
    $ping = [System.Net.NetworkInformation.Ping]::new()

    try {
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $adapter = Get-NetAdapter -Name $script:AdapterName -ErrorAction SilentlyContinue
            $status = if ($adapter) { [string]$adapter.Status } else { 'Missing' }
            $gwInfo = Get-DefaultGateway
            $gateway = if ($gwInfo) { $gwInfo.Address } else { $null }

            $pingOk = $false
            if ($gateway) {
                try { $pingOk = $ping.Send($gateway, 800).Status -eq 'Success' } catch { }
            }
            $elapsed = ((Get-Date) - $start).TotalSeconds

            if ($status -eq 'Up' -and $gateway -and $pingOk -and $elapsed -ge 5) {
                SayF 'Wait_Success' @($gateway)
                return [pscustomobject]@{ Connected = $true; IcmpBlocked = $false; NoGateway = $false; Gateway = $gateway }
            }

            if ($status -eq 'Up' -and $elapsed -ge 6 -and (($gateway -and -not $pingOk) -or -not $gateway)) {
                if ((Get-Date) -ge $nextControl) {
                    if (-not $controlAnnounced) {
                        if ($gateway) { Say 'Wait_ControlProbe' }
                        else { Say 'Wait_ControlProbeNoGateway' }
                        $controlAnnounced = $true
                    }
                    $controlOk = Test-ControlConnectivity
                    $nextControl = (Get-Date).AddSeconds(5)
                }
                if ($controlOk) {
                    if ($gateway) {
                        Say 'Wait_SuccessIcmp'
                        return [pscustomobject]@{ Connected = $true; IcmpBlocked = $true; NoGateway = $false; Gateway = $gateway }
                    }
                    Say 'Wait_SuccessNoGateway'
                    return [pscustomobject]@{ Connected = $true; IcmpBlocked = $false; NoGateway = $true; Gateway = $null }
                }
            }

            if (((Get-Date) - $lastProgress).TotalSeconds -ge 5) {
                $gatewayText = if ($gateway) { TF 'Wait_GatewayReady' @($gateway) } else { T 'Wait_GatewayNotReady' }
                SayF 'Wait_Progress' @([int]$elapsed, (Format-AdapterStatus $status), $gatewayText)
                $lastProgress = Get-Date
            }
        }
    } finally {
        $ping.Dispose()
    }

    $reasonKey = if ($status -ne 'Up') { 'Wait_ReasonAdapter' }
                 elseif (-not $gateway) { 'Wait_ReasonGateway' }
                 else { 'Wait_ReasonNetwork' }
    SayF 'Wait_Timeout' @((T $reasonKey))
    return [pscustomobject]@{
        Connected = $false
        IcmpBlocked = $false
        NoGateway = (-not $gateway)
        Gateway = $gateway
        Reason = (T $reasonKey)
    }
}

# ---------- 汇总/菜单 ----------
function Format-LossCell($Loss, [bool]$IcmpBlocked) {
    if ($Loss.Skipped) { return (T 'Summary_NotMeasured') }
    if ($IcmpBlocked) { return (TF 'Summary_IcmpBlocked' @($Loss.Loss, $Loss.Sent)) }
    return ('{0}/{1}' -f $Loss.Loss, $Loss.Sent)
}

function Show-Summary($BeforeLoss, $BeforeSites, $AfterLoss, $AfterSites, $Wait, [bool]$BeforeIcmp, [bool]$AfterIcmp) {
    Write-Host ''
    Write-Host ' ------------------------------------------------'
    Say 'Summary_Title'
    Write-Host ' ------------------------------------------------'

    $beforeCell = Format-LossCell $BeforeLoss $BeforeIcmp
    $afterCell = if ($AfterLoss.Skipped) {
        if ($AfterIcmp) { T 'Summary_NotMeasuredIcmp' } else { T 'Summary_NotMeasured' }
    } else {
        Format-LossCell $AfterLoss $AfterIcmp
    }

    SayF 'Summary_Loss' @($beforeCell, $afterCell)
    SayF 'Summary_Sites' @($BeforeSites.Ok, $BeforeSites.Total, $AfterSites.Ok, $AfterSites.Total)
    if ($script:PowerChange) { SayF 'Summary_Power' @($script:PowerChange) }

    $afterSitesOk = ($AfterSites.Fail -eq 0)
    $afterConfirmedLoss = (-not $AfterLoss.Skipped) -and ($AfterLoss.Loss -gt 0) -and (-not $AfterIcmp)
    $beforeBad = (-not $BeforeLoss.Skipped -and $BeforeLoss.Loss -gt 0) -or ($BeforeSites.Fail -gt 0)

    if (-not $Wait.Connected -and -not $afterSitesOk) {
        $conclusion = T 'Con_NotRecovered'
    } elseif ($afterConfirmedLoss) {
        $conclusion = T 'Con_StillLoss'
    } elseif (-not $afterSitesOk) {
        if ($Wait.IcmpBlocked -or $AfterIcmp) { $conclusion = T 'Con_IcmpSitesFail' }
        elseif ($Wait.NoGateway -or $AfterLoss.Skipped) { $conclusion = T 'Con_NoGatewaySitesFail' }
        else { $conclusion = T 'Con_SitesOnly' }
    } elseif ($Wait.IcmpBlocked -or $AfterIcmp) {
        $conclusion = T 'Con_IcmpBlocked'
    } elseif ($Wait.NoGateway) {
        $conclusion = T 'Con_NoGatewaySitesOk'
    } elseif ($beforeBad) {
        $conclusion = T 'Con_Fixed'
    } else {
        $conclusion = T 'Con_Healthy'
    }

    SayF 'Summary_Conclusion' @($conclusion)
    if ($afterConfirmedLoss) { SayF 'Summary_Advice' @((T 'Con_Advice')) }

    if ($afterConfirmedLoss -or -not $afterSitesOk) { $script:ExitCode = 1 }
}

function Select-Action {
    if ($script:Yes) { return 'd' }

    $prop = Get-PowerSavingProperty
    if (-not $prop) {
        Say 'Menu_DisableRestartNoPower'
    } elseif ((Get-PowerValueRole $prop.DisplayValue) -eq 'Disabled') {
        Say 'Menu_DisableRestartAlready'
    } else {
        Say 'Menu_DisableRestart'
    }
    Say 'Menu_RestartOnly'
    if ($prop) { Say 'Menu_PowerOnly' }
    Say 'Menu_Cancel'

    $allowed = if ($prop) { @('d', 'r', 'p', 'n') } else { @('d', 'r', 'n') }
    return (Read-Choice 'Menu_Prompt' 'n' $allowed)
}

function Select-PowerAction {
    $prop = Get-PowerSavingProperty
    if (-not $prop) {
        Say 'Power_NoProperty'
        return 'k'
    }

    Say 'Menu_PowerDisable'
    Say 'Menu_PowerAuto'
    Say 'Menu_PowerKeep'
    $choice = Read-Choice 'Menu_PowerPrompt' 'k' @('d', 'a', 'k')
    if ($choice -eq 'a') { Say 'Power_AutoWarn' }
    return $choice
}

# ---------- 主流程 ----------
function Main {
    Start-Log

    Write-Host ''
    Write-Host ' ================================================'
    SayF 'Common_BannerTitle' @($script:Version)
    Say 'Common_BannerSub'
    Write-Host ' ================================================'

    $badge = ''
    if ($script:DryRun) { $badge = T 'Common_BadgeDryRun' }
    elseif ($script:ReadOnly) { $badge = T 'Common_BadgeReadOnly' }
    SayF 'Common_BannerAdapter' @($script:AdapterName, $badge)

    Show-Section 1 'Section_Adapter'
    Show-AdapterInfo

    Show-Section 2 'Section_Network'
    $net = Show-NetworkInfo
    $router = if ($net) { $net.Gateway } else { $null }

    Show-Section 3 'Section_Test'
    if ($router) { $beforeLoss = Test-Loss $router }
    else { $beforeLoss = New-SkippedLoss }
    $beforeSites = Test-Sites
    $preIcmp = (-not $beforeLoss.Skipped) -and ($beforeLoss.Loss -eq $beforeLoss.Sent) -and ($beforeSites.Ok -gt 0)

    if ($preIcmp) { Say 'Loss_MaybeIcmp' }
    elseif (-not $beforeLoss.Skipped -and $beforeLoss.Loss -eq 0) { Say 'Loss_Normal' }
    elseif (-not $beforeLoss.Skipped) { Say 'Loss_Lossy' }
    Show-SiteHint $beforeLoss $beforeSites $preIcmp

    if ($script:DryRun) {
        Show-Section 4 'Section_Action'
        $plan = Resolve-PowerTarget 'Disable'
        if (-not $plan.Property) { Say 'Power_NoProperty' }
        elseif ($plan.Already) { Say 'Power_AlreadyDisabled' }
        elseif ($plan.Ok) { SayF 'Power_DisablePlan' @((Format-PowerValue $plan.Current), (Format-PowerValue $plan.Target)) }
        else { Say 'Power_NoTarget' }
        SayF 'Menu_DryRunRestart' @($script:AdapterName)
        Say 'Menu_DryRunEnd'
        $confirmedLoss = (-not $beforeLoss.Skipped -and $beforeLoss.Loss -gt 0 -and -not $preIcmp)
        if ($confirmedLoss -or $beforeSites.Fail -gt 0) { $script:ExitCode = 1 }
        return
    }

    if ($script:ReadOnly) {
        Say 'ReadOnly_Notice'
        $confirmedLoss = (-not $beforeLoss.Skipped -and $beforeLoss.Loss -gt 0 -and -not $preIcmp)
        if ($confirmedLoss -or $beforeSites.Fail -gt 0) { $script:ExitCode = 1 }
        return
    }

    Show-Section 4 'Section_Action'
    $prop = Get-PowerSavingProperty
    if ($prop) {
        SayF 'Power_Current' @((Format-PowerValue $prop.DisplayValue))
        $values = @($prop.ValidDisplayValues | ForEach-Object { Format-PowerValue $_ })
        SayF 'Power_Valid' @(($values -join '  |  '))
    } else {
        Say 'Power_NoProperty'
    }

    $action = Select-Action
    if ($action -eq 'n') {
        Say 'Menu_Canceled'
        return
    }

    if ($action -eq 'p') {
        $powerChoice = Select-PowerAction
        if ($powerChoice -eq 'k') {
            Say 'Menu_PowerKept'
            return
        }
        $mode = if ($powerChoice -eq 'd') { 'Disable' } else { 'Auto' }
        $powerResult = Invoke-PowerChange $mode
        if ($powerResult.Changed -or $powerResult.VerifyFailed) { Say 'Power_NeedsRestart' }
        if (-not $powerResult.Success) { $script:ExitCode = 1 }
        return
    }

    $powerChanged = $false
    if ($action -eq 'd') {
        $powerResult = Invoke-PowerChange 'Disable'
        $powerChanged = [bool]$powerResult.Changed
        if (-not $powerResult.Success) { $script:ExitCode = 1 }
    }

    try {
        $script:AdapterObject = Get-NetAdapter -Name $script:AdapterName -ErrorAction Stop
        Restart-NetAdapter -InputObject $script:AdapterObject -Confirm:$false -ErrorAction Stop
        Say 'Restart_Issued'
    } catch {
        SayF 'Restart_Failed' @($_.Exception.Message)
        if ($powerChanged) { Say 'Power_NeedsRestart' }
        $script:ExitCode = 1
        return
    }

    Show-Section 5 'Section_Wait'
    $wait = Wait-Reconnect

    $newGateway = Get-DefaultGateway
    if ($newGateway) {
        if (-not $router -or $newGateway.Address -ne $router) {
            if ($router) { SayF 'Wait_GatewayChanged' @($router, $newGateway.Address) }
            $router = $newGateway.Address
        }
    } elseif (-not $wait.NoGateway) {
        $wait.NoGateway = $true
    }

    Show-Section 6 'Section_After'
    if ($wait.IcmpBlocked) {
        Say 'Loss_SkippedIcmp'
        $afterLoss = New-SkippedLoss
    } elseif ($wait.NoGateway -or -not $router) {
        $afterLoss = New-SkippedLoss
    } else {
        $afterLoss = Test-Loss $router
        if (-not $afterLoss.Skipped -and $afterLoss.Loss -eq 0) { Say 'Loss_AfterOk' }
    }

    $afterSites = Test-Sites
    $afterIcmp = [bool]$wait.IcmpBlocked
    if (-not $afterIcmp -and -not $afterLoss.Skipped -and $afterLoss.Loss -eq $afterLoss.Sent -and $afterSites.Ok -gt 0) {
        $afterIcmp = $true
        Say 'Loss_MaybeIcmp'
    }
    Show-SiteHint $afterLoss $afterSites $afterIcmp
    Show-Summary $beforeLoss $beforeSites $afterLoss $afterSites $wait $preIcmp $afterIcmp
}

# ---------- 入口 ----------
try {
    Main
} catch {
    SayF 'Common_UnhandledError' @($_.Exception.Message)
    $script:ExitCode = 1
}

Stop-Log
Pause-Exit
Stop-WithCode $script:ExitCode
