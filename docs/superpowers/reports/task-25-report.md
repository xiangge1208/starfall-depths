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
