# M3-J-D Juice 束收口 — 开关矩阵回归 + §18.5 手感清单 + 触感接线核对（G-1 输入）

任务卡 J-D 交付：Juice 束（J-A hitstop v2 / J-B trauma 屏震+连击音高 / J-C 粒子 v2）的收口回归。
本文档为 G-1 真人/真机走查的输入清单与改动台账（风格对齐 `m3-font-walkthrough.md`）。

- 分支：`m3-jd`（基于 main @ c1853d3）
- 自动化冒烟：`godot --headless --path . res://tests/scenes/juice_smoke.tscn` —— **46/46 断言全绿，exit 0，0 SCRIPT ERROR**（本次收口新建）
- 整局开关矩阵：`godot --headless --path . res://tests/scenes/juice_matrix_run.tscn` —— 6 组合 × bot 整局，判定/信息证据逐局采证（本次收口新建，见 §1.2）
- 全量单测：`cmd //c "tools\\run_tests.cmd"` —— 见 §7 收口记录
- 纪律披露：本卡未改动 ui/、fx/、core/、autoload/、project.godot（唯一例外见 §7 收口记录中 perf_probe 的 additive 采样适配，属任务卡明示授权）；审计发现的缺陷一律记录在 §6 移交编排者，不越权修。

---

## 1. 开关矩阵全关回归（判定/信息零损失）

四类开关口径：`hitstop_enabled`（存档键）/ `screen_shake`（滑条，0=关）/ 粒子预算降级（无存档键——规格 §2 J3 的「同屏 ≤200 超预算自动降级」运行期机制）/ `vibration`（存档键）。
红线（Juice v2 规格）：一切效果不得改变数值与判定；全关后游戏可正常进行，核心玩法判定与 HUD 信息（命中判定/伤害数字/状态图标）不受影响。

### 1.1 机检固化：tests/scenes/juice_smoke.gd（46 项断言，全绿）

运行输出（2026-09-01，`SMOKE DONE: OK (0 checks failed)`，exit 0，日志无 SCRIPT ERROR）：

| 分节 | 断言（摘要） | 结果 |
|---|---|---|
| §0 接线存在性 | Fx autoload 在位；ParticlesPool 池容量 240；J-A 导演在位且 balance.json juice 必需键 15 项装载成功（load_ok）；ArtLookup 8 条带贴图可载；GameCamera 可实例化 + trauma² 幅值曲线（1.0→8px、0.5→2px）；设置面板可实例化 | 11/11 PASS |
| §1 hitstop 开关 | `hitstop_enabled=false`：Fx.hitstop(40) no-op（树不冻结）、击杀链 no-op，**伤害数字照常生成**（信息侧无损）；恢复 true：击杀链冻结生效（v2 80ms 缓出）、cancel_hitstop 幂等还原（树暂停解除 + time_scale 归 1）；连击音高接线（on_combo_hit→pitch 上升） | 7/7 PASS |
| §2 屏震开关 | shake=1.0 + trauma 1.0：相机 offset/rotation 抖动生效且**跟随目标不丢**；shake=0 + trauma 1.0（能量再注满）：offset/rotation 钉死为零，跟随依旧（信息零损失）；默认档回落 0.5 | 4/4 PASS |
| §3 粒子预算降级 | 240 次播放打满池：≥200 活跃自动进降级、**溢出请求仍出单帧图**（40 单元 degraded + 200 单元照常逐帧——降级=退化为单帧而非消失）；241 次请求被池硬容量干净丢弃；越时长全部回收；活跃回落预算内自动恢复 | 10/10 PASS |
| §4 面板 UI→存档→消费端 | 真实控件驱动 HitstopToggle/VibrationToggle：toggle 关→`SaveSystem.get_setting` 翻转为 false 且 Fx 冻结请求被门控（UI→落盘→消费端三段贯通）；toggle 开→还原 | 6/6 PASS |
| §5 信息侧抽检 | HUD 红心渲染、金币计数更新、Buff chip（状态图标）渲染；`damage_numbers` 开/关语义（开→暴击数字 42 生成；关→按自身开关语义抑制——非本矩阵四键，恒开参与矩阵）；`colorblind_shapes` 开/关语义（火=▲） | 7/7 PASS |
| §6 输入延迟 ≤1 帧 | `Input.action_press("move_right")` → player `_physics_process` 同物理拍消费（次拍拍首观测 velocity.x>0） | 1/1 PASS |

