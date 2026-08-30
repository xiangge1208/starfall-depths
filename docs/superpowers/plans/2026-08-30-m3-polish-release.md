# M3 打磨发布 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task-by-task, organized by the Wave table (roadmap §2.1 并行波次规范). Steps use checkbox (`- [ ]`) syntax.

- 日期：2026-08-30
- 前置：M2 门禁（tag `m2`）通过后进入执行期；**先行批次（P0，4 卡）不依赖 M2，已于 M2 执行期间在 `m3-prelude` 分支交付**（见下表）。
- 依据：[GDD §20/§22](../specs/2026-08-28-starfall-depths-design.md) + [试炼模式规格](../specs/2026-08-30-m3-trial-mode-spec.md) + [Juice v2 规格](../specs/2026-08-30-m3-juice-v2-spec.md)

**Goal:** Juice v2、试炼模式（每日种子+挑战因子）、设置项齐全（含按键重映射/音量/振动）、平衡周回归 ×2、Windows+Android 双平台 60fps 导出包——达成 M3 门禁（无 P0/P1 缺陷、双平台 60fps、设置项齐全）。

**Architecture:** 延续 M0~M2 既有架构，**无新 autoload**（audio_mgr 已随 M2-T5 交付）；新增：试炼因子引擎（RunState.mods 单点注入）、trauma 屏震（game_camera 升级）、combo_counter 纯逻辑类、`data/balance.json`（Juice 数值节）、设置面板/重映射 UI 线、`user://trial_records.json` 本地排行榜。

**Tech Stack:** Godot 4.7.2 / GDScript / GdUnit4 6.2.1（锁定，勿升级）。

## Global Constraints（继承 M1/M2 + M3 增补）

1~7 同 M2 计划（60Hz 逻辑帧；固定伤害暴击唯一随机乘区；RNG 只经 RunState 分盐且盐常量收敛；数据驱动 schema fail-closed；热路径零分配；合并后先 `--import` 再全量测试；TDD + worktree 隔离 + 每波 ≤3 实现者 + 每束末卡集成收口）。

8. **表现与判定分离**：Juice v2 一切效果不得改变数值/判定；设置三开关全关可正常通关。
9. **试炼因子单点注入**：全系统只读 `RunState.mods`，禁止散读 `data/trials.json`。
10. **墙钟豁免仅限试炼入口读日期**（试炼规格 §2）；战斗逻辑仍禁 `Time.*`。
11. **平衡修订窗口**：仅 B-1/B-2 卡可改数值，且限 `data/balance.json` 与 `data/*.json` ±20% 内；超限回写 GDD/附录并经编排者确认（roadmap 硬规则 6）。
12. **文档所有权**：M3 不修改 `2026-08-28-starfall-depths-data-tables.md`（M2-T2/T3 拥有，附录 I/J/K 所在）与 M2 计划/路线图；M3 契约以 P0-1/P0-2 规格文件为数值出处。

## 先行批次（P0——M2 期间交付于 `m3-prelude` 分支，不依赖 M2 的部分）

| 卡 | 内容 | 交付物 | 状态 |
|---|---|---|---|
| P0-1 | 试炼模式量化规格（因子池 8 条边界口径/每日种子/排行榜/成就接线/蓝晶 ×1.5） | `docs/superpowers/specs/2026-08-30-m3-trial-mode-spec.md` | ✅ |
| P0-2 | Juice v2 量化规格（hitstop v2/trauma 屏震/粒子 v2/伤害数字 v2/连击音高/Boss 定格） | `docs/superpowers/specs/2026-08-30-m3-juice-v2-spec.md` | ✅ |
| P0-3 | 试炼数据表 + 独立 schema 校验测试 | `data/trials.json` + `tests/unit/test_trials_data.gd` | ✅ |
| P0-4 | Juice v2 特效素材包（确定性生成器 + 三重 QA） | `tools/spritegen_m3.py` + `art/generated/fx/*_strip*.png` + `art/generated/fx/MANIFEST_M3.md` | ✅ |
| P0-5 | 像素中文字体资产捆绑（遗漏补查 2026-08-30：M1 遗留「尚缺字体」，M2/M3 均未认领） | `art/fonts/fusion-pixel-12px-monospaced-zh_hans.ttf` + OFL 许可 + README | ✅（接线随 S-C） |
| P0-6 | 试炼因子图标 ×8（R-B 的 HUD 角标/面板因子卡素材） | `art/generated/trials/factor_*.png` ×8（MANIFEST_M3.md 追加节） | ✅（接线随 R-B） |

