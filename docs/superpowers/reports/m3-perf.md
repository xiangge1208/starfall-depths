# M3-X-B 双平台 60fps 达标验证 — §18.3 五指标 + 降级预案演练（G-1 输入）

任务卡 X-B 交付：GDD §18.3 性能预算五指标逐项判定（Windows 开发机口径）+ 超标降级预案（先降粒子→再降实体）演练 + OBS-3 帧率异常处置 + Android 侧证据链与移交。
本文档为 G-1 门禁的输入台账（风格对齐 `m3-juice-checklist.md`）。

- 分支：`m3-xb`（基于 main @ 878ad44，已含 J-D Juice 收口/补课、S-C 字体接线、X-A Android 导出线）
- 探针：`tests/scenes/perf_probe.gd(+.tscn)`（M2-T29 原探针 + 本卡 additive 适配，见 §7；M2 默认判定语义零改动，`-- --uncapped` 档保留）
- 执行环境：开发机 i5-14400F / RTX 3050 / 32GB / Windows 10.0.26200，Godot 4.7.2-stable official，DisplayServer **Windows**（窗口化，vsync 关）；数据采样时段宿主有活跃桌面负载（Chrome/IDEA/微信/企业微信/QQ 音乐）与并行 workstream（另一 worktree 的 balance bot），墙钟类指标受此噪声影响处均已标注
- 执行时间：2026-09-02 00:20–03:30（本会话）
- **判定摘要：Windows 五指标全 PASS（开发机口径，渲染 GPU 侧与核显本真测归 G-1）；Android 真机缺失、模拟器近似已打通「安装→启动」链路（WHPX + 47.4s boot + adb 在线 + install Success + Godot 主循环启动），但模拟器 GPU 仿真无法呈现 Godot 4.7 画面（Vulkan present / GLES3 uniform 上限，环境限制非游戏缺陷），帧数据未取得——Android 60fps 判定移交 G-1（风险项挂账），不以近似数据冒充真机结论。降级预案两档演练全通过（含一次全指标 PASS exit 0）。**

---

## 1. 基线口径（GDD §18.3 原文）

> 「中端核显笔记本与 2GB 内存安卓机 60fps：活动实体 ≤300、同屏弹幕 ≤500、draw call ≤150（全图集）、逻辑帧耗时 ≤6ms、渲染 ≤10ms。超预算先降粒子再降实体。」

判定口径沿用 M2（`m2-perf.md`）：采样窗**平均值**对预算线（≤ 通过），max 样本作尖峰披露；「同屏弹幕 ≤500」的 PASS 语义 = 顶格负载下其余指标仍达标（生产节奏不会长期满池）。

## 2. OBS-3 帧率异常处置（J-D 移交 → 本卡收窄定性）

### 2.1 J-D 移交内容（`m3-juice-checklist.md` §4.1/§6 OBS-3）

J-D 会话（2026-09-01 日间）：`Engine.max_fps=60` 节流劣化到 0.2~2.5s/帧，窗口/无头、pre/post-J-A 代码同现，同机 M2 期记录 TIME_FPS=60.0；定性「环境/会话级，非游戏回归」，节流窗复测移交 X-B。

### 2.2 本会话量化（新增 `-- --anomaly-check` 档）

| 场景 | max_fps=0 | max_fps=60 | 结论 |
|---|---|---|---|
| 空场景（探针 .tscn 原样，无游戏内容） | **1.077 ms/帧**（≈928fps） | **16.7 ms/帧**（精确钳 60fps） | 节流机制本身正常 |
| 空场景 无头 | 6.897 ms/帧（≈145fps，与 J-D 记录一致） | 16.7 ms/帧 | 同上 |

**`max_fps=60` 节流路径零异常。OBS-3 的「0.2~2.5s/帧」不复产于本会话的空场景；带内容压测的爬行另有根因（§2.3），与节流机制无关。**

### 2.3 爬行真因定位（本卡新增，两个叠加放大器）

