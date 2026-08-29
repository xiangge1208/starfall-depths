# M1 Gate Playtest — 《星陨地牢》StarfallDepths

- 日期: 2026-08-28 · HEAD 8b0a5b7 (main, 工作树净) · Godot 4.7.2 · Windows, 窗口 1440×810 (viewport 480×270)
- 方式: 同 M0 门禁 —— 真实窗口 PostMessage 注入 (WM_KEYDOWN/WM_LBUTTONDOWN 带扫描码) + PrintWindow(PW_RENDERFULLCONTENT) 截图 + 遥测读取 + 仓库外临时脚本打印种子 20260828 地牢布局 (只读)。代码零改动。
- 环境局限 (沿袭 M0 门禁记录): 本环境系统级鼠标失效 (GetCursorPos 恒回 (0,0)、SetCursorPos/SendInput 不可用), 游戏内瞄准恒为"向左平射"; 键盘走位/翻滚/交互/菜单可用。
- 证据目录: `docs/superpowers/reports/m1-evidence/` (01–17 号 PNG)。

## Checklist 结果

### 1. 主菜单流 — PASS
main_menu → 设置面板打开 (02) → 点击滑杆改屏震 1.0→0.5、点击开关 伤害数字 off→on，`%APPDATA%\Godot\app_userdata\StarfallDepths\save.json` 即时落盘确认 (before: `screen_shake:1.0,damage_numbers:false` → after: `0.5,true`) (04) → 开始 → 选角 骑士·凛 (05, 金框高亮+被动/技能/初始武器文案齐全) → 点击卡片路由进游戏场景 (06)。
注: ① 键盘焦点导航只能在这 6 个菜单按钮间移动, Tab/方向键均无法把焦点移入设置面板控件, 改设置必须鼠标点击 (真人可用, 键盘全靠边, 无障碍欠佳); ② 选角落地 `SceneRouter.goto("game")` 到的是 **M0 训练房** (training_room.tscn), 不是地牢 —— 路由本身工作正常, 但"进入游戏"≠"进入一局" (见第 2 条)。

### 2. 完整一局到 A2 — PARTIAL (环境受限为主, 另含集成缺口)
菜单流进不了地牢, 改直开 `res://core/rooms/floor_scene.tscn` (自举 seed 20260828 floor1):
- 生成验证 OK: 遥测 `floor_build,0,13` — 13 房/层; 布局打印确认类型齐全: start(0) + combat×6(1,2,3,8,9,10) + elite(5) + miniboss(6) + boss(7) + shop(4) + treasure(11) + event(12), 12 条走廊; start 房已清、东侧门开、进房 combat_a1_08 即锁门(棕色门闸可见, 10/13 号图), HUD `boss门:锁定` 判定存在。
- **未能到达 Boss 房**: 必须先清 miniboss 房才解锁 boss 门 (FloorFlow 规则); 而第 1 间战斗房就无法用注入输入清场 —— 3 次进入 3 次团灭 (遥测 hurt 行: 蝙蝠 3×4 次 12 点打穿 8hp+4sh; 另 2 次为自爆虫贴脸爆炸+弩手), 固定向左平射 vs 追身自爆虫是必败局, 与 M0 门禁记录的操控天花板一致。
- Boss 击杀 → 三选一 → 喷泉 → 第 2 层 整条链路因此未达成。按门禁规则本应记 FAIL ("无法进入 Boss 房"), 但卡点首先是本环境鼠标瞄准失效 (M0 已记录), 生成/锁门/门闸机制本身工作正常, 故按环境受限记 PARTIAL; 真人鼠标瞄准下需复测。
- 附带发现 (客观, 与环境无关): boss 击杀后层间流程**没有接线** —— floor_scene.gd 全文无 InterFloor 引用, boss 死亡仅视为普通清房开门, 永远停在第 1 层; 第 2 层进入在当前 HEAD 无任何路径。

### 3. 房型覆盖 — FAIL (集成为主 + 环境受限)
实际进入: start ✓、战斗房 ✓ (combat_a1_08, 进房/锁门/两波刷怪正常, 10/11/13/14/15 号图) —— 但未清场, 精英(5)/小Boss(6)/Boss(7)/宝箱(11)/事件(12)/商店(4) 房均被第 1 房战斗锁门拦住, 无法到达。≥1 要求 (战斗×3/精英/宝箱/商店/事件/小Boss/Boss) 大面积未满足。
**代码层客观证据 (HEAD 8b0a5b7)**: shop 房与 event 房在 floor_scene 中是"空桩"—— `_build_stub(room, center, "商店（C线未接入）")` / `"事件（C线未接入）"`; Shop(含黑商/回收)、Shrine、DrinkMachine、EventRoom 组件与单测都在盘上, 但没有任何场景实例化它们。买 1 件/回收 1 件/接受 1 次事件在玩家路径上**不存在**。宝箱房有实现 (开箱→roll 武器→掉落台) 但同样未到达。

