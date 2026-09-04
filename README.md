# 星陨地牢 Starfall Depths

> Godot 4.7 像素风 Roguelike 弹幕射击地牢爬行——对标《元气骑士》的可玩性硬指标。
>
> A pixel-art roguelite dungeon crawler built with Godot 4.7, benchmarked against *Soul Knight*.

## 简介

《星陨地牢》是一款俯视角像素 Roguelike：翻滚、射击、近战反弹、元素共鸣，每局随机生成地牢，
局内构筑武器与增益，局外用蓝晶点亮天赋树、扩充图鉴、解锁成就。v1 内容已全量交付并通过
里程碑门禁（M0–M4），集成守卫全绿。

## v1 内容一览

- **3 大生态 × 多层地牢**：随机生成、全房型、事件房 / 商店 / 雕像 / 饮料机
- **6 名可操作角色**，各自手感和构筑倾向
- **115 把武器**（近战反弹 / 远程弹幕）、**40 种敌人**、**36 种增益**
- **元素共鸣**：属性叠加触发战斗层共鸣结算
- **6 个 Boss** + 小 Boss（藤蔓巨像等）
- **熔铸**系统：局内武器合成与强化
- **局外成长**：蓝晶经济、天赋树、图鉴解锁、24 项成就（全接线）
- **试炼模式**：独立挑战入口与结算
- **Juice v2**：打击感、屏震、粒子、音画反馈全套
- 存档 v2（跨局成就/图鉴/经济持久化），Windows + Android 双平台导出

## 运行

1. 安装 [Godot 4.7](https://godotengine.org/download)（标准版即可，无需 .NET）。
2. 用 Godot 打开本仓库根目录的 `project.godot`，按 F5 运行。

或直接运行已导出的 Windows 成品：`user_export/starfall.exe`（本地构建产物，不入库）。

## 测试与工具

| 脚本 | 用途 |
|---|---|
| `tools/run_tests.cmd` | 跑 gdUnit4 全量测试（M4 门禁口径 1839 用例全绿） |
| `tools/run_balance.cmd` | 平衡机器人回归（数值带校验） |
| `tools/export_smoke.cmd` | Windows 导出冒烟 |
| `tools/export_android.cmd` | Android 导出（release keystore 在仓库外注入，见 `.gitignore` 注释） |

质量基线（M4 门禁）：1839 测试绿、零孤儿资源、9000 随机种子地牢生成校验通过、
存档 v2 往返 99/99、成就 24/24 接线核验、经济判定入档。

## 目录结构

```
addons/       gdUnit4 测试框架
art/          像素素材（精灵 / 字体 / UI）
audio/        音乐与音效
autoload/     全局单例（音频、事件总线、存档、场景路由、RNG 服务…）
core/         战斗 / 地牢生成 / 经济等核心逻辑
data/         数据表（JSON，schema 校验）
docs/         GDD 主设计文档 + 数据表附录 + 里程碑计划与门禁报告
fx/           特效
tests/        gdUnit4 单元 / 场景测试
tools/        测试、平衡回归、导出脚本
ui/           界面场景
```

## 里程碑

| Tag | 里程碑 | 交付 | 门禁 |
|---|---|---|---|
| `m0` | 战斗原型 | 移动/翻滚/射击/近战反弹、6 武器、4 敌人、Juice v1 | 手感清单全绿 |
| `m1` | 垂直切片 | 完整一局（A1）：地牢生成、商店/雕像/事件、Boss、HUD、存档桩 | 30 分钟新玩家完整体验 + 1000 种子校验 |
| `m2` | 全内容 | 3 层 6 Boss 6 角色、115 武器、40 敌人、36 增益、熔铸、天赋树/图鉴/成就 | 节奏目标达标 + 1000 种子 × 3 生态 + 性能预算 |
| `m3` | 打磨发布 | Juice v2、平衡周、试炼模式、设置/无障碍、双平台导出 | 1654 测试、9000 种子、双机 60fps（附条件关闭） |
| `m4` | v1 补完与校准 | 13 张补完/校准卡全并 | 1839 测试、零孤儿、存档 99/99、成就 24/24（附条件：LOGO 定稿、Android 真机等真人数据项） |

## 文档

- [主设计文档（GDD）](docs/superpowers/specs/2026-08-28-starfall-depths-design.md)
- [数据表主文档](docs/superpowers/specs/2026-08-28-starfall-depths-data-tables.md) 与附录（天赋树 / 图鉴 / 成就接线）
- [开发路线图](docs/superpowers/plans/2026-08-28-starfall-depths-roadmap.md)
- 各里程碑实施计划：`docs/superpowers/plans/`；门禁与审计报告：`docs/superpowers/reports/`

## 开发方式

单人 + 子 Agent 编排流程（superpowers 方法论）：任务卡 → TDD 实现 → 规格评审 + 代码评审双 PASS
→ 合入 main；里程碑末跑集成守卫门禁。约定见路线图 §2；conventional commits，任务号入 message。

Backlog（v1 明确不做）：宠物、花园、无尽回廊、本地双人、云存档、每日种子排行榜。