> 遗漏补查（2026-08-30 二次审计）结论：对照 GDD §20/§22/§19/§5.3、附录 G.2 与 M1 遗留清单，补入 P0-5 字体、S-C 字体接线、X-C 的 LOGO 生成、R-B 因子图标注记四处；其余 M3 交付物（Juice v2/平衡周 ×2/试炼/设置含重映射/双平台导出 60fps/无障碍）均已由 J/R/S/B/X/G 束覆盖。

**先行批次隔离声明**：P0 全部为**新增文件**，与 M2 全部 34 卡（W0~W11）的文件所有权清单**零交集**（M2 拥有 `data/weapons|enemies|buffs|heroes.json`、`core/**` 大部、`art/generated/{characters,enemies,tiles,projectiles}`、`tools/gen_placeholder_art*.py`、数据表附录文档等，P0 一概未触碰）；`git diff main..m3-prelude` 全部为新增文件，M2 门禁合入 main 后本分支 rebase 即可并入，预计零冲突。**约束**：M2 执行期间本分支只做 P0，不开任何执行期卡（执行期卡全部依赖 M2 交付物）。

## 对 M2 交付物的接口依赖（执行期前置核对表）

| M2 卡 | 交付物 | M3 消费方 |
|---|---|---|
| T5 | audio_mgr（`play(key, pitch_scale)` + 音量设置接口） | J5 连击音高 / S-A 音量 UI |
| T4/T7 | 暗视野组件（CanvasModulate+PointLight2D）/ SlowZone 基类 | R-B `narrow_vision` 因子 |
| T27 | `tools/balance_bot.gd` 无头自动游玩 | B-1/B-2 平衡周 |
| T31 | `export_presets.cfg`（Windows + Android debug 链） | X-A/X-C 导出线 |
| T32 | 蓝晶结算完整口径（层通过+击杀+首杀） | R-C 试炼 ×1.5 结算 |
| T33 | 成就系统（22 激活 + 2 条 M3 预留：试炼者/试炼大师） | R-C 成就接线 |
| T2/T15 | 天赋树（附录 I 24 节点） | 门禁设置齐全核对（无改动，仅回归） |

## 执行期波次总表（依赖 tag `m2`；每波 ≤3 实现者，束间文件所有权互不相交）

