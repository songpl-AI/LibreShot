# 本轮贴图改动相关 Issue 补充核对

2026-10-12，通过 GitHub 连接器读取正文与相关评论，再用仓库 Issue 列表核对状态；共 37 条 Issue。只分析和修改本地源码，没有回复、关闭或变更任何 Issue。

| Issue | 与本轮关系 | 处理结果 |
| --- | --- | --- |
| [#22](https://github.com/songpl-AI/LibreShot/issues/22#issuecomment-6117046650)，OPEN | 最新评论要求悬停滚轮调整属性，并省略调属性后绘制前的额外点击 | 属性滚轮已接入；本次追加普通截图/图片文档绘制承载视图首次点击处理。原图片编辑器 `acceptsFirstMouse` 断言失败，修复后通过；区域画布窗口缩放和原生全屏 Space 也复验通过。具体用户环境体验仍待新包确认 |
| [#34](https://github.com/songpl-AI/LibreShot/issues/34)，OPEN | 左/中/右对齐主工具栏 | 增加把手及收起图标后，旧布局对齐了整行附件，主按钮栏右缘偏离图片。原生回归失败；改为主按钮栏锚点，并消除 AppKit 窗口原点取整造成的半点偏移。修复后实际主栏右缘为 600，与图片右缘 600 相同 |
| [#33](https://github.com/songpl-AI/LibreShot/issues/33)，OPEN | 贴图右键原地编辑 | 已实现，并根据维护者反馈追加即时编辑、保留撤销、编辑时移动、空白双击直接保存及可见收起入口。本轮一起回归 |
| [#32](https://github.com/songpl-AI/LibreShot/issues/32)，OPEN | 滚轮缩放/透明度 | 已实现，Ctrl 不改变位置尺寸，保存不烘焙显示缩放/透明度；本轮检查继续通过 |
| [#35](https://github.com/songpl-AI/LibreShot/issues/35)，OPEN | 外接屏/台前调度下原位贴图 | 原全局选区位置已实现；本轮编辑移动不改变标注本地坐标，工具栏随窗口重新定位。台前调度+跨屏切换专项仍需实机，不能仅凭坐标回归关闭 Issue |
| [#30](https://github.com/songpl-AI/LibreShot/issues/30)，CLOSED | 双击已有文字/序号不能误保存 | 共享空白确认判断继续复用到贴图独立保存回调；已有标注、控制点、输入框及真实拖动不触发。普通截图与贴图双击行为分别测试 |
| [#20](https://github.com/songpl-AI/LibreShot/issues/20#issuecomment-6116799610)，OPEN | 内存与关闭释放 | 最新用户评论报告 v1.3.16 两小时 82.9M。保持贴图底图裁剪范围；编辑模型只在贴图生命周期内保留以维持撤销，关闭释放检查继续通过；不把用户报告或弱引用检查等同于新版物理内存承诺 |
| [#36](https://github.com/songpl-AI/LibreShot/issues/36)，OPEN | 关闭贴图后用快捷键召回最近截图，可选历史翻页 | 是同领域新增能力，但需最近截图缓存、全局快捷键及保留策略；现有 Cmd+P 是编辑期间贴图，不能冒充全局召回。本轮不仓促加入。后续建议先实现单张最近截图、菜单入口、可配置且默认不抢占其他软件的全局快捷键，采用有界磁盘缓存；历史翻页单独扩展 |
| [#27](https://github.com/songpl-AI/LibreShot/issues/27)，OPEN | 已有标注悬停高亮 | 属于新的视觉反馈；本轮保留现有鼠标移动光标，空白移动与标注命中隔离已测试，高亮样式另行设计 |
| [#28](https://github.com/songpl-AI/LibreShot/issues/28)、[#37](https://github.com/songpl-AI/LibreShot/issues/37#issuecomment-6117211125)，OPEN | 十字线/放大器与截图前鼠标位置取色、RGB/HEX 复制 | #37 评论明确不是给标注工具设置颜色；属于截取前阶段的新工具，不并入贴图编辑修复 |
| [#38](https://github.com/songpl-AI/LibreShot/issues/38)，OPEN | 菜单栏左键动作可配置，右键菜单保留 | 独立设置与入口设计。评论说明用户取消快捷键以避免冲突；适合与全局召回快捷键一起单独设计，本轮不改变已有菜单点击行为 |

## 联合检查

原生贴图检查通过，包括位置、滚轮、工具栏实际右对齐、首次点击、编辑移动、直接 PNG 保存和保留撤销/关闭释放。全屏编辑器 8 组检查通过；原生全屏 Space 检查通过（visible/key/activeSpace 为 true，spaceChanges 为 0，原全屏窗口仍在）。

检查日志与公开截图保存在 `dist/pin-issue-followup-20261012/`。源码检查与专用 fixture 不能替代最终安装包验收；本轮合并准备 1.3.19 build 47，包与权限结果独立记录。
