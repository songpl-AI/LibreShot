# sourceRect r2 实测记录

日期：2026-10-10。测试对象是当时安装副本 `/Applications/LibreShot.app`，版本 1.3.10 (32)，sourceRect r2 候选；不是最终 r4。`Physical footprint` 来自 `vmmap -summary`，RSS 来自 `ps`；活动监视器“内存”列未在本轮同 PID、同时间核对，不能直接称作 RSS。

## 已完成的验证

- 当前安装副本已重新取得“录屏与系统录音”权限，能出现真实截图遮罩。
- 普通路径成功生成并保存 500×350 PNG；文件可解码。
- `LIBRESHOT_DIRECT_REGION_CAPTURE=1` 路径成功生成并保存 500×350 PNG；文件可解码。
- 测试完成后已执行 `launchctl unsetenv LIBRESHOT_DIRECT_REGION_CAPTURE`，并重启 `/Applications/LibreShot.app`。当前环境变量为空，应用回到普通路径。

证据文件：

- 普通路径采样：`dist/sourceRect-r2-validation/A-normal/samples.csv`，峰值 raw 为 `raw/vmmap-0086.txt`。
- direct 路径采样：`dist/sourceRect-r2-validation/B-direct/samples.csv`，峰值 raw 为 `raw/vmmap-0227.txt`。
- 普通路径输出：`~/Downloads/Screenshot 2026-10-10 10.36.15.png`（500×350）。
- direct 路径输出：`~/Downloads/Screenshot 2026-10-10 10.48.36.png`（500×350）。

## 结果

| 路径 | 采样最高 footprint | 进程记录 peak | 峰值 graphics resident | 峰值后采样末值 |
| --- | ---: | ---: | ---: | ---: |
| 普通 | 89.1 MiB | 97.0 MiB | 40.5 MiB | 44.7 MiB |
| direct sourceRect | 92.0 MiB | 92.0 MiB | 40.5 MiB | 48.8 MiB |

峰值 vmmap 的主要行几乎相同：

- 普通：`owned unmapped (graphics)` 41.0M virtual / 40.5M resident，`MALLOC_SMALL` 56.4M / 22.6M resident，`IOAccelerator (graphics)` 3.568M resident。
- direct：`owned unmapped (graphics)` 41.0M virtual / 40.5M resident，`MALLOC_SMALL` 67.5M / 24.9M resident，`IOAccelerator (graphics)` 3.120M resident。

截图结束后两组的 `owned unmapped (graphics)` 都降到约 48 KiB，说明图形 backing 会释放；direct 没有让这个约 40.5 MiB 的主峰消失。两组采样起点和操作期间的前台内容不完全一致，不能把 89.1 与 92.0 MiB 当作严格统计 A/B，也不能据此声称 direct 使内存增加。能够确认的是：当前实现没有测出预期的 80 MiB 级收益。

## 原因判断

`sourceRect` 把输出帧尺寸改成选区大小，但两组仍观察到约 40.5 MiB 的 graphics backing。这与显示器捕获和 overlay 整屏预览有关的解释相符；仅凭 vmmap 分类尚不能精确区分 ScreenCaptureKit、WindowServer 和 overlay 各自的分配。r2 切断了完成回调后 direct 异步任务对整屏 `CGImage` 的引用，但整屏预览在框选阶段已经存在，本轮没有消除整个截图过程的首要峰值。

direct 路径还会在 overlay 关闭后重新读一次屏幕。菜单、动画、视频或倒计时可能与用户框选时看到的冻结帧不同；这条路径不能直接作为默认功能替换。OCR、原图翻译、贴图和图像特效仍走冻结预览。

## 后续建议

1. 保持当前默认路径，暂不打开 `LIBRESHOT_DIRECT_REGION_CAPTURE`。
2. 若继续追求 20–30 MiB 稳定值，下一项实验应优先测 `SCStreamConfiguration.queueDepth` 为 1 或 2，并保持冻结预览语义；当前配置未显式设置它，不能把 SDK 默认值直接当作已分配内存。
3. 若要继续压低约 40.5 MiB graphics 峰值，应实验“overlay 关闭后再启动一次短捕获”或系统静态截图 API，重点观察 `owned unmapped (graphics)` 是否消失，再做 Retina、多屏和动态画面回归。
4. 当前普通路径后续重试曾收到 `SCStreamError -3811`，应把连续启动/停止捕获的竞争单独作为稳定性回归项；本轮没有把该错误归因于内存泄漏。

本记录不提交、不推送、不发布 Release，也不关闭相关 Issue。
