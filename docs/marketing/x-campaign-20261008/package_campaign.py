from pathlib import Path
import json,subprocess,zipfile,hashlib
R=Path(__file__).resolve().parent; O=R/'ready'
url='https://github.com/songpl-AI/LibreShot'
posts=[('01-launch-annotate','首发：序号、模糊、箭头','Day 0',f'I built LibreShot, a free, open-source screenshot app for Mac.\n\nCapture, number the steps, add arrows, and blur details before sharing.\n\nMac users and developers: what would you improve?\n\n{url}'),('02-translate-in-place','原图翻译与原文切换','Day 2',f'Text in a screenshot, translated right where it was.\n\nLibreShot lets you compare the translation with the original.\n\nFree and open source. Translation needs macOS 26+ and downloaded language packs.\n\n{url}'),('03-ocr','OCR：截图文字变成可复制文本','Day 4',f'Stop retyping text from screenshots.\n\nSelect an area, run OCR, and copy the text with LibreShot. Chinese and English recognition runs locally on your Mac.\n\nFree and open source. What would you use this for?\n\n{url}'),('04-customize','隐藏按钮、调整顺序、自定义快捷键','Day 7',f'Make LibreShot work your way.\n\nShow or hide toolbar buttons, reorder your tools, and choose your own screenshot shortcut.\n\nFree, open source, and native to macOS. Which tools belong in your toolbar?\n\n{url}'),('05-pin-reference','贴图置顶：在其他页面上保留参考','Day 10',f'Keep a screenshot in sight while you work.\n\nLibreShot can pin a capture above other windows, so a reference stays close while you switch tasks.\n\nFree and open source for Mac.\n\n{url}')]
reply=f'Download and setup: {url}\n\nFound a bug? Please include your macOS version, LibreShot version, and steps to reproduce it: {url}/issues'
(O/'reply-download-and-feedback.txt').write_text(reply+'\n')
info=[]
for stem,title,day,copy in posts:
 assert len(copy)<=280,(stem,len(copy))
 (O/(stem+'.txt')).write_text(copy+'\n')
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height,pix_fmt,r_frame_rate','-of','json',str(O/(stem+'.mp4'))]))
 info.append(dict(stem=stem,title=title,day=day,text_characters=len(copy),duration_seconds=round(float(probe['format']['duration']),2),bytes=(O/(stem+'.mp4')).stat().st_size,sha256=hashlib.sha256((O/(stem+'.mp4')).read_bytes()).hexdigest(),streams=probe['streams']))
