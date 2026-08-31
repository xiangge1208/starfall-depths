# Task 37 报告：全图集合并 + A2 光圈批处理（F2 draw call 回预算）

- 卡：M2 T37（§18.3 F2 draw call 超标 ~8% 修复，承接裁定㉓ / T29 遗留移交项 3）
- 分支：`m2-t37`（worktree `D:\workspace\thomas\.worktrees\m2-t37`，基线 a177691）
- 日期：2026-08-31
- 证据文件：本目录 `m2_perf_before_t37.json` / `m2_perf_after_t37.json`（探针窗口运行原始输出 `user://m2_perf.json` 另存）

## 一、结论

**探针 F2 draw call：avg 157.2（超 150 预算 ~4.8%，本轮基线复现 FAIL）→ avg 105.6 / max 145（PASS，余量 29.6%）。三层全 PASS，max 样本首次全部落入 150 线内（156/145/147）。** 全量 gdUnit **1351/1351 绿（基线 1335 + 新增 16）**，0 orphans。

| 指标（窗口运行，vsync 关） | BEFORE（a177691） | AFTER（本卡） | 预算 |
|---|---|---|---|
| F1 draw avg / max | 123.7 / 202 | 106.2 / 156 | ≤150 |
| **F2 draw avg / max** | **157.2 / 279（FAIL）** | **105.6 / 145（PASS）** | ≤150 |
| F3 draw avg / max | 118.9 / 210 | 95.0 / 147 | ≤150 |
| F2 逻辑帧 avg | 0.0165 ms | 0.0136 ms | ≤6ms |
| F2 60fps 能力（合成） | 11.50 ms | 10.33 ms | ≤16.67ms |

（BEFORE/AFTER 同机同口径各跑一轮；F2 模板本轮已是 T26 落地后的 `combat_a2_01`，与 T29 报告的 a1 回落基线不同源但同样复现 FAIL。）

## 二、根因修正（实测归因，修正裁定㉓的剪影假设）

