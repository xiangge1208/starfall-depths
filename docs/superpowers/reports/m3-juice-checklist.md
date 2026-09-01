# M3-J-D Juice 束收口 — 开关矩阵回归 + §18.5 手感清单 + 触感接线核对（G-1 输入）

任务卡 J-D 交付：Juice 束（J-A hitstop v2 / J-B trauma 屏震+连击音高 / J-C 粒子 v2）的收口回归。
本文档为 G-1 真人/真机走查的输入清单与改动台账（风格对齐 `m3-font-walkthrough.md`）。

- 分支：`m3-jd`（基于 main @ c1853d3）
- 自动化冒烟：`godot --headless --path . res://tests/scenes/juice_smoke.tscn` —— **70/70 断言全绿，exit 0，0 SCRIPT ERROR**（J-D 收口新建 46 项 + 补课批次新增 24 项，见 §0）
- 整局开关矩阵：`godot --headless --path . res://tests/scenes/juice_matrix_run.tscn` —— 6 组合 × bot 整局，判定/信息证据逐局采证（J-D 收口新建，见 §1.2）
- 全量单测：`cmd //c "tools\\run_tests.cmd"` —— 见 §7 收口记录
- 纪律披露：本卡未改动 ui/、fx/、core/、autoload/、project.godot（唯一例外见 §7 收口记录中 perf_probe 的 additive 采样适配，属任务卡明示授权）；审计发现的缺陷一律记录在 §6 移交编排者，不越权修。
- **补课批次（同分支二阶段，§6 D-1~D-4 已修复）**：修复不适用上条纪律披露——编排者裁定补课授权后改动 `autoload/fx.gd`、`core/player/player.gd`、`core/rooms/floor_scene.gd`、`ui/hud.gd`、`data/balance.json`，新建 `fx/hit_arc.gd`、`fx/desat.gdshader`；详见 §0。

---

## 0. J-D 补课批次（D-1~D-4 缺口修复台账，2026-09-01）

