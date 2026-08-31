# M2 Gate — Integration Guard Report

- 日期：2026-09-01（编排者执行，T34 集成守卫）
- Repo：`D:\workspace\thomas`，branch `main`，报告基线 `aadda72`（生产代码 tip = m2-t33 merge；含 T37/T33/m2-retest 三合并 + docs 归档提交）
- Godot：`4.7.2.stable.official.ed1daf0bf`（WinGet PATH shim）；gdUnit 6.2.1；Pillow 12.3.0（`python -c "import PIL"` 通过，无环境假红）
- 关合并链（本门禁态）：T36 `a177691` → T35 `125ddc1` → T30 `b4beea9` → **T37（含修复轮 `011f671`）** → **T33（5 提交，含修复轮 `73b3b93`）** → m2-retest 探针现代化 `080d0cb`

## Check 1 — 全量测试 ×2（确定性）：PASS

命令：`godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`（两次独立进程，每次前置清 `save_headless.json` 测试隔离档——裁定㉔口径）。

| 轮 | 结果 |
|---|---|
| 第 1 轮（T33 合并后） | **1399 test cases \| 0 errors \| 0 failures \| 0 flaky \| 0 skipped \| 0 orphans**，77/77 套件，exit 0 |
| 第 2 轮（确定性复跑） | **1399 / 77/77 全绿一致**，exit 0 |

测试账目：M1 终态 570 → M2 终态 **1399（+829）**，77 套件。增量主要来自 34 张内容卡 TDD 用例（含 T37 图集/光圈 22、T33 成就接线+密封 19、T36 路由 14、T28 决策+校准 53 等）。

## Check 2 — 启动烟测：PASS

命令：`godot --headless --path . --quit-after 300` → exit 0，`SCRIPT ERROR` 计数 **0**。

## Check 3 — 地牢生成校验（3 生态）：PASS

`tools/validate_dungeon.gd` 本门禁参数化（`--seeds=N --floors=1,2,3`；**无参默认 = M1 契约 1000×floor1 逐字节不变**，回归确认）：

| 口径 | 结果 |
|---|---|
| M1 契约回归（1000 种子 × F1） | **1000/1000 PASS**，exit 0 |
| **T34 门禁口径（3000 种子 × 3 生态 = 9000 装配）** | **9000/9000 PASS**，exit 0 |

A2/A3 模板池自 T26（`b144647` 修复轮）在库，逐种子逐层 build+validate 全通过——GDD §M2 验收行「1000 种子生成校验通过（3 生态）」超额满足。

## Check 4 — §18.3 性能预算（最终 main，窗口运行）：PASS

命令：`godot --path . res://tests/scenes/perf_probe.tscn`（Windows DisplayServer 真机窗口，vsync 关；探针为 m2-retest 现代化版——densest 按层池自动选型，A3 危险地块走模板生产路径）。**PERF VERDICT: PASS**，exit 0。

| 层（最密模板） | draw avg / max | 逻辑帧 avg | 预算 |
|---|---|---|---|
| F1 `combat_a1_03` | **101.4** / 187 | 0.013 ms | draw ≤150（avg 口径，T29 判定不变） |
| F2 `combat_a2_01` | **102.2** / 166 | 0.013 ms | 逻辑 ≤6ms ✅ |
| F3 `combat_a3_08` | **102.1** / 176 | 0.013 ms | 渲染 CPU ≤10ms ✅（0.023 avg） |

- 压测构成：40 敌满压 + 500 弹打满 + 生态特效全开（A2 暗视野/剪影/冰面、A3 火雨），活动实体 65 ≤300 ✅。
- 对照链：T29 基线 F2 **157.2 FAIL** → T37 首轮 **105.6** → T37 修复轮折叠终态 **101.2** → 本门禁 main 复测 **102.2**——F2 闭环余量 ~32%（证据 `t37-evidence/m2_perf_{before,after,fixround,main_2026-09-01}.json` 四份在档）。
- 口径披露（承 T29/T37）：预算判定取采样窗 avg；max 样本 166~187 为瞬态（掉落/伤害数字爆发拍）；GPU 侧逐帧毫秒无公开 API 未采，以 draw ≤150 间接约束；60fps 能力合成口径 11.1ms ≤16.67ms ✅。

