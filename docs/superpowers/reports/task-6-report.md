# M2 Task 6 独立评审报告（C 数据-1 武器扩至 115）

> 评审对象：`.worktrees/m2-t6`（分支 `m2-t6`，单 commit `56ce47d` "feat(m2-t6): full 115 weapon pool per appendix a"，基于 `ed88ef8`）
> 评审日期：2026-08-30。只读评审（未修改任何代码 / 未 commit / 未 merge；评审过程中 `--import` 触碰的 `icon.svg.import` 已还原，工作树保持 clean）。
> 评审依据：`docs/superpowers/plans/2026-08-30-m2-full-content.md`（Global Constraints + Task 6 卡）、`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md` 附录 A（数值唯一出处）。

## 结论

**Approved-with-notes**

规格全部符合：115 把逐把与附录 A 交叉验证零误差（720 项字段比对），稀有度分布/locked/掉落池/图鉴出口全部达约，测试 729/729 实测通过且断言真实有效。无 Blocker。存在 1 项 Major（潜伏性双路径掉落池不一致，当前无任何游戏内/测试影响，T27 前需修复）与若干 Minor/跨卡风险，均不阻塞合并。

---

## 一、规格符合度逐项表

| # | 规格项（Task 6 卡 + 附录 A） | 结果 | 证据 |
|---|---|---|---|
| 1 | 总数 115 | **PASS** | `data/weapons.json` 实测 115 行（Python 独立解析） |
| 2 | id 唯一（行内 id == 字典键） | **PASS** | 115 行 `id==key` 零失配；`test_ids_unique_and_match_keys` 覆盖 JSON 重复键静默合并场景 |
| 3 | 逐行 schema v2 校验 | **PASS** | `test_every_row_passes_schema_v2` 逐行走 `GameDB.validate_row`；GameDB 装载路径 fail-closed（`game_db.gd:165-171`） |
| 4 | 4 元素覆盖 | **PASS** | fire 7 / ice 9 / poison 6 / shock 7（≥2/元素，测试断言） |
| 5 | 稀有度分布 = 附录 A 实际清点（白9/绿21/蓝36/紫33/橙16） | **PASS** | 评审员独立清点附录 A 全表 = JSON 实测 = 9/21/36/33/16；计划卡括号数（13/30/32/25/15）按"按附录 A 实际清点"指示正确弃用 |
| 6 | 紫/橙 locked:true（49 把） | **PASS** | 33 紫 + 16 橙全部 `locked:true`；白/绿/蓝零 locked；`test_locked_matches_rarity_rule` 双向断言（epic/legend 必 locked 且非 epic/legend 必未 locked） |
| 7 | 掉落池排除 locked（66 = 115−49） | **PASS** | `game_db.gd:98-107` `_ready` 剔除后 `GameDB.weapons`=66；消费方 `floor_scene.gd:1026-1030`（`_roll_weapon`）遍历过滤后表；`test_drop_pool_excludes_locked_but_codex_keeps_all` 断言 66 + 池内零 locked |
| 8 | 图鉴侧全量出口 weapons_all | **PASS** | `weapons_all = weapons.duplicate(true)`（115 深拷贝）；测试断言 115；注释明确 T20 CodexSystem 为消费方 |
| 9 | 分布/一致性测试真实有效（非恒真） | **PASS** | 断言常量（9/21/36/33/16/49/66）与实现者数据独立得出且与附录一致；计数动态计算自真实文件（`before_test` 每次 `_load_table` 重读）；详见「三、测试质量」 |
| 10 | TDD + conventional commit 带卡号 | **PASS** | 单 commit `feat(m2-t6): ...`；无多余文件混入（改动仅 3 文件，无 .uid 需求——无新建 .gd） |
| 11 | Global Constraints #3（数值唯一出处=附录）/#8（改 data/*.json 附分布/一致性测试）/#6（import+全量测试） | **PASS** | 720 项字段比对零误差；新增/强化 13 个数据测试；评审员本机复跑 import + 全量绿 |

## 二、附录 A 交叉验证（独立全量，非抽样）

**方法**：评审员从附录 A 文本独立转录全部 115 行（名称、稀有度、类别、伤害、射速/s、蓝耗、元素 + 特性列中的记法字段：N×M 弹丸 / 穿透 N / 反弹 N / 弹速+50% / 射程 px / DOT 记法），与 `data/weapons.json` 双向比对。