### 1.2 整局矩阵回归：tests/scenes/juice_matrix_run.gd（6 组合 × bot 整局）

驱动方式：复用 M2-T27 BalanceBot（`tools/balance_bot.gd`，bot 只经玩家真实操作面游玩、无内部数值 hack——见其头注接口边界），同种子族 2001..（M2 校准批）逐组合跑到自然终局（胜/死）。**判定/信息零损失判据逐局采证**：①自然终局（非 crash/超时）；②kills>0（伤害/击杀判定链正常）；③死亡报告成因非空（死亡归因链正常，死因来自 DeathRecorder 生产口径）；④局内采样采到伤害数字节点 + 战斗 HUD 在位（信息通道活着）；⑤火花被采到（表现通道活着；降级组合额外验证降级标记被观测）。

实跑结果（2026-09-01，无头，种子族 2001.. 逐组合异种子起步、卡步逐次 +1 换种子；`MATRIX VERDICT: PASS`，EXIT=0，0 SCRIPT ERROR）：

| 组合 | hitstop | shake | 粒子降级 | 振动 | 种子(尝试) | 结局 | kills | 死因 | 伤害数字 | HUD | 火花 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline_all_on | 开 | 0.5 | 否 | 开 | 2001(×1) | 死亡 23.9s | 8 | 苦力虫的自爆 | 采到 | 在位 | 采到 |
| hitstop_off | **关** | 0.5 | 否 | 开 | 2005(×4) | 死亡 8.1s | 2 | 弩兵的弹幕 | 采到 | 在位 | 采到 |
| shake_off | 开 | **0** | 否 | 开 | 2005(×3) | 死亡 8.1s | 2 | 弩兵的弹幕 | 采到 | 在位 | 采到 |
| particles_degraded | 开 | 0.5 | **全程强制** | 开 | 2005(×2) | 死亡 8.0s | 2 | 弩兵的弹幕 | 采到 | 在位 | 采到（降级标记观测=true） |
| vibration_off | 开 | 0.5 | 否 | **关** | 2005(×1) | 死亡 8.1s | 2 | 弩兵的弹幕 | 采到 | 在位 | 采到 |
| all_off | **关** | **0** | **全程强制** | **关** | 2006(×1) | 死亡 13.1s | 5 | 弩兵的弹幕 | 采到 | 在位 | 采到（降级标记观测=true） |

**结论：6/6 组合全部自然终局 + 判定/信息证据全采集，无 crash、无脚本错误——四类开关全关组合下核心玩法判定与 HUD 信息零损失（机检口径）。**

附加确定性信号（同种子同轨迹）：hitstop 开着的 shake_off / particles_degraded / vibration_off 三个组合在种子 2005 上收敛到**完全相同**的轨迹（8.1s / 2 kills / rooms=0 / 同死因），hitstop_off 在 2005 上也收敛到同一轨迹——同种子下表现层开关（含全程强制粒子降级）不改变游戏进程的直接实证（单种子样本，量级佐证）。