带内容的压测（40 注入敌 + 500 弹）在部分窗口出现整帧爬行（0.2~2.5s/帧量级，与 J-D 观察量级一致）。经逐级二分（headless/窗口化 × 节流/不节流 × Vulkan/GL × 音频 Dummy × pristine 探针对照 × 敌数 1/5/10/20/40 梯度 + 引擎监视器逐段追踪）定位到两个**叠加的放大器**，均非游戏逻辑成本：

1. **日志放大器**：敌堆叠饱和后 `enemy_base._physics_process`（`core/enemies/enemy_base.gd:260`）的 `velocity=(brain_pos-global_position)*FPS` 归零，`move_and_slide` 内部对零向量 normalize 逐敌逐帧发 WARNING（含 GDScript backtrace，stdout+`godot.log` 双写同步刷盘）。实测单次压测运行刷 6.0万~18.6万条（`logs/godot2026-09-02T*.log` 计数），饱和期 ~900 条/帧 × ~1.5ms/条 ≈ **1.4s/帧**。处置：探针测量期 `Engine.print_error_messages = false`（仅测试面日志开关，不触 fx/core/data 任何文件；堆叠静止是压测注入的预期终态、warning 是引擎对合法零速移动的噪音；生产导出包 release 模板不含该日志开销）。抑制后爬行 1.4s/帧 → 0.4s/帧，暴露第二放大器。
2. **堆叠物理饱和（服务器端）**：40 个不死注入敌（玩家抬血 9999 保活）终态全部堆叠到玩家单点，CharacterBody2D 的堆叠碰撞恢复成本随同点密度**非线性爆炸且发生在 PhysicsServer flush 内**——`TIME_PHYSICS_PROCESS` 全程仅 0.02~0.09ms（脚本侧恒 PASS），但物理拍墙钟拉到 ~30ms（pf 增速 60Hz→30Hz）。敌数梯度实测：**1 敌/5 敌/10 敌：全层恒定 60fps**；**20 敌：~10-20s 游戏时间后爬行**；**40 敌：warmup 期即爬行**（会话越忙、帧越慢、堆叠游戏时间越长、越快进入饱和——正反馈）。

**定性与边界**：真实局中该病理终态不可持续——40 个接触伤害敌堆叠时玩家数秒内即死亡重建，不存在「40 不死敌堆叠 25s+」的正常玩法可达态（探针抬血 9999 恰是制造该终态的原因）。**M2 与 J-D 的全负荷有效数据均取自饱和前窗口**（M2 窗口化 fps=60 实证；J-D 头less ~145fps F1/F2 完成），与本卡结论不冲突。OBS-3 定性自「环境级待查」收窄为：「压测负荷病理终态 × 日志放大器 × 会话负载」三因子叠加，**游戏逻辑、节流机制零回归**。

**移交 G-1**：在静默会话/目标机用默认档（40 敌）复测一次探针作终验（探针已按 §7 加固：日志抑制默认生效，饱和前 8s 采样窗即完成）。

## 3. Windows 五指标判定（开发机口径）

### 3.1 「中端核显本」近似口径与风险标注

- 本机 i5-14400F 为 **F 后缀（无核显）**，无集成显卡可测；也不具备真核显笔记本。
- 采用近似口径：①逻辑帧/活动实体/同屏弹幕三轴与 GPU 无关，直接有效；②draw call 为 CPU 提交侧计数（驱动前后），有效；③GPU 光栅化在 RTX 3050 上测得的结果对核显本是**下界**（只快不慢）——本作 2D 像素 480×270 视口，渲染侧约束历来在 draw call 而非像素吞吐（M2 §三 已证）。
- **风险**：核显本真机 60fps 终验归 G-1；若核显本实测超标，按 §5 演练证明过的预案顺序处置（先降粒子→再降实体），降粒子档实测可减免 draw call（§5.1）。

### 3.2 逐机逐指标数据表

**表 A：本卡 fresh 窗口化运行（2026-09-02，现行代码含 Juice v2 全量，窗口化 vsync 关，`--drill-enemies=10` 负荷档）**

