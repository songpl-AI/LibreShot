# 贴图即时编辑与工具栏首次点击修复

用户在 1.3.17 build 45 上确认实体 Option、贴图缩放、Ctrl 滚轮透明度、右键进入编辑正常；反馈工具第一次点击无响应，以及应用/取消等底部操作行冗余。

## 首次点击根因及验证

原生贴图图片窗与独立工具栏子窗交替持有键盘焦点。工具栏实际命中视图为 `NSHostingView<PinnedEditorTools>`，其 `acceptsFirstMouse` 返回 false：第一下点击只激活窗口，第二下才执行工具动作。原生回归 `bash tests/run-pinned-image-checks.sh` 已捕获原版本断言失败，修复后命中 `PinnedEditorHostingView` 并返回 true。同样使处于编辑状态的图片承载视图接受首次点击，避免选完工具后第一下绘制被另一次窗口激活吞掉。

依据：[Apple NSView.acceptsFirstMouse(for:)](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse%28for%3A%29) 明确说明默认拒绝首次点击，以及覆盖方法可让激活和操作在同一下点击发生。

## 即时编辑交互

- 删除工具栏底部应用、取消、复制、保存整行及其额外高度；保留绘图工具、撤销和当前工具属性，不再强制 320 点最小宽度。
- 已完成的标注修改直接同步贴图文档，编辑画布立即显示；无需应用。
- Esc 或贴图右键“结束编辑”收起工具栏、保留修改；当前文本输入的 Esc 行为继续遵循原编辑器规则。结束编辑提交有效的文字输入，格式无效时保持编辑状态。
- 同一贴图保留编辑模型和撤销历史，再次进入可撤销此前的修改；关闭贴图时释放模型、窗口内容、回调和订阅。
- 复制、保存继续由贴图右键菜单及既有保存快捷键提供。窗口位置、缩放和透明度不随收起/重开工具栏改变；不可变底图仍保留，重复编辑不重复烘焙特效。

设计依据：[Apple 编辑菜单](https://developer.apple.com/design/human-interface-guidelines/edit-menus) 建议通过撤销恢复操作并避免重复控件挤占界面；[工具栏](https://developer.apple.com/design/human-interface-guidelines/toolbars) 推荐可辨识图标和简洁布局。此处从这些原则推导即时编辑方案，而非称 Apple 强制所有图片编辑采用该模式。

## 验证与包状态

原生贴图回归通过，覆盖首次点击接收、即时文档修改、撤销分组、收起后重开撤销、位置与透明度保留、重复编辑不烘焙、关闭释放模型及 10 次创建/编辑/关闭循环。即时同步断言也在修复前失败，修复后通过。

全屏回归 8 组通过，包括生产 ImageEditor → 贴图 → 再次编辑路径。原有源码测试未替代最终安装包体验测试。

原生工具栏截图已经视觉检查：仅工具图标和当前属性栏，底部操作行已移除。截图与红/绿检查日志保存在 `dist/pin-editor-live-tools-20261012/`。

本次仅修改源码和回归检查；当前 `/Applications/LibreShot.app` 仍为此前验收的 1.3.17 build 45，不包含此修复。下次打包、换包必须再次执行安装与授权验收规范。未发布 Release 或回复 Issue。