| 波 | 卡 | 内容 | 依赖 | 独占文件（摘要） |
|---|---|---|---|---|
| W1 | J-A | hitstop v2 + 慢速演出 + Boss 死亡定格（J1/J7/J6 死亡段） | m2 | `data/balance.json`(新), `fx/hitstop_director.gd`(新), `core/enemies/boss_base.gd`(1 信号), `tests/unit/test_hitstop.gd`(新) |
| W1 | R-A | 试炼因子引擎 + 每日种子 + GameDB 接线（试炼规格 §2/§7） | m2 | `core/meta/trial_system.gd`(新), `autoload/run_state.gd`(mods+SALT_TRIAL), `data/trials.json`(接线校验), `tests/unit/test_trial_system.gd`(新) |
| W1 | S-A | 设置面板 UI + 音量接线 + 振动键 + 持久化 | m2 | `ui/settings_panel.gd(+tscn)`(新), `ui/main_menu.gd`(1 挂钩), `tests/unit/test_settings_ui.gd`(新) |
| W2 | J-B | trauma 屏震 + 连击音高（J2/J5） | J-A | `fx/game_camera.gd`, `core/combat/combo_counter.gd`(新), `tests/unit/test_combo_counter.gd`(新) |
| W2 | J-C | 粒子表现 v2：火花/枪口焰/碎片环接线 + 预算降级（J3/J4） | J-A,P0-4 | `core/art/art_lookup.gd`(注册段), `fx/particles_*.gd`, `tests/unit/test_art_lookup.gd`(追加) |
| W2 | R-B | 试炼流程 UI（面板/角标/结算徽标）+ 本地排行榜（试炼规格 §5/§6） | R-A | `ui/trial_panel.gd(+tscn)`(新), `core/meta/trial_records.gd`(新), `tests/unit/test_trial_records.gd`(新) |
| W3 | S-B | 按键重映射（动作列表/监听/冲突检测/恢复默认/InputMap 动态重载） | S-A | `ui/rebind_panel.gd(+tscn)`(新), `autoload/save_system.gd`(key_rebinds 键), `tests/unit/test_rebind.gd`(新) |
| W3 | S-C | 像素中文字体全局接线（主题/字号/nearest 渲染；素材已随 P0-5 捆绑） | S-A,P0-5 | `ui/m3_theme.tres`(新), `project.godot`(gui/theme), `ui/*.gd`(字号覆盖核对), `tests/scenes/font_render_smoke.gd`(新) |
| W3 | R-C | 试炼结算接线：×1.5 倍率 + `trial_completed` + 成就 2 条激活 | R-B | `core/rooms/inter_floor_flow.gd`(结算行), `core/meta/achievement_system.gd`(2 条接线), `tests/unit/test_trial_settle.gd`(新) |
| W3 | X-A | Android release 签名 + release preset + aab/apk 产出冒烟 | m2 | `export_presets.cfg`, `tools/export_android.cmd`(新), `docs/superpowers/reports/m3-android-export.md` |
| W4 | B-1 | 平衡周 1：Balance Bot 100 局回归 → 报告 → 修订窗口 1 | R-A(因子可注入) | `docs/superpowers/reports/m3-balance-w1.md`, `data/balance.json`(±20%), `data/*.json`(±20%) |
| W4 | J-D | Juice 收口：设置开关矩阵全关回归 + §18.5 清单 + 触感接线核对 | J-B,J-C | `tests/scenes/juice_smoke.gd`(新), `docs/superpowers/reports/m3-juice-checklist.md` |
| W5 | B-2 | 平衡周 2（含 Juice v2/试炼上线后回归）→ 修订窗口 2 → §14.3 终判 | B-1,J-D | `docs/superpowers/reports/m3-balance-w2.md`, `data/*.json`(±20%) |
| W5 | X-B | 双平台 60fps 达标：目标机复测 + 超标降级预案（粒子→实体）执行 | X-A,J-D | `docs/superpowers/reports/m3-perf.md`, `tests/scenes/perf_probe.gd`(复用 M2-T29) |
| W6 | X-C | 导出包收口：版本号/图标/存档 v2 兼容/双包启动冒烟 | X-B,B-2 | `export_presets.cfg`, `docs/superpowers/reports/m3-export-final.md` |
| W6 | G-1 | **M3 门禁**：集成守卫（全量绿+3000 种子+§18.3+存档往返）+ 试玩员（Windows 全流程 + Android 触屏全流程含试炼局 + v2 手感清单）+ 设置项齐全核对 + 裁定 tag `m3` | 全部 | `docs/superpowers/reports/m3-gate-*.md` |

> 计 21 卡 = P0 先行 6 + 执行期 16（J×4 / R×3 / S×3 / B×2 / X×3 / G×1）。执行期 16 卡含 roadmap §6 预告口径（12~16）上沿（预告不含 P0 设计卡与遗漏补查的 S-C 字体接线）。每束末卡收口：J-D（Juice 束）/ R-C（试炼束）/ X-C（导出束）。

---

### Task J-A: hitstop v2 + 慢速演出 + Boss 死亡定格

**Files:** Create `data/balance.json`（`juice` 节全参数）、`fx/hitstop_director.gd`（单例语义的纯逻辑导演类：请求队列 + 冻结/慢速状态机 + 缓出曲线）、`tests/unit/test_hitstop.gd`；Modify `core/enemies/boss_base.gd`（死亡信号 1 行）、Boss/玩家死亡调用点（各 ≤3 行）
**规格:** 试炼规格引用 J1/J7/J6 死亡段参数表；`hitstop_enabled=false` 全跳过；时间缩放仅表现层；全部时长读 balance.json。
- [ ] TDD：请求叠加封顶（120ms）/缓出曲线采样点/慢速进入-恢复时序/hitstop_enabled 短路/Boss 定格→慢速→战利品延迟链。
- [ ] Commit `feat(m3-ja): hitstop v2 director + boss death sequence`