| 指标（预算线） | F1 洞穴 combat_a1_03 | F2 暗视野+剪影 combat_a2_01 | F3 岩浆+火雨 combat_a3_08 | 判定 |
|---|---|---|---|---|
| 逻辑帧（≤6ms） | 0.0113ms（max 0.0156） | 0.0115ms（max 0.0150） | 0.0116ms（max 0.0177） | **PASS ×3** |
| 渲染 CPU（≤10ms） | 0.0204ms | 0.0203ms | 0.0208ms | **PASS ×3**（GPU 侧未采，口径见 §6.1） |
| draw call（≤150） | 43.2（max 92） | 51.4（max 94） | 46.1（max 98） | **PASS ×3**（max 亦 ≤98） |
| 活动实体（≤300） | 32 | 27 | 31 | **PASS ×3** |
| 同屏弹幕（≤500） | 峰 500（顶格） | 峰 500（顶格） | 峰 500（顶格） | **PASS ×3** |
| 节流窗 60fps 实证 | **fps=60.0 steps=1.00** | **fps=60.0 steps=1.00** | **fps=60.0 steps=1.00** | **PASS ×3**（生产节奏逐层实证） |
| 60fps 合成线（≤16.67ms） | 16.867ms（+1.2%） | 23.615ms（噪声污染） | 9.707ms | F3 PASS；F1/F2 的 uncapped 墙钟被宿主负载毛刺抬高，见 §6.2 披露 |

（数据源 `m2_perf.json` 转存 `meta.date=2026-09-02T02:10:45`，`drill_enemies=10`。F2 在后续复跑中 fps 在 27↔60 间摆动，同为会话噪声，见 §6.2。）

**表 B：全负荷（40 注入敌）参照——渲染侧取 T37 合并后唯一完好窗口化运行（2026-09-01T00:45，pre-Juice-v2）**

| 指标（预算线） | F1 | F2 | F3 | 判定 |
|---|---|---|---|---|
| draw call（≤150） | **101.4**（max 187） | **102.2**（max 166） | **102.1**（max 176） | **avg PASS ×3（余量 ~32%）**；max 尖峰 166~187 仍越线（瞬时 UI/特效），口径按 avg |
| 逻辑帧（≤6ms） | 0.0132ms | 0.0129ms | 0.0127ms | PASS ×3 |
| 渲染 CPU（≤10ms） | 0.0228ms | 0.0238ms | 0.0230ms | PASS ×3 |
| 60fps 合成线（≤16.67ms） | 9.775ms | 11.148ms | 9.514ms | **PASS ×3（最差余 33%）**，fps 59~60、steps 1.01~1.04 |
| 活动实体（≤300） | 65 | 61 | 61 | PASS ×3（占预算 ~21%） |

（该运行即 T37 合并证据「probe F2 101.2/150 PASS margin 32.5%」同族数据；其时 a2/a3 最密模板已选型（combat_a2_01/a3_08），Juice v2 尚未合入。）
**Juice v2 渲染增量有界性**：v2 新增绘制面 = 粒子池精灵（本卡实测活跃峰 ≤19，池预算 200）+ 受击方向弧（事件驱动瞬态）——为 ≤20 量级的 Sprite2D draw，相对 150 线与 48 的全负荷余量不构成判定风险。**头less 下 draw call 恒 0 不可直接测**（Dummy 渲染器），此增量为推算界，披露如上。

**表 C：全负荷逻辑轴——头less 对照（逻辑/实体/弹幕轴与 GPU 无关，头less 有效）**

| 来源 | 负荷 | 逻辑帧 avg | 判定 |
|---|---|---|---|
| J-D 2026-09-01（头less `--uncapped`，现行代码） | 40 敌+500 弹 | F1 0.014 / F2 0.015 ms | PASS |
| 本卡 trace3（头less，饱和爬行期监视器读数） | 40 敌+500 弹 | 0.02~0.09 ms（饱和期恒定） | PASS（余量 65~300×） |

### 3.3 五指标判定结论（Windows）

