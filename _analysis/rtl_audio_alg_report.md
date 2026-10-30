# lab_ex5_i2s 音频算法链 RTL 技术摘要（只读分析）

> 分析对象：`src/user_source/hdl_source/` 下 18 个 Verilog 源文件，以及顶层 `top_tf_hdmi_audio.v` 的连线关系。
> 全文数值均来自源码字面量与可复算的算术推导，不含估计值；凡属推断（如资源折算）均显式标注。

---

## 0 全局前提

### 0.1 系统与时钟

| 项 | 值 | 来源 |
|---|---|---|
| 顶层 | `top`（`top_tf_hdmi_audio.v`，600 行） | 文件 |
| 像素/视频时钟 | `video_clk` = 25 MHz | `video_pll`，时序 800×525 |
| 帧率 | 25 000 000/(800×525) = 59.52 Hz，帧周期 16.80 ms | 推导 |
| 音频主时钟 `audio_mclk` | 12.288 MHz（`PLL_HDMI_AUDIO` clk2） | 顶层第 198–205 行 |
| 音频采样率 | 48 000 Hz（`science_audio_i2s` 有理数使能，平均精确 48 kHz） | 源码 + `doc/build_evidence.json` |
| BCLK / LRCK（内部 I2S） | 6.144 MHz / 48 kHz，64 BCLK/声道，128 BCLK/立体声帧 | 推导（见 §17） |
| 单一时钟域 | 所有音频分析模块（FFT、波形、频谱、音高、谐波、XY、特征存储、渲染）全部在 `video_clk` 域 | 顶层连线 |
| CDC | 分析链无 CDC；仅 SD 域/HDMI 串行域有独立同步（不在本文范围） | — |

**关键结论：`audio_mclk`（12.288 MHz）在本工程顶层只连到 PLL 输出、未被任何模块使用**（`hdmi_audio_tone_i2s_64fs` 未被实例化，仅被 `tests/tb_waveform_i2s.sv` 使用）。整条音频链由 25 MHz 视频域内的“有理数时钟使能”合成，不存在跨时钟域。

### 0.2 音频数据通路（顶层实测连线）

```
science_audio_i2s (25MHz域, DDS+旋律)
      │ bclk/lrck/dout (I2S 串行, 64bit/声道)
      ▼
I2S_receiver  ──► audio_valid / audio_left_data[23:0] / audio_right_data[23:0]
      │                     ├──► hdmi_1_4b_transmitter_core_wrapper (HDMI_B 音频, 48K, ACR N=6144)
      │                     ├──► audio_arc_calculate (CTS/N)
      │                     └──► voice_analysis_source (源选择)
      │                                  │ analysis_valid / analysis_left / analysis_right
      │                                  ├──► audio_waveform_overlay
      │                                  ├──► audio_fft1024 ──► audio_spectrum_overlay
      │                                  └──► secondary_hdmi_tx (HDMI_A 独立分析屏)
      │                                            ├── secondary_feature_store (+pitch_estimator)
      │                                            ├── secondary_harmonics
      │                                            ├── secondary_lissajous
      │                                            └── secondary_audio_renderer
inmp441_i2s_rx (MIC, 25MHz域 NCO) ──► mic_pcm/mic_valid ──► voice_analysis_source
```

- FFT 的“旁路”性质：`audio_fft1024` 与波形模块对 PCM **只观测、从不反压**（无 ready/ack 回传到 I2S 或科学音源）。
- 唯一握手是 FFT↔频谱叠加：`result_done` / `result_ack`（见 §1）。
- 复位：`rst_all = ~rst_n | ~audio_pll_lock`；分析链另用 `analysis_reset = rst_all | source_clear`（`source_clear` 为切换 DDS/麦克风源时的单拍脉冲）。

### 0.3 官方例程基线（用于各节“新增了什么”）

`设计参考例程文档.md` §2.4/§3.6 明确：官方例程音频链只有 **`hdmi_audio_tone_i2s_64fs` → `I2S_receiver` → `audio_arc_calculate` → HDMI 发射核**（48 kHz、N=6144、方波测试音）。本工程把音源换成 `science_audio_i2s`，并新增 FFT/频谱/波形/音高/谐波/XY/麦克风/第二屏整条分析链。

---

## 1 audio_fft1024.v — 1024 点定点 Radix-2 DIT FFT

### 1.1 端口与时钟

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `clk, rst` | in 1 | `video_clk` 25 MHz；`rst` 高有效（接 `analysis_reset`） |
| `audio_valid` | in 1 | PCM 采样有效（48 kHz 单拍） |
| `audio_left[23:0]`, `audio_right[23:0]` | in 24 | 解码后的 24 bit 立体声 PCM（有符号，二进制补码） |
| `result_ack` | in 1 | 频谱叠加完成换 bank 后的确认（单拍） |
| `spectrum_write` | out 1 | 写一列频带高度 |
| `spectrum_address[7:0]` | out 8 | `{声道, 频带号[6:0]}`，bit7=1 为右声道 |
| `spectrum_height[6:0]` | out 7 | 对数高度 0..66 |
| `result_done` | out 1 | 一块双声道处理完成 |
| `capture_start` | out 1 | 捕获第 0 个样本时置位（供 `secondary_feature_store`/`harmonics` 打标签） |
| `bin_valid` | out 1 | 每个 bin 一拍（每块 2×512 拍） |
| `bin_channel` | out 1 | 该 bin 所属声道 |
| `bin_number[8:0]` | out 9 | bin 序号 0..511 |
| `bin_magnitude[16:0]` | out 17 | `|Re|+|Im|` |

### 1.2 数据格式

| 环节 | 位宽/格式 | 缩放与饱和 |
|---|---|---|
| 输入 | 24 bit PCM，**取高 16 位 `[23:8]`**，低 8 位直接截断 | 等效 Q1.15（1 LSB = 1/32768 FS） |
| 加窗 | `window_product = s16 × w16`（32 bit，Q1.30），取 `[30:15]` | 结果 Q1.15；因 `w ≤ 32767`，不可能溢出 |
| 窗系数 | 16 bit Q0.15（周期 Hann，0..32767） | 见表 §2 |
| 旋转因子 | 32 bit = `{Re[31:16], Im[15:0]}`，各 Q1.15 | `e^{-j2πk/1024}` |
| 蝶形中间量 `tr,ti` | signed [16:0]（Q1.15 + 1 符号位） | `(33 bit 乘积差) >>> 15`，算术右移 |
| 每级输出 | 16 bit Q1.15 | **每级算术右移 1 位** + `sat16()` 饱和（±32767/−32768），不回卷 |
| 总缩放 | 10 级各 /2 → **整体 1/1024** | 与 doc 记录一致 |
| 幅值 | 17 bit 无符号 | `|Re| + |Im|`（**不是**模平方、不是 RMS/功率、未做窗增益与 dBFS 标定） |

### 1.3 算法步骤

1. **捕获**：`state==CAP` 且 `audio_valid` 时，`capture_ram[capture_index] <= {L[23:8], R[23:8]}`，共 1024 对（21.333 ms @48 kHz）。捕获满后进入计算，计算期间新到的 PCM 被**丢弃**（不拼凑不连续样本）。
2. **加窗 + 位倒序装载**（每声道一次，1024×5 拍）：
   `window_product = x16 · window_q`；`fft_ram[reverse10(n)] <= {window_product[30:15], 16'd0}`，虚部补 0。`reverse10()` 为 10 bit 位序反转。
3. **就地 DIT 蝶形**，共 10 级，第 s 级（s=0..9）：
   - `half_size = 2^s`，`base` 按 `2·half_size` 步进遍历 1024 点；
   - 蝶形对：`A = X[base+j]`，`B = X[base+j+half_size]`；
   - 旋转因子地址 `k = j << (9 − s)`（`twiddle_shift` 从 9 递减到 0，最大用到 ROM 第 511 项）；
   - 复乘（4 个 16×16 有符号乘法器，两级寄存）：
     `tr = (br·Wr − bi·Wi) >>> 15`，`ti = (br·Wi + bi·Wr) >>> 15`；
   - 蝶形（33 bit 中间和，右移 1 位、饱和后写回）：
     `X[base+j]          = sat16((ar+tr)>>1) + j·sat16((ai+ti)>>1)`
     `X[base+j+half]     = sat16((ar−tr)>>1) + j·sat16((ai−ti)>>1)`
4. **左右时分复用**：先左后右。`channel` 选择 `capture_q[31:16]`（左）或 `capture_q[15:0]`（右）；左声道 512 个 bin 输出完后，`channel<=1` 并重新装载右声道（再 1024×5 拍 + 5120 蝶形）。
5. **幅值 + 频带聚合 + 对数映射**：见 1.4。

### 1.4 幅值、频带与频率轴

- 幅值：`abs_re = |fft_q[31:16]|`，`abs_im = |fft_q[15:0]|`（二进制补码取负），`magnitude = abs_re + abs_im`（17 bit，最大 65536）。
- 只读取 **bin 0..511**（正频率半轴）；bin 512（Nyquist）由蝶形算出但不输出、不聚合。
- **128 个显示频带**，每带取组内 `magnitude` 的**最大值**（`band_max`），`remaining` 计数控制合并数：

| 频带号 | 每带 bin 数 | bin 范围 | 频率范围（46.875 Hz/bin） |
|---|---|---|---|
| 0..31 | 1 | 0..31 | 0 .. 1453.1 Hz（边界 1500 Hz） |
| 32..63 | 2 | 32..95 | 1500 .. 4453.1 Hz（边界 4500 Hz） |
| 64..95 | 4 | 96..223 | 4500 .. 10453.1 Hz（边界 10500 Hz） |
| 96..127 | 9 | 224..511 | 10500 .. 23953.1 Hz |

