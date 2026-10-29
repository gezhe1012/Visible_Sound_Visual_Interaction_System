# 第六页人声可视化：静音底噪优化版

基于本地检查点 `b2feea7`，只修改麦克风分析前端及第六页双屏频谱的小幅残留门限。前五页图片、Logo、字幕、布局、DDS 声音、转场、全部按键和接线不变；KEY3 仍同时开关时域波形与 FFT。不增加麦克风回放。

旧版 bit 和证据完整保留在上一级目录，本目录单独交付新版 `HDMI_live_voice_noise_reduced.bit`。工程入口仍为 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`。本目录 ZIP 含集成工程、IP、测试与新版 bit；TF 卡五张教学图片沿用原版本，无须替换。

2026-10-29 本轮综合及布局布线通过：LUT 15,238/19,600（77.74%），寄存器 8,364；BRAM 63/64、DSP 27/29、PLL 3/4 均未增加。建立裕量 +0.283 ns，保持裕量 +0.004 ns，STA 覆盖 96.40%。原厂 SDRAM 放置/局部时钟布线等既有警告未隐藏；本轮未增加时序例外，也不能把覆盖率写成 100%。

bit 为 634,280 字节，SHA256：`EAC0601F24EA73F6B3B5055D5C401E874959B5AB7953E353A2195C19780E7C57`。

## 处理方式

1. 保留现有去直流与 24 位饱和处理，把噪声检测从 1024 点峰值改成 256 点平均绝对幅度，避免单个小脉冲打开整段波形。
2. 在关闭状态估计背景幅度，估计值限制为 128–1024 个原始 PCM 单位；强声输入与开门期间冻结估计，避免把持续发声学成底噪。开门阈值为 `max(768, 3×背景)`，关门阈值为 `max(384, 2×背景)`。
3. 连续两个达标窗口开门。48 kHz 下每个窗口约 5.33 ms，两个完整窗口为 10.67 ms；考虑发声与窗口的相位，预计最迟约 16 ms。低于关门阈值连续 18 个窗口才关闭，保留约 96 ms 收尾时间。
4. 关闭时增益固定为 16 倍、分析输出为有效的零样本，不再追着底噪抬高增益，也不停止 FFT/历史刷新；讲话时才允许增益增加到 128 倍，过载时仍可降至 8 倍。
5. 只在第六页把低于 8 像素的 FFT 柱高归零；主屏频谱和副屏瀑布共用同一结果。原 FFT 运算、原始频点与五页 DDS 映射均不改变。

这是可视化静音抑制，不是语音分离或录音降噪算法。连续风扇、碰撞、近距离吹气、强工频干扰仍可能触发显示；低于门限的极轻声也可能不触发。没有现场原始采样记录，不能把仿真底噪幅度当作实测噪声级。

## 当前验证范围

- `run_voice.ps1`：I2S 字对齐/采样率、六页播放器、去直流/限幅、旧/新前端同输入对照、轻声、持续发声、脉冲、80 ms 句尾、静音恢复、增益上限和有效采样连续性。
- 对照中的三段模拟安静输入：旧版非零输出 74,556 个，新版 0 个；一次轻声开启用时 511 个采样（10.65 ms）。80 ms 收尾 3,840 个采样保持门打开，3,837 个输出非零。以上均为可重复的数字输入仿真结果，不是实物测量。
- `run_voice_display.do`：外部串行麦克风模型→实际前端→实际 1024 点 FFT→主副屏渲染。验证 440/880 Hz、切源清除、安静后已发布波形 RAM 全平、频谱 RAM 全零、新瀑布列无能量、当前主频提示无效及重新轻声输入恢复。过去的瀑布历史正常保留，不强行清掉有效历史。
- `run_voice_compat.do`：前五页 4,608,000 个有效像素与原稳定参考逐像素一致，含波形、频谱、字幕、副屏谐波/XY、握手与行帧标志。
- 另外重跑 FFT、KEY3 联动、亮度/对比度/按键、副屏特征及绘图测试。未修改的 FAT32、SDRAM 和完整旋律测试本轮未重跑，其旧证据保留在上一级目录。
- 完整实现资源、建立/保持裕量、bit SHA256、当前源码哈希和本轮日志见 `build_evidence.json`、`routed_timing.txt`、`utilization.txt` 与 `test_logs/`。仿真图像不是上板照片。

## 实机复测

1. 下载本目录新版 bit，先临时下载验证。进入第六页，用 KEY3 开启分析面板。
2. 环境安静、不讲话数秒：主屏波形应基本水平、频谱无持续乱跳；副屏当前主频应消失，新瀑布列趋于背景色。历史图不会立即被整屏清除，这是正常的时间记录。
3. 正常讲话、拖长元音，再测试轻声和句尾；应出现明显变化，停止后应在收尾及 FFT/视频刷新时间后恢复安静。预计整体约 0.15–0.25 秒，不是立刻硬切。
4. 返回前五页，检查图片、对应声音、字幕、切页、自动轮播、亮度/对比度与 KEY3。再做冷启动及长时间运行。

新 bit 的现场静音门限、人声效果和整机稳定性仍需用户实机确认；若仍有稳定噪声，应先记录安静与正常讲话的可视化差异，再据实调阈值，不宜一味加大门限。

## 复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_voice.ps1
# 在 tests 目录用 ModelSim 分别执行 run_voice_display.do、run_voice_compat.do
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_fft.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_display_controls.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_secondary_checks.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File complete-hx4s20c-hdmi-project/scripts/verify_project.ps1 -RunImplementation
powershell -NoProfile -ExecutionPolicy Bypass -File tests/check_voice_structure.ps1 -CheckRouted
```

打包脚本采用 `--noise-reduced`，证据收集脚本采用 `-NoiseReduced`，避免覆盖上一级已交付镜像。证据收集还需执行原有 ROM 与 CDC 网表审计脚本，保留本轮日志。
