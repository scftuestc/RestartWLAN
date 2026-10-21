# RestartWLAN — 网卡重启小工具 v3.0

Windows 下的 PowerShell 小工具: 一键完成「网络信息 → 丢包诊断 → 重启无线网卡 → 复测」, 用于应对无线网卡间歇性丢包的情况(网页时卡时不卡、游戏加速器报网络异常等)。

## 功能流程(七步, 每步 y/N 确认)

1. **网卡信息** — 自动识别无线网卡(默认名 `WLAN`; 默认名不存在时按 `NdisPhysicalMedium = 9` 识别); 显示硬件名称、驱动版本、支持频段、当前省电模式、当前连接(SSID/频段/协议/信号/RSSI)
2. **当前网络信息** — 通过 `Get-NetIPConfiguration` / CIM 读取主机名、描述、物理地址、IPv4 地址/掩码、默认网关、DHCP、租约和 DNS; 不再解析 `ipconfig` 文本, 不受系统语言影响; **丢包测试目标自动取自检测到的默认网关**
3. **丢包测试(前)** — 用 .NET Ping 向网关发 20 个包(默认间隔 500ms, 可用参数调整), 统计丢包、平均/最大 RTT 和波动; 随后对 8 个国内网站做 **DNS 解析 + TCP 443 握手**, 比 ICMP 更贴近"网页能不能打开"; 若网关 0 丢包但网站不可达, 会区分 DNS 失败和 443 失败并给出可能原因
4. **省电模式切换(可选)** — 自动查找驱动的省电属性(优先 `RegistryKeyword = LowPowerEnable`, 否则按名称匹配), 根据 `ValidDisplayValues` 切换, 不再写死中文显示值
5. **重启网卡**
6. **等待 WiFi 重连** — 最多 45 秒, 同时等待网卡 `Up` 和默认网关可达; 超时会给出明确提示
7. **丢包测试(后)** — 复测网关丢包和网站连通; 若网关变化会自动更新目标; 最后输出重启前后汇总和结论

## 使用方法

下载 `RestartWLAN.bat` 和 `RestartWLAN.ps1`, 双击 `RestartWLAN.bat`(它来拉起 `RestartWLAN.ps1`)→ 在 UAC 弹窗点「是」→ 按提示输入 y 继续, 回车或 N 随时退出, 结尾按 Enter 关闭窗口。

也可以在命令行直接执行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
```

只读演练(不修改省电模式、不重启网卡, 也不需要管理员):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -DryRun
```

批处理也支持传参: `RestartWLAN.bat -DryRun`.

## 可选参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-Adapter` | `WLAN` | 指定网卡名; 默认名不存在时自动识别无线网卡; 有多块无线网卡时需显式指定 |
| `-PingCount` | `20` | 丢包测试包数(1-200) |
| `-PingIntervalMs` | `500` | 包间隔, 单位毫秒(10-5000); 想观察更长时间可调大 |
| `-DryRun` | 关 | 只读演练: 不切换省电、不重启网卡, 跳过第 6/7 步 |
| `-NoElevate` | 关 | 跳过自动提权; 需当前已是管理员, 或只做只读检查 |

## 日志与退出码

- 每次运行会尝试记录到 `%LOCALAPPDATA%\RestartWLAN\logs\RestartWLAN_日期_时间.log`, 结尾会打印具体路径; 若无法写入则自动跳过, 不影响主流程
- 退出码: `0` 正常完成或用户主动退出; `1` 找不到网卡、无默认网关、重启失败, 或复测仍有丢包/网站不可达
- 自动识别依据 `NdisPhysicalMedium = 9`(Native 802.11); 如果机器上有多个无线网卡, 脚本会列出名称并要求用 `-Adapter` 指定

## 注意事项

- **`RestartWLAN.ps1` 为 UTF-8(BOM)编码**, 用 VS Code / 记事本均可正常查看; `RestartWLAN.bat` 为纯 ASCII, 任何编辑器打开都不会乱码
- 修改网卡状态(省电/重启)需要管理员权限; 脚本会自动请求提权, `-DryRun` 不需要
- 省电模式由驱动决定; 若驱动没有可用的省电属性, 第 4 步会提示并跳过
- 网站检测使用 DNS + TCP 443, 仍会受到代理、防火墙和网站侧策略影响; 它比 ping 更接近网页可达性, 但不是完整的页面加载测试
- 需要 Windows PowerShell 5.1 及以上(Windows 10/11 自带); 脚本使用 `Get-NetIPConfiguration`、`Resolve-DnsName` 等 Windows 自带 cmdlet
