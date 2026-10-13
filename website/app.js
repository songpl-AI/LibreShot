"use strict";

const translations = new Map([
  ["跳到正文", "Skip to content"],
  ["功能", "Features"], ["使用方式", "Workflow"], ["常见问题", "FAQ"],
  ["免费下载", "Download free"],
  ["v1.3.19 已发布", "v1.3.19 is out"], ["来看看新变化", "See what's new"],
  ["截下重点，", "Capture the point,"], ["表达清楚。", "make it clear."],
  ["你的想法，值得被看见。", "Your ideas deserve to be seen."],
  ["用 LibreShot 截图、标注、提取文字，", "Capture, annotate, and extract text with LibreShot,"],
  ["把屏幕上的内容变成清楚的表达。", "turning your screen into a clear message."],
  ["免费下载 macOS 版", "Download free for macOS"],
  ["免费开源", "Free & open source"], ["原生 macOS", "Native macOS"], ["本机处理", "Runs locally"],
  ["标注", "Annotate"], ["贴图", "Pin"],
  ["工作场景示意 · 非应用截图", "Work example · Not an app screenshot"],
  ["点击放大", "View larger"],
  ["灵感出现时，随手一截。", "When an idea appears, capture it."],
  ["区域截图", "Area capture"], ["全屏截图", "Full-screen capture"],
  ["按你的习惯，自由设置", "Set shortcuts your way"],
  ["小工具，顺手的大用处", "Small tool, big help"],
  ["从截下来，到说清楚。", "From capture to clarity."],
  ["记录一个想法，说明一个问题，", "Save an idea, explain a problem,"],
  ["或留住一张值得分享的画面。", "or keep a frame worth sharing."],
  ["标注示意", "Annotate example"], ["OCR 示意", "OCR example"], ["贴图示意", "Pin example"],
  ["01 / 标注", "01 / Annotate"], ["02 / 识别与翻译", "02 / Recognize & translate"], ["03 / 原位贴图", "03 / Pin in place"],
  ["你的重点，一眼就懂。", "Make the point obvious."],
  ["图片里的字，也能用。", "Text in images, ready to use."],
  ["好参考，留在眼前。", "Keep a reference in view."],
  ["箭头、文字、序号与圆角矩形，把说明画在图上。马赛克与模糊，让敏感内容有处可藏。", "Arrows, text, numbers, and rounded boxes put the explanation on the image. Mosaic and blur keep sensitive details private."],
  ["本机 OCR 提取文字，再复制或翻译。支持将译文放回原图位置。翻译功能需 macOS 26+。", "Extract text with on-device OCR, then copy or translate it. Place the translation back over the image when needed. Translation requires macOS 26+."],
  ["把截图贴在原位置，滚轮缩放、调整透明度。右键原地编辑，边看边改，少一次来回切换。", "Pin a capture where you need it, zoom with the scroll wheel, and adjust opacity. Edit in place while you work, with fewer context switches."],
  ["区域、全屏与滚动长截图", "Area, full-screen & scrolling capture"],
  ["复制、保存与另存为", "Copy, save & save as"],
  ["工具属性与快捷键可定制", "Custom tool settings & shortcuts"],
  ["让表达少一点步骤", "Fewer steps to explain"],
  ["截一下。画两笔。", "Capture. Mark it up."], ["分享出去。", "Share it."],
  ["从屏幕到剪贴板，", "From screen to clipboard,"],
  ["把注意力留给你正在做的事。", "keep your attention on the work."],
  ["查看完整使用指南", "Read the full guide"],
  ["框选你想记录的内容", "Select what you want to record"],
  ["按", "Press"],
  ["启动区域截图，也可从菜单栏选择全屏或长截图。", "for an area capture, or choose full-screen or scrolling capture from the menu bar."],
  ["加一点标注，说明重点", "Add a mark to explain the point"],
  ["箭头指向问题，序号梳理步骤，文字补上想法。颜色、粗细和字号按工具记忆。", "Point an arrow at the issue, number the steps, and add a note. Colors, weights, and sizes are remembered per tool."],
  ["完成，随手粘贴", "Finish and paste it anywhere"],
  ["按回车完成并复制到剪贴板。想留存？", "Press Return to finish and copy to the clipboard. Need a file? Use"],
  ["手动保存，或开启自动保存。", "to save, or turn on auto-save."],
  ["准备好你的第一张截图", "Ready for your first capture"],
  ["几步安装，就能开始。", "Install in a few steps."],
  ["安装与权限指南", "Installation & permissions"],
  ["下载，拖入应用程序", "Download and move to Applications"],
  ["打开下载的 DMG，将 LibreShot 拖入“应用程序”。升级前先退出旧版。", "Open the downloaded DMG and drag LibreShot to Applications. Quit the old version before upgrading."],
  ["允许屏幕录制", "Allow screen recording"],
  ["首次截图按提示授权。使用双击 Option 启动截图时，还需输入监控权限。", "Grant access when prompted on the first capture. Starting with double-Option also needs Input Monitoring permission."],
  ["开始第一张截图", "Take your first capture"],
  ["从菜单栏启动，或按 ⌘⇧X。框选、标注，然后把你的想法分享出去。", "Start from the menu bar or press ⌘⇧X. Select, annotate, and share your idea."],
  ["当前安装包采用 ad-hoc 签名，未经过 Apple 公证。若 macOS 阻止打开，请按", "The current package uses an ad-hoc signature and is not notarized by Apple. If macOS blocks it, follow the "],
  ["安装指南", "installation guide"], ["处理。", "."],
  ["你可能还想知道", "You may also wonder"], ["一些小问题。", "A few questions."],
  ["还有别的问题或新想法？", "Have another question or idea?"],
  ["欢迎来 GitHub 聊聊。", "Come talk on GitHub."], ["反馈问题与建议", "Send feedback"],
  ["支持哪些 Mac？", "Which Macs are supported?"],
  ["支持 macOS 13 及以上、Apple Silicon 与 Intel。翻译功能需要 macOS 26 及以上；复杂底纹、表格和特殊字体的原图翻译需要人工核对。", "macOS 13+, Apple Silicon, and Intel are supported. Translation requires macOS 26+; images with complex textures, tables, or unusual fonts should be checked by a person."],
  ["截图和识别文字会上传吗？", "Are captures and OCR uploaded?"],
  ["截图、OCR 与翻译文本在本机处理。首次下载翻译语言包与检查更新需要联网；语言包安装后可离线翻译。", "Captures, OCR, and translation text are processed on your Mac. Downloading a translation language pack and checking for updates require a connection; installed packs work offline."],
  ["截图完成后，会自动保存吗？", "Are captures saved automatically?"],
  ["新用户默认仅复制到剪贴板。可在设置中开启自动保存，或用 ⌘S 手动保存、⌘⇧S 另存为。升级会保留原来的设置。", "New users copy to the clipboard by default. Turn on auto-save in Settings, or use ⌘S to save and ⌘⇧S to save as. Upgrades keep your settings."],
  ["真的免费吗？可以参与开发吗？", "Is it really free? Can I help?"],
  ["LibreShot 免费使用，源代码以 MIT 许可证开放。欢迎提交 Issue 或 Pull Request，也可以通过 GitHub Sponsors 支持项目维护。", "LibreShot is free to use and released under the MIT license. Open an Issue or Pull Request, or support maintenance through GitHub Sponsors."],
  ["为清楚的表达，留一把小剪刀。", "A small pair of scissors for clear communication."],
  ["下一张截图，用 LibreShot。", "Use LibreShot for your next capture."],
  ["以 MIT 开源，为你的 Mac 而做。", "MIT open source, made for your Mac."],
  ["更新日志", "Changelog"], ["支持项目", "Support the project"],
  ["LibreShot 首页", "LibreShot home"], ["主导航", "Main navigation"], ["页脚导航", "Footer navigation"],
  ["LibreShot 工作场景示意", "LibreShot work examples"], ["LibreShot 图标", "LibreShot icon"],
  ["放大查看 LibreShot 标注示意", "View the LibreShot annotate example larger"],
  ["放大查看 LibreShot OCR 示意", "View the LibreShot OCR example larger"],
  ["放大查看 LibreShot 贴图示意", "View the LibreShot pin example larger"],
  ["放大查看标注界面示意", "View the annotate example larger"],
  ["放大查看 OCR 界面示意", "View the OCR example larger"],
  ["放大查看贴图浮窗示意", "View the pin example larger"], ["关闭截图", "Close screenshot"],
  ["工作场景 OCR 示意：将会议记录提取为可用文字", "Work example: extract meeting notes with OCR"],
  ["会议记录文字提取示意，非实际 OCR 窗口", "Meeting note extraction example, not an actual OCR window"],
  ["工作场景标注示意：在办公页面中框出异常并加上箭头说明", "Office issue annotation example with highlighted areas and arrows"],
  ["工作场景贴图示意：将异常记录留在工作页面旁", "Incident reference pinned beside the work page"],
  ["办公异常标注示意，非实际应用界面", "Office issue annotation mockup, not an app screenshot"],
  ["异常记录对照参考示意，非实际贴图浮窗", "Incident reference mockup, not an actual pinned window"],
  ["标注 · 工作场景示意", "Annotate · Work example"],
  ["工作场景示意 · 非应用截图，页面内容为虚构数据。", "Work example · Not an app screenshot. The page contains fictional data."]
]);

