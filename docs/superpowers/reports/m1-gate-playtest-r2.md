# M1 Gate Playtest R2（主循环整合后复测）— 《星陨地牢》StarfallDepths

- 日期: 2026-08-28 · HEAD 9ef819d (m1-t27 整合卡已入 main) · Godot 4.7.2 · Windows, 窗口 1440×810 (viewport 480×270)
- 方式: 沿用 M0/M1-R1 门禁工具链 —— PostMessage 键鼠注入 + PrintWindow(PW_RENDERFULLCONTENT) 截图 + 遥测 CSV + 仓库外临时脚本（按 HUD 实时种子打印地牢布局, 只读）。代码零改动。
- 环境局限（沿袭 R1）: 系统级鼠标失效（GetCursorPos 恒 (0,0)）。R2 新对策: **窗口位置瞄准法** —— 因瞄准取 OS 光标 `(0,0)-窗口原点`, 用 SetWindowPos 把窗口移到计算位置即可改变瞄准方向（实测有效, 见 r2-13 的 kill 行）; 另用后台宏（按住开火+走位+翻滚循环）覆盖人工读屏的 10–30s 延迟。
- 证据目录: `docs/superpowers/reports/m1-evidence/` (r2-01～r2-15 PNG)。

## Checklist 结果

### 1. 主菜单流 — PASS
主菜单 (r2-01) → 设置面板 (r2-02) → 点击 伤害数字 off→`save.json` 即时 `"damage_numbers":false` → 再点回 on→`true`（双向落盘验证）→ 开始 → 选角 骑士·凛 (r2-04, 金框+被动/狂潮/初始武器文案齐全) → 点卡片进 **run_root 真实地牢**: HUD `M1-T10 floor1 | start_a1(start) 已清 | boss门:锁定` + 右上 `第1层/种子/金币` (r2-05)。**4 次开局全部直入生成地牢（4 个随机种子）, 不再是 M0 训练房** —— R1 的"路由到训练房"缺口已修复。键盘焦点流也可全程走通（R2 第 5 局即由空格流在菜单/选角上自动连开）。

### 2. 完整一局到 M1 终点 — PARTIAL（环境受限为主; 主循环已活）
活循环实测: 选角→真实第 1 层→战斗房进房锁门（棕色门闸可见 r2-07）→两波刷怪→击杀记遥测→死亡→结算→主菜单→再开局, 全链自洽。但 4 局均在前期战斗房阵亡, 30 分钟内未能到 Boss:
- 死因固定: 自爆虫 kuli_bug 贴脸爆炸（8 伤）+ 弩兵 3 伤穿盾 —— 固定/扫掠瞄准 + 注入延迟下, 追身自杀虫是必败局（与 R1/M0 记录的操控天花板一致）。
- 扫掠瞄准宏实测拿到 **真实击杀**: 遥测 `kill,5763,kuli_bug,117,laohuoji`（ttk 117 帧, source 列=玩家武器 ✓）、`hurt/hit/fire` 行齐备; 布局打印确认 13 房/层与房型齐全（3 层种子分别验证: combat×6+elite+miniboss+boss+shop+treasure+event+start, 12 走廊）。
- 终局链路接线已上 HEAD（代码核实, R1 的断点已闭合）: `FloorScene.boss_defeated` → `RunRoot._on_boss_defeated` → 嵌 `inter_floor.tscn`（三选一→喷泉→门, 阶段门禁）→ `next_floor_requested` → A2 数据门（M1 无 A2 模板）→ "M1 完结"浮层（run_root.gd OVERLAY_TEXT）。组件单测在盘; 真人鼠标下需复测到 Boss。

### 3. 房型覆盖 — PARTIAL（实走 start+战斗; 其余房型集成已实、环境未达）
实走: start ✓、战斗房 ×3（跨 3 局: combat_a1_06/combat_a1_02 等, 进房/锁门/两波/清房遥测 `floor_enter`/`floor_clear` 正常）、真实 A1 垃圾怪击杀 ✓（kuli_bug）。精英/宝箱/商店/事件/小 Boss/Boss 未走到。
**R1 的 FAIL 根因（空桩）已确认消除（代码核实 HEAD 9ef819d）**: shop 房首进即实例化真 `shop.tscn`（ShopLogic.roll_stock 货单 + RunState 钱包 + 副手回收回调 `_drop_offhand`, 买/回收/闪红拒绝齐全）; event 房进房即开真 EventRoom（神秘商人/乞丐/星髓泉/涂鸦墙 4 选 1, 接受/拒绝/Esc）; treasure 真宝箱→权重 roll 武器→掉落台; 精英/垒主/Boss 走 `REAL_GUEST_ROWS` 真实数据行（双刀蜥人 swift+berserk、自爆王虫 armored+leech、藤蔓巨像 boss_script+phases）——"C线未接入"文本桩仅在设施未建时兜底, 玩家路径上已不存在。实买/回收/接事件的手上验证因未到达商店/事件房而缺失。

### 4. 增益三选一 — PARTIAL（接线已修, 未能实测生效）
R1 两个断点均已在 HEAD 闭合: ① boss 房清→`boss_defeated`→RunRoot 开层间（R1 无任何调用方, 已接）; ② `inter_floor.gd:148` 明确修复"ui_layer 漏挂树——三选一浮层不上树即不可见（孤儿泄漏）"。open() 以 loot 盐流掷三选一并 `buff_pick.open(offerings)`, 选 1→`flow.choose_buff`+`RunState.add_buff`+`apply_to_player`, 阶段推进 BUFF→FOUNTAIN→DOOR（HUD 站点提示三态, R1 已验喷泉/门渲染）。因未击杀 Boss, "选 1 个且生效"无法手上确认。

