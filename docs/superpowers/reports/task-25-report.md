# Task 25 评审报告：熔铸台场景接线（分支 m2-t25）

- **被审对象**：`.worktrees/m2-t25`，功能提交 `b331bce` `feat(m2-t25): forge station wiring` + `c0ba77a`（merge main tip `89b5cfa`），净 +1012 行 / 10 文件
- **评审员**：独立评审（只读；除本报告外未修改任何实现文件）
- **评审日期**：2026-08-31
- **数值唯一出处**：`docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md` **附录 D（熔铸固定配方 15 条）**（计划文档勘误裁定⑤确认附录 D 实为熔铸配方表）
- **规格锚点**：波次表 W8 T25（`2026-08-30-m2-full-content.md:50`，文件 = floor_scene.gd(熔铸房) + ui/forge.gd）；编排者裁定③（m2-progress.md:38，craft_x/forge_only）；T20 披露（codex_system.gd:13/191 的「craft_x 占位待 T25」）；移交项（m2-progress.md:59 召唤物残留收口承接卡 T22/T25）
- **测试实测**：`godot --headless --path . --import` 通过；GdUnit4 全量 **1132/1132 通过**（67/67 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，4min22s，exit 0）＝main 基线 1097 + 本卡 35，与预期精确吻合

---

## 一、结论

# NEEDS FIXES（Important ×2，Minor ×4；核心实现质量高，修复面很小）

数据面零误差：附录 D 15 条配方**程序化全量交叉验证通过**（组合/产物/产出稀有度三层，含与 weapons.json 的 id/名称/稀有度比对，零失配）；ForgeLogic 纯逻辑习语干净（fail-closed 全覆盖、preview/fuse 同源判定无付费陷阱）；挂载走 RunState 四接缝（wallet/pool/rng/run_state）；35 例测试断言真实（附录钉死、同种子探针独立复算、locked 掉落池 vs 全量表对照断言）；全局约束（热路径/场景数值/中英文/.uid/data 一致性测试）全部合规。

但**规格核对点 3/4 未满足**：T20 留下的 `count_craft()` 占位（「T25 熔铸台接线点」）**没有任何调用方**——`ui/forge.gd` 熔铸成功路径未上报 CodexSystem，`data/unlock_tasks.json` 中 5 条 craft_x 任务（含裁定③点名的 4 把★熔铸限定武器图鉴项）进度恒 0、永不解锁。这是本卡规格明示的接线项，修复约 1 行 + 1 测试。另按评审指令将移交项「召唤物跨房间残留 3 行收口」（承接卡 T22/T25）未包含记为 Important 标注性缺口。详第三节。

---

## 二、规格符合度逐项表

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 波次表 W8 文件面：floor_scene.gd(熔铸房) + ui/forge.gd | **PASS** | `core/rooms/floor_scene.gd:35`（FORGE_SCENE preload）+ `:1153-1161`（_build_shop 内挂载）；`ui/forge.gd`(289 行) + `ui/forge.tscn`；变更面 10 文件与卡面一致，无越界文件 |
| 2 | fusions.json 与附录 D 逐条核对（配方组合/产物/成本全键） | **PASS** | 评审员程序化比对（非抽样）：15/15 行的 a/b/result 三键与附录 D #1~#15 的材料 A/材料 B/产物**逐一对应**（拼音 id → weapons.json 中文名反查全对，含「迫击·悬顶=pojixuanding」「战壕清扫=zhanhaoqingxiao」等易错项）；产物稀有度与附录「产出稀有」列全对（2 蓝/1 绿/12 橙）；id 全部存在于 weapons.json；无重复对。`test_forge.gd:119-144` 另将 15 条钉死防漂移 |
| 3 | 裁定③：craft_x 进度上报接到 codex_system | **FAIL** | 全库 grep `count_craft`：仅 `core/meta/codex_system.gd:192`（定义）与 `tests/unit/test_codex_system.gd:196`（T20 自测）；`ui/forge.gd:83-105` `_on_fuse_pressed` 成功路径无任何 CodexSystem 调用 → Important-1 |
| 4 | T20 披露「craft_x 占位待 T25」被真实接线取代 | **FAIL** | `core/meta/codex_system.gd:13` 注释「crafts_total ← count_craft()（T25 熔铸台接线占位，当前无调用方=恒 0）」与 `:191`「本卡占位接口，无调用方」在 T25 合入后**仍然为真**——占位未被取代 → Important-1 |
| 5 | 4 把★熔铸限定武器产出路径存在 | **PASS** | fusions.json #4/#5/#8/#13 四条配方产物 = 雷神之锤/斩舰刀/星陨炮/湮灭核心（附录 D ★标记一致）；★永不在掉落池（`game_db.gd:184` weapons 排除 locked + `codex_system.gd:170-172` `_grant_if_poolable` 对 forge_only 不回池）但可装备：`game_db.gd:216-219` `get_weapon` 缺池回落 weapons_all → `ui/forge.gd:119` `rig.equip` 可落槽；UI 展示同回落（`ui/forge.gd:190-193`）；配方命中不要求产物在池（`forge_logic.gd:118-124` 只查 find_recipe）——闭环成立 |
| 6 | forge_only 排除不被破坏 | **PASS** | codex_system.gd / game_db.gd 零改动（本分支 10 文件不含）；T20 测试套件全绿复跑；`test_forge.gd:166-170`（FUSION_ONLY 恰为 4★）+ `:241-247`（升级候选排除★）双断言 |
| 7 | SALT_FORGE 新盐 + forge_upgrades 新字段 | **PASS（附 Minor-3）** | `autoload/run_state.gd:33` `const SALT_FORGE := "forge"`（常量）；`:57` 字段声明；`:80` start_run 重置。正式路径唯一派生点 `floor_scene.gd:1159` 用常量（RngSvc.stream 种子含 floor_idx，每层异序列、每层恰 1 商店房→每层恰 1 次派生，无同盐多处派生）。Minor：`forge_logic.gd:158` 兜底路径调用点字面量 `"forge"` |
| 8 | 熔铸台挂载模板化预留 | **PASS** | `floor_scene.gd:1153-1154` 注释明示「每层固定 1 台（GDD §8.3/§9.1 每层恰 1 商店房 → 常量选型挂商店房，数据驱动模板字段由后续卡扩 schema）」——已知披露项确认有注释承接 |
| 9 | 35 例测试断言真实性 | **PASS** | 见第四节测试质量 |
| 10 | 全局约束 ①~⑥ | **PASS** | 见第四节 |
| 11 | 移交项：召唤物跨房间残留 3 行收口 | **未包含（Important-2 标注）** | 分支唯一功能提交 b331bce 十文件无召唤物改动；`floor_scene.gd:788-790` ShieldSpirit 重接循环处未为 "summons" 组补同款收口（T8 评审 Minor① 指明的约 3 行位置） |

