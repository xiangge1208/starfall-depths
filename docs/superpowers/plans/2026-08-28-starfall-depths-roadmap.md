# 《星陨地牢》开发路线图与子 Agent 编排方案

- 日期：2026-08-28
- 版本：v1.0
- 依据：[主设计文档](../specs/2026-08-28-starfall-depths-design.md)（GDD）+ [数据表附录](../specs/2026-08-28-starfall-depths-data-tables.md)
- 方法论：superpowers（brainstorming → writing-plans → subagent-driven-development）

---

## 1. 总体开发步骤（里程碑链）

每个里程碑 = 一份独立任务级实施计划（`docs/superpowers/plans/`），独立产出可运行、可测试的软件。前一个门禁通过后，才编写并执行下一个里程碑的计划。

| 里程碑 | 交付物（来自 GDD §20） | 门禁（不过不进入下一阶段） | 计划文件 |
|---|---|---|---|
| **M0 战斗原型** | 移动/翻滚/射击/近战反弹、6 武器、4 敌人、1 战斗房+靶场、Juice v1、伤害/共鸣结算+单测 | GDD §18.5 手感清单全绿（试玩员实测） | [2026-08-28-m0-combat-prototype.md](./2026-08-28-m0-combat-prototype.md) |
| **M1 垂直切片（A1 完整一局）** | 地牢生成+全房型、商店/雕像/饮料/事件、小 Boss+藤蔓巨像、死亡结算+死亡回顾 v1、存档桩、HUD、骑士+游侠、武器 40、增益 15、元素共鸣完整接入战斗 | 新玩家 30min 完整体验 1 层并主动想开第 2 局（试玩员实测）；1000 种子地牢生成校验通过 | M0 门禁后编写 |
| **M2 全内容** | 3 层+6 Boss+6 角色、武器 115、敌人 40、增益 36、熔铸、蓝晶/天赋树/图鉴/成就全通 | GDD §14.3 节奏目标全达标；性能预算达标（60fps/弹 500/draw ≤150） | M1 门禁后编写 |
| **M3 打磨发布** | Juice v2、平衡周（机器人回归）、试炼模式、设置/无障碍、Windows+Android 导出 | 双平台 60fps；无 P0/P1 缺陷；设置项齐全 | M2 门禁后编写 |

Backlog（明确不进 v1，防蔓延，来自 GDD §20/§21）：宠物 → 花园 → 无尽回廊 → 本地双人 → 云存档 → 每日种子排行榜。

## 2. 开发流程（任务卡生命周期）

```dot
digraph flow {
  rankdir=TB;
  plan   [label="编排者：从当前里程碑计划取下一张任务卡", shape=box];
  impl   [label="实现者（全新子Agent）\nTDD: 失败测试→实现→通过→自检→commit", shape=box];
  srev   [label="规格评审员：逐条对照任务卡\nPASS / FAIL+证据", shape=box];
  crev   [label="代码质量评审员：可读性/边界/测试有效性/占位符扫描", shape=box];
  fix    [label="实现者修复（同一子Agent续跑，≤2轮）", shape=box];
  esc    [label="升级：编排者改任务卡或请示用户", shape=box];
  done   [label="编排者勾选任务卡，拉下一张", shape=box];
  gate   [label="里程碑末：集成守卫门禁 + 试玩员实测\n→ 用户验收 → 编写下一里程碑计划", shape=box];
  plan -> impl -> srev -> crev;
  srev -> fix [label="FAIL"];
  crev -> fix [label="FAIL"];
  fix -> srev [label="复评"];
  fix -> esc [label="2轮仍FAIL"];
  crev -> done [label="双PASS"];
  done -> plan [label="还有任务"];
  done -> gate [label="里程碑任务全部完成"];
}
```

硬规则：

1. **一任务一commit组**：实现者按任务卡的 commit 步骤提交，conventional commits（`feat:`/`test:`/`fix:`/`chore:`/`docs:`），message 带任务号（如 `feat(m0-t4): spatial hash`）。
2. **main 永远可运行**：只有双评审 PASS 后的代码才在 main 上（单人+Agent 流，不用特性分支；若需隔离可用 git worktree，见 superpowers:using-git-worktrees）。
3. **测试先行**：可测逻辑（数值/状态/生成/存档）必须 TDD；场景手感类任务的"手动验证"步骤不可跳过，由试玩员复核。
4. **内容表变更**走 Data Steward：改 `data/*.json` 的任务派数据管家，跑 schema 校验 + 掉落分布抽查。
5. **每 5 张任务卡**：试玩员抽查一次手感回归（防 juice/手感在迭代中劣化）。
6. **GDD 数值改动 >±20%**：必须回写 GDD/附录对应表格（GDD 尾注约定）。

