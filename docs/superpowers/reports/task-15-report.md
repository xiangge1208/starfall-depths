# Task 15（E-1 天赋树系统落地）独立评审报告

- **被审对象**：`.worktrees/m2-t15`，分支 `m2-t15`，单 commit `09ba744`（`feat(m2-t15): talent tree system`，基于 `1d71bda`）
- **评审员**：独立评审 subagent（只读评审，未改任何代码、未 commit、未 merge）
- **评审日期**：2026-08-30
- **变更面**：8 文件 +873 行——`core/meta/talent_system.gd`（新 193 行）、`ui/talents.gd`+`talents.tscn`（新）、`autoload/save_system.gd`（+32 行最小新增）、`tests/unit/test_talent_system.gd`（26 例）+ 3 个 `.uid`

## 结论

**有条件通过（CONDITIONAL PASS）。**

系统本体（数据消费、购买流、own-delta 幂等落地、持久化、UI、测试）质量高：26/26 新测试稳定绿，全量 836 例中 T15 相关零失败（两轮全量各自失败的 2/1 例均为**负载敏感偶发**、非 T15 文件，单跑全绿，详见测试实测节）；无 Blocker。但存在 **2 个 Major**，均为"接线/承接悬空"类规格问题（实现者已如实披露）：①附录 I.4 声明 **M2-T15 本卡**为消费方的 4 个 `talent_` 键未接线，且计划中无任何后续卡承接该接线；②BuffManager 六键绝对写与天赋 own-delta 的覆盖冲突是**潜伏缺陷**，当前因局内未 apply 而未触发，但收口方案必须在接线卡落地，而"局内开局 apply"本身也无明确承接卡。建议：**合并前先在计划/台账中把这两项承接明确化**（一行修订即可），系统代码本体可原样合入。

## 规格核对（逐项）

| # | 规格项 | 判定 | 依据（文件:行号） |
|---|---|---|---|
| 1 | `available()`：前置满足 + 未购 | **PASS** | `core/meta/talent_system.gd:52-69`；`is_available` 单点实现，available 排序保证确定性 |
| 2 | `buy(id)`：蓝晶校验→SaveSystem 扣除→持久化 | **PASS** | `talent_system.gd:79-98`；校验顺序：未知 id（push_error）→重复→前置→后端缺席（push_error）→余额→`add_gems(-cost)`→`record_talent_purchase` |
| 3 | `apply_to_player`：效果全量落地 | **PASS（带 Major-1 保留）** | `talent_system.gd:132-178`；12 个复用键直写 Player（9 键）/WeaponRig（3 键）公开字段，与附录 I.4 复用键表逐一同名同义；5 个 `talent_` 前缀键中仅落 meta 聚合（见 Major-1） |
| 4 | apply 落地键 ⊆ 附录 I 白名单 | **PASS** | `aggregate()`（:113-124）只认 `GameDB.TALENT_PCT_KEYS/TALENT_INT_KEYS`（game_db.gd:94-102，与附录 I.4 两表并集一致）；测试 `test_aggregate_keys_subset_of_whitelist` 锁定 |
| 5 | UI：三系树状排布 + 购买 + 蓝晶余额 | **PASS** | `ui/talents.gd:46-66` 三系各一列 ×8 层纵排；:95-109 点击购买；:72 蓝晶余额。树状分叉拓扑经详情面板前置文案表达（480×270 不画连线，:44-45 注明）——设计妥协合理 |
| 6 | 场景零硬编码玩法数值 | **PASS** | `talents.tscn` 仅布局/颜色/占位文本"蓝晶 0"（`_refresh` 即覆写）；价格/tier/名称/描述/前置全部读 `GameDB.talents`；`NODE_MIN`/色板为表现层常量非玩法数值 |
| 7 | TDD 五类：前置门控/蓝晶扣减/效果落地/重复购买拒绝/持久化往返 | **PASS** | 26 例覆盖五类 + 附录 I.5 满系数值逐键锁定 + fail-soft 脏档 + 全树买空经济校验（`test_talent_system.gd`，清单见附录 A） |
| 8 | 边界披露评估（4 键消费未接线/主菜单入口/局内 apply 未接线） | **部分可接受** | `talent_gem_gain_pct`→T31（波次表）计划明确 ✓；**其余 4 键 + 主菜单入口 + 局内开局 apply 无计划内承接卡**（见 Major-1） |

补充核对：

- **提交卫生**：conventional commit 带卡号 ✓；3 个 `.uid` 随卡提交 ✓；RNG/盐不涉及 ✓；热路径零分配不涉及（apply 仅开局/购买时调用）✓；数值唯一出处（cost/effects 全部 `data/talents.json`，测试常量 `FULL_TREE_COST=10000` 为附录 I.2 锁定值）✓。
- **数据表一致性**：`data/talents.json` 24 节点与附录 I.3 全表逐行一致（id/名称/价格/前置/效果抽查全对）；满系聚合与附录 I.5 累计逐键吻合（测试 :180-202 锁定）。