方法论披露（证据边界，不掩饰）：
- **同种子逐局轨迹不可逐 tick 对照**：hitstop 冻结时长是真实墙钟（ignore_time_scale 定时器，fx.gd:79-83），冻结跨过几个逻辑拍随无头帧时序浮动，bot 又以全局物理帧计翻滚决策 → 同种子跨批次结局/kills 合法分岔（首批实测 baseline 同种子一次 36.6s 死、另一次停滞到 cap）。因此本回归的零损失判据取「终局性质 + 判定/信息证据在位」，不取逐 tick 复现。游戏内部计时器（敌 AI/波次/CD）在冻结期整体同步暂停，判定序列不受影响。
- **bot 卡步（停滞至 cap）为 bot 寻路方差**：卡步表现为房间内 kills/hp 静止 ≥60s（bot 不死不进），与开关无关（开关全开的 baseline 在其他批次也卡过；详见 OBS-1 的种子分化数据），驱动以换种子重试（≤4 次、逐次 +1，种子/尝试次数逐行落证据）取自然终局；M2 基线批亦存在超时结局（m2-balance-2026-08-31：timeouts=1/10，18min 封顶口径）。
- **粒子降级组合的实现口径**：降级是运行期预算机制、无存档键，矩阵以 driver 逐拍强制 `Fx.particles._degrade=true` 等价「全程超预算」；单帧退化语义与自动恢复由 juice_smoke §3 以真实触发路径（200+ 活跃）机检。全特效下真实触发的降级观测另见 §4（perf_probe 采样）。
- **无头 bot 局 ≠ 真人通关**：bot 胜率≈0（M2 口径），「四开关全关 + 伤害数字开，真人完整通关一局（3 层含 Boss）」归 G-1 试玩员（§8 第 1 条）。bot 局全程未达 Boss 死亡链，J7 定格演出的整局语境实拍归 G-1。

### 1.3 判定/信息零损失的代码级佐证（四开关均为纯表现层）

| 开关 | 消费点（行号） | 判定侧接触 |
|---|---|---|
| hitstop_enabled | `autoload/fx.gd:90-92`（经导演 `_gate()`）、`fx/hitstop_director.gd:104-107/235-236` | 零——只产「冻结/时间缩放」状态（director 头注红线），判定在请求前已完成 |
| screen_shake | `fx/game_camera.gd:31-48`（读档夹取 0..1，`autoload/fx.gd:146-147`） | 零——只写相机 offset/rotation；`trauma` 为表现层能量值 |
| 粒子预算降级 | `fx/particles_pool.gd:132-157/194-213` | 零——只改池内 Sprite2D 换帧行为（降级=锁第 0 帧） |
| vibration | `ui/settings_panel.gd:165-167`（唯一写入方） | 零——**且无任何消费端**（见 §5 缺陷 D-1） |

---

## 2. §18.5 手感验收清单（GDD 设计稿 §18.5，M0 门槛口径逐条）

| # | 清单项 | 自动化/机检证据 | 状态 |
|---|---|---|---|
| 1 | 输入延迟 ≤1 帧 | juice_smoke §6：action_press 同物理拍被 player 消费（velocity 次拍拍首可测）；M0 曾以逐帧截图取证（m0-evidence/02-input-*.png） | 机检 PASS；真人复感归 G-1 |
| 2 | 翻滚无敌可实拍验证躲弹 | 机检：翻滚 i-frame 窗口与 CD 逻辑有单测守护（tests/unit 既有覆盖）；M0 门禁曾实拍 PASS（m0-gate-playtest.md §2） | M0 已证；M3 v2 语境实拍归 G-1 |
| 3 | TTK 达标 | M2 balance 批量化证据：单房中位 26.1s、杂兵 TTK 分位见 m2-balance-2026-08-31.md（GDD §14.3 带内） | 机检 PASS（引用 M2 报告） |
| 4 | 击杀/受击反馈全触发 | juice_smoke §1/§5 + tests/unit/test_fx.gd（火花/白闪/数字/震屏注入逐件）；矩阵 6 局火花+伤害数字逐局采到 | 机检 PASS；「反馈爽感」主观项归 G-1 |
| 5 | 触屏双摇杆可单手完成整层 | 需 Android 真机 | **待 G-1（Android 真机）** |

