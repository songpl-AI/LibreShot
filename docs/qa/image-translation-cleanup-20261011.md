# 图片翻译会话释放：源码修复与验证

日期：2026-10-11。源码基线 `1858e14d17ade7637ac8271d87b4d33c68d49325`，叠加工作区原有未提交的截图内存优化与长截图重构，以及本页记录的图片翻译生命周期修改。源码修复与针对性回归完成；未提交、未推送、未发布。

本页记录源码阶段的生产修改、合成生命周期回归和内存策略。随后包含修复的固定候选1.3.16 build44已构建并安装，实机进度另见[build44验收](1.3.16-44-translation-memory-20261011.md)；build43数据仍属修复前，源码测试不替代新包验收或实机内存下降证明。

## 问题证据与目标

[build 43 功能内存报告](1.3.15-43-feature-memory-profile-20261011.md)记录了同一主 PID 81589：用户确认 OCR、图片翻译成功并关窗后，90 秒内 footprint 为 76.84–77.28 MiB。引用树关联系统翻译 completion → closure → `ImageTranslationModel.original` → 图像 provider → 29,704,192 bytes（28.33 MiB）的 Data backing。原图还有图形缓存引用，部分扫描根是保守指针，不能说业务模型是唯一持有者。

因此本次目标是结束会话时主动撤掉业务像素所有权，避免旧系统回调延长原图/译图存活，并拦截迟到异步结果。释放对象、释放 allocation、physical footprint 降低是不同证据；不预报必然减少 28.33 MiB，也不把另一 PID 的约 40 MiB 待机当成本轮严格操作前基线。

## 源码范围

| 文件 | 本轮行为 |
| --- | --- |
| `LibreShot/LibreShot/Core/OCR/ImageTranslationWindowController.swift` | 原图可置空；新增幂等 `dismiss()`；窗口关闭清原图、译图与区域；取消保持可重试原图；异步返回检查会话/请求/渲染身份；翻译任务弱捕获模型；布局重挂与真正关闭分开处理 |
| `LibreShot/Features/Overlay/OverlayViewModel.swift` | 父 owner 持有一个会话模型，移除翻译/选区变化/reset 先 dismiss 再撤 owner；导出同时检查真实模型状态；显式 MainActor 隔离，macOS 26 类型通过 availability/type erasure 兼容 macOS 13 部署目标 |
| `LibreShot/Features/Overlay/OverlayView.swift`、`LibreShot/LibreShot/Core/ImageEditorWindowController.swift` | inline 视图观察父 owner 的唯一翻译模型，避免工具条布局分支各自创建模型 |
| `tests/VisualWorkflowChecks.swift` | 原有导出场景先通过合成区域和真实 renderer 取得可导出模型，再继续既有像素检查 |
| `tests/ImageTranslationReleaseChecks.swift`、对应运行脚本 | 合成 provider 释放、取消/重试、异步迟到、布局时序与重复会话回归，保留源码哈希和编译模式 |

`OverlayViewModel.captureRequiresExistingPreview`、OCR worker、长截图 matcher/store 和窗口生命周期的其他既有修改不属于本次新增；既有暂存与未跟踪文件均保留。

## 释放回归方法

使用可观测释放回调的 `CGDataProvider` 和 weak model/NSImage 引用，不用活动监视器下降代替对象证据。mock OCR/文字翻译配合挂起、取消和迟到返回；像素排版使用生产 renderer。测试不调用真实 OCR、真实系统翻译，不打开窗口，不读用户截图，不修改用户设置或现场进程。

初轮普通编译及 `-O` 各通过 9 组：

- cancel 保留原图用于手动重试，视图重新激活不会自动重试手动取消。
- 保留旧 completion/model 时，dismiss 仍释放原始 provider 与译图；迟到动作不能恢复已结束会话。
- 不响应取消的文字翻译仍挂起时，原始像素已释放；OCR 在取消并退出其输入作用域后释放图像。
- render debounce 期间 dismiss 能释放原图，迟到排版不能重新生成输出。
- 同会话布局重挂恢复被中断的 OCR/翻译/排版，完成译图可保留。
- SwiftUI 先取消 task、后通知消失的顺序仍可恢复。
- 移除翻译/选区改变保持正常编辑；保留 11 个旧 model 时，每次 reset 仍释放原始 provider backing。

初轮日志：`dist/image-translation-release-checks-20261011T070345Z/results.log`、`dist/image-translation-release-checks-20261011T070419Z/results.log`。最终审查发现布局新挂载先激活、旧挂载后消失及重叠任务的额外时序；最终修复和重跑结果另附下节，初轮记录不替代最终源码验证。

