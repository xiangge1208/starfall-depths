# M2 流水线台账（编排者维护）

> 更新规则：每次合并/裁定后更新。
> **2026-08-31 12:00 第三次接管重建**：前会话（`sess_838b9cba`）于 2026-08-31 11:23–11:25 UTC 触达 5 小时套餐上限，全部在飞子 Agent 同批死亡。本文件已按 `git` 实际状态 + `docs/superpowers/sdd/2026-08-30-m2-full-content/progress.md`（11:21，最新）重建为真值。
> **2026-08-31 12:25 第四次接管（本会话）**：复核第三次重建无误（main `89b5cfa`、worktree 半成品清点一致）；裁定⑭关闭缺口 2；第一波派发：T25 独立评审 + prophet / T31 / T32 半成品恢复实现（并发 ≤4）。
> **2026-08-31 下午（同会话续）**：T36 实现评审 **Approved**（5 Minor 非阻塞）→ 已合 `a177691`，全量 **1335/1335 绿**（74 套件，5m14s）；T35 实现完成 `f9c5022`（自报 1344 绿）评审已派；T37 第五波已派（worktree ff 至 `a177691`）；T30/复测仍在飞（worktree 有未提交进度）。
> **2026-08-31 下午（同会话续 2）**：T35 评审 **Approved**（零 C/I；10 个未接线键全部经 grep 证实为所有权边界外合法移交）→ 已合 main，全量 **1358/1358 绿**（75 套件，亲验）；T33 预检提前派出（见裁定㉗范围扩张）。在飞：T37 / T30 / 复测 / T33。

## 地面真值（接管时亲自复验）

| 项 | 值 |
|---|---|
| main tip | T35 合并提交（m2-t35 → main；前序 `007a4dc` docs → `a177691` m2-t36 → `a87605f` test seal） |
| 工作树 | main 检出干净；在飞 worktree：m2-t30 / m2-t37 / m2-retest（T35 已合并，worktree 可清） |
| 全量测试 | **1358/1358 绿**，75 套件，exit 0（T35 合入后，本次亲验） |
| 测试耗时 | ~5m |

### ⚠️ 环境前提（否则会误判为红）

`tests/unit/test_art_pipeline.gd` 用子进程调 `python` 跑 `art_prune_guard.py`，需要 **Pillow**。
- 系统 Python `C:\Program Files\Python312\python.exe` 有 Pillow 12.3.0 ✅
- WorkBuddy 托管 Python 3.13.12 **无 Pillow** ❌，若 `PATH` 中它排在前面，该套件报 2 failures（`ModuleNotFoundError: No module named 'PIL'`）

跑测试前确认：`python -c "import PIL"` 通过。这是环境问题，**不是仓库缺陷**。

## 卡片状态总表

### 已合并（32 张）

