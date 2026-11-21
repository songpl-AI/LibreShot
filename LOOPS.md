# Project loops

## LibreShot 本机权限恢复

保存日期 2026-11-21。批量恢复已安装 LibreShot 的失效权限，系统需要身份验证时暂停，完成后从当前界面继续。

> 按[安装与授权验收规范第 3 节](docs/operations/install-and-permissions.md#3-逐项检查并恢复授权)确认哪项权限实际失效。正常退出 LibreShot 后，用 [Computer Use 批处理](scripts/refresh-permissions.cua.js) 恢复该项。只把密码或 Touch ID 交给用户。核对新条目已启用、按规范重启并验证实际行为。记录权限结果、需要用户介入的次数及阻塞点。

1. 在 Computer Use JavaScript 会话取系统设置对象，载入 `scripts/refresh-permissions.cua.js` 的函数定义。使用已校验的已安装版本，`permission` 填 `input` 或 `screen`。

   ```javascript
   let refresh = libreShotPermissionReplay(settings, permission, installedVersion)
   nodeRepl.write(await refresh())
   ```

2. 每次只调用一次 `refresh()`。返回 `continue` 时在下一次工具调用继续，避免一次跨太多原生界面触发工具重置。返回 `authentication` 时等用户在系统弹窗验证，再继续同一个实例。进度保存在当前会话中。
3. 返回 `enabled` 后换下一项失效权限，或重开安装副本。两项都可用时跳过恢复。返回 `blocked` 时，根据当前权限页或选择器尝试规范里记录的替代操作，确认结果后续跑。同一状态无进展时记录阻塞。
4. 如果环境要求对新增或扩大的权限单独确认，按界面要求确认后继续。批处理范围限于为同一安装身份恢复现有授权。