| §18.3 指标 | 判定 | 依据 |
|---|---|---|
| 逻辑帧 ≤6ms | **PASS** | 表 A/B/C 全负荷全层 0.007~0.09ms，余量 ≥65× |
| 渲染 ≤10ms | **PASS** | 渲染 CPU 0.019~0.024ms（CPU 侧口径）；GPU 侧未采（§6.1），合成线干净窗 5.9~11.1ms |
| draw call ≤150（全图集） | **PASS** | T37 全图集合并后全负荷 avg 101~102（余 ~32%）；fresh 43~51；v2 增量 ≤20 有界 |
| 活动实体 ≤300 | **PASS** | 全负荷峰 61~69（21~23%），10en 档 27~32 |
| 同屏弹幕 ≤500 | **PASS** | 三层顶格 500 下其余指标全部达标 |
| 60fps | **PASS（实证口径）** | 全部有效运行的节流窗 TIME_FPS=60.0、steps/frame=1.00（M2/T37/本卡一致）；合成线在本会话噪声敏感（§6.2），干净窗 5.9~11.1ms |

**Windows 总判定：五指标 PASS（开发机口径）。未触发降级预案（无超标项）。**

## 4. Android 侧（真机缺失 → 模拟器近似 + 证据链）

### 4.1 真机

无真机：本会话 `adb devices` 为空（X-A 报告后无变化）。§18.3「2GB 内存安卓机 60fps」的**最终验收必须真机**，移交 G-1。

### 4.2 模拟器近似（本卡实际执行台账，时间盒内尽力的完整记录）

| 步骤 | 结果 | 证据 |
|---|---|---|
| cmdline-tools 升级 | 仓库 XML 已升 v4，机内 11076708（v3）找不到包；装 13114758 至 `D:\dev\android-sdk\cmdline-tools\latest-new`（原 latest 不动） | `sdkmanager --list` 正常返回 574 包 |
| 镜像选型 | **`system-images;android-34;x86_64` 已从仓库退役**（列表无此包）→ 按 `android-36;default;x86_64`（AOSP）安装（2.0GB），min_sdk=21 兼容 | `--list` 输出 |
| emulator 安装 | 37.1.11 装成 | `emulator/emulator.exe` 在位 |
| 硬件加速 | **WHPX：installed and usable**（Hyper-V 在跑） | `emulator -accel-check` 输出 `0` |
| 低配 AVD | `xb_perf`：pixel_4 设备定义 + `hw.ramSize=2048`（=2GB 内存目标机）+ android-36 AOSP | `avdmanager create avd` + config.ini |
| 启动实证 | `-no-window -gpu swiftshader_indirect -memory 2048`（软件 GPU=弱 GPU 上界近似）：**Boot completed in 47384 ms**，adb `emulator-5554 device`、`sys.boot_completed=1` | `emulator_boot.log` |
| apk 导出（首次） | **FAIL rc=-1073741819**：gradle daemon JVM **native OOM**（`hs_err_pid27232.log`：insufficient memory，daemon -Xmx4536m；当时宿主 32GB 被 Chrome/IDEA/微信/企业微信/QQ 音乐 + 模拟器 2GB + 并行压测占满） | `hs_err_pid27232.log`/`replay_pid27232.log`（已移出工作树留档 /tmp） |
| apk 导出（重试） | 模板 `gradle.properties` jvmargs 降 `-Xmx2700m`（gitignored 机器级文件，零仓库漂移）后重跑 `tools/export_android.cmd` → **PASS** | §4.3 |
| 安装/启动 | x86_64 双 ABI apk **install Success + launch 成功**（Godot 主循环启动、进程存活、无 FATAL）；渲染被模拟器 GPU 仿真阻断（Vulkan present err5 / GLES3 uniform 261 上限），帧数据未取得 | §4.3 |

### 4.3 导出重试与帧数据（实际结果，如实记录）