带中心频率：`f(b) = 46.875 × (b)`(b≤31)；`46.875 × (32.5+2(b−32))`(32≤b≤63)；`46.875 × (97.5+4(b−64))`(64≤b≤95)；`46.875 × (228+9(b−96))`(96≤b≤127)。

- **对数高度**（`log_height`，组合逻辑）：令 `e = MSB位置(value)`，`frac = (value<<3)>>e ∈ [8,15]`，
  `level = (e−2)×6 + ((frac−8)×6 >> 3)`，即 **≈ 6·log2(value) − 12 像素**（6 像素/倍幅 ≈ 6 dB/oct）；
  `value<4` 或 `level<0` → 0；`level>66` → 66。故柱高 0..66 px，**幅值 ≥ 2^13 = 8192（Q1.15 下的 0.25）即顶满 66 px**，不再增高；4 个 FFT LSB 以下不绘柱。

### 1.5 状态机与流水线

20 个状态（5 bit）：`CAP(0), LOAD_R(1), LOAD_W(2), LOAD_M(3), LOAD_S(4), LOAD_NEXT(5), RA(6), WA(7), RB(8), WB(9), MUL(10), ROT(11), SUM(12), WRITE_A(13), WRITE_B(14), NEXT(15), MAG_R(16), MAG_W(17), MAG_L(18), WAIT_ACK(19)`。

| 迁移 | 条件 |
|---|---|
| CAP → LOAD_R | `capture_index==1023` 且 `audio_valid` |
| LOAD_R→W→M→S→NEXT | 固定 5 拍/样本；`load_index==1023` → `stage=0, half=1, shift=9` → RA |
| RA→WA→RB→WB→MUL→ROT→SUM→WRITE_A→WRITE_B→NEXT | **每蝶形固定 10 拍**（读A/存A/读B/存B/乘/旋转/蝶形/写A/写B/指针） |
| NEXT | `j==half−1` 且 `base+2·half≥1024`：`stage==9` → MAG_R；否则 `stage+1, half<<1, shift−1` → RA |
| MAG_R→MAG_W→MAG_L | 3 拍/bin；`MAG_L` 内每 `remaining` 个 bin 发一次 `spectrum_write` 并推进 `band_index` |
| MAG_L | `bin_index==511`：左声道 → `channel=1, load_index=0` → LOAD_R；右声道 → `result_done=1` → WAIT_ACK |
| WAIT_ACK → CAP | `result_ack`（即下一个 VS 换 bank 后） |

**周期数（可复算）**：每声道 `1024×5（装载）+ 5120×10（蝶形）+ 512×3（幅值）= 57 856` 拍；两块 = **115 712 拍 = 4.63 ms @25 MHz**（工程文档实测记录 115 714 拍，差 2 拍为状态开销）。

**帧节拍**：捕获 21.33 ms + 计算 4.63 ms + 等待 VS ⇒ 单块 ≥ 25.96 ms，实际约 **每 2 个视频帧（≈33.6 ms）更新一次频谱**，更新率 ≈ 30 Hz 上限。

### 1.6 资源

| 资源 | 规模（由数组组织折算） |
|---|---|
| `capture_ram` | 1024×32 简单双口（4 KiB）≈ 4 个 9K BRAM |
| `fft_ram` | 1024×32（4 KiB）≈ 4 个 9K BRAM |
| 系数 ROM | `twiddle` 512×32（16 kbit）+ `window` 1024×16（16 kbit）≈ 4 个 9K BRAM（与文档“4 个系数 BRAM”一致） |
| 乘法器 | **5 个 16×16 有符号**（4 个蝶形 + 1 个加窗） |
| 其他 | 幅值/对数/饱和为纯组合逻辑；无除法器 |

### 1.7 相对官方例程

全新模块：官方例程无任何频域处理。FFT 系数表由 `tests/generate_fft_vectors.py --tables` 生成并固化为常量，运行时不依赖文件路径。

> **报告可用的表述**：`audio_fft1024` 在 25 MHz 视频域内以“捕获—冻结—左右时分复用”的方式实现 1024 点 16 bit 定点 Radix-2 DIT FFT：输入取 24 bit PCM 高 16 位、周期 Hann 窗 Q0.15、每级算术右移 1 位并饱和，整体增益 1/1024，幅值取 `|Re|+|Im|`，按 1/2/4/9 bin 的 128 组取最大值后经 6 像素/倍频程的近似 log2 映射为 0..66 像素柱高，单块双声道耗时 115 712 拍（4.63 ms），频谱刷新受 VS 节流约每两帧一次。

---

## 2 fft1024_tables.v — 系数 ROM

| 项 | 内容 |
|---|---|
| 端口 | `clk, twiddle_address[8:0], window_address[9:0] → twiddle_q[31:0], window_q[15:0]`（输出寄存，1 拍延迟） |
| 旋转因子 | `twiddle_rom[0:511]`，32 bit/项（`{[31:16]=Re(Q1.15), [15:0]=Im(Q1.15)}`），**512 项 = 16 kbit**，`e^{-j2πk/1024}`；`[0]=0x7FFF0000`，`[256]=0x00008001`，`[511]=0x8002FF37`（≈−1−j0.006） |
| 窗系数 | `window_rom[0:1023]`，16 bit Q0.15，**1024 项 = 16 kbit**，**周期** Hann：`w[n]=round(32767·0.5·(1−cos(2πn/1024)))`；`w[0]=0`、`w[511]=0x7FFF`、`w[512]=0x7FFF`、`w[1023]=1`（非对称窗，端点不重复） |
| 存储方式 | `reg` 数组 + `initial` 块初始化 → 综合为 ROM（BRAM/M9K），综合网表已验证 INIT 内容 |
| 总容量 | 32 kbit ≈ **4 个 9K BRAM** |
| 新增 | 全新；替代“浮点/运行时三角函数”方案，避免 DSP 与除法 |

> **报告可用的表述**：全部频域系数以常量表固化——512 个 32 bit Q1.15 复旋转因子（16 kbit）与 1024 个 16 bit Q0.15 周期 Hann 系数（16 kbit），共 32 kbit 片上 ROM，运行时零三角函数运算。

---

## 3 audio_spectrum_overlay.v — 频谱叠加绘制

### 3.1 端口与布局

| 端口 | 位宽 | 说明 |
|---|---|---|
| `clk,rst,hs,vs,de` | 1 | 视频时序（来自波形模块输出的 `hs_waveform…`，已延迟 2 拍） |
| `rgb_in/rgb_out` | 24 | RGB888 直通/叠加 |
| `panel_visible` | 1 | 来自波形模块的 VS 锁存开关（同一 KEY3 状态） |
| `voice_mode` | 1 | = `display_lesson_idx==5`（人声页） |
| `spectrum_write / spectrum_address[7:0] / spectrum_height[6:0]` | | FFT 写入 |
| `result_ack / result_done` | 1 | 与 FFT 的换 bank 握手 |

- 面板区域：`px∈[48,591]`、`py∈[120,236]`，边框色 `#60849A`；柱状区 `px∈[64,576)`、`py∈[148,214]`（基线 214，柱高 ≤66 ⇒ 顶端 148）。
- 双 bank：`left_ram[0:255]`、`right_ram[0:255]`（各 7 bit×256，`{bank, band[6:0]}`）；**只在 VS 上升沿交换** `display_bank/write_bank`，交换后回 `result_ack`，因此 FFT 不会覆盖待显示数据。
- 无有效 PCM 计时：`NO_AUDIO_CYCLES = 6 250 000`（25 MHz → **250 ms**），超时清 `display_valid`（不显示冻结旧谱）。

### 3.2 绘图与映射

| 项 | 值/规则 |
|---|---|
| 每频带宽度 | 4 px（`read_band_index = graph_x[8:2]`，`graph_x = px−64`） |
| 立体声 | 带内 `graph_x[1]`：0 → 左（`#52E3FF` 青），1 → 右（`#FFE66D` 黄），**每声道 2 px**，同带并排显示而非叠加 |
| 柱判定 | `py > 214 − height` 且 `height≠0` |
| 网格 | `px=64/192/320/448/575`、`py=148/170/192/214`，色 `#294052` |
| 标题文字 | 5×7 字模、8 px/字符：`FFT 1024 48K`（px 64..256），`L`(488)/`R`(536) 声道标记 |
| 频率刻度 | `0`(px64)、`1.5K`(176)、`4.5K`(304)、`10.5K`(432)、`24K`(552)，对应 bin 0 / 32 / 96 / 224 / 511 |

**人声模式（`voice_mode=1`）**：
- 复用同一块 log-band RAM，但**重映射读取索引**（不是第二套 FFT、不是插值）：

  `voice_scaled_x = 42·graph_x`（`<<5 + <<3 + <<1` 三个移位相加），
  `voice_bin = 2 + (voice_scaled_x >> 9) = 2 + floor(42·graph_x/512)` ∈ **[2,43]**，
  `voice_band = voice_bin<32 ? voice_bin : 16 + (voice_bin>>1)` ∈ [2,31]∪[32,37]。
- 覆盖频率：bin 2..43 = **93.75 Hz .. 2015.625 Hz（≈0.1–2 kHz）**，512 px 均匀展开 ⇒ **12.19 px/bin**（原图 4 px/带）。
- 柱高只读左 bank（单声道），统一色 `#5BDAC6`；`R` 标记隐藏、`L` 改为 `M`；刻度改为 `0.1K / 1K / 2K`。
- 顶层另做“去毛刺”：`displayed_spectrum_height = (voice_page && height<8) ? 0 : height`（两块屏共用同一高度）。
- 说明：该模式读取的仍是原 log-band 的 1/2 bin 最大值（bin 2..43），**分辨率由 FFT 决定，未被重采样放大**；像素被展宽 3 倍。

