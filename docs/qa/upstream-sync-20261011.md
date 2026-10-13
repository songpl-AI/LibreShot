# 最新主线同步与本地候选整合（2026-10-11）

用户要求拉取最新 Git 提交并处理冲突。本轮在当前 `master` 保存本地改动、快进主线、恢复并整合；没有提交、推送或发布本地修改。安装副本未替换，源码编译不能代替新包实际截图验收。

## 同步与恢复点

- 同步前：`1858e14d17ade7637ac8271d87b4d33c68d49325`。
- 同步后：`498c51b8bdedce8677312ee69d1e0abae28fe123`，与本轮 `origin/master` 一致，快进3个提交并取得 `v1.3.15` 标签。
- 新生产改动来自 `99faf75`：保留双击已有标注的编辑行为，并暴露已有截图声音偏好；另两个提交为发布文档。
- 原83个本地修改/新增文件、完整差异、原index、状态和SHA保存在 `dist/sync-backup-20261011-210238/`。
- 恢复stash：`62424d02fa5971516a1b0efa55ad68adda89d5c6`，`stash apply`后仍保留，未删除；此前的恢复stash也保留。
- 原index没有实际暂存内容，有23个intent-to-add条目。stash前临时解除标记，恢复后逐项恢复；同步后仍无实际暂存内容。

预检查`merge-tree`发现工程版本号冲突，未跟踪文件与上游路径无碰撞。`git pull --ff-only origin master`成功，恢复stash后唯一文本冲突是`project.pbxproj`的两套版本字段：远端1.3.15/build41与本地1.3.18/build46。保留本地已经验收的候选版本字段，不降回早期版本；没有整文件选择ours/theirs。新整合源码若后续打包，仍须使用新的候选身份重新安装验收。

原83文件全部恢复：81份逐字节不变，只有`OverlayView.swift`和`OverlayViewModel.swift`叠加上游改动。工程冲突解决后与同步前文件逐字节一致。长截图引擎、无标注导出优化、翻译释放和既有QA/测试保留。

## 行为审查

上游双击确认逻辑与本地翻译生命周期改动位于不同逻辑位置，自动合并后独立源码审查通过：已有文字/序号双击进入编辑，输入框、控制点、拖动及过期点击不触发完成；空白双击只完成一次。完成动作仍经本地`canExportSelection`校验，稳定翻译会话模型、dismiss清引用、译图/特效preview保护均保留。声音设置只暴露原`playSound`偏好，与内存改动无重叠。

## 验证

证据目录：`dist/sync-validation-20261011-210353/`。

| 检查 | 结果 |
| --- | --- |
| 完整Debug编译，`CODE_SIGNING_ALLOWED=NO` | 通过，`BUILD SUCCEEDED`，源码哈希编译前后不变 |
| 长图导出优化专项，`-O` | 122/122通过 |
| 翻译释放专项，`-O` | 通过，14项PASS；合成识别/翻译，无真实服务调用 |
| 上游双击/声音模型、文字编辑专项 | 通过，Issue25模型14个PASS；inline editing 3组PASS含21个文字渲染/导出样本，均`-O`和exit0；native窗口事件明确跳过 |
| 裁剪/私有剪贴板内存专项 | 通过，24个PASS，`-O`和exit0 |
| 未合并index、冲突标记、diff空白 | 最终通过；HEAD与origin一致、ahead/behind均0、无实际暂存内容、23个intent-to-add及恢复stash保留 |

测试使用公开/合成输入和私有测试剪贴板。`Issue25Checks`原native mouse observer会显示窗口，因此只在任务临时副本中跳过该调用，执行其他所有模型与声音assertions；原测试源码不修改。原生鼠标窗口交互没有重新实测。没有用源码同步结果替代新包权限或实际截图验收。

现有图标尺寸、默认参数actor隔离及无async的await警告仍在，Debug编译无错误；本轮不将这些既有警告归为合并故障。

完成的编译与回归均exit0，源码在验证前后hash不变，独立审查确认双击保护代码与最新HEAD一致。记录见`build/result.json`、`model/{results.json,overlay-review.json}`、`memory/checks.json`及`final-git-checks.json`。本机仍是先前已验收的build46安装包，主程序SHA `64b31b957e6a7a8ae1d995ee765dccab4a1ddce1d12840459b4b943fe195993c`未变化；这次同步后的源码尚未重新打包安装。