## 3. Juice v2 增项逐条（specs/2026-08-30-m3-juice-v2-spec.md §2/§4）

| 项 | 规格 | 落地状态（代码证据） | 机检证据 | 主观项归属 |
|---|---|---|---|---|
| J1 hitstop v2 | 击杀 80ms 缓出/多杀+40 封顶 120/Boss 阶段 120+0.3×240/玩家死亡 0.3×600 | ✅ `fx/hitstop_director.gd` 状态机 + `data/balance.json` juice 节（唯一数值出处，15 必需键 fail-closed）；玩家死亡慢速接线 `core/meta/death_recorder.gd:171` | test_hitstop.gd（时序/缓出采样/门控）；juice_smoke §1 | 缓出「可感」→ 待 G-1 |
| J1 玩家死亡去饱和 0.4s 渐入 | desat 渐入 | ❌ **未落地**：`fx/hitstop_director.gd:181` 注明「着色器落地在 J-C」，全库 grep desat 无着色器/消费端（balance 参数存在但无人读） | — | 缺陷 D-3（§6） |
| J2 trauma 屏震 | trauma²×8px/×2°、衰减 1.6/s、seed 42、来源表、峰值≤1.0、默认 50% | ✅ `fx/game_camera.gd` + `autoload/fx.gd:33/126-153` + balance juice 来源表（0.3/0.4/0.5/1.0/0.15） | test_hitstop.gd:123-133（clamp/衰减采样）；juice_smoke §2 | 「不晕」晕动观感 → 待 G-1 |
| J3 粒子 v2 | 4 帧火花条带 ×6 色/暴击金 1.3×/枪口焰 3 帧 tint/碎片环 6 帧/预算 ≤200 降级 | ✅ `core/art/art_lookup.gd:92-114` + `fx/particles_pool.gd`（池 240/预算 200/单帧降级/自动恢复） | test_art_lookup.gd；juice_smoke §3；压测自然触顶观测见 §4.1（峰 16~17/200，标准配比未触顶） | 观感 → 待 G-1 |
| J4 伤害数字 v2 | 暴击弹跳 1.0→1.6→1.3/0.18s + tick 0.8× 小号 + 屏外裁剪 + damage_numbers 全跳过 | ✅ `autoload/fx.gd:305-378`（常量为规格直译）+ 视野裁剪缝（测试注入 + 生产视口/相机回退） | test_fx.gd:165（裁剪）；juice_smoke §5 | 观感 → 待 G-1 |
| J5 连击音高 | 窗 1.2s/+2 音分/封顶 6 档/换武器·脱战·受击重置 | ✅ `core/combat/combo_counter.gd`（纯逻辑）+ `autoload/fx.gd:219-236` + 生产接线 combat_system.gd:127/131（远程命中上报+消费）、melee.gd:63、weapon_rig.gd:55 | test_combo_counter.gd；juice_smoke §1 | 「可闻」→ 待 G-1 |
| J6 低血呼吸红晕 | 2HP≥HP>0 呼吸（0.8s 周期 alpha 0.15~0.35）+ 心跳音（若 M2 已接则复用） | ⚠️ 红晕呼吸已落地但参数非规格字面：`ui/hud.gd:13/192-201`（阈值 hp≤2 ✓；呼吸 0.12↔0.38、0.7s 半程≈1.4s 周期，tween 正弦 Ease in/out）；心跳音：M2 未接 lowhp_heartbeat（grep 零命中），规格条件「若已接则复用」不成立 → N/A | juice_smoke §5（低血红晕显隐随 low_hp 快照） | 呼吸观感 → 待 G-1；参数偏差记录 D-4 |
| J6 受击方向指示 | 8px 弧形闪光指向来源 0.2s 淡出 | ❌ **未实现**（全库 grep 零命中） | — | 缺陷 D-3（§6） |
| J6 振动 | 受击 30ms/Boss 死亡 80ms，Android 生效，键默认开 | ⚠️ 设置键+UI+持久化 ✅；**振动 API 消费端不存在**（§5 链路核对） | juice_smoke §4（键往返+门控） | 缺陷 D-1（§6） |
| J7 Boss 死亡定格链 | 定格 300ms→白闪+trauma 1.0→0.3× 慢速爆散 900ms→战利品延迟 300ms→可快进 | ⚠️ 链主体 ✅：`core/rooms/floor_scene.gd:1191` → `autoload/fx.gd:286-298`（trauma 1.0 先注再冻）→ 导演 BOSS_DEATH 时序；白闪+碎片环 `fx/particles_pool.gd:95-126`（node_added 逐实例订阅 boss_defeated）；❌ 快进未接线（fx.gd:300 `request_skip` 全库无调用点——注释自认「输入接线在 J-C/J-D 收口」）；❌ 战利品延迟喷出无人消费（`hitstop_director.gd:33` on_loot_delay_started 生产侧无挂接，掉落照旧即时） | test_hitstop.gd（链时序/skip 幂等/loot 不吞） | 演出完整性/可跳过实感 → 待 G-1；缺陷 D-2/D-3（§6） |

