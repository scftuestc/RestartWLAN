# RestartWLAN — WLAN Restart Tool v4.0

[中文](README.md) | [English](README.en.md)

A small Windows PowerShell tool that diagnoses the network, restarts the wireless adapter, and retests. It is intended for intermittent Wi-Fi packet loss (web pages that sometimes stall, game accelerators reporting network errors, and similar symptoms).

## Flow (6 sections, one action menu)

1. **Adapter information** — detects the wireless adapter automatically (default name `WLAN`; if that name does not exist, it uses `NdisPhysicalMedium`). Shows hardware, driver, status, supported bands, power-saving mode, and the current SSID / band / radio type / signal / RSSI.
2. **Current network information** — reads host name, description, MAC, IPv4/mask, default gateway (IPv4 or IPv6), DHCP, lease, and DNS via `Get-NetIPConfiguration` / CIM. Warns if the default route does not use the selected adapter.
3. **Connectivity test (before)** — runs automatically, no confirmation:
   - Sends 20 pings to the default gateway (default 500 ms interval) and reports packet loss, average/max RTT, and jitter.
   - Resolves DNS and performs a TCP 443 handshake for 8 China-based sites (tries up to three A records; falls back to AAAA only when no A record exists).
   - If the gateway drops 100% of ICMP but sites are reachable, the tool treats it as ICMP filtering rather than adapter loss.
   - If no default gateway exists, the loss test is skipped, but the site test and adapter restart remain available.
4. **Choose an action** — the main flow asks for input only here (choosing `[p]` opens one more power-saving prompt); Enter cancels:

   ```
   [d] Disable power saving and restart adapter (recommended; restart only if already disabled)
   [r] Restart adapter only
   [p] Power saving only -> [d] Disable / [a] Restore Auto (test) / [k] Keep
   [n] Cancel
   ```

   If the driver reports no power-saving property, `[p]` is hidden and `[d]` becomes restart-only. `-Yes` selects `[d]` automatically; `-DryRun` asks nothing and only previews.
5. **Wait for reconnection** (only `[d]`/`[r]`) — up to 45 seconds; waits for the adapter to be `Up` and the gateway to be reachable. If the gateway blocks ICMP, a TCP 443 control probe is used; if no gateway exists, TCP 443 is used to check internet reachability. Progress is printed every 5 seconds, and timeouts explain the missing condition.
6. **Post-test and summary** (only `[d]`/`[r]`) — retests loss and sites, updates the gateway if it changed, and prints before/after results and a conclusion. Confirmed packet loss, unreachable sites, or a restart failure returns exit code 1.

## Usage

Download `RestartWLAN.bat` and `RestartWLAN.ps1`, then double-click `RestartWLAN.bat` -> confirm the UAC prompt -> choose an action (Enter cancels) -> press Enter at the end to close.

Command line:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1
```

Read-only dry run (no power-saving change, no restart, no administrator needed; the final Enter can be skipped with `-NoPause`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -DryRun
```

Force English or Chinese UI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -Lang en
powershell -NoProfile -ExecutionPolicy Bypass -File RestartWLAN.ps1 -Lang zh
RestartWLAN.bat -Lang en
```

The batch file forwards all arguments, for example `RestartWLAN.bat -DryRun` or `RestartWLAN.bat -Lang en -NoPause`.

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-Adapter` | `WLAN` | Adapter name; if the default name does not exist, a wireless adapter is detected automatically. Required when multiple wireless adapters exist |
| `-PingCount` | `20` | Number of loss-test pings (1-200) |
| `-PingIntervalMs` | `500` | Interval between pings in ms (10-5000) |
| `-Lang` / `-Language` | `auto` | UI language: `auto`, `zh`, or `en` |
| `-Yes` | off | Selects the recommended action `[d]`; no prompts and no pause |
| `-NoPause` | off | Skips the final Enter |
| `-DryRun` | off | Read-only preview: no action prompts, no settings changed, no restart; no log by default |
| `-NoLog` | off | Disables logging (takes precedence over `-Log`) |
| `-Log` | off | Writes a log even in DryRun |
| `-NoExitSession` | off | Does not close an existing PowerShell session when the script ends |
| `-SiteTimeoutMs` | `3000` | TCP timeout per site IP (500-15000 ms) |
| `-ReconnectTimeoutSec` | `45` | Reconnection wait in seconds (10-300) |
| `-NoElevate` | off | Skips self-elevation; non-admin sessions automatically become read-only |