**结果**：
- **名称集合双向零差**：附录 115 名 = JSON 115 名，无缺失、无多余、无重复（"缺失 [] / 多余 []"）。
- **字段级比对 720 项全部一致**：rarity/category/damage/rate/energy_cost/element 全量 6 字段 × 115 把 + 记法附加字段（projectiles 17 处、pierce 5 处、bounce 4 处、range 5 处、bullet_speed 1 处）。远超"数值字段抽样 ≥20 把"要求。
- **独立清点稀有度**：白 9（老伙计/铆钉枪/制式步枪/铅管/短弓/学徒法杖/铁剑/双匕/手雷）、绿 21、蓝 36、紫 33、橙 16；紫+橙 = 49 = locked 数；与附录合计行（specs 第 183 行）及 JSON 三方一致。
- **11 类分布**：pistol 13 / melee 12 / 其余 9 类各 10，与附录 A.1~A.11 分节计数一致。
- **★熔铸限定 4 把**（星陨炮/雷神之锤/斩舰刀/湮灭核心，全橙）均在表且 locked:true，不掉落 ✓。

## 三、质量发现

### Blocker（0 项）

无。

### Major（1 项，潜伏性，不阻塞本卡）

**M-1 locked 过滤只存在于 `GameDB._ready()`，非 SceneTree 回退路径拿到未过滤的 115 把全量池**
- 位置：`autoload/game_db.gd:98-107`（过滤在 `_ready`）；`core/meta/shop_logic.gd:126-135`（`_weapons()` 的 `--script` 回退用 `script.new()` + `_load_table` 直接装载——手动实例化不进树，`_ready` 永不触发，locked 49 把不会被剔除且 `_fallback_weapons` 静态缓存固化）。
- 影响：游戏内与 GdUnit 均走 autoload（过滤正确，本次 729/729 全绿证实）；但 `godot -s` 无头工具模式下 `ShopLogic.roll_stock/roll_weapon_id/roll_black_weapon_id` 可抽到 locked 紫/橙。当前仓库无工具使用 ShopLogic（`tools/` 已核查），**T27 Balance Bot 落地时其商店/掉落统计将被紫/橙污染**。
- 建议：把 locked 剔除提为可复用 static（如 `GameDB.drop_pool(all_table)`），`_ready` 与 ShopLogic 回退同源调用；或在回退分支补同款过滤。T27 前修复即可。

### Minor（4 项 + 1 跨卡风险）

**m-1 黑市"偏好紫"在真实数据下退化为纯蓝档**
- `shop_logic.gd:60-68` 黑商优先 legend→epic→rare 回退；紫 33 把全部 locked 出池后，黑市整架只能落到 rare（层 3 权重 epic 13%/legend 4% 的掷点也全部回退到 rare）。`tests/unit/test_shop.gd:315-321` `test_black_stock_prefers_epic_then_rare` 仍绿（断言是成员检查 `["epic","rare"].has(...)`），但其"偏好紫"分支在 T20 解锁引擎落地前是死分支。非本卡缺陷（规格明确要求剔池），建议 T20 落地时回归此测试意图，或先加注释说明。

**m-2 无人机母舰 `rate: 0.0` 的除零隐患**
- `data/weapons.json:114`（附录 A.11 使用/s 为"—"转录为 0.0）；`core/player/weapon_rig.gd:96` `TimeConst.FPS / effective_rate` → inf。该武器 locked 当前不可获得，无实际影响；但 T20/武器行为卡接通前建议在 `effective_attack_rate`（weapon_rig.gd:142-145）钳制 rate 下限或数据侧改用极小正数。

**m-3 schema 无法承载的附录语义（实现者自报 4 类已核实，方向符合附录原意；另发现同类未上报项）**
- 已核实：① 无限穿透/全穿（裁决/贯星弓/电磁轨道/穿棱镜 → `pierce:0`，schema 无"无限"键）；② 穿墙（贯日 → `pierce:0`）；③ 蓄力条件（审判者/长风/星陨炮/审判之日/短弓；**猎风长弓"满蓄力穿透 3"被转录为无条件 `pierce:3`**——简化方向可接受但非附录字面）；④ AoE 附加（星陨炮 30+18→30、火球杖 6+4→6、爆裂箭 8+6→8、手雷 50px/火神重炮 40px 无半径键）。全部取"保留基础数值、丢弃条件加成"的一致方向，且涉及武器几乎全为 locked 紫/橙，当前零玩法影响。
- **未上报的同类丢失**：行为修正类特性亦无法承载——左轮·正午/老兵暴击率、断头台暴击倍率×3、影丸警觉半径、终焉急促叠层哑火、湮灭号角环形分布（arc_deg 0）等。其中 **蜂刺（uncommon，可掉落）** 的"三连点射，第 3 发 ×2"退化为普通手枪——是唯一**当前可掉落武器**的语义降级。建议把"dropped-semantics 清单"整体记入后续武器行为卡 backlog（无需本卡返工）。

