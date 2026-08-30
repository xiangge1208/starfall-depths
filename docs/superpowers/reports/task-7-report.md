# Task 7 评审报告：A2 地刺 + 晶柱折射 + A1 危险地块补全（分支 m2-t7）

- **被审对象**：`.worktrees/m2-t7`，单 commit `c4aa6fa` `feat(m2-t7): a2 spikes, prism refraction, a1 hazards, a2 enemies`（基线 `1d71bda`）
- **评审员**：独立评审（只读；除本报告外未修改任何被审代码、未 commit、未 merge。评审中 `--import` 触碰的 `icon.svg.import` 已当场还原，worktree 复净）
- **评审日期**：2026-08-30
- **规格出处**：`docs/superpowers/plans/2026-08-30-m2-full-content.md` Global Constraints + Task 7 卡；GDD design §10（A1/A2 危险地块行）
- **测试实测**：`godot --headless --path . --import` exit 0 无报错；GdUnit4 全量 **841/841 通过**（53/53 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，32.96s）——与实现者自报一致；新增 31 例（`test_enemy_laser.gd` 12 + `test_hazards_m2.gd` 19）逐例见 PASSED

---

## 一、结论

# Approved

规格六项全 PASS：地刺相位机、晶柱 45° 折射（反射数学四象限手算复核无误、防无限闭环成立）、藤蔓减速（结构上敌人不可能被写入）、滚石全生命周期、编排者裁定④（enemies.json 47→47 行仅加 `laser:true`）、TDD 覆盖齐全且实测全绿。turret.gd 的 laser 分支为纯增量（行键门控），既有 projectile/fan/burst 形态零扰动。

**无 Blocker、无 Major**。8 项 Minor（多为注释表述与表现层精度问题，均不阻塞合并）+ 3 项移交项（spikes/rock 数据 dormant 待 T10/T26 落库、折射柱快照语义与激光束量上限待 T14 知悉）。修复建议见第六节。

---

## 二、规格符合度逐项表

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 地刺：周期 90t 伸出 / 预警 24t / 伤 4 / 缩回 60t（周期 174t 回卷）；**伤害发生在伸出期** | **PASS** | `hazard_spikes.gd:12-15` 常量 24/90/60/4；`cycle_ticks()=174`；`phase_at` 半开区间钉死边界（t=24 立即进伤害窗、t=114 立即安全，负 t 回卷）；`damage_at` 仅 `Phase.OUT` 且 zone 命中才返回 4。`test_spike_phase_boundaries` / `test_spike_damage_window_only_while_out` 全边界覆盖 |
| 2 | 晶柱折射：敌方激光命中晶柱按 45° 反射再飞、最多 1 次（防无限）；反射数学 r=2(d·u)u−d 四象限正确性 | **PASS** | `enemy_laser.gd:39-44` 纯函数；评审员手算复核（u=(√2/2,√2/2)）：RIGHT→DOWN、LEFT→UP、UP→LEFT、DOWN→RIGHT，四轴向入射偏转恰 90°；法线入射（d⊥u）r=−d 原路折返；沿轴掠射 r=d 不变（仍消耗次数，注释与测试均钉死该边界）。`MAX_REFRACTIONS=1`，二次触柱 `_end()` 吸收（`test_laser_second_pillar_hit_absorbed_no_infinite`）；折射后从柱面沿新向弹出 12px > 判定半径 11px，防同柱反复判定 |
| 3 | 藤蔓减速：进入减速 40%、复用 T4 区域模式、敌人不受影响 | **PASS** | `vine_zone.gd`：IceZone 同构（`Array[Rect2]`+`add_zone`+`tick` 帧级接缝），语义不同（写 `incoming_slow_pct/until` 而非 friction）故平级复用模式不继承，取舍正确；与更强减速取 max 不互相削弱（有测试）；`tick` 只收 `Player`，敌人无该接缝字段（`test_vine_never_touches_enemies` 结构性断言）；2t 保持窗自然过期，楼层销毁不泄漏（帧基自过期，优于 friction_mult 的显式复位） |
| 4 | 滚石：预警线 0.5s（30t）、速度 200、伤 6、撞墙（出房内域）消失 | **PASS** | `rolling_rock.gd:11-13`：WARN_TICKS=30（=TimeConst.ticks(0.5)，FPS=60 已核）、SPEED_PX=200、DAMAGE=6；ROLL 相位滚出 `bounds.grow(ROCK_RADIUS)` 即回 WAIT（`test_rock_lifecycle_wait_warn_roll_despawn` 全周期含撞墙）。间隔默认 240t、模板 `interval_ticks` 可调（卡面未给间隔，合理补充） |
| 5 | 编排者裁定④：enemies.json 无重复插行（总数仍 47）；仅 rock_crystal_turret 加 laser:true | **PASS** | diff 仅 1 行（enemies.json:24 尾加 `"laser":true`）；基线与 HEAD 均实测 47 行；键名重复清点为零；`laser` 键不在 ENEMY_SCHEMA/OPTIONAL 但加载器只校验必填键、多余键保留（game_db.gd:201-222），与既有 `burst_count`/`fan_count` 同款按行 opt-in 模式，无 fail-closed 风险 |
| 6 | TDD：周期边界 / 伤害窗 / 折射方向 / 滚石生命周期 | **PASS** | 31 新测试实测全绿：相位全边界（含负 t）、伤害窗内外、四象限+法线+掠射+单位长度+零向量、双柱防无限、擦边不折射、出界/寿命终结、滚石全周期+车道接触+方向归一、FloorScene 接线（模板 hazards → 实例化 + 帧驱动伤害）、晶柱入组、炮台激光形态参数取行。附注：单 commit 无法从产物证明 RED→GREEN 顺序（GC7 过程项，非缺陷） |
| 7 | （附加）turret.gd laser 分支不破坏既有 projectile 形态 | **PASS** | `turret.gd:47-50` 行键门控且置于最前，非 laser 行走原 fan/burst 路径零改动；roster 中仅 rock_crystal_turret 带 laser:true（实测 grep）；原 burst_count=1 单发弹 → 现激光，是该行本卡的预期形态切换 |

