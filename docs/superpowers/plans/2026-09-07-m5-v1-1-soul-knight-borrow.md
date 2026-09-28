# M5（v1.1）元气骑士借鉴扩展计划：九卡三波（2026-09-07）

- 依据：[对标复盘](../specs/2026-09-07-soul-knight-benchmark-diff.md) §3 清单 #1~#9（用户指令：全部实施）
- 纪律：①TTK-R——全部为**新增内容**，不触碰现有数值带（无 >±20% 存量改动）②内容卡允许改 core/（与平衡 bot 卡的「零生产改动」不同），但波内文件所有权零交集③改存档必须走 save v2 migration + 往返测试④`gen_placeholder_art.py` 全量 main() 破坏性禁裸跑（裁定⑪），素材走增量流程⑤存量测试钉值被本卡内容改变的，按证据改期望，禁止删测试
- 验收总口径：每卡全量测试绿（基线 1960+本卡新增）+ 冒烟无回归；集成波由主会话跑全量 + README/GDD 数量回写

## 波次与文件所有权

**W1（并行 3 卡）**
- **A1 复活图腾落地**（对标复盘 #1）：GDD §14.2 锚点（一次性，Boss 房前，150 金）+ `totem_revive` 贴图在盘。
  - 交互物：小 Boss 房后、Boss 房前的主路节点固定放置；E 交互购买（金币 ≥150），购买后本局标记（RunState 局内态），死亡时若已购 → 原地复活 50% HP / 满 2 盾、清除弹幕（0.8s 无敌帧）、图腾消耗；未购买交互显示价格。
  - 所有权：`core/rooms/**`（interact/fixture 层）、`core/meta/**`（死亡结算缝）、`autoload/run_state.gd`（局内标记）、`art/`（totem_revive 接线）、新增 `tests/unit/test_m5_totem.gd`
- **A2 手刀（空手攻击）**（#2）：
  - 空槽（ WeaponRig 当前槽为空）按开火 → 徒手挥击：射程 26px / 90° 弧、伤害 1、射速 3.0/s、0 耗蓝、**保留 0.12s 反弹窗口**（复用 melee 反弹判定路径）；HUD 武器槽显示「手刀」回落（复用 ui5 的缺图回落文字路径）。
  - 所有权：`core/player/**`（weapon_rig / melee / driver 开火路径）、`fx/`（挥击表现）、新增 `tests/unit/test_m5_hand_blade.gd`
- **B Boss 专属橙**（#9）：6 Boss 各一把专属橙（vine_colossus/gem_queen/prism_golem/frost_widow/magma_tyrant/starfall_prophet）。
  - 武器行 6 条入 `data/weapons.json`（橙档 DPS 带 22~27、GDD §8.1 上下文内；各带 1 条唯一特性文本与元素多样性）；Boss 掉落池加权 100%（首杀必掉、复杀 25%）；图鉴/兵器谱页标注「Boss 掉落」来源；武器总量 115→**121**。
  - 素材：走 spritegen 增量流程（勿裸跑 main()）；art 完备性 tripwire（图在盘路径存在）必须过。
  - 所有权：`data/weapons.json`、`data/enemies.json`（boss 行 drops 字段）、`core/enemies/**`（掉落读取如需）、`tools/spritegen*`、`art/**`、新增 `tests/unit/test_m5_boss_weapons.gd`

**W2（并行 3 卡）**
- **C 武器配件系统**（#4）：新 `data/attachments.json`，12 条：白 5（伤害+10%/射速+10%/弹速+15%/散布-20%/穿透+1）、蓝 4（伤害+20% 且射速-5% / 双发-20% 单发伤 / 蓝耗-25% / 反弹+1）、橙 3（**三连发模块**：每发变 3 连射间隔 2 帧 / **冰霜弹匣**：攻击附加冰元素积累 / **折跃枪托**：翻滚后 1.5s 射速+50%）。
  - 三个槽位：muzzle/mag/stock，每武器每槽 1 个；来源：精英房必掉 1、挑战房必掉 1、商店第 4 货架；拾取即装当前武器同槽（已有则替换，被替换的消失）；武器实例字典带 `attachments` 字段（**禁止污染 GameDB 共享缓存**——实例化拷贝行字典）。
  - 所有权：`data/attachments.json`、`core/combat/**`（伤害/弹幕应用点）、`core/player/weapon_rig.gd`（实例化）、`core/rooms/**`（掉落与货架）、新增 `tests/unit/test_m5_attachments.gd`