| 缺口 | 修复 | 实现位置（文件:行） | 规格出处 | 自动化断言（juice_smoke §7~§10） |
|---|---|---|---|---|
| D-1 振动无消费端 | `Fx.request_vibrate(ms)`：设置键（`get_setting("vibration")`，消费模式同 screen_shake 的运行时读取）+ 平台能力双重门控后才调 `Input.vibrate_handheld`；桌面/无头在 `Fx.vibration_supported()` 早退（不裸调 API）；`vibrate_api` 注入口供无头机检。受击 30ms（`on_player_hurt`）/ Boss 死亡 80ms（`request_boss_death`，自有开关语义不随演出链门控）；时长入 balance juice（`vibration_hurt_ms`/`vibration_boss_death_ms`） | `autoload/fx.gd:45-50`（注入口）、`autoload/fx.gd:238-258`（请求原语+双门控）、`autoload/fx.gd:290-291`（受击接线）、`autoload/fx.gd:360-361`（Boss 死亡接线）、`data/balance.json:30-31` | Juice v2 §2 J6「（Android）受击振动 30ms / Boss 死亡 80ms：新设置键 vibration（默认开），仅 Android 生效」+ 规格头注「时长/幅度运行期入 balance.json」 | §7 五项：平台门控 false（无 Android/无注入）、注入口视为具备能力、受击 30ms、Boss 死亡 80ms、vibration=false 双路不震 |
| D-2 J7 快进无接线 | `Fx._poll_boss_death_skip`（_process 逐帧轮询）：仅 BOSS_DEATH 链活跃时消费既有 InputMap 动作 `fire`/`touch_fire`（不新增键位）→ `director.skip()`；非演出期间零误触发；Fx 为 PROCESS_MODE_ALWAYS，冻结拍照跑、首按即可跳定格段。`Fx.boss_death_chain_active()` 查询器供快进/掉落挂起共用 | `autoload/fx.gd:383-396`（查询器+轮询）、`autoload/fx.gd:605`（_process 挂接） | Juice v2 §2 J7「整链 boss_defeated 信号驱动，可被跳过（连按攻击键快进）」 | §8 三项：非演出期按键零误触发、链活跃冻结在位、演出期按键跳链+时计恢复 |
| D-3a 玩家死亡去饱和 | 全屏 `hint_screen_texture` shader（亮度加权去饱和，无缩放/无重采样/无过滤，像素风红线不破）；层挂 current_scene 随死亡结算换场景自动回收；渐入按真实毫秒推进（time_scale 0.3 不拉长，0.4s 完成于 600ms 链尾前）；时长=导演参数 `player_death_desat_ms`（balance 唯一出处）；hitstop off/链接管失败不启动（演出整体跳过口径一致）；`cancel_hitstop` 边界清理 | `autoload/fx.gd:11`（DESAT_SHADER）、`autoload/fx.gd:52-60`（层状态+前台门注入口）、`autoload/fx.gd:370-372`（request_player_death 接线）、`autoload/fx.gd:406-460`（启停/推进/查询；cancel 清理 `autoload/fx.gd:141`）、`fx/desat.gdshader`（新建） | Juice v2 §2 J1「玩家死亡 0.3× 慢速 600ms + 去饱和渐入 0.4s → 死亡结算」（慢速段 J-A 已落地，本批次只补渐入） | §9 前四项：hitstop off 不启动、接管后 ~0 起渐入、真实毫秒推进（慢速不拉长）、400ms 满档 + cancel 清理 |
| D-3b 受击方向指示 | `Fx.spawn_hit_arc(player, from)`：8px 弧形闪光指向伤害来源、0.2s 线性淡出、到时自毁（纯 _draw 矢量弧，无贴图/无缩放/无过滤）；方向取伤害事件 `ctx["from"]`（player.gd 受击缝传入）。**无方向裁定（规格未定义，取「不误导」）**：from 缺失（INF/非有限）/与玩家重合（<1px，环境 DOT 等无来源）不生成弧——记录于本行，G-1 如有异议另调 | `autoload/fx.gd:290-292`（on_player_hurt 接线）、`autoload/fx.gd:298-322`（spawn_hit_arc）、`fx/hit_arc.gd`（新建，RADIUS=8/FADE_SECONDS=0.2 为规格直译常量）、`core/player/player.gd:363`（ctx.from 传入） | Juice v2 §2 J6「v1 红晕基础上加受击方向指示（以玩家为中心的 8px 弧形闪光指向伤害来源，0.2s 淡出）」 | §10 前六项：右向 0rad/上向 -PI/2 几何、无方向不画弧（缺失+重合）、8px/0.2s 规格、线性淡出半程 ~0.5、0.2s 自毁 |
| D-3c J7 战利品延迟 300ms | `Fx.defer_boss_loot(cb)`：Boss 死亡链在跑时 floor_scene 把掉落生成挂起，导演 loot 段开始（`on_loot_delay_started`，_init_director 挂接）或快进/链接管补发时统一 flush（快进不吞事件）；链缺席 defer 拒绝、同步照旧——掉落内容/盐流/判定零改动，只挪表现时机；flush 带 `is_valid` 宿主释放守卫 | `autoload/fx.gd:54-60`（挂起队列）、`autoload/fx.gd:82`（on_loot_delay_started 挂接）、`autoload/fx.gd:466-481`（defer/flush）、`core/rooms/floor_scene.gd:1236-1254`（_spawn_guest_drops 挂起门+_spawn_drops_now 原路径保留） | Juice v2 §2 J7「战利品延迟 300ms 喷出（视觉聚焦）」（loot_delay_ms=300 段仍保持 0.3× 慢速，落在恢复时计前） | §9 后四项：链活跃接受挂起、不立即喷出、快进补发恰一次、链缺席拒绝（同步照旧） |
| D-4 低血呼吸参数偏差 | 呼吸参数收回规格带内：alpha 0.15~0.35（原 0.12↔0.38）、0.8s 周期（半程 0.4s，原 1.4s 周期）；阈值 hp≤2 原本正确不动。参数提为 `HUD.BREATH_*` 常量供机检 | `ui/hud.gd:16-18`（常量）、`ui/hud.gd:196-209`（_build_vignette/_start_breath_tween） | Juice v2 §2 J6「红晕 vignette 呼吸（0.8s 周期正弦，alpha 0.15~0.35）」 | §10 末项：三常量对齐规格（0.15/0.35/0.8s） |

