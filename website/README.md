# LibreShot 官网预览

纯 HTML、CSS、JavaScript 单页，无构建步骤或外部运行依赖。当前为本地审阅稿，未发布到 GitHub Pages。

在仓库根目录启动：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
```

浏览器打开 `http://127.0.0.1:8765`。首页可切换中英文；图库可切换标注、OCR 和贴图三组办公场景示意，点击图片或功能卡可放大。键盘可用左右方向键、Home、End 切换标签；放大窗口支持 Escape 关闭。

宣传事实依据公开 v1.3.19 README、使用指南与安装指南。下载按钮链接到 GitHub Releases/latest。顶部版本提示和固定版本文档链接需在新版本发布时更新。

## 素材

当前宣传素材统一使用异常办公案例：线上发布异常排查、会议记录文字提取、异常记录与设计反馈对照。首页、功能卡、放大说明以及图片本身均明确标注“工作场景示意 · 非应用截图”。

`samples/work-scenes.html` 支持 `?mode=annotate|ocr|pin` 与 `?lang=zh|en`，用于生成三种办公示意。未仿制 LibreShot 原生工具栏，也未将绘制的标注、文字提取卡片、参考卡片描述为实际应用 UI。

| 素材 | 内容 |
| --- | --- |
| `assets/demo-annotate.jpg` / `demo-annotate-en.jpg` | 线上发布异常的标注示意 |
| `assets/demo-ocr.jpg` / `demo-ocr-en.jpg` | 会议记录文字提取示意 |
| `assets/demo-pin.jpg` / `demo-pin-en.jpg` | 异常记录对照参考示意 |

示意页与素材中的项目名、日期、人名、日志和问题均为虚构数据。官网图片用 contain 完整显示，避免裁掉重要信息。

后续若采集真实 LibreShot 的标注、OCR、贴图操作画面，应核实版本来源后再替换素材和说明。若使用本地试用包，不应把实拍归属到公开版本；素材采集也不代替安装与权限验收。

后续发布 GitHub Pages 时，仅部署此目录的网页资源，并保持相对资源路径。目前尚未添加自动部署流程。