| 卡 | 内容 | 合并提交 | 备注 |
|---|---|---|---|
| T1 | S0 加固 | ed88ef8 | M1 终审 3 项闭环 |
| T2 | 天赋树全表 | b633ed6 | 24 节点 + 附录 I |
| T3 | 图鉴 49 + 成就接线表 | 894b5f6 | J.7 已对齐 T12 |
| T4 | A2 暗视野 + 冰面 | 3810149 | |
| T5 | 音频管理器 + sfx 接线 | 1ff4a52 | |
| T6 | 武器扩至 115 | 801e9ae | 附录全量零误差 |
| T7 | A2 地刺 + 晶柱折射 | 6b902df | |
| T8 | 召唤框架 + 工程师 | 02ea278 | |
| T9 | 敌人补齐 40 | e6a06f3 | |
| T10 | A3 岩浆生态 | e0e19d3 | A3 模板延后（见下「缺口」） |
| T11 | 法师 + 守护者技能 | 363d114 | 裁定⑥ |
| T12 | 增益 36 | 3760272 | |
| T13 | 刺客 + summon_cap | a0cb075 | |
| T14 | 宝石蜂后 + 晶棱魔像 | 7c43398 | 评审 Approved |
| T15 | 天赋树系统落地 | 33b2c07 | → T35 承接 |
| T16 | 寒渊蛛母 | 290b412 | 评审 Approved；cage 纯视觉移交 |
| T17 | 英雄行走帧 | de37d2e | 96 帧逐字节验证 |
| T18 | 胜利结算 | aac889b | routes union 6 keys；裁定⑫ |
| T19 | 熔核暴君 | 89b5cfa | 含修复轮 `eba6643`（火拳伤 7→8 权威回改 + 岩浆区可视化 + 三方合并） |
| T20 | 图鉴 + 解锁引擎 | 22e4b56 | 评审 Approved |
| T21 | 敌人 2 帧 + 管线守卫 | 18deb90 | 裁定⑪ 美术管线断链修复 |
| T22 | 音乐 5 曲 + Boss 切层 | 28c0b94 | QOA loop 修复 `0161916` |
| T24 | 死亡回顾 + DPS 采样 | 7d8f7ee | 3s 确定性重放 |
| T27 | A2/A3 瓦片映射 + 元素弹分化 | 06cb619 | 修复轮 `9b3964f`，像素色距 0 证据 |
| T31 | 蓝晶结算 + 存档 migration v2 | 0d07799 | 评审 Approved；回退「进门入账」保死亡减半口径 |
| T32 | 成就系统 22 激活 | a04f32f | 评审 Approved；save_system 与 T31 并集；17 条待 T35 发射 |
| T25 | 熔铸台场景接线 | 7478f79 | 评审 Imp×2 全闭环（craft_x 接线由存留代理补）；裁定⑮⑯⑰ |
| prophet | 星陨先知 + 隐藏门 | 701a791 | 评审 C-1/I-1 修复轮 `e71e23f`（门提前开→房清拍判定 + 共鸣斩单击化）；编排者亲核修复证据 |
| T26 | 挑战房灾厄 + A2/A3 模板 ×16 + 矩阵复核 + 移交项 | bcb940b | 评审 I-1/I-2 修复轮 `b144647`（治疗拦截单一收口 + a2 入口桩真建层）；A2/A3 波次敌人名录仍 A1（移交 T36 评估） |
| T28 | Balance Bot 全层回归 | 3ddb77c | 10 局校准批：0 胜 9 死 1 超时（bot 档读法）；战斗房时长带内；六校准点五确认一新发现（稀有度权重漂移坐实）；胜率带待 T26 合并复跑 |
| T29 | §18.3 压测 | 7ac811c | 预算五项 PASS；**F2 draw call 超标 ~8%**（全图集前提未达成）→ 裁定㉓ T37；监视器单位毫秒实证；渲染侧留 T34 真机 |
| T36 | Boss 楼层路由 + 柱接线 + cage 机制化 + 灾厄复合（裁定⑳㉑） | a177691 | 评审 **Approved**（5 Minor 非阻塞，去向见裁定㉖）；14 新测试钉死路由/柱生命周期/豁口几何/复合系数 |
| T35 | meta 生效接线（裁定⑨①-⑥） | （m2-t35 merge） | 评审 **Approved**（零 C/I）；15 键接线 + 10 键所有权外合法移交；wipe→repair 解 T15 自抵消（双修复点对称性经评审独立验证）；shop_purchase 四 kind 成功点发射；T18 胜利桩 Label 已清 |
| T30 | Windows 导出冒烟 + Android 链预通 | b4beea9 | 编排者亲审直并（2 新文件零生产代码，未派独立评审——按效率原则）；**Windows PASS**（117MB exe 30s 存活无崩溃，PowerShell 真 PID 法）；Android **SKIP 如实**（本机无 SDK，log 存档）；注意：导出模板 1.28GB 需 CI 缓存勿直下（裁定㉘） |

### 待处理（2 张 + 复测 + 门禁）

