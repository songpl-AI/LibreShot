# 本机换包执行入口

维护日期：2026-10-06。固定脚本：`scripts/upgrade_local.py`，仅依赖 Python 3 与现有 macOS/Xcode 工具。它调用现有 `build_release.sh`，默认 ad-hoc，不发布 Release。

下次用户要求“删旧包、打包、安装”，先读本页和 [授权验收规范](install-and-permissions.md)，然后按下面执行。不要重新发明安装流程。

## 固定执行顺序

1. 确定源码、版本与新的 build 号，提交代码；用户需要未提交试用时，脚本会保存已有跟踪文件差异，但拒绝未跟踪输入。脚本不自动改版本、不提交或推送代码。
2. 打包到一个**从未存在的新目录**：

   ```sh
   python3 scripts/upgrade_local.py package dist/LibreShot-1.3.6-28-trial
   ```

   示例中的版本/build 必须先与项目设置一致。输出包括 DMG、SHA256SUMS、build.log、SOURCE.json、source.patch 和安装授权规范。目录已存在则停止；失败日志保留在输出目录旁。
3. 用原生应用菜单正常退出 LibreShot/Preview，再检查：

   ```sh
   python3 scripts/upgrade_local.py status
   ```

   脚本不强杀进程，也不模拟 UI。专用公开测试 fixture 不影响换包，继续保留。
4. 查看清理计划，然后安装**刚才固定的同一包**：

   ```sh
   python3 scripts/upgrade_local.py install dist/LibreShot-1.3.6-28-trial --plan
   python3 scripts/upgrade_local.py install dist/LibreShot-1.3.6-28-trial
   ```

   `--plan` 只核验并展示，不改变文件。安装命令发现主进程仍运行就停止，退出后重复安装命令即可，不需要重新编译。
5. 通过 Finder/原生桌面接口打开 `/Applications/LibreShot.app`。读取设置和授权缺失提示；按授权规范分别处理录屏、输入监控，精确添加当前路径，正常重开。系统密码/Touch ID 由用户输入。
6. 默认执行授权规范的重启前后实际截图与保存，并填写版本 QA；用户明确说“你不用试，我验证”时交由用户验证，在记录中注明待验，不能写成代理已验收通过。文件、签名、版本和实际进程身份仍要核对。

## 脚本自动完成的工作

- 校验 DMG SHA-256、镜像、主应用/helper 签名及打包架构。
- 挂载 DMG，比较候选/镜像内容，先在安装目录旁准备并核验完整副本。
- 备份原偏好文件，保留容器、保存目录及书签。
- 把 `/Applications/LibreShot.app` 及仓库 `dist/*` 下旧候选、archive 中同 bundle ID 的主应用移入废纸篓；最新包中的应用保持原位。其他名称、Preview、fixture 和旧 DMG不在清理范围。遇到无效应用信息则停止。
- 安装固定路径，再核验最终内容与签名；写 `INSTALL.json` 和 `retired-apps.json`。
- 替换过程中失败时恢复已移出的旧应用，写 `rollback.json`；回退后的权限仍待复验。已经安装过且有 INSTALL.json 的包拒绝静默重复安装。

## 留给系统 UI 与验证的工作

脚本不会修改 TCC 数据库、全局重置权限、关闭 Gatekeeper、操作授权开关、输入密码、发起截图或自动发布。`INSTALL.json` 的权限与实际验收初始状态始终是 pending，需要依据 UI 和实际结果填写 QA；脚本成功只表示文件安装成功。

每个独立构建的 ad-hoc 身份可能变化，脚本无法保证以后完全不需要重新授权。它省去固定的文件与校验步骤，授权恢复走同一个明确流程。

## 脚本检查

```sh
python3 -B tests/LocalUpgradeChecks.py
```

六项隔离检查覆盖成功替换、校验失败、运行中阻止替换、镜像不一致、替换后失败恢复全部旧副本、只读计划。检查使用临时文件与模拟 macOS 工具，不改变本机应用和授权；真实 macOS 签名/挂载仍由每次安装命令执行。