---

## 三、质量维度发现

### Important-1：craft_x 进度上报未接线（规格核对点 3/4，可 1 行修复）

- **证据**：`ui/forge.gd:83-105`（`_on_fuse_pressed` 全文——预览门控→扣费→fuse→计数 upgrade→`_apply_result`，无 CodexSystem 触达）；全库 grep `count_craft` 仅定义处与 T20 自测；`core/meta/codex_system.gd:191-194` 占位注释在 T25 合入后仍属实。
- **影响**：`data/unlock_tasks.json` 5 条 craft_x 任务——`leishenzhichui`(goal 6, :183)、`xingyunpao`(goal 8, :147)、`zhanjiandao`(goal 10, :187)、`yamiehexin`(goal 12, :195)、`yaniemhaojiao`(goal 10, :143)——`crafts_total` 恒 0，**图鉴 5 项永不解锁**（含裁定③点名的 4 把★限定；湮灭号角还叠加「解锁回池」路径死锁）。附录 K 成就侧同源计数（`forge_smith` 熔铸匠）也依赖此线。
- **修复建议**：`ui/forge.gd` `_on_fuse_pressed` 成功路径（`_apply_result(String(out["id"]))` 之前/后）+1 行 `CodexSystem.count_craft()`——先例为 `core/interact/shop.gd:167/188/220` 的 `CodexSystem.count_buy()` 直调（ui 层直引 autoload 同风格，`ui/forge.gd:207` 已直引 RunState）。顺带把 `codex_system.gd:13`/`:191` 的「无调用方=恒 0」注释改真。测试：UI 侧补 1 例直调 `_on_fuse_pressed` 后断言 `CodexSystem.counters.crafts_total` 递增（最小 goal 6，单次 +1 不会误触发解锁，无档副作用风险）。

### Important-2（标注性缺口，按评审指令不必实现）：移交项「召唤物跨房间残留 3 行收口」未包含

- **证据**：`docs/superpowers/reports/m2-progress.md:59`（承接卡 T22/T25）；本分支变更 10 文件无 `core/player/skills/turret.gd`/summons 相关改动；`core/rooms/floor_scene.gd:788-790` 的 ShieldSpirit 重接循环仍未覆盖 "summons" 组。
- **处理建议**：移交下一张触碰 floor_scene.gd 的卡（或 T33 门禁前卫生卡），在 `_wire_room_combat` 循环处为 summons 组补同款 combat 重接（约 3 行，T8 评审已给方案）。

### Minor-1：熔铸产物属性继承规则未实现且未披露

- **规格**：GDD §8.3（design 文档 :183）「通用升级（同稀有度任意两把 → +1 稀有度的随机武器，**蓝耗取高者**，每局限 2 次）」+ 附录 D 尾注「熔铸产物继承：蓝耗取两材料较高者；元素附魔取 B 材料」。
- **实现**：`ui/forge.gd:111-121` `_apply_result` 直接 `rig.equip(weapon_id)` 装表行（`weapon_rig.gd:32-33` equip 内部取 `GameDB.get_weapon` 原行），产物的 `energy_cost`/`element` 均用表值，不做材料合成。weapons.json 字段就绪（115 把中 99 把 energy_cost>0、29 把 element≠none），影响真实——例如测试自用的真实绿对 双子星(energy_cost 2) + 蜂刺(1) 升级出的蓝武，GDD 口径应蓝耗 2，现为表值任意。
- **定性**：`ui/forge.gd:8-10` 头注释披露了「M1 简化（披露）：无背包……」，但**未披露继承规则缺失**。评审指令的附录 D 核对范围（配方组合/产物/成本）不含继承键，故记 Minor；若控制器裁定继承为硬规格，请升级处理。
- **修复建议**：equip 后对 `rig.slots[0]` 行覆写 `energy_cost = max(材料A, 材料B)`、`element = 材料B.element`（槽存整行 Dictionary 可直改，或扩 `WeaponRig.equip` 接受行覆盖）；若归后续武器实例化卡，至少在 forge.gd 头注释补披露并登记移交表。