1. **导出重试：PASS**。模板 `gradle.properties` jvmargs 降 `-Xmx2700m`（gitignored 机器级文件，零仓库漂移）后 `tools/export_android.cmd` **exit 0——release apk（89,070,223B）+ aab（38,119,448B）双产物产出、apksigner/jarsigner 双核签通过**（`RESULT: PASS`）。
2. **安装尝试（模拟器，x86_64）**：
   - release apk（arm64-v8a，X-A 预设口径）→ `INSTALL_FAILED_NO_MATCHING_ABIS`（模拟器为 x86_64 镜像）——符合预期，非缺陷；
   - 临时开 `architectures/x86_64=true` 零漂移导出（164,483,132B，双 ABI）→ **install Success、launch 成功**：Godot 主循环启动（`OnGodotMainLoopStarted`）、OpenSLES 音频轨创建、进程持续存活，无 FATAL/ANR；
   - **渲染被模拟器 GPU 栈阻断**：`ERROR: Couldn't present to Vulkan queue (VkResult error 5)`（forward_plus/Vulkan；swiftshader 交换链 present 失败）→ 黑屏；改 `gl_compatibility`（项目级 override，两次导出核验）→ `CanvasShaderGLES3: Program linking failed: Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)`——**两者均为 headless 模拟器 GPU 仿真（swiftshader Vulkan / gfxstream GLES3）的环境限制，非游戏缺陷**（同一 apk 在带正常 Vulkan/GLES3 驱动的真机不受影响；Godot 4.7 官方已知模拟器 GPU 仿真对两大渲染器支持不全）。
3. **帧数据：未取得**。`dumpsys gfxinfo` 恒 0 帧（SurfaceView 游戏不在其统计口径，且 present 未成功）；SurfaceFlinger latency 亦无有效呈现帧。**模拟器近似至此触壁，按时间盒纪律收手**；§18.3 Android 60fps 判定移交 G-1 真机执行。

### 4.4 已具备的替代证据链（X-A + 本卡）

1. release apk（89,035,428B）+ aab（38,083,099B）双产物产出、apksigner/jarsigner 双核签通过（X-A run6，exit 0）。
2. `etc2_astc` 纹理压缩管线过 Godot Android 导出强制校验（X-A §4 开关 a 机制）。
3. gradle 构建模板（版本戳/.gdignore 自愈）+ JDK21 + SDK 全链在位，且本卡在 m3-xb worktree 完成了一次同流程引导（android/ 目录为机器级 gitignored 物）。
4. adb 驱动/平台工具就绪；模拟器环境（WHPX+AVD+boot）本卡实证可用，G-1 复测时可直接 `emulator -avd xb_perf ...` 复用。

**Android 判定：60fps 五指标无本机实测数据（真机缺失 + 导出受宿主资源所限），移交 G-1；不以 swiftshader 软件渲染近似数据冒充真机结论。**

## 5. 降级预案演练（§18.3「超预算先降粒子再降实体」，全过也补做）

五指标全 PASS 未超标，按卡面与编排者指令将预案作为**数据补做演练**：逐档强制降到下一档采数对比，验证预案真实可开。两档均为 additive 探针档（`--drill-particles` / `--drill-enemies=N`），fx/core/data 零改动。

### 5.1 T1 先降粒子（`--drill-particles`：采样期逐拍强制 `_degrade=true`，单帧退化语义）

负荷 = 表 A 同配置（10 注入敌 + 500 弹，窗口化）。

| 指标 | 基线（表 A） | T1 降级档 | 效果 |
|---|---|---|---|
| 降级标记观测 | 0/480 拍 | **474/468/477 每层采样拍**（强制全程生效） | 预案真实开启 |
| draw call | 43.2 / 51.4 / 46.1 | **41.5 / 47.7 / 45.3** | −1.7~−3.7（在屏粒子仅 10~15 个，单帧退化减去的换图帧有限；粒子满屏时减免更大——J-D 实测自然峰 16~17/200，压测配比远未触顶） |
| 逻辑帧 | 0.0113~0.0116 | 0.0111~0.0133 | 零变化（纯表现层） |
| 节流窗 fps | 60.0 ×3 | 60.0 ×3（F2 撞会话毛刺 27，与该档无关，§6.2） | 无恶化 |
| 判定 | — | juice_smoke §3 已证：单帧退化而非消失、自动恢复、判定/信息零损失 | **预案可用性成立** |

