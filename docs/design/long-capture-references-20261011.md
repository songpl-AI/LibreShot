# 长截图重构参考：实际开源实现与本项目边界

日期：2026-10-11。范围：读取实际算法代码、许可证及当前 LibreShot 失败证据；没有安装/运行参考应用，也未修改生产源码或测试。参考仓库均固定到本轮读取的 commit，源码版本不代表其任意平台实测质量。本项目 [LICENSE](/Users/happyelements/Documents/TestProjects/LibreShot/LICENSE) 为 MIT。

结论：建议保留 ScreenCaptureKit 与 UI，独立实现纯拼接引擎；借鉴受控采集、明确结果分类和内容条带验证。三套桌面实现都不能直接替代本项目的完成正确性与低内存契约：有的猜接缝，有的仅取单峰，有的忽略 confidence；都存在随完整长图增长的反复复制。不能把“成熟项目也这么做”作为静默遗漏正文的依据。

## 1. ShareX：受控滚动、连续原像素行，允许部分成功

仓库：ShareX/ShareX，commit [`0899cece0f9f3f98333004a0a2b2091cef42ed3a`](https://github.com/ShareX/ShareX/commit/0899cece0f9f3f98333004a0a2b2091cef42ed3a)。实际实现为 [ScrollingCaptureManager.cs](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L82)，不是功能宣传。

- **采集**：[L104](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L104) 激活选中窗口、等待StartDelay，可发送Home；[L116](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L116) 禁止捕获鼠标，每轮抓区域后发送滚轮/Down/PageDown/Windows VSCROLL；扣除计算时间后等待ScrollDelay。[默认选项L30](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureOptions.cs#L30) StartDelay/ScrollDelay均300ms。这是“滚动由程序控制”的Windows流程，不能把300ms等同手工任意滚动的稳定证明。
- **位移与接缝**：[L255](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L255) 对候选行使用完整字节相等；[L308](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L308) 搜索向上连续相同行的最大长度，最多半帧。可借鉴原像素接缝核验，但没有本项目所需的重复内容次峰歧义拒绝，也不耐颜色重绘。
- **固定区域**：[L271](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L271) 忽略两侧至少50px/约5%（上限1/3）；[L284](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L284) 从尾部相同行估计ignoreBottom，外加默认50px/10%边距，并保留历史最大ignoreBottom。这是匹配窗口启发式，不是动态footer的时序识别，不宜照搬裁掉用户正文。
- **未知/快速滚动**：[L333](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L333) 无任何匹配时会复用历史bestMatchCount/index/ignoreBottom作bestGuess，随后[L366](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L366) 标记PartiallySuccessful。LibreShot可借鉴“部分/失败状态分开”，但不能把旧位移猜测当完整拼接成功。
- **内存**：[L354](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L354) 每次分配整张更高newResult、复制既有result与新增区域；之后[L156](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L156)才dispose旧result。累计图越大，旧/新图并存峰值越高。相邻截图显式dispose值得借鉴；此文件未见像素字节/最终输出预算，不适合作为20–30MB目标的实现范本。
- **完成**：[L121](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L121)相邻图相同即停止，或者用户stop请求/无法combine；finally清理临时截图、保留result。这里没有“最终观测必须已锚定提交前沿”契约。Windows滚动信息函数存在，但该StartCapture循环实际使用相邻图相同停止，不能说普遍获得了目标应用的文档坐标。

许可：[根LICENSE](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/LICENSE.txt#L1) 为GPLv3；该源码文件region写GPLv3，但头部[L7](https://github.com/ShareX/ShareX/blob/0899cece0f9f3f98333004a0a2b2091cef42ed3a/ShareX.ScreenCaptureLib/ScrollingCaptureManager.cs#L7)文本写GPLv2-or-later，存在标注差异。本轮不解决差异；两者都不能把移植的衍生实现仅以LibreShot MIT发布。只参考通用思路，独立实现，不复制算法表达。

## 2. Deepin screen recorder：50px模板、显式错误类别，整图复制与队列边界不足

仓库：linuxdeepin/deepin-screen-recorder，commit [`c5d44c2dd99205d02134c4b8187156208fc304ad`](https://github.com/linuxdeepin/deepin-screen-recorder/commit/c5d44c2dd99205d02134c4b8187156208fc304ad)。拼接实现在 [pixmergethread.cpp](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L443)，生命周期在 [scrollScreenshot.cpp](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/scrollScreenshot.cpp#L108)。

- **位移**：[L470](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L470) 下滚取当前帧顶部全宽50px灰度模板，在已拼长图上做OpenCV `TM_CCOEFF_NORMED`，只取最大位置，阈值0.8；上滚用底部50px模板。[L485](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L485)据此整图拼接。小条带作为候选是可借鉴点；单模板/单最大峰不能安全处理重复文本、固定栏或低纹理，未见原分辨率独立接缝确认/次峰拒绝。
- **接缝**：[L495](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L495)使用50px羽化混合，[L13](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L13)转换float RGBA并逐行加权。可改善视觉条带，但不能证明匹配正确；截图文字错位时可能变成重影，LibreShot应先确认整数位移和唯一覆盖，不用融合掩盖接缝。
- **固定栏**：[L125](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L125)首次下滚识别头部，`getTopFixedHigh`[L275](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L275)取首个原像素不同的行；向上同理扫描尾部。后续沿用直到部分错误路径重置。空白正文或边缘重绘同样可能影响它，不能作为footer34问题的成熟解决方案。
- **错误/快速滚动**：[header L27](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.h#L27)分Failed/ReachBottom/MaxHeight/InvalidArea/RollingTooFast，并可给调整区域。很适合借鉴具体结果分类；速度分类依赖粗时间差和失败路径，不能把任意未匹配都翻译成用户滚太快。[L504](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L504)在自动模式以长度不增长判底部，手工模式另判，不是通用末帧完整性证明。
- **内存**：[header L74](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.h#L74)QQueue持有图像；enqueue[L130](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L130)无显式数量/字节限额。已有10000px高度限制[L72](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L72)，但不随宽度折算内存，last image还绕过限制；每次拼接整张新Mat，保存[L174](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L174)再copy完整QImage。我们应改成字节预算和条带存储，不照搬队列/整图模型。
- **采集/完成**：[scrollScreenshot.cpp L32](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/scrollScreenshot.cpp#L32)使用X11/Wayland自动滚动，每300ms模拟，按频率取图；手工模式给方向。保存[L181](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/scrollScreenshot.cpp#L181)等待500ms，stopTask、wait线程、返回现有result；不是独立末端位置验收。串行工作线程和停止等待可以借鉴，Linux输入/抓屏不可直接搬到macOS。

许可：[源码SPDX](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/src/utils/pixmergethread.cpp#L1)是GPL-3.0-or-later，[根LICENSE](https://github.com/linuxdeepin/deepin-screen-recorder/blob/c5d44c2dd99205d02134c4b8187156208fc304ad/LICENSE#L1)GPLv3。保持本项目MIT发布时，不能直接翻译/移植上述GPL实现；本轮只借鉴设计，未添加OpenCV依赖。

## 3. eSearch：当前已改成相位相关；裁边覆盖与有限并发不等于正确完成

仓库：xushengfeng/eSearch，commit [`68ad11636392f204085efa81caab0b3d19e4dc28`](https://github.com/xushengfeng/eSearch/commit/68ad11636392f204085efa81caab0b3d19e4dc28)。实际代码 [clip_window.ts L619](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L619)。开发文档中旧OpenCV说法不能代替当前实现。

- **当前位移算法已实读依赖**：[L781](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L781)把两张完整ImageData交给 `picture_match.findOffset`，反转dx/dy；调用层不使用confidence，不执行独立接缝/歧义检查。[pnpm-lock L74](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/pnpm-lock.yaml#L74)锁定0.1.4。npm该版本gitHead为[`a4a017091462d4ba5a490f1af37a086d4719f773`](https://github.com/xushengfeng/pic_match/commit/a4a017091462d4ba5a490f1af37a086d4719f773)。本轮读取其[src/lib.rs L113](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/src/lib.rs#L113)：Hann窗、零填充FFT、归一化互功率、IFFT取单最大峰，是相位相关。不是此刻仍在用模板匹配。
- **精度边界**：[依赖L264](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/src/lib.rs#L264)按最大尺寸做2/4/8倍双轴降采样，[L280](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/src/lib.rs#L280)直接将位移乘factor，没有原像素refinement。1600×1350为factor4，返回位移是4px倍数；不满足LibreShot真实1/2px细滚和连续正文精确行数契约。可借鉴“粗候选→精验证”的前半部分，不能直接以相位单峰提交。
- **固定栏**：[clip_window.ts L792](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L792)按方向裁掉约1/3边缘，再以新图覆盖旧图。保留起始顶栏/刷新末端底栏，是启发式覆盖而非固定栏识别；较厚/动态栏没有显式模型。裁区与匹配区分离可借鉴，但比例裁边不能静默吞正文。
- **采集/未知**：[L619](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L619)忙时直接跳过；键盘至少300ms、滚轮500ms采样或定时采样。从抓屏接口整屏获取后裁选区。串行避免并发基准竞争很好；busy丢帧没有保证仍有重叠，调用层未提供unknown/gap/ambiguous结果。`dx=dy=0`时忽略，不能把零峰直接当停止证明。
- **完成**：[L728](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L728)尝试再抓图，最多等待busy2秒，再转编辑；busy时最后抓图本身可跳过。没有本项目末帧未接上保护。
- **内存**：[L840](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L840)每次新建增长canvas、复制旧长图；[L894](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/src/renderer/clip/clip_window.ts#L894)完成读取整图ImageData后复制进编辑canvas，没有明确像素/字节预算。依赖[L20](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/src/lib.rs#L20)先为原两幅图分配f64灰度，再降采样；1600×1350两幅原灰度约32.96MiB。factor4后的400×337在FFT零填充成1024×1024，[L129](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/src/lib.rs#L129)两个Complex<f64>数组另约32MiB，此外还有窗口/候选/输入等。这是数组预算分析，非实测RSS；不能因为使用WASM或降采样就说低内存。

许可：eSearch [LICENSE](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/LICENSE#L1)、[package.json L24](https://github.com/xushengfeng/eSearch/blob/68ad11636392f204085efa81caab0b3d19e4dc28/package.json#L24)为GPL-3.0，上层拼接/裁边表达不能直接移植后仅MIT发。独立pic_match的[LICENSE](https://github.com/xushengfeng/pic_match/blob/a4a017091462d4ba5a490f1af37a086d4719f773/LICENSE#L1)与本轮下载0.1.4发布包LICENSE都为Apache-2.0；可独立评估合规使用，需履行Apache许可/声明等条件且继续核实依赖，不能因此把eSearch上层GPL代码当Apache。本轮不引入组件。

## 网页DOM方案为何不能替代桌面引擎

补充边界对照：mrcoles/full-page-screen-capture-chrome-extension，commit [`d1b6bbbf4c3f8101d787dd737e5476a5be082014`](https://github.com/mrcoles/full-page-screen-capture-chrome-extension/commit/d1b6bbbf4c3f8101d787dd737e5476a5be082014)，[LICENSE](https://github.com/mrcoles/full-page-screen-capture-chrome-extension/blob/d1b6bbbf4c3f8101d787dd737e5476a5be082014/LICENSE#L1) MIT。

实际[page.js L24](https://github.com/mrcoles/full-page-screen-capture-chrome-extension/blob/d1b6bbbf4c3f8101d787dd737e5476a5be082014/page.js#L24)直接读DOM scrollHeight/scrollWidth，隐藏滚动条、调用window.scrollTo，再发送真实scrollX/Y与devicePixelRatio；[api.js L45](https://github.com/mrcoles/full-page-screen-capture-chrome-extension/blob/d1b6bbbf4c3f8101d787dd737e5476a5be082014/api.js#L45) captureVisibleTab后按确定坐标绘制，无视觉位移估计；[L100](https://github.com/mrcoles/full-page-screen-capture-chrome-extension/blob/d1b6bbbf4c3f8101d787dd737e5476a5be082014/api.js#L100)按canvas尺寸/面积上限拆图。

可以借鉴分块输出、坐标与尺度明确化；但LibreShot抓任意macOS窗口，没有DOM、文档高度或可靠scroll offset，不能通过SCK得到这些信息。即使许可证允许，也不能把Chrome扩展流程直接包装成Finder/PDF/任意应用长截图方案。网页适配器若未来另做，应显式成为另一种输入源，而非降低桌面引擎的正确性要求。

## 对 LibreShot 纯引擎方案的审查

当前可追溯证据：[build42实际失败分析](/Users/happyelements/Documents/TestProjects/LibreShot/dist/build42-runtime/long-01/failure-analysis.md)、[footer34公开合成结果](/Users/happyelements/Documents/TestProjects/LibreShot/dist/build41-runtime/synthetic-header-probe/results.json)。build42日志记录累计追加360px后，横向采样图中126行发生变化且重绘兜底拒绝；它证明追加能力和该判定路径的失败，尚未取得原始帧，不能证明变化对象、颜色或根因就是合成的局部重绘。公开色带0→1px已重现假footer34，但不是保存图已漏34行的证明。

| 边界 | 建议及必要不变量 |
| --- | --- |
| SCK→Frame | 保留权限、坐标、序列化stop/drain；统一脱离SCK backing的选区像素+真实采集时间。重复pending重放是同一证据，不能加0.2s冒充新稳定观察。 |
| Observation | 可记录当前稳定观察和局部重绘；结构零位移证据必须来自滚动正文、多处分散位置。超预算或超时变unknown/rejected，不自动成功。 |
| Motion proposal | 多正文带估计位移，允许零位移候选，保留竞争候选与信息量；尺度粗化只提议，再原像素找精确整数行。固定侧栏、空白、周期行不能单独证明正文没动。 |
| Commit frontier | 与observed baseline分开；保留观测相对已提交文档前沿的可验证变换。新增必须回到commit基准验证接缝/覆盖后原子提交，不能只累计相邻帧delta导致漂移。 |
| Body/overlay | 可撤销候选，经多次已确认运动仍在屏幕坐标静止才提升可信度；首对不永久cache。静止白底/横色带不是固定栏证据；不确定时继续保留正文像素。 |
| Document storage | 保持现有分段条带思路，追加只存新增像素，不像参考每帧扩整图。preview按需缩图；导出才创建最终bitmap，考虑输出像素预算/分块策略，避免bitmap+TIFF+PNG长时间并存。 |
| Pending | 数量、字节、时间均设限；1600×1350 RGBA单帧8.24MiB，2–3帧16.5–24.7MiB。CPU描述/条带替代保留额外full frame；内存不足时明确失败/降低采样频率，禁止无限队列。 |
| Completion | 先停止并排空，然后resolve最后观测：已锚定零位移重绘可完成；未解释位移/重叠不足仍拒绝；渲染失败另分类。不能只检查accepted>1、等200ms或旧图足够长。 |

推荐结果语义：`appended / revisited / stationaryConfirmed / pendingEvidence / ambiguous / overlapMissing / resourceLimit / stopped`，并在诊断中给reason、原图diff bbox/count/maxDelta、格式/alpha、结构锚点、候选和观测/commit身份。不要把内存限制、未知运动或重绘都映成“请慢滚”。

离线replay先固定当前实际/合成反例：125px局部重绘后继续追加、1/2px真实滚动+重绘、稀疏正文旁固定栏、周期数字变化、伪footer色带、反向回访后前沿不漂移、未接上末帧、时间戳重复、资源预算拒绝。以完整输出像素/行覆盖为判据，不能只检查高度。完成后再在最终安装同包真实截图、重启前后保存，并检验编号和接缝；构建/安装遵守项目规范。

内存目标按阶段拆开：待机释放会话与窗口；捕获保留有限观察+条带；导出允许与输出像素成比例的可解释峰值。例如1600×1710最终RGBA自身约10.44MiB，1600×10000约61.0MiB，不能承诺任意长图全程20–30MB。用户已澄清20–30MB是期望，合理优化极限优先保证功能与正确性。

## 阅读方式与限制

本轮通过GitHub固定commit的原始文件、npm picture_match@0.1.4发布包LICENSE与gitHead核对；参考快照仅存 `/tmp`，没有参考应用运行或性能benchmark。以上内存为代码分配模型，速度/鲁棒性比较不是跨平台实测排名。设计独立实现，不从GPL文件复制代码、注释或逐行翻译。