### Task R-A: 试炼因子引擎 + 每日种子

**Files:** Create `core/meta/trial_system.gd`、`tests/unit/test_trial_system.gd`；Modify `autoload/run_state.gd`（`mods: Dictionary` + `SALT_TRIAL` 常量 + `is_trial_run`）、`autoload/game_db.gd`（trials.json 接线 + fail-closed schema）
**规格:** 试炼规格 §2/§3/§7 全条；因子抽取按 SALT_TRIAL + 结果按 id 排序；`mods` 单点注入（enemy_speed_pct 等消费在对应系统读取 mods——本卡只建通道+抽因子+校验，消费接线随 R-B/J 收口验证）；业务日 05:00 归属函数可测（注入时间参数，不直读墙钟——测试友好）。
- [ ] TDD：种子同日稳定/因子组合跨会话一致/mods 注入完整/schema 坏行 fail-closed/业务日边界（04:59→前一日，05:00→当日）。
- [ ] Commit `feat(m3-ra): trial factor engine + daily seed`

### Task S-A: 设置面板 + 音量 + 振动

**Files:** Create `ui/settings_panel.gd(+tscn)`、`tests/unit/test_settings_ui.gd`；Modify `ui/main_menu.gd`（1 挂钩）、暂停菜单挂点（执行期核对归属文件）
**规格:** 键矩阵——既有 5 键（screen_shake 0/50/100、damage_numbers、colorblind_shapes、auto_aim、touch_controls）+ 新增 `hitstop_enabled:bool=true`、`vibration:bool=true`、`volume_master/music/sfx:int 0~100`（默认 80/80/80）；settings 新键走默认值容错（`get(key, default)`），**不 bump SAVE_VERSION**（M2-T25 v2 不动）；音量走 M2-T5 `audio_mgr` 音量接口；UI 中文文案 + 键盘/触屏可操作。
- [ ] TDD：键默认值容错（旧档无新键）/三音量持久化往返/滑条边界 0~100/开关即时生效信号。
- [ ] 手动：暂停菜单与主菜单双入口、滑条听音。
- [ ] Commit `feat(m3-sa): settings panel + volume + vibration`

### Task J-B: trauma 屏震 + 连击音高

**Files:** Modify `fx/game_camera.gd`（trauma 状态机）、`core/player/weapon_rig.gd` 或命中结算点（combo 上报 ≤2 行）；Create `core/combat/combo_counter.gd`（纯逻辑：窗口/上限/重置）、`tests/unit/test_combo_counter.gd`
**规格:** Juice v2 规格 J2/J5 全参数；screen_shake 档位映射 0/0.5/1.0；combo 重置条件三件（换武器/超窗/受击）；pitch 映射 `1.0+0.02×min(combo,6)`。
- [ ] TDD：trauma 注入/衰减/平方曲线采样/档位缩放；combo 窗口边界/封顶/重置路径。
- [ ] Commit `feat(m3-jb): trauma camera shake + combo pitch`

### Task J-C: 粒子表现 v2（火花/枪口焰/碎片环 + 预算降级）

**Files:** Modify `core/art/art_lookup.gd`（fx 条带注册段）、`fx/` 粒子消费点、`tests/unit/test_art_lookup.gd`（追加 8 个条带存在性断言）
**规格:** Juice v2 规格 J3/J4；粒子池 ≤200 + 超预算降级路径（帧动画→单帧）；元素色映射火/冰/毒/电四条带；暴击金 1.3×；元素 tick 跳字小号色字。
- [ ] TDD：注册断言/降级触发（超 200 生成请求→单帧模式标记）/热路径零分配复查。
- [ ] 手动：四元素命中/暴击/击杀/枪口焰逐一看效。
- [ ] Commit `feat(m3-jc): particle v2 sprites wiring + budget degrade`

### Task R-B: 试炼 UI + 本地排行榜