### 3.3 流水线/资源

- 像素管线 **2 拍**（`px/py/pixel_q/valid_q/visible_q` 与 `hs/vs/de` 两级寄存），叠加后 `rgb_out<=de_pipe[0]?composed:0`。
- 资源：2×256×7 bit 双 bank RAM（≈1 个 9K BRAM）、常量字模 case 逻辑；无乘法器。

> **报告可用的表述**：频谱叠加把 128 个频带以 4 px/带的宽度画在 512×66 px 区域内（带内 2 px 左青、2 px 右黄），双 bank 只在 VS 交换；人声页不新建 FFT，而是用 `bin = 2 + floor(42·x/512)` 的一次线性索引重映射，把 bin 2..43（93.75–2015.6 Hz）铺满同一 512 px，实现约 0.1–2 kHz 的“频谱聚焦”。

---

## 4 audio_waveform_overlay.v — 双声道时域波形

| 项 | 值 |
|---|---|
| 端口 | `clk,rst,hs,vs,de,rgb_in[23:0], audio_valid, requested_visible, voice_mode, audio_left[23:0], audio_right[23:0] → hs_out,vs_out,de_out, panel_visible, rgb_out[23:0]` |
| 存储 | `wave_ram[0:511]`×24 bit（2 bank×256 点），每字打包 **当前+前一点**：`{[23:18]=L_cur,[17:12]=L_prev,[11:6]=R_cur,[5:0]=R_prev}`；单读口即可画竖线段 |
| 采样窗口 | 256 点 = **5.333 ms @48 kHz**，每点 2 px（512 px） |
| 增益 | 1 垂直像素 = 65536 PCM LSB：`scaled = sample >>> 16`（24 bit 全位宽算术移位），`level = 31 − scaled`，`|scaled|>31` 饱和到 0/62（不回卷） |
| 绘图区 | `px∈[64,576)`；左声道 `py∈[255,317]`（中心 286），右声道 `py∈[339,401]`（中心 370）；色 `#52E3FF` / `#FFE66D` |
| 触发 | 左声道**上升过零**：`trigger = previous_negative && !audio_left[23]`（`previous_negative` 每 `audio_valid` 更新）；若 255 点内无触发则强制采集（`trigger_wait==255`），即自由运行 |
| 段绘制 | `between(py−offset, cur_level, prev_level)` 画竖线 ⇒ 相邻样本间自动连成折线 |
| 换 bank | `capture_bank/display_bank` 乒乓，**只在 VS 上升沿交换**；`pending` 表示一帧已采满 |
| 无音保护 | 250 ms（6 250 000 拍）无 `audio_valid` → 清 `display_valid/pending`，不把冻结旧迹当实时 |
| 人声模式 | 右声道轨迹改为**全波整流幅度**：`abs = |R|`，`level = 31 − abs[20:16]`，`abs≥0x1F0000(2 031 616)` 视为顶格；标签 `L/R` → `W`（signed 波形）/`A`（absolute amplitude） |
| 面板 | `py∈[238,416)`（含边框与网格 `py=255/286/317/339/370/401`）；`panel_visible` 输出给频谱模块保持两块面板同帧开关 |
| 流水线 | 2 拍（RGB/HS/VS/DE 同延），与频谱模块合计 **4 拍** |
| 资源 | 512×24 bit RAM（2 bank）≈1–2 个 9K BRAM；`>>>16` 为接线，无乘法器 |

> **报告可用的表述**：波形叠加在 I2S 解码后取 256 个连续立体声样本（5.33 ms），每样本 2 像素、单像素对应 65 536 LSB（±31 像素裁剪），左声道上升过零触发、255 点超时自由运行，两点电平以 `between()` 连成竖线段形成示波器折线；人声页把右声道换为 `|R|` 幅度包络（W/A 双迹）。

---

## 5 audio_arc_calculate.v — ACR（CTS/N）

| 项 | 值 |
|---|---|
| 端口 | `I_clk, I_rst, I_audio_valid, O_acr_valid, O_acr_cts[19:0], O_acr_n[19:0]` |
| 参数 | `ACR_N = 6144`；`AUDIO_DIV = ACR_N >> 7 = 48`（48 个采样 = **1 ms** @48 kHz） |
| 算法 | 8 bit 分频计数 `S_audio_div_cnt` 数 `audio_valid`；每到 48 个产生 `S_audio_valid_div`；20 bit 计数器 `S_acr_cts_cnt` 在此期间数 `I_clk`（25 MHz），输出 `CTS = cnt+1`，`N = 6144` |
| 数值 | 25 MHz×1 ms ⇒ **CTS ≈ 25 001**（每 1 ms（48 采样）刷新一次，抖动 ±1 拍） |
| 复位 | 异步高有效；输出寄存无复位（`always @(posedge I_clk)`） |
| 新增 | **与官方例程完全相同**（官方即 `ACR_N=6144`、同一 RTL） |

> **报告可用的表述**：`audio_arc_calculate` 每 48 个音频采样（1 ms）用 25 MHz 计数得到一个 CTS≈25 001、N 恒为 6144 的 ACR 包参数，供 HDMI 接收端重建 48 kHz 音频时钟；该模块与官方例程一致，未作修改。

---

## 6 secondary_pitch_estimator.v — 主峰音高估计

### 6.1 端口与通道复用

| 端口 | 位宽 | 说明 |
|---|---|---|
| `clk,rst,clear` | 1 | `clear` 接 `scene_clear`（换页） |
| `bin_valid, bin_channel, bin_number[8:0], bin_magnitude[16:0]` | | 直接来自 `audio_fft1024` 的被动观测口 |
| `left_feature[79:0] / right_feature[79:0]` | 80 | 特征字（布局见下） |
| `feature_done` | 1 | **右声道**发布完成时单拍（每块一次） |

80 bit 特征字布局（与文件头注释一致）：

| 位域 | 宽 | 含义 |
|---|---|---|
| [79] | 1 | `good_signal`（有效） |
| [78:64] | 15 | `frequency_hz`（整数 Hz） |
| [63:44] | 20 | BCD 5 位十进制（万/千/百/十/个） |
| [43:40] | 4 | 音级 0..11（0=C..11=B，含升降） |
| [39:37] | 3 | 八度 2..6 |
| [36] | 1 | `note_valid`（落在 C2..B6 内） |
| [35:19] | 17 | 峰值 `|Re|+|Im|` |
| [18:13] | 6 | 音名序号 0..59（C2=0..B6=59） |
| [12:7] | 6 | 轨迹位置 0..47（代表 100..1000 Hz） |
| [6:0] | 7 | 保留 0 |

### 6.2 算法（含公式）

1. **扫描取峰**（`SCAN`，随 `bin_valid` 逐 bin）：`peak = max(bin≥2)`，`peak_bin` 为首个最大值；同时 `left_mag = mag[peak_bin−1]`（用 `previous_mag`）、`right_mag = mag[peak_bin+1]`；`spectral_sum = Σ_{bin≥2} mag`（跳过 bin 0/1，抑制 DC 与最低频）。
2. **有效判据**：`good_signal = (peak ≥ 32) && (peak ≥ spectral_sum/64)`（峰值至少占总和 1/64 ≈ 1.6%）。搜索范围即全部 512 bin（0..23953 Hz），无额外带限。
3. **三点抛物线插值**（`INTERP` + 24 步恢复余数除法 `DIVIDE`）：
   - `Δ = |R−L|`，`D = 2P − L − R`；
   - `delta_q8 = min(128, floor(128·Δ / D))`，符号取 `sign(R−L)` ⇒ **δ = 0.5·Δ/D（单位 bin），以 Q8（1/256 bin）定点存储**，限幅 ±0.5 bin；
   - 保护：`peak_bin==511`、`2P≤L+R` 或 `!good_signal` 时 `delta=0`。
4. **频率换算**（`QBIN`/`HZ`）：`qbin = peak_bin·256 + delta`（Q8 bin）；
   `raw_hz = (375·qbin + 1024) >> 11`。其中 `375/2048 = 46.875/256`，故
   **`f = 46.875 × qbin/256` Hz（四舍五入到 1 Hz）**；`!good_signal` 时 `raw_hz=0`。
   乘法用移位加实现：`qext·(256+64+32+16+4+2+1) = qext·375`。
5. **平滑**（`SMOOTH`）：仅当 `good_signal && 上一块有效 && |raw_hz − prior_hz| ≤ 10 Hz` 时做两帧平均 `f = (raw + prior + 1)>>1`；否则直接取 `raw`。**不做跨音符/静音的平均**。
6. **音名映射**（`NOTE`）：`f<64 Hz` 或 `!good` → 无效；否则从 `note_index=0`（C2）起顺序比较 `f ≤ upper_hz[index]`（表见 §7），命中即有效；每跨 12 个音升一个八度（初值 2），最多到 index 59（B6）。
7. **轨迹位置**（`SCALE`）：`pos = floor(47·(f−100)/900)`，`f≤100` → 0，`f≥1000` → 47（`47 = 32+8+4+2+1` 移位加；除数 900 用同一 24 步除法器）。⇒ 轨迹纵轴 **线性**覆盖 100..1000 Hz，**1000 Hz 以上被钉在顶端**。
8. **BCD**（`BCD_INIT/BCD_STEP`）：对 15 bit `frequency_hz` 做 17 步 double-dabble（`≥5 加 3`），得 5 位十进制。
9. **发布**（`PUBLISH`）：左声道写 `left_feature`，右声道写 `right_feature` 并置 `feature_done`；同时把**未平滑**的 `raw_hz` 与 `good_signal` 存为下一块 `prior`。

