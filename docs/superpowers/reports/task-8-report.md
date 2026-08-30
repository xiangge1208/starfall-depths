# Task 8 评审报告：B-1 召唤物框架 + 工程师（m2-t8）

- **被审对象**：`.worktrees/m2-t8`（分支 m2-t8，单 commit eb4fba1 `feat(m2-t8): summon framework + engineer turret`，基线 b633ed6）
- **评审范围**：`git diff b633ed6..HEAD`（7 个实质文件 +4 个 `.uid`，+579/−6 行）
- **评审日期**：2026-08-30
- **评审人**：独立评审 agent（只读评审，未改动任何生产代码，本报告文件除外）
- **验证环境**：Godot 4.7.2.stable.official.ed1daf0bf / GdUnit4 6.2.1（与门禁锁定一致）

## 结论：Approved-with-notes

核心规格全部落地：SummonBase 框架（setup/存活计时/combat 与 player 注入/统一退场+遥测）、工程师炮台三参数（12s/2/s/伤 4）与升级导弹（每 3s、12 AoE）、heroes.json 工程师行与 GDD §6 逐值一致、选角 UI 经 GameDB 驱动自动扩展、TDD 四项全覆盖。实测 **756/756 全绿**（49 套件，0 errors/0 failures/0 orphans），与实现者自报一致。热路径合规（非节拍帧零分配零字符串）、despawn 幂等且守卫完备、弹走房间 CombatSystem 同通路不另起 RNG。

无 Blocker、无 Major。7 项 Minor 中最重要的是实现者自报的**跨房间残留边界**——经FloorFlow 门规则复核，实际严重度为**低**（战斗房未清前两门皆锁，玩家离开旧房时旧房必已清空，残余火力无可命中目标；残余仅为 ≤12s 的视觉滞留与旧房 combat 注册占用）。建议随 T22/T25（两卡均改 `floor_scene.gd`）以约 3 行在 `_wire_room_combat` 的 ShieldSpirit 重接循环处顺带收口，不阻塞本卡合入。

## 数值出处核对（含勘误）

- 评审指令所引"数据表附录 D（英雄表）"**有误**：`2026-08-28-starfall-depths-data-tables.md` 附录 D 是熔铸固定配方，全文件无英雄表。英雄数值唯一出处为 **GDD（design 文档）§6 角色系统**（`2026-08-28-starfall-depths-design.md:87-111`）。本报告按 GDD §6 核对。
- 工程师面板：HP 7/盾 5/蓝 120/速 78/初始铆钉枪（`maodingqiang`，weapons.json 首行存在，白品手枪）——`data/heroes.json` engineer 行逐值一致。
- 主动技：CD 12s（720t）= GDD §6；0 耗蓝 = GDD（§6 未标耗蓝，同骑士/游侠先例）；库存上限 2 = GDD §6「与被动共用库存上限 2」。
- 强化：每 3s 一发导弹 12 AoE = GDD §6 强化列逐值一致。
- **规格矛盾裁定执行核查**：计划卡「射速 2/s 伤 4」（=8 DPS）vs GDD §6 被动列「DPS 15」——编排者已裁定以计划卡为准、列入 T28 平衡校准点。实现按 `FIRE_INTERVAL_TICKS := 30` + `SHOT_DAMAGE := 4`（`core/summons/turret.gd:29-30`）落地，**符合裁定**。
- 无出处议定值（弹速 180/弹寿命 1.5s/导弹 AoE 半径 48/炮台 HP 10/半径 7）已在文件头注释逐项披露并标 T28 校准点——符合 Global Constraint 3 的"矛盾上报"精神，可接受。

## 规格符合度逐项核对

