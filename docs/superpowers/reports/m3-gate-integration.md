# M3 Gate — Integration Guard Report（G-1 自动化部分）

- 日期：2026-09-02（门禁准备实现者执行 G-1 可自动化项；**裁定与 tag 归编排者**，本报告不含裁定）
- Repo：worktree `D:\workspace\thomas\.worktrees\m3-gate`，branch `m3-gate`，基线 `77f5567`（= main @ 77f5567，含 M3 执行期 16 卡 + fix1/fix2 全部修复）
- Godot：`4.7.2.stable.official.ed1daf0bf`；gdUnit 6.2.1；Windows 10.0.26200，i5-14400F / RTX 3050 / 32GB
- 范围声明：G-1 全卡 = 集成守卫（本文）+ 试玩员走查（按现行裁定转为**用户自测清单** `m3-gate-user-checklist.md`，由真人执行回报）+ 设置项齐全核对（本文 §6）+ 裁定 tag（不在本文）
- 标注约定：各结论标「**本次复跑**」（本机本会话真实运行）或「**引用**」（既有报告数据，未重跑）

## Check 1 — 全量测试：PASS（本次复跑 ×2）

命令：`cmd //c "tools\\run_tests.cmd"`（内置 import 前置；两次独立进程）。

| 轮 | 结果 |
|---|---|
| 第 1 轮（基线，改动前） | **1634 test cases \| 0 errors \| 0 failures \| 0 flaky \| 0 skipped \| 0 orphans**，89/89 套件，(1634/1634)，exit 0，1min 24s |
| 第 2 轮（终态，含 G-1 唯一新增断言后） | **1635 test cases \| 0 errors \| 0 failures \| 0 flaky \| 0 skipped \| 0 orphans**，89/89 套件，(1635/1635)，exit 0 |

测试账目：X-C 收口时 1622 → fix1/fix2 合入后 **1634**（+12，fix2 贡献 test_safe_placement 8 + test_floor_scene 修复轮 4）→ 本门禁 +1（Check 5 的 P0-6 图标封口断言）= **1635**。账目各环均有在档全绿记录支撑。

## Check 2 — 地牢生成校验（3000 种子 × 3 生态）：PASS（本次复跑）

命令（M2 门禁同口径，`tools/validate_dungeon.gd` 参数化档）：

```
godot --headless --path . --script res://tools/validate_dungeon.gd -- --seeds=3000 --floors=1,2,3
```

结果：**9000/9000 PASS (seeds=3000 floors=[1, 2, 3])**，exit 0，零失败种子、零错误类别。对照 M2 门禁同口径 9000/9000（m2-gate-integration.md Check 3）一致；GDD §M3 验收继承的「1000 种子生成校验（3 生态）」维持超额满足。

## Check 3 — §18.3 压测对照（X-B 五指标抽验）：PASS，与 X-B 报告一致（本次复跑＝抽验口径）

按任务卡不重跑压测全量：X-B（`m3-perf.md`）已交付 Windows 五指标全 PASS 数据；本门禁做抽验——`perf_probe` 复跑一次（默认 40 敌满负荷，`-- --uncapped` 诊断档；本机沿承 J-D/X-B 记录的 `max_fps=60` 节流会话异常，uncapped 为既定诊断路径，见 m3-juice-checklist §4.1 / m3-perf §2.2）。

命令：`godot --headless --path . res://tests/scenes/perf_probe.tscn -- --uncapped` → **PERF VERDICT: PASS**，exit 0，0 SCRIPT ERROR。证据 JSON 转存 `m3-gate-evidence-perf-uncapped.json`（本目录，meta.paced=false / enemy_target=40 / bullet_target=500）。

| 指标（预算线） | F1 a1_03 | F2 a2_01 | F3 a3_08 | X-B 对照（引用） | 判定 |
|---|---|---|---|---|---|
| 逻辑帧 avg（≤6ms） | 0.034ms（max 0.076） | 0.032ms（max 0.055） | 0.038ms（max 0.075） | 头less 全负荷 0.02~0.09ms（m3-perf 表 C trace3）；J-D 0.014~0.015ms | **一致**（同量级，余量 ≥150×） |
| 渲染 CPU avg（≤10ms） | 0.009ms | 0.009ms | 0.008ms | 头less 0.004~0.006 / 窗口化 0.020~0.024 | **一致** |
| draw call（≤150） | 0（头less Dummy 恒 0，不可测） | 0 | 0 | 窗口化全负荷 avg 101~102（m3-perf 表 B，引用） | N/A（口径受限于头less；以 X-B 窗口化数据为准） |
| 活动实体（≤300） | 63 | 59 | 66 | 全负荷 61~69（m3-perf 表 B/C） | **一致** |
| 同屏弹幕（≤500） | 峰 500 顶格 | 峰 500 顶格 | 峰 500 顶格 | 三层顶格 | **一致** |
| 粒子池观测 | 峰 23 / 降级 0 | 峰 23 / 降级 0 | 峰 29 / 降级 0 | 活跃峰 ≤19~29，预算 200 未触顶 | **一致** |
| 60fps 合成线 | N/A（uncapped 档不判定） | N/A | N/A | 节流窗 TIME_FPS=60.0、steps=1.00 ×3（m3-perf §3.2 表 A） | 节流窗实证以 X-B 为准（引用） |

