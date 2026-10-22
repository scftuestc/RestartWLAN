# RestartWLAN — 网卡重启小工具 v4.0

[中文](README.md) | [English](README.en.md)

Windows 下的 PowerShell 小工具：自动诊断网络、重启无线网卡并复测，用于无线网卡间歇性丢包的情况（网页时卡时不卡、游戏加速器报网络异常等）。

## 功能流程（6 个区段，一次动作菜单）

1. **网卡信息** — 自动识别无线网卡（默认名 `WLAN`；默认名不存在时按 `NdisPhysicalMedium` 识别）；显示硬件、驱动、状态、频段、省电模式，以及当前 SSID / 频段 / 协议 / 信号 / RSSI
2. **当前网络信息** — 通过 `Get-NetIPConfiguration` / CIM 读取主机名、描述、MAC、IPv4/掩码、默认网关（IPv4 或 IPv6）、DHCP、租约和 DNS；如果默认路由不在所选网卡上会给出警告
3. **连通性测试（前）** — 自动执行，不需要确认
   - 向默认网关发送 20 个 Ping（默认间隔 500ms），统计丢包、平均/最大 RTT 和波动
   - 对 8 个国内网站做 DNS 解析 + TCP 443 握手（最多尝试 3 条 A 记录；没有 A 记录时尝试 AAAA）
   - 网关 100% 不响应 ICMP 但网站可达时，会标记为“ICMP 被拦截”，不误判为网卡丢包
   - 没有默认网关时跳过丢包测试，但继续网站测试，仍可重启网卡
4. **选择操作** — 主流程只在这里输入一次（选 `[p]` 后会再选一次省电动作），回车默认取消：

   ```
   [d] 禁用省电并重启网卡（推荐；省电已是禁用时只重启）
   [r] 仅重启网卡
   [p] 仅处理省电模式 → [d] 禁用 / [a] 恢复 Auto（测试）/ [k] 保持
   [n] 取消
   ```

   驱动没有省电属性时隐藏 `[p]`，`[d]` 等价于仅重启。`-Yes` 会自动选择 `[d]`；`-DryRun` 不询问、只预览。
5. **等待重连**（仅 `[d]`/`[r]`）— 最多 45 秒；等待网卡 `Up` 且网关可达。网关禁 ICMP 时用 TCP 443 对照探测；没有网关时也用 TCP 443 判断外网是否恢复。每 5 秒输出一次进度，超时会说明原因。
6. **后测与汇总**（仅 `[d]`/`[r]`）— 复测丢包和网站，自动更新网关，输出重启前后对比和结论。确认丢包、网站不可达或重启失败时退出码为 1。

## 使用方法

下载 `RestartWLAN.bat` 和 `RestartWLAN.ps1`，双击 `RestartWLAN.bat` → 在 UAC 弹窗点「是」→ 在动作菜单中选择（回车取消）→ 结尾按 Enter 关闭窗口。

命令行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
```

只读演练（不修改省电、不重启网卡、不需要管理员；结尾仍可按 Enter 关闭，或用 `-NoPause` 跳过）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -DryRun
```

英文界面：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -Lang en
RestartWLAN.bat -Lang en
```

批处理会透传参数，例如 `RestartWLAN.bat -DryRun`、`RestartWLAN.bat -Lang en -NoPause`。

## 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-Adapter` | `WLAN` | 指定网卡名；默认名不存在时自动识别无线网卡；有多块无线网卡时需显式指定 |
| `-PingCount` | `20` | 丢包测试包数（1-200） |
| `-PingIntervalMs` | `500` | 包间隔毫秒（10-5000） |
| `-Lang` / `-Language` | `auto` | 界面语言：`auto`、`zh`、`en` |
| `-Yes` | 关 | 自动选择推荐动作 `[d]`；不询问，也不暂停 |
| `-NoPause` | 关 | 跳过结尾 Enter |
| `-DryRun` | 关 | 只读演练：零确认、不写设置、不重启；默认不写日志 |
| `-NoLog` | 关 | 不写日志（优先于 `-Log`） |
| `-Log` | 关 | 即使在 DryRun 下也写日志 |
| `-NoExitSession` | 关 | 在已有 PowerShell 会话中运行时不关闭会话 |
| `-SiteTimeoutMs` | `3000` | 单条网站 IP 的 TCP 超时（500-15000ms） |
| `-ReconnectTimeoutSec` | `45` | 重启后等待重连的秒数（10-300） |
| `-NoElevate` | 关 | 跳过自动提权；非管理员时自动进入只读模式 |