### Minor-2：费用公式与 GDD 区间偏离，书面裁定缺档

- `forge_logic.gd:10-11` 注释披露「GDD §8.3『40~80 金』为早期区间口径，本卡按控制器规格固定公式落地」，公式 = 较高稀有度 `ShopLogic.BASE_PRICES`（附录 H 锚点中值）×1.5 取整到 5 → 实际区间 **30~390**（20→30/42→65/85→130/155→235/260→390，`test_forge.gd:301-306` 逐值钉死）。
- 但 `m2-progress.md` 裁定栏（1~11 条）**无此裁定记录**，「控制器规格」无档可查。公式本身与既有经济自洽（A1 买绿 42 vs 熔两白 30；A3 橙 665 vs 熔两橙 390），GDD 区间在 5 稀有度体系下也无法逐级落位；建议补记裁定入 m2-progress.md（或按 GDD 校正），防后续卡/门禁质疑。

### Minor-3：`forge_logic.gd:158` 调用点盐字面量

- `found.call("stream", "forge")` 是全库唯一非 `RunState.SALT_*` 常量形式的盐实参（其余调用点 shrine.gd:88 / shop.gd:240 / floor_scene.gd:234-236,1159 / inter_floor.gd:70 全用常量；frost_widow.gd:104-105 用本类常量）。注释自认「盐字面量同 RunState.SALT_FORGE("forge")」并援引 ShopLogic 习语——但 ShopLogic 先例（shop_logic.gd:129）只是按名寻址 autoload，**并无盐字面量先例**。
- 风险低（`--script` 模式兜底路径；正式局 floor_scene 必注入 rng、测试注入 rng，均不可达），但违反全局约束①字面（禁调用点字面量），且 SALT_FORGE 改值时此处会静默漂移。
- **修复建议**：改为 `found.call("stream", String(found.get("SALT_FORGE")))`（按名读常量），或抽本类 `const _SALT_FORGE_FALLBACK := "forge"` 并加与 `RunState.SALT_FORGE` 的一致性测试。

### Minor-4：`test_run_state.gd` 未补 forge_upgrades 重置断言

- `run_state.gd:57/:80` 新增字段与 start_run 重置，但 `tests/unit/test_run_state.gd:12-41` `test_start_run_resets_all_fields` 的污染/断言清单未含 `forge_upgrades`（对照：T19 的 `star_spring_used` :25/:39 有）。跨局残留计数会突破「每局限 2 次」。2 行补齐。

---

## 四、测试质量与全局约束核验

### 测试质量（test_forge.gd，35 例，逐类核验非同义反复）

