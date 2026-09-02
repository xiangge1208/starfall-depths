# M4 v1 补完与校准 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task-by-task, organized by the Wave table (roadmap §2.1 并行波次规范). Steps use checkbox (`- [ ]`) syntax.

- 日期：2026-09-02
- 前置：M3 门禁（tag `m3` @70dd070，GREEN 附条件）通过后进入执行期。
- 依据：[GDD §6/§14/§16/§19/§20](../specs/2026-08-28-starfall-depths-design.md) + [m2-gate §5 移交清单](../reports/m2-gate.md) + [m3-gate-integration Check 6/8](../reports/m3-gate-integration.md) + [task-33 §6.1/§2.4](../reports/task-33-report.md) + [task-35](../reports/task-35-report.md) + [task-37](../reports/task-37-report.md) + [m3-fix1/fix2 残差记录](../reports/m3-fix1.md)
- 范围裁定（用户 2026-09-02 选项确认）：**v1 补完与校准**——清 M2/M3 两代门禁欠账，不做 Backlog 新内容（宠物/花园/无尽回廊等留 M5+）。

**Goal:** GDD v1 的「全内容」与「可量化节奏目标」两个 §20 验收承诺做实——数据表所有承诺条目有 gameplay 消费端（敌人派味特技 11 项、英雄被动 4 条、增益键 10 个、成就数据源 2 条+1 条 blocked 解锁）、美术 QA 三重校验全管线覆盖、蓝晶经济模拟三点带判定、bot 能力残差清零后全量复跑产出胜率/时长带首次可评数据、TTK 校准窗口就绪（数据触发）——达成 M4 门禁（无 P0/P1、消费端零孤儿、经济带判定入档）。

**Architecture:** 延续 M0~M3 架构，无新 autoload。新增：敌人 archetype 行为段、英雄被动消费端（player/run_root/combat_system 既有缝）、增益祭坛设施（floor_scene 设施缝 + interact 场景）、可破坏物机制（props 伤害入口 + 破坏结算 + 事件）、暴击弹帧（atlas 扩展）、美术 QA 校验脚本、经济模拟工具（tools/）、bot 能力升级（lead/绕障/save 隔离）、版本常量单源。

**Tech Stack:** Godot 4.7.2 / GDScript / GdUnit4 6.2.1（锁定，勿升级）/ Python+Pillow（美术管线，`~/.workbuddy/binaries/python/envs/default` venv）。

## Global Constraints（继承 M0~M3 + M4 增补）

1~9 同 M3 计划（60Hz 逻辑帧；固定伤害暴击唯一随机乘区；RNG 只经 RunState 分盐；数据驱动 schema fail-closed；热路径零分配；合并后先 `--import` 再全量测试[run_tests.cmd 已内置]；TDD + worktree 隔离 + 每波 ≤3 实现者 + 束间文件所有权互不相交；表现判定分离；试炼 mods 单点注入）。