### 4. 增益三选一 — FAIL
真实流程 (Boss 后) 三选一不出现 —— floor_scene 无 boss 死亡→InterFloor.open() 接线 (见第 2 条)。standalone 直开 `inter_floor.tscn` 复核组件: 中转房渲染正常 (喷泉+下层门+HUD "增益三选一(1/2/3 或点击)", 16/17 号图), 但 **三选一浮层从未渲染**, 按 1/2/3 无反应, 阶段卡死 PICK, 喷泉 E 被阶段门禁拦下。三选一→选择→生效确认 (火焰附魔/强健前后对比) 无法执行。buff_pick.tscn/BuffManager/InterFloorFlow 均有单测且在盘, 属"组件齐全、玩家不可达"。

### 5. 藤蔓巨像三阶段 — FAIL
未到达 Boss 房 (无阶段可观察)。且代码层 Boss 是占位: floor_scene 的 `guest_row("vine_colossus")` 用 vine_charger 行 ×8hp=144、radius16 覆盖, **丢弃了 enemies.json 原行的 `boss_script` 与 `phases:[1.0,0.6,0.3]`** —— 即可玩路径的"巨像"是不带任何阶段招式 (拍击/弹环/横扫/召唤/毒雨) 的普通 charging 怪; 真三阶段 VineColossus 类与 BossBase 框架只在 `guest_spawner` 注入时生成, 而该缝除单测外无人注入。拍击+弹环/横扫+召唤/毒雨 三段标志性招式 0 观察 (占位怪亦未到达)。

### 6. 死亡回顾 — PASS
训练房 (前台为游戏场景) 故意站桩吃 K 弹幕雨致死: 「守夜人陨落」结算面板出现 (07) —— 统计 (房数/击杀/金币/层数/时长 3:57/受击 15 次) + 致死原因回顾 ("最近 3 秒受击 3 次, 共 3 点伤害", 与 DeathRecorder v1 披露的窗口归因口径一致) + 蓝晶结算 "+0（死亡保留 50%）" (gems=0, 公式展示正确, 数额无法验证非零分支) ; 按任意键确认 → 回主菜单 (08)。地牢内 3 次死亡同样走完整结算→主菜单/选角链路, 无崩溃无卡死。
自动化伪影注记: 死亡瞬间仍被按住的键/缓冲点击会被结算面板或主菜单吞掉 (任意键确认+焦点按钮), 出现"秒退面板/连跳到选角" —— 真人单次按键不受影响, 但建议 M2 给确认加 0.5s 输入锁。

### 7. 主观 — 2/5
想开第 2 局的意愿: **2/5**。菜单/选角/死亡结算的"壳"已经像模像样, 训练房手感底子仍在; 但地牢里"一局游戏"的主循环接不起来 —— 第一间战斗房就是当前版本的玩家可达终点, 商店/事件/三选一/三阶段 Boss/下一层全是断头路。承认我的操控是残缺的 (无瞄准), 战斗数值不好下结论; 但流程断点和占位桩是客观的, 这版没有"一局"可言。

## 试玩过程简录 (异常与观察)
1. 三次整局尝试均在第 1 战斗房 (combat_a1_08) 团灭: 蝙蝠环绕蹭 3 伤 ×4 次; 自爆虫 (kuli_bug) 追身后爆炸; 波次锁门期间退路封死。固定向左平射下敌人天然在我右侧, 只有追身怪进入弹道。
2. 子弹穿墙: 玩家/敌方弹幕无墙体碰撞, 隔墙射击/隔墙受击均发生 (13 号图弹道横穿西走廊)。建议 M2 加墙体阻挡或衰减。
3. 训练房与地牢的死亡都会开结算面板, 但训练房自身还有 1.5s 后 reload_current_scene 的 M0 旧接线, 与 DeathRecorder 路由存在竞态双路径 (本次未观察到明显异常, 建议整合时移除旧接线)。
4. 遥测 flush 是惰性的: 进程被杀时未落盘的行丢失 (结束时 CSV 仅剩 `inter_floor_open` 行); kill 行 source 列存在但本局无击杀无法验证取值。建议加周期性 flush 或退场钩子。
5. 层间 standalone 的 HUD 层数显示 "第 0 层" (floor_scene standalone) / "floor1" (inter_floor) 两套口径不一致; RunState.start_run 只在选角/层间自举时调用, 直开地牢时 RunState 恒 0。
6. 环境速记: PostMessage 键盘/鼠标注入对 Godot 窗口全程有效; PrintWindow 截图在窗口部分移出屏幕时仍正常; 菜单键盘焦点可用但进不了设置面板。

## 结论
1 PASS · 2 PARTIAL(环境受限) · 3 FAIL · 4 FAIL · 5 FAIL · 6 PASS · 7 = 2/5
核心症结: M1 各组件 (地牢生成/商店/事件/神龛/层间/三阶段 Boss) 单独成件且测试齐备, 但 **最终整合没上主分支** —— 路由到训练房、商店事件是文本桩、Boss 是占位行、层间无人调用; 再叠加本环境无鼠标瞄准, 玩家路径的可玩内容止步于第 1 间战斗房。

PLAYTEST VERDICT: RED (items: 3, 4, 5; item 2 PARTIAL 环境受限)
