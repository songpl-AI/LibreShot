# 功能后内存拆分（2026-09-26）

## 口径

正式版 `/Applications/LibreShot.app` 为 1.3.0 (12)，进程 PID 2039 从 9 月 25 日 09:24 运行至本次检查。`vmmap -summary` 的 `physical footprint` 在试用后约 183.3 MiB，历史峰值 359.2 MiB；隔夜约 172.6 MiB。安装时约一分钟的冷启动值 16.5 MiB，并非同工况对照。`heap` 显示大量 Apple Espresso/TextRecognition 对象，但未启用分配栈记录，不能将所有未分类 malloc 都归因于 OCR。

新增 `tests/FeatureMemoryProfile.swift` 和 `tests/run-feature-memory-profile.sh`，使用生产 OCR、Translation、原图翻译模型/窗口、渲染器及长图拼接器。每个场景在独立优化编译进程运行，以 `task_info(TASK_VM_INFO).phys_footprint` 测操作点及作用域释放后闲置 1/5/15/60 秒。输入为 1200×800 文字图或 13 帧 1400×800 RGBA 长图，未读取用户屏幕或剪贴板。运行示例：`bash tests/run-feature-memory-profile.sh ocr translation image-translation translation-window-loop image-render long`。

| 独立场景 | 基线 | 操作中采样点 | 60 秒闲置 | 相对基线 |
| --- | ---: | ---: | ---: | ---: |
| OCR 5 次 | 5.5 | 第 1 次 110.0；第 5 次 125.7 | 53.8 | +48.3 |
| 纯文本英译中 3 次 | 5.5 | 7.4 | 7.2 | +1.7 |
| OCR→原图翻译窗口→翻译→重绘→关窗 | 5.4 | OCR 后 109.0；窗口后 131.6；重绘后 168.9 | 82.5 | +77.1 |
| 只创建/关闭原图翻译窗口 1 次 | 5.5 | 48.7 | 18.9 | +13.4 |
| 只创建/关闭原图翻译窗口 10 次 | 5.5 | 第 1 次 19.2；第 10 次 20.4 | 20.4 | +14.9 |
| 只覆写渲染译文图 | 5.4 | 37.7 | 8.0 | +2.6 |
| 长图拼接 13 帧并生成结果 | 5.5 | 34.8 | 6.5 | +1.0 |

既有 `tests/run-memory-checks.sh` 同进程对照：20 次编辑/复制后闲置 60 秒 97.3 MiB，再做 5 次 OCR 后闲置 60 秒 139.2 MiB，OCR 净增 41.9 MiB。第 2–5 次 OCR 与 10 次窗口创建没有按次数线性叠加。以上采样点不是连续采样所得真实瞬时峰值；场景之间不是严格可相加的内存账本。

## 判断

- OCR 是主进程里最明显的持久增量。应用源码每次新建 `VNRecognizeTextRequest` 并在工作队列的 autorelease pool 内执行，没有自行保存识别模型；实际堆中的 Espresso/TextRecognition 对象和首次跃升、重复趋稳的模式，支持系统 Vision/ML 运行时保留模型或分配池的解释，但不能证明 Apple 内部的具体淘汰策略。
- 纯文本翻译对主进程增量很小。另有系统 `translationd` 和 `TranslationAPISupportExtension` 在 9 月 25 日约 09:30 启动；9 月 26 日检查时 physical footprint 分别为 63.4 和 17.8 MiB。启动时间与本次试用相近，但它们是系统共享进程，不应全部算作 LibreShot 独占，也不包含在应用自身的 172.6 MiB 内。
- 原图翻译窗口的首次初始化留约 13 MiB；十次循环仅再多约 1.5 MiB。译文覆写渲染单独留约 2.6 MiB。窗口关闭时生产代码取消任务并移除内容视图，未见每次关闭都保留整张原图的线性增长。
- 长图拼接器释放结果后接近基线。该探针没有走真实 `ScreenCaptureKit` 流、遮罩层、最终编辑器或系统剪贴板，不能据此排除这些环节造成的完整应用峰值/留存。
- `leaks` 对当前 hardened runtime 正式版提示不可完整调试，只报告约 19 KiB 可见泄漏；这不能证明 173 MiB 中不存在未释放缓冲。

下一步若要解释正式版剩余占用，需在可分析的开发构建中用相同尺寸图片和真实窗口链路，按“截图、关闭编辑器、长图完成并关闭、OCR、文本翻译、原图翻译并关闭”记录进程及 `translationd` 的操作前/中/后 1/5/15/60 秒 footprint，并用 Allocations/MallocStackLogging 定位大块非对象分配。普通 log 只能标记阶段，不能代替内存采样。先检查完整应用的截图缓冲、剪贴板与编辑器持有，再考虑将 OCR 移到按需退出的 helper；后者可能降低主进程闲置值，但不能保证降低所有进程的合计峰值。

2026-09-26 后续：已加入只在 Debug 且显式设置 `LIBRESHOT_MEMORY_TRACE` 时生效的阶段记录，并构建独立诊断包。获得首版诊断包的屏幕录制授权后，真实 OCR/翻译路径显示重复 OCR 关窗后内存趋稳，但真实长截图流在只有首帧被接受的情况下持续上涨；限时复测与修补验证状态见 [live-memory-profile.md](live-memory-profile.md)。