## Check 5 — 存档 v2 往返：PASS（含于 Check 1 两轮全绿）

钉死用例（`tests/unit/test_save.gd`）：`test_roundtrip_persists_all_fields` / `test_v1_save_migrates_to_v2_preserving_all_fields` / `test_migration_v2_idempotent_double_load` / `test_missing_version_migrates_from_zero` / 首杀记录 4 例——两轮 1399 全绿内含，无隔离档泄漏（T33 TestSaveSeal 密闭后极限脏档破坏性验证通过，见 task-33-report §三）。

## Check 6 — 导出冒烟（T30 存档证据）：Windows PASS / Android 诚实 SKIP

T30（`b4beea9`，2026-08-31）：Windows exe 117MB、真 PID 30s 存活、日志零 FATAL/CRASH；Android 无 SDK 本机 SKIP（非 FAIL）。CI/重装机注意导出模板 1.28GB 需缓存（裁定㉘）。

## Check 7 — Balance Bot 胜率带复跑（种子 3001..3010，最终 main）：完成，判定见下

命令：`godot --headless --path . res://tools/balance_bot.tscn -- --runs=10 --seed-base=3001 --out-md/-json=m2-balance-rerun-2026-09-01.*`（墙钟真实速率，批前清 save_headless 与校准批同起点；报告含编排者增补修正工具模板的过时基线叙事）。

| 指标 | 实测 | 判定 |
|---|---|---|
| 结局分布 | **0 胜 / 7 死 / 3 超时 / 0 崩溃**，全止步 F1 | bot 能力瓶颈（非内容缺失）：6/7 死于苦力虫自爆；3 超时为 bot 门槛震荡（telemetry 实证 a1_04/a1_05 逐帧交替） |
| §14.3 胜率带 | 0/10 | **bot 口径不可评**（GDD 带为玩家成长曲线，bot≈纯新手且从未进 F2/F3）→ 真人试玩权威（playtest checklist #1/#2） |
| §14.3 A1 杂兵 TTK | 中位 3.7s vs ≤2.0s | **偏离 1.85×**——平衡发现如实入账，M3 校准点（先采真人数据） |
| §14.3 战斗房时长 | 中位 23.9s（20~40s 带） | 达标 |

详细：`m2-balance-rerun-2026-09-01.md`（含 M3 行动项三条：bot 震荡修复 / 自爆虫死因待真人复核 / laohuoji 输出校准）。

## Check 8 — 仓库卫生：PASS（附披露）

- `git status` 干净面：全部生产/测试/docs 变更已入库（本报告与 m2-gate.md 为最后 docs 提交）。
- 会话脚手架不入库（有意的未跟踪项）：`.tmp_session_extract/`（前会话取证）、`.workbuddy/`、`.tmp_balance_rerun.log/.tmp_balance_done.flag`（本批脚手架，批后随收口清理）。
- 证据归档：`t37-evidence/`（4 PNG + 4 探针 JSON）、`task-33-report.md`、`task-37-report.md`、`m2-balance-rerun-2026-09-01.{md,json}`（批后）。
- 工具变更披露：`tools/validate_dungeon.gd` 参数化（Check 3 契约回归确认无破坏）。

## 门禁判定（集成守卫侧）

**Check 1~6、8 全 PASS；Check 7 完成——bot 口径胜率带不可评（bot 能力瓶颈，telemetry 实证）+ A1 杂兵 TTK 偏离 1.85×（如实入账，M3 校准点）+ 战斗房时长带内达标。** 综合裁定见 `m2-gate.md`。
