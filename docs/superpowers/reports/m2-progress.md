# M2 流水线台账（编排者维护）

> 更新规则：每次合并/裁定后更新。前会话台账遗失，本文件自 2026-08-30 起重建为唯一权威进度记录。

## 卡片状态总表

| 卡 | 内容 | 状态 | 分支/提交 | 测试 | 备注 |
|---|---|---|---|---|---|
| T1 | S0 加固 | ✅ 已合并 | ed88ef8 | 724 绿 | M1 终审 3 项闭环 |
| T2 | 天赋树全表 | ✅ 已合并 | bebcea3/b633ed6 | 744 绿 | 24 节点+附录 I |
| T3 | 图鉴49+成就表 | ✅ 已合并 | 799dc18+4f7f0c7 | 916 绿 | J.7 已对齐 T12；boss_slain 改名 |
| T4 | A2 暗视野+冰面 | ✅ 已合并 | e0580e4+af05911/3810149 | 761 绿 | 评审 A-with-notes，Major 已修 |
| T5 | 音频管理器 | ✅ 已合并 | 682010a+d43d1c3+2156228/1ff4a52 | 774 绿 | 评审 A-with-notes，2 Major 已修 |
| T6 | 武器115 | ✅ 已合并 | 56ce47d/801e9ae | 779 绿 | 附录全量零误差（720 字段比对） |
| T7 | A2 地刺+晶柱 | ✅ 已合并 | c4aa6fa | 841 绿 | 评审 APPROVED |
| T8 | 召唤框架+工程师 | ✅ 已合并 | eb4fba1/02ea278 | 791 绿 | 0 Major |
| T9 | 敌人补齐40 | ✅ 已合并 | 54673b9+99c064b/e6a06f3 | 810 绿 | main 实际 40+6+1=47 行 |
| T10 | A3 生态 | 🔄 实现中 | m2-t10 | — | |
| T11 | 法师+守护者技能 | ✅ 已合并 | 204e942 | 861 绿 | 评审 APPROVED，裁定⑥ |
| T12 | 增益36 | ✅ 已合并 | 137eed1+01f5985/3760272 | 929 绿 | 注释改真+flag max 已修 |
| T13 | 刺客数据+选角扩展 | 🔄 实现中 | m2-t13 | — | guardian 行已由 T11 落，本卡只加 assassin |
| T14 | 宝石蜂后+晶棱魔像 | 🔄 实现中 | m2-t14 | — | 复用 T7 EnemyLaser |
| T15 | 天赋树系统落地 | ✅ 已合并 | 09ba744 | 887 绿 | 条件通过→T35 承接已立项 |
| T16 | 寒渊蛛母 | ⏸ 待 T14 | | | |
| T17 | 英雄行走帧 | ✅ 已合并 | 882f30c | 899 绿 | 96 帧逐字节验证 |
| T18 | 胜利结算 | 🔄 实现中 | m2-t18 | — | |
| T20 | 图鉴+解锁引擎 | 🔄 实现中 | m2-t20 | — | |
| T21 | 敌人2帧+管线修复 | 🔄 实现中 | m2-t21 | — | 含美术管线断链修复（裁定⑪） |
| T35 | meta 生效接线（补充卡） | ⏸ 已立项待派 | | | 与 T18 错开 run_root.gd，下轮派 |
| T19~T34 | 后续 | ⏸ 排队 | | | 波次表见计划文档 |

main 测试基线：**929/929 绿**（3760272）。合并轨迹 744→761(T4)→774(T5)→779(T6)→791(T8)→810(T9)→841(T7)→861(T11)→887(T15+flaky 加固)→899(T17)→916(T3)→929(T12)。telemetry flaky 已根治（确定性边界驱动，commit `test(m2-hygiene)`）。

## 编排者裁定记录