## 最终源码验证

审查补修了三个明确时序：新布局先挂载、旧布局后消失时，挂载 UUID 门禁阻止旧回调暂停新任务；相同 request/revision 的重叠翻译或渲染由独立 invocation 身份保护 success/catch/defer；跨布局 publication 读取当前模型值、核对 owner/session，并用 `initial: true` 同步首值。系统语言下载/权限的用户取消，若 hosting task 未取消，不写入布局恢复意图；仍允许用户显式重试。

普通与 `-O` 最终 **各 13 组全部通过**，在前述 9 组基础上新增：

1. 新挂载激活先于旧挂载消失；旧挂载迟到回调、错误使用新 request ID、已取消激活及旧挂载 render 都不能接管当前工作。
2. 同 request 的重叠翻译，旧成功/旧取消先于新结果以及旧结果晚于新结果三个顺序，均不能清新任务或覆盖输出。
3. 同 revision 的重叠排版，旧取消不能清新 rendering 状态或遗留假恢复意图。
4. 用户取消系统服务不会因布局重挂自动重试，显式 retry 仍可取得正常导出。

证据：

- [普通编译结果](../../dist/image-translation-release-checks-20261011T071238Z/results.log)
- [优化编译结果](../../dist/image-translation-release-checks-20261011T071258Z/results.log)
- 对应目录中的 `RUN.json` 记录全部生产 Swift 源码及测试/脚本 SHA-256，最终逐项核对无漂移；编译模式分别为普通与 `-O`。

最终生产源码另重跑 Visual workflow，6 项 PASS；完整 Release 源码编译再次 `BUILD SUCCEEDED`。日志为 `dist/translation-cleanup-20261011/final/visual-workflow.log` 与 `xcode-release-compile.log`，对应 `visual-RUN.json` / `xcode-RUN.json` 记录源码哈希，exit 均为 0、source drift 均为空。`git diff --check` 与 runner 的 `bash -n` 通过。

已开始的 OCR 或排版调用栈仍可能持有输入图直到合作取消并退出；dismiss 的保证是立即撤模型自身像素所有权并拒绝迟到写回，而不是强行释放仍由运行任务使用的图像。上述测试是 headless 模型/生产 renderer 回归，不替代真实 SwiftUI `.translationTask` 系统行为。

复跑入口：

```sh
bash tests/run-image-translation-release-checks.sh
LIBRESHOT_OPTIMIZE=1 bash tests/run-image-translation-release-checks.sh
```

## 其他已完成回归

| 检查 | 已取得结果 | 初轮证据目录 `dist/translation-cleanup-20261011/` |
| --- | --- | --- |
| Visual workflow：工具条、长图显示、译图色彩、选区/标注/原图切换及导出 | 6 项 PASS | `visual-workflow.log` |
| 窗口释放生命周期 | PASS | `window-release.log` |
| Capture 导出：sRGB/P3、alpha、圆角、行跨度、端序与已渲染图复用 | 33/33 | `capture-export-pixels.log` |
| Release 完整源码编译，macOS 13 deployment | BUILD SUCCEEDED | `xcode-release-compile.log` |

Release 编译使用 `CODE_SIGNING_ALLOWED=NO`；DerivedData 只是未签名编译输出，未安装或启动，不是试用包。完整 toolbar 脚本涉及真实 OCR/TranslationSession 和可见窗口，本轮未执行；生产 `.translationTask` 真正关闭/布局重挂行为仍需最终安装副本验收。

## 待验与下一步

1. 准备一个固定签名候选，按[安装与授权验收规范](../operations/install-and-permissions.md)完成同包重启前后截图/标注/保存；已有有效权限保留，不提前重置。
2. 使用同尺寸/像素格式/stride 的固定素材，对普通截图、OCR、图片翻译分别记录操作前、处理、保存、关闭及自然空闲曲线；分列主进程/准确 OCR worker/系统共享翻译服务。先自然采样，再做 heap/引用树，避免观测扰动混入回落区间。
3. 重复使用后看活对象与字节是否阶梯累积；核对旧 completion 悬挂时大像素是否脱离模型。实机结果出来前，不宣称 77 MiB 已回落至某个数字。
4. 长图约 209 MiB 瞬时峰另用 Allocations/VM Tracker 追最终渲染、首次显示、编码及交接；关闭后 heap 不能恢复已经释放的瞬时分配栈。必要时独立 A/B 选区物化，兼顾颜色/alpha/像素正确与复制峰值。

策略及系统机制见[图像会话与内存策略](../design/memory-lifecycle-policy.md)。本轮无需用户立即再截图或恢复授权。