**m-4 存量 40 行格式重排造成 diff 噪音**
- 旧文件对齐留白（`"laohuoji":    {...}`）改为紧凑单行，40 行存量行数值零变化（逐字段比对证实），153 行 diff 中约 1/4 为重排。可接受，提示后续数据卡保持一种风格。

**跨卡风险（提请编排者，非本卡缺陷）：★熔铸限定与图鉴解锁的语义冲突**
- 附录 A 第 11/183 行规定 4 把★武器"不入普通掉落池，仅能由附录 D 配方产出"；但本卡 locked 键无法区分"图鉴可解锁"与"熔铸专属"，而计划卡 **T3 要求 49 条解锁任务 = 全部紫+橙（33+16，含★4）**、**T20 规则"解锁达成→武器进掉落池"**。若照字面执行，★4 解锁后将违反附录 A 进普通掉落池。建议：T3 的 unlock_tasks 表排除★4（49→45）或加 `forge_only` 区分键，并在 T20 过滤逻辑中落地。此为计划层矛盾（Global Constraints #3"发现矛盾→停止上报"通道），本卡按规格"紫/橙默认锁定"执行无过错。

### game_db.gd 改动质量（专项）

- **最小性**：diff 仅 +15/-3 行——WEAPON_OPTIONAL 加 `locked:false`（game_db.gd:13）、双出口变量声明+注释（:89-90）、`_ready` 内 8 行过滤（:98-107）。无多余重构。
- **出口语义清晰**：两变量均带消费方注释（weapons→FloorScene/ShopLogic/validate_hero_row/get_weapon；weapons_all→T20 图鉴）。`get_weapon`（:117-118）仍走过滤池——locked 武器当前无获取途径，语义自洽；全部既有消费方（shop.gd:153/390-394、floor_scene.gd:974、weapon_rig.gd:33、training_room.gd:128、hud.gd:126、hero_select.gd:119）对空行均有防御，**零破坏**。
- **validate_hero_row**（:359-368）依赖过滤后 weapons 表：未来若有英雄初始武器为紫/橙会被拒——heroes.json 现有 2 英雄初始武器全白（laohuoji/tiejian/duangong），计划内 T8/T11/T13 初始武器亦为白，无影响（记入 m-3 同级注意事项）。
- **无存档兼容问题**：save_system 不持久化武器 id（已核查），M1 旧档无 locked 武器回载风险。
- **DungeonBuilder 回退**（dungeon_builder.gd:338-351）只手载 rooms 表，不受影响。

### 测试质量（专项）

- **旧测试零弱化、全部收紧**：`≥40` → `==115`；稀有度 `≥8/≥12/≥15` → 五档精确 `9/21/36/33/16`；id/名称/schema/元素/多弹丸 5 个既有测试原样保留（schema 测试还补了 failure message）。
- **新增测试真实有效**（非恒真）：
  - `test_locked_matches_rarity_rule`（test_weapons_pool.gd:137-148）：双向跨字段不变量（epic/legend ⇔ locked），数据侧任一方向造假即红。
  - `test_drop_pool_excludes_locked_but_codex_keeps_all`（:151-178）：对真实 autoload 断言 115/66/49 三计数 + 池内零 locked + locked 不泄漏 + 非 locked `get_weapon` 可解析。
  - `test_appendix_notation_spot_checks`（:181-215）：23 把 × 35 项字段对附录记法硬编码锚点（N×M/穿透/反弹/弹速+50%/射程 px/DOT 记法修正），与本次独立全量比对结论一致。
  - 断言常量与评审员独立清点值完全相等，构成"数据↔附录"的真实绑定。

## 四、测试实测计数

在 `.worktrees/m2-t6` 执行（评审员本机复跑）：

```
godot --headless --path . --import                              # OK
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
      -a res://tests --ignoreHeadlessMode
```

- **729 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans**
- 套件 47/47，exit code 0，总时长 2min 44s。
- 与实现者自报 729/729 全绿**一致**。

## 五、修复建议汇总（供后续卡承接，本卡可合并）

1. （M-1，T27 前）locked 剔除提为 `GameDB` 静态助手，ShopLogic `--script` 回退同源过滤。
2. （m-2，T20/行为卡前）weapon_rig 对 `rate<=0` 钳制或数据改小正数。
3. （m-3）dropped-semantics 清单（无限穿透/穿墙/蓄力/AoE/暴击修正/蜂刺三连发等）移交武器行为卡。
4. （跨卡）T3/T20 区分 ★熔铸限定与图鉴解锁（unlock_tasks 排除★4 或加 forge_only 键）——需编排者裁定。
5. （m-1 附带）T20 落地后回归黑市"偏好紫"测试意图。

---

*评审员：独立评审 agent（只读）。本报告为唯一写入产物。*
