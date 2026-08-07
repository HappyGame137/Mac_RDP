# RDP 上游更新监控状态

此文件供 Codex 定时任务去重。只有一手来源出现与本项目实质相关的新变化时才更新“已通知”记录。

## 初始基线（2026-08-07）

- 本地 FreeRDP：3.30.0，自建 VideoToolbox 版本。
- 本地 Microsoft Remote Desktop / Windows App：11.3.9（build 3061）。
- 本地 Moonlight：6.1.0。
- Mac Low Latency RDP：0.9.2（build 12）。
- FreeRDP 客户端 UDP：3.30.0 的 Multitransport 客户端回调仍以 `E_ABORT` 拒绝，项目固定使用 TCP。
- RemoteApp：Windows Pro + FreeRDP SDL3 的 RAIL 与 alternate shell 均实测黑屏，界面已停用。
- 4K：VideoToolbox 硬解可用，但 FreeRDP/SDL 的 CPU/BGRA 回传及 Metal 上传路径明显落后于 Windows App 的用户实测。

## 已通知更新

暂无。