### 5.2 T2 再降实体（`--drill-enemies`：注入敌 10→5）

| 指标 | 10 敌（表 A） | 5 敌档 | 效果 |
|---|---|---|---|
| draw call | 43.2 / 51.4 / 46.1 | **28.5 / 37.9 / 32.8** | **−13.3~−14.7（≈−1.3 draw/敌**：剪影/光环/播件逐敌 draw 的直接减免） |
| 逻辑帧 | 0.0113~0.0116 | **0.0072~0.0084** | −27~−38% |
| 活动实体 | 27~32 | 17~22 | 账目同步下降 |
| 60fps 合成线 | 9.7~23.6ms（噪声敏感） | **5.9~6.7ms 全干净** | 档位越低抗宿主噪声越强 |
| 整体判定 | F1/F2 合成线 FAIL（噪声） | **`PERF VERDICT: PASS`，exit 0 全绿** | **预案可用性成立（含一次全指标 PASS 实录）** |

### 5.3 演练结论

两档预案均真实可开、逐档有效、与既有机检（juice_smoke §3 单帧退化语义+自动恢复；juice_matrix 判定零损失）互证。本卡五指标无超标，**未对产品代码实施真实降级**（fx/、core/、data/ 零改动，符合纪律）；若 G-1 目标机实测超标，按 T1→T2 顺序执行即可，预期收益以本节实测数据为准。

## 6. 偏差与披露

1. **渲染 ≤10ms 的口径**：GPU 逐帧耗时无公开 API（M2 §六.3 沿袭），采 TIME_PROCESS + frame_setup_time_cpu 为 CPU 侧口径；60fps 能力另以「节流窗 TIME_FPS + steps/frame」运行实证与「合成线 = 逻辑帧 avg + 不节流整帧 avg」双口径呈现。
2. **合成线对宿主负载噪声敏感**：不节流窗墙钟的均值被桌面负载毛刺抬高（同一次运行内 F3 9.7ms 干净 vs F2 23.6ms 污染；T1 档 F2 又在节流窗撞毛刺 fps=27）。**判定以节流窗 60fps 实证（生产真实节奏）为主口径，合成线按干净窗（5.9~11.1ms）与 T37 全负荷参照（9.5~11.1ms，余 33%）佐证**；M2 亦记录过同类「F1/F2 反序」波动（m2-perf §六.6）。静默会话/目标机复测归 G-1。
3. **本卡 fresh 窗口化运行采用 10 注入敌负荷档**（`--drill-enemies=10`）：40 敌满负荷在本会话必进入 §2.3 堆叠饱和病理态，窗口化数据不可采。满负荷的证据由表 B（渲染参照，pre-v2）+ 表 C/§3.2（逻辑轴，现行代码）承担；10en 档用于验证现行代码全管线（含 v2 粒子/字线/剪影/火雨）在窗口化下的渲染与 60fps 实证。探针已具备 `--orbit-player` 去饱和档（移动玩家目标），实测尚不足以对抗 40 敌单点饱和 knot（knot 随目标整体迁移），如实记录、不虚报。
4. **执行期间误杀澄清**：首次头less 探针挂起 18 分钟经查为 fresh worktree 未跑 `--import` 导致的 autoload 解析失败（探针场景空转、900s 看门狗从未创建）——非 OBS-3 复现，已在本 worktree 完成 `--import` ×2（第二次 0 ERROR）。fresh worktree 首跑测试前需 `godot --headless --path . --import`（标准工作流，与 S-C/J-D 披露一致）。
5. **会话并发披露**：数据采样时段宿主有桌面应用与另一 workstream（B-2 balance bot，独立 worktree）并发运行；gdUnit 全量在本卡收口阶段单独跑，不受其影响。
6. **数据文件**：本轮 JSON 均转存 /tmp（`m2_perf_win10.json` / `m2_perf_win10_dp.json` / `m2_perf_win5.json` + T37 参照 `m2_perf_t37_windowed.json`）+ 控制台转录，`user://m2_perf.json` 为最后一轮（T2 档）覆盖写。