### 6.3 状态机与开销

12 状态：`SCAN, INTERP, DIVIDE, RETURN, QBIN, HZ, SMOOTH, NOTE, SCALE, BCD_INIT, BCD_STEP, PUBLISH`。
额外开销：两次 24 步除法（插值 + 轨迹）+ 17 步 BCD + 最多 60 次比较，约 70–130 拍/声道，相对 512 bin 扫描可忽略；每块每声道一次。无 RAM、无乘法器、无 DSP。

> **报告可用的表述**：音高估计完全复用 FFT 的 bin 流——在 0..511 bin 中取最大幅值 bin，用 `δ=0.5(R−L)/(2P−L−R)` 的三点抛物线插值（Q8 定点、限幅 ±0.5 bin、24 步串行除法）把频率细化到 `f=46.875·(b+δ)` Hz，再经“峰值≥32 且≥总和/64”的门限、两帧（|Δf|≤10 Hz 才平均）平滑，用等比中分界表映射到 C2..B6 并给出 5 位 BCD 频率与 100..1000 Hz 线性轨迹位置。

---

## 7 secondary_note_thresholds.v — 音名分界表

| 项 | 内容 |
|---|---|
| 端口 | `index[5:0] → upper_hz[14:0]`（纯组合 case） |
| 内容 | 60 项，MIDI 36(C2)..95(B6)，A4=440 Hz 十二平均律 |
| 数值性质 | 每项为相邻半音频率的**几何中点**（对数域中点），四舍五入到整数 Hz：`upper[i] = round(sqrt(f_i · f_{i+1}))` |
| 关键值 | C2 上界 67、C3 135、C4 269、C5 539、C6 1077、B6 上界 **2033** |
| 比较方式 | 每个 FFT 块顺序比较一次，**不是逐像素**；无 ROM、纯 LUT |
| 新增 | 全新（官方例程无音名功能） |

> **报告可用的表述**：音名判定用 60 项整数门限表（C2..B6，几何中点分界，67…2033 Hz），每块只做一次顺序比较，避免逐像素除法与浮点。

---

## 8 secondary_harmonics.v — H1..H5 谐波柱

### 8.1 端口与门控

| 端口 | 位宽 | 说明 |
|---|---|---|
| `clk,rst,frame_tick,scene_clear,audio_stale` | 1 | 发布/清零门控 |
| `lesson[2:0], lesson_valid` | | **仅 `lesson==2`（TIMBRE 页）工作** |
| `bin_valid,bin_channel,bin_number[8:0],bin_magnitude[16:0]` | | 被动观测；`capture_start` 仅为端口兼容，**逻辑中未使用** |
| `shown_feature[79:0], analysis_feature[79:0], analysis_ready` | | 音高特征（用 analysis 那份，保证同块） |
| `harmonic_heights[29:0]` | 30 | 5×6 bit，H1..H5 柱高 |
| `harmonic_valid` | 1 | 发布有效（VS 更新） |

### 8.2 算法

1. **幅值缓存**：`magnitude_ram[0:127]`（17 bit），在 `lesson==2 && bin_valid && !bin_channel && bin_number<128` 时写入 ⇒ 只存**左声道 bin 0..127（0..5953 Hz）**，覆盖 1000 Hz 的 H5（5000 Hz）。
2. **H_n 定位**（`IDLE`）：取 `f0 = analysis_feature[78:64]`，要求 `valid && 100 ≤ f0 ≤ 1000`；令 `step = 8·f0`（`f0<<3`），`rem = 8·f0 + 187`。
3. **重复减 375**（`LOCATE`）：`while rem ≥ 375: rem −= 375; bin++` ⇒ `bin_n = floor((8·n·f0 + 187)/375) = round(n·f0/46.875)`（**最近 bin**，+187 为 375/2 四舍五入项）。H1..H5 最大 106（f0=1000）≤ 127。
4. **±1 bin 邻域取最大**（`WAIT_RAM`/`READ_RAM`，每次读 2 拍，共 3 次）：`H_n = max(mag[bin_n−1], mag[bin_n], mag[bin_n+1])`（补偿 Hann 主瓣与栅栏效应）。
5. **以 H1 归一化**（`NORM`/`SCALE`）：
   - `H1 = H_0`（index 0 的邻域峰值）；`H1 < 32` ⇒ 全部柱高 0、无效；
   - `H_n ≥ H1` ⇒ 高度 = 38（顶格）；
   - 否则用 **38 次逐次累加**求 `height = floor(38·H_n/H1)`（`scale_sum = rem + H_n`，`≥H1` 则减 `H1` 并 +1），**避免 17 bit 除法器**；高度范围 **0..38**。
6. **发布**（`SAVE` + `frame_tick`）：`working_heights[index*6+:6] <= height`；5 个全算完后 `pending=1`，下一 `frame_tick` 提交 `harmonic_heights`，`harmonic_valid = pending_valid`；`audio_stale` 或离开第 2 课时清零。
7. **柱高显示**：`secondary_audio_renderer` 中 `px∈[94+96h, 130+96h)`、基线 `py=448`，柱顶 `448−height`，H1 用琥珀 `#E9C477`、H2..H5 用青绿 `#5BDAC6`，下方标 `H1..H5`。

### 8.3 状态机与开销

7 状态：`IDLE, LOCATE, WAIT_RAM, READ_RAM, NORM, SCALE, SAVE`。
每谐波 ≈ `locator_bin`（≤106）次减 + 6 拍读 RAM + 1 + 38 + 1 ≈ **≤152 拍**；5 个谐波 ≈ **≤760 拍 ≈ 30 µs @25 MHz**，相对 4.63 ms 的 FFT 计算可忽略。资源：128×17 bit RAM（≈2 kbit，1 个 9K BRAM），无乘法器、无除法器。

> **报告可用的表述**：谐波柱把 `f0` 换算成 `n·f0/46.875` 的最近 bin（`floor((8·n·f0+187)/375)`，H5≤bin 106），取 ±1 bin 邻域最大值作 `H_n`，以同块 H1 归一化后用 38 次串行累加求 `floor(38·H_n/H1)` 得到 0..38 像素柱高，只在 TIMBRE 页工作、只在 VS 提交，整组 5 柱开销 <800 拍。

---

## 9 secondary_lissajous.v — XY 李萨如

| 项 | 值 |
|---|---|
| 端口 | `clk,rst,frame_tick,scene_clear,audio_stale, lesson[2:0], lesson_valid, audio_valid, audio_left[23:0], audio_right[23:0], xy_read_address[11:0] → xy_q, xy_visible` |
| 存储 | `reg plane[0:8191]` = **2 个平面 × 64×64 = 4096 bit/面，共 8192 bit（1 KiB）**，1 bit/点；地址 `{bank, y[5:0], x[5:0]}` |
| 取样条件 | `lesson_valid && lesson==3`（STEREO 页）且 `audio_valid` ⇒ **同一时刻的 L/R PCM 对**，无插值、无延时补偿 |
| 坐标映射 | `x = 32 + L[23:16]`，`y = 32 − R[23:16]`；裁剪：`L>31 → x=63`，`L<−31 → x=1`；`R>31 → y=1`，`R<−31 → y=63`（**R 正向上**，保留 1 px 边距） |
| 增益 | 1 平面像素 = **65 536 PCM LSB**（取高 8 位 `[23:16]`）；±31 px ⇒ ±2^21 ≈ ±1/4 FS（≈ −12 dBFS 即触边，源码注释称 "signed gain 4"） |
| 每面样本数 | **512**（`sample_count 0..511`，48 kHz ⇒ **10.67 ms/面**） |
| 换面时机 | `READY` 态等 **`frame_tick`（VS）** 才 `front_bank<=write_bank`，绝不在帧内交换 |
| 清屏 | `CLEAR` 态逐拍写 0，4096 拍（163.8 µs）；清完才采集 |
| 读取/显示 | `xy_read_address = {xy_y[6:1], xy_x[6:1]}`，`xy_x=x−432`、`xy_y=y−192` ⇒ 显示窗 128×128 px（`px∈[432,560)`、`py∈[192,320)`），**每面像素占 2×2 屏幕像素**；颜色 `#5BDAC6`，中心十字线 `#294858` |
| 无效处理 | `!active` 或 `scene_clear` 或（`frame_tick` 且 `audio_stale`）→ 回 CLEAR、`xy_visible=0` |
| 资源 | 8192×1 bit（分布式 RAM/LUTRAM，不占 9K BRAM），无乘法器/DSP |

> **报告可用的表述**：XY 李萨如用 2 个 64×64 单 bit 平面（共 8192 bit，不用帧缓存）记录同一时刻左右声道的散点：`x=32+L[23:16]`、`y=32−R[23:16]`，1 px 对应 65 536 LSB 并在 ±31 px 处对称裁剪，每面采集 512 个样本（10.67 ms）后只在 VS 换面，显示窗 128×128 px（每面像素 2×2 屏像素）。

---

## 10 secondary_feature_store.v — 特征存储 / 瀑布图 / 电平

### 10.1 结构与端口