const tabs = [...document.querySelectorAll(".gallery-tab")];
const panels = [...document.querySelectorAll(".gallery-panel")];
const caption = document.querySelector("#gallery-caption");
const status = document.querySelector("#gallery-status");
const languageToggle = document.querySelector("#language-toggle");
const dialog = document.querySelector(".screenshot-dialog");
const fullImage = document.querySelector("#screenshot-full");
const dialogTitle = document.querySelector("#screenshot-title");
const dialogDescription = document.querySelector("#screenshot-description");
let language = "zh";
let currentMode = "annotate";
let dialogMode = "annotate";

const screenshots = {
  zh: {
    annotate: { title: "标注 · 工作场景示意", caption: "框出办公页面中的异常位置，再用箭头补上处理意见。" },
    ocr: { title: "OCR · 工作场景示意", caption: "提取会议记录里的文字，直接复制到下一份工作文档。" },
    pin: { title: "贴图 · 工作场景示意", caption: "把参考资料留在眼前，对照内容继续手头的工作。" }
  },
  en: {
    annotate: { title: "Annotate · Work example", caption: "Highlight an issue on a work page and add an arrow with the next step." },
    ocr: { title: "OCR · Work example", caption: "Pull text from meeting notes and paste it into the next work document." },
    pin: { title: "Pin · Work example", caption: "Keep a reference in view while you continue the work at hand." }
  }
};

