# 六页主屏统一使用安路图形 Logo

基于 `f915d8c`，用用户指定的 `doc/TF卡图片/logo_640x480_24bit_不翻转.bmp` 替换主屏原 ANLOGIC 像素字样及蓝底条。只修改运行中的 `video_osd_overlay.v`；工程入口仍为 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`，没有增加 HDL 文件或修改工程引用。

## 显示与赛题要求

- 素材为红色横条/倒三角和藏蓝 A 形图案，原图不带文字。不重新设计品牌标志，不镜像、不翻转，也不修改原 BMP。
- 根据原图的非白色边界 `(13,63)–(288,241)` 裁去外部大面积空白，等比例缩为 48×31 像素，放在 `(22,16)`；使用原图主色红 `ED1C24`、藏蓝 `1C2D4E` 与白色编码。缩小后量化为三色，细小抗锯齿颜色归并到对应主色，详见 `logo_asset.json`。
- 小白底徽标范围为 `x=18..73, y=14..49`，保持在原 Logo 区高度内，保证藏蓝标志在深色人声页仍清晰可辨；原区域其余 `x=74..173` 恢复图片，不再有蓝色文字条。
- 主屏第 1–6 页共用同一个 OSD，全部统一替换，无需分别修改六张图片。副屏原本没有 ANLOGIC 字样，故不动其 SOUND LAB 标题及布局。
- 保留赛题扩展1所需的动态时间、参数提示、滚动字幕与 Alpha 叠加。Logo 本体采用不透明原色，原时间/参数面板及字幕 Alpha 混合继续工作，不以“Logo 本身透明”冒充赛题要求。
- 麦克风门控、主屏约 100–2000 Hz FFT、KEY3 同时开关时域/FFT、副屏无音符/PK 的上一版行为、教学图片与声音、自动轮播及其他按键保持不变。

两组组合逻辑行掩码直接随 bit 固化，不依赖启动后读取 Logo 文件，不增帧缓存，也不增加像素流水线延迟。TF 卡原五张教学图片继续使用，不必把此 Logo 文件额外加入 TF 卡播放列表。

## 工具验证与实机边界

| 检查项 | 本轮结果 |
|---|---|
| 素材来源、方向、比例与编码 | 原 BMP SHA256 和裁切边界记录于 manifest；生成脚本校验两组 HDL 掩码与素材一致 |
| 六页图形标志一致、旧文字与蓝条清除 | 6 帧共 1,843,200 个像素；8,928 个图形像素对照 BMP 生成的 RGB 金标准；12,096 个白底徽标像素及 21,600 个恢复图片像素检查通过 |
| 其他 OSD 不变 | 替换矩形之外 1,809,504 个像素与 f915d8c 精确一致，包含时间、BRI/CON、字幕及消隐 |
| 原滚动字幕及两端律动 | 重跑五页逐像素金标准及 100 帧滚动/淡化/换页动画测试 |
| 原按键、FFT、麦克风及双屏 | 重跑接收器/门控/播放器、FFT/KEY3、显示参数、副屏绘图、人声串行模型→真实FFT→双屏及原兼容性测试 |
| 时序、资源与新 bit | 以本目录 `build_evidence.json`、`routed_timing.txt`、`utilization.txt` 和日志为准，只交付建立/保持时序均通过的 bit |
| 真实开发板观感及长稳 | 待用户实机确认，仿真栅格图不是上板照片 |

未修改的 FAT32/SDRAM 及完整旋律测试本轮未重新执行；其先前构建证据保留。厂商既有 SDRAM 放置/局部时钟布线警告不隐藏，不把非100%的 STA 覆盖率写成全覆盖。

首次默认实现因布局变化，使原有 SD 域 `scan_sector` 到扫描状态判定路径出现 −0.227 ns 裕量，未作为交付。首次完整日志和时序保留为 `build_attempt1.txt`、`timing_attempt1.txt`。后续采用 TD 官方 TimingMedium 的布局优化参数重新完整构建；不修改 SD 状态机、时钟、SDC，不使用新增 false path 或多周期约束来隐藏该问题。具体参数保存在 `tests/logo_timing_implementation.tcl`。

最终建立裕量 **+0.101 ns**、保持裕量 **+0.004 ns**，STA 覆盖率 96.38%。最终资源：LUT 15,250/19,600（77.81%）、寄存器 8,380、BRAM 63/64、DSP 25/29、PLL 3/4；没有新增 BRAM/PLL，DSP 比上一版减少 2 个。

最终 bit 生成于 2026-10-29 22:39:33，634,280 字节，SHA256：`E8B7062981ED18447F4EB73D397EBFEA93828E87FCD307F51619D198E659DBC0`。

## 下载与文件

下载本目录 `HDMI_anlogic_logo.bit`，先临时下载验证六页左上角图形、图片原位置和字幕，再检查全部按键、FFT、人声与双屏。确认后再沿用原固化流程。

`INMP441_live_voice_project.zip` 包含当前集成 RTL、IP、工程入口、运行目录配置、测试、源 Logo BMP、新版 bit 及证据；不包含之前的 bit。前版 `doc/live_voice/voice_focus/` 及更早交付目录完整保留，可按原流程回退。

`dual_screen_rtl.png` 是完整麦克风/FFT 链路生成的主副屏预览；`six_page_osd_rtl.png` 是六页 OSD 回归的渐变背景拼图，用于检查 Logo 一致性，不是替换后的教学图片。

## 复现

1. 用 Python/Pillow 执行 `tests/build_logo_asset.py --generate-test-assets`，从原 BMP 重新生成 `tests/logo_expected.hex`，并校验源码中的行掩码。`--emit-rtl` 仅打印可审查的生成片段。
2. 在 `tests` 目录用 ModelSim 执行 `run_logo.do`；在工程根目录执行 `tests/run_ticker.ps1`、`tests/run_display_controls.ps1`，以及本轮日志列出的其他既有回归。
3. 执行 `complete-hx4s20c-hdmi-project/scripts/verify_project.ps1 -RunImplementation -ImplementationFlowScript tests/logo_timing_implementation.tcl`，随后执行结构、FFT ROM 与 CDC 网表检查。
4. 使用 `tests/capture_voice_evidence.ps1 -AnlogicLogo` 收集 `logo_*.log` 和匹配的新 bit；预览与打包脚本使用 `--anlogic-logo`，输出本目录，不覆盖以前的交付。