(O/'manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2))
intro='''# LibreShot X 发布包

本包已有 5 条可发布视频和对应英文文案。按下面顺序逐条发；不要同一天全部发出。长截图尚未得到可核对的完整录制结果，未放入 ready 文件夹。

视频为本机 LibreShot 1.3.9（31）的实际画面，加了英文提示；无配音、无音乐。统一 H.264 / MP4、1280×960、30 fps，适合静音观看。示例文字与邮箱为虚构内容。原图翻译复用了同日先前实录素材，没有生成模拟产品动画。

## 发布日程

Day 0 指你实际发布首帖的那一天。推荐先用北京时间 21:00 作为方便执行的固定时间，后续按自己的受众和互动调整；这不是“最佳发布时间”的保证。若首发是 10 月 8 日，以下日期可直接照做。

|阶段|相对时间|示例日期|视频／文案|宣传重点|
|---|---|---|---|---|
'''
rows=[]
for (stem,title,day,_),date,item in zip(posts,['10月8日','10月10日','10月12日','10月15日','10月18日'],info):
 rows.append(f'|{title}|{day}|{date}|[{stem}.mp4]({stem}.mp4) · [{stem}.txt]({stem}.txt)|{item["duration_seconds"]} 秒|')
rest='''

## 每条怎样发

1. 打开 X 的新帖输入框，复制同编号 `.txt` 文件的全部文字。
2. 用媒体按钮上传同编号 `.mp4` 原生视频；不用把视频改成 GIF，也不用把封面另发成图片。
3. 等待上传和处理完成，预览文字、视频开头和结尾，确认没有上传错文件，再发布。
4. 首帖发出后，用帖子菜单置顶到个人资料，方便后来看到功能帖的人了解整个项目。
5. 在首帖下面发一条回复：复制 `reply-download-and-feedback.txt`。后续帖已有 GitHub 链接，不必机械重复回复；需要串联时可另加一条回复，贴首帖链接。
6. 接下来每条作为新的独立主帖发布。不要只放在首帖的深层回复里，也不需要每天转发同一段功能清单。

封面 PNG 是备用预览素材。如果发布界面支持选择视频封面，可选同编号 cover；没有该选项也能正常发布。视频界面为本机中文 UI，关键动作配了英文提示。

## 分阶段怎样处理反馈

- 首发当天：发布后留 20～30 分钟回应 Mac 用户和开发者的真实问题。安装入口、操作方法和复现步骤优先答清楚。
- Day 1：整理反馈，再发翻译视频。原图翻译必须保留 macOS 26+、先下载语言包的条件；不要宣称首次使用完全不需要联网。
- Day 4～10：按日程展示 OCR、个性化和贴图。每条只问一个与场景相关的问题，方便用户给具体建议。
- Day 14：若已经有实际反馈或修复，发一次“根据反馈改了什么”。没有实质变化就不发虚构更新。长截图补录并核对保存结果后，才作为这一阶段的追加功能帖。
- 遇到影响安装或截图的阻塞问题：先回应和修复，后续宣传顺延。不要在尚未验证时声称已修复。

发布后 24 小时记录：浏览量、有效回复、主要需求、可复现 Bug、关联 Issue。不要把浏览量等同于安装量；没有跟踪数据时不宣称转化效果。

## 功能表述边界

首帖以日常截图处理为入口，翻译负责展示视觉亮点，OCR负责说明实用价值，个性化和贴图留给后续深入使用场景。免费、开源、原生 Mac 的定位贯穿全部帖子。

翻译适合文档和较简单背景，复杂背景可能需要校正。OCR 支持中英文、本机识别。截图、OCR、翻译文本在本机处理，但下载语言包和检查更新需要联网。因此本包没有使用“整个应用永不联网”的文案。

## 长截图：暂不发布

本次 UI 自动化无法正常定位浮动完成窗口，也未拿到可核对的长截图结果。`raw/scroll.mov` 只是工作素材，不是发布成片，不在 ZIP 包里。

补录脚本：选中滚动区域 → 连续小幅滚动三到四次 → 点完成 → 展示真实生成的长图 → 保存 → 核对上下段落连续且无重复或缺漏。视频约 15～20 秒。

补录成功后可使用以下英文草稿，配真实成片：

> A page longer than your screen? Capture it as one image with LibreShot.\n>\n> Select the scrolling area, scroll, then finish and annotate the result.\n>\n> Free and open source for Mac.\n>\n> https://github.com/songpl-AI/LibreShot

## 核对与依据

本包视频逐条完成 ffmpeg 全片解码检查和画面抽帧检查；文案按普通 280 字符帖限制控制（本包使用 ASCII 文案，URL 未缩短时也不超过 280）。具体时长、大小和 SHA-256 在 `manifest.json`。成片不含桌面通知、个人文件路径或系统权限弹窗；原始工作素材可能包含这些内容，不要直接上传 raw/work。

这次只录制已有应用，没有构建、替换应用、发布 Release 或执行新包安装验收，也没有代发 X。

X 官方说明：普通账号视频可上传至 140 秒／512 MB，发布时通过媒体按钮附加视频并完成上传。本包均低于这些上限。[视频帮助](https://help.x.com/en/using-x/x-videos) · [发布帖子帮助](https://help.x.com/en/using-x/how-to-post)。查阅日期：2026-10-08。发布时间和节奏是本次策划建议，不是 X 官方算法结论。
'''
(O/'发布说明.md').write_text(intro+'\n'.join(rows)+rest)
(R/'README.md').write_text('# 工作目录\n\n对外只用 `ready/` 或 `LibreShot-X-ready.zip`。`raw/`、`work/` 是内部录制和剪辑素材，可能含桌面信息，不要上传。编辑脚本为 `edit_campaign.py`，打包脚本为 `package_campaign.py`。长截图未完成，详见 ready/发布说明.md。\n')
with zipfile.ZipFile(R/'LibreShot-X-ready.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in O.iterdir():
  if p.is_file(): z.write(p,Path('LibreShot-X-ready')/p.name)
print(json.dumps([{k:v for k,v in x.items() if k in ['stem','duration_seconds','text_characters','bytes']} for x in info],indent=2))
