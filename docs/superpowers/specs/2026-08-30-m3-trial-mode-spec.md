# 《星陨地牢》试炼模式量化规格（M3-P0-1 契约）

- 日期：2026-08-30
- 版本：v1.0（M3 先行契约——M2 执行期间定稿，M3 执行期照此落地，不得再改数值）
- 数值出处：本文 + GDD 附录 G.2（因子原文）/ G.1（成就）；**不写入** `2026-08-28-starfall-depths-data-tables.md`（该文件归 M2-T2/T3 所有）
- 对应 GDD：§4.3 局外循环 / §14.1 蓝晶 ×1.5 / §20 M3 / §22 挑战玩法（M3 项）

---

## 1. 定位与入口

- 试炼 = **每日种子 + 挑战因子**的可重复挑战玩法；一局 = 完整 3 层（A1→A3），地牢生成、房型、Boss、掉落规则与正常局完全一致，仅叠加因子与结算倍率。
- 入口：主菜单新增「试炼」按钮 → 试炼面板（今日因子预览 / 今日最佳 / 历史 / 开始）。选角沿用既有选角面板。
- 与挑战房（M1/M2 的灾厄房）无关：两者可叠加（试炼局内遇到挑战房照常生效）。

## 2. 每日种子与因子抽取

- **业务日**：以本地时区 05:00 为刷新点；`t < 05:00` 归前一业务日。`trial_date = 业务日 YYYY-MM-DD`。
- **种子**：`trial_seed = hash("trial" ⊕ trial_date)`（与 GDD §9.1 runSeed 同构的固定盐拼接哈希，实现用 `hash()` 或 `FNV`，一次定稿不得更换——换式即换当日布局）。
- **角色自由选择**：种子不含角色 id（同日所有人同布局，角色差异体现在排行榜）。
- **因子抽取**：从 `data/trials.json` 的 8 条因子中，经 `RunState.stream(RunState.SALT_TRIAL)`（新盐常量，收敛进 RunState——M2 全局约束 2）抽取 `pick_per_day=2` 条；抽取结果按因子 id 排序后使用（保证同日跨会话/跨角色因子组合一致）。
- **墙钟豁免口径**（对 GDD 全局约束 1 的显式豁免，仅此一处）：战斗逻辑仍禁 `Time.*`；试炼**入口**（主菜单/面板）读取系统日期属元游戏调度，允许。种子写入 RunState 后一切随机走 RngSvc 种子链。

## 3. 因子池（8 条，逐字转录附录 G.2；mods 键 = data/trials.json 契约）

| # | id | 名称 | 玩家文案（desc） | mods |
|---|---|---|---|---|
| 1 | `enemy_haste` | 敌人提速 | 敌人移速与攻速 +20% | `enemy_speed_pct:20, enemy_attack_speed_pct:20` |
| 2 | `melee_drops` | 近战洗礼 | 武器掉落只出近战类 | `drop_melee_only:true` |
| 3 | `energy_tax` | 蓝量重税 | 所有武器蓝耗 ×1.5（向上取整） | `energy_cost_mult:1.5` |
| 4 | `bullet_haste` | 弹速风暴 | 敌方弹幕速度 +25% | `bullet_speed_pct:25` |
| 5 | `bargain_ban` | 黑心集市 | 商店半价，但禁止红心 | `shop_discount_pct:50, no_hearts:true` |
| 6 | `narrow_vision` | 管中窥豹 | 视野 -35% | `vision_scale:0.65` |
| 7 | `elite_surge` | 精英潮 | 精英数量 +100% | `elite_bonus_pct:100` |
| 8 | `single_element` | 元素独尊 | 每层限定单一元素附魔 | `force_element:"random"` |

**边界规格（消歧义，实现按此执行；实现者发现未覆盖情形 → 上报编排者，不得自行定夺）：**

- `bullet_haste`：+25% 后仍受 GDD §7.5 上限 **150 px/s 约束（clamp）**——慢弹等比提速、快弹封顶；**预警时间不减免**（公平性契约不动）。
- `no_hearts`：红心掉落位（战斗房/宝箱/精英奖励）替换为等值金币；商店不出现治疗类商品；事件「星髓泉」（盾）与饮料「生命苏打」（上限 +2）**不受影响**（均非红心治疗）。
- `narrow_vision`：暗角遮罩 = 基准视野 ×0.65，**复用 M2-T4 暗视野组件**（CanvasModulate + PointLight2D）参数化实现；与 A2 暗视野叠加时取更暗者（不双乘）。
- `elite_surge`：每层精英房精英数 ×2（同模板双精英）；战斗房 15% 增益祭坛概率改为追加 1 精英；词缀规则不变（A2 单词缀 / A3 双词缀）；精英掉落不变。
- `single_element`：每层从火/冰/毒/电按层种子随机定 1（HUD 显示本层元素）；本层玩家获得的一切元素附魔（武器自带/增益/雕像星髓像）统一转为该元素；敌人抗性与共鸣规则不变。
- `energy_tax`：开火结算时 `ceil(蓝耗 × 1.5)`；蓝上限/回复/空蓝规则不变；面板显示原始蓝耗，实际扣除为准（HUD 蓝耗角标 ×1.5 提示可选）。
- `melee_drops`：武器掉落池过滤 `category == 近战`（含熔铸不变——熔铸材料仍可投入任意武器，产物流不变）。