| 项 | 内容 |
|---|---|
| 端口（输入） | `clk,rst,frame_tick,scene_clear, lesson[2:0], lesson_valid, audio_valid, audio_left[23:0], audio_right[23:0], capture_start, bin_valid, bin_channel, bin_number[8:0], bin_magnitude[16:0], spectrum_write, result_done, spectrum_address[7:0], spectrum_height[6:0], read_column[6:0], read_band[5:0]` |
| 端口（输出） | `heat_q[3:0], trace_q[7:0], shown_head[6:0], shown_count[6:0], shown_feature[79:0], shown_right, peak_left/peak_right[7:0], average_left/average_right[7:0], analysis_ready, audio_stale, analysis_feature[79:0]` |
| 存储 | `heat_ram[0:8191]`×4 bit（128 列×64 带，**32 kbit = 4 KiB**）；`trace_ram[0:127]`×8 bit；`column_levels[255:0]`（64 带×4 bit 组装寄存器） |
| 列组织 | **128 个物理列，96 列可见**（`read_column = shown_head − 96 + cell_x`，7 bit 自动回绕）；多余 32 列作为写入侧保护 |
| 发布时机 | 只在 `frame_tick`（VS）更新 `shown_head/shown_count/shown_feature/电平` |
| 内嵌子模块 | `secondary_pitch_estimator estimator(...)`（`clear=scene_clear`） |

### 10.2 算法

1. **瀑布列更新（每 FFT 块一列）**：`spectrum_write && !copying && spectrum_address[6:0]<64` 时把高度压缩成 4 bit：
   `level = (height ≥ 60) ? 15 : height[5:2]`（即 `height>>2`，0..14；≥60 顶格 15）；
   左声道写 `column_levels[band*4+:4]`，右声道取 **max**（`compressed > 原值` 才覆盖）⇒ **L/R 合并方式为逐带取最大**，不构造“单声道/相位关系”。
2. **提交（每块一次）**：当 `feature_done && (fft_ready||result_done) && block_valid && captured_lesson==lesson && lesson_valid && !copying && !pending` 时锁存 `pending_feature = selected_feature`（`selected = 左有效 ? 左 : 右`）、`copying=1`，随后 64 拍把 64 个 4 bit 带拷进 `heat_ram[{write_column, band}]`，并把
   `trace_ram[write_column] <= {valid, right_flag, trace_position[5:0]}`（8 bit：bit7 有效、bit6 右声道、bit5..0 轨迹）。
   写完后 `write_column++`、`pending=1`，下一 VS 更新 `shown_head`（`shown_count` 最多 96）。
3. **块合法性**：`capture_start` 时锁存 `captured_lesson = lesson_d`（上一拍的 lesson），并校验 `valid_d && lesson_d==lesson`；换页或 `!lesson_valid` 清 `block_valid`，避免把上一课/上一块的频谱与音高拼在一起。
4. **电平统计（1024 采样窗 = 21.33 ms）**：`abs = |PCM[23:8]|`（16 bit），
   `peak = max(abs)`，`sum += abs`；窗口结束（`level_count==1023`）时
   `average = sum[25:10] = Σabs/1024`（**平均绝对值，不是 RMS**），
   两者都送 `bar_length(v) = (7v) >> 10`（即 `v` 映射到 0..224 像素；满幅 32767 → 224）。
   只在 VS 发布，`audio_stale` 时输出 0。
5. **无音检测**：`NO_AUDIO_CYCLES = 6 250 000` ⇒ **250 ms**，`audio_stale` 同时送给谐波与 XY 模块。

### 10.3 频率轴（瀑布 64 带）

前 64 个 log 带，纵轴自下而上：

| 带 | bin | 带宽 | 屏幕行（`py`） |
|---|---|---|---|
| 0..31 | 0..31 | 46.875 Hz | 349..351（底）… |
| 32..63 | 32..95 | 93.75 Hz | … 160..162（顶） |

`frequency_band` 从 63 递减到 0，每带 3 行（其中 2 行绘制、1 行留缝），共 192 行（`py 160..351`）；刻度 `0`(py344)、`1.5K`(253)、`4.5K`(160)。

> **报告可用的表述**：特征存储用 128 个物理列（96 列可见）的 64×4 bit 热力 RAM 保存频谱历史，每个 FFT 块写入一列（4 bit = `height>>2`，≥60 顶格），左右声道逐带取最大值；同一列附 8 bit 轨迹字（有效位/声道位/0..47 音高位置），只在 VS 发布；另用 1024 采样窗给出峰值与平均绝对值电平（0..224 像素）。

---

## 11 secondary_audio_renderer.v — 第二屏渲染（接口与页面映射）

### 11.1 接口与节拍

| 项 | 值 |
|---|---|
| 端口 | `clk,rst(25MHz), lesson[2:0], lesson_valid, video_locked, heat_q[3:0], trace_q[7:0], shown_head[6:0], shown_count[6:0], shown_feature[79:0], shown_right, peak_*/average_*[7:0], harmonic_heights[29:0], harmonic_valid, xy_q, xy_visible → xy_read_address[11:0], frame_tick, scene_clear, read_column[6:0], read_band[5:0], axis_user/valid/last, axis_data[23:0]` |
| 光栅 | `col 0..799`、`line 0..524`（800×525），25 MHz ⇒ 59.52 Hz；`active = col≥160 && line≥45`，`x=col−160`、`y=line−45`（640×480） |
| 节拍 | `frame_tick = (col==0 && line==0)`；`scene_clear = frame_tick && (lesson≠shown_lesson || lesson_valid≠shown_valid)` |
| 流水线 | **2 拍**（`px/py/...`、`user_pipe/valid_pipe/last_pipe`），`axis_data <= valid_pipe[0]?composed:0`；AXIS `user/last` 与数据同延 |
| 存储 | 无帧缓存；仅组合字模 `secondary_font5x7`（35 bit/字符）+ 16 级调色板 |

### 11.2 页面映射（lesson 0..5 = 第 1..6 页）

| lesson | 标题 | 音频相关显示要素 |
|---|---|---|
| 0 | `PITCH` | 音名（`note_letter`+`#`+八度）、5 位 BCD 频率、`F0~`、`FFT / L|R`、`48K / 1024`、瀑布 + 音高轨迹 |
| 1 | `LEVEL` | 峰值/平均电平条（`PK`/`AVG`，L/R 各一条），瀑布 + 轨迹 |
| 2 | `TIMBRE` | **H1..H5 谐波柱**（`py 448` 基线，`px 94+96h..130+96h`），标题 `HARMONICS` |
| 3 | `STEREO` | **窄版布局**（`narrow=1`）：瀑布 96 列×3 px、右侧 **XY 李萨如窗 128×128 px**（`px 432..560`,`py 192..320`），标题 `STEREO LEVEL`/`STEREO XY` |
| 4 | `MUSIC` | 与 0 相同（页名 `MUSIC`），用于观察旋律的音高/频谱变化 |
| 5 | `LIVE VOICE` | 隐藏音名/`PK~`/`HZ` 文本块（`px 40..320, py 74..108`），标签 `MIC / MONO`、`PK~`，电平条 + 瀑布 + 轨迹 |

### 11.3 关键坐标常量

| 元素 | 范围 |
|---|---|
| 主标题 `SOUND LAB` | `px 24..312`、`py 24..38`（2× 字模） |
| 页码/页名 | `px 448..592`、`py 28..35`（`0N/ <PAGE>`） |
| 锁定指示 | `px 600..608`、`py 28..36`（绿=锁定，黄=未锁） |
| 瀑布 | `px 64..(narrow?352:544)`、`py 160..352`；单元 5 px（窄 3 px）×3 行 |
| 颜色图例 | `px 568..576`（窄 360..368），色 = `palette(frequency_band[5:2])` |
| 音高轨迹 | `px 64..544`、`py 408..455`（`y = 455 − trace[5:0]`，`py=455`=100 Hz、`408`≈1000 Hz）；100 Hz/1 kHz 刻度、1 K 网格线 |
| 电平条 | 峰值 `py 412..423`（L `px 80..303`、R `352..575`）；平均 `py 440..447` |
| 谐波柱 | 基线 `py 448`，列宽 36 px，间距 96 px，高 0..38 |

### 11.4 资源

无 RAM/DSP/乘法器；`palette()` 与文字为 case/移位逻辑；`heat_q` 4 bit 直接索引 16 级调色板（`#0D2637`→`#FFE1A0`）。

> **报告可用的表述**：第二屏渲染器以 25 MHz、800×525 光栅产生独立 640×480 AXIS 视频流，把 6 个页面映射为 PITCH/LEVEL/TIMBRE/STEREO/MUSIC/LIVE VOICE：瀑布 96 列×64 带、音高轨迹（基线 455，`y=455−pos`）、H1..H5 五根 36 px 柱（基线 448）、以及 STEREO 页的 128×128 px XY 窗口，全部数据来自特征存储与谐波/XY 模块且只在 VS 提交。

---

## 12 voice_analysis_source.v — 麦克风条件化（噪声门 + AGC）

### 12.1 端口与选择关系

| 端口 | 位宽 | 说明 |
|---|---|---|
| `clk,rst` | 1 | `video_clk` / `rst_all` |
| `lesson[2:0], lesson_valid` | | `selected = lesson_valid && lesson==5`（第 6 页） |
| `dds_valid, dds_left[23:0], dds_right[23:0]` | | 来自 `I2S_receiver`（科学音源） |
| `mic_valid, mic_pcm[23:0]` | signed 24 | 来自 `inmp441_i2s_rx` |
| `analysis_valid, analysis_left/right[23:0]` | | 下游 FFT/波形/第二屏的统一入口 |
| `source_clear` | 1 | 切换瞬间单拍（顶层用于复位 FFT/波形/频谱） |
| `active, clipped, gain_shift[3:0]` | | 状态指示（供第 6 页 OSD 显示） |

