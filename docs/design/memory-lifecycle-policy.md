# 图像会话与内存策略

日期：2026-10-11。适用于截图、OCR、图片翻译与长截图。目标是在保证可编辑、可重试和像素正确的前提下，减少同时存活的像素与会话结束后的无用引用；不把固定 20–30 MiB 当作跨系统、跨屏幕配置的保证。

## 生命周期优先

| 资源 | 保留期限 | 释放边界 |
| --- | --- | --- |
| 当前编辑原图、译图、识别区域 | 用户仍在编辑或需要取消后重试 | 移除翻译、改变选区、关闭编辑/翻译窗口、结束截图会话 |
| 翻译取消后的原图和区域 | 当前会话可重试 | `cancel()` 保留，`dismiss()` 永久清空 |
| 布局变化中的翻译状态 | 同一会话在工具条上下布局之间移动 | 父模型持有唯一翻译 model；短暂 `suspend()` / `activate()`，不等同关闭 |
| OCR worker 及传输暂存 | 一次识别任务 | 等待子进程结束并回收；取消时终止，始终串行 |
| 长截图条带及临时文件 | 拼接与最终渲染 | 完成输出或失败/取消后撤会话 owner，清临时存储 |
| 可再生缓存 | 有可测量的复用价值才引入 | 明确字节预算；必要时自管淘汰顺序，压力通知只作补充 |

原始截图不作跨会话热缓存：下一次截图通常是新的屏幕内容，保留旧像素的复用价值低。当前没有业务 LRU、固定闲置清理计时器或内存压力监听器。无需为图片翻译生命周期问题新增常驻监控 helper。

目前长截图条带内存预算 32 MiB、单帧上限 64 MiB、最终输出上限 128 MiB，分别约束阶段数据；它们不是总进程 footprint 上限。按实际 `bytesPerRow × height` 计量原始位图，不能用压缩后的 PNG 文件大小估算处理内存。

## 系统回收的边界

ARC 在最后强引用撤掉后销毁对象。闭包、异步调用及裁剪图的 provider 链都可能延长大像素 allocation 的生命周期。会话结束必须主动撤掉自身原图/译图引用，不能等待系统识别闲置业务对象。过期请求和排版版本必须拦截迟到结果，防止已关闭会话被重新填充。

`autoreleasepool` 用于同步图像循环中的延后释放临时对象，不能清理仍被强引用持有的原图。malloc 释放后的空洞可供复用，部分页面可能仍因活对象/碎片保留。系统还会管理 clean 文件页、可丢弃页、压缩及换出；对象释放与 physical footprint 下降不是同一个事件。

这些机制不等于严格 LRU，也没有固定的闲置倒计时。即使使用 `NSCache`，Apple 也不保证严格 cost 上限或淘汰顺序。iOS/iPadOS 还可能在压力下终止应用，告警只是尽力发送，不能等告警才结束已完成会话；部分支持设备的 iPadOS 有 Virtual Memory Swap，不能笼统说所有 iOS/iPadOS 均无换出。

外部 helper 不能正常地对主进程仍存活的对象执行 `free`。它可以通过 IPC 请求主程序清理，也可以自己承载重任务并退出。当前 OCR 已采用后一种模式。仅在分配证据证明框架驻留仍是大头、且启动/IPC/像素传输成本可接受时，才考虑扩大进程隔离；系统共享的翻译服务不会因此保证退出。iOS 常规应用不能照搬 macOS 任意子进程的架构。

## 验证顺序

1. 合成素材的 provider release callback 与 weak model/NSImage：保留旧回调和旧 model，真正结束会话后像素仍须释放；正在识别/渲染的工作则在取消并退出后释放输入。
2. 覆盖取消重试、目标语言变化、布局重挂、原图/译图切换、移除翻译、选区变化、保存和关闭；迟到结果不能复活。重复结束多轮，检查对象与像素字节有无阶梯累积。
3. 固定素材、像素格式/stride 和构建模式，先采完整应用自然过程，再运行 heap/leaks。分列主进程、准确 OCR worker 和系统共享服务，记录操作边界、采样最大值及关窗后观察窗；不相加不同时间/不同进程的峰值。
4. 对长图瞬时峰，用 Allocations 与 VM Tracker/分配栈核对同一时刻的位图、图形 surface、首次绘制及编码。不能从结束后的 live heap 恢复已释放瞬时 allocation 的栈。

小 crop 可能共享并保留整屏 provider backing，本次旧安装副本的引用树已有这种关联。若关闭释放修复后，活动会话仍不必要地保留整屏，应单独对比物化独立选区的方案：它会多一次短时复制，需同时验证色彩/alpha/像素和峰值，不能直接视作零成本优化。

## 官方依据

- [Swift ARC](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/)
- [Apple Analyze heap memory](https://developer.apple.com/videos/play/wwdc2024/10173/)
- [Apple Detect and diagnose memory issues](https://developer.apple.com/videos/play/wwdc2021/10180/)
- [NSCache.totalCostLimit](https://developer.apple.com/documentation/foundation/nscache/totalcostlimit)
- [Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings)
- [Jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)
- [iPadOS 支持设备的 Virtual Memory Swap](https://www.apple.com/uk/newsroom/2022/06/ipados-16-takes-the-versatility-of-ipad-even-further/)
- [Apple XPC](https://developer.apple.com/documentation/xpc)