---

## 三、关键实现取舍评估（评审员意见）

1. **纯逻辑组件 + 宿主帧驱动**（spikes/rock/vine 均 RefCounted，视觉由 FloorScene 挂）：延续 T4 IceZone 模式，无头可测、无 Area2D 依赖。地刺相位用 `phase_at` 纯函数钉死边界而非状态机计数，天然支持 `offset_ticks` 错峰（确定性网格散列 `(gx*7+gy*13)%174`，不引 RNG，合规 GC2）。**认可**。
2. **EnemyLaser 世界坐标权威 + 节点仅显示镜像**（`_sync_display` 每帧 `global_position=laser_pos`）：挂任意父节点（含运动的 T14 魔像）都安全；帧注入 `tick()` 与树内 `_physics_process` 双驱动，脑层测试直呼。**认可，为 T14 复用铺好了路**。
3. **伤害节流委托玩家 0.8s 受击无敌帧**（HURT_IFRAME_TICKS=48，`take_hit` 内部裁决）：与敌方接触伤害（enemy_base.gd:262-272）完全同款契约，不另设冷却。**认可**；但引出 Minor m8 的节奏口径问题（见下）。
4. **dormant 数据 + 注入测试**：spikes/rock 接线已实现但无真实数据行（GameDB hazards 白名单仅 vine，game_db.gd:335-336）。测试以注入 `GameDB.rooms["combat_a1_99"]` 验证（绕过校验是有意的——schema 未扩展），`after_test` 释放场景并擦除注入行（test_hazards_m2.gd:64-68，**清理干净**，全量 0 orphans 佐证）。代码与测试注释均显式标注"待 A2/A3 模板卡扩展 schema"。**认可为合规的分卡交接**，移交项见第五节。

---

## 四、质量发现（Blocker 0 / Major 0 / Minor 8）

### Minor