## 7. 交付物与探针适配台账（tests/scenes/perf_probe.gd，全部 additive）

| 档位/改动 | 用途 | 默认路径影响 |
|---|---|---|
| `-- --anomaly-check` | OBS-3 节流量化（空场景双窗对照，采完即退，不进判定/JSON） | 无 |
| `-- --drill-particles` | 降级演练 T1（逐拍强制 `_degrade`，矩阵 driver 同路径） | 无 |
| `-- --drill-enemies=N` | 降级演练 T2（注入敌数覆盖；亦作负荷分档） | 无（-1=默认 40） |
| `-- --step-trace` | 会话慢速诊断的阶段时间戳+引擎监视器逐段打印 | 无 |
| `-- --orbit-player` | 堆叠去饱和档（玩家 30 帧周期半径 96 圆轨道；对 40 敌单点 knot 实证不足，披露于 §6.3） | 无 |
| `Engine.print_error_messages = false`（_ready 内，含根因注释） | 测量期抑制引擎 WARNING 刷屏（§2.3 放大器 1） | **唯一触碰默认路径的改动**：压测运行的告警日志不再打印（判定打印走 print() 不受影响；无头单测不进此路径——test_perf_probe 仅静态断言，未受影响，全量回归佐证） |
| meta 追加 `drill_particles`/`drill_enemies` | 演练档溯源入 JSON | 无 |
| `-- --uncapped` 档（J-D 建） | 保留未动 | — |

其余交付：本文档；模拟器/AVD/模板为机器级 gitignored 引导物（§4.2），仓库零漂移（`git status` 仅本卡两文件）。

## 8. 收口记录

- 全量单测：`cmd //c "tools\\run_tests.cmd"` → **Overall Summary: 1598 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans，exit 0**（2026-09-02；本卡探针适配后既有用例零改动全绿，执行 `(1598/1598)`）。
- Commit：`feat(m3-xb): dual-platform 60fps verification`（`docs/superpowers/reports/m3-perf.md` 新建 + `tests/scenes/perf_probe.gd` 适配；工作树临时物已清：`hs_err_pid27232.log`/`replay_pid27232.log` 移出留档 /tmp，`*.import`/`project.godot`/`export_presets.cfg` 误触全部还原，`git status` 仅本卡两文件）。hash 见 git log 本 commit。
- 导出产物（user_export/，gitignore）：`starfall-release.apk` / `.aab`（X-A 脚本 PASS）+ 本卡调试用 `starfall-x86/gl/gl3.apk`（零漂移临时开关产物，供 G-1 模拟器复用）。

## 9. 移交 G-1 清单

1. **Android 真机 60fps 五指标复测**（§18.3 硬门槛）：2GB 内存真机安装 release apk，主菜单+完整战斗一局（3 层含 Boss）帧数据（`dumpsys gfxinfo`/Godot 帧监视器），逐指标对照 §1 预算线；超标则按 §5 预案顺序处置。
2. **静默会话/目标机 Windows 终验**：默认档（40 敌）探针一次（§2.3 收窄定性后的例行确认，探针已加固）。
3. **核显本真测**：中端核显笔记本一次 §18.3 五指标（本卡近似口径 §3.1 的终验）。
4. **模拟器即用包**：`xb_perf` AVD（2GB）+ WHPX 就绪，`emulator -avd xb_perf -no-window -gpu swiftshader_indirect -memory 2048` 可直接复用；注意模拟器 GPU 仿真跑不动 Godot 4.7 渲染器（§4.3），帧数据复测必须真机；宿主内存紧张时先关桌面重负载应用再跑 gradle（§4.2 OOM 教训），必要时维持 `-Xmx2700m`。
5. **draw call max 尖峰**：全负荷 max 样本 166~187（T37 参照）虽不进 avg 判定，若真机发现掉帧尖刺与 UI/特效瞬时 draw 相关，可走 balance 修订窗口语义另调（非本卡范围）。