**切换而非混合**：`selected=1` 时输出麦克风条件化信号，否则**直通 DDS 立体声**；两者无加权求和。`analysis_right` 在第 6 页与左声道**同一 mono 字**（渲染器显式标 `MIC / MONO`，且第 6 页不启用 XY）。另注：麦克风**不进入 HDMI 音频输出**（顶层 HDMI 只取 `I2S_receiver` 输出），且第 6 页 `science_audio_i2s.enabled=0`（DDS 静音）。

### 12.2 算法（公式）

1. **DC 跟踪**（Q24.8）：`dc` 为 32 bit 定点（低 8 位小数）。每 `mic_valid`：
   `dc += (mic_pcm·256 − dc) >>> 10` ⇒ 一阶高通，极点 `1−1/1024`，时间常数 ≈1024 采样，**−3 dB 转折 ≈ 7.5 Hz @48 kHz**。
   `centered = mic_pcm − (dc >>> 8)`（25 bit 有符号）。
2. **幅度/包络**：`abs = |centered|`（25 bit）；256 采样块：`block_sum += abs`，`block_peak = max(abs)`，块尾 `block_mean = block_sum >>> 8`（**平均绝对值**，忽略孤立尖峰），块周期 **256/48 kHz = 5.333 ms**。
3. **噪声底自适应（有界慢跟踪）**：
   - `noise_floor` 12 bit，初值 **256**；
   - 目标值 `noise_target = clamp(block_mean, 128, 1024)`；
   - **仅在门关闭且“安静”块**更新：`block_mean < 4·noise_floor || block_mean < 768` 时
     `noise_floor += (noise_target − noise_floor) >>> 3`（一阶、增益 1/8，每块 5.33 ms ⇒ 时间常数 ≈8 块 ≈ 42.7 ms）；
   - 强语音块（首次音节）不会被学成背景；门打开期间冻结。
4. **门限**：`open_level = max(768, 3·noise_floor)`，`close_level = max(384, 2·noise_floor)`（均为 25 bit 域的平均绝对值）。
5. **攻击**：连续 **2 个**块 `block_mean ≥ open_level` 才开门（`attack` 标志，任一块不满足即清）⇒ **≤10.67 ms**；开门时 `gain_shift=5`（×32）、`active=1`。
6. **释放**：门开后 `block_mean < close_level` 则 `release_count++`，累计 **18 块**（18×5.33 = **96 ms**）才关门 ⇒ 保留词尾；任一块回升即 `release_count=0`。
7. **AGC（3..7 即 ×8…×128）**：
   - 过载快降：`amplified_peak > 4 194 304 (2^22)` 且 `gain_shift>3` ⇒ 每块减 1；
   - 提升慢升：`gain_count==3`（每 4 块 = 1024 个有声样本）且 `block_mean ≥ close_level` 且 `amplified_peak < 1 048 576 (2^20)` 且 `gain_shift<7` ⇒ 加 1；
   - 关门时强制 `gain_shift=4`（**安静增益固定 ×16**，只有合格语音才允许升到 ×128）。
8. **输出**：门关 ⇒ `conditioned=0`（连续 0 流，不中断下游节拍）；门开 ⇒ `amplified = centered << gain_shift`，超出 24 bit 饱和到 `0x7FFFFF/0x800000`（不回卷）；`clipped = gate_open && (block_peak<<gain_shift) > 8 388 607`。
9. **`source_clear`**：`selected != selected_d` 时单拍，通知下游清历史。

### 12.3 状态/资源

无状态机，只有块计数器（`block_count` 8 bit）与 `gate_open/attack/release_count/gain_count` 标志。
资源：1 个 32 bit 累加（DC）、1 个 33 bit 累加（块和）、2 个 25 bit 比较/移位；**无 RAM、无乘法器、无除法器**。

> **报告可用的表述**：人声前级用 Q24.8 一阶 DC 跟踪（极点 1−1/1024，≈7.5 Hz）把 24 bit 麦克风信号去直流，256 采样（5.33 ms）平均绝对值块驱动自适应噪声门：噪声底在 128..1024 内以 1/8 步长、只在安静块且门关闭时跟踪，开门门限 `max(768,3N)`、关门 `max(384,2N)`，攻击 2 块（10.67 ms）、释放 18 块（96 ms），并在门内以 2^22/2^20 双阈值做 ×8…×128 的 AGC（每 1024 个有声样本最多升 1 档），输出 24 bit 饱和、门关时输出连续零而不中断下游节拍。

---

## 13 inmp441_i2s_rx.v — INMP441 麦克风 I2S 主机

| 项 | 值 |
|---|---|
| 参数 | `CLOCK_HZ=25 000 000`、`SAMPLE_HZ=48 000`、`STARTUP_FRAMES=4096` |
| 端口 | `clk,rst,mic_sd → mic_sck,mic_ws, mic_pcm[23:0](signed), mic_valid, ready` |
| 时钟合成 | 25 bit 相位累加：`phase += 48 000×128 = 6 144 000`；`phase_sum ≥ 25 000 000` 时 `edge_enable` 并回减。⇒ 边沿率 6.144 MHz，**SCK = 3.072 MHz = 64×48 kHz**（非整数分频，平均精确） |
| SCK 占空 | 由 25 MHz/6.144 MHz = 4.069 ⇒ 半周期 4/5 拍交替（源码注释 160/200 ns，全周期 320/360 ns，满足 INMP441 ≥312 ns） |
| 帧格式 | `slot 0..63`（SCK 计数），`mic_ws` 在 slot 31 置 1、slot 63 清 0 ⇒ **64 SCK/帧，50% 占空，WS 低=左** |
| 数据对齐 | 标准 I2S：**slot 0 丢弃（1 SCK 延迟）**，slot 1..24 在 SCK 上升沿移入 24 bit，MSB 先行；slot 24 且 `ready` 时锁存 `mic_pcm` 并给 `mic_valid` 单拍 |
| 未用位 | 每声道 32 bit 槽中后 8 bit 忽略（只取 24 bit） |
| 输入同步 | `mic_sd` 经 2 级同步（`sd_meta→sd_sync`）后使用 |
| 启动 | 4096 帧后 `ready=1`（4096/48 kHz = **85.3 ms** 预热），此前不产生 `mic_valid` |
| 资源 | 无 RAM、无 PLL、无 DSP；全部在 25 MHz 域，与视频/分析链同域（无 CDC） |
| 新增 | 全新（官方例程无麦克风） |

> **报告可用的表述**：INMP441 接收端在 25 MHz 视频域用 6 144 000/25 000 000 的有理数相位累加产生 3.072 MHz SCK（64 SCK/帧、48 kHz 帧率），按标准 I2S 在 WS 后丢弃 1 个 SCK、取 24 bit MSB 先行数据，4096 帧（85.3 ms）预热后每帧给出一拍 `mic_valid` 与 24 bit 有符号 `mic_pcm`，不新增时钟域。

---

## 14 live_voice_background.v — 第 6 页程序化背景

| 项 | 值 |
|---|---|
| 端口 | `clk,rst,vs,de, ready,active,clipped,panel_visible → rgb[23:0]` |
| 内容 | 无 BMP/无 RAM 的纯组合背景：底色 `#102A3B`，内框 `#0A2030`（`x 24..616, y 78..418`），分隔线 `y=116`（`#294858`） |
| 文字 | `secondary_font5x7`，8 px/字符、16 px 字距：标题 `LIVE VOICE`（`y 98..112`，青 `#5BDAC6`）；状态四选一 `WARMUP / LIMIT / VOICE / LISTEN`（`!ready→WARMUP`，`clipped→LIMIT`，`active→VOICE`，否则 `LISTEN`），有源时青、否则琥珀 `#E9C477`；面板隐藏时提示 `KEY3  WAVE / FFT`、`SPEAK AND WATCH` |
| 时序 | 仅 `x/y` 计数器（`de` 递增、`vs` 清零），无额外延迟；下游 OSD/Logo/时钟/字幕继续叠加 |
| 资源 | 0 RAM、0 DSP；纯 LUT + 字模 ROM |
| 新增 | 全新（第 6 页背景，替代第 6 张 BMP） |

> **报告可用的表述**：第 6 页背景为纯组合绘制（无第 6 张 BMP、无额外 RAM），显示 `LIVE VOICE` 标题与 `WARMUP/LIMIT/VOICE/LISTEN` 四态状态字，状态直接取自麦克风接收的 `ready` 与噪声门/限幅标志。

---

## 15 I2S_receiver.v — I2S 解串

| 项 | 值 |
|---|---|
| 端口 | `I_clk, I_rst, I_i2s_BCLK, I_i2s_LRCK, I_i2s_DOUT → O_audio_valid, O_audio_left_data[23:0], O_audio_right_data[23:0]` |
| 同步 | BCLK/LRCK/DIN 各 3 级触发器（`_1d/_2d/_3d`），全部在 `video_clk` 域 |
| 边沿检测 | `bclk_p_edge = ~bclk_3d & bclk_2d`（2 拍延迟后的上升沿）；`lrck_sync` 在每个 BCLK 上升沿采样，`lrck_p_edge/n_edge` 由 `lrck_sync` 与 `lrck_3d` 比较得到 |
| 解串 | 每 BCLK 上升沿：`lrck_sync=1`（右）→ 右移 `S_right_shift_data`，左清零；否则左移 `S_left_shift_data`，右清零。**64 bit/声道** |
| 取数 | 左声道在 LRCK 上升沿锁存 `S_left_data_lock`，右声道在 LRCK 下降沿输出：`O_audio_left_data = left_lock[63:40]`、`O_audio_right_data = right_shift[63:40]` |
| 有效 | `O_audio_valid` 在右声道边界（LRCK 下降沿）单拍，即 **48 kHz 采样节拍** |
| 格式约定 | 每声道 64 bit，样本在 **`[63:40]`（MSB 先行 24 bit）**，低 40 bit 补 0；**发射端无标准 I2S 的 1 bit 延迟**，与 `science_audio_i2s` 严格配套 |
| 时序裕量 | BCLK 6.144 MHz / 25 MHz = 4.07 拍/周期（半周期 ≈2 拍），属临界采样，靠 3 级同步 + 逐位仿真验证 |
| 新增 | **与官方例程相同**，未修改（官方即此 RTL，仅 `I_clk` 由 74.25 MHz 改为 25 MHz） |