### 2.1 并行波次规范（v1.1 增补，用户指令：充分利用并行但不为小事并行）

**规划期（writing-plans 阶段就要做好）**——每张任务卡必须标注两件事，据此预先划波：

1. **依赖**（前置任务卡）；2. **文件所有权**（本卡独占的文件清单，与其他卡不相交）。

**分波规则：**
- 同一波内任务必须满足：依赖已满足 + 文件所有权互不相交 + 各自独立可测（对照 superpowers:dispatching-parallel-agents 的"独立问题域"判定）。
- **值得并行**的下限：单卡预计 ≥ 半天量级的实现工作（如 M0 的 t7/t10/t11 三卡）；纯 5 分钟小修、数据转录小卡不必并行——调度开销反超收益。
- **永不并行**：同文件任务（如共改 `player.tscn` 的 t8/t9）、集成收口任务（t12）、门禁验收（t13）、同一缺陷的修复循环。

**执行期机制：**
- 隔离：每张并行卡一个 git worktree（`.worktrees/<task-id>` + 同名分支），主树留给出波任务；worktree 内先 `--import` 再跑测试。
- 评审与合并：每卡完成即评审（评审是只读的，可与其它卡的实现并行）；评审通过后按序 merge 回 main，main 合并后跑全量测试。
- 并发上限：**每波 ≤3 个实现者**（评审带宽与合并冲突面考虑）。

**M1~M3 计划要求**：任务束分解时直接产出依赖图与 Wave 划分（如 M1 的 D 角色线 / E 数据线 / A 地牢线三线并行），收口线（G/H）串行殿后。

## 3. 子 Agent 职责表（RACI）

> 均由主会话（编排者）通过 Agent 工具派发；除编排者外每个实例职责单一、上下文自足（提示词自带任务卡全文 + 相关 GDD 章节）。

| # | 角色 | 承担者 | 职责 | 输入 | 输出 / 完成标准 |
|---|---|---|---|---|---|
| 0 | **总编排 Orchestrator** | 主会话（我） | 维护路线图与任务卡；派发与调度下述全部子 Agent；组织双评审；里程碑门禁汇总；唯一对用户沟通口。**不写实现代码** | GDD、本路线图、任务计划 | 每任务卡状态更新；门禁报告；向用户汇报 |
| 1 | **实现者 Implementer** | `general-purpose`（每任务全新实例） | 按任务卡逐步实现：写失败测试→实现→测试通过→自检（对照任务卡验收）→commit。允许运行 godot/python/node 命令验证 | 任务卡全文 + 全局约束 + 相邻任务接口签名 | commit 推至 main；自检报告（测试输出贴回） |
| 2 | **规格评审员 Spec Reviewer** | `general-purpose` | 拿任务卡逐条核对 diff：接口签名、数值与 GDD 一致、步骤全执行、无遗漏交付物 | 任务卡 + `git diff` 范围 | `PASS` 或 `FAIL + 逐条证据` |
| 3 | **代码质量评审员 Code Reviewer** | `general-purpose` | 评审代码质量：边界条件、热路径零分配、无占位符/TODO、测试是否真断言、命名与目录约定 | 同上 diff | `PASS` 或 `FAIL + 修改清单` |
| 4 | **数据管家 Data Steward** | `general-purpose` | 批量产出/校验 `data/*.json`（武器/敌人/增益/配方…按附录表转录）；跑 schema 校验与掉落分布抽样 | 附录 A~H 对应表 + schema 文件 | 校验通过的 JSON + 分布抽查结论 |
| 5 | **美术工程师 Artgen Engineer** | `general-purpose` | 维护 `tools/spritegen`（Python+Pillow）与 `tools/sfxgen`（Node）；产出 `art/generated/`、`audio/generated/`；跑调色板/剪影/对比度三重 QA 脚本 | GDD §16/§17 + 部件参数表 | 入库产物 + QA 报告（对比度≥30、剪影可辨） |
| 6 | **试玩员 Playtest Pilot** | `general-purpose` + computer-use 工具 | 启动游戏实机操作：按 GDD §18.5 手感清单逐项验证（输入延迟、翻滚无敌、TTK、反馈触发、可玩性主观项）；截图留证 | 可运行构建 + 清单 | `PASS/FAIL + 每项证据` 的门禁报告（`docs/superpowers/reports/`） |
| 7 | **集成守卫 Integration Guard** | `general-purpose` | 门禁执行者：全量无头测试、1000 种子生成校验（M1+）、性能冒烟（实体/弹幕上限压测）、汇总各报告出结论 | 里程碑门禁清单 | 门禁结论（绿/红 + 缺陷清单） |
| 8 | **平衡机器人 Balance Bot** | `general-purpose`（M2 起启用） | 无头自动游玩整局（启发式走位+随机），统计胜率/死亡热房/DPS 曲线，对照 GDD §14.3 目标值回归 | 可无头运行的游戏 + 统计脚本 | 平衡回归报告（周更） |

