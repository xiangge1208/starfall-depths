# M2 门禁综合报告（全量内容：3 层生态 × 6 Boss × 6 角色 × 武器 115）

- 日期：2026-09-01（T34，编排者执行）
- 裁定：**GREEN（附条件）**——附条件 = 真人试玩 checklist（`m2-gate-playtest.md` 十项）作为 M3 开工前常设验证项 + 两项量化偏离随 M3 校准卡收口（见下）
- 分项报告：[集成守卫](./m2-gate-integration.md)｜[试玩（PENDING-USER）](./m2-gate-playtest.md)｜平衡复跑 [m2-balance-rerun-2026-09-01.md](./m2-balance-rerun-2026-09-01.md)｜性能四份探针证据 [t37-evidence/](./t37-evidence/)
- 基线：main `aadda72`（T37 修复轮 + T33 预检合并后；validate_dungeon 参数化在其后一提交）——M2 计划 34 卡全部合入（T1~T37 + prophet 补卡 + 复测）

## 1. 集成守卫（八项检查）

| 检查 | 结果 |
|---|---|
| 全量测试 ×2（确定性） | **1399/1399 绿 ×2**，77 套件，0 orphans，exit 0（M1 终态 570 → +829） |
| 无头启动烟测 | exit 0，0 SCRIPT ERROR |
| 地牢生成校验 | M1 契约回归 1000/1000 + **门禁口径 3000 种子 × 3 生态 = 9000/9000 PASS** |
| §18.3 性能预算（窗口真机） | **PERF VERDICT PASS**：F1 101.4 / F2 102.2 / F3 102.1 draw avg（≤150）；逻辑 0.013ms（≤6）；渲染 CPU 0.023ms（≤10）；实体 65（≤300）；弹幕 500 封顶——F2 超标闭环链 157.2→105.6→101.2→102.2 全程在档 |
| 存档 v2 往返 | 迁移/幂等/首杀合并用例含于两轮全绿（T31 契约） |
| 导出冒烟（T30） | Windows PASS（117MB exe 30s 存活零崩溃）；Android 无 SDK 诚实 SKIP |
| Balance Bot 复跑（3001..3010） | 0 崩溃；**胜率带 bot 口径不可评**（bot 止步 F1：自爆虫死因 6/7 + 门槛震荡超时 3，telemetry 实证非游戏死锁）；战斗房时长带内达标；A1 TTK 3.7s 偏离 1.85× |
| 仓库卫生 | 干净（会话脚手架披露不入库；证据全归档 docs） |

## 2. 试玩（PENDING-USER，十项 checklist）

环境约束（系统鼠标注入禁用，M0 起不变）使真人项无法由 Agent 代做。十项 checklist 已备（完整 3 层通关 / 三层 Boss 三阶段 / 藤蔓巨像 90~150s〔M1 补录①〕/ A2 光圈弹幕可读性〔裁定㉙ handoff〕/ 全房型 / 三选一生效 / 熔铸实操作 / 图鉴成就抽查 / 死亡确认锁 / 主观 ≥3/5）。代码层先行证据（路由测试、成就接线 13 例、像素证据等）已逐项挂接。

## 3. 两项量化偏离（如实入账，不凑数）

| 偏离 | 实测 | 目标 | 处置 |
|---|---|---|---|
| A1 杂兵 TTK | 3.7s 中位（bot, vanguard+laohuoji, n=91） | ≤2.0s | M3 校准卡：先采真人数据（bot 命中率低于人），再定 laohuoji 输出 +20~30% 或杂兵 HP 下调 |
| §14.3 胜率带 | bot 0/10 | 新手 ~10% 起 | bot 无 F2/F3 覆盖能力，权威口径=真人试玩 checklist #1 |

## 4. 裁定

- **集成守卫 GREEN**（六项 PASS + 两项如实入账偏离 + bot 不可评项有 telemetry 实证与 M3 行动项）。
- **试玩 PENDING-USER** → 沿 M1 先例判 **GREEN（附条件）**：tag `m2` 不因真人项阻塞（M1 同例），真人 checklist 转入 M3 开工前常设验证项；若真人项出现 FAIL，按严重度定 M3 首卡修复或回滚合并 m3-prelude。
- 依据：M1 门禁先例（代码层证据 + 无头全循环烟测可替代环境受限的实走验证）；M2 的对应代码层证据面（1399 绿 ×2、9000 装配校验、成就/路由/锁定接线测试钉死、四份探针证据、像素级视觉证据）较 M1 更厚。

## 5. 移交 M3 的记录项

- 真人试玩十项（playtest checklist，常设）
- 平衡三行动项（bot 门槛震荡修复 / 自爆虫死因真人复核 / laohuoji TTK 校准）
- T33 移交清单：8 项派味特技 0/8 + 英雄被动 5 条 data-only（spare_parts/echo/blessing/hawk_eye/shadow_reap）+ collector/grand_collector 数据源写入方（codex_seen）+ demolition 待可破坏物机制
- T35 移交：10 个无消费者增益键（rig 5 + 展示 3 + heart_sense + anti_poison）→ M3 combat/resonance 侧
- T37 披露：A2 光圈内伤害数字/FX 粒子无增亮（弹幕已折叠补偿、预警纹已回真实光照）——真人核验若不足再议
- 双平台 60fps（GDD §M2 行注：归 M3）；m3-prelude 分支 7 提交待本门禁后合并
- 导出模板缓存（裁定㉘）适用于任何 CI/重装机

## 6. 门禁结论

**集成守卫 GREEN + 试玩 GREEN（附条件）→ M2 门禁通过**，git tag `m2`。真人试玩与两项量化校准为 M3 开工前置/首卡。
