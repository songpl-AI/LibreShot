# OCR 辅助进程接入验证（2026-10-03）

## 当前结论

生产 OCR 接口已接入按需退出的辅助进程，原始 Vision 参数与结果结构保持一致。自动化验证通过后，仍需用完整预览版复测真实截图、OCR 关窗与内存；Issue #5 暂不结案。

## 自动化结果

- `bash tests/run-toolbar-checks.sh`：工具栏、截屏输出、中文 OCR、原图翻译渲染/文字框、取消、系统翻译及批量区域 ID 检查通过。
- `bash tests/run-ocr-worker-checks.sh`：真实中英文/分栏原图，与旧 Vision 路径逐字段比较文本、置信度、ID、行数和坐标；sRGB/P3 半透明原始像素、ICC 配置和物理尺寸对照通过。缺失组件、非零退出、错误 JSON、错误版本、超大响应、忽略 SIGTERM 的超时/取消、排队任务及时取消、串行多调用，以及父进程意外退出后停止辅助进程并删除截图文件通过。
- `bash tests/run-ocr-sandbox-isolation-profile.sh production`：实际签名沙盒、生产接口、5 次识别和 15 秒闲置。两次增量分别约 **0.84 MiB** 与 **27.20 MiB**，均通过 32 MiB 的诊断门槛。非沙盒同样调用约 **1.67 MiB**。旧进程内路径约 69–71 MiB。第二次仍有约 26 MiB 像素/分配器驻留的变化，不能只选低值，也不构成低于 10 MiB 的承诺。
- Release 应用及辅助进程 arm64/x86_64 构建通过，`codesign --verify --deep --strict` 通过；辅助进程只有 sandbox+inherit 权限，架构与父应用一致。

日志存于忽略的 `dist/ocr-worker-integration-20261003/`。采样是父进程的 physical footprint，不能理解为总 OCR 峰值：识别期间子进程仍需要加载模型，识别后退出才消除这部分常驻。

## 验证范围

完整预览版实测、最终打包验签记录待补。最低支持系统、Intel 真机、多屏仍未测试；未发布、未修改 `/Applications/LibreShot.app`。

## 完整预览发现的边界修复

首次真实 1030×1260 像素选区识别触发“图片格式无法无损传输”：CGImage 的 provider 可省略最后一行末尾填充，而传输检查错误地要求 `bytesPerRow * height` 个字节。已改为接受最后一行实际像素长度到完整行填充之间的合法区间，无需重新渲染图片；裁剪 provider 的真实 Vision/辅助进程文字、坐标、置信度对照通过。相应回归纳入 `run-ocr-worker-checks.sh`。

真实桌面测试使用独立的中英文静态窗口 `OCRPublicFixtureApp.swift`，避免其他应用的桌面内容和窗口切换影响识别结果。首轮构建只用于定位上述边界，不作为连续 OCR 通过证据。

第二轮真实截图仍被传输前置检查拒绝，说明仅放宽尾行填充不够。现增加对延迟/共享 provider 的同尺寸、同色彩空间栅格读取后备路径，并支持无 ICC 但有系统色彩空间名称的描述；未进行 PNG 编码或缩放。强制使用后备路径的裁剪 OCR 文本、置信度、文字框对照通过。最终真实预览结果须单独记录，不用普通 CGContext 用例代替系统截图。