补课批次自动化与全量：juice_smoke 46 → **70 断言**（§7 振动 5 + §8 快进 3 + §9 去饱和/掉落 9 + §10 方向/呼吸 7），全绿 exit 0；全量 gdUnit 1598 用例 0 错误（§7）。注：新增 `class_name HitArc` 后已跑 `godot --headless --import` 重建全局类缓存（标准 Godot 工作流，fresh checkout 首次需一次 import）。

---

## 1. 开关矩阵全关回归（判定/信息零损失）

四类开关口径：`hitstop_enabled`（存档键）/ `screen_shake`（滑条，0=关）/ 粒子预算降级（无存档键——规格 §2 J3 的「同屏 ≤200 超预算自动降级」运行期机制）/ `vibration`（存档键）。
红线（Juice v2 规格）：一切效果不得改变数值与判定；全关后游戏可正常进行，核心玩法判定与 HUD 信息（命中判定/伤害数字/状态图标）不受影响。

### 1.1 机检固化：tests/scenes/juice_smoke.gd（70 项断言，全绿——收口 46 + 补课 24）

运行输出（2026-09-01，`SMOKE DONE: OK (0 checks failed)`，exit 0，日志无 SCRIPT ERROR）：

| 分节 | 断言（摘要） | 结果 |
|---|---|---|
| §0 接线存在性 | Fx autoload 在位；ParticlesPool 池容量 240；J-A 导演在位且 balance.json juice 必需键 15 项装载成功（load_ok）；ArtLookup 8 条带可载；GameCamera 可实例化 + trauma² 幅值曲线（1.0→8px、0.5→2px）；设置面板可实例化 | 11/11 PASS |
| §1 hitstop 开关 | `hitstop_enabled=false`：Fx.hitstop(40) no-op（树不冻结）、击杀链 no-op，**伤害数字照常生成**（信息侧无损）；恢复 true：击杀链冻结生效（v2 80ms 缓出）、cancel_hitstop 幂等还原（树暂停解除 + time_scale 归 1）；连击音高接线（on_combo_hit→pitch 上升） | 7/7 PASS |
| §2 屏震开关 | shake=1.0 + trauma 1.0：相机 offset/rotation 抖动生效且**跟随目标不丢**；shake=0 + trauma 1.0（能量再注满）：offset/rotation 钉死为零，跟随依旧（信息零损失）；默认档回落 0.5 | 4/4 PASS |
| §3 粒子预算降级 | 240 次播放打满池：≥200 活跃自动进降级、**溢出请求仍出单帧图**（40 单元 degraded + 200 单元照常逐帧——降级=退化为单帧而非消失）；241 次请求被池硬容量干净丢弃；越时长全部回收；活跃回落预算内自动恢复 | 10/10 PASS |
| §4 面板 UI→存档→消费端 | 真实控件驱动 HitstopToggle/VibrationToggle：toggle 关→`SaveSystem.get_setting` 翻转为 false 且 Fx 冻结请求被门控（UI→落盘→消费端三段贯通）；toggle 开→还原 | 6/6 PASS |
| §5 信息侧抽检 | HUD 红心渲染、金币计数更新、Buff chip（状态图标）渲染；`damage_numbers` 开/关语义（开→暴击数字 42 生成；关→按自身开关语义抑制——非本矩阵四键，恒开参与矩阵）；`colorblind_shapes` 开/关语义（火=▲） | 7/7 PASS |
| §6 输入延迟 ≤1 帧 | `Input.action_press("move_right")` → player `_physics_process` 同物理拍消费（次拍拍首观测 velocity.x>0） | 1/1 PASS |
| §7 D-1 振动消费端（补课） | 平台门控（无 Android 特性/无注入口 → `vibration_supported()` false，不裸调 API）；注入口机检调用链；受击 30ms / Boss 死亡 80ms 触发；`vibration=false` 双路不震 | 5/5 PASS |
| §8 D-2 快进接线（补课） | 非演出期连按攻击键零误触发；Boss 死亡链活跃冻结在位；演出期按键跳链 + 时计恢复（time_scale 归 1） | 3/3 PASS |
| §9 D-3a/D-3c（补课） | hitstop off 不启去饱和；接管后 ~0 起渐入、真实毫秒推进（慢速 0.3× 不拉长）、400ms 满档、cancel 清理；掉落挂起不立即喷出、快进补发恰一次、链缺席拒绝挂起（同步照旧） | 9/9 PASS |
| §10 D-3b/D-4（补课） | 方向几何（右 0rad/上 -PI/2）、无方向不画弧（缺失/重合裁定）、8px/0.2s 规格常量、线性淡出、0.2s 自毁；低血呼吸三常量对齐规格 §J6 | 7/7 PASS |

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
| hitstop_enabled | `autoload/fx.gd`（经导演 `_gate()`）、`fx/hitstop_director.gd:104-107/235-236` | 零——只产「冻结/时间缩放」状态（director 头注红线），判定在请求前已完成 |
| screen_shake | `fx/game_camera.gd:31-48`（读档夹取 0..1，`autoload/fx.gd` screen_shake_scale） | 零——只写相机 offset/rotation；`trauma` 为表现层能量值 |
| 粒子预算降级 | `fx/particles_pool.gd:132-157/194-213` | 零——只改池内 Sprite2D 换帧行为（降级=锁第 0 帧） |
| vibration | `autoload/fx.gd:255-258`（request_vibrate 运行时读键；受击 `:291`/Boss 死亡 `:361` 触发）——**补课后有消费端**（见 §5） | 零——纯触觉反馈，不触碰任何数值/判定 |

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
| J1 玩家死亡去饱和 0.4s 渐入 | desat 渐入 | ✅ **补课已落地**：`fx/desat.gdshader`（hint_screen_texture 亮度加权去饱和）+ `autoload/fx.gd:370-372/406-460`（request_player_death 接线 + 真实毫秒渐入推进）；balance 参数 `player_death_desat_ms=400` 已有消费端；层挂 current_scene 随死亡结算自动回收 | juice_smoke §9（off 不启动/渐入推进/400ms 满档/cancel 清理） | 去饱和观感 → 待 G-1 |
| J2 trauma 屏震 | trauma²×8px/×2°、衰减 1.6/s、seed 42、来源表、峰值≤1.0、默认 50% | ✅ `fx/game_camera.gd` + `autoload/fx.gd:33/126-153` + balance juice 来源表（0.3/0.4/0.5/1.0/0.15） | test_hitstop.gd:123-133（clamp/衰减采样）；juice_smoke §2 | 「不晕」晕动观感 → 待 G-1 |
| J3 粒子 v2 | 4 帧火花条带 ×6 色/暴击金 1.3×/枪口焰 3 帧 tint/碎片环 6 帧/预算 ≤200 降级 | ✅ `core/art/art_lookup.gd:92-114` + `fx/particles_pool.gd`（池 240/预算 200/单帧降级/自动恢复） | test_art_lookup.gd；juice_smoke §3；压测自然触顶观测见 §4.1（峰 16~17/200，标准配比未触顶） | 观感 → 待 G-1 |
| J4 伤害数字 v2 | 暴击弹跳 1.0→1.6→1.3/0.18s + tick 0.8× 小号 + 屏外裁剪 + damage_numbers 全跳过 | ✅ `autoload/fx.gd:305-378`（常量为规格直译）+ 视野裁剪缝（测试注入 + 生产视口/相机回退） | test_fx.gd:165（裁剪）；juice_smoke §5 | 观感 → 待 G-1 |
| J5 连击音高 | 窗 1.2s/+2 音分/封顶 6 档/换武器·脱战·受击重置 | ✅ `core/combat/combo_counter.gd`（纯逻辑）+ `autoload/fx.gd:219-236` + 生产接线 combat_system.gd:127/131（远程命中上报+消费）、melee.gd:63、weapon_rig.gd:55 | test_combo_counter.gd；juice_smoke §1 | 「可闻」→ 待 G-1 |
| J6 低血呼吸红晕 | 2HP≥HP>0 呼吸（0.8s 周期 alpha 0.15~0.35）+ 心跳音（若 M2 已接则复用） | ✅ **补课已对齐规格字面**：`ui/hud.gd:16-18/196-209`（alpha 0.15↔0.35、半程 0.4s=0.8s 周期，参数提为 BREATH_* 常量；原 0.12↔0.38/1.4s 偏差已收回）；心跳音：M2 未接 lowhp_heartbeat（grep 零命中），规格条件「若已接则复用」不成立 → N/A | juice_smoke §10（三常量对齐规格）；§5（低血红晕显隐随 low_hp 快照） | 呼吸观感 → 待 G-1 |
| J6 受击方向指示 | 8px 弧形闪光指向来源 0.2s 淡出 | ✅ **补课已实现**：`fx/hit_arc.gd`（纯 _draw 矢量弧，无贴图/无缩放/无过滤）+ `autoload/fx.gd:290-322`（受击缝接线）；方向取伤害事件 `ctx["from"]`（player.gd:363 传入）；无方向裁定=不画弧（见 §0 D-3b 行） | juice_smoke §10（几何/淡出/裁定六项） | 观感 → 待 G-1 |
| J6 振动 | 受击 30ms/Boss 死亡 80ms，Android 生效，键默认开 | ✅ **补课已接线**：设置键+UI+持久化 + `Fx.request_vibrate` 消费端（`autoload/fx.gd:238-258`，开关+平台双门控，时长入 balance juice）；调用链核对见 §5 | juice_smoke §4（键往返+门控）+ §7（消费端调用链） | 真机振动体验 → 待 G-1 |
| J7 Boss 死亡定格链 | 定格 300ms→白闪+trauma 1.0→0.3× 慢速爆散 900ms→战利品延迟 300ms→可快进 | ✅ 链主体 ✅：`core/rooms/floor_scene.gd:1191` → `autoload/fx.gd`（trauma 1.0 先注再冻）→ 导演 BOSS_DEATH 时序；白闪+碎片环 `fx/particles_pool.gd:95-126`（node_added 逐实例订阅 boss_defeated）；✅ **补课**：快进输入接线 `autoload/fx.gd:383-396`（演出链期间连按 fire/touch_fire → skip，非演出期零误触发）；战利品延迟 `autoload/fx.gd:466-481` + `core/rooms/floor_scene.gd:1236-1254`（loot 段/快进补发喷出，链缺席同步照旧） | test_hitstop.gd（链时序/skip 幂等/loot 不吞）；juice_smoke §8（快进）/§9（掉落延迟） | 演出完整性/可跳过实感 → 待 G-1 |

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
| ④ 消费端（运行时读键触发振动） | `Fx.request_vibrate`（`autoload/fx.gd:255-258`）：`get_setting("vibration", true)` 双重门控第一道——**补课后已接**，触发点受击 `on_player_hurt`（fx.gd:291，30ms）/ Boss 死亡 `request_boss_death`（fx.gd:361，80ms） | juice_smoke §7 机检（30/80ms 触发 + 开关关不震） | ✅ 已补课 |
| ⑤ 平台 API | `Input.vibrate_handheld()` 调用点（fx.gd:258）：`vibration_supported()`（fx.gd:248-252）门控第二道——仅 Android 特性在位（或测试注入口）才触达，桌面/无头早退不裸调 | juice_smoke §7（无头 supported=false 断言） | ✅ 已补课 |