## 质量发现

### Blocker

无。

### Major

**Major-1：附录 I.4 声明"M2-T15"为消费方的 4 个 `talent_` 键未接线，且承接悬空。**

- 附录 I.4（`docs/superpowers/specs/数据表附录-I-天赋树.md:102-110`）对 5 个新键逐键声明消费方：`talent_dmg_pct`→**M2-T15** →WeaponRig 伤害乘区、`talent_hurt_iframe_pct`→**M2-T15** →Player 受击无敌帧乘区、`talent_coin_gain_pct`→**M2-T15** →Pickup 金币乘区、`talent_pickup_radius_pct`→**M2-T15** →Pickup 磁吸乘区；仅 `talent_gem_gain_pct`→M2-T31。已合并的 `autoload/game_db.gd:89-93` 注释重复同一声明。
- 实现（`talent_system.gd:188-193` 消费方接线表）把这 4 键的接线推给"各自文件所有权卡"——但**M2 计划中不存在拥有 `weapon_rig.gd` 伤害乘区 / `player.gd` iframes / `pickup.gd` 磁吸与金币的后续卡**（波次表 W5-W10 逐卡核对无着落；T18 只依赖 T15 做 victory_summary，T25/T31/T32 只管蓝晶结算与存档 migration）。
- 权衡与定性：Task 15 卡的 Files 行只授予 `talent_system.gd`+`ui/talents`，实现者不越权改 `player.gd/weapon_rig.gd/pickup.gd` 符合 worktree 文件所有权纪律，且以 meta `talent_effects` + `effects_of(player)` 只读出口（:182-186）交付了聚合值——**边界处理本身是干净的、披露是充分的**；但按"数值唯一出处=附录"的严格口径，附录声明本卡消费的 4 键实际成为**无主死键**，直到有人接线前天赋树红绿两系对局内玩法零生效（蓝系 6/8 键、绿系 4/8 键已生效）。这不是代码缺陷而是**承接缺口**，修法见修复建议 R1。

**Major-2：BuffManager 六键绝对写对天赋贡献的覆盖（潜伏，无当前触发路径）。**

- 实现者披露准确：`core/meta/buff_manager.gd` 对 `crit_bonus`(:126)、`crit_damage_bonus`(:127)、`status_rate_bonus`(:128)、`shield_delay_reduction_ticks`(:130)、`roll_cd_pct`(:132)、`enchant_proc_chance`(:153，rig 侧) 为**基线绝对写**（buff_agg+drink meta），BuffManager 任意一次重 apply 都会抹掉 TalentSystem 先前 own-delta 加上去的贡献；此后 TalentSystem 再 apply 时"减掉幻影上次贡献+重加"恰好补回（数学上自洽，见修复建议 R2 的推导）。
- 评审补充一处实现者未列的**顺序敏感面**：`buff_manager.gd:146-147` 的 `rate_mult/bullet_speed_mult` 走 `_rig_base` 首次捕获策略——若首次 buff apply 早于天赋 apply（基线不含天赋倍率），此后每次 buff 重 apply 会把 rig 重置到 `基线×buff`，同样抹掉天赋贡献；若天赋先 apply，天赋倍率被烘进基线（天赋是永久的，语义可接受）。R2 的顺序不变式对这处同样生效。
- 顺序无关面（无需担心）：`hp_max/shield_max/energy_max/move_speed` 两侧均为 own-delta（加法/乘法可逆），任意顺序可组合 ✓。
- **当前严重度：潜伏、零 live bug**——grep 证实 `TalentSystem.apply_to_player` 在 `core/`（run_root/player/weapon_rig/pickup）无任何调用点，天赋尚未进局。但"局内开局 apply"本身也没有承接卡（同 Major-1 的缺口面），若接线时不带顺序不变式，红系暴击/暴伤/异常、蓝系盾延时/翻滚 CD、附魔概率共 7 处将在第一次三选一后静默丢失天赋贡献。收口方案见 R2。

### Minor

