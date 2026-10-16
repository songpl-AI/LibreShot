# 长截图边框与提示不可见：现场排查

2026-10-16。安装包仍是 1.3.24 build 55，主进程 7692，未替换、重签名或恢复权限。维护者说明：框选后点击工具栏“长截图”，选区和提示都消失。

## 已取得的证据

- 当前包日志表明确实进入过采集：14:13 的帧为 1550×1222，14:14 的帧为 2351×992，接受数 1，随后有 unmatched 记录。没有发现本次主进程退出或崩溃；这些日志不证明拼接正常。
- 使用公开滚动 fixture、当前安装副本复现工具栏入口。小选区 495×650 转入采集后，AX 可读“已采集 1 帧 · 当前高度 650 px · 回车完成”。WindowServer 有 9 个本应用 screenSaver 层窗口：状态 320×42，四条边框和四块外围遮罩；alpha 均为 1。状态窗口桌面坐标 (1704,138)，在右侧 2560×1440 显示器内。这一轮未复现窗口被销毁或跑出屏幕。
- 全部 9 个窗口的 kCGWindowSharingState 均为 0，对应生产代码中三处 window.sharingType = .none。这提供了远程桌面兼容性的排查方向，但不证明特定远程客户端实际如何渲染。
- 当前显示器为主屏 1512×982 与右屏 2560×1440，右屏 Cocoa frame 为 (1512,-458,2560,1440)。自动化最初在主屏已有选区时错误地向右屏拖拽；取消旧会话后再从右屏快捷键启动解决。该输入错误不记为产品根因。

只读窗口元数据探针保存在 dist/long-capture-visibility-20261016/。旧输出字段 remoteCaptureEligible 仅按共享状态推断，不能作为远程实际画面通过证据；源码已改为更准确的 allWindowSharingReadOnly。它在 build 55 上退出 1，报告 9 个 sharing=0 窗口；只证明共享策略，不构成原用户不可见场景的完整复现。

## 待确认与修复边界

已询问维护者是在 Mac 本机屏幕前操作，还是通过 UU 等远程桌面，尚未收到答复。当前候选方向为：远程显示过滤、切换显示器/全屏 Space 后可见性、采集期间窗口提前清理。前两项需要结合实际操作环境；小选区生命周期观察暂不支持第三项。

Apple [NSWindow.SharingType 文档](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum) 当前将 none 描述为 macOS 不再使用的 legacy 常量；[sharingType 属性](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property) 描述的是其他进程读取窗口内容的级别。因此不能仅以这个属性断言所有系统或远程捕获实现必然隐藏窗口。

尚未修改生产代码，尚未构建新包，不能声称问题已修复。结束本轮公开采集并关闭公开 fixture，保留当前正式安装副本。若确认远程路径，下一步针对共享策略做单变量对照，同时验证长截图流仍通过自身应用过滤排除辅助 UI。
