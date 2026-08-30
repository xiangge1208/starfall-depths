# 《星陨地牢》Juice v2 量化规格（M3-P0-2 契约）

- 日期：2026-08-30
- 版本：v1.0（M3 先行契约——M2 执行期间定稿，M3 执行期照此落地）
- 数值出处：本文（M3 专属契约，不写入数据表附录——该文件归 M2-T2/T3 所有）；时长/幅度运行期入 `data/balance.json`（新建，M3 拥有）
- 对应 GDD：§2 支柱 1（手感即正义）/ §5.3（Juice v1 预算表）/ §16.2 / §17 / §18.3
- 红线：**表现与判定分离**——v2 一切效果不得改变任何数值与判定；设置三开关（屏震/伤害数字/hitstop）全关后游戏可正常通关（无障碍验收线）；§18.3 预算不破（逻辑 ≤6ms / 渲染 ≤10ms / 粒子池化零分配）

---

## 1. v1 基线（M0 已交付，v2 不重复实现）

敌方白闪 60ms + 击退 4px + 火花粒子 + 命中音；暴击数字 1.5× + hitstop 40ms；击杀 hitstop 60ms + 爆散粒子 + 掉落吸附；玩家受击红晕 0.3s + 屏震(轻 2px/0.12s) + 闷响 + i-frame 闪烁；翻滚残影 3 帧 + 尘土；Boss 阶段切换 hitstop 120ms + 屏震(重 6px/0.25s) + 全屏闪光。

## 2. v2 升级项

### J1 hitstop v2 + 慢速演出（分层时间缩放）

| 事件 | v1 | v2 参数（ticks，60Hz） |
|---|---|---|
| 普通击杀 | 60ms 定值 | **80ms 缓出**：前 20ms 全冻结 → 后 60ms 线性恢复 |
| 多杀（0.3s 内第 3+ 杀） | — | 追加 40ms（与击杀 hitstop 叠加封顶 120ms） |
| Boss 阶段切换 | 120ms | 120ms + 后接 **0.3× 慢速 240ms** |
| Boss 死亡 | — | **定格 300ms → 0.3× 慢速 900ms**（见 J7） |
| 玩家死亡 | — | **0.3× 慢速 600ms** + 去饱和渐入 0.4s → 死亡结算 |

- 实现口径：时间缩放只作用于**表现层**（`Engine.time_scale` 包裹或局部节点 `process_rate`），判定在缩放前已完成，不产生二次判定/二次掉落；`hitstop_enabled=false`（既有设置语义扩展为总开关）时全部跳过。
- 所有时长/倍率入 `data/balance.json` 的 `juice` 节（场景零硬编码）。

### J2 屏震 v2（trauma 系统）

- 替换 v1 定值屏震：`trauma ∈ [0,1]`；事件注入（受击 +0.3 / 爆炸 +0.4 / Boss 拍地与死亡 +0.5~1.0，逐来源登记表入 balance.json）；衰减 **1.6/s**；位移 = `trauma² × 8px`，旋转 = `trauma² × 2°`；噪声 `FastNoiseLite`（seed 固定 42，x 轴随时间推进）。
- 既有设置档 `screen_shake 0/50/100` 映射为幅度系数 **0 / 0.5 / 1.0**。
- 接线点：`fx/game_camera.gd`（M3 执行期 rebase 后与 M2 产物核对所有权——M2 波次表未认领该文件）。
- 晕动防线：trauma 峰值 ≤1.0、单事件注入 ≤0.5、默认档 50%。

### J3 粒子与命中表现 v2

- 命中火花：色块粒子 → **4 帧火花条带**（P0-4 素材包）；通用 `spark_hit_strip4`，元素命中换 `spark_{fire|ice|poison|shock}_strip4`（电元素代码命名为 `shock`，见 `core/combat/elements.gd`；素材文件名已对齐代码），暴击 `spark_crit_strip4`（金色 + 1.3× 缩放）。
- 击杀爆散：v1 爆散之上叠加 **6 帧碎片环** `kill_shard_strip6`；掉落吸附保持 v1。
- 枪口焰：`fx_muzzle` 单帧 → `muzzle_v2_strip3` 三帧，按武器类别 tint（步枪/霰弹/激光三组预设色）。
- 粒子预算：同屏粒子 **≤200**；全池化、热路径零分配；超预算自动降级（关帧动画退化为单帧贴图）——对齐 GDD §18.3「先降粒子」预案的第一档。
- 残影维持 v1 节点复制方案（无新素材）。

### J4 伤害数字 v2

- 暴击：定值 1.5× → **弹跳缓动**（scale 1.0→1.6→1.3，0.18s，tween）+ 金色描边。
- 元素 tick 跳字（燃烧/中毒/岩浆 DOT）：元素色、0.8× 小号、不弹跳。
- 屏外目标不生成跳字（视野裁剪）；`damage_numbers=false` 全跳过（既有设置）。

### J5 连击音高（GDD §17 落地）

- 连击窗口 **1.2s** 内连续命中累计 combo；命中音 `pitch_scale = 1.0 + 0.02 × min(combo, 6)`（+2 音分/次，封顶 +12 音分）；换武器 / 脱战 1.2s / 受击重置。
- 接线：M2-T5 契约 `audio_mgr.play(key, pitch_scale)` 已留参——v2 只维护 combo 计数器（新 `core/combat/combo_counter.gd` 纯逻辑类，TDD 友好）。

### J6 低血与受击增强

- 低血（2 HP ≥ HP > 0）：红晕 vignette **呼吸**（0.8s 周期正弦，alpha 0.15~0.35）+ 心跳音（若 M2 已接 `lowhp_heartbeat` 则复用其触发，不重复接线）。
- 受击：v1 红晕基础上加 **受击方向指示**（以玩家为中心的 8px 弧形闪光指向伤害来源，0.2s 淡出）。
- （Android）受击振动 30ms / Boss 死亡 80ms：新设置键 `vibration`（默认开），仅 Android 生效。

### J7 Boss 死亡定格（演出链）

定格 300ms → 白闪 + trauma 1.0 屏震 + 0.3× 慢速爆散 900ms（尸体碎片 + kill_shard 环）→ 战利品延迟 300ms 喷出（视觉聚焦）→ 恢复时计。整链 `boss_defeated` 信号驱动，可被跳过（连按攻击键快进——respect 老玩家节奏）。

## 3. 素材依赖（M3-P0-4 先行交付，本卡只消费）

`spark_hit_strip4 / spark_crit_strip4 / spark_fire_strip4 / spark_ice_strip4 / spark_poison_strip4 / spark_shock_strip4 / muzzle_v2_strip3 / kill_shard_strip6`（另有试炼图标 `trial_gate.png` / `trial_medal.png` 归 R-B 消费）——由 `tools/spritegen_m3.py` 生成于 `art/generated/fx/`；ArtLookup 注册 + 池化消费在 M3 执行卡 J-C 落地，届时向 `tests/unit/test_art_lookup.gd` 追加存在性断言（沿用 M2-T28 模式）。

## 4. 验收（M3 执行期）

- 手感：GDD §18.5 清单全绿 + v2 增项逐条实测（hitstop 缓出可感、trauma 屏震不晕、连击音高可闻、Boss 定格演出完整且可跳过）。
- 性能：§18.3 压测场景 **叠加 v2 全特效** 后 60fps 全指标达标。
- 无障碍：三开关全关 + `vibration=false` 下完整通关一局，无任何判定/信息损失。