- **Minor-1（耐久性缝隙）**：`buy()` 两次落盘（`save_system.gd:120-122` `add_gems`→save_now；:166-171 `record_talent_purchase`→save_now）之间进程死亡会留下"蓝晶已扣、购买记录丢失"的档。菜单场景、窗口极小、代码注释已自知（:164-165）；可在 T31 migration 时合并为单事务写（先 record 再一次性 add_gems+save，或加聚合 API）。
- **Minor-2（文案）**：`ui/talents.gd:117-127` `_effect_summary` 把效果裸显为英文原始键名（如 `crit_pct+4% hp_max+2`），详情面板中英混杂，违背"文案中文"基调。建议键→中文量纲映射表（伤害/暴击率/HP 上限…）。
- **Minor-3（duck-typing 不对称）**：`talent_system.gd:89` 只 `has_method("add_gems")` 防御，随后直接调 `gems()`(:93) 与 `record_talent_purchase`(:96) 未防御；当前后端契约恒满足，仅测试注入异构后端时可能裸崩。
- **Minor-4（卡号漂移）**：计划波次表 T31=存档 migration v2，详情卡却是 Task 25（migration）/Task 32（结算接线）/Task 31（导出冒烟）；代码注释（`save_system.gd:40-41`、`talent_system.gd:191`）引用"T31"按波次表口径。收口时需统一，避免承接卡号二义。
- **Minor-5（测试盲区）**：①无 BuffManager×TalentSystem 交错 apply 的组合测试（对应 Major-2，接线卡应先补 RED）；②`test_apply_recompute_preserves_external_writes`（:280-292）外部写入场景未购买移速节点，乘法 own-delta 的"非平凡除法还原 ×外部写入"组合未直接覆盖（幂等测试 :267-277 覆盖了除法反转，两者机制各自有证，组合留白）；③无 rig 更换（`_rig_last` 跨 rig 对象）用例。
- **Minor-6（非本卡引入）**：`test_floor_scene.gd:394-395`、`test_telemetry.gd:80` 两处帧时序用例在全量负载下偶发失败（见下节实测），单跑全绿。建议门禁（T34）前专项治理（放宽 `_await_until` 超时或改注入帧驱动）。
- **Note（实例态）**：`_p_last/_rig_last` 为 TalentSystem **实例级**状态（:34-35）——若 UI 实例与局内实例对同一 Player 交错 apply 会互相踩。接线卡须保证"每 run 单一 applier 实例"或注入同一实例；建议写进接线卡的契约注释。

## own-delta 幂等实现正确性（重点复核）

- **两次连call**：`aggregate()` 从 purchased 列表全量重算，own-delta 先剥 `_p_last` 再加新 agg——第二调用 = field − T + T，不变 ✓（`test_apply_idempotent` 实证：hp 12/能量 140/移速 86.4/rig 1.06、1.08 双 apply 后不叠加）。
- **购买新节点后再 apply**：agg 为全量总额而非增量，`_p_last` 记录的也是全量——增量差自动正确 ✓。
- **乘法键（move_speed/rate_mult/bullet_speed_mult）**：`(cur / (1+last)) * (1+agg)` 可逆还原 ✓；除零不可能（幅度上限 +0.10，白名单校验兜底）。
- **rig 为空时**：`_p_last` 照常更新而 `_rig_last` 不动（:162-163），rig 后到再 apply 时 `_rig_last` 仍为中性零基线，不误除 ✓。
- **与外部写入共存**：`test_apply_recompute_preserves_external_writes` 断言外部改 hp_max/移速后重 apply 不丢外部值 ✓。
- **结论**：own-delta 实现正确，与 BuffManager 的组合缺陷不在本系统实现，而在 BuffManager 的绝对写面（Major-2）。

## 蓝晶经济一致性

- 负余额防护：`buy` 先 `gems() < cost` 拒绝后扣减（:92-95），经 buy 路径不可能透支 ✓；边界恰好够（=cost）允许、余额归零（测试 :118-121）✓。
- 并发：Godot 单线程 + `save_now` 临时文件原子 rename（save_system.gd:107-118），无并发窗口；两次落盘缝隙见 Minor-1。
- 重复购买/未知 id/前置未满足均不扣款（测试 :124-145 逐项锁定）✓。

## save_system.gd 改动最小性

**PASS。** +32 行全部围绕单键 `purchased_talents`：默认档骨架（:39-42）、`_merge_saved` 同 `unlocked_heroes` 口径（:80-87）、防御性读取 `purchased_talents()`（:153-162）、幂等 `record_talent_purchase()`（:164-171）。fail-soft 口径与既有键一致（脏元素静默过滤，测试 :340-352 锁定）；不递增 SAVE_VERSION、不动 migration 钩子，T31 注记明确 ✓。additive 键位使旧档零迁移可读，设计得当。

## 测试实测（本机真实计数）

| 项 | 结果 |
|---|---|
| `godot --headless --path . --import` | exit 0 ✓ |
| 全量第 1 轮（836 例） | **2 failures**：`test_floor_scene > test_scene_combat_lock_two_waves_clear`（:394-395 两条断言，`_await_until` 超时） |
| 全量第 2 轮（836 例） | **1 failure**：`test_telemetry > test_flush_every_60_physics_frames`（:80，物理帧时序） |
| `test_floor_scene.gd` 单独跑 | 24/24 PASS（476ms） |
| `test_talent_system.gd` 单独跑 | **26/26 PASS**（448ms，0 orphans） |
| `ui/talents.tscn --quit-after 5` headless 冒烟 | exit 0，无脚本错误 ✓ |