**Files:** Create `ui/trial_panel.gd(+tscn)`、`core/meta/trial_records.gd`、`tests/unit/test_trial_records.gd`；Modify `ui/main_menu.gd`（试炼按钮）、`ui/hud.gd`（因子角标 ≤5 行）、结算面板（徽标 ≤5 行）
**规格:** 试炼规格 §5/§6；`user://trial_records.json` fail-soft 重建；30 条滚动 + daily_best 归并规则；因子角标悬浮/长按文案。
- [ ] TDD：记录追加/30 条截断/daily_best 取深取快/损坏文件重建/因子展示数据源。
- [ ] 手动：面板→选角→局内角标→结算徽标全链走查。
- [ ] Commit `feat(m3-rb): trial panel + local leaderboard`

### Task S-B: 按键重映射

**Files:** Create `ui/rebind_panel.gd(+tscn)`、`tests/unit/test_rebind.gd`；Modify `autoload/save_system.gd`（`settings.key_rebinds` 容错读取，不 bump 版本）、`tools/setup_input.gd` 或启动挂点（InputMap 动态重载）
**规格:** GDD §5.1「所有按键可重映射」；动作清单 = 移动四向/瞄准射击/技能/翻滚/切武器/交互；重映射流程 = 点动作→监听下一输入→写入→InputMap 重载；冲突检测（同键已有动作→提示并拒绝/交换可选，定：提示拒绝）；「恢复默认」按钮；手柄轴不开放重映射（v1 范围外，Backlog 注记）。
- [ ] TDD：写入/读取往返/冲突拒绝/恢复默认/重载后动作生效（InputMap.has_action + event 比对）。
- [ ] 手动：改键后立即生效 + 重启保留。
- [ ] Commit `feat(m3-sb): key remapping`

### Task S-C: 像素中文字体全局接线

**Files:** Create `ui/m3_theme.tres`（Theme 资源：默认字体 = `art/fonts/fusion-pixel-12px-monospaced-zh_hans.ttf`、12px 整数倍字号表、行距）、`tests/scenes/font_render_smoke.gd`；Modify `project.godot`（`gui/theme/custom`）、`ui/*.gd`（逐场景硬编码字号/主题覆盖核对，改动面以走查清单为准）
**规格:** 素材已随 P0-5 捆绑（来源/版本/SHA-256/许可见 `art/fonts/README.md`）；Godot FontFile 关闭 oversampling 与 subpixel（480×270 nearest 像素锐利）；HUD/结算/面板/图鉴/天赋等全部中文 UI 字号对齐 12px 基准（12/24 两档为主），长文本（图鉴条件/成就描述）行距走查防截断；伤害数字若受字号影响需复测可读性（对照 J4）。
- [ ] 手动走查清单：主菜单/选角/HUD/三选一/死亡与胜利结算/暂停/设置/重映射/试炼面板/图鉴/天赋/成就 toast——中文显示、无截断、无糊字；导出包（X-C）内同样本复验。
- [ ] Commit `feat(m3-sc): pixel cjk font global wiring`

### Task R-C: 试炼结算接线 + 成就激活

**Files:** Modify `core/rooms/inter_floor_flow.gd`（倍率行）、`core/meta/achievement_system.gd`（试炼者/大师 2 条接线）；Create `tests/unit/test_trial_settle.gd`
**规格:** 试炼规格 §4；`trial_completed` 每局至多一次（含放弃）；死亡保底 75%；结算面板倍率明细行。
- [ ] TDD：×1.5 向下取整/死亡 75%/放弃结算/成就 1 次与 10 次阈值/信号去重。
- [ ] Commit `feat(m3-rc): trial settlement + 2 achievements live`

### Task X-A: Android release 签名 + 产出冒烟

**Files:** Modify `export_presets.cfg`；Create `tools/export_android.cmd`、`docs/superpowers/reports/m3-android-export.md`
**规格:** release keystore 生成（keytool，路径与口令策略记录在报告；keystore 本体与口令**不入库**，.gitignore 核对）；release preset（package name/版本码/权限最小化——无网络无存储）；导出 apk+abl 产出并在真机/模拟器安装启动冒烟（主菜单→进局 30s 无错）。
- [ ] 验收：双格式产出+安装启动截图；报告记录工具链版本（JDK/SDK/Gradle）。
- [ ] Commit `feat(m3-xa): android release signing + export smoke`

### Task B-1 / B-2: 平衡周 ×2