// Keep the Chinese source nodes intact so switching languages preserves icons and keyboard hints.
const localizedText = [];
const textWalker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
while (textWalker.nextNode()) {
  const node = textWalker.currentNode;
  const value = node.textContent.trim();
  if (translations.has(value)) localizedText.push({node, original: node.textContent, translated: translations.get(value)});
}
const localizedAttributes = [];
document.querySelectorAll("[aria-label], [alt]").forEach(element => {
  ["aria-label", "alt"].forEach(attribute => {
    const value = element.getAttribute(attribute);
    if (translations.has(value)) localizedAttributes.push({element, attribute, original: value, translated: translations.get(value)});
  });
});

function refreshDialog() {
  const screenshot = screenshots[language][dialogMode];
  dialogTitle.textContent = screenshot.title;
  dialogDescription.textContent = language === "en"
    ? `${screenshot.caption} Work example; this is not a LibreShot app screenshot. The page contains fictional data.`
    : `${screenshot.caption} 工作场景示意，非 LibreShot 应用截图；页面内容为虚构数据。`;
}

function setLanguage(next) {
  language = next;
  document.documentElement.lang = language === "en" ? "en" : "zh-CN";
  document.title = language === "en" ? "LibreShot — Capture the point, make it clear." : "LibreShot — 截下重点，表达清楚。";
  document.querySelector('meta[name="description"]').content = language === "en"
    ? "LibreShot, a free and open-source native macOS capture and annotation tool. Area capture, scrolling capture, OCR, and pinned images help make your point clear."
    : "LibreShot，免费开源的原生 macOS 截图与标注工具。区域截图、长截图、OCR 与原位贴图，把重点表达清楚。";
  localizedText.forEach(({node, original, translated}) => {
    node.textContent = language === "en" ? original.replace(original.trim(), translated) : original;
  });
  localizedAttributes.forEach(({element, attribute, original, translated}) => {
    element.setAttribute(attribute, language === "en" ? translated : original);
  });
  document.querySelectorAll("[data-screenshot] img").forEach(img => {
    const mode = img.closest("[data-screenshot]").dataset.screenshot;
    img.src = `assets/demo-${mode}${language === "en" ? "-en" : ""}.jpg`;
  });
  languageToggle.textContent = language === "en" ? "中文" : "EN";
  languageToggle.setAttribute("aria-label", language === "en" ? "Switch to Chinese" : "切换为 English");
  languageToggle.setAttribute("aria-pressed", String(language === "en"));
  caption.textContent = screenshots[language][currentMode].caption;
  status.textContent = language === "en" ? "English selected" : "已切换为中文";
  if (dialog.open) {
    const source = document.querySelector(`.screenshot-open[data-screenshot="${dialogMode}"] img`);
    fullImage.src = source.src;
    fullImage.alt = source.alt;
    refreshDialog();
  }
  const languageUrl = new URL(window.location.href);
  languageUrl.searchParams.set("lang", language);
  history.replaceState(null, "", languageUrl);
  try { localStorage.setItem("libreshot-language", language); } catch (_) { /* Storage can be disabled. */ }
}

