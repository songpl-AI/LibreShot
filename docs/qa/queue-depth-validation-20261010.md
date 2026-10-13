# queueDepth 普通截图 A/B 验证

日期：2026-10-10。测试对象为当时 `/Applications/LibreShot.app` 的 1.3.10 (32) 本地实验包，不是最终 r4。通过 `LIBRESHOT_STREAM_QUEUE_DEPTH` 在进程启动前设置 `SCStreamConfiguration.queueDepth`，未设置时仍使用 SDK 默认值 8。

## 固定条件

- 同一 Apple Silicon/macOS 26.6.2 环境、同一显示器和同一公开桌面区域。
- 目标选区为屏幕坐标约 `(700,300)–(1200,650)`；8/1 两轮实际输出 500×350，2 这一轮实际输出 500×266，因此不是严格等像素 A/B。
- 每个深度均退出并重新启动应用，使用新 PID，避免历史 peak 跨轮累积。
- `Physical footprint` 取 `vmmap -summary`，RSS 取 `ps`；活动监视器“内存”列未在本轮同 PID、同时间核对，不能直接称作 RSS。

## 结果

| queueDepth | PID | 截图输出 | 截图后 footprint | 进程历史 peak | 截图后 graphics resident |
|---:|---:|---|---:|---:|---:|
| 8 | 57506 | `~/Downloads/Screenshot 2026-10-10 12.05.36.png` | 49.3 MiB | 87.6 MiB | 464 KiB |
| 2 | 52671 | `~/Downloads/Screenshot 2026-10-10 12.02.13.png`（500×266） | 47.0 MiB | 86.6 MiB | 464 KiB |
| 1 | 63193 | `~/Downloads/Screenshot 2026-10-10 12.07.58.png` | 48.8 MiB | 87.4 MiB | 48 KiB |

原始 `vmmap`：

- `dist/queue-depth-validation-20261010/q8-fresh/vmmap-after.txt`
- `dist/queue-depth-validation-20261010/q2/vmmap-after.txt`
- `dist/queue-depth-validation-20261010/q1/vmmap-after.txt`

## 判断

普通单帧截图中，`queueDepth=1/2` 相比默认 8 没有测出稳定的内存收益；三轮历史 peak 相差约 1 MiB。但每种只跑了一轮，且深度 2 的实际输出像素不同，不能据此证明等价或做统计显著性判断。截图结束后三轮 graphics backing 都回落到 KiB 级，本轮没有发现通过队列深度降低长期驻留的证据。

这项实验不能外推到长截图：长截图以约 100 ms 的间隔持续处理帧，下一步仍需单独验证 `queueDepth=2` 和 `1` 的帧数、拼接高度、丢帧与峰值。当前结论是普通截图不应为了理论上的队列节省而默认改成 1；若要压低约 40 MiB 的瞬时 graphics 峰值，应继续评估一次性截图 API 或 overlay 关闭后的短捕获。