- **D 英雄解锁 + 技能强化**（#3，同时关闭「购买流/选角锁死」待裁定，按 GDD §6 原样落地）：
  - `data/heroes.json` 加字段 `unlock_cost`（vanguard 0 / ranger 2000 / mage 2000 / assassin 5000 / engineer 5000 / guardian 8000）与 `upgrade_cost` 1500；SaveSystem.unlock_hero 扣蓝晶（不足拒绝）+ `upgraded` 购买写入方；选角页锁标变实锁 + 解锁/强化按钮（蓝晶余额、价格、已强化态三态 UI）。
  - 六技能强化分支按 GDD §6 表逐条接线（狂潮受伤-30% / 影袭无敌+0.6s / 奥术新星半径+40% 冻结 2s / 残影斩残影爆炸 20 伤 / 炮台每 3s 导弹 12 AoE / 法阵内受伤-20%）。
  - 存档 migration：`unlocked_heroes` 默认仅 vanguard + 用户已购态字段；save 版本号 bump + 往返测试扩。
  - 所有权：`data/heroes.json`、`core/meta/**`、`core/player/skills/**`、`autoload/save_system.gd`、`ui/**`（hero_select/成就无关页不动）、新增 `tests/unit/test_m5_hero_unlock.gd`
- **E 局内武器升级台**（#5）：每层固定 1 台（与熔铸台同房不同设施）。
  - 金币升级当前手持武器：+8% 伤害/级，每把武器至多 3 级，价 35/55/80 递增；实例字段 `up_level`（禁止污染 GameDB）；HUD 显示级数角标。
  - 所有权：`core/rooms/**`（新 fixture，注意与 C 卡的房间层改动冲突——**C 只做掉落/货架、E 只做新 fixture 文件**，集成时主会话核冲突）、新增 `tests/unit/test_m5_upgrade_bench.gd`

**W3（并行 3 卡）**
- **F 招募跟随**（#6）：事件房新增「佣兵」事件 + 商店低概率货架；50 金雇佣，场上至多 1 名。
  - 实现路径：从敌人花名册选 3 行（crossbowman/volt_spider/moss_slime）实例化为友军阵营（audit 敌 AI/弹幕阵营判定后加最小 ally 通道），存活 90s 或死亡即消失，跟随玩家、自主索敌开火。
  - 所有权：`core/enemies/**`（友军化）、`core/rooms/**`（事件/货架条目）、`data/events.json`（如存在）、新增 `tests/unit/test_m5_follower.gd`
- **G 每日挑战本地记录**（#7）：试炼模式已有每日种子+抽 2 因子。
  - 新增：试炼结算页记录入本地榜（save 字段 `trial_records`，按蓝晶收益 Top10：日期/种子/因子/收益/时长）；分享码「STF-<seed>-<因子>」复制到剪贴板；试炼入口显示今日最佳。
  - 所有权：`autoload/save_system.gd`（migration）、`ui/**`（trials 相关页）、新增 `tests/unit/test_m5_trial_records.gd`
- **H 皮肤**（#8）：每英雄 1 套换色皮肤（命名：凛-夜霜/苇-赤羽/烬-苍蓝/蝉-墨玉/铆-铜绿/萄-金穗）。
  - 实现路径：先审 `tools/spritegen_m3.py` 参数表——若支持增量生成英雄变体则走表；否则运行期调色板置换（shader/texture 替换），零数值影响；选角页换肤按钮 + save 持久化 `skins` 字段。
  - 所有权：`tools/spritegen*` 或 `fx/`（shader）、`art/**`、`ui/**`（选角页局部）、`autoload/save_system.gd`（与 G 卡冲突——**G 动 records 字段、H 动 skins 字段，migration 冲突集成时主会话核**）、新增 `tests/unit/test_m5_skins.gd`

## 集成与收口（主会话）

每波：merge 三分支（文件所有权零交集预期零冲突；C/E 与 G/H 的房间层/存档层按上面注记的边界核）→ 全量测试 → 冒烟 → push。全部完成后：README/GDD 数量回写（武器 121、新系统条目）、图鉴/成就接线核验、记忆归档、w4 报告。

## 明确不做（本里程碑）

存量数值调参（含孢子手减速——仍待用户真人体感裁定）、在线排行榜（本地榜 only）、角色数量扩张、花园/宠物/坐骑/无尽/双人（backlog 维持）。
