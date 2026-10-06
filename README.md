# RestartWLAN — 网卡重启小工具 v2.0

Windows 下的 PowerShell 小工具: 一键完成「网络信息 → 丢包诊断 → 重启无线网卡 → 复测」, 用于应对无线网卡间歇性丢包的情况(网页时卡时不卡、游戏加速器报网络异常等)。

## 功能流程(七步, 每步 y/N 确认)

1. **网卡信息** — 硬件名称、驱动版本、支持频段、当前连接(SSID/频段/协议/信号)
2. **当前网络信息** — 运行 `ipconfig /all` 并解析无线网卡一节, 整理输出主机名 / 描述 / 物理地址 / IPv4 地址 / 默认网关 / DNS / DHCP / 租约时间; **丢包测试目标自动取自检测到的默认网关**, 不再硬编码, 换网络环境无需改代码
3. **丢包测试(前)** — 向网关发 20 个包统计丢包, 随后测 8 个国内网站(baidu / bilibili / qq / taobao / 163 / jd / aliyun / douyin)各 4 包; 若链路 0 丢包但有网站不通, 会给出可能原因分析(DNS 解析失败 / 网站禁 ping / 运营商异常 / 安全软件拦截等)
4. **省电模式切换(可选)**
5. **重启网卡**
6. **等待 WiFi 重连**
7. **丢包测试(后)** — 复测丢包并复测网站连通; 若重启后仍丢包, 会建议使用专业网络诊断工具或寻求专业技术支持

## 使用方法

下载`RestartWLAN.bat`和`RestartWLAN.ps1`文件, 双击 `RestartWLAN.bat`(它来拉起 `RestartWLAN.ps1`)→ 在 UAC 弹窗点「是」→ 按提示输入 y 继续, 回车或 N 随时退出, 结尾按 Enter 关闭窗口。

也可以在命令行直接执行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
```

## 注意事项

- **`RestartWLAN.ps1` 为 UTF-8(BOM)编码**, 用 VS Code / 记事本均可正常查看; `RestartWLAN.bat` 为纯 ASCII, 任何编辑器打开都不会乱码
- 只重启名为 WLAN 的无线网卡; 需要管理员权限(脚本会自动请求提权)
- 无线网卡的「省电 = Auto」模式已知可能会导致丢包, 日常保持「已禁用」即可
- 需要 Windows PowerShell 5.1 及以上(Windows 10/11 自带)