> **报告可用的表述**：`I2S_receiver` 在 25 MHz 域用 3 级同步 + BCLK 上升沿检出对 6.144 MHz I2S 解串，每声道 64 bit、取 `[63:40]` 的 24 bit 样本，在 LRCK 下降沿产生一拍 `audio_valid` 与左右 PCM，是整条分析链与 HDMI 音频的共同数据源；该模块与官方例程一致。

---

## 16 hdmi_audio_tone_i2s_64fs.v — 官方 I2S 测试音（本工程未例化）

| 项 | 值 |
|---|---|
| 参数 | `PHASE_INC=32'd39370534`（兼容旧顶层，内部不用）、`AMP=24'sd2 000 000`、`NOTE_HOLD_FRAMES=24000`（0.5 s @48 kHz） |
| 时钟 | `I_mclk=12.288 MHz`；`O_i2s_BCLK` **每个 MCLK 翻转 ⇒ BCLK = 6.144 MHz**；`bit_cnt 0..63`/声道 ⇒ **LRCK = 6.144 M/128 = 48 kHz** |
| 格式 | 每声道 64 bit，样本 `{sample[23:0], 40'd0}`（`[63:40]`），左右同一样本 |
| 音源 | **方波**：32 bit 相位累加 `phase += note_inc`，取 `phase[31]` 决定 `+AMP / −AMP`（无正弦表、无包络） |
| 音符表 | 8 音（C4..C5），`inc = round(f·2^32/48000)`：23409862(261.63)/26276681(293.66)/29494578(329.63)/31248410(349.23)/35075155(392.00)/39370534(440.00)/44191930(493.88)/46819716(523.25) |
| 幅度 | ±2 000 000 / 8 388 608 ≈ **23.8 % FS（−12.5 dBFS）** |
| 节拍 | 每音 24 000 帧 = 0.5 s，8 音循环 **4 s** |
| 新增 | **官方例程原始模块**；本工程顶层已不再例化（仅 `tests/tb_waveform_i2s.sv` 用 `NOTE_HOLD_FRAMES=64` 做波形测试源），音源由 `science_audio_i2s` 取代 |

> **报告可用的表述**：官方测试音模块在 12.288 MHz 主时钟下把 BCLK 二分频为 6.144 MHz、每声道 64 bit、LRCK=48 kHz，用 32 bit 相位累加器产生 ±2 000 000 的方波并按 8 音表每 0.5 s 换音（4 s 循环）；本工程保留该 RTL 但顶层不再使用，仅作测试激励。

---

## 17 science_audio_i2s.v — 课程 DDS 音源（重点）

### 17.1 端口与采样节拍

| 端口 | 位宽 | 说明 |
|---|---|---|
| `clk,rst` | 1 | 25 MHz 视频域；异步高有效复位 |
| `enabled` | 1 | 顶层 `transition_display_valid && !voice_page`（第 6 页强制静音） |
| `lesson[2:0]` | 3 | 页面号 0..5 |
| `bclk,lrck,dout` | 1 | I2S 输出 |
| `sample_tick` | 1 | 每帧（48 kHz）单拍（顶层未用） |
| `pcm_left/right[23:0]` | 24 | 并行 PCM（顶层未用，仍经 I2S 回环解码） |
| `lesson_step[1:0]` | 2 | 前 4 页的阶段号 |
| `melody_complete` | 1 | 第 5 页旋律播完（送 SD 控制器门控自动轮播） |

**时钟合成**：`tick_acc` 25 bit 每拍累加 **12 288 000**，`≥25 000 000` 时减 25 000 000 ⇒ `mclk_enable` 平均 **12.288 MHz**（使能，非门控时钟）。
`bclk <= ~bclk` 在使能拍翻转 ⇒ **BCLK = 6.144 MHz**；`bit_count 0..63` 于 BCLK 周期内递增 ⇒ 每声道 64 bit、立体声 128 bit ⇒ **LRCK = 6.144 M/128 = 48.000 kHz（平均精确，抖动 ±40 ns）**，50% 占空。

**帧格式**：`bit_count==63` 时换声道并装载 64 bit 字 `{pcm, 40'd0}`；样本在 `[63:40]`（MSB 先行 24 bit，无 1 bit 延迟）。左声道数据在 LRCK 由 1→0 时装载（WS 低=左）。

### 17.2 音源类型（`phase_increment` / 波形 / 包络）

| 页 | 主题 | 频率（32 bit 相位增量，`f = inc·48000/2^32`） | 波形/幅度 |
|---|---|---|---|
| 0 | 音高 | step0 **220 Hz**(19685267)、step1 **330 Hz**(29527900)、step2 **440 Hz**(39370534)、step3 **660 Hz**(59055800) | 正弦 |
| 1 | 响度 | 440 Hz | step0 幅度 ×1/4（−12 dB）、step1/3 ×1/2（−6 dB）、step2 ×1 |
| 2 | 音色 | 440 Hz | step0/3 正弦，step1 三角，step2 方波（±32767） |
| 3 | 立体声 | 左 440 Hz、右 **660 Hz**(59055800) | step0 仅左、step1 仅右（对侧 `base=0`）、step2/3 双声道 |
| 4 | 音乐 | 17 音旋律（见 17.3） | 正弦 + Q6 音量 |
| 5 | 人声 | `enabled=0` ⇒ `pcm=0`、相位清零 | 静音（音源换成麦克风） |

- 相位：`phase_left/right` 32 bit，每采样加 `phase_increment(page, step, right)`（左/右可不同，实现第 4 页立体声）。
- 正弦表 `sine8`：**8 bit 相位→256 点查表**，用 1/4 周期表（0..64 共 65 项）+ 象限折叠：`index = angle[6] ? 64−angle[5:0] : angle[5:0]`，符号取 `angle[7]`；峰值 32767（Q1.15），分辨率 360°/256 = 1.40625°。
- 三角 `triangle8`：`mag = angle[6] ? 64−angle[5:0] : angle[5:0]`，`positive = (mag==64)?32767 : mag[5:0]<<9`（6 bit 幅度 ×512）。
- 方波：`phase[31] ? −32767 : +32767`。
- **阶梯包络（前 4 页）**：`STEP_SAMPLES = 48000`（**1 s/步**），每步首尾各 64 采样线性斜坡（`envelope = position`，尾 `= 47999−position`），中间 64。
- 幅度：`amplitude = base×60`；`out = (amplitude×envelope) >>> 6` ⇒ 峰值 `32767×60 = 1 966 020`（≈ **23.4 % FS，−12.6 dBFS**），无削顶。
- `lesson_step` 为 2 bit，每步 48 000 采样后 +1，**4 步循环（4 s）**。
- 换页/`!enabled`：`active_lesson != lesson` 时清零相位、步计数、旋律指针与 `pcm`，并刷新 `shift_reg`。

### 17.3 旋律（第 5 页）

- 节奏：`NOTE_UNIT_SAMPLES = 12000` = 八分音符 0.25 s（**120 BPM**），共 **32 个八分单位 = 8.000 s**，`melody_note 0..16`。
- 乐句（C 大调，4 小节）：`C4 E4 G4 A4 G4 | E4 D4 E4 G4 | A4 C5 B4 G4 | F4 E4 D4 C4`。
- 音高表 `melody_increment`（`round(f·2^32/48000)`）：C4 23409859 / D4 26276679 / E4 29494575 / F4 31248413 / G4 35075158 / A4 39370534 / B4 44191930 / C5 46819719。
- 时长表 `melody_length`：音符 1,2,13,14 = 1 单位；音符 16 = 4 单位（1 s）；其余 2 单位（0.5 s）。
- 音量表 `melody_gain`（Q6，0..64）：音符 0,3,7,9,12 → 56；1,5 → 52；2,4,8,16 → 60；6 → 48；10 → 64；11,14 → 54；其余 50。
- 包络：起音 `position < 64<<2 = 256` 采样（5.33 ms，`env = position>>2`）；释音 `remaining < 64<<3 = 512` 采样（10.67 ms，`env = remaining>>3`）；中间 64。
- 幅度：`weighted = base×gain`；`amplitude = (weighted×60) >>> 6`；`out = (amplitude×env) >>> 6` ⇒ 峰值 `32767×64×60/64 = 1 966 020`。
- 音符切换时相位**重新起算为 0**（`phase_left<=0`）以减少瞬态；左右声道输出同一旋律（单声道复制）。
- 播完第 17 音（C4, 48000 采样）后 `melody_complete=1` 并输出 0（**静音**），离开再返回从头重播。

### 17.4 状态/资源

