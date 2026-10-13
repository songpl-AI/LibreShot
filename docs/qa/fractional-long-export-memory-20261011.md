# 自由框选长图导出：像素兼容与内存实验

基线为主线 `498c51b8bdedce8677312ee69d1e0abae28fe123` 加现有未提交修改，已安装 1.3.19/build47。此轮仅修改导出 renderer 和保留单次规范化的 helper；不改变拼接算法、框选几何、逻辑尺寸、OCR 或翻译服务。工作树与真实 index 原有修改保留，未提交、推送或发布。

## 问题和方案

native crop 向外取整，而 Session 仍保留原始逻辑选区宽度，因此真实长图不保证精确 1x/2x。旧优化对不精确比例安全回退，但失去节省合成缓冲区的收益。直接放宽复用条件不安全：128 个真实裁剪组合仅96个原图直接导出严格相同，32个改变像素或物理尺寸，alpha 通道最大差6。

保留原精确比例与 same-CGImage 零合成路径，新增独立 known-long 来源证明。满足原图、完整选区、无标注/手势/文字/译图且允许保存/复制动作时，仍按原背景包装进行原 `bitmapRep(opaque:false)`，仅省去后续空标注整图绘制。关闭时清理 source；输出只随当前 action 持有。转换失败沿用原背景返回语义。

## 离线功能证据

| 验证 | 结果 | 对照及限制 |
| --- | --- | --- |
| 既有冻结旧 PNG | 160/160 | 固定候选真实 renderer；每份旧 PNG SHA 复核，原生样本/布局、ICC、完整 metadata、PNG semantic chunks、logical size 精确一致 |
| 新 near fractional 几何 | 64/64 | 601/300、602/300.25、301/300、1669/834；独立 fresh factory 与未改旧 composite 算法对照，不是已有冻结 PNG |
| 实测内存输入的精确几何补验 | 32/32 | 1669×1891/834.25pt、2049×4096/1024.25pt；alpha/opaque、noise/pattern、圆角/直角、resident/spill，与旧算法独立factory严格一致；另160历史PNG再次一致 |
| 实际裁剪、StreamGeometry、Store、Session 公式、renderer | 128组合×4动作全部一致 | 比较既有冻结旧 PNG；1x/2x、整数/半点/四分之一点、贴边/越界；Session 是无 SCStream 的逐字公式边界模拟 |
| 再按真实 WindowController 顺序取 preview 的入口矩阵 | 128组合×4动作全部一致 | 44组合原像素复用、76单次规范化、8安全回退；8回退为1x越界四分之一点，AppKit生成非规范且identity不稳定的表示 |
| 生产专项回归 | 449/449 | 动作/来源/格式/身份/编辑/翻译门禁、PNG/TIFF/DPI私有板、临时保存一次编码、provider 恰好释放一次；零窗口及 Provider 请求 |
| 既有导出像素 | 33/33 | 色彩、位深、padding、decode、style override；没有全局开启空标注返回 |
| 拼接/Store/Geometry/重绘 | 37/37、52/52及3溢出模式、65/65、95/95 | 保留当前连接与资源预算行为，不代替真实 SCK 或任意页面质量 |

固定源码与证据位于 `dist/fractional-long-export-20261011/`：`frozen`、`candidate`、`implementation-only.patch`、`production-pixels/run-20261011T145519Z`、`candidate-results`、`editor-entry-{baseline,candidate}`、`single-normalization/production-focused-r2.log`。源码独立审阅未发现当前可复现缺陷。生产没有返回特殊格式的 bitmapRep override；本矩阵不能为任意第三方 override 作兼容承诺。

## 内存测量

已完成24个独立PID，两个尺寸×PNG/私有PNG+TIFF复制×3对AB/BA。分别用冻结build47和固定候选真实production renderer编译，源代码、probe、runner与二进制hash固定，采样前所有像素/回归进程已退出。候选全部实际调用一次规范化helper，旧版helper为0；renderer两边bitmap规范化均为1。

| 图像/圆角动作 | 旧导出结束累计峰中位数 | 新导出结束累计峰中位数 | 降低 |
| --- | ---: | ---: | ---: |
| 1669×1891、834.25pt、PNG | 155.97 MiB | 143.81 MiB | 12.16 MiB |
| 同小图、私有PNG/TIFF复制 | 157.58 MiB | 145.50 MiB | 12.08 MiB |
| 2049×4096、1024.25pt、PNG | 148.88 MiB | 116.70 MiB | 32.17 MiB |
| 同大图、私有PNG/TIFF复制 | 181.27 MiB | 149.13 MiB | 32.14 MiB |

累计峰是进程ledger的历史值，全部24轮fixture-ready峰低于export-ended的新峰，因此此处新高发生在导出区间。复制后读取私有数据长度没有新增累计峰；大图PNG的6轮导出后仅再涨16KiB，单列为观察/日志等后续开销，未把它算作导出精确峰。当前值每10ms与bitmap/style阶段边界采样，最大间隔15.23ms，可能漏掉更短峰；观察max存在波动，不用单对约20MiB差夸大稳定收益。renderer-ended当前值配对差分别约12.12、12.05、32.13、32.13MiB，也支持少一份约12/32MiB整图绘制。未取得逐字节分配栈，不能称此为完整分配归因。

释放后10秒末段旧新中位数基本一致：小图PNG约12.99MiB、复制约13.44MiB；大图PNG约20.89MiB、复制约21.35MiB。收益是瞬时分配，不能宣称待机永久下降12/32MiB。不同小数几何触发AppKit表示/规范化开销不同，小图全程峰甚至高于大图，不能按像素数线性推断完整进程峰。PNG/TIFF每对字节长度相同只是完整性检查，像素结论仍来自独立精确gate；未按耗时宣称提速。

有效运行 `memory/run-20261011T150432Z/{RUN,SUMMARY}.json` 与 `REPORT.md`。首轮因probe对Foundation临时目录的错误假设提前退出，无有效fixture/样本，单独保留且排除。macOS忽略自定义TMPDIR，最终记录实际默认目录、前后生产spool/encode前缀集合一致；没有新增残留或删除全局历史文件，不声称临时目录沙盒隔离。未插桩或修改两份冻结生产源码，未操作应用/桌面/系统剪贴板或Provider。当前安装副本仍为已验收build47，新包正构建；此实验不代替完整应用120秒自然回落。

## 实际验收状态

新候选包、基础同包重启前后实际保存、长图质量、系统剪贴板粘贴与完整应用自然回落均待本轮固定包后验收。build47普通截图后32.86MiB待机是已存在的独立基线，不外推此轮长图结果。没有用强制 purge、重启或低画质追求20～30MiB。