- 总数 836 = 基线 810 + 26，与自报"+26 测试"一致 ✓。
- **"836/836 绿"未能在本机全量复现**，但两轮失败的用例各不相同、且都不在 T15 变更面（diff 不触及 combat/telemetry 代码路径），单独跑均绿——判定为**负载敏感偶发（flaky-under-load），与 T15 无因果**（Minor-6）。实现者的自报在其运行环境下可能为真，门禁复跑时如再遇同两处失败按已知 flaky 处理。
- 断言强度：26 例全为直接断言（assert_int/float/array/is_equal_approx），无 lambda 发现器怪癖规避痕迹（全常规 `func test_*`），断言未被削弱 ✓。
- 评审副作用说明：本次评审的 `--import` 运行改动了 worktree 内 `icon.svg.import`（未提交），符合"勿提交噪音"约束，合入前实现者/编排者无需处理。

## 修复建议

**R1（Major-1 承接明确化——合并前置，改计划不改代码）**：三选一，推荐 a。
- a. 增设微卡 `m2-t15b`（或并入 T25/T31 卡内 checklist）：`weapon_rig.gd` 伤害乘区（同 `rate_mult` 模式，读 `TalentSystem.effects_of`）、`player.gd` `HURT_IFRAME_TICKS × (1+v)`（player.gd:11,139）、`pickup.gd` `MAGNET_RANGE_PX × (1+v)` 与 coin 计数乘区（pickup.gd:11,40,48-）、`run_root._spawn_hero_player` 开局 apply（run_root.gd:90-101 之后）、main_menu 灰钮点亮 + SceneRouter 加 `"talents"` 路由键——一并带 R2 顺序不变式。
- b. 修订附录 I.4 + game_db.gd:89-93 注释的消费方列到实际承接卡号（若编排者决定延期）。
- c. 维持现状但必须在 `m2-progress.md` 台账登记移交项（当前台账 T15 行无任何移交记录）。
- 无论选哪项：`m2-progress.md` 的 T15 行应补"4 键消费未接线/入口未接线"移交标注。

**R2（Major-2 最小收口——接线卡 MUST-FIX，两选一，推荐 A）**：
- **A. 顺序不变式（零新耦合，改动最小）**：接线时定死 apply 顺序 **HeroApplier → BuffManager → TalentSystem**，且**每次 BuffManager 重 apply 之后追加一次 `TalentSystem.apply_to_player(player)`**（调用点：run_root.gd:101 后开局一次；`buffs.apply_to_player` 的全部调用处之后，即三选一 buff_pick 路径）。正确性推导：buff 绝对写把字段抹回 `base+buff` 后，天赋 own-delta 执行 `field − _p_last(幻影) + agg = (base+buff) − T + T`，恰好补回贡献；对 `_rig_base` 捕获策略同样成立（只要天赋 apply 总在最后一次 buff apply 之后，倍率丢失后总会被重乘回）。天赋键永不变（购买只在菜单），重 apply 语义安全。
- **B. 结构性并入**：BuffManager 六处绝对写改为并入读取天赋聚合（如 `:126` 改 `buff_agg + drink + float(TalentSystem.effects_of(p)["crit_pct"])`）。一次写全、无顺序依赖，代价是 BuffManager→TalentSystem 静态耦合 + 六处改动 + `test_buffs` 回归。
- 无论 A/B：先补 **RED 组合测试**——`buy 红系 → talent apply → buff pick（含暴击/暴伤 buff）→ 断言六键 = buff+drink+talent 之和 → 再 buff pick → 再断言`；顺带覆盖 rig 侧 `rate_mult` 基线捕获顺序（buff 先/后两种时序）。

**R3（Minor，随 T31/收口）**：Minor-1 购买单事务写；Minor-2 效果摘要中文量纲映射；Minor-3 `gems()`/`record_talent_purchase` 的 has_method 对称防御；Minor-4 台账统一卡号口径；Minor-5 组合测试随 R2；Minor-6 flaky 治理（放宽 `_await_until` 时限或注入帧驱动）归门禁预检。

## 附录 A：26 例清单（分类）

前置门控 4（roots/排除子节点/买根放行/绿系主脊逐级）；蓝晶 6（扣减/不足/恰好边界/未知 id/前置未满足不扣款/重复拒绝单次扣款）；聚合 4（空中性/求和/白名单子集/满系逐键=附录 I.5）；落地 7（无购 noop/蓝系字段/红系标量/rig 三键/talent_ 前缀 meta/幂等/外部写入保留）；持久化 3（全新实例往返/重读防重复购买/脏档 fail-soft）；经济 1（全树买空 24 节点余额归零）；autoload 冒烟 1（API 存在性，只读不触真实档）。