1. **炮台 DPS 矛盾**（T8 上报）：计划卡「射速 2/s、伤 4」=8 DPS vs GDD §6「DPS 15」。裁定：以计划卡为准（8 DPS 落地），列入 T28 Balance Bot 校准点。
2. **武器稀有度分布**：附录 A 实际 = 白9/绿21/蓝36/紫33/橙16（计划卡括号 13/30/32/25/15 为占位误值，弃用）。紫33+橙16=49 locked。
3. **T3 熔铸限定口径**：49 条解锁任务含 4 把★熔铸限定（星陨炮/雷神之锤/斩舰刀/湮灭核心），条件类型用 craft_x；T20 落地时加 forge_only 键保证解锁后仍不入普通掉落池（附录 A「永不入普通掉落池」）。
4. **T7 范围收窄**：T9 已交付全部 A2 敌人行（rock_crystal_turret/prism_ranger/ice_spider/crystal_rat/magnet_golem 等），T7 禁止重复插行，聚焦 hazard_spikes/enemy_laser 晶柱折射/滚石/藤蔓减速/floor_scene hazards 接线；可选把 rock_crystal_turret 切激光形态。
5. **计划文档勘误**：附录 D 实为熔铸配方，英雄表在 GDD design §6；「12 个既有 WAV」实际 47 个；波次表与任务正文在 T22 后编号错位——以任务正文为准。
6. **T11 技能数值权威**（GDD §6 vs 计划卡摘要）：生命潮汐升级=法阵内 -20% 受伤（非计划卡"+0.5 治疗"）+ 施放即回 2HP，按 GDD 落地；新星升级含冻结 2s；法阵 3s 实落 1HP（累加器不跨施放）留 T28 定夺；守护者持史诗星辉杖（无弱化版）→ T13/T28 关注。
7. **增益白名单口径**：附录 C = 36 = 16 已有（零修正）+ 20 新增（计划卡"+21"系笔误，T3/T12 双向独立印证）；新效果键实际 25 个（拆键）；键名权威 = T12 实现（T3 附录 J.7 已按此修订）；稀有度分布实为 白15/绿11/蓝10。
8. **T3 信号裁定**：新成就信号改名 `boss_slain(boss_id, floor_idx)`（避让既有 FloorScene.boss_defeated(room_id) 实例级信号）；buy_x 计数源 shop_purchase 信号待发射（归 T35）。
9. **T35（补充卡）meta 生效接线**（评审 T12/T15 的 Major 承接，W6 派发，文件所有权：player.gd/pickup.gd/shop_logic.gd/drink_machine.gd/weapon_rig.gd/fx 最小读接线 + run_root.gd + main_menu.gd + scene_router.gd）：①T12 的 25 个增益键 get_meta 消费接线（含 haggle 负值 clamp、phoenix 致死分支、hurt_iframe_bonus）；②T15 天赋 4 键（dmg/hurt_iframe/coin_gain/pickup_radius）消费 + run_root 开局 apply_to_player；③固定顺序 Hero→Buffs→Talents + buff 重 apply 后补天赋 apply（先 RED 组合测试）；④主菜单天赋入口 + SceneRouter 路由；⑤shop/drink 购买信号发射（T3 K 表同名）。commit 前缀 `feat(m2-t35)`。
10. **地刺跨帧语义**（T7 m8 裁定）：伸出期=连续伤害区，i-frame 48t 自然节流（站桩每周期约 2 跳），符合类元气骑士地刺手感，非每周期至多 1 次。
11. **美术管线断链**（T17 发现/T6 遗留）：gen_placeholder_art_m2 断言 115 vs 数据 115+75 暂定 slug=190，main() 先清库再串联 → 全量入口当前为破坏性操作（禁跑）；10 个正式武器 id 缺图标（20 文件）→ **T21 修复**（武器 slug 数据驱动化+恢复全量入口幂等+补缺图+T17 Minor① apply_player_sprite 清 hframes）。

## 移交/遗留项（消费卡号）

| 项 | 来源 | 承接卡 |
|---|---|---|
| death 键口径确认 + music 2 通道本体 | T5 | T23 |
| ShopLogic --script 回退未过滤 locked | T6 | T27 前收口 |
| LOOT_RARITY_WEIGHTS 绿→rare 映射漂移 | T6 | T28 校准 |
| ★4 解锁后 forge_only 排除普通掉落池 | T6 评审 | T20 |
| 黑市「偏好紫」死分支（epic 全 locked） | T6 评审 | T20 后复核 |
| 冰面 zone 视觉 + biome 字段模板驱动 | T4 | T26 |
| 每帧组查询分配/剪影 O(n) 优化 | T4 评审 | T29 压测观察 |
| 召唤物跨房间残留 3 行收口 | T8 评审 | T22/T25 |
| summon_cap 注册进 HERO_OPTIONAL | T8 评审 | T13 |
| spare_parts 被动接线 | T8 | T33 预检 |
| 小 Boss 楼层缩放（A2×400/A3×870）+抽取池接线 | T9 评审 | T26/T27 |
| 8 项派味特技（偷币/水洼提速/模仿武器/抛物线/龟缩/钳击/拉拽/落地生怪） | T9 评审 | T33 门禁移交核对表 |
| 派味 Boss 行为（熔核暴君 P3 掩体挡火浪等） | T9 | 对应 Boss 卡 T19/T24 |
| EnemyLaser 不入敌弹 400 上限 + 折射柱快照（炮台死束亡边界） | T7 评审 | T14 复用时重估 |
| A2 混排晶柱 kind 拆分（当前所有 pillar 都折射） | T7 评审 | T26（A2/A3 模板卡） |
| 被动 echo/blessing/spare_parts 无消费代码 | T8/T11 | T33 预检（或 T35 顺手） |
| 天赋 4 键消费 + 顺序固定 + 主菜单入口 | T15 评审 Major-1/2 | **T35**（已立卡） |
| 25 增益键消费接线 + shop_purchase 信号 | T12 评审 Major-1 | **T35**（已立卡） |
| telemetry/floor_scene 满载偶发弱频闪（非单卡引入） | T4/T9/T15 观察 | 卫生项，T10 或最近卡顺手加固 |

## 运行规则（承前会话）

- 并发不限 4 槽（用户 2026-08-30 授权），但文件所有权互斥必须保持；worktree 隔离（.worktrees/m2-tN，基于 main tip）。
- 流程：实现（TDD）→ 独立评审（规格+质量双维，报告入 docs/superpowers/reports/task-N-report.md）→ Major 修复 → merge --no-ff → 全量门禁复跑 → 台账更新 → 派下一卡。
- 测试：先 `godot --headless --path . --import`，再 `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`（gdUnit 6.2.1 fail-fast，套件内首个失败即停）。
- 子 Agent 后台不可用时：单条消息内多 Agent 调用并发；已完成 Agent 用 SendMessage 续命做修复轮。
| T13 | 刺客数据+选角扩展 | ✅ 已合并 | 748525f（评审 Approved 附条件已结：台账以 main 侧存活；935 绿实测） | 935 绿 | 影袭变体沿用裁定允许；GDD§6 刺客三项（翻滚CD0.45/近战反弹特质/残影斩口径）→ 移交表 T33 预检；shadow_reap 接线并入 echo/blessing 行 |
