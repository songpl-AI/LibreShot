# 远端同步与本地内存改动整合（2026-10-10）

用户要求先拉取当前主线，保留此前已测试的本地改动，处理冲突并验证，再继续长截图质量与内存分析。本轮没有提交、推送、发布或替换安装应用。

## 源码与恢复点

- 分支：`master`，远端：`https://github.com/songpl-AI/LibreShot.git`。
- 同步前：`b11231edf316beeec3fb2b738d546222fb3b084c`。
- 同步后：`1858e14d17ade7637ac8271d87b4d33c68d49325`，与本轮 fetch 的 `origin/master` 一致；快进 42 个提交，同时取得 v1.3.11–v1.3.14 标签。
- 本地 28 个修改/新增文件在 `dist/sync-backup-20261010-215254/` 保留文件副本、SHA-256 清单、完整差异、原索引与状态。
- 持久恢复 stash：`8fd1595210de90c5e40806913ac4d95a06eca541`，使用 `stash apply` 恢复后仍保留，未删除。
- 原索引没有实际暂存内容，仅有 7 个 intent-to-add 条目；为兼容 stash 临时解除这些标记，恢复文件后重新设置原标记。本地功能保持未提交。

首次直接快进被本地改动拦截。保存恢复点后执行 `git pull --ff-only` 成功；恢复 stash 时唯一文本冲突为工程两处 `CURRENT_PROJECT_VERSION` 的本地 35 与远端 40，均采用远端 40。`MARKETING_VERSION` 为 1.3.14。没有对业务文件使用整文件 ours/theirs 替换。

原 28 个文件全部存在：23 个文件与同步前逐字节一致；另 5 个为 OverlayViewModel、CaptureService、LibreShotApp、ToolbarRegressionChecks 与工程文件，其中前四个叠加主线变更，工程保留主线版本。CaptureService 另去除一处原有本地空行尾随空格。

## 行为整合

- 保留主线所有工具双击完成、序号首击回退与文字提交。
- 保留全屏截图触发时固定鼠标所在显示器，并在目标屏幕打开编辑器。
- 保留新版保存流程：完成动作的自动保存开关、旧用户偏好迁移、显式保存到配置目录与另存为初始目录。
- 保留自动工具属性栏、独立工具偏好、矩形圆角与序号边框/填充/数字独立颜色，以及旧 style 工具迁移和动态工具栏索引。
- 保留本地提前释放 overlay、脱离源图的裁剪副本、单帧请求及流停止生命周期、OCR/贴图窗口关闭释放、长截图诊断和静态重绘处理。
- `LIBRESHOT_DIRECT_REGION_CAPTURE` 与队列深度仍是实验环境开关，不因同步启用。

远端没有长截图算法修复。本轮同步不能视为修复用户在 build 35 成图中反馈的内容重复、漏行或错位。已有 clean-01 trace 的零拒绝也不能替代视觉质量检查。

## 同步后验证

证据统一保存在 `dist/sync-validation-20261010/`。

| 检查 | 结果与证据 |
| --- | --- |
| 完整 Debug 源码编译，不签名/不启动 | 通过；`build/xcodebuild.log`，`BUILD SUCCEEDED` |
| 工具栏与图片翻译测试编译 | 通过；`toolbar-compile/compile.log`；执行会显示窗口，本轮只编译 |
| 裁剪内存、CVPixelBuffer 转换、请求生命周期、overlay/OCR 关闭释放、贴图内存与导出 | 5 项脚本均退出 0；`memory/results.json` 与各日志 |
| 双击完成、工具属性、Issue 23 连续文字输入/裁剪边框 | 3 项脚本均退出 0；`upstream/summary.json` 与各日志 |
| 长截图重绘、Issue 4、Issue 17/18 | 3 项脚本均退出 0，分别 90、270、22 项 PASS，合计 382 项；`long/summary.log` |
| 未合并索引、冲突标记、diff 空白检查 | 均通过；`final-checks.json` |

所有实际执行的测试使用合成或仓库公开 fixture；需要剪贴板的专项使用具名测试剪贴板。未运行会置前窗口、写系统剪贴板的完整 toolbar/fullscreen 运行测试，也未运行会切换 Space 的 fullscreen-overlay 测试。

## 安装身份与待办

本轮只同步和验证源码。只读核对 `/Applications/LibreShot.app` 仍为 1.3.10 build 35、PID 54422；本轮没有退出或替换它。因此不能声称已安装应用含最新 1.3.14 功能，也不能声称合并源码已经通过最终安装副本的实际截图验收。

后续基于同步后的源码继续定位长截图质量问题。修复后若构建试用包，使用新的唯一 build 号和独立 QA 文件，按安装规范完成最终安装路径的录屏、输入监控及同包重启前后截图保存验收；旧 build 35 与主线 build 40 的历史验收不能替代。