10. **消费端零孤儿（M4 核心约束）**：data 表承诺键在本里程碑结束时必须有 gameplay 消费端，或带裁定编号的豁免注记——验收时全键 grep 审计。
11. **数值修订 ≤±20%**：data/*.json 修订沿用窗口约束；**TTK-R 例外协议**见下文（幅度需用户明示批准）。
12. **新行为必带遥测**：新敌人特技/被动/祭坛/可破坏物均发遥测事件（平衡回归与成就依赖），事件名先查 `Telemetry` 既有清单避免撞名。

## 欠账清单总表（入账 → 卡号）

| # | 欠账 | 来源 | 卡 |
|---|---|---|---|
| 1 | 敌人派味特技 8 项 0/8 + 相邻 3 项未建 | M2-T33 §6.1 | C-1 |
| 2 | 英雄被动 4 条 data-only（spare_parts/echo/blessing/shadow_reap） | M2-T33 + m2-gate §5 | C-2 |
| 3 | 10 个无消费者增益键（rig 5 + 展示 3 + heart_sense + anti_poison） | M2-T35 + m2-gate §5 | C-3 |
| 4 | codex_seen 无写入方（collector/grand_collector 成就事实不可达） | M2-T33 §2.4 | C-3 |
| 5 | 暴击弹专用帧（元素弹帧已随 M2-T27 落地并核对在库；本卡复刻其管线） | M2 审计美术 I 束 | A-1 |
| 6 | 美术 QA 三重校验（对比度/剪影/接缝）仅覆盖 fx+trials，M1/M2 产物零覆盖 | GDD §16.1/§21 | A-2 |
| 7 | 增益祭坛设施不存在 → elite_surge 因子半边悬置 | m3-fix1 §残留 | C-4 |
| 8 | 可破坏物机制不存在 → demolition 成就 BLOCKED | M2-T33 §2.4 | C-5 |
| 9 | hero_select 6 卡行超界豁免（1316px vs 480px 设计宽） | S-C m3-font-walkthrough | K-2 |
| 10 | 游戏内版本读点缺失 | X-C 移交 | K-1 |
| 11 | import_etc2_astc 未正式化（导出脚本临时写入） | X-A/X-C 移交 | K-1 |
| 12 | LOGO/icon.svg 仍 Godot 默认（程序化图标已入 preset，未定稿） | X-C 移交 | K-1 |
| 13 | A2 光圈内伤害数字/FX 粒子无增亮 | M2-T37 披露 | K-3 |
| 14 | bot 能力残差（无 lead 预判/无绕障/shooter 不贴近）4+2 例 | m3-fix2 §3/§6 | B-3 |
| 15 | save 并行竞态（save_headless.json 多实例串写） | B-1/fix1 披露 | B-3 |
| 16 | 蓝晶经济模拟（门禁操作化明文要求，零执行） | M2 审计 + GDD §14.3 | B-4 |
| 17 | 胜率/单层/单局三带 bot 不可评 → bot 过层能力 | M3-B2 终判 | B-3/B-4 |
| 18 | A1 TTK 4.5s 出带 2.25×（超窗，真人数据优先） | M3-B1/B-2 | TTK-R 协议 |
| 19 | Android 真机 60fps + 触屏全流程；核显笔记本真测；节流窗 60fps 静默会话复测（X-B 三项移交） | M3 附条件 | 用户侧（有设备/环境时） |

## 执行期波次总表（依赖 tag `m3`；每波 ≤3 实现者，束间文件所有权互不相交）

| 波 | 卡 | 一句话 | 依赖 | 文件所有权 |
|---|---|---|---|---|
| W1 | C-1 | 敌人派味特技 ×8+3（archetype 行为段 + 遥测 + 单测） | m3 | `core/enemies/**`, `core/combat/projectile.gd`, `core/rooms/`(zone/生怪钩), `data/enemies.json`(+schema), `tests/unit/` |
| W1 | C-2 | 英雄被动 ×4（echo/blessing/spare_parts/shadow_reap 消费端） | m3 | `core/player/**`, `core/combat/combat_system.gd`, `core/rooms/run_root.gd`, `core/summons/**`, `tests/unit/` |
| W1 | A-2 | 美术 QA 三重校验全管线（对比度/剪影/接缝 + M1/M2 产物纳入 + 测试化） | m3 | `tools/`(新校验脚本+gen_*.py 接线), `tests/unit/test_art_pipeline*` |
| W2 | C-3 | 增益消费端 ×10 键 + codex_seen 写入方（成就权威口径切换） | C-2(combat_system 先并) | `core/combat/**`, `core/enemies/**`(telegraph), `core/rooms/`(掉落), `core/player/player.gd`, `core/meta/codex_system.gd`, 获取点(shop/forge/初始), `tests/unit/` |
| W2 | A-1 | 暴击弹专用帧（生成 + ArtLookup crit 参数 + 消费端 + A-2 校验纳入） | A-2 | `tools/gen_*.py`, `core/art/art_lookup.gd`, `core/rooms/room_combat.gd`, `tests/unit/` |
| W2 | K-3 | A2 光圈增亮折叠（伤害数字/FX 粒子 self_modulate + draw 预算复测） | m3 | `autoload/fx.gd`, `fx/particles_pool.gd`, `tests/`(含 perf 复测) |
| W3 | C-4 | 增益祭坛设施 + elite_surge 试炼分支（因子半边收口） | m3 | `core/rooms/floor_scene.gd`(设施缝), `core/rooms/interact/`(新), `core/meta/trial_mods.gd`(读点), `tests/unit/` |
| W3 | K-1 | 版本读点单源 + etc2 正式化 + LOGO 变体 ×3 供选 | m3 | `ui/settings_panel.gd`, `project.godot`([rendering]/[gui]), `tools/export_android.cmd`(删临时段), `tools/gen_icon.py`(变体), `tests/unit/` |
| W3 | K-2 | hero_select 布局重排（分页/缩卡）+ 撤 S-C 豁免 | m3 | `ui/hero_select.gd(+.tscn)`, `tests/scenes/font_render_smoke.gd` |
| W4 | C-5 | 可破坏物机制 + demolition 成就接线 | m3 | `core/rooms/**`(props 伤害入口/破坏结算), `core/meta/achievement_system.gd`(1 行), `fx/`(破坏表现), `tests/unit/` |
| W4 | B-3 | bot 能力（lead 预判/shooter 贴近/绕障初版）+ save 并行隔离 | m3 | `tools/balance_bot*.gd`, `autoload/save_system.gd`(路径注入缝), `core/player/auto_aim.gd`(lead 可选参数,默认关), `tests/unit/` |
| W5 | B-4 | 经济模拟（三点带判定）+ bot 100 局全量复跑（残差率+过层数据） | B-3, C-1~C-5(内容全上) | `tools/`(economy_sim 新), `docs/superpowers/reports/m4-*.md/json`, `data/*.json`(仅窗口内修订) |
| W6 | G-1 | **M4 门禁**：全量绿 + 消费端零孤儿审计 + 经济带判定 + 集成守卫 + tag `m4` | 全部 | `docs/superpowers/reports/m4-gate-*.md` |

> 计 13 卡 = C×5 / A×2 / K×3 / B×2 / G×1。TTK-R 为数据触发协议卡（非排期）；Android 真机/核显本/静默会话复测与 LOGO 定稿为用户侧动作项。

## 不在 M4 范围的已记录偏差（防静默丢失，均有出处）

| 偏差 | 出处 | 处置 |
|---|---|---|
| 敌 AI 相位非确定性（同种子结局有分布漂移，跨批对比只有分布意义） | fix1/B-2 披露 | 记录为已知偏差，M4 不修（RNG 穿透 AI 相位属深改，收益限 bot 回归精度） |
| AudioMgr 自有 float 音量键与面板 int 键双轨 | settings_panel.gd 头注已声明 | 已声明实现细节，不判双源冲突 |
| A2 光圈为折叠口径非真实光照（K-3 修复后覆盖弹幕+预警纹+伤害数字+粒子，仍非全场景光照） | T37/fix1 探针矩阵（真实光照 +47 draw 被否决） | 设计取舍入档，等真机观感反馈再议 |
| save 竞态仅存在于 headless 并行多进程（单进程产品路径无竞态） | B-1/fix1 披露 | B-3 以 per-process 隔离解决 bot 侧；产品侧无需动作 |
| bot 与真人能力差（瞄准/走位/无成长学习） | B-2 终判 | 结构性：胜率/手感带以真人数据为权威（TTK-R 与用户自测清单承载） |

---

### Task C-1: 敌人派味特技 ×8+3

**Files:** `core/enemies/archetypes/*`（行为段）、`core/combat/projectile.gd`（抛物线参数）、`core/rooms/`（水洼 zone/落地生怪/拉拽钩子）、`data/enemies.json`（行为参数键 + `tools/` schema 同步）、`tests/unit/test_signature_moves.gd`（新）
**规格:** 规格源=task-33 §6.1 表 + task-9 原表（:77-91），逐条实现：`hardshell_turtle` 龟缩（缩壳免疫态，正面减伤 0.8 已存在、其上叠加）、`thorn_turret` 抛物线弹（projectile 重力/弧线参数）、`moss_slime` 水洼提速（zone 生成与增益）、`seed_pitcher` 落地生怪（弹着点 30% 生苗，表参数）、`magnet_golem` 拉拽（对玩家位移力）、`frost_crab` 钳击（预警扇区横扫+高伤）、`crystal_rat` 偷币（接触窃取金币+逃跑）、`echo_lurker` 模仿武器（复制玩家武器弹形）。相邻 3 项（幽光水母电弧链/熔岩犬两段咬/火雨祭司火雨区，task-33 尾注）一并实现；确属超范围者经编排者裁定豁免并记录。每项带遥测事件 + 单测；行为参数 data 驱动（schema fail-closed）；弹幕走既有预算/预警规范（§7.5）。task-33 定性提醒：属敌型风味打磨、非门禁链路依赖——**不得破坏房间可清不变量**（bot 冒烟验证）。
- [ ] 验收：11 项行为可玩可测（或豁免裁定入档）+ 全量绿 + bot 冒烟 10 局无新停滞（新行为不卡死房间可清不变量）。
- [ ] Commit `feat(m4-c1): enemy signature mechanics ×11`

### Task C-2: 英雄被动 ×4

**Files:** `core/combat/combat_system.gd`（echo 伤害 roll）、`core/rooms/run_root.gd`（blessing 层入口/spare_parts 换层）、`core/summons/turret.gd`（spare_parts 补台，cap=heroes.summon_cap）、`core/player/melee.gd`+`core/player/player.gd`（shadow_reap 近战击杀返蓝+翻滚 CD 门控）、`tests/unit/test_hero_passives.gd`（新）
**规格:** GDD §6 表逐字：**echo**（法师·烬）法杖/激光类（weapons.json category）伤害 +15%；**blessing**（守护者·萄）每进入新层回满护盾 + 5% 全伤害单局叠至 4 层；**spare_parts**（工程师·铆）开局带 1 台便携炮台（存活 12s/DPS 15）+ 每层补 1 台，**与主动技能共用库存上限 2**（GDD 明文，超限不补或替换最旧按 summons 既有语义）；**shadow_reap**（刺客·蝉）近战击杀返 5 蓝 + 下 1s 翻滚无 CD。先例参照：defiance（player.gd:66,397-411）、hawk_eye（ranger_shadowstep.gd:43-81 EventBus 监听模式）。每被动单测钉死数值与触发边界；`tests/unit/test_heroes.gd:65-106` 数据钉不可回退。
- [ ] 验收：4 被动真人可感（bot 冒烟含 4 英雄各 ≥2 局无异常）+ 全量绿。
- [ ] Commit `feat(m4-c2): hero passives ×4 live`

### Task C-3: 增益消费端 ×10 键 + codex_seen 写入方

**Files:** `core/combat/combat_system.gd`（rig 5 键伤害/复仇 roll）、`core/combat/resonance.gd`（共振半径/时长）、`core/enemies/archetypes/*`（展示 3 键：telegraph 强化/高亮描边）、`core/rooms/`掉落侧（heart_sense 红心掉率）、`core/player/player.gd`（anti_poison 毒免疫，仿 anti_ice:317 模式）、`core/meta/codex_system.gd` + 获取点（codex_seen 写入：默认池首取 ∪ 掉落/商店/熔铸/任务解锁）、`tests/unit/`（扩展）
**规格:** buff_manager.gd:184-186「消费方待接线」注记清账，**10 键全列**（buff_id → meta 键映射在 buffs.json 行）：rig 5 = `dmg_vs_statused_pct`（hunter，对异常状态敌伤害%）、`resonance_radius_pct` + `resonance_duration_ticks`（resonance_amp 共振半径/时长）、`vengeance_pct` + `vengeance_ticks`（avenger 受击后复仇）；展示 3 = `element_vision`、`telegraph_bonus_ticks`、`resonance_vision`（按行 desc 落地预警纹/元素标记/共振范围提示）；`heart_sense_pct`（红心掉率 roll，掉落侧）；`anti_poison`（毒免疫，仿 player.gd:317 anti_ice 模式）。codex_seen 写入方落地后 collector/grand_collector 成就自动切权威口径（achievement_system.gd:405-413 回落逻辑不删，验证切换，写入集=默认池首取 ∪ 掉落/商店/熔铸/任务解锁）；两成就达成路径单测（模拟 50/115 见集）。
- [ ] 验收：10 键 grep 消费端齐 + codex_seen 写入方 + 两成就可达性单测 + 全量绿。
- [ ] Commit `feat(m4-c3): buff consumers ×10 + codex_seen writer`

### Task C-4: 增益祭坛设施 + elite_surge 分支

**Files:** `core/rooms/floor_scene.gd`（设施缝：`_open_facility`/SCENE 常量扩展）、`core/rooms/interact/`(新祭坛场景)、`core/meta/trial_mods.gd`（elite_surge 读点）、`data/`（祭坛权重/池，schema 同步）、`tests/unit/`
**规格:** m3-fix1 §残留口径：战斗房 15% 概率生成增益祭坛（交互三选一增益或代价换增益，数值从 buffs.json 既有池取，禁止新数值键优先）；非试炼局=纯增益设施；试炼局 elite_surge 因子激活时祭坛分支改为「追加 1 精英」（读 TrialMods 单点，禁止散读 trials.json），遥测 `trial_elite_bonus` 既有事件复用。祭坛与雕像/喷泉的房内设施互斥规则入 schema。
- [ ] 验收：祭坛可交互可测 + elite_surge 两半边齐（精英房 ×2 已有 + 祭坛分支新）+ 全量绿 + bot 冒烟含试炼局祭坛分支。
- [ ] Commit `feat(m4-c4): buff altar facility + elite_surge trial branch`

### Task C-5: 可破坏物机制 + demolition 成就

**Files:** `core/rooms/`（props 伤害入口/破坏结算/掉落）、`core/meta/achievement_system.gd`（1 行 notify）、`fx/`（破坏表现，走粒子预算）、`tests/unit/`
**规格:** task-33 §2.4：props（pillar/crate/bush）从静态阻挡升级为可破坏——伤害入口接 combat_system 判定流（固定伤害制）、HP 入 data、破坏结算（阻挡消失 + 小额掉落/无掉落按行）+ `notify_prop_destroyed()` 遥测；demolition 成就（拆迁办，gems 50）1 行接线激活。Boss 战蜂巢柱（可破坏掩体）既有特例不回归。可破坏物不进弹幕预算（独立池小上限）。成就计数口径：M2 末 21/22 非试炼激活（demolition blocked）+ M3 试炼 2 条 = 现 23/24，本卡后 **24/24**。
- [ ] 验收：demolition 成就 24/24 全激活口径达成（22+1 试炼 2 已在 M3 活 → 本卡后全活）+ 全量绿 + perf 抽验 draw 无回归。
- [ ] Commit `feat(m4-c5): destructible props + demolition achievement`

### Task A-1: 暴击弹专用帧

**Files:** `tools/gen_placeholder_art*.py`（crit 变体生成）、`core/art/art_lookup.gd`（projectile_texture_path crit 参数）、`core/rooms/room_combat.gd`（_sync_bullet_visuals 消费）、`tests/unit/test_art_lookup.gd`（追加）
**规格:** M2-T27 元素弹帧（`save_elem_bullet`，gen_placeholder_art.py 弹丸节）先例复刻：暴击弹专用帧（金色描边/强化发光变体，玩家+敌弹两套）；优先走 `gen_projectiles_scoped()` 窄通道再生（不触发全量 main，prune 风险隔离；A-2 已在前波落地 keep 集修复则不受限）；消费端 `room_combat.gd:535-549 _sync_bullet_visuals` 在既有暴击判定点切换纹理（暴击 roll 已是唯一随机乘区，纹理切换零判定影响）；A-2 校验管线自动纳入新帧。
- [ ] 验收：暴击弹可视可辨（暴击时弹体变体切换）+ 校验过 + 全量绿。
- [ ] Commit `feat(m4-a1): crit bullet frames`

### Task A-2: 美术 QA 三重校验全管线

**Files:** `tools/`(新 `art_qa_check.py` 或扩展 spritegen_m3)、`tools/gen_placeholder_art.py`/`gen_placeholder_art_m2.py`（校验接线）、`tests/unit/test_art_pipeline.gd`（扩展）
**规格:** **前置必修（P0，2026-08-31 prelude 审查遗留、从未落卡）**：`gen_placeholder_art.py` `_prune_stale()`（:1838-1857）keep 集仅含 M1 SPEC + MANIFEST/preview/.gitkeep——全量跑 M1 管线会**静默删除 M3/M4 资产子树**（`art/generated/fx/`、`trials/`、`icon/`）。先扩展 prune 豁免非本管线子树（或 keep 集纳入），配回归测试（dry-run prune 清单断言三子树零删除），此后全量 main() 方可解禁（裁定⑪保留至本项落地）。主体：GDD §16.1/§21 + roadmap 口径三重校验——对比度（前景/背景亮度差 ≥30）、剪影（30% 亮度轮廓可辨，IoU ≥0.85）、接缝（瓦片/walk 帧序列邻接连续性——spritegen_m3 现有帧序列项对齐 roadmap「接缝」命名）；覆盖面从 fx+trials 扩到**全部 art/generated/**（M1/M2 产物：瓦片/角色/敌人/弹幕/UI）；失败 fail-closed（生成管线退出码）；测试化（test_art_pipeline 挂 venv python）。存量产物先跑基线，超阈值项列清单交编排者裁定（修资产或调阈值，不许静默放过）。
- [ ] 验收：全量产物三重校验 PASS（或超阈清单有裁定）+ 测试化 + 全量绿。
- [ ] Commit `feat(m4-a2): art QA triple-check pipeline`

### Task K-1: 版本读点 + etc2 正式化 + LOGO 变体

**Files:** `ui/settings_panel.gd`（底部版本行）、`project.godot`（[rendering] 增 `textures/vram_compression/import_etc2_astc=true` + 版本常量单源方案）、`tools/export_android.cmd`（删临时写入段，保留漂移自证）、`tools/gen_icon.py`（变体 ×2 新方向）、`tests/unit/`
**规格:** ①版本读点：设置面板底部一行 `v1.0.0 (100)`，单源常量（autoload 或 ProjectSettings 定制键），与 export_presets 三处值一致性强测试（读 preset 文件比对或常量双向断言）；②etc2 正式化后**全量重导入 + Windows 导出复跑**确认无视觉/性能回归（draw 抽验）；③LOGO：gen_icon.py 在现「星空石门」外出 2 个新方向变体（预览页 PNG 并排），交用户定稿——本卡只交变体，替换 icon.svg/config 是用户选定后的 5 分钟跟进（不阻塞）。
- [ ] 验收：版本读点 + 强一致测试 + etc2 正式化且导出双 PASS + 变体预览页产出 + 全量绿。
- [ ] Commit `feat(m4-k1): version read point + etc2 formalized + logo variants`

### Task K-2: hero_select 布局重排

**Files:** `ui/hero_select.gd(+.tscn)`、`tests/scenes/font_render_smoke.gd`（撤豁免）
**规格:** S-C 豁免清账：6 卡 1316px vs 480px 设计宽——三选一（分页翻页/横滚/缩卡网格）由实现者按触屏可用性定，验收=全部卡在视口内且可聚焦（keyboard/gamepad 导航序完整）；font_render_smoke 撤 waive（Cards 子树视口断言恢复全量）。
- [ ] 验收：豁免撤销 + 冒烟全绿 + 全量绿。
- [ ] Commit `fix(m4-k2): hero select layout fits viewport`

### Task K-3: A2 光圈增亮折叠

**Files:** `autoload/fx.gd`（spawn_damage_number 走 BiomeFx.bullet_aid 同形 self_modulate 折叠）、`fx/particles_pool.gd`（同）、`tests/`（含 F2 draw 复测）
**规格:** T37 披露收口：伤害数字/FX 粒子在 A2 光圈内增亮——走弹幕已验证的 self_modulate 折叠路线（零批处理成本，task-37 探针矩阵为证），**不走**真实光照参与集（+47 draw 已被否决）。F2 满压 draw 复测 ≤150 预算（perf_probe 既有档）。
- [ ] 验收：A2 视觉一致（光圈内伤害数字/粒子增亮）+ draw 复测入预算 + 全量绿。
- [ ] Commit `feat(m4-k3): a2 light fold for damage numbers + fx`

### Task B-3: bot 能力 + save 并行隔离

**Files:** `tools/balance_bot.gd`/`balance_bot_decisions.gd`（lead 预判 nudge/shooter 接近带/实体柱绕障斥力）、`core/player/auto_aim.gd`（lead 可选参数，**默认关**=生产零漂移）、`autoload/save_system.gd`（save_path 注入缝 + bot `--save-suffix` per-process 隔离）、`tests/unit/`
**规格:** m3-fix2 §3 三可修点：①弹道 lead（bot 侧 `_nudge_aim_if_unlocked` 扩展速度×飞行时间预判；auto_aim 生产参数默认关+单测钉默认行为逐字节不变）；②shooter 类（弩兵等）纳入接近带（风筝残差主因）；③走位绕障初版（实体柱/props 斥力场，fix2 3271-a3 Seek 楔死柱面实证）。save 隔离：并行实例各写 `save_headless_<suffix>.json`，消除图鉴/成就/首杀跨进程竞态。验收=fix2 的 11+2 残差种子复跑残差率显著下降（目标 ≤1/31）+ 100 局不回归。
- [ ] 验收：残差复跑达标 + save 并行隔离（双实例同跑无串写断言）+ 全量绿。
- [ ] Commit `feat(m4-b3): bot capability + save isolation`

### Task B-4: 经济模拟 + bot 全量复跑

**Files:** `tools/economy_sim.py`（新，读 balance JSON gems_curve + SaveSystem 价格表）、`docs/superpowers/reports/m4-economy.md`、`docs/superpowers/reports/m4-balance-rerun.md/json`
**规格:** ①经济模拟（GDD §14.3 三点带判定）——**模型策略防虚假精度**：产出侧以 §14.1 规则解析模型为主（层通过 60/120/200、Boss 首杀 300、成就 50~500、试炼 ×1.5、死亡保留 50%），bot 局 `gems_curve` 数据为辅校准；**过层率参数必须扫参**（当前 bot 89/100 死于 F1、F1 gems 多为 0——bot 直接实测层通过收入不可行，过层能力依赖 B-3 结果），对过层分布做敏感性区间（乐观/悲观/目标 §14.3 胜率曲线三档），三点判定（2~3h 解锁第 1 角色 / 10h 天赋树 60% / 20h 图鉴 80%）按区间结论汇报而非单点；消费侧=价格表实值（角色 2000/2000/5000/5000/8000、强化 1500/名、天赋/图鉴成本从 SaveSystem/GameDB 读）。出带→修订窗口内调产出/价格（≤±20%）或记录超限意向。②bot 100 局全量复跑（种子 3401..3500）：残差率终验 + bot 过层能力数据（若可达 F2/F3 → 单层/单局时长带首次 bot 可评；不可达则记录能力边界，时长带维持用户自测口径）。
- [ ] 验收：经济三点带判定表（带内/出带+修订台账）+ 100 局复跑报告 + 全量绿。
- [ ] Commit `feat(m4-b4): economy sim + balance rerun`

### TTK-R 协议（数据触发，非排期）

M3-B1/B-2 实证 A1 TTK 4.5s vs ≤2.0s（出带 2.25×），回带需武器输出 ≈+125% 或 A1 杂兵 HP ≈-56%，均超 ±20% 窗口。按 M2 裁定㉝「真人数据优先」：**用户自测反馈到达后**，编排者汇总（自测清单 ① 的 TTK 体感 + 死因分布）→ 向用户提交修订方案（幅度/影响面/bot 前后对照计划）→ 用户明示批准幅度 → 立 TTK-R 卡执行（修订 + bot 100 局前后对照 + 全量绿 + 报告）。用户反馈未到前不动数值。

### Task G-1: M4 门禁

**Files:** `docs/superpowers/reports/m4-gate-integration.md`（+ 用户自测增补清单节）
**规格:** 集成守卫：全量测试绿 + 消费端零孤儿审计（data/*.json 全键 grep 消费端，豁免必须带裁定编号）+ 9000 种子地牢校验 + §18.3 抽验对照 + 存档 v2 往返 + 经济模拟带判定入档 + bot 复跑结论 + 成就 24/24 激活口径 + 工作树干净。用户侧条件项盘点（Android 真机/LOGO 定稿/TTK-R 状态/时长带数据状态）。编排者裁定：无 P0/P1 + 消费端零孤儿 + 经济带判定（或超限有裁定）→ GREEN 则 tag `m4`。
- [ ] 验收：上述全绿 + tag。
- [ ] Commit `feat(m4-gate): integration guard + verdict`