---

## 4. 全特效压测采帧耗时（代理指标，目标机复测归 X-B）

口径：复用 M2-T29 `tests/scenes/perf_probe.gd` 原预算与双窗口测量法（节流窗 60fps 采逻辑帧/渲染 CPU/draw call + 不节流窗采整帧墙钟；vsync 关；热身 120 帧 + 采样 480 帧），负荷 = 每层最密战斗模板 + 40 敌 + 500 弹 + 0 伤弹走完整命中管线（=juice 全开）。**本卡 additive 适配**：采样循环追加粒子池活跃峰/降级标记观测、`-- --uncapped` 诊断档与阶段标记（仅观测/披露，不改默认预算判定路径，见 perf_probe.gd 内注释）。

### 4.1 本开发机今日（2026-09-01）实测

**环境异常披露（先行）**：本会话下 `Engine.max_fps` 节流机制异常——置 60 后实测 0.2~2.5s/帧（窗口化与无头同现；**pre-J-A 的 M2 期代码同样复现**，且同机 M2 记录为 TIME_FPS=60.0），置 0 即恢复全速；窗口化下另有远程显示适配器（OrayIdd + TeamViewer 会话）呈现节流（GPU 占用仅 16%）。经二分定位为**环境/会话级问题，非 Juice v2 或游戏回归**。故今日数据取自 `-- --uncapped` 诊断档（无头全速 ~145fps，两窗均不节流）——逐 tick/逐帧计量项有效，整帧墙钟与 60fps 合成线不判定（探针 meta.paced=false 自动跳过并打印）：

| 层 | 逻辑帧 avg/max（≤6ms） | 渲染 CPU avg（≤10ms，无头下仅 TIME_PROCESS 口径） | 活动实体（≤300） | 同屏弹幕峰（≤500） | 粒子池活跃峰 / 降级触发 |
|---|---|---|---|---|---|
| F1 洞穴（combat_a1_03） | **0.014 / 0.023 ms PASS** | 0.004 ms | 64 PASS | 500 顶格 PASS | 17 / 未触发 |
| F2 暗视野+剪影+冰面（combat_a2_01） | **0.015 / 0.027 ms PASS** | 0.006 ms | 61 PASS | 500 顶格 PASS | 16 / 未触发 |
| F3 岩浆+火雨 | 本会话未取得有效数据（长跑爬行，两次复现，含 pre-J-A 对照） | — | — | — | — |

粒子观测注记：标准压测配比（500 弹 + 0 伤命中管线全开）下粒子池活跃峰仅 16~17 / 预算 200——**命中频率不足以自然触顶，预算降级未被自然触发**（降级语义由 juice_smoke §3 真实 240 池满路径 + 矩阵 particles_degraded/all_off 组合强制档覆盖，均 PASS）。draw call 无头下无效（Dummy 渲染器，恒 0）。