### 5. 藤蔓巨像三阶段 — FAIL（未观察; 占位问题已在代码层修复）
Boss 房不可达, 三阶段标志招式 0 观察。代码层 R1 的"占位怪覆盖"已修复: `use_real_guests` 默认开, `vine_colossus` 行含 `boss_script`+`phases:[1.0,0.6,0.3]`, `VineColossus extends BossBase` 实现 P0 巨掌拍击/种子弹环（12+12 两波）、P1 藤蔓横扫+召唤蘑菇、P2 毒雨（3 安全区绿圈）。按门禁口径（需现场观察 ≥1 次/阶段）记 FAIL —— 环境受限型, 非集成缺口。

### 6. 死亡回顾 — PASS
两次真实阵亡完整走链: 致命伤→「守夜人陨落」结算面板（r2-10）——统计（房数/击杀/金币/层数/时长 3:07/受击 2 次）+ 致死原因回顾（"最近 3 秒受击 1 次, 共 3 点伤害", 与 DeathRecorder 窗口归因口径一致）+ 蓝晶结算 "+0（死亡保留 50%）" → 任意键确认 → 回主菜单 →（键盘）直接开出下一局（r2-14 顶部新种子 3975969800 为证）。全流程无崩溃。
异常注记（自动化伪影）: ① 离散单发按键有时不触发确认（第 3 局结算面板对 enter/space/esc/点击均无响应, 进程存活仅渲染; **连续按键流则稳定确认**——注入时序/输入队列类伪影, 建议 M2 给确认加 0.5s 输入锁+轮询, 与 R1"秒退"注记同族）; ② 新开局 `DeathRecorder.reset()` 会清 Telemetry 会话文件——跨局遥测不留存（本报告 kill/floor 行为实时抓取, 但进程结束后旧局行不可回溯）。

### 7. 主观 — 3/5
想开第 2 局意愿 3/5（R1: 2/5）。"一局游戏"的主循环这次是真的: 菜单→选角→生成地牢→锁门战斗→击杀结算→死亡回顾→再来一局, 闭环自洽, 死了想再来一把的钩子第一次存在。扣分: 商店/事件/宝箱/层间/三阶段 Boss 仍是我够不到的"下一层"（本环境无瞄准 + 我的注入延迟）, 战斗手感只能评"有牙", 谈不上"好玩"; 若真人鼠标下第 5 项能跑通, 意愿可上 4。

## R1 三个 FAIL 项的复核结论
| R1 项 | R1 判定 | R2 状态 |
|---|---|---|
| 3 房型覆盖 | FAIL（商店/事件是文本桩, 嘉宾占位行） | **集成层已修复**（真商店/真事件/真宝箱/真实嘉宾行均在玩家路径, 代码+单测佐证）; 手上实走仅 start+战斗 → PARTIAL |
| 4 增益三选一 | FAIL（无接线 + 浮层不上树） | **两处断点均已修**（RunRoot 接线 + ui_layer 挂树）; 未实测生效 → PARTIAL |
| 5 藤蔓巨像 | FAIL（占位行丢弃 boss_script） | **占位替换已落地**（真三阶段类在可玩路径）; 未到 Boss 无观察 → FAIL（环境受限型） |

## 试玩过程简录（异常与观察）
1. 瞄准攻关史: R1"恒向左平射"根因 = 瞄准读 OS 光标而 GetCursorPos 恒 (0,0)。R2 用 SetWindowPos 移窗改变 `(0,0)-窗口原点` 方向实现任意瞄准角（`aim <deg>`/扫掠宏）, 实测有效并产出真实击杀; 但配合截图读屏延迟, 近身自杀虫仍无解。
2. 起始房开火会刷屏 `spawn_projectile in base 'Nil'`（WeaponRig.combat 未接线, 起始房非战斗房）—— 无害但吵, 建议 M2 起始房也挂空 CombatSystem 或静默。
3. 敌方弹幕仍无墙体碰撞（沿袭 R1）, 隔走廊被弩兵点名多次。
4. 遥测 flush 周期性落盘正常（fire/hit/hurt/kill 实时可见）, 但开局 reset 清档导致跨局不可回溯（见第 6 条注记②）。
5. 战斗房波次/刷点完全确定（模板 spawn_points + 房号轮转波次）, 可预计算瞄点 —— 本报告宏即此原理。
6. 环境速记: PostMessage 键鼠注入全程有效; 无前台窗口（GetForegroundWindow=0）不影响注入; PrintWindow 对移出屏外窗口正常。

## 结论
1 PASS · 2 PARTIAL(环境受限) · 3 PARTIAL(集成已修/实走不足) · 4 PARTIAL(集成已修/未实测) · 5 FAIL(未观察, 集成已修) · 6 PASS · 7 = 3/5
主循环整合卡（m1-t27）方向性生效: R1 的"路由进训练房/商店事件文本桩/Boss 占位/层间无接线"四大断点在 HEAD 全部闭合, 玩家路径第一次成为"一局游戏"; 剩余缺口集中在"手够不到 Boss/商店/事件"的环境天花板, 建议真人鼠标复测第 2/4/5 项终局链路。

PLAYTEST VERDICT: PARTIAL (items: 2,3,4 PARTIAL; 5 FAIL; 1,6 PASS; 7=3/5)