- **m1｜伤害 ctx 在重叠期每物理帧构建，注释表述过强**：`core/rooms/floor_scene.gd:472-473` 注释称"伤害 ctx 仅命中拍构建（事件频率）"，实际 `:491-492`（地刺）/`:506-507`（滚石）在 `damage_at>0` 的**每一帧**都构建 Dictionary——站桩伸出期 90t 内约 90 次分配，i-frame 只让 `take_hit` 内部 no-op，不阻止分配。与敌方接触伤害既有惯例（enemy_base.gd:267 同款）一致，非回归、量级可忽略，但违反 GC5 字面且注释与行为不符。建议：`damage_at>0` 后加 `not player.is_invincible()` 前置门控再构建 ctx，使注释成真。
- **m2｜藤蔓判定域与视觉形状不一致**：`floor_scene.gd:396` 判定域为外接正方形（2r×2r），视觉是半径 r 的圆形贴图（hazard_vine.png）。四角（距中心 r√2≈34px）在贴图外仍减速，判定面积多约 27%（4/π−1）。玩家会在"看起来没踩到"的位置被减速。建议改为圆判定（`distance_to(center) <= r`）或方形的视觉贴图。
- **m3｜滚石预警线穿透远端墙**：`floor_scene.gd:444-449` 车道线长 = interior 全宽/全高、从出生瓦片起算，西墙出生的线会超出东墙内界约 24-40px。纯表现（z=-4、α=0.25），无玩法影响。
- **m4｜EnemyLaser 不入敌弹 400 上限 / 未池化**：`turret.gd:83` 每发 `EnemyLaser.new()`，束是独立 Node2D 而非 combat.spawn_projectile，不受"敌弹单独上限 400"约束也不入池（GC4）。当前节律自限：cd180−windup36=144t > life120t → 每炮台至多 1 束并存，风险受控。**T14 晶棱魔像三向扫描复用时须重估束量并考虑计入弹幕预算**。
- **m5｜所有 pillar 陈设都折射，卡面口径是 prop_crystal_pillar**：`floor_scene.gd:361-362` 将一切 `kind=="pillar"` 入 `refraction_pillars` 组。当前无行为差异（A1 垃圾池 kuli_bug/cave_bat/crossbowman/vine_charger 无激光行，laser:true 仅 A2 的 rock_crystal_turret），A2 模板落库（T27）若需混排"普通石柱不折射/晶柱折射"须拆 kind 或加子键。
- **m6｜激光音效无门控**：`turret.gd:96` `_fire_laser` 无条件 `AudioMgr.play`，而 `fire_bullet`（enemy_base.gd:109-121）以 `combat!=null` 门控音效（脑层测试不触发）。脑层炮台测试会真实播音（headless 无输出，无害），仅与既有口径不一致。
- **m7｜`player.global_position` 无 is_instance_valid 防护**：`floor_scene.gd:477`（`_tick_hazards` 开头）。`_physics_process:182` 只判 `player == null`；若玩家实例被 free 会崩。与既有代码同款（`:718`/`:965` 亦直接取 `player.global_position`），且当前玩家无运行中 free 路径——非回归，记档备查。
- **m8｜场景层 i-frame 测试保真度 + 地刺站桩节奏口径**：`test_hazards_m2.gd:289-292` 在**同一引擎物理帧**内循环 200 次 `fs._physics_process(0.0)`（`Engine.get_physics_frames()` 恒定），只验证了同帧幂等；跨帧语义未覆盖——真实对局中 OUT 窗 90t > i-frame 48t，站桩玩家**每周期吃 2 次 4 伤（8 伤/周期）**。测试注释已如实标注"同物理帧内"，非误导，但该跨帧语义无任何测试。两点建议：①补 `take_hit_ctx(ctx, frame)` 显式帧驱动的跨帧用例；②提请编排者确认"伤 4"是否意指每周期至多 1 次（若是，OUT 期内需自持节流，如命中后该簇本周期不再判定）——敌方接触伤害同款语义（48t 一跳），按现口径判为可接受，但地刺是玩家主动站上去的静态 hazard，口径值得显式裁定。

### 移交项（非本卡缺陷，需后续卡承接）

- **h1｜T10/T26**：扩展 `game_db.gd:335-336` hazards 白名单（spikes/rock + side/interval_ticks 键的类型校验）并落真实数据行——当前 spikes/rock 全链 dormant，仅测试注入可达。
- **h2｜T14**：折射柱为**发射时快照**（`turret.gd:77-82` 一次性收集组内坐标）——飞行中的激光看不到之后新生成的柱。晶棱魔像"晶柱再生"下，再生柱只影响后续新射线（通常正是期望语义），但需知悉；魔像死亡其名下激光束随子节点级联消亡（束亡于_owner，瞬移安全因世界坐标权威）。连同 m4 的束量上限一并复核。
- **h3｜T27**：A2 瓦片接线时补地刺/晶柱/滚石专项贴图（当前为染色多边形占位，符合美术管线排期）。

