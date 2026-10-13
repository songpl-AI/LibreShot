# 长截图引擎与内存预算

日期：2026-10-11。独立 Swift 实现；[外部源码研究](long-capture-references-20261011.md)固定了参考版本与边界。未引入 OpenCV、FFT/WASM 或移植 GPL 代码。

## 分层

`冻结预览选区 seed + ScreenCaptureKit → LongCaptureFrameAccumulator → LongCaptureStitcher → LongCaptureDocumentStore → editor`

- `LongCaptureStreamGeometry` 将 Cocoa 全局选区转换为显示器局部左上原点的 SCK sourceRect，尺寸仍按旧 integral native-pixel crop 取整。SCK 只产出选区，queueDepth 明确设 3。多屏、分数缩放与边缘裁剪已有离线几何检查，真实 SCK 的尺度/颜色仍须安装验收。
- `LongCaptureInitialFrameSource` 在框选确认时独立复制冻结预览的原始选区像素，保留8bit BGRA/颜色空间，先提交为起始基线，再恢复用户滚动。避免异步采集流首帧已处于顶部回弹造成重复白边或拒绝；随后释放整屏预览与遮罩内容树。若触发截图前页面本来已在动画中，冻结图也可能不稳定，此策略不能检测所有既有动画。
- `LongCaptureStreamService` 串行处理完整帧，pause 不推进前沿；stop 等启动/停止生命周期门及输出队列排空。完成先停止连续流，再用同 filter/config 的有限观察流取得真实最终画面，无并存的两个 capture 流。收尾在2秒观察预算内等待250ms没有新的像素变化，只持有最新真实帧；精确重复和idle不重计时，静态一帧后无后续回调由定时器结束。blank/suspended/stopped明确失败。选中的稳定帧仍要验证连接；持续变化/无完整帧会报错，绝不超时导出旧前缀。250ms是待实际SCK验证的策略参数，不是平台稳定保证；生命周期start/stop本身不承诺2秒内返回。暂停时完成保留暂停位置。取消尊重 teardown 后的 Task 状态。
- `LongCaptureFrameAccumulator` 区分 empty、atFrontier、revisiting、unresolved。只有确认的前沿参与去重；重复未接上的帧不会变成功。完成时 unresolved 抛出错误，不导出不完整的前缀。
- `LongCaptureOverlapMatcher` 在横向采样图上保留全部原始像素行，提供多个正文带的候选；背景 median 仅由变化正文列计算。原有全量行验证和次峰歧义拒绝继续执行。可靠分散正文行界定范围，孤立页头重绘不能把固定页头算作正文。低信息量、周期多解与位移无重叠时拒绝猜接缝。
- `LongCaptureSeamVerifier` 独立核对原像素，而非直接相信灰度得分。固定前缀按零位移核验，只允许最多64像素、小于32×32且源色或目标色一致的局部变化；否则退回全部原始变化行的运动核验，避免稀疏编号文本被排除。移动正文按候选整数位移核验；局部瞬态最多 128 像素、最多两块连通区域、各块小于 64×64 且不超过已验证像素的 1%，接缝前 16 行不允许用重绘容差掩盖。这样可处理旧/新 caret 两个位置，不能掩盖大面积变化或独立滚动面板。
- `LongCaptureDocumentStore` 只接受统一宽度、连续 Y 的独立 sRGB RGBA 条带。分配和写盘全部成功才原子推进前沿；失败不会改高度、前沿或已有内容。最终仅创建一次完整位图并逐条读取绘制。会话成功、失败或取消后释放帧/条带与临时目录，再交付编辑器。

## 固定底栏与回滚

固定底栏是候选而非首对帧永久真值。若原像素完整正文接缝能对齐，优先不裁底部，避免把列表空白裁成底栏。首次确认为真实底栏时，将第一条正文裁切与第一次追加作为一次存储事务，尾栏只保留一份。

后续已确立底栏必须继续证明同一高度和静止像素；增长、缩小或变化不能把旧栏留在正文中。本轮明确拒绝无法证明的动态栏，用户可回到最后接上的位置或重新排除该区域。没有静默部分成功。暂不通过羽化融合隐藏错误接缝。

反向回访只验证已覆盖位置，不移动向下增长的前沿；继续向下时仍相对于最后提交帧核验，避免重复正文或累计漂移。回到确切前沿或有独立结构证据的零位移重绘可以解除 unresolved 状态。

当前单frontier仍有已知限制：向下多屏后，深回访至与frontier没有足够重叠的位置会拒绝，即使画面属于已经捕获的文档。可靠支持它需要验证过的观察游标与文档位置分离，并按strip核对已捕获内容；不能直接更新前沿图，否则旧行会重复追加。本轮起始/收尾修复不声称解决此限制。

## 内存和临时文件

默认预算以字节计，非任意像素高度或整进程内存承诺：