## Language switching

- `-Lang auto` (default) follows the Windows **display language** (`CurrentUICulture`): `zh*` uses Simplified Chinese; everything else uses English.
- `-Lang zh` / `-Lang en` force a language; `RestartWLAN.bat -Lang en` works as well.
- Only the tool's own UI, prompts, and logs are translated. SSIDs, driver display values, `Up` / `Disconnected`, `Auto`, and other OS/driver values remain as reported; known statuses and known power values are annotated or mapped for display.
- When elevating, the resolved `zh` / `en` is passed to the child process so the UI does not jump back to the system language after UAC.

## Diagnosis notes and limits

- **Packet loss**: pings the default gateway. If the gateway drops 100% of ICMP while sites are reachable, the tool treats it as ICMP filtering rather than adapter loss. A gateway that rate-limits ICMP can still be misread; conclusions use cautious wording such as "looks like" or "possibly".
- **Sites**: DNS resolution plus a TCP 443 handshake, not a full page load. Proxies, captive portals, or site-side policy can still produce false results. A non-China network may see widespread failures.
- **IPv6**: prefers an IPv4 gateway and falls back to IPv6; site tests prefer A records and only try AAAA when no A record exists.
- **Power saving**: uses the driver's `ValidDisplayValues` and prefers a matching `ValidRegistryValues` entry. The setting is written with `-NoRestart`; the restart step applies it. If the current value already matches the target, the tool does not switch to another value.
- **Non-WLAN adapters**: explicitly selecting Ethernet or another adapter with `-Adapter` skips SSID/signal/power-saving checks and restarts only that adapter.

## Permissions and modes

- Changing power saving or restarting an adapter requires administrator rights. The script requests elevation automatically; the original window waits for the elevated process and propagates its exit code.
- `-DryRun`: no administrator needed, no action prompts, only previews "would disable power saving / would restart adapter". If the pre-test finds loss or site failures, the exit code is 1.
- `-NoElevate`: skips elevation. A non-admin session becomes read-only and only shows diagnostics. `-NoElevate -Yes` in a non-admin session exits with code 2.
- `-Yes`: selects `[d]`, does not prompt, and does not pause. Intended for elevated/automated use; non-admin users should use `-DryRun` or allow self-elevation.
- A non-interactive session (redirected stdin / no console) without `-Yes` or `-DryRun` exits with code 2 instead of waiting for input.
- Running `.\RestartWLAN.ps1` inside an existing PowerShell session without `-NoExitSession` closes that session when the script exits. Prefer the BAT file or `powershell -File`, or pass `-NoExitSession`.

## Logs and exit codes

- After the main flow starts, each run attempts to write `%LOCALAPPDATA%\RestartWLAN\logs\RestartWLAN_<date>_<time>.log` and keeps the 20 most recent files. The path is printed at the end.
- DryRun does not write a log by default; `-Log` forces it; `-NoLog` takes precedence.
- The log header records `version / lang / ui / culture / admin / adapter / dryrun / readonly`; the body follows the selected UI language.
- Logs include the host name, user name, SSID, MAC, IP, gateway, DNS, and similar details. Use `-NoLog` on shared machines.
- Exit codes:
  - `0`: normal completion, user canceled, or a healthy DryRun/read-only check
  - `1`: confirmed packet loss, unreachable sites, restart failure, power-saving write failure, or a problematic DryRun/read-only check
  - `2`: non-interactive without `-Yes`/`-DryRun`, or non-admin `-NoElevate -Yes`

## Notes

- **`RestartWLAN.ps1` is UTF-8 with BOM**; `RestartWLAN.bat` is plain ASCII. Keep both files in the same directory.
- Requires Windows PowerShell 5.1 or later (included with Windows 10/11).
- Power-saving properties vary by driver. The tool prefers `LowPowerEnable` and also matches names such as "Power Saving"; if no property exists, the power-saving step is skipped.
- The built-in site list contains eight China-based sites. Custom site lists, WLAN-service/airplane-mode diagnosis, and TLS/HTTP page-level validation are not included.
- Restarting the adapter briefly disconnects the network; make sure no important network task is running before executing it.