**派发提示词模板要点**（编排者拼装）：`你是<角色>。只做任务卡 N。以下是任务卡全文/全局约束/接口签名。完成后输出自检报告。禁止改动任务卡外文件。`——每个实例不携带其他任务上下文，接口靠任务卡的 Consumes/Produces 块传递。

## 4. 环境基线（所有实现者任务的前提）

- **引擎**：Godot 4.x stable（Task m0-t1 安装并锁版本，`godot --version` 写入 `docs/superpowers/reports/env.md`）
- **测试**：GdUnit4（addons/gdUnit4），无头命令 `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests`（Task m0-t1 验证并固化到 `tools/run_tests.cmd`）
- **工具链**：Python 3.12 + Pillow 12（spritegen）、Node 22（sfxgen）、winget（装机）
- **平台**：Windows 11 开发机（win32），Git Bash

## 5. 全局约束（每个任务卡隐含继承，来自 GDD）

1. 逻辑固定 60Hz（`_physics_process`），渲染插值后期再开；禁止在逻辑代码用墙钟（`Time.*`）。
2. 伤害固定值，暴击唯一随机乘区；最终伤害=max(1, int(base×全局乘区×(暴击?2:1)))。
3. 逻辑随机只经 `RngSvc`（种子链），禁 `randi()/randf()`；时间用物理帧计数（60帧=1s）。
4. 热路径（弹幕/粒子/伤害数字）零每帧分配，全部池化；同屏弹幕 ≤500。
5. 全内容数据驱动（`data/*.json`），场景零硬编码数值。
6. 渲染 480×270、nearest 过滤、canvas_items 拉伸。
7. 代码/标识符英文，玩家可见文案中文。
8. 玩法数值以 GDD 附录为准；实现者发现表内矛盾 → 停止并上报编排者，不得自行改表。

## 6. 里程碑内任务束分解（M1~M3 的任务卡粒度预告）

M1（约 22~26 张卡）：A 地牢生成器与校验 / B 房型框架（8 种）/ C 设施（商店黑商/雕像/饮料/事件/喷泉）/ D 骑士+游侠全技能与三端输入（含触屏虚拟摇杆）/ E 武器 40+增益 15（数据管家批量）/ F 藤蔓巨像+小 Boss×2 / G 局流程（选角→层间三选一→死亡结算+死亡回顾 v1→存档桩）/ H HUD+Juice v1.5。
M2（约 30~36 张卡）：三生态机制（暗视野/冰面/岩浆/可破坏掩体）、角色×4、武器至 115+掉落权重+熔铸台、敌人至 40+精英词缀、Boss×5、增益至 36、蓝晶/天赋树/图鉴/成就、音频全套、死亡回顾完整。
M3（约 12~16 张卡）：Juice v2、平衡周（Balance Bot 周回归 ×2）、试炼模式、设置与无障碍（屏震/色弱形状/自动瞄准开关）、双平台导出与性能达标。

## 7. 风险触发的流程调整

| 触发信号 | 调整动作 |
|---|---|
| M0 门禁 FAIL（手感不达标） | 只允许改手感参数（GDD §5.2/§5.3 数值域内）再测 2 轮；仍不达标→升级给用户改设计数值 |
| 同一任务卡 2 轮修复仍 FAIL | 编排者拆卡重写，必要时升级用户 |
| 无头测试发现 GDD 表矛盾 | 冻结相关任务卡 → 修 GDD/附录 → 提交 → 继续执行 |
| 性能冒烟超标 | 先降粒子→再降实体上限→最后才考虑架构变更（升级用户） |
| Godot/平台环境阻塞 >半天 | 切换备选安装方式（官网 zip 直装），必要时升级用户 |