| 项目 | 默认预算 | 含义 |
| --- | ---: | --- |
| 常驻文档条带 | 32 MiB | 超出预算的旧条带无损写入会话临时目录 |
| 单帧 RGBA | 64 MiB | 在归一化分配前拒绝超大帧 |
| 最终 RGBA 输出 | 128 MiB | 防止编辑位图无限增长；达到限制明确报错 |
| 条带数量 | 20,000 | 限制大量极小增量的元数据成本 |
| capture queueDepth | 3 | SCK 选区表面数量；不是 RSS 上限 |

临时目录为随机会话路径、权限 0700，条带为独立 RGBA 文件。写入事务失败清理新增文件，结束/取消释放目录；落盘内容不会加入诊断日志。异常进程退出的目录可能残留于系统临时目录，不能承诺崩溃后立即清理。磁盘容量不足会报存储错误而非滚太快。

原始匹配前沿最多保留一帧；正在处理的输入另占一帧。精确去重和 stitcher 引用的是同一已接受图，不复制两份。进度通知只合并最新值，MainActor 阻塞时最多等待一个 UI 发布任务。取消和结束不保留 pending replay，不用修改时间戳假装新观察。

长图的最终编辑位图无法消除：1600×10000×4 约 61 MiB，除此以外还有 AppKit、SCK、匹配描述、导出编码及分配器驻留。用户的 20–30 MiB 仅是期望，不能为追数字破坏画质/功能。

### 无标注长图导出

`ImageEditorExportRenderer` 在提交文字后，按原 `base ?? imageForExport` 和文档逻辑尺寸包装背景。只有来源明确、原图/preview/完整选区没有改变、没有标注/手势/文字/翻译会话，且动作为保存、另存、复制或保存并复制，才能优化。普通截图、译图及其他动作继续完整合成。

- 精确 1x/2x、单一规范 sRGB RGBA8 位图且背景包装保持同一 CGImage 时，共享原像素，不产生合成位图。
- 自由框选可能因 native crop 向外取整而产生非整数比例。新增独立 `ImageEditorLongCaptureSource` 仅证明文档来源及身份；它不证明背景包装保持原像素。这条路径保留原 `bitmapRep` 规范化，只省去随后无标注的整图 CGContext 绘制。
- 特殊表示、身份/格式变化或编辑状态继续原合成。不能通过放宽尺寸容差、改变逻辑尺寸或忽略颜色差异来增加命中率。

规范化仍使用真实包装后的背景：AppKit 对小数逻辑尺寸可能重新选择表示、重采样甚至改变输出物理尺寸。规范化原 Store 图或直接返回原图不能保持旧导出结果。圆角、PNG/TIFF 编码、DPI 与保存/复制生命周期保持原流程。新增来源只持有共享 CGImage，关闭文档时与原图及模型一起清理，不缓存规范化输出。`LIBRESHOT_LONG_CAPTURE_TRACE=1` 的 `editor-export-route` 事件区分复用、单次规范化和完整合成；日志不包含图像内容。

## 验证入口与范围

- `tests/run-long-capture-engine-checks.sh`：完整像素输出、1/2/120px 位移、反向回访、尾部重绘、周期/缺口、动态栏安全。
- `tests/run-long-capture-redraw-checks.sh`：原有 95 项真运动/稀疏运动/重绘回归。
- `tests/run-long-capture-seam-checks.sh`：固定页头/纹理侧栏、双 caret、原像素接缝、动态栏/回访安全。
- `tests/run-long-capture-matcher-boundary-checks.sh`：最小独立纹理区域滚动、双面板冲突与页头重绘安全。
- `tests/run-long-capture-store-checks.sh`：条带无损、spill/reload、事务回滚、尺寸预算、整数溢出、清理。
- `tests/run-long-capture-integration-memory-checks.sh`：引擎实际使用 store、强制 spill 输出正确、历史 raw provider 释放、上限失败/恢复。
- `tests/run-long-capture-stream-geometry-checks.sh`：多屏与 scale 坐标、生成像素与旧裁剪一致。
- `tests/run-long-capture-initial-baseline-checks.sh`：原像素选区复制与整屏provider释放、顶部回弹初帧、精确输出、真实缺口拒绝。
- `tests/run-long-capture-frame-settlement-checks.sh`：注入时钟的有限收尾、重复/变化/无后续帧、超时/取消及引用释放。
- `tests/run-long-capture-stationary-quantization-checks.sh`：低对比真实移动/同列静态锚点/周期/alpha与多色1级重绘的安全边界；保留未能区分的变化为失败。
- `tests/run-long-capture-export-checks.sh`：真实 Store/spill/footer 到生产 renderer 的资格、整数/小数逻辑尺寸、PNG/TIFF/DPI、编辑/译图回退、单次编码和来源 provider 释放；只使用私有剪贴板与临时保存目录。
- `tests/run-issue4-checks.sh`：既有 Finder 编号真实渲染 fixture、颜色、底栏、编辑导出及隔离剪贴板等回归。

离线测试不调用录屏授权、不保存私人桌面。独立内存实验只比较文档存储，不能替代完整应用待机/捕获/导出测量。真实最终安装包须遵守 [安装验收规范](../operations/install-and-permissions.md)，普通截图在同包重启前后实际保存，随后再验长图编号/接缝与内存。