无状态机：`tick_acc`、`bit_count[5:0]`、`step_count[15:0]`、`melody_position[15:0]`、`melody_note[4:0]`、`phase_left/right[31:0]`。
资源：2 个正弦表（65×16 bit 组合 case，非 ROM）、1 个三角/方波逻辑、若干 16×24 乘法（`base×60`、`×envelope`、`×gain`）；无 BRAM、无除法。

### 17.5 新增

取代官方 `hdmi_audio_tone_i2s_64fs`（方波 8 音）：新增 5 页课程音源、正弦/三角/方波音色、4 档幅度、左右分立频率与交替静音、17 音 8 秒旋律与 `melody_complete` 门控，并把时钟生成从 12.288 MHz PLL 域搬到 25 MHz 域的“有理数使能”。

> **报告可用的表述**：`science_audio_i2s` 在 25 MHz 视频域用 12 288 000/25 000 000 的有理数时钟使能合成 6.144 MHz BCLK 与 48.000 kHz LRCK（64 bit/声道、24 bit MSB 先行），以 32 bit 相位累加 + 1/4 周期 256 点正弦表生成 5 类课程音源：音高页 220/330/440/660 Hz、响度页 −12/−6/0/−6 dB、音色页正弦/三角/方波、立体声页 L440/R660 交替与同响、音乐页 17 音 120 BPM 的 8 秒 C 大调旋律（八分音符 12 000 采样、Q6 音量、256/512 采样起落包络、峰值 1 966 020），第 6 页则整体静音并让位给麦克风。

---

## 18 rom/i2s_rom_player_single_pll_fix64_rom_ip.v — 波形 ROM 旋律播放

| 项 | 值 |
|---|---|
| 参数 | `SAMPLE_RATE=48000`（仅参与注释/步进设计）、`SAMPLE_BITS=24`、`ROM_DEPTH=48`、`ADDR_WIDTH=6`、`NOTE_LEN_SAMPLES=12000`（0.25 s @48 kHz） |
| ROM | `AUDIO_SAMPLE_ROM`（厂商 IP，`EG_LOGIC_BRAM`，DATA 24 bit×48 深、单口 SP、NOREG、IMPLEMENT 9K、INIT `audio_sine_24bit_48deep_scale8.mif`）⇒ **1 个 9K BRAM 存 48 点单周期正弦（24 bit）** |
| 读表合成音高 | 相位累加器 **Q16.16**：`phase += step`，`step = round(f·48/48000·2^16)`；`phase ≥ 48<<16` 时回绕；地址 = `phase[31:16]`（48 点表 ⇒ 每点 7.5°） |
| 音符步进 | C4 **17146**、D4 19245、E4 21603、F4 22887、G4 25690、A4 28836、B4 32367、C5 34292（`8 音循环`） |
| 换音 | `note_cnt==NOTE_LEN_SAMPLES−1` 时 `note_sel+1`（0..7 循环）、`phase←0`、`note_cnt←0` |
| 通道字 | 左右各 64 bit，均为 `{sample[23:0],40'd0}`（单声道复制），`bit_cnt` 0..127 |
| 时钟链（按代码推导） | `S_mclk_div` 每 MCLK 翻转且仅 `==0` 拍执行 → 执行率 6.144 MHz；该拍内 `BCLK` 翻转 ⇒ **BCLK = 3.072 MHz**；`bit_cnt 0..127` ⇒ **LRCK ≈ 24 kHz**。**注意：与文件头注释“BCLK=6.144 MHz、LRCK=48 kHz”不一致**（注释相当于漏掉 `mclk_div` 的 /2）；若按 48 kHz 设计值，音高表才对应 C4..C5，按代码实际 24 kHz 则音高低一个八度 |
| 启动 | `S_init_step` 0→1→2 三步预装（复位地址、预读 ROM、装左右字），之后进入正常发送 |
| ROM 读出 | 1 拍延迟，用 `S_capture_pending` 在换帧时把 `S_rom_q` 锁入 `S_sample_next` |
| 资源 | 1 个 9K BRAM（ROM）+ 1 个 48 深地址计数器；无乘法器（步进为常量表）、无 DSP |
| 新增/地位 | 独立的“ROM 波表 + 步进合成”演示模块；**本工程顶层未例化**（`grep` 仅命中自身与 IP），属官方 I2S 演示分支的遗留实现，与本工程 `science_audio_i2s`（DDS + 音色 + 旋律）是两条不同路线 |

> **报告可用的表述**：ROM 播放器把 48 点 24 bit 单周期正弦存进 1 个 9K BRAM，用 Q16.16 相位累加（步进 = `round(f·48/48000·2^16)`，C4..C5 共 8 档）读表合成音高，每 12 000 帧换音、8 音循环，每声道 64 bit 字数 24 bit MSB 先行；按代码推导 BCLK=MCLK/4=3.072 MHz、LRCK≈24 kHz，与文件头“48 kHz”注释存在因子 2 的不一致，且该模块未在本工程顶层使用。

---

## 19 汇总（可直接引用的参数表）

### 19.1 时间与频率

| 量 | 值 | 出处 |
|---|---|---|
| 采样率 / 位深 | 48 000 Hz / 24 bit（立体声） | §17、§15 |
| FFT 点数 / bin 宽 | 1024 / **46.875 Hz** | §1 |
| FFT 窗长 | 1024/48000 = **21.333 ms** | §1 |
| FFT 单块计算 | **115 712 拍 = 4.63 ms** | §1.5 |
| 频谱刷新 | ≥25.96 ms，实际约 **2 帧 ≈33.6 ms** | §1.5 |
| 波形窗 | 256 点 = **5.333 ms**，1 帧 1 次 | §4 |
| XY 每面 | 512 点 = **10.67 ms** | §9 |
| 电平窗 | 1024 点 = **21.33 ms** | §10 |
| 历史深度 | 96 列 ×(26–33.6 ms) ≈ **2.5–3.2 s** | §10 |
| 无音超时 | 6 250 000 拍 = **250 ms** | §3、§4、§10 |
| 噪声门 | 攻击 ≤10.67 ms、释放 96 ms、块 5.333 ms | §12 |
| 麦克风预热 | 4096 帧 = **85.3 ms** | §13 |
| 课程音源步进 | 48 000 采样 = **1 s**，4 步/页 | §17 |
| 旋律 | 32 单位 ×0.25 s = **8.000 s**，120 BPM | §17 |
| 官方测试音 | 8 音 ×0.5 s = 4 s 循环，方波 ±2 000 000 | §16 |
| ACR | N=6144、CTS≈25 001 / 1 ms | §5 |

### 19.2 频率轴一览

| 显示 | 数量 | bin 映射 | 频率 |
|---|---|---|---|
| 主屏频谱 | 128 带 ×2 声道 | 1/2/4/9 bin | 0..23 953 Hz，非线性（0–1.5k–4.5k–10.5k–24k） |
| 主屏人声模式 | 42 bin（重映射） | bin 2..43 | 93.75..2015.6 Hz，12.19 px/bin |
| 第二屏瀑布 | 64 带 | 1/2 bin | 0..4 453 Hz（0–1.5k–4.5k） |
| 音高轨迹 | 48 位置 | 线性 | 100..1000 Hz（越界钉边） |
| 音名 | 60 项 | 几何中点门限 | C2..B6（67..2033 Hz） |
| 谐波 | H1..H5 | `round(n·f0/46.875)`±1 bin | f0∈[100,1000] Hz |

### 19.3 定点格式一览

| 信号 | 格式/位宽 |
|---|---|
| PCM | 24 bit 二进制补码（1 LSB = FS/2^23） |
| FFT 输入 | Q1.15（PCM[23:8]） |
| Hann 窗 | Q0.15（0..32767） |
| 旋转因子 | Q1.15 复（32 bit/项） |
| 蝶形中间量 | Q1.15 + 1 符号位（17 bit）；每级 /2，总 1/1024 |
| 幅值 | 17 bit `|Re|+|Im|`（最大 65536） |
| 柱高 | 7 bit（0..66），≈6·log2(x)−12 |
| 音高频率 | 15 bit 整数 Hz；插值用 Q8 bin（delta ±128） |
| 谐波柱高 | 6 bit（0..38） |
| 热力等级 | 4 bit（0..15，height≥60 顶格） |
| 电平条 | 8 bit（0..224 px，`(7v)>>10`） |
| 麦克风 DC | Q24.8，极点 1−1/1024 |
| 正弦表 | 16 bit Q1.15（±32767） |
| DDS 相位 | 32 bit 无符号（`f=inc·48000/2^32`） |
| ROM 播放相位 | Q16.16（表深 48） |

### 19.4 相对官方例程的新增清单

| 模块 | 官方例程 | 本工程 |
|---|---|---|
| `hdmi_audio_tone_i2s_64fs` | 有（唯一音源） | 保留 RTL，顶层不再例化 |
| `I2S_receiver` / `audio_arc_calculate` | 有 | **未修改** |
| `science_audio_i2s` | 无 | 新增（5 页课程音源 + 8 s 旋律） |
| `audio_fft1024` / `fft1024_tables` | 无 | 新增（1024 点定点 FFT + 系数 ROM） |
| `audio_spectrum_overlay` / `audio_waveform_overlay` | 无 | 新增（频谱 + 双声道示波器，均 2 拍流水） |
| `inmp441_i2s_rx` / `voice_analysis_source` / `live_voice_background` | 无 | 新增（麦克风、噪声门/AGC、第 6 页背景） |
| `secondary_*`（store/pitch/note/harmonics/lissajous/renderer/hdmi_tx） | 无 | 新增（HDMI_A 独立分析屏，6 页） |
| `i2s_rom_player_single_pll_fix64` | 独立演示分支 | 未在本工程例化 |
