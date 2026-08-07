# Mac Low Latency RDP

面向 Apple Silicon Mac 的低延迟 RDP 实验客户端。原生 SwiftUI 负责配置、Keychain 凭据和诊断，FreeRDP 3 的 SDL3 客户端负责完整 RDP/NLA、H.264、输入、剪贴板与音频。

## 当前基线

- 目标：用户配置的 Windows 主机（默认示例为 `windows-host.example:3389`）
- v0.9 低延迟动画基线：4096 × 1716、Windows 200% 缩放、AVC420、全屏、静音、局域网模式
- FreeRDP 3.30 客户端的 Multitransport 回调会拒绝 UDP，本客户端因此固定 `-multitransport`，不再显示无效 UDP 开关
- 证书策略：TOFU（首次信任，后续校验证书）
- A/B 参数：异步通道、SDL Metal VSync 与 Frame ACK 可独立切换；SDL 当前强制禁用的 async-update 不再误导性开启
- 全屏策略：使用原生 4K 像素并让 Windows 做 200% 桌面缩放，保持 2K 的视觉大小但不拉伸位图
- 网络诊断：同时测量到默认网关和 Windows 的丢包、均值与峰值，并显示 Wi‑Fi 频段/信道
- 4K 视频：用户 A/B 实测明显落后于 Microsoft Windows App；界面会直接建议改用 Windows App，客户端仅保留 3K 视频兼容预设
- 单应用：Windows Pro 上 `/app`/RAIL 和 `/shell` 均实测黑屏，已从界面停用。参数生成代码保留，待 Windows Server RDS、Azure Virtual Desktop 或 Windows 365 环境验证后再开放
- 外网：连接参数可选择 `auto` 或 `wan` 网络提示；3389 不应直接暴露到公网
- Windows 只读检查：应用内可复制 PowerShell，或运行 `windows/Inspect-RDPVideo.ps1`，核对硬编事件与 UDP 3389
- Windows 硬编 A/B：`windows/Enable-RDPVideoHardware.ps1` 应用三项图形策略并在 `C:\ProgramData\MacLowLatencyRDP` 生成逐项备份；`Restore-RDPVideoHardware.ps1` 恢复原值
- 密码存储：macOS Keychain；启动时所有参数经 `/args-from:stdin` 传给 FreeRDP，密码不进入进程参数

## 构建

```bash
brew install freerdp
./scripts/build_freerdp_videotoolbox.sh
swift test
./scripts/build_app.sh
./scripts/install_app.sh
open "dist/Mac Low Latency RDP.app"
```

构建产物位于 `dist/Mac Low Latency RDP.app`。

`build_freerdp_videotoolbox.sh` 会校验 FreeRDP 3.30.0 官方源码的 SHA-256，随后构建 M1/arm64 专用版本并启用实验性的 Apple VideoToolbox H.264 硬件解码。客户端会优先选择该版本；Homebrew 版仍保留在系统中，便于诊断时手动回退。

运行命令行 A/B 脚本前，通过环境变量提供本机信息，仓库不保存用户名或主机地址：

```bash
MACRDP_HOST=windows-host.example \
MACRDP_USERNAME='windows-user@example.com' \
./scripts/run_freerdp_ab.sh quality desktop
```

## 预设

| 预设 | 分辨率 | 图形 | Frame ACK | VSync | 音频 | 用途 |
|---|---:|---|---:|---|---|---|
| 4K 日常（推荐） | 4096 × 1716 | 允许 AVC444v2 | 2 | 开 | 开 | 清晰文字与交互动画；两个旧 4K 模式已合并 |
| 3K 流畅 / 外网 | 3072 × 1288 | 禁用 AVC444；服务器选择 surface codec | 2 | 开 | 开 | 像素减少约 44%，用于外网或需要真正减负时 |

旧“低延迟动画”和“4K 清晰文字”的短时 A/B 中，用户目视无区别，客户端平均 CPU 分别为 26.4% 与 26.8%，平均 RSS 为 613 MB 与 595 MB；差异不足以支撑两个面向用户的预设。旧配置仍可解码，但不再显示为独立按钮。

## 客户端分工

- Mac Low Latency RDP：交互动画、清晰文字、办公和外网 RDP。
- Microsoft Windows App：当前这台 Mac/Windows 组合上的 4K 视频。
- Moonlight：游戏、高帧率视频和最低动态画面延迟。

## 安全说明

客户端不会把密码放进命令行。复制按钮产生的命令也不含密码。首次连接会记录 Windows 主机证书；如果证书之后变化，FreeRDP 会拒绝连接并在日志中说明。