**Files:** Create `docs/superpowers/reports/m3-balance-w1.md` / `m3-balance-w2.md`；Modify `data/balance.json`、`data/*.json`（±20% 内）
**规格:** Balance Bot（M2-T27 产物）每周期 **100 局**全 3 层回归；对照 §14.3：TTK/胜率带 20~40%/单房 20~40s/单层 8~12min/单局 25~35min；试炼因子可注入 bot 跑 10 局因子局（验因子不破坏节奏带）；B-2 额外：Juice v2 + 试炼上线后全量回归（roadmap 硬规则 5 手感抽查）；修订仅在窗口内且 ≤±20%，超限回写 GDD。
- [ ] 验收：报告产出 + 胜率带内或修订后进带 + 修订逐条记录（旧值→新值→理由）。
- [ ] Commit `feat(m3-b1): balance week 1 regression` / `feat(m3-b2): balance week 2 + final §14.3 verdict`

### Task J-D: Juice 束收口（开关矩阵 + 手感清单）

**Files:** Create `tests/scenes/juice_smoke.gd`、`docs/superpowers/reports/m3-juice-checklist.md`
**规格:** 三开关全关 + vibration 关 → 无头跑通整局（判定/信息零损失证据）；§18.5 清单 + v2 增项逐条实测记录（试玩员协同）；压测场景叠加全特效采帧耗时。
- [ ] 验收：清单全绿 + 全特效 60fps 数据。
- [ ] Commit `feat(m3-jd): juice bundle closure + checklist`

### Task X-B: 双平台 60fps 达标

**Files:** Create `docs/superpowers/reports/m3-perf.md`；复用 M2-T29 `tests/scenes/perf_probe.gd`
**规格:** 基线口径 = GDD §18.3（中端核显笔记本 / 2GB 内存安卓机）；Windows：开发机 + 核显本（如无可则集成显卡笔记本近似并标注风险）；Android：真机优先，无真机则 x86_64 模拟器低配 + Godot 远程性能监控近似（报告中显式标注「模拟器近似」）；§18.3 五指标逐项；超标走降级预案（先降粒子→再降实体→上报），逐档记录效果。
- [ ] 验收：双平台 60fps 全指标 PASS 或降级预案后 PASS；报告含逐机数据表。
- [ ] Commit `feat(m3-xb): dual-platform 60fps verification`

### Task X-C: 导出包收口

**Files:** Modify `export_presets.cfg`（版本号/图标）、`icon.svg`（正式 LOGO 替换 Godot 默认图标——遗漏补查 2026-08-30：LOGO 生成器已就绪 `tools/spritegen_m3.py`，定稿需用户过目，草案可在 M3 执行期先行生成）；Create `docs/superpowers/reports/m3-export-final.md`
**规格:** 版本 1.0.0；LOGO/图标核对（主菜单标题 LOGO + 各平台图标尺寸：Windows ico/Android adaptive icon）；存档 v2 在导出包内读写往返（首次启动建档→重启读档）；Windows exe + Android apk 双包启动冒烟（进主菜单+完整一局抽房）；导出产物 `user_export/`（gitignore）。
- [ ] 验收：双包产出 + 截图 + 存档兼容证据。
- [ ] Commit `feat(m3-xc): export package finalization`

### Task G-1: M3 门禁

**Files:** Create `docs/superpowers/reports/m3-gate-integration.md`、`m3-gate-playtest.md`、`m3-gate.md`
**规格:** 集成守卫：全量测试绿 + 3000 种子×3 生态生成校验 + §18.3 压测报告对照 + 存档 v2 往返 + 工作树干净 + P0-3/P0-4/P0-6 素材接线完整性（ArtLookup/图标消费方断言覆盖）。试玩员：①Windows 真人完整通关一局（3 层含 Boss）+ 试炼局 1 次（体验两因子）+ Juice v2 手感清单逐项 + 设置面板/重映射实操 + S-C 字体走查样本（HUD/结算/图鉴抽页）；②Android 触屏完整一局（虚拟摇杆+自动瞄准+振动）+ 试炼面板实操。编排者裁定：**无 P0/P1 缺陷 + 双平台 60fps + 设置项齐全（GDD §19 列表逐项核对表）** → GREEN 则 tag `m3`。
- [ ] 三份报告 + 裁定 + tag。