| 卡 | 内容 | 分支 | 状态 | 下一步 |
|---|---|---|---|---|
| **T37** | 全图集合并 + A2 剪影批处理（裁定㉓，F2 draw call 超标闭环） | m2-t37 | **实现完成 `a70305d`**（1351/1351 自报；F2 平均 157.2→105.6 转 PASS；根因修正=PointLight2D cull mask 而非剪影 modulate；披露：弹幕/伤害数字不再受光环提亮），评审在飞 | 评审 → 修复轮（如有）→ merge |
| **复测** | T28 胜率带复跑 + TTK 正式表 + T29 A2/A3 密房复测（T26 已合前提） | m2-retest | **第四波在飞**（perf_probe.gd 有进度） | 报告增补 → 编排者归档 |
| **T33** | 门禁预检，范围扩张见裁定㉗：save_headless 密闭（裁定㉔）+ **17 条成就发射点审计与补线** + M1 补录 ③④ 核销 + T36 Minor ①②③⑤ 微修 + T35 Minor ④⑤⑥ 微修 + 移交表逐项复核（8 派味特技/spare_parts/echo/blessing 以 T35 评审 25 键结论为基准） | m2-t33 | **在飞** | 实现 → 编排者核证据 → merge |
| **T34** | M2 门禁（双报告 + 裁定 + tag；含 T29 渲染侧真机复测 + M1 补录第 1/2 项 + 裁定㉔② 真人 Boss 房段试玩——T36 已合，具备条件） | — | 从未派发 | T37 + 复测 + T33 合并后 |

另有 `m3-prelude` 分支领先 main 7 提交（M3 预研，不在 M2 门禁范围内）。

## ⚠️ 发现的两处口径缺口（需编排者裁定）

### 1. 计划文档 T22 之后编号错位（裁定⑤已判「以正文为准」，但 worktree 未按此执行）

同一张卡在波次表与任务正文里编号不同，worktree 命名跟随**波次表**：

| 内容 | 波次表编号（worktree 用） | 正文编号 |
|---|---|---|
| G-2 音乐 5 曲 + Boss 切层 | T22 → `m2-t22` | Task 22 |
| F-2 死亡回顾完整 | T24 → `m2-t24` | Task 23 |
| **D-4 星陨先知 + 隐藏门** | **无独立号** → `m2-prophet` | Task 24 |
| 熔铸台场景接线 | T25 → `m2-t25` | （正文无此卡） |
| 挑战房灾厄 + 房型复核 | T26 → `m2-t26` | Task 30 |
| Balance Bot | T28 → `m2-t28` | Task 27 |
| A2/A3 瓦片 + 元素弹分化 | T27 → `m2-t27` | Task 28 |
| 压测 | T29 → `m2-t29` | Task 29 |
| 蓝晶结算 | T31 → `m2-t31` | Task 32 |
| 成就系统 | T32 → `m2-t32` | Task 33 |
| 导出冒烟 | T30（未建） | Task 31 |

**本台账以 worktree 编号为准**（与已合并提交一致），正文编号仅作规格索引。

### 2. A2/A3 房间模板 ×16（正文 Task 26）无人承接

`data/rooms/` 只有 `a1_templates.json`（`game_db.gd:179` 只注册这一个），A2/A3 模板从未创建。
T10 合并（`e0e19d3`）把「A3 模板」延后给「T26」，但会话把 T26 按波次表定义成了「挑战房灾厄 + 房型矩阵复核」，**模板创建因此落空**。
T27 报告也侧面印证：「A2/A3 层模板 `door_local`/spawn 缺键」——实际不是缺键，是模板根本不存在，当前三层共用 A1 布局、仅靠 T27 的 biome 贴图做视觉区分。

**影响**：房型矩阵复核（T26）缺少 A2/A3 数据前提；GDD 的「每生态 8 战斗模板」未落地。
**已裁定⑭（2026-08-31 第四次接管）**：并入 T26——依据 `e0e19d3` 合并时既有裁定「A3 templates deferred to T26」+ 本表复核；T26 最终范围见卡片状态总表。

## 编排者裁定记录