## 语言切换

- `-Lang auto`（默认）跟随 Windows **显示语言**（CurrentUICulture）：`zh*` 使用简体中文，其他使用英文
- `-Lang zh` / `-Lang en` 可强制覆盖；`RestartWLAN.bat -Lang en` 也有效
- 只翻译工具自己的界面、提示和日志。SSID、驱动显示值、`Up`/`Disconnected`、`Auto` 等系统/驱动返回值保留原样；已知状态和已知省电值会在显示时加本地化注解或映射
- 提权时会把已解析的 `zh`/`en` 传给子进程，不会在 UAC 后跳回系统语言

## 诊断方式与边界

- **丢包**：Ping 默认网关；如果网关 100% 不响应 ICMP 但网站可达，会认为更像是路由器禁 ping，而不是网卡丢失。仍可能把“网关限速 ICMP”误判为 ICMP 被拦截，结论会使用“更像/可能”的措辞
- **网站**：DNS 解析 + TCP 443 握手，不是完整页面加载；代理、强制门户或网站侧策略仍可能造成误判。非中国大陆网络可能大面积失败
- **IPv6**：网关优先 IPv4，没有 IPv4 时尝试 IPv6；网站优先 A 记录，仅在完全没有 A 记录时尝试 AAAA
- **省电**：使用驱动提供的 `ValidDisplayValues`，并优先按 `ValidRegistryValues` 映射写入；设置时不重启网卡（`-NoRestart`），由第 5 步统一重启。已是目标值时不会自动切到另一个值
- **非无线网卡**：显式用 `-Adapter` 选择以太网等适配器时会跳过 SSID/信号/省电相关检测，只重启所选适配器

## 权限与模式

- 修改省电或重启网卡需要管理员权限；默认会自动请求提权。原窗口会等待提权进程结束并传回退出码
- `-DryRun`：不需要管理员，零确认，只显示“将禁用省电 / 将重启网卡”等计划；如果前测有丢包或网站失败，退出码为 1
- `-NoElevate`：跳过提权。非管理员时会自动进入只读模式，只显示诊断结果；`-NoElevate -Yes` 在非管理员下会以退出码 2 结束
- `-Yes`：自动选择 `[d]`，不询问，也不暂停，适合管理员环境下的自动化；非管理员请先用 `-DryRun` 或让它自提权
- 非交互环境（stdin 重定向/无控制台）如果没有 `-Yes` 或 `-DryRun`，会直接以退出码 2 结束，不会卡在输入
- 在已有 PowerShell 会话中直接 `.\RestartWLAN.ps1` 且没有 `-NoExitSession` 时，脚本结束会关闭该会话；建议用 BAT / `powershell -File`，或加 `-NoExitSession`

## 日志与退出码

- 进入主流程后，每次运行会尝试记录到 `%LOCALAPPDATA%\RestartWLAN\logs\RestartWLAN_日期_时间.log`，保留最近 20 个；结尾会打印路径
- DryRun 默认不写日志；`-Log` 可强制写；`-NoLog` 优先
- 日志开头包含 `version / lang / ui / culture / admin / adapter / dryrun / readonly` 元数据；正文跟随界面语言
- 日志会记录主机名、用户名、SSID、MAC、IP、网关、DNS 等信息；共享电脑上可用 `-NoLog`
- 退出码：
  - `0`：正常完成、用户取消，或 DryRun/只读模式检测正常
  - `1`：确认丢包、网站不可达、重启失败、省电写入失败，或 DryRun/只读模式发现问题
  - `2`：非交互且未指定 `-Yes`/`-DryRun`，或非管理员使用 `-NoElevate -Yes`

## 注意事项

- **`RestartWLAN.ps1` 为 UTF-8(BOM) 编码**；`RestartWLAN.bat` 为纯 ASCII，两个文件需放在同一目录
- 需要 Windows PowerShell 5.1 及以上（Windows 10/11 自带）
- 省电属性因驱动而异；优先使用 `LowPowerEnable`，也支持名称匹配（省电/节能/Power Saving）。找不到属性时会跳过省电操作
- 网站列表内置 8 个国内站点；暂不支持自定义列表、WLAN 服务/飞行模式诊断或 TLS/HTTP 页面级验证
- 重启网卡会短暂断网；实际执行前请确认当前没有重要网络任务