### 4.2 渲染侧参照（M2 窗口化基线，同机 2026-08-31，pre-Juice-v2）

i5-14400F / RTX 3050 / OrayIdd 虚拟显示（m2-perf.md §0）：逻辑帧 0.013ms、渲染 CPU 0.022~0.024ms、**60fps 合成线 6.76~11.22ms 全层 PASS（最差余 33%）**、活动实体 65~69、弹幕 500 顶格；F2 draw call avg 162.6 超 150 约束 ~8%（「全图集」前提未达成的结构性缺口，M2 已上报，非本卡范围）。

**结论口径**：Juice v2 全特效叠加后，本开发机今日可证部分全部 PASS 且余量巨大（逻辑帧占预算 0.25%、实体 21%、弹幕顶格即达标）；渲染侧窗口化 60fps 正式复测（含 v2-on 增量与本会话节流异常下的复测环境）移交 **X-B**——其卡面即拥有「双平台目标机复测 + 超标降级预案」职责，本卡数据为代理指标中的代理（无头逻辑侧 + M2 窗口基线参照）。

---

## 5. 触感接线核对（设置面板 → 移动端实际触发，逐环）

| 环 | 链路 | 证据（文件:行） | 状态 |
|---|---|---|---|
| ① UI 键 | 设置面板振动开关（Button toggle） | `ui/settings_panel.gd:39/55/73/112/125/165-167`（`_on_vibration_toggled` → `_toggle_setting`） | ✅ |
| ② 即时落盘 + 信号 | `SaveSystem.set_setting("vibration")`（内含 save_now）+ `setting_changed` 发射 | `ui/settings_panel.gd:187-191`；`autoload/save_system.gd:272-277` | ✅ |
| ③ 持久化往返 | 默认键 `"vibration": true`；重载合并/往返 | `autoload/save_system.gd:37`；tests/unit/test_settings_ui.gd:122/208-218（断言存在） | ✅ |
| ④ 消费端（运行时读键触发振动） | `get_setting("vibration", …)` 的 gameplay 调用点 | **全库 grep 零命中**（仅设置面板自身与 save_system 默认表） | ❌ 断链 |
| ⑤ 平台 API | `Input.vibrate_handheld()` / `Input.start_joy_vibration()` 调用点 | **全库 grep 零命中**（含 core/ui/autoload/fx） | ❌ 断链 |

**核对结论**：链路在 ④ 断——`vibration` 目前是「只写不读」的设置键：面板开关、持久化、单测俱全（S-A 交付口径即「仅设置键」，`save_system.gd:30` 注释明示「振动 API 消费在 J6/J-D」），但 J6 规格的「（Android）受击振动 30ms / Boss 死亡 80ms」从未接线，Android 真机上振动不会触发（键默认开也无副作用）。**本卡按纪律不越权补线（消费端在 core/ 或需新建接线点），缺陷上报编排者裁定（§6 D-1）**；juice_smoke §4 已把「面板→存档」两环固化机检，补线后可直接复用。

---

## 6. 阻塞/缺陷项移交（编排者裁定；本卡零越权改动）