## 4. 结算与经济

- 蓝晶倍率：试炼局结算 = 正常口径（层通过 + 击杀 + 首杀，M2-T32 交付）**× 1.5，向下取整**（GDD §14.1）。
- 死亡保底：正常 50% → 试炼 **75%**（= 50% × 1.5）。
- 成就接线（G.1 两条，M3 激活；依赖 M2-T33 成就系统）：
  - **试炼者**：完成 1 次每日试炼——死亡、胜利、放弃均计；信号 `trial_completed`（每次试炼局结束发一次，每局至多一次）。
  - **试炼大师**：累计 10 次 `trial_completed`。
- 放弃：暂停菜单新增「放弃试炼」（仅试炼局显示）——按当前进度正常结算（已过层 ×1.5），发 `trial_completed`，回试炼面板。

## 5. 排行榜（纯本地）

- 文件 `user://trial_records.json`：
  ```json
  { "version": 1,
    "records": [ {"date":"2026-08-30","hero_id":"vanguard","deepest_floor":2,
                   "clear_time_s":1043,"gems_earned":180,"victory":false,
                   "factors":["enemy_haste","elite_surge"]} ],
    "daily_best": { "2026-08-30": {"deepest_floor":2,"clear_time_s":1043} } }
  ```
- 每次试炼局结束追加 1 条 `records`；保留最近 **30** 条；`daily_best` 同日多次取「最深层数优先、次取最短用时」。
- 校验 fail-soft：损坏/缺字段 → 重建空表（对齐 SaveSystem fail-soft 设计），不阻断启动。
- UI：试炼面板显示今日因子卡 ×2（名称+文案）、今日最佳、历史最近 10 条（日期/角色/最深/用时/胜利标记）。

## 6. UI 流程

主菜单 → 试炼面板（日期 + 因子预览 + 今日最佳 + 历史 + 开始）→ 选角 → 局内：HUD 左上层数旁增 2 个因子小图标（悬浮显示文案；触屏长按显示）→ 死亡/胜利结算面板标题带「每日试炼」徽标 + 倍率明细行（基础 X × 1.5 = Y）→ 返回试炼面板。

## 7. 数据契约（data/trials.json，由 M3-P0-3 先行交付）

```json
{ "version": 1,
  "refresh_hour": 5,
  "pick_per_day": 2,
  "reward_gem_multiplier": 1.5,
  "factors": [ {"id":"enemy_haste","name":"敌人提速","desc":"敌人移速与攻速 +20%",
                "mods":{"enemy_speed_pct":20,"enemy_attack_speed_pct":20}}, … ×8 ] }
```

- **mods 键白名单**（schema 校验用，超出即 fail-closed）：`enemy_speed_pct / enemy_attack_speed_pct / drop_melee_only / energy_cost_mult / bullet_speed_pct / shop_discount_pct / no_hearts / vision_scale / elite_bonus_pct / force_element`。
- 校验规则：factors 恰 8 条、id 唯一且在 §3 表内、mods 键均在白名单、数值域同 §3 表、`refresh_hour=5`、`pick_per_day=2`、`reward_gem_multiplier=1.5`、`force_element` 值域 `["random"]`。
- M3-P0-3 交付独立校验测试（FileAccess 直读，不依赖 GameDB 接线）；GameDB 正式接线（fail-closed schema）在 M3 执行卡 R-A 落地。

## 8. M3 执行卡映射（见 M3 实施计划）

- **R-A 因子引擎**：`RunState.mods` 单点注入（因子→mods 字典→各系统读 mods，禁止散读 trials.json）+ 每日种子 + SALT_TRIAL + GameDB 接线。
- **R-B 流程与排行榜**：试炼面板/角标/结算徽标 + trial_records 读写。
- **R-C 结算接线**：×1.5 倍率 + trial_completed + 成就 2 条（依赖 M2-T32/T33）。