1. **炮台 DPS 矛盾**（T8 上报）：计划卡「射速 2/s、伤 4」=8 DPS vs GDD §6「DPS 15」。裁定：以计划卡为准（8 DPS 落地），列入 T28 Balance Bot 校准点。
2. **武器稀有度分布**：附录 A 实际 = 白9/绿21/蓝36/紫33/橙16（计划卡括号 13/30/32/25/15 为占位误值，弃用）。紫33+橙16=49 locked。
3. **T3 熔铸限定口径**：49 条解锁任务含 4 把★熔铸限定（星陨炮/雷神之锤/斩舰刀/湮灭核心），条件类型用 craft_x；T20 落地时加 forge_only 键保证解锁后仍不入普通掉落池。
4. **T7 范围收窄**：T9 已交付全部 A2 敌人行，T7 禁止重复插行，聚焦 hazard_spikes/enemy_laser 晶柱折射/滚石/藤蔓减速/floor_scene hazards 接线。
5. **计划文档勘误**：附录 D 实为熔铸配方，英雄表在 GDD design §6；「12 个既有 WAV」实际 47 个；**波次表与任务正文在 T22 后编号错位——以任务正文为准**（注：worktree 实际按波次表编号，见缺口 1）。
6. **T11 技能数值权威**：生命潮汐升级=法阵内 -20% 受伤 + 施放即回 2HP，按 GDD 落地；新星升级含冻结 2s；法阵 3s 实落 1HP（累加器不跨施放）留 T28 定夺；守护者持史诗星辉杖（无弱化版）→ T13/T28 关注。
7. **增益白名单口径**：附录 C = 36 = 16 已有 + 20 新增（计划卡「+21」系笔误）；新效果键实际 25 个；键名权威 = T12 实现；稀有度分布实为 白15/绿11/蓝10。
8. **T3 信号裁定**：新成就信号改名 `boss_slain(boss_id, floor_idx)`；buy_x 计数源 shop_purchase 信号待发射（归 T35）。
9. **T35（补充卡）meta 生效接线**（文件所有权：player.gd/pickup.gd/shop_logic.gd/drink_machine.gd/weapon_rig.gd/fx 最小读接线 + run_root.gd + main_menu.gd + scene_router.gd）：①T12 的 25 个增益键 get_meta 消费接线（含 haggle 负值 clamp、phoenix 致死分支、hurt_iframe_bonus）；②T15 天赋 4 键（dmg/hurt_iframe/coin_gain/pickup_radius）消费 + run_root 开局 apply_to_player；③固定顺序 Hero→Buffs→Talents + buff 重 apply 后补天赋 apply（先 RED 组合测试）；④主菜单天赋入口 + SceneRouter 路由；⑤shop/drink 购买信号发射（T3 K 表同名）。commit 前缀 `feat(m2-t35)`。
10. **地刺跨帧语义**（T7 m8 裁定）：伸出期=连续伤害区，i-frame 48t 自然节流（站桩每周期约 2 跳），符合类元气骑士地刺手感。
11. **美术管线断链**（T17 发现/T6 遗留）：gen_placeholder_art_m2 断言 115 vs 数据 190，main() 先清库再串联 → 全量入口当前为破坏性操作（禁跑）；10 个正式武器 id 缺图标 → **T21 修复**（已合）。
12. **T18 胜利预告文案**：采用实现者版本「更多内容与试炼模式即将开放」（胜利时已在第 3 层，语义更自洽）。T18 移交：inter_floor 胜利桩 Label 清理 → T35 顺手。
13. **T19 火拳伤害**：以数值权威 `2026-08-28-starfall-depths-data-tables.md:389-395` E.5 行的 **8** 为准（任务转述的 7 是转录错误），已在 `eba6643` 回改。
14. **A2/A3 房间模板 ×16 归属**（缺口 2 收口）：并入 **T26**。依据：T10 合并 `e0e19d3` 已有裁定「A3 templates deferred to T26」；模板是房型矩阵复核的数据前提，单列卡反而制造 `game_db.gd`/`data/rooms/` 双重所有权。T26 范围 = 挑战房灾厄收口（正文 Task 30）+ A2/A3 模板 ×16（正文 Task 26）+ 房型矩阵复核 + 小Boss 楼层缩放（A2×400/A3×870 抽取池接线）+ A2 混排晶柱 kind 拆分 + 冰面 zone 视觉 biome 字段驱动（移交表各项）。
15. **熔铸 forge_only 权威源**：`unlock_tasks.json` 的 `forge_only:true` 数据驱动（ForgeLogic 直读），常量降级为数据缺失兜底——追认修复轮 `0e25990`（前会话存留代理自编号「裁定⑭」，台账统一重编为⑮）。
16. **熔铸产物继承**：附录 D 尾注落地（蓝耗=两材料较高者/元素=B 材料元素），只写副本不污染表行——追认 `0e25990`（其自编号「裁定⑯」编号恰好不冲突）。
17. **熔铸费用公式**：M2 采用实现者 30~390 阶梯（附录 D 无逐条费用条目；GDD §8.3 的 40~80 疑为早期占位区间），**T28 Balance Bot 校准点复核**。
18. **前会话存留代理（僵尸）事件记录**：2026-08-31 12:55–13:15，一存活代理在 `.worktrees/m2-t25` 自主执行修复轮并读走本编排者评审报告（`5b1061b`）后提交 `0e25990`/`78bb9e8`（craft_x 接线 + 盐常量，评审 Important-1/Minor-3 全闭环）。处理：不派对抗代理，监控其产出；其裁定编号以台账为准重编。其修复轮已随 `7478f79` 合入。
19. **先知击杀经济口径**（prophet 评审 I-2）：T31 击杀结算（Boss +50 / 首杀 +300）是标准权威；prophet 的 gems3 实体掉落是隐藏 Boss 设计加成，两者**叠加合法**（先知击杀合计 +53 或 +353 首杀）。列入 T28 校准点。
20. **T36 立卡（Boss 楼层路由接线）**：T26 披露③——FloorScene Boss 房波次三层恒 `vine_colossus`（floor_scene.gd:1373），gem_queen/prism_golem/frost_widow/magma_tyrant/starfall_prophet 均未路由进场；M2 门禁「三层 Boss 各三阶段」被此阻塞。范围：楼层×Boss 池路由（附录 E 归属：A1 vine_colossus / A2 gem_queen+prism_golem+frost_widow 池 / A3 magma_tyrant，先知走隐藏门已有机制）+ T14 移交 HivePillar/Crystal 出生接线 + T16 移交 cage 机制化 + T26 披露②精英楼层缩放。floor_scene 所有权：待 prophet/T26 合并后派。
21. **挑战房「视野-35%」灾厄双 BiomeFx 实例 defer**（T26 评审 I-3）：后挂 CanvasModulate 胜出致灾厄房画面反亮（0.65 替换生态 0.25）+ 双光圈叠加；0.4 剪影下限仍兜底。修复方向 = 复合进既有 biome_fx 而非二次实例；承接 **T36**（同动 floor_scene/biome_fx，避免双卡竞争所有权）。
22. **无头跑图共享 `save_headless.json` 累积真实图鉴进度**：场景级测试（m1 smoke 等）经真解锁链解锁武器回池并持久化——属产品正确行为；测试侧密封化先例 `df9691a`（forge 空桶前提显式构造）。**T33 预检核对项**：全量门禁前清档重跑一次，确认无其他「纯净引导」假设测试。
23. **F2 draw call 超标闭环（T29 上报）**：根因 = §18.3「全图集」前提未达成（逐纹理精灵）+ A2 逐敌剪影 O(n) draw 放大；降粒子/降实体均非解。立 **T37**：全图集合并 + A2 剪影批处理，T34 前完成；T34 真机复测渲染侧后重跑 perf_probe 复核。
24. **save_headless 套件非进程密闭**（T26 修复轮披露）：套件内结算/解锁测试跨 run 持久化漂移可致定向抽取/池计数用例假败（本次实证 `test_black_stock_prefers_epic_then_rare`）；复跑前清档即绿。立卡或 T33 预检统一收口（套件启动清档 or 测试内还原）。并行「有窗 evidence × 全量套件」共享 user:// 互踩——复跑流程串行。
25. **僵尸代理 main 直提追认**：`3377a09`（test_art_pipeline 优先托管 venv Python/Pillow，环境纪律正确）+ `e6ed091`（M1 全程复查补录 4 项 + 波次表编号错位另注）——均为良性高质量，追认入线。补录 4 项去向：①藤蔓巨像 90~150s 验收 → T34 checklist；②真人试玩提前 → T36 合并后、T34 前安排真 Boss 房段试玩；③死亡确认输入锁 / ④跨局遥测留存 → T24 已合，转 **T33 预检**核对现实现是否已覆盖，未覆盖则 T35/T37 顺手或单列微卡。
26. **T36 评审 5 Minor 处置**（2026-08-31，评审 Approved 非阻塞）：①cage 豁口 ±40° 含柱体实缘 ~10.6°（穿柱宽容，可辩护）→ 补注释披露，T33 预检顺手或微卡；②`_cage_confine` 到期不清旗（空列表守卫 no-op，纯卫生）→ 同上微卡；③`_pick_boss_row` 重复 `boss_row_for_floor` 的 duplicate+sort → 微卡；④`compound_vision_factor` 从常量重算的 brittleness 备注（单写者下安全）→ 记录不立项；⑤A2 端到端未断言 Boss hp（800/1800/1800 契约）→ **并入 T33 预检**（见待处理表）。另：T36 评审复核确认裁定⑳实施前评审曾提出的「柱体 position 世界语义/register_body 缺失」两项 Important 已由实现以 `top_level=true` + `register_body` + `combat_radius()` 完整闭环，T14 移交项相应销账。
27. **T35 评审处置 + 「17 条成就发射点」归属澄清 + T33 范围扩张**（2026-08-31）：T35 评审 Approved 零 C/I，①-⑤ 全落地；10 个未接线键（rig 5 + 展示 3 + heart_sense + anti_poison）经评审 grep 证实无任何现有消费者、均在裁定⑨所有权清单之外，合法移交——**消费建设归 M3**（combat/resonance 侧），不在 M2 门禁路径。Minor 处置：④未用参数 frame、⑤thorns「就近」实为组序首个+致死弹仍反伤、⑥测试死调用与 rig 落地仅测 hunter → 全部 T33 顺手微修；fx 所有权授予未使用（无缺陷）。**澄清**：台账 T35 行旧备注「含 T32 的 17 条成就发射点」系表格简写与裁定⑨正文（仅 shop_purchase 发射）不一致——评审暴露此缺口属实：**17 条成就发射点从未被任何卡承接**（T32 激活 22 条中 17 条缺游戏事件→信号发射点）。裁定：**并入 T33 预检**，范围=审计 22 条成就的发射点现状 + 为缺失者在正确游戏事件处补线（signal 名以 T3 K 表/裁定⑧ 为权威）+ 测试钉死；文件所有权临时授予 floor_scene/room_combat/bosses/inter_floor/player 已合文件（与在飞 T37 的图集/剪影路径预计不重叠，若冲突以 T37 优先、T33 rebase）。
28. **T30 直并 + 导出模板获取经验**（2026-08-31）：T30 仅 2 新文件（export_presets.cfg / tools/export_smoke.cmd）零生产代码，按「小任务不过度并行」原则由编排者亲审 diff 直并（presets 无密钥无加密、产物入 gitignored user_export/、脚本 exit-code 语义诚实），**未派独立评审代理**。Windows 冒烟 PASS（117MB exe，PowerShell Start-Process 真 PID 30s 存活检测 + 游戏日志 FATAL/CRASH 扫描，日志目录先清零防跨次误判）；Android 无 SDK 诚实 SKIP 非 FAIL。导出模板 4.7.2-stable 1.28GB 官方 CDN TLS 断连，经 gh api + Range 64MB 分块重试装入 `%APPDATA%\Godot\export_templates\4.7.2.stable\`——**CI/重装机须缓存模板，勿直下**。

## 移交/遗留项（消费卡号）

| 项 | 来源 | 承接卡 |
|---|---|---|
| death 键口径确认 + music 2 通道本体 | T5 | T23（编号未使用，见缺口 1） |
| ShopLogic --script 回退未过滤 locked | T6 | T27 前收口 |
| LOOT_RARITY_WEIGHTS 绿→rare 映射漂移 | T6 | T28 校准 |
| ★4 解锁后 forge_only 排除普通掉落池 | T6 评审 | T20 ✅ |
| 黑市「偏好紫」死分支（epic 全 locked） | T6 评审 | T20 后复核 |
| 冰面 zone 视觉 + biome 字段模板驱动 | T4 | T26 |
| 每帧组查询分配/剪影 O(n) 优化 | T4 评审 | T29 压测观察 |
| 召唤物跨房间残留 3 行收口 | T8 评审 | T22/T25 |
| summon_cap 注册进 HERO_OPTIONAL | T8 评审 | T13 ✅ |
| spare_parts 被动接线 | T8 | T33 预检 |
| 小 Boss 楼层缩放（A2×400/A3×870）+抽取池接线 | T9 评审 | T26 |
| 8 项派味特技（偷币/水洼提速/模仿武器/抛物线/龟缩/钳击/拉拽/落地生怪） | T9 评审 | T33 门禁移交核对表 |
| 派味 Boss 行为（熔核暴君 P3 掩体挡火浪等） | T9 | T19 ✅（prophet 卡延续） |
| EnemyLaser 不入敌弹 400 上限 + 折射柱快照 | T7 评审 | T14 复用时重估 |
| A2 混排晶柱 kind 拆分（当前所有 pillar 都折射） | T7 评审 | T26 |
| 被动 echo/blessing/spare_parts 无消费代码 | T8/T11 | T33 预检（或 T35 顺手） |
| 天赋 4 键消费 + 顺序固定 + 主菜单入口 | T15 评审 Major-1/2 | **T35**（已立卡） |
| 25 增益键消费接线 + shop_purchase 信号 | T12 评审 Major-1 | **T35**（已立卡） |
| HivePillar/Crystal 坐标空间 + register_body（拆柱→晶棱再生博弈环依赖） | T14 整合要求 | boss 生成接线卡（T26/prophet 顺手） |
| T16 cage 围困纯视觉无机制约束 | T16 评审 | 房间接线后续卡 |
| inter_floor 胜利桩 Label 清理 | T18 | T35 顺手 |
| 熔铸台常驻位置模板驱动（当前硬编码每层 1 个） | T25 | 后续模板卡（并入缺口 2） |
| A2/A3 层模板 door_local/spawn 缺键 | T27 | 实为模板不存在 → 缺口 2 |

## 运行规则（承前会话）

- 并发不限 4 槽（用户 2026-08-30 授权），但**文件所有权互斥必须保持**；worktree 隔离（`.worktrees/m2-tN`，基于 main tip）。
- 流程：实现（TDD）→ 独立评审（规格+质量双维，报告入 `docs/superpowers/reports/task-N-report.md`）→ Major 修复 → `merge --no-ff` → 全量门禁复跑 → 台账更新 → 派下一卡。
- 测试命令（**先确认 Pillow 可用**，见上）：
  ```
  godot --headless --path . --import
  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
  ```
  gdUnit 6.2.1 fail-fast，套件内首个失败即停。
- 子 Agent 后台不可用时：单条消息内多 Agent 调用并发；已完成 Agent 用 SendMessage 续命做修复轮。

## 已知文件所有权冲突（派发时必须错开）

| 文件 | 竞争卡 |
|---|---|
| `core/rooms/floor_scene.gd` | prophet / T26 / T25（已提交，待合） / T35 |
| `data/enemies.json` + `core/enemies/enemy_factory.gd` | prophet（新增 boss 行） |
| `autoload/run_state.gd` | T25（+SALT_FORGE/forge_upgrades） / T31 |
| `core/rooms/inter_floor_flow.gd` | T31 / T35 / T18 桩清理 |
| `autoload/save_system.gd` | T31 / T32 |