| # | 规格项 | 判定 | 证据 |
|---|---|---|---|
| 1 | SummonBase `setup(row)` 数值行注入 | **PASS** | `core/summons/summon_base.gd:32-37`（id/hp/lifetime_ticks，缺省保子类默认，同 EnemyBase.setup 习语） |
| 2 | 生命/存活计时 | **PASS** | hp/take_hit（:59-66）；`begin(frame)` 起算 + `tick` 先判超时再交 `_tick_ai`（:46-57）；719/720 边界有直测 |
| 3 | RunState 玩家引用注入 | PASS（措辞偏差，见 Minor⑦） | 计划卡原文"索敌用 RunState 玩家引用注入"；RunState 无 player 字段（grep 证实），实现改为技能侧注入 `turret.player = player`（`core/player/skills/turret.gd:68`），同 ShieldSpirit 接缝习语 |
| 4 | combat 注入 | **PASS** | `turret.combat = player.combat`（skills/turret.gd:67）——RoomCombat/FloorScene 均按房间注入该引用（room_combat.gd:300 / floor_scene.gd:474），duck-typed 同 ShieldSpirit |
| 5 | 挂 RoomCombat 的 combat 引用 | **PASS** | 同上；测试断言 `turret.combat is_same(cs)` 且炮台已登记为玩家阵营战斗体（敌弹可命中） |
| 6 | 死亡/超时 queue_free + 统计 | **PASS** | `despawn(reason)` 幂等统一退场：注销战斗体→`despawned` 信号→`Telemetry.log_row(["summon_end",…])`→`queue_free`（summon_base.gd:76-85）；三种 reason（expired/destroyed/replaced）均有直测 |
| 7 | 索敌 240px 最近敌人，复用 AutoAim.pick_target | **PASS** | `RANGE_PX := 240.0` + `_acquire_target` 距离预滤后调 `AutoAim.pick_target(pos, 0.0, candidates, 360.0)`（core/summons/turret.gd:77-94）；越界不开火有直测 |
| 8 | 炮台 12s 存活 | **PASS** | `LIFETIME_TICKS := 720`（:24）；测试断言 719t 存活、720t queue_free |
| 9 | 射速 2/s | **PASS** | `FIRE_INTERVAL_TICKS := 30`；cadence 测试断言 30t 第 1 发、29t 未发、60t 第 2 发 |
| 10 | 伤 4 | **PASS** | `SHOT_DAMAGE := 4`；测试断言弹体 damage==4（=8 DPS，符合编排者对计划卡 vs GDD"DPS 15"矛盾的裁定） |
| 11 | 升级版 +3s 导弹 | **PASS** | `MISSILE_INTERVAL_TICKS := 180`、`MISSILE_DAMAGE := 12`（每 3s 追加，GDD §6 强化列口径）；AoE 内/外差分断言；非升级版永无导弹有直测。注：导弹为"以当前目标为爆心的即时 AoE 直击"（无飞行体），数值符合、形态为实现裁量已注释披露 |
| 12 | heroes.json engineer 行全字段 | **PASS** | hp7/盾5/蓝120/速78.0/crit 0.05/初始[maodingqiang]/skill_script turret.gd/skill_cd 720/skill_energy 0/passive spare_parts/skill_name 自动炮台/**summon_cap 2**——逐键有 `test_engineer_row_values` 断言；16 必填键齐（键外第 17 键 summon_cap 见 Minor③） |
| 13 | hero_select 自动扩展 | **PASS** | 卡片列表 `_ids = GameDB.heroes.keys()`（hero_select.gd:30）天然扩展，`test_hero_select_scene_builds_three_cards` 验证 3 卡零列表代码改动；实际 1 行改动是 PASSIVES 文案表补 `spare_parts` 描述（:20，展示层归 UI 的既有架构），合理最小改动 |
| 14 | TDD 四项 | **PASS** | 部署（生产 HeroApplier 换装端到端 + 接线断言）/索敌开火（注入帧，方向 dot≈1）/超时自毁（719/720 边界）/上限 2（第三次施放顶替最旧，reason=="replaced"）——`tests/unit/test_summons.gd` 12 用例 + `test_heroes.gd` 2→3 行计数更新 |
| 15 | Commit 规范 | **PASS** | `feat(m2-t8): summon framework + engineer turret`，带卡号；新 `.gd` 全附 `.uid`（Global Constraint 收尾要求）；工作区 clean |

## 质量发现

### Blocker（无）

### Major（无）

### Minor

1. **跨房间残留边界**（实现者自报，评估为低严重度）。`core/player/skills/turret.gd:60-73`：炮台挂 `player.get_parent()`——FloorScene 生产路径下即楼层根，非房间节点。换房后炮台最长 12s 停留旧位、`combat` 仍指旧房 CombatSystem、且仍注册在旧房 `_bodies`/空间哈希中。**实际影响复核**：(a) 战斗房进房锁门、清完开门，且 FloorFlow 规则门对两未清房间上锁（floor_scene.gd:924-927）→ 玩家可离开旧房时旧房必已清空，**残余火力无可命中目标**；(b) 旧房弹池本就不被 `_sync_bullet_visuals` 镜像（仅当前房），无视觉串扰；(c) 残余物为旧位色块 ≤12s（相机已随玩家走）与旧房 combat 的 12s 注册占用（despawn 时注销，无泄漏）。**收口必要性**：建议但非必须——T22/T25 均改 `floor_scene.gd`，在 `_wire_room_combat`（:477-479）既有 ShieldSpirit 重接循环处为 "summons" 组补同款 combat 重接（或进房退场旧召唤物），约 3 行。
2. **非战斗房施放退化**（既有接缝继承，非本卡引入）。`floor_scene.gd:463-464` 对 `room.combat == null` 早退，商店/事件/起始房进房后 `player.combat` 残留上一战斗房 → 在此类房间施放会把炮台注册进旧房 combat（打不出任何有效输出，白付 12s CD）。与 Minor① 同点收口（顺带在 `_deploy` 可加"player.combat 所属房间 == 玩家所在房间"守卫或直接允许部署为哑炮）。当前无崩溃路径（null/失效引用均有守卫）。
3. **summon_cap 键外直通，无 schema 校验**。`HERO_SCHEMA` 16 键（autoload/game_db.gd:51-59），`validate_row`（:170-177）只查缺失+类型、不拒键外键 → `summon_cap` 拼写错误静默回退 `DEFAULT_SUMMON_CAP=2`（当前缺省值与数据值相同，零实际影响）；但类型错误可静默劣化（如字符串 `"两"` 经 `int()` → 0 → `maxi(1,…)` = 1，上限悄悄变 1）。建议 T11/T13 增加更多英雄时将 `summon_cap` 注册进 `HERO_OPTIONAL` 或 validate_hero_row 白名单（含类型/下界校验）。注：`_deep_int_restore` 已保证整数字面量到达时为 int（game_db.gd:231-234）。
4. **被动 spare_parts 无承接卡**。`data/heroes.json` passive_id 与 `ui/hero_select.gd:20` 文案（"开局带 1 台便携炮台……每层补 1 台"）已先行落地，T8 卡明示"本卡不实现"，但 34 卡计划中 T11/T13 亦未列实现——M2 交付面存在"UI 承诺未兑现"风险。建议记入 T33 门禁预检闭环清单（或补微卡）。
5. **层切换/场景销毁时召唤物无 summon_end 遥测行**。炮台随 FloorScene 整树释放，不经 `despawn()` → 遥测少计（仅统计口径，无内存泄漏——树释放连带回收）。可在层退场处遍历 "summons" 组 `despawn("floor_end")`，与 Minor① 同点处理。
6. **despawn 遥测帧口径**：`summon_base.gd:83` 用 `Engine.get_physics_frames()` 而非注入帧——生产侧两者同源无影响；注入帧测试下 CSV 行帧号与逻辑帧口径不一致。纯观测备注。
7. **计划卡措辞与实现的 两处 谅解偏差**（均已注释披露）：(a) "RunState 玩家引用注入"——RunState 无该字段，改为技能侧注入，SummonBase 保留 `player` 接缝给后续召唤物（T11 法师/守护者）；(b) 索敌距离以**炮台自身**为圆心（而非玩家）——对固定炮台是更合理的读法，且 240px 契约值逐字落地。

### 正面确认（质量维度）

- **热路径**：`_tick_ai` 非节拍帧两次布尔比较即返回（core/summons/turret.gd:61-66），稳态每物理帧零分配零字符串；组扫描（`get_nodes_in_group("enemies")`，全楼共享组）仅在 2/s + 3s 节拍发生，开火 Dictionary 字面量与 EnemyBase.fire_bullet/武器 rig 既有习语一致（Global Constraint 5 字面与精神均合规）。
- **守卫完备**：`combat` 三处消费均 `null + is_instance_valid`（+despawn 处 `has_method`）双守卫；`_despawned` 幂等门；`take_hit` 不可复活；`living_summons` 剔除已退场/已排队删除实例。房间释放后炮台静默失效等待超时清理——与 ShieldSpirit 同款接缝哲学。
- **不另起 RNG**（Global Constraint 2）：直射弹经 `combat.spawn_projectile` 走房间 CombatSystem 的 proj_crit 盐流（暴击/元素/共鸣照常结算）；导弹直击 `is_crit: false` 不消费随机——同毒火云/跳电习语。
- **上限语义正确**：`_retire_over_cap` 以全局 "summons" 组（跨技能/被动共享）树序 FIFO 顶替，与 GDD"与被动共用库存上限 2"一致；`maxi(1,…)` 下限防 0 上限语义退化，注释明示。
- **满编顶替而非拒施放**的选择（新炮台照常部署、最旧退场）自洽且已直测。
- **测试质量**：12 用例断言真实（弹方向 dot≈1、AoE 内外 hp 差分 18/30、29t/30t 节拍边界、CD 门、组注销验证）；含 1 条生产换装端到端路径（player.tscn + HeroApplier.apply + skill_cd/meta 时序）；夹具 `auto_free` + root 子树回收，实测 **0 orphans**；注入帧风格与 test_skills 既有惯例一致（测试体内物理帧不前进，无自驱干扰）。
- **文件所有权**：全部改动落在卡内独占文件 + 数据一致性测试（test_heroes.gd 的 2→3 更新系 Global Constraint 8"改 data/*.json 的卡须附分布/一致性测试"的合规要求）；hero_select.gd 仅 1 行文案。

## 测试实测计数

在 `.worktrees/m2-t8` 独立执行（非转抄实现者数据）：

```
godot --headless --path . --import                          → 退出码 0
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
      -a res://tests --ignoreHeadlessMode
```

| 指标 | 实测值 |
|---|---|
| 测试套件 | 49/49 执行 |
| 测试用例 | **756/756 通过** |
| errors / failures / flaky / skipped | 0 / 0 / 0 / 0 |
| orphans | 0 |
| 总耗时 | 2min 50.5s |
| 退出码 | 0 |
| test_summons 套件（新增） | 12 用例全过（XML 报告 `tests="12" failures="0"`，2.59s） |

与实现者自报 756/756 一致。

## 移交条目（供编排者排程，均不阻塞合入）

| 条目 | 建议承接 | 说明 |
|---|---|---|
| summons 跨房 combat 重接 / 非战斗房守卫 / 层退场 despawn | T22 或 T25（均改 floor_scene.gd） | Minor①②⑤，≈3-6 行，`_wire_room_combat` ShieldSpirit 循环处 |
| summon_cap 注册进英雄 schema | T13（heroes.json 下一改动卡） | Minor③ |
| spare_parts 被动实现归属 | T33 门禁预检（或补微卡） | Minor④，UI 文案已先行 |
| 炮台 DPS 8（vs GDD 15）平衡点 | T28 Balance Bot（已列） | 编排者既有裁定，实现已按裁定落地 |
| 议定值（弹速/弹寿/AoE 半径/炮台 HP） | T28 校准 | 文件头已披露清单 |