**核对结论（补课后更新）**：链路 ①→⑤ 全通——面板开关 → 落盘 → `Fx.request_vibrate` 运行时读键（消费模式同 screen_shake 的消费端读取）→ 平台能力门控 → `Input.vibrate_handheld`。开关关=双触发点均不震（机检 §7）；桌面平台无 Android 特性时不调用振动 API（无害 no-op 也不调，零噪音）；Android 真机振动手感归 G-1（§8 第 9 条）。

---

## 6. 阻塞/缺陷项移交（编排者裁定；本卡零越权改动）

| 编号 | 级别 | 事项 | 证据 |
|---|---|---|---|
| D-1 | ~~缺陷~~ **已补课**（2026-09-01，编排者授权补课批次） | ~~振动无 API 消费端~~ → 已接线：`Fx.request_vibrate` 开关+平台双门控，受击 30ms / Boss 死亡 80ms，时长入 balance juice | 实现位置/规格出处/断言名见 **§0 D-1 行**；调用链核对见 §5 |
| D-2 | ~~缺陷~~ **已补课**（同上） | ~~Boss 死亡链快进无输入接线~~ → 已接线：演出链期间连按攻击键（fire/touch_fire，既有键位）→ `Fx.request_skip`，非演出期零误触发 | 实现位置/规格出处/断言名见 **§0 D-2 行** |
| D-3 | ~~缺陷~~ **已补课**（同上，三项全清） | ①玩家死亡去饱和渐入 → `fx/desat.gdshader` + Fx 推进（真实毫秒 0.4s）；②受击方向指示 → `fx/hit_arc.gd`（8px 弧/0.2s 淡出，无方向不画弧裁定见 §0）；③J7 战利品延迟 300ms → `Fx.defer_boss_loot` 挂起 + loot 段/快进补发 | 三项实现位置/规格出处/断言名见 **§0 D-3a/D-3b/D-3c 行** |
| D-4 | ~~观察项~~ **已补课**（同上） | ~~低血呼吸参数偏差~~ → 已对齐规格字面：alpha 0.15~0.35 / 0.8s 周期（阈值 hp≤2 原本正确） | `ui/hud.gd:16-18/196-209`；断言名见 **§0 D-4 行** |
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
- **补课批次新增（2026-09-01）**：新建 `fx/hit_arc.gd`（+`.uid`）、`fx/desat.gdshader`（+`.uid`）；新增 class_name 后已跑 `godot --headless --import` 重建全局类缓存（fresh checkout 首次需一次 import，标准 Godot 工作流）；`data/balance.json` juice 节追加 `vibration_hurt_ms=30`/`vibration_boss_death_ms=80`（Fx 侧 fail-soft 可选键，导演 15 必需键集不变）。补课提交：`e459cc3`（D-1+D-2）/ 本批次第二个 commit（D-3a/b/c+D-4）。
- 全量单测：`cmd //c "tools\\run_tests.cmd"` → **Overall Summary: 1598 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans，86/86 套件，exit 0**（2026-09-01，总耗时 1min15s；补课批次后复跑同数全绿）。本卡新增文件不进 gdUnit 收集（非 test_* 命名，同 font_render_smoke 惯例），既有用例零适配。
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
5. Boss 死亡定格演出完整性与观感（300ms 定格→白闪→0.3× 慢速 900ms→碎片环/白闪）；**快进已接线（D-3 之外 D-2 已补，commit e459cc3）**：连按攻击键（鼠标左键/触屏开火键）快进验证。
6. J3 粒子观感：火花六元素/暴击金 1.3×/枪口焰 tint/碎片环；超预算降级单帧在实战中是否可接受（不显突兀）。
7. J4 伤害数字观感：暴击弹跳、元素 tick 小号跳字在混战中的可读性。
8. 低血呼吸红晕观感（**D-4 已对齐规格字面 0.15~0.35/0.8s**，确认观感是否满意）。
9. §18.5 第 5 条：Android 真机触屏双摇杆单手完整一层；**振动已接线（D-1 已补，commit e459cc3）**：真机验证受击 30ms/Boss 死亡 80ms 振动体验。
10. 伤害数字 8px / 元素形状 10px 锐利度复核（§6 J-D 裁定维持现状的观感确认）。