| 编号 | 级别 | 事项 | 证据 |
|---|---|---|---|
| D-1 | 缺陷（J6 交付缺口） | 振动无 API 消费端：受击 30ms / Boss 死亡 80ms 从未接线，Android 真机振动不可触发（§5） | grep 全库零命中；save_system.gd:30 自述「消费在 J6/J-D」 |
| D-2 | 缺陷（J7 交付缺口） | Boss 死亡链快进（连按攻击键 `Fx.request_skip`）无输入接线 | fx.gd:300-303 定义存在、全库无调用点（fx.gd:300 注释自认「输入接线在 J-C/J-D 收口」未兑现） |
| D-3 | 缺陷（J1/J6/J7 表现缺口，同一移交批次） | ①玩家死亡去饱和渐入未落地（hitstop_director.gd:181 待 J-C 的着色器未存在）；②受击方向指示（8px 弧形闪光）未实现；③J7 战利品延迟 300ms 喷出未挂接（on_loot_delay_started 无生产消费方，掉落即时照旧） | grep desat/方向指示/loot 消费端零命中 |
| D-4 | 观察项（轻） | 低血呼吸红晕参数与 J6 规格字面偏差（实现 0.12↔0.38 / 1.4s 周期 tween vs 规格 0.15~0.35 / 0.8s 周期）；阈值 hp≤2 正确 | ui/hud.gd:13/192-201 |
| OBS-1 | 观察（bot 侧，非游戏缺陷） | bot 卡步率偏高且**按种子（布局）分化**：本轮回归中种子 2002/2003/2004 在每个批次均停滞（确定性），2001/2005/2006 恒自然终局；M2 基线批（pre-J-A，18min 封顶）同族种子仅 1/10 超时。卡步 = 房间内 kills/hp 静止 ≥60s 的寻路停滞，与开关无关（各开关组合、含全开 baseline 均出现）。若 B-2 平衡周复用 bot，建议先修低血/寻路停滞或换种子族 | §1.2 披露 + 矩阵日志 RETRY 行（批次 3/5/6 交叉对比） |
| OBS-2 | 观察（预存时序口径） | player 翻滚 CD 基于全局物理帧（`core/player/player.gd` start_roll/roll_ready_at），hitstop 冻结期全局帧照走 → 冻结拍内 CD 相对游戏时序微缩。M0 时代口径、影响每次冻结数帧，非判定损失；如需收紧另立小卡 | player.gd 与 fx.gd:79-83 真实毫秒定时器口径差 |
| OBS-3 | 观察（环境，移交 X-B） | 本开发机当前会话 `Engine.max_fps` 节流异常（置 60 → 0.2~2.5s/帧，置 0 全速；窗口/无头、pre/post-J-A 代码同现；同机 M2 记录 TIME_FPS=60.0）+ 远程显示适配器呈现节流（GPU 16%）。§18.3 节流窗复测需在正常会话/目标机执行 | §4.1 披露 + 诊断日志（perf warmup 帧率标记、二分记录） |

### J-D 收口裁定项（此前各卡留言「收口归 J-D」的三处，均裁定维持现状）

| 项 | 裁定 | 理由 |
|---|---|---|
| 粒子池表现参数（预算 200/池 240/帧时长 0.05/tint/1.3×）是否入 balance.json（particles_pool.gd:16 留言） | **维持模块常量，不入 balance** | 表现调校参数非数值平衡；对齐 AudioMgr POOL_SIZE=8 先例；入 balance 需扩导演 fail-closed 必需键集，扩校验面无对应收益 |
| 枪口焰三组 tint 色值（particles_pool.gd:38 留言） | **维持实现预设**（步枪热白黄/霰弹橙/激光青） | 规格只定「三组预设色」未定值；观感项，G-1 走查如不满意走既有 balance 修订窗口语义另调 |
| fx.gd 伤害数字 8px/元素形状 10px（m3-font-walkthrough §2.4 移交 J-D 对照 8/10/12） | **维持 8/10 不追 12** | 伤害数字为纯西文数字+2px 描边（8px 非整数缩栅风险低于中文），且战斗层读屏干扰随字号增大——维持 font-walkthrough §2.4 的建议口径；元素形状为符号点缀同理。主题接线后两者已切 fusion-pixel，锐利度观感复核归 G-1（§8 第 10 条） |

---

## 7. 收口记录