function selectMode(mode) {
  currentMode = mode;
  tabs.forEach(tab => {
    const selected = tab.dataset.mode === mode;
    tab.classList.toggle("active", selected);
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  panels.forEach(panel => { panel.hidden = panel.dataset.mode !== mode; });
  caption.textContent = screenshots[language][mode].caption;
  status.textContent = screenshots[language][mode].caption;
}

tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectMode(tab.dataset.mode));
  tab.addEventListener("keydown", event => {
    let nextIndex;
    if (event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
    if (event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = tabs.length - 1;
    if (nextIndex === undefined) return;
    event.preventDefault();
    selectMode(tabs[nextIndex].dataset.mode);
    tabs[nextIndex].focus();
  });
});

document.querySelectorAll("[data-screenshot]").forEach(button => {
  button.addEventListener("click", () => {
    dialogMode = button.dataset.screenshot;
    const sourceImage = button.querySelector("img");
    fullImage.src = sourceImage.src;
    fullImage.alt = sourceImage.alt;
    refreshDialog();
    dialog.showModal();
  });
});

document.querySelector(".dialog-close").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", event => {
  if (event.target !== dialog) return;
  const bounds = dialog.getBoundingClientRect();
  const outside = event.clientX < bounds.left || event.clientX > bounds.right ||
    event.clientY < bounds.top || event.clientY > bounds.bottom;
  if (outside) dialog.close();
});
dialog.addEventListener("close", () => { fullImage.removeAttribute("src"); });
languageToggle.addEventListener("click", () => setLanguage(language === "en" ? "zh" : "en"));
let initialLanguage = "zh";
const requestedLanguage = new URLSearchParams(window.location.search).get("lang");
if (requestedLanguage === "zh" || requestedLanguage === "en") {
  initialLanguage = requestedLanguage;
} else {
  try { if (localStorage.getItem("libreshot-language") === "en") initialLanguage = "en"; } catch (_) { /* Storage can be disabled. */ }
}
setLanguage(initialLanguage);