**结论：抽验各项量级与判定同 X-B 报告一致，无偏差。** 下列项维持 X-B 移交口径，不在本机重复：节流窗 60fps 正式复测（需静默会话/目标机，X-B §9.2）、Android 真机五指标（X-B §9.1，无真机）、核显本真测（X-B §9.3）。

## Check 4 — 存档 v2 往返：PASS，对照 X-C 报告一致（本次复跑＝定向复跑口径）

X-C 专项证据为一次性脚本（`user_export/xc_save_v2_verify.gd`，gitignore 区，checks=135 fails=0——**引用** `m3-export-final.md` §3.2；该脚本不在本 worktree，无法原样复跑）。本门禁等价口径：定向复跑 X-C 点名的存档相关五个套件（save v2 全字段往返 / v1 迁移 / 幂等 / 设置持久化 / 改键持久化 / 图鉴进度跨档）：

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/test_save.gd -a res://tests/unit/test_settings_ui.gd \
  -a res://tests/unit/test_rebind.gd -a res://tests/unit/test_codex_system.gd \
  -a res://tests/unit/test_trial_records.gd --ignoreHeadlessMode
```

结果：**94 test cases \| 0 errors \| 0 failures，5/5 套件，(94/94)，exit 0**。X-C §3.1 点名用例逐条在本次复跑中 PASSED：`test_roundtrip_persists_all_fields`、`test_v1_save_migrates_to_v2_preserving_all_fields`、`test_migration_v2_idempotent_double_load`、`test_unlock_tasks_progress_roundtrip`、`test_volume_int_keys_roundtrip_through_disk`、`test_persistence_roundtrip_through_disk`（rebind）等。另附注：本门禁亦尝试以 `-s` 单脚本复刻 X-C PART1 全字段写读深比较，确认 `-s` 模式下 `save_system.gd` 编译期即不可解析具名 autoload（`AchievementSystem`，`unlock_hero` 引用），比 X-C 脚本注脚披露的限制更严——故放弃该路径改用上述 gdUnit 定向复跑（测试进程内 autoload 在树，口径等价且更接近生产）。「首次启动建档→重启读档」真人闭环走查归用户自测清单 ④。

## Check 5 — 素材接线完整性（P0-3 / P0-4 / P0-6）：PASS（核对＋哈希本次复跑）

| 卡 | 素材 | 注册段/消费方 | 自动化断言（测试编号，本次复跑全绿） | 盘上一致性 |
|---|---|---|---|---|
| P0-3 | `data/trials.json` 试炼数据表 | `core/meta/trial_system.gd`（mods 注入）/ `GameDB.trials` | `tests/unit/test_trials_data.gd` 8 用例（可解析/8 因子白名单/mods 逐键精确比对/数值域/布尔类型）＋ `test_trial_mods.gd`、`test_trial_system.gd`、`test_trial_settle.gd`、`test_trial_records.gd` | — |
| P0-4 | `art/generated/fx/*` Juice v2 条带 ×10 | `core/art/art_lookup.gd` `FX_STRIPS`（92-114 行注册段）＋ `fx/particles_pool.gd` 池化消费 | `tests/unit/test_art_lookup.gd`：`test_fx_strip_paths_registered`（8 条带路径精确断言）、`test_fx_strip_frames_match_manifest`（帧数）、`test_all_fx_strip_files_exist_on_disk`（盘上存在）、`test_fx_strip_textures_have_manifest_geometry`（实载几何=manifest） | `MANIFEST_M3.md` QA 总表 10 件 + trials 节 8 件，**sha256-16 逐件与盘上字节比对 18/18 一致（本次复跑，Python 独立复算）**；生成器自带 LEGACY_SHA16 旧产物基线自证机制（tools/spritegen_m3.py:698）未触发偏离 |
| P0-6 | `art/generated/trials/factor_*.png` ×8 | `ui/trial_panel.gd:22` `FACTOR_ICON_FMT`（HUD 因子角标 + 面板因子卡消费） | `test_trial_records.gd`：`test_factor_display_triple_from_gamedb`（路径 + `ResourceLoader.exists` 在盘）、`test_factor_displays_preserve_order_and_cover_today_pair`（当日两枚路径）；**G-1 新增封口**：`test_trials_data.gd > test_all_factor_icons_exist_on_disk`（8 枚白名单逐一在盘——既有断言仅覆盖当日两枚 + enemy_haste 散点，此处补全量，Check 1 第 2 轮 1635 内含，单独复跑 8/8 PASSED） | 8 件哈希入上行走查（18/18 内含） |

缺断言项仅 P0-6 一处（上表已补），其余均有既有测试覆盖；未发现接线缺陷。

## Check 6 — 设置项齐全核对（GDD §19/§5.3 逐项）：齐全（10 面板键 + 9 动作重映射，覆盖 GDD 全部条目）

来源条目：GDD §19「设置含屏震、伤害数字、色弱形状编码、自动瞄准、按键重映射」＋ §5.3「屏震强度 0/50/100%、伤害数字开关、hitstop 开关（无障碍）」＋ §4 触屏/自动瞄准默认口径＋ Juice v2 规格（J6 振动键）＋ m3-sa 十键面板卡。逐项核对表：

| # | GDD 条目（出处） | 面板控件（ui/settings_panel.gd / rebind_panel.gd） | 存档键（autoload/save_system.gd） | 消费端（文件:行） | 持久化/UI→存档→消费断言 | 状态 |
|---|---|---|---|---|---|---|
| 1 | 屏震强度（§19/§5.3） | 屏震滑条（0..1 步进 0.1，默认 0.5） | `settings.screen_shake` (float) | `autoload/fx.gd:164` → `fx/game_camera.gd:31-48`（trauma² 幅值） | test_settings_ui.gd 196/234；juice_smoke §2（0 档钉死/默认档回落） | ✅（注 a） |
| 2 | 伤害数字开关（§19/§5.3） | 「伤害数字」开关 | `settings.damage_numbers` (bool) | `autoload/fx.gd:524` | test_settings_ui.gd；juice_smoke §5（开→暴击 42 生成/关→抑制） | ✅ |
| 3 | 色弱形状编码（§19） | 「色弱形状」开关 | `settings.colorblind_shapes` (bool) | `autoload/fx.gd:568`（火=▲ 形状编码） | test_settings_ui.gd；juice_smoke §5 | ✅ |
| 4 | 自动瞄准（§19；触屏默认开 §4） | 「自动瞄准」开关（默认开） | `settings.auto_aim` (bool true) | `core/rooms/player_driver.gd:104` | test_settings_ui.gd；test_auto_aim.gd | ✅ |
| 5 | 按键重映射（§19/§4「所有按键可重映射」） | 主菜单「按 键」→ `ui/rebind_panel.gd`（9 动作：移动四向/射击/技能/翻滚/切武器/交互；冲突拒绝+恢复默认） | 顶层键 `key_rebinds`（v2 additive） | `SaveSystem._apply_saved_rebinds`（启动恢复，save_system.gd:53/399）＋ InputMap 运行时覆写 | test_rebind.gd 11 用例（序列化/落盘往返/冲突/恢复默认/启动应用） | ✅（注 b） |
| 6 | hitstop 开关·无障碍（§5.3） | 「打击停顿」开关 | `settings.hitstop_enabled` (bool) | `autoload/fx.gd:110`、`fx/hitstop_director.gd:107`、`core/meta/death_recorder.gd:191` | test_settings_ui.gd；juice_smoke §4（UI→落盘→消费三段贯通） | ✅ |
| 7 | 振动（Juice v2 J6，Android 生效默认开） | 「振动」开关 | `settings.vibration` (bool true) | `autoload/fx.gd:256`（开关+平台双门控；受击 30ms `:291` / Boss 死亡 80ms `:361`） | test_settings_ui.gd；juice_smoke §7 | ✅ |
| 8 | 三路音量（m3-sa 卡；存档含设置 §12） | 主音量/音乐/音效滑条（int 0..100，默认 80） | `settings.volume_master` / `volume_music` / `volume_sfx` | AudioServer 总线 0（面板直写）/ `AudioMgr.set_music_volume` / `set_sfx_volume`；启动 `main_menu.gd:40` apply_audio_settings | test_settings_ui.gd（int 键落盘往返/越界钳制/端点推线）；test_audio_mgr.gd | ✅（注 c） |
| 9 | 触屏控件（§4 虚拟摇杆/开火键显隐） | 「触屏控件」开关 | `settings.touch_controls` (bool) | `core/rooms/player_driver.gd:81`、`ui/touch_controls.gd:27`、`ui/virtual_joystick.gd:45` | test_settings_ui.gd；test_touch_* 相关套件 | ✅ |
| 10 | 暂停菜单「继续/设置/重开/回主菜单」（§19） | —（全库无暂停菜单 UI） | — | — | — | ⚠️ 偏差（预存裁定，注 d） |

注：
- a. GDD §5.3 写「0/50/100% 三档」，实现为 0..1 连续滑条（含 0/0.5/1.0）——连续档为三档的严格超集，且 J2 晕动防线默认档 50% 对齐（save_system.gd:23 注）；不判缺陷，观感走用户自测 ④。
- b. 重映射开放范围为 9 个键盘动作（rebind_panel.gd 头注：手柄轴/触屏虚拟动作范围外，有裁定记录）；「所有按键」按该口径收窄。
- c. AudioMgr setter 随写持久化自有 float 键（audio_mgr.gd:105 等），与面板 int 键双轨并存——settings_panel.gd 头注已声明属实现细节（UI int 键为权威，启动以 int 键推端点），不判双源冲突。
- d. GDD §19 暂停菜单全库缺席为预存事实（hud.gd:385 注「暂停菜单全库缺席——编排者裁定入口在 HUD」；S-C 走查 #17 同口径记录）——设置入口现仅主菜单（局内不可调设置）。**移交编排者**：是否接受该偏差随 m3 tag 放行，或另立小卡。
- 面板键集单一事实源对齐：`SaveSystem.DEFAULT_SETTINGS` 10 键 ↔ `settings_panel.gd` KEY_* 10 常量 ↔ 面板控件 10 项，一一对应无缺键（本次逐键 grep 核对）。

## Check 7 — 工作树干净：PASS

门禁起点 `git status` 干净（基线 77f5567，无未跟踪/未提交生产物）。本门禁全部产出 = 本报告 + 用户自测清单 + perf 证据 JSON + tests/unit/test_trials_data.gd 一枚断言（commit 见文末），无 core/、ui/、autoload/、data/、export_presets.cfg 触碰。

## Check 8 — M3 各卡移交项汇总（交叉引用）

| 卡 | 报告 | 一句话状态 | 移交 G-1 项与本门禁处置 |
|---|---|---|---|
| X-A Android 导出 | m3-android-export.md | PASS（apk+aab 双产物、双签核验） | 真机触屏一局 → 用户自测 ⑥ |
| S-C 字体接线 | m3-font-walkthrough.md | 全局 fusion-pixel 接线完成，走查清单待真人 | 样本点转录 → 用户自测 ⑤ |
| B-1/B-2 平衡周 | m3-balance-w1/w2.md | §14.3 终判 CONDITIONAL 三项（A1 TTK 深度出带 2.25×、三带 bot 不可评、停滞 11%） | 裁定归编排者（随 tag）；真人体验 → 自测 ①② |
| J-D Juice 收口 | m3-juice-checklist.md | 70/70 机检 + 6 组合矩阵零损失；主观项 10 条待真人 | 转录 → 用户自测 ③ |
| X-B 双平台 60fps | m3-perf.md | Windows 五指标 PASS（开发机口径）；Android 真机缺 | 抽验一致（Check 3）；真机/核显本/静默会话终验维持移交（自测 ⑥ + 编排者） |
| X-C 导出收口 | m3-export-final.md | 双包冒烟 PASS；versionCode=100/图标/存档 v2 | 存档对照一致（Check 4）；Windows 真人交互 → 自测 ①④⑤；LOGO/版本读点等产品裁定 → 编排者 |
| fix1 停滞修复 | m3-fix1.md | 刷怪不变量 P0 修复 + 试炼 mods 消费端接线 | 随全量绿覆盖（Check 1） |
| fix2 停滞残差 | m3-fix2.md | 产品侧 7 例修复钉死；bot 侧 4+2 例量化移交 | 残差为 bot 能力缺陷（真人基础操作面可清，fix2 §6）→ 不构成门禁阻塞项；bot 能力卡另立归编排者 |

## 门禁判定（自动化守卫侧）

**Check 1~5、7 全 PASS；Check 3/4 对照 X-B/X-C 一致无偏差；Check 6 设置项齐全（GDD 条目全覆盖，1 项预存偏差注 d 移交裁定）。** 未发现 P0/P1 自动化可测缺陷。裁定（含 tag `m3` 与注 d 偏差处置）归编排者；真人主观项见 `m3-gate-user-checklist.md`。