用临时归因场景（复用 `perf_probe` 构建体，40 敌满压 + 500 弹，窗口实测 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`）做了变量隔离矩阵（两轮，均值口径）：

| 配置 | draw avg | 结论 |
|---|---|---|
| F1 无 A2 fx | 108.9 | 基线 |
| F2 全特效（默认） | 148.9~154.6 | 与探针 FAIL 同构 |
| F2 光圈 PointLight2D 关闭 | 115.2~120.3 | **+33~+45 全部来自光圈** |
| F2 光圈在、`range_item_cull_mask=0`（无任何条目参与） | 108.8~117.5 | 光圈节点本身零成本 |
| F2 逐敌剪影 modulate 关闭（光圈在） | 156.2 | **modulate 无辜**（不裂批） |
| F2 全同贴图 + modulate / 全同贴图无 modulate | 171.4 / 160.8 | 贴图同质化不解决（反升） |
| F2 光圈收口专属位（仅地形面+敌人参与） | 109.9~119.3 | **= 无光圈基线，修复成立** |

**修正结论：F2 的 O(n) 增量不是"每敌剪影一次 draw"（modulate 写入不破坏批处理），而是光圈默认 `cull_mask=1` 使画布上全部条目（弹幕/伤害数字/FX 粒子/拾取…）参与逐项光照重渲，2D 批处理沿条目 lit/unlit 状态翻转碎裂 → O(穿越次数) 增量。** 部分排除（仅排敌人或仅排弹幕）无效（152.2 / 150.7），只有把参与集收口到低计数世界条目才归零——与"全图集"前提正交，两项修复叠加生效。

## 三、改动

### 1) 全图集合并（§18.3「全图集」前提落地）
- **`tools/gen_art_atlas.py`（新）**：additive/idempotent 生成器——扫描 `art/generated` 白名单目录（characters 非 sheet / enemies / projectiles / pickups / fx / weapons / ui/weapons，317 张）→ 确定性 shelf 装箱单页 512×512 + 2px 边缘外扩（防渗色）→ `atlas/atlas_page.png` + `atlas/atlas.json`（区域清单）。fail-closed：Pillow 缺失 / 单图 >128px / 装不进 1024 页 → hard fail。**排除**：`tiles/*`（make_tiled 依赖 texture_repeat，AtlasTexture 不支持平铺）、`*_sheet.png`（hframes/vframes 帧表寻址依赖整图）、`ui/` 其余大图（Control 消费）。
- **`tools/gen_placeholder_art.py`**：`main()` 在 m2 批次之后、prune 之前串联 `pack_atlas(OUT, add_spec=add)`（图集失败即中止，绝不带陈旧图集清理，产物入 SPEC 随 prune 白名单保留）；`--atlas` 窄通道（仅重打包，零源图触碰）；两个 scoped 入口后随源幂等重打包。**未裸跑 main()（裁定⑪）**，本卡产物由 `--atlas` 等价路径生成。
- **`core/art/art_atlas.gd`（新）**：运行时查询（清单惰性加载、AtlasTexture 备忘、JSON float→int 归一、区域越界拒用）；任何未命中（停用/无清单/不在表）返回 null → `ArtLookup.tex` 回落原逐文件路径（fail-closed，游戏表现零依赖图集存在）。
- **`core/art/art_lookup.gd`**：`tex()` 先查 `ArtAtlas.texture_for`；`make_tiled` 增加 AtlasTexture 拒用守卫（push_error + null，防排除表被破坏后平铺静默变形）。

### 2) A2 光圈批处理
- **`core/rooms/biome_fx.gd`**：新增 `LIT_ITEM_MASK := 2`；光圈 `range_item_cull_mask = LIT_ITEM_MASK`；`setup()` 把玩家外观 opt-in（光圈中心玩家亮度与既往一致）。
- **`core/art/art_lookup.gd`**：`make_sprite` / `make_tiled` / `dress_enemy_sprite` 产出的世界精灵 `light_mask = LIT_ITEM_MASK`（静态地形面/陈设/门/危险地块 + 敌人剪影）。高计数瞬态条目（弹幕/伤害数字/FX 粒子）不经这些工厂 → 留默认位 1，零逐项光照重渲。无光圈楼层（F1/F3/训练房）`light_mask` 无消费者，零影响。

### 3) 测试（TDD，RED 先行：两套件曾以编译失败/断言缺失确认 RED）
- **`tests/unit/test_art_atlas.gd`（新，12 例）**：清单/页存在与规格（幂次边长 ≤1024、padding≥1）；条目整数像素 + 含 padding 不重叠（占据栅格）；**像素恒等**（317 条目 × 全可见像素逐位比对，α=0 处不比——导入器 fix_alpha_border 域）；区域钉值（kuli_bug/bullet_enemy 字面量，防再打包漂移）；运行时接线（tex 命中返回共享同页 AtlasTexture、尺寸语义不变、敌人/弹/拾取/英雄同页）；排除契约（tiles/sheet 不入）；fail-closed 回落；生成器幂等（子进程跑两轮 `--root/--out` 重定向，atlas.json 逐字节一致，零仓库副作用）。
- **`tests/unit/test_biome_a2.gd`（+4 例）**：光圈 cull_mask = 专属位 2（≠默认 1）；`dress_enemy_sprite` / `make_tiled` / `make_sprite` 产出精灵 opt-in（批处理前提断言）；`setup()` 玩家外观 opt-in。

## 四、视觉偏差披露（有意，全部量化）

1. **图集边缘亚像素采样**：钉种子确定性 F2 截图（1440×810，冻结 AI/动画）before/after 逐像素 diff = **85 px / 1,166,400（0.007%）**，集中在暗色精灵最右列的 1 texel 采样翻转，最大通道差 73/255（同流程双跑对照 = 0 px，管线确定性成立）。逐精灵**可见像素（α>0）恒等已由单测全量钉死**；85 px 属区域 UV 在四边形右/下边缘的最近邻取整差异，肉眼不可辨。
2. **弹幕/伤害数字/FX 粒子不再被光圈照亮**（默认位 1）：光圈半径内的弹幕/飘字亮度不再 ×(1+1.2g) 提升。压测截图无弹幕，此项未入截图 diff；静态面 + 敌人剪影 + 玩家（公平性主体）保持真实光照，实测零成本。GDD §10 A2 的剪影公平性下限 0.4 由 modulate 曲线承担，不变。
3. α=0 像素 RGB 不再与源逐位一致（导入器 fix_alpha_border 抗黑边重写，两态同样不可见）。

## 五、探针测量口径说明（未改 perf_probe.gd，遵守约束 1）

- BEFORE/AFTER 均为窗口运行（Windows DisplayServer，vsync 关，探针内置双窗口 480+240 帧采样），取 `judge()` 平均值口径（T29 判定口径不变）。
- 归因矩阵与截图 diff 用**临时 scratch 场景**（已删，未入库），非探针改动；探针 F2 之外的观察项（objects/orphans）未复采，AFTER JSON 里数值与 BEFORE 同量级。

## 六、文件清单

新增：`core/art/art_atlas.gd(+.uid)`、`tools/gen_art_atlas.py`、`tests/unit/test_art_atlas.gd(+.uid)`、`art/generated/atlas/atlas_page.png(+.import)`、`art/generated/atlas/atlas.json`
修改：`core/art/art_lookup.gd`、`core/rooms/biome_fx.gd`、`tools/gen_placeholder_art.py`、`tests/unit/test_biome_a2.gd`
未触碰（约束 1/2 遵守）：`tests/scenes/perf_probe.gd`、inter_floor/player/shop_logic/scene_router/main_menu/drink_machine/pickup/run_root/weapon_rig 等禁改清单全绿。

## 七、遗留移交

1. **T34 真机复测**：本卡 GPU 侧仍未采（口径同 T29）；真机上 lit-mask 收口与图集共页的收益建议复验。
2. **T26 密房规模复验**：`densest_combat_id` 已自动选 `combat_a2_01/a3_08`；更密模板合入后重跑探针（预期 opt-in 光照 + 同页图集使增量保持平缓）。
3. **MANIFEST.md 未含图集行**：全量 `gen_placeholder_art.py main()` 下次运行时经 `add_spec` 自动入表（本卡未裸跑 main）；期间 `atlas/` 两文件不受 prune 影响（prune 仅在 main 成功路径运行）。
4. **AtlasTexture 与 SpriteFrames**：若未来引入 AnimatedSprite2D/SpriteFrames 资源，图集区域不适用其内建帧寻址，沿用 `*_sheet.png` 排除口径。
5. **抽检拾取物（pickup）在光圈内的 lit 状态**：pickups 经 `make_sprite` → opt-in（lit）。压测无掉落未单测覆盖；计数 ≤ 个位数，风险可忽略，如需与弹幕同口径可后续给 `make_sprite` 加参。

---

## Fix Round 1（评审 Approved：1 Important + 7 Minor，2026-08-31）

### Important-1：弹幕/预警纹可读性（地面红纹同题）

评审指出：光圈内飞行敌弹（A2 图主要威胁刺激）与预警纹在首轮后只剩 CanvasModulate
亮度，失去光圈 +1.2 增亮；且首轮视觉证据是无弹截图，未覆盖该玩家可见场景。

**实测两条路（全部同机探针 A/B，非 diag 外推）：**

| 方案 | 探针 F2 draw avg / max | 判定 |
|---|---|---|
| T37 首轮基线（同机复测） | 100.4 / 141 | 参照 |
| 弹幕+预警纹进光照参与集 | 147.6 / 239（复测 148.5 / 256） | **+47，余量 1% 否决** |
| **弹幕 self_modulate 折叠 + 预警纹参与（落地）** | **101.2 / 158** | **余量 32.5% 落地** |

- **(a) 弹幕：`BiomeFx.bullet_aid(dist, radius)` 折叠**（评审建议机制）——光斑径向衰减
  纯函数 `aura_gradient(t)`（复刻 GradientTexture2D 锚点 1/0.25/0）× LIGHT_ENERGY，
  写入弹幕共享精灵 `self_modulate`（`floor_scene._sync_bullet_visuals` 逐帧；无 A2
  组件时 WHITE，池化跨层复位安全）。首轮矩阵已实证逐项 modulate 写入零批处理成本
  （f2_nomod ≈ f2）。**注意：diag 归因工具曾显示弹幕参与集仅 +3.7，但探针口径
  （伤害数字/白闪全管线高频状态翻转）实测 +47——diag 值为下界不可外推，已在
  tools/probe_light_attribution.md 记录两个口径。**
- **(b) 预警纹（地面红纹/滚石预警道/间歇泉瓦片/火雨红圈）进 LIT_ITEM_MASK**
  （floor_scene 创建点 opt-in）——探针 F2 101.2 实证在预算内，保留真实光照。
- **视觉证据（报告目录，钉种子确定性构图，BULLETS=1 WAIT_FRAMES=30）**：
  `t37_fix1_aura_bullet_compare.png`（上=before 暗弹 / 中=after 折叠增亮 /
  下=cull1 全亮参照）、`t37_fix1_combat_before.png`、`t37_fix1_combat_after.png`、
  `t37_fix1_combat_reference_fulllight.png`；after 相对 before ≥32 亮度差的像素
  103,780（增亮足迹 ≈ 光圈内弹幕群）。

### Minor 修复

- **Minor-2（报告矛盾句）**：见本节文末更正。
- **Minor-3（同义反复断言）**：test_art_atlas.gd 删除 manifest size[0] 自比断言。
- **Minor-4（个人 venv 绝对路径）**：`_python_exe` 改为 `ART_ATLAS_PYTHON` 环境变量
  优先（可指认含 Pillow 解释器），回落 PATH python/py；不再写死绝对路径
  （test_art_pipeline.gd 的同款路径属 m2-t21 既有契约，未在本卡擅动，移交后续卡）。
- **Minor-5（先建后检/无负缓存）**：`ArtAtlas.texture_for` 先判界后建 AtlasTexture；
  新增 `_invalid` 负缓存（畸形行在 `_apply_manifest` 归一化时记入、越界行首查记入）
  ——腐坏行只告警一次，热路径零重复分配。新增 2 例单测（畸形行归一化拒绝、越界行
  先检后建 + 负缓存 + `_regions` 不含该行）。
- **Minor-7（归因不可复现）**：诊断脚本随库走——`tools/diag_light_attribution.gd
  (+.tscn)`（VAR 单变量手术 + SHOT_OUT 截图模式）+ `tools/probe_light_attribution.md`
  （两轮矩阵 + 复现命令）。
- **Minor-8（裸 traceback）**：main() 图集步骤包 try/except——打印 annotated 失败
  信息（含 Pillow/尺寸/页容修复提示）后 RuntimeError 中止（prune 时序语义不变）。

### Minor 2/6 报告更正（追加，不改写历史）

- **Minor-2 更正**：首轮报告「max 样本首次全部落入 150 线内（156/145/147）」为假
  ——F1 max 156 > 150。正确表述：**F2/F3 max（145/147）落入 150 线内，F1 max 156
  仍越线；预算判定按 T29 口径取采样窗平均值，avg 门不受影响**（AFTER 轮 avg
  106.2/105.6/95.0 全 PASS）。Fix 轮落地配置复测 avg 105.1/101.2/100.2（max
  165/158/173），PASS 维持。
- **Minor-6 更正**：首轮「可见像素（α>0）逐位恒等」措辞过强——实现为
  `Color.is_equal_approx` 逐像素近似比对（工程像素值域下与逐位比对等效，但非
  位级断言）。Fix 轮起表述统一为「逐像素 is_equal_approx 恒等（α>0 全量）」。

### Fix 轮验证

- 新增/更新单测：BiomeFx `aura_gradient`/`bullet_aid` 纯函数（锚点/单调/边界）、
  floor_scene 弹幕折叠接线（光圈内 self_modulate>1、卸载复位 WHITE、参与集保持
  默认位）、ArtAtlas 负缓存 2 例。定向套件 39/39 绿。
- 探针（落地配置，窗口运行）：F1 105.1/165、F2 101.2/158、F3 100.2/173——
  **全 PASS**；证据 `m2_perf_fixround_t37.json`。
- 全量 gdUnit：见提交信息（预期 1355：1351 −2 弹幕 lit-mask 用例改写 + 6 新增）。

### 环境备注（Fix 轮全量回归）

Fix 轮首次全量回归出现 4 例失败（test_forge / test_skills_mage_guardian /
test_weapons_pool 的掉落池计数）——根因为 gdUnit 无头隔离档
`user://save_headless.json` 跨套件运行累积解锁态（test_forge.gd:396 自证其会
持久化解锁；a87605f 只封堵了其中一例）。该文件是测试隔离产物而非玩家数据
（真档 user://save.json 与本卡窗口探针互不干扰），已备份后重置，重跑全量
恢复绿。移交：4 处「紫橙全锁」时代假设的断言建议随 T31/T32 后续卡统一按
a87605f 前例封堵，避免反复全量回归后复发。