### 热路径核查（GC5）

`_tick_hazards` 每帧：零字符串/零路径拼接；色全常量（`SPIKE_WARN_COLOR/SPIKE_OUT_COLOR`）；`match` 整型枚举；`damage_at`/`phase_at` 纯算术；视觉仅翻 `visible`/写 `modulate` 引用。唯一分配是 m1 的重叠期 ctx。晶柱组查询在发射事件时（非每帧）。BiomeFx 的逐帧 enemies 组遍历为 T4 既有。**结论：热路径合格**。附注：`_spikes/_rocks` 为全楼层累计数组（非当前房过滤），几十实例的算术推进可忽略，T26 大规模落库后若需优化可改"仅推进当前房"（代价：错峰相位须改为绝对帧对齐，当前 `offset_ticks` 设计已兼容）。

---

## 五、测试实测记录

| 项 | 结果 |
|---|---|
| `godot --headless --path . --import` | exit 0，无 ERROR/PUSH_ERROR |
| GdUnit4 全量（res://tests，--ignoreHeadlessMode） | **841 test cases，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans**，53/53 套件，32.96s，exit 0 |
| 新增套件 | `test_enemy_laser.gd` 12 例全 PASSED（折射数学 4 + 生命周期 7 + 炮台形态 1）；`test_hazards_m2.gd` 19 例全 PASSED（地刺 5 + 藤蔓 5 + 滚石 4 + 接线 5） |
| 与自报核对 | 841/841（+31）**一致** |
| worktree 卫生 | 提交内无 .import/__pycache__ 噪音；.uid 四枚随卡提交符合波次表注 |

---

## 六、修复建议（按优先级）

1. **（m1，一行）** `floor_scene.gd:491/506` 两处 `if s.damage_at(player_pos) > 0:` 后增 `and not player.is_invincible():`——对齐注释"事件频率"承诺，消除重叠期每帧 Dictionary 分配（GC5 字面合规）。
2. **（m2，小改）** `_build_vine` 判定域改圆（VineZone 增 `in_circle` 或 zone 存 center+radius），消除视觉外减速。
3. **（m8，测试+裁定）** 补跨帧 i-frame 用例（`take_hit_ctx` 显式帧驱动）；向编排者提请裁定地刺"每周期命中次数"口径（维持现语义或 OUT 期自持节流）。
4. **（m3/m6，顺手）** 预警线长度截到 interior 内界；`_fire_laser` 音效按 fire_bullet 口径加 `combat != null` 门控（或注释说明差异）。
5. **（m4/m5，登记到 T14/T27 卡简报）** 激光束量上限与弹幕预算归口；pillar kind 拆分预案。
6. **（h1，登记到 T10/T26 卡简报）** hazards schema 白名单扩展清单：`kind∈{vine,spikes,rock}`、rock 增 `side∈{N,S,E,W}`/`interval_ticks:int>0`、spikes 用现有 grid。

---

## 七、复核用关键文件

- 被审实现：`.worktrees/m2-t7/core/rooms/hazard_spikes.gd`（56 行）、`vine_zone.gd`（42）、`rolling_rock.gd`（67）、`core/enemies/enemy_laser.gd`（151）、`core/enemies/archetypes/turret.gd`（+36）、`core/rooms/floor_scene.gd`（+204/−24）、`data/enemies.json`（1 行）
- 测试：`.worktrees/m2-t7/tests/unit/test_hazards_m2.gd`（313 行）、`tests/unit/test_enemy_laser.gd`（166 行）
- 佐证读取：`core/rooms/ice_floor.gd`、`core/rooms/biome_fx.gd`、`core/rooms/player_proxy.gd`、`core/player/player.gd`（i-frame/减速接缝）、`core/enemies/enemy_base.gd`（接触伤害契约/combat_bounds）、`core/rooms/room_combat.gd:166-167`（player_ref/combat_bounds 注入）、`core/combat/time_const.gd`、`autoload/game_db.gd`（hazards 白名单/行加载）、`data/rooms/a1_templates.json`（真实 hazards 仅 vine）