- **数据一致性（6 例）**：15 行计数 / a-b-result schema / **附录 D 15 条硬编码钉死**（expected 与 json 双向夹逼：15 行 + 无重复对 + 15 条全在 = 集合相等）/ id 全存在（get_weapon 回落 weapons_all，覆盖 locked 材料）/ 配方对唯一 / FUSION_ONLY 恰 4★。满足「data/*.json 改动须附分布/一致性测试」。
- **fuse fail-closed（7 例）**：配方命中两种顺序等价 / 15 条全命中（全表池）/ 同名拒绝 / 未知与空 id 拒绝 / 稀有度不同返回空 / **locked 材料不在掉落池拒绝 + 换全量表对照命中**（:214-221，双语义断言）/ 桶空、顶稀有返回空。
- **升级掷签（3 例）**：同种子**探针独立复算**期望值（:224-232，非复读实现）/ 同种子确定性 / ★排除后桶空返回空。
- **preview（4 例）**：配方确切产物 / 升级只给目标稀有度不掷签（断言无 id 键）/ none 三态 / **preview 与 fuse 同源桶空一致性**（:289-296，掉落池 none vs 全量表 upgrade 对照——「可预览、熔铸却失败」的付费陷阱防回归）。
- **cost（3 例）**：五稀有度逐值（30/65/130/235/390）/ 高稀有度取档 / 未知稀有度防御 common。
- **UI 集成（12 例）**：headless 实例化 forge.tscn + 真实 Player/WeaponRig——开层快照（双槽名/金币）/ 预览与费用文案 / 配方熔铸端到端（扣费 65 + 产物入槽 0 + 副槽清空 + 指针复位 + 计数不增）/ 通用升级端到端（真实绿对 → 计数 +1 → 产物 rare）/ 上限第 3 次拒绝且不扣费 / 配方不受上限约束 / 金币不足拒绝不扣费 / 空槽禁熔 / Esc 与按钮关店 / interact 接线。
- **覆盖缺口**：craft_x 上报（归 Important-1，随修复补 1 例）；★产物端到端装备（rig.equip 走 weapons_all 回落）无 UI 级直测——低风险，顺带可补。

### 全局约束

- **①RNG/盐**：SALT_FORGE 为 RunState 常量；正式路径每层恰 1 次派生（每层恰 1 商店房 + floor_idx 入种），forge.rng 注入后 `_default_rng` 不可达；fuse 升级路径才消费 rng、配方路径不消费（注释声明且 preview 无掷签测试佐证）。唯一瑕疵 = Minor-3 字面量。
- **②热路径**：新代码无 `_process`/`_physics_process`；`_unhandled_input`（ui/forge.gd:68-77）仅键码判断 + 面板可见早退，零字符串拼接/零 Dictionary 新建；`_default_rng` 的字符串散列种子仅在无树兜底路径。
- **③场景零硬编码玩法数值**：forge.tscn 仅布局/字号/中文文案（半径 20 为交互碰撞体，同 Shop 先例）；全部玩法数值走 fusions.json / ShopLogic.BASE_PRICES / RARITIES 常量；费用公式常量 `COST_MULT`/`ROUND_TO` 在 logic 层（同 ShopLogic.FLOOR_MULT 习语）。
- **④代码英文/文案中文**：标识符全英文，注释/UI 文案中文（「熔铸台」「无法熔铸（双槽均需武器）」等），与仓库惯例一致。
- **⑤.uid**：`forge_logic.gd.uid`/`ui/forge.gd.uid`/`test_forge.gd.uid` 三件随提交；forge.tscn 无 uid= 头与 shop.tscn 先例一致（tscn 无 .uid 文件先例）。
- **⑥data 一致性测试**：见上「数据一致性」。
- **挂载方式**：常量选型 + 注释披露模板化路径（规格核对点 8），`Vector2(0, 56)` 偏移与同房商店(-72,0)/饮料机(72,0)/雕像(±72,-56) 同风格字面量——属既有披露口径，非新发现。

---

## 五、测试实测记录

| 项 | 结果 |
|---|---|
| `python -c "import PIL"` | 通过（PATH 正常） |
| `godot --headless --path . --import` | 通过（无报错） |
| GdUnit4 全量 `-a res://tests --ignoreHeadlessMode` | **1132/1132 通过**，67/67 套件，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，4min22s，exit 0 |
| test_forge.gd | 35 例全绿（1132 = main 基线 1097 + 35，精确吻合；实现者自报 1011 为当时基线口径） |
| 与自报一致性 | 全量绿一致；唯自述未提 craft_x 未接线（Important-1） |
| 复跑时点工作树 | **干净（= HEAD c0ba77a）**：复跑启动前 `git status` 零修改，1132 计数与 35 例版本精确吻合佐证。复跑结束后工作树出现**实现者并行的未提交修复**（`core/meta/forge_logic.gd`/`tests/unit/test_forge.gd` M，+224/−21：fusion_only 权威数据源化、产物蓝耗/元素继承、缓存哨兵、+10 新测试至 45 例）——**不在本评审对象内**（本报告评审对象严格 = 提交 `b331bce`+`c0ba77a`），其内容与本报告 Minor-1/Minor-3 方向吻合，属实现者后续工作，本评审不予置评 |

---

## 六、修复建议（按优先级）

1. **【合并前·Important-1，约 1 行 + 1 测试】** `ui/forge.gd` `_on_fuse_pressed` 成功路径补 `CodexSystem.count_craft()`（先例 `core/interact/shop.gd:167`）；改真 `codex_system.gd:13/:191` 占位注释；UI 侧补 crafts_total 递增断言 1 例。
2. **【移交标注·Important-2】** 召唤物残留 3 行收口重新指卡（下一张 floor_scene.gd 卡或 T33 门禁前卫生卡），落点 `floor_scene.gd:788-790`。
3. **【下卡顺带·Minor-1】** 产物蓝耗/元素继承：equip 后覆写槽行两字段，或头注释补披露 + 移交表登记。
4. **【编排者·Minor-2】** 熔铸费用公式（附录 H 中值 ×1.5 → 30~390 vs GDD 40~80）补书面裁定入 m2-progress.md。
5. **【可选·Minor-3】** `forge_logic.gd:158` 盐字面量改 `found.get("SALT_FORGE")` 读常量。
6. **【可选·Minor-4】** `test_run_state.gd` 重置断言补 `forge_upgrades` 污染/清零 2 行。

---

## 七、规格符合度总览

**PASS 9 / 11 项**（核对点 3、4 因同一缺口 FAIL → Important-1；移交项按指令记 Important-2 标注）。附录 D 数据转录零误差、4★产出路径与 forge_only 排除闭环完好、35 例测试断言真实全绿、全局约束合规；阻塞项仅 craft_x 上报一处（1 行修复），修复后本卡即达 APPROVED 口径。

---

# Fix Round 1

**执行者：** m2-t25 实现者
**分支 HEAD：** `78bb9e8`
**父链：** `78bb9e8`（craft_x + 盐常量）→ `0e25990`（修复轮①：裁定⑭⑮⑯ + Minor）→ `faa2bc9`（merge main `2c34f30`）→ `5b1061b`（评审）→ `c0ba77a`（merge main `89b5cfa`）→ `b331bce`（实现提交）
**结论：** 评审 `5b1061b` 的 Important-1 / Minor-1 / Minor-3 已修，Important-2 / Minor-2 / Minor-4 按评审指令移交；裁定⑭⑮⑯ 全部落地。全量 **1145/1145 绿**。
**未合入 main** —— 原因见 §9，需编排者确认。

---

## 0. 前置披露：存在两份不一致的评审报告

控制器提示词指定我读 `.superpowers/sdd/2026-08-30-m2-full-content/task-25-report.md` 的 `## Review Round 1`。但分支内 `5b1061b` 提交的 `docs/superpowers/reports/task-25-report.md` 是**另一份评审**，两者发现项几乎不重叠：

| | 副本 A（`.superpowers/sdd/...`，提示词指定） | 副本 B（`5b1061b`，分支内） |
|---|---|---|
| 结论 | Approved with notes | **NEEDS FIXES** |
| 条目 | Important ×3 + Minor ×8 | **Important ×2 + Minor ×4** |
| 关键项 | I-1 FUSION_ONLY 硬编码 / I-2 可达性 / I-3 产物继承 | **Important-1 craft_x 未接线** / Important-2 召唤物残留 |
| 在仓库内可检出复核 | 否（`.superpowers/` 不入版本库） | **是** |
| 被台账引用 | 否 | **是**（`m2-progress.md:59` 引用 `5b1061b`） |

**本轮以副本 B（`5b1061b`）为准**，理由：可检出复核、台账引用它、且它点出了真正的合并阻塞项（craft_x）。两份的重叠项（产物继承）处置一致。

---

## 1. merge main 实况（裁定⑮ 前置步骤）

评审已用 `git merge-tree --write-tree` 预判无冲突，实测确认：

| 步骤 | 结果 |
|---|---|
| `git merge main`（main 当时 `89b5cfa`） | 提交 `c0ba77a`，双亲 `b331bce` + `89b5cfa` |
| 冲突 | **0**（仅 `floor_scene.gd` auto-merge，改动区不重叠） |
| 合并树校验 | HEAD tree = `61d150d5…`，与评审 `merge-tree` 试算输出**逐字节一致** |
| merge 后基线全量 | **1132/1132**，67 套件，0 errors / 0 failures，`test_forge` 35/35 |

> 环境坑：首次 `git merge` 因编辑器等待被工具超时 SIGTERM，但合并提交已正确落盘，仅残留 `MERGE_HEAD`/`MERGE_MODE`/`MERGE_MSG`/`AUTO_MERGE` 四个状态文件未清理（校验 `HEAD^{tree}` == `AUTO_MERGE` 后确认合并实质完成），已手工清除。后续 merge 一律加 `GIT_EDITOR=true --no-edit < /dev/null`。

期间 main 又前进两笔（`c84bf88` 台账重写、`2c34f30` wave-1 结果 + 裁定 15–18），均为 docs-only，已再次 merge（`faa2bc9`，无冲突）。分支现与 main 完全同步（`git log m2-t25..main` 为空）。

---

## 2. 裁定⑭（台账重编为 **15**）：`FUSION_ONLY` 改为数据驱动

**落地方式：**

- `core/meta/forge_logic.gd` 新增 `const UNLOCK_TASKS_PATH := "res://data/unlock_tasks.json"`，新增 `_read_forge_only_ids()` 直读 `forge_only:true` 条目（**不经 GameDB 装载**，同 `CodexSystem._load_tasks` 的 FileAccess 直读习语；缺文件/坏 JSON → `push_error` + 返回空数组，fail-soft）。
- 新增 `fusion_only()`（数据可用走数据，否则回落常量）与 `forge_only_from_data()`（纯数据侧，供测试比对）。
- `FUSION_ONLY` 常量**降级为兜底**，注释明示「非真相源」。
- `_candidates()` 的 `FUSION_ONLY.has(id)` 改为 `fusion_only().has(id)`。

**验证：**

- 新测试 `test_fusion_only_matches_unlock_tasks_forge_only_data` 双向钉死：数据侧集合与常量**规模相等 + 双向包含**。改数据不改常量（或反之）立刻 RED。
- `--script` 模式实测（`autoload GameDB present = false`）：`forge_only_from_data()` 正常返回 4 个 id，证明不依赖 autoload。

---

## 3. 裁定⑯（台账 **16**）：附录 D 产物继承

**落地方式：**

- 新增 `find_recipe_row(a, b) -> {result, mat_a, mat_b}`：`mat_a`/`mat_b` 是**配方表 a/b 键**对应的那两把，与调用方入参顺序无关；`find_recipe()` 改为委托它。
- 新增 `_inherit_stats(out, hit, pool)`：
  - `energy_cost = maxi(材料A.energy_cost, 材料B.energy_cost)`
  - `element = 材料B.element`（B = 配方表 `b` 键那把）
  - 材料行缺字段时回落 `0` / `"none"`（裁定「无元素时按常规回落」）
- `preview()` / `fuse()` 统一走新增的 `_recipe_result()`，**两处口径同源**（继承不会只出现在 fuse 里）。
- **只写返回副本，绝不回写 GameDB 表行**（继承是局内实例属性）。
- `ui/forge.gd` 新增 `_apply_inherited_stats()`：把继承值盖到**实际装备的槽行**上。关键陷阱——`WeaponRig.equip()` 存的是 GameDB 行**共享引用**（`slots[target] = w`），必须先 `duplicate()` 再改，直写会污染全量表。仅配方产物携带这两个键，通用升级产物沿用武器自身静表值（行为零变化）。

**验证（4 条新测试）：**

| 用例 | 断言 |
|---|---|
| `test_fuse_recipe_inherits_energy_cost_as_higher_of_materials` | 铁剑(ec0)+燃烧瓶(ec2) → 烈焰剑（静表 ec0）→ **ec=2** |
| `test_fuse_recipe_inherits_element_from_recipe_b_slot` | 正序 / 逆序两次调用 element 都 = `fire`（B=燃烧瓶），且 energy_cost 相等 |
| `test_fuse_recipe_inherited_energy_cost_overrides_static_row` | 光剑(0)+时间沙漏(8) → 湮灭核心（静表 5）→ **ec=8** |
| `test_fuse_recipe_inheritance_falls_back_when_fields_absent` | 材料行无字段 → ec=0 / element=`none` |
| `test_preview_recipe_reports_inherited_stats` | preview 与 fuse 报同一组继承值 |
| `test_fuse_recipe_does_not_mutate_global_weapon_table` | 熔铸后 `GameDB.get_weapon("lieyanjian")` ec/element 不变 |
| `test_ui_recipe_fuse_applies_inherited_stats_to_equipped_slot` | `rig.slots[0]` ec=2 / element=fire，且 GameDB 静表仍 ec=0 |

**⚠️ 口径歧义（提请编排者复核）：** 控制器提示词写「元素附魔取 B 材料（**第二个槽位**）」，评审 I-3 则写明「B = 配方表 `b` 键对应的那把」。二者在「玩家换槽顺序」时会给出不同结果。**本轮按评审口径实现（配方表 b）**，理由：① `find_recipe` 已做 a/b 无序匹配，「投入顺序敏感」会破坏熔铸的顺序无感性；② 附录 D 表格本身有 A/B 材料列，「B 材料」指表列更贴合原文。测试 `test_fuse_recipe_inherits_element_from_recipe_b_slot` 已把此语义钉死（逆序投入仍取 fire）。若编排者要改回「玩家槽位 1」，改 `_inherit_stats` 一处即可，该测试会 RED。

> 补充：当前数据下两种口径**结果完全一致**——15 条配方中产物带原生元素的 5 条（烈焰剑/冰霜巨剑/毒牙短刃/雷神之锤/电磁轨道），其 B 材料元素恰好等于产物静表元素，其余 10 条两边都是 `none`。故无产物被剥掉原生元素。

15 条配方继承后的实测值（供 T28 Balance Bot 参考）：

| # | 产物 | 静表 ec | 继承 ec | 继承 element |
|---|---|---|---|---|
| 1 | 烈焰剑 | 0 | **2** | fire |
| 2 | 冰霜巨剑 | 0 | **3** | ice |
| 3 | 毒牙短刃 | 0 | **2** | poison |
| 4 | ★雷神之锤 | 0 | **2** | shock |
| 5 | ★斩舰刀 | 0 | **7** | none |
| 6 | 终焉急促 | 3 | **2** | none |
| 7 | 裁决 | 4 | **2** | none |
| 8 | ★星陨炮 | 8 | **3** | none |
| 9 | 彩虹发生器 | 8 | 8 | none |
| 10 | 终焉之杖 | 9 | **5** | none |
| 11 | 贯星弓 | 5 | **3** | none |
| 12 | 星核榴弹 | 7 | **4** | none |
| 13 | ★湮灭核心 | 5 | **8** | none |
| 14 | 湮灭号角 | 6 | **3** | none |
| 15 | 电磁轨道 | 6 | **3** | shock |

注：继承会**下调**多数橙武的蓝耗（如星陨炮 8→3、终焉之杖 9→5）。这是 GDD「取两材料较高者」的直接后果（材料多为低蓝耗的蓝/绿武），不是笔误——若 T28 认为橙武蓝耗被削过头，应改 GDD 规则而非本实现。

---

## 4. 裁定⑮：merge 后可达性复测

**问题背景：** 评审 I-2（副本 A）实测「掉落池只剩 66 把、紫橙 0、8/15 配方被 locked 材料卡死」，并推测「那是基于过旧基线 `18deb90`，T20 已合入，解锁引擎会动态回填掉落池」。

**本轮实测（临时探针，跑完即删，未进版本库）：**

| 场景 | 掉落池 | 配方可达 | ★可得 | 通用升级桶（排除★后） |
|---|---|---|---|---|
| 评审基线 `18deb90`（新档） | 66（白9/绿21/蓝36/紫0/橙0） | 7/15 | 1/4 | 白→绿 21 / 绿→蓝 36 / **蓝→紫 0 / 紫→橙 0** |
| **merge main 后 · 新档**（`unlocked_weapons=[]`） | **66（白9/绿21/蓝36/紫0/橙0）** | **7/15** | **1/4** | 白→绿 21 / 绿→蓝 36 / **蓝→紫 0 / 紫→橙 0** |
| 解锁稳态（非★ locked 45 把全解锁回池，★ 4 把按 J.6 永不回池） | 111（白9/绿21/蓝36/紫33/橙12） | **15/15** | **4/4** | 白→绿 21 / 绿→蓝 36 / **蓝→紫 33 / 紫→橙 12** |

**结论：merge main 对新档可达性零改变。** 评审推测的「T20 会回填掉落池」在新档**不成立**：`SaveSystem.unlocked_weapons` 默认 `[]`（`save_system.gd:45`），`CodexSystem._ready` 只对**已解锁**的武器调 `grant_to_pool`，新档无解锁 → `GameDB.weapons` 依旧 66。T20 的解锁引擎是**按存档进度**回填，不是启动期全量回填。

**但这仍是预期行为（进度门），不改代码**，依据：

1. 49 把 locked **每一把都有独立解锁任务**（49 任务 ↔ 49 locked，无孤儿），非★ 45 把解锁后经 `grant_to_pool` 回池 → 配方逐级解锁 → 稳态 15/15、★4/4 全可达。
2. 看似会「链条断死」的 #12→星核榴弹→#5（斩舰刀）：星核榴弹的解锁任务是 `resonate_x goal=900`，**独立于熔铸**，链条可解。
3. 唯一真正死锁的是 **craft_x 任务本身**——熔铸计数此前恒 0，5 条 craft_x（湮灭号角 10 / ★星陨炮 8 / ★雷神之锤 6 / ★斩舰刀 10 / ★湮灭核心 12）永不解锁。这正是评审 Important-1，**已在本轮修掉**（见 §6），修完 craft_x 线即可推进。

**移交 T33 预检：** 新档开局「8/15 配方不可达、3/4 ★不可得、蓝→紫桶空」是**进度门**而非缺陷，T28 Balance Bot / 试玩员不得按回归 bug 报。

按裁定⑮，merge 后无测试因可达性翻转（`test_preview_upgrade_empty_bucket_is_none`、`test_fuse_locked_material_not_in_drop_pool_rejected` 仍绿），**无需修正断言**。

---

## 5. Minor 修复清单

| 项 | 处置 | 说明 |
|---|---|---|
| M-1 缓存哨兵 `is_empty()` → error 风暴 | **已修** | `_recipes_loaded` / `_forge_only_loaded` 布尔哨兵（装载一次即置位，与结果是否为空无关）；新增 `reset_caches()` 供测试重置 |
| M-2 locked 产物 `name` 退化成拼音 id | **已修** | 新增 `_product_row()`：pool 缺则回落 `weapons_all` 取展示名（用 `ShopLogic._weapons` 习语，无树时手动装载，不裸引 autoload）。测试 `test_fuse_locked_product_name_falls_back_to_weapons_all`：星轨+迫击·悬顶 → ★星陨炮，`name` = `星陨炮` 而非 `xingyunpao` |
| M-3 两条 oracle-by-reimplementation | **已修** | ① `test_fuse_generic_upgrade_picks_next_rarity` 改为「独立算出的候选集 == `["ua","ub"]`」+ **golden 值 `ub`**（注：评审猜的 `ua` 是错的，实测种子 `20260828` 首抽索引 = 1）；② `test_fusion_only_marks_exactly_the_four_star_weapons` 补反向覆盖（4 个★名字各自都被命中、名字互不重复） |
| 评审 Minor-3 盐字面量 | **已修** | `forge_logic.gd` 抽 `const SALT_FORGE := "forge"` + `test_forge_fallback_salt_matches_run_state_constant` 钉死 == `RunState.SALT_FORGE`。**注**：评审建议的「按名读 `found.get("SALT_FORGE")`」实测不可行（Godot 4.7.2 `Object.get()` 读脚本 const 返回 `null`），故用评审给的备选方案 |

---

## 6. Important-1：craft_x 接线（评审点名的合并阻塞项，提示词未提及）

**问题：** `CodexSystem.count_craft()`（T20 留的占位接口）**无任何调用方**。`ui/forge.gd` 熔铸成功不上报 → 5 条 craft_x 任务进度恒 0、永不解锁（含 4 把★图鉴项），附录 K 成就 `forge_smith` 同源失效。

**处置：**

- `ui/forge.gd` `_on_fuse_pressed` 成功路径补 `CodexSystem.count_craft()`（先例：`core/interact/shop.gd:167/188/220` 的 `CodexSystem.count_buy()`；本文件 `:207` 本就直引 `RunState`）。**配方熔铸与通用升级各计 1 次**；被拒绝的熔铸（金币不足 / 超上限 / 空槽 / 桶空）不计数。
- 改真 `core/meta/codex_system.gd` 两处「无调用方=恒 0」注释（越界 2 行，**仅注释**，见 §10）。
- 测试：`test_ui_fuse_reports_craft_to_codex_system`（递增）+ `test_ui_rejected_fuse_does_not_report_craft`（拒绝不计数）。
- **污染防护**：新增 `before_test()`/`after_test()` 逐例还原 `CodexSystem.counters["crafts_total"]`。必要——一旦跨套件累计到 craft_x 最小 **非★** goal（湮灭号角 10），会真的触发解锁 → `grant_to_pool` 改全局掉落池，污染其它套件。

---

## 7. 未修项 / 移交

| 项 | 归属 | 理由 |
|---|---|---|
| 评审 Important-2 召唤物跨房间残留 3 行收口 | 移交（下一张触碰 `floor_scene.gd` 的卡 / T33 门禁前卫生卡） | 评审原文「按评审指令不必实现」；落点 `floor_scene.gd:788-790` |
| 评审 Minor-2 熔铸费用公式缺书面裁定 | 编排者 | 台账已记为**裁定 17**（30~390 阶梯，T28 校准点复核）——本次无需再动 |
| 评审 Minor-4 `test_run_state.gd` 未补 `forge_upgrades` 重置断言 | 移交 T25 后续 / 编排者 | `tests/unit/test_run_state.gd` **非本卡所有权文件**；`start_run()` 已有重置（`run_state.gd:80`），属测试覆盖缺口而非 bug，风险低 |
| 副本 A 的 M-4（UI 用例数笔误 12→实为 10） | 已随本轮覆盖（现 48 例） | 无需单独处理 |
| 副本 A 的 M-5（RED 证据不可复现） | 本轮已补 | 见 §8，附真实失败输出 |
| 副本 A 的 M-6（走查证据未落盘） | 部分解决 | 可达性探针结论已写进本报告 §4 并附完整数据；探针本身为临时文件（评审同一做法）。若要固化成 `tests/scenes/` 用例，建议单独立卡 |
| 副本 A 的 M-7（`rig.slot` 直写缺接缝） | 移交 | 本轮新增的 `_apply_inherited_stats` 又多了一处 `rig.slots[0]` 直写（已在代码注释披露）。建议 `WeaponRig` 补 `select_slot(i)` / `equip_row(row)` 两个接缝后统一收敛，属 `weapon_rig.gd` 所有权范围 |

---

## 8. 测试与 TDD 证据

### 命令（PATH 前置系统 Python，否则 `test_art_pipeline` 报 2 个假失败）

```
export PATH="/c/Program Files/Python312:$PATH"   # PIL 12.3.0
python -c "import PIL"                            # 必须无报错
godot --headless --path . --import
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

### TDD RED 证据（修复轮①，裁定⑯）

先只实现裁定⑭ + M-1 + M-2（`_inherit_stats` 留空桩），继承断言真实转红：

```
res://tests/unit/test_forge.gd > test_fuse_recipe_inherits_energy_cost_as_higher_of_materials FAILED 94ms
  Report:
  Expecting:
 2
 but was
 -1    at 'test_fuse_recipe_inherits_energy_cost_as_higher_of_materials' in res://tests/unit/test_forge.gd:235

Statistics: 12 test cases | 0 errors | 1 failures | ...
```

（gdUnit4 6.2.1 套件内 fail-fast，首个失败即停，非发现截断。）同轮裁定⑭ 的三条断言已先转绿，证明红点确实只在继承规则上。填入 `_inherit_stats` 后转绿。

### 最终数字

| 指标 | 结果 |
|---|---|
| 全量用例 | **1145 / 1145** |
| 测试套件 | **67 / 67** |
| errors / failures / flaky / skipped / orphans | **0 / 0 / 0 / 0 / 0** |
| `test_forge` | **48 / 48**（评审时 35 → 修复轮① 45 → 修复轮② 48） |
| 总耗时 | 4min 46s，exit 0 |
| XML 交叉核对 | `reports/report_30/results.xml`：`SUITE test_forge tests=48`，各套件 `tests` 求和 = 1145 |

基线演进：`b331bce` 自述 1011（当时基线）→ merge main 后 **1132** → 本轮 +13 → **1145**。

### 附加验证

- `--script` 模式（无 autoload，`autoload GameDB present = false`）：`recipes()` 15、`fusion_only()` 4、`fuse()`/`preview()`/`fuse_cost()` 全部正常，继承值与有 autoload 时一致。
- 工作树在最终全量跑完后 `git status --short` **全干净**。

---

## 9. 合并待确认（未执行 `git merge --no-ff m2-t25`）

提示词步骤 6 要求合入 main，**本轮未执行**，原因是执行过程中发现编排者台账的新指令：

> `m2-progress.md:123`（裁定 18）：「…一存活代理在 `.worktrees/m2-t25` 自主执行修复轮…处理：不派对抗代理，监控其产出；其裁定编号以台账为准重编。**若其在 main 上自行 merge 即回滚并接管**。」

合入 main 属共享状态变更（T28 依赖 T25，且编排者明确预留了回滚意图），故**停在分支上等待确认**。分支已与 main 完全同步（`git log m2-t25..main` 为空），确认后一条命令即可完成：

```
cd /d/workspace/thomas && git checkout main && git merge --no-ff m2-t25
```

合入前置条件已全部满足：全量 1145/1145 绿、评审 Important-1 已修、无越界代码改动。

---

## 10. 越界改动披露

| 文件 | 改动 | 理由 |
|---|---|---|
| `core/meta/codex_system.gd` | **2 行注释**（`:13`、`:191`） | Important-1 要求「把占位注释改真」——原文「T25 熔铸台接线占位，当前无调用方=恒 0」在接线后已失实。仅注释，零代码改动 |
| `docs/superpowers/reports/m2-progress.md` | 台账更新 | 提示词步骤 8 指定 |
| `docs/superpowers/reports/task-25-report.md` | 追加本 Fix Round 1 | 与提示词指定的 `.superpowers/sdd/...` 副本同步，避免两份报告分叉 |

本卡所有权文件内的改动：`core/meta/forge_logic.gd`、`ui/forge.gd`、`tests/unit/test_forge.gd`。未改 `data/fusions.json`、`ui/forge.tscn`、`core/rooms/floor_scene.gd`、`autoload/run_state.gd`（本轮无需求）。

---

**Fix Round 1 结束。分支 `m2-t25` @ `78bb9e8`，全量 1145/1145 绿，等编排者确认合入。**