- 新建：`tests/scenes/juice_smoke.gd` + `.tscn` + `.gd.uid`（开关矩阵机检固化）、`tests/scenes/juice_matrix_run.gd` + `.tscn` + `.gd.uid`（bot 整局矩阵驱动）、本文档。
- 适配：`tests/scenes/perf_probe.gd` additive 粒子观测采样 + `-- --uncapped` 诊断档 + 阶段标记（任务卡明示授权；默认路径预算/判定逻辑零改动，M2 原口径保持默认）。
- 全量单测：`cmd //c "tools\\run_tests.cmd"` → **Overall Summary: 1598 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans，86/86 套件，exit 0**（2026-09-01，总耗时 1min15s）。本卡新增文件不进 gdUnit 收集（非 test_* 命名，同 font_render_smoke 惯例），既有用例零适配。
- 整局矩阵 `MATRIX SUMMARY` 原始转录（`MATRIX VERDICT: PASS`，EXIT=0，0 SCRIPT ERROR）：
  ```text
  MATRIX SUMMARY: 6 combos, baseline_kills=8
    baseline_all_on      seed=2001 x1 outcome=death floor=1 rooms=1 kills=8   dur=  23.9s dmg#peak=1 hud=true spark=true
    hitstop_off          seed=2005 x4 outcome=death floor=1 rooms=0 kills=2   dur=   8.1s dmg#peak=1 hud=true spark=true
    shake_off            seed=2005 x3 outcome=death floor=1 rooms=0 kills=2   dur=   8.1s dmg#peak=1 hud=true spark=true
    particles_degraded   seed=2005 x2 outcome=death floor=1 rooms=0 kills=2   dur=   8.0s dmg#peak=1 hud=true spark=true
    vibration_off        seed=2005 x1 outcome=death floor=1 rooms=0 kills=2   dur=   8.1s dmg#peak=1 hud=true spark=true
    all_off              seed=2006 x1 outcome=death floor=1 rooms=0 kills=5   dur=  13.1s dmg#peak=1 hud=true spark=true
  ```
  （完整逐局 JSON 行含 death_cause/coins/gems/wall_s 等字段，见收口批次控制台日志；particles_degraded 与 all_off 的 degraded_observed=true。）
- perf 原始 JSON：`user://m2_perf.json` 本轮**未产出**（诊断档运行因 floor 3 长跑爬行被看门狗截停，未走到写盘；§4.1 数值转录自控制台逐层判定行）。

## 8. 移交 G-1 试玩员清单（自动化不能替代的主观/真机项）

1. **四开关全关（hitstop/屏震/振动关 + 默认档）真人完整通关一局**（3 层含 Boss）：验证无障碍红线「无判定/信息损失可通关」的真人口径（机检证据 §1，本项为其补全）。
2. hitstop v2 缓出「可感」：击杀 80ms 缓出 vs v1 60ms 定值对比、多杀叠加、暴击 40ms 层次是否可辨。
3. trauma 屏震「不晕」：默认 50% 档连续战斗 10min 晕动自查；0/100 两档对比。
4. 连击音高「可闻」：1.2s 窗内连续命中音高爬升（+2 音分/档，封顶 +12 音分）是否可感。
5. Boss 死亡定格演出完整性与观感（300ms 定格→白闪→0.3× 慢速 900ms→碎片环/白闪）；快进接线补上后（D-2）验证连按攻击键快进。
6. J3 粒子观感：火花六元素/暴击金 1.3×/枪口焰 tint/碎片环；超预算降级单帧在实战中是否可接受（不显突兀）。
7. J4 伤害数字观感：暴击弹跳、元素 tick 小号跳字在混战中的可读性。
8. 低血呼吸红晕观感（D-4 参数偏差是否需追平规格字面）。
9. §18.5 第 5 条：Android 真机触屏双摇杆单手完整一层；振动接线补上后（D-1）真机受击/Boss 死亡振动体验。
10. 伤害数字 8px / 元素形状 10px 锐利度复核（§6 J-D 裁定维持现状的观感确认）。
