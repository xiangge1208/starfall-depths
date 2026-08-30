# Task 17（I-1 英雄行走帧）独立评审报告

- **被审对象：** 分支 `m2-t17`（worktree `D:\workspace\thomas\.worktrees\m2-t17`），单 commit `882f30c`，基 `1d71bda`
- **评审员：** 独立评审（只读；未改代码/未 commit/未 merge，唯一写出的文件即本报告）
- **评审日期：** 2026-08-30
- **对照规格：** `docs/superpowers/plans/2026-08-30-m2-full-content.md` Task 17 卡 + Global Constraints

## 一、结论

**PASS（有条件通过）** —— 本卡规格全数达成、822/822 实测全绿、窄通道 workaround 独立验证安全。唯一 Major 为 **T6 遗留的生成器管线断链**（非本卡引入，实现者已诚实披露并在 docstring 留档），需在 T21（敌人 2 帧动画，同样要动生成器）之前修复；另修正实现者一处披露数字偏差（缺图实为 10 个武器 id，非 50 个）。

## 二、验证环境与实测

| 项 | 命令 | 结果 |
|---|---|---|
| 导入 | `godot --headless --path . --import` | 完成，无错误 |
| 全量测试 | `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` | **822/822 通过**（52 套件，0 失败/0 错误/0 flaky/0 跳过/0 孤儿，3min 6s），与自报一致；其中 `test_hero_walk_anim.gd` 新增 **12/12** |
| 幂等复跑 | `python tools/gen_placeholder_art.py --hero-sheets`（评审员独立执行一次） | 6 张帧表 + `MANIFEST.md` **sha256 复跑前后逐字节一致**，`git status` 零漂移（未触碰任何其它子树） |
| 帧表像素抽检 | PIL 逐帧字节比对 | 6 张表全部 64×64；四向行互异 12/12、walk 三帧两两互异 12/12、idle≠walk 12/12（**非复制粘贴假动画**） |

未复现项：计划卡要求的「游戏内行走动画视觉确认（截图）」在无头评审环境不可执行，以场景接线测试 + 像素差异验证替代，标注 **N/A（待门禁试玩员补）**。

## 三、规格核对（逐项）

| # | 规格项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 6 英雄 × 4 向 × (idle 1 + walk 3) = 96 帧，64×64 表、16px/帧 | **PASS** | 像素抽检：6 表 × 16 帧全异；`hero_<id>_sheet.png` 布局 = 4 行(下/上/左/右) × 4 列(idle+walk×3)，`player.gd` 帧序 `row*4+col` 与之一致 |
| 2 | 生成器重跑确定性（seed 42 逐字节一致） | **PASS** | 独立复跑 `--hero-sheets`：PNG+MANIFEST sha256 前后一致、git 零漂移。hero walk 链路**零共享 RNG**（纯像素数学），插入 `main()` 不消耗 `random.Random(42)` 序列 → 不扰动其它子树字节（声明成立） |
| 3 | player 移动方向自动切换：主轴优先 | **PASS** | `anim_dir_index`：`absf(x)>=absf(y)` 取横向；对角落横行；测试覆盖 5 组对角/近似单轴 |
| 4 | 静止保留行 | **PASS** | `_anim_dir` 仅在 `dir != Vector2.ZERO` 时更新；`anim_frame_index(ZERO, last_dir, _) = last_dir*4`；测试覆盖 |
| 5 | 8t 帧循环 | **PASS** | `1 + (f/8) % 3`，列 1..3（≈7.5fps）；测试覆盖边界 0/7/8/15/16/23/24 |
| 6 | 受击白闪不变 | **PASS** | diff 未触碰 `fx.gd`/`white_flash.gdshader`；节点名 `Sprite` 保留（`fx.gd:201` 按名寻址契约），白闪 material 挂 CanvasItem、与纹理/帧正交 |
| 7 | MANIFEST 断言测试（帧表行比对） | **PASS** | `test_manifest_lists_all_walk_sheets`：6 行逐条 `contains` + 64x64 尺寸列 + 用途文案；拼接锚点缺失时 `RuntimeError` fail-closed |
| 8 | player.tscn 帧表接线 | **PASS** | ext_resource 换 `hero_vanguard_sheet.png`，Sprite `hframes=4 vframes=4`，scale 0.75 不变（footprint 与碰撞不动）；缺表英雄回落 hframes=vframes=1 整图站立像 |
| 9 | Commit 规范（带卡号 conventional） | **PASS** | `feat(m2-t17): hero walk animation frames` |
| 10 | 游戏内视觉确认（截图） | **N/A** | 无头评审环境不可执行；建议门禁/试玩环节补 |
| 11 | `.import` 卫生 | **PASS** | +6 个 `*.png.import` 与仓库既有模式一致（main 跟踪 789 个，HEAD 795 个）；`.gitattributes` 标 `-text` 保证字节稳定，无噪音 |

## 四、质量发现

### Major（1 项，继承债务，非本卡引入）

**M-1 生成器全量入口断链（T6 遗留）——披露属实，但量化数字有偏差**
见下文第五节独立核实。影响：`main()` 全量再生不可用；`ui/weapons/` 与 `weapons/` 各有 10 个正式武器 id 缺图（合计 20 个文件），T20 图鉴 115 格武器墙与武器外观将踩到缺图。**建议在 T21 开工前修复**（T21 同样要改 `gen_placeholder_art.py` 并新增敌人帧 MANIFEST 通道，届时绕不开全量口径对齐）。

### Minor（4 项）

**m-1 `apply_player_sprite` 写站立像不清帧网格，存在 1 物理帧的错误裁切中间态**
`art_lookup.gd:223-239` 只写 `texture`，不重置 `hframes/vframes`。进房路径（`room_combat.gd:292`、`floor_scene.gd:484`）写入 16×16 站立像时，Sprite 仍处 hframes=4 → 站立像被裁为 4×4 像素一格，直到下一 `_physics_process` 懒复位（`player.gd:167-171` 贴图同一性检测）恢复帧表。窗口 ≤1/60s 不可感知，且 `test_walk_anim_redresses_after_sprite_reapply` 已覆盖恢复链路；但中间态在技术上是错误渲染。一行修复：`apply_player_sprite` 末尾补 `spr.hframes = 1; spr.vframes = 1`（与 m-4 二选一处理亦可）。

**m-2 披露数字偏差：缺盘武器图实测 10 个 id，非 50 个**
实现者自报「50 个武器图标缺盘上文件」。评审实测：`ui/weapons/` 与 `weapons/` 各 115 文件在盘，`data/weapons.json` 115 id 中缺图 **10 个**（`bingdonglei, duyaduanren, fenshenxinhaotan, shezhezhe, tantiaokuikuwu, yahuozhe, yamiehexin, yaniemhaojiao` 等；图标与手持图同缺）。成因：75 个暂定 slug 与正式 id 重叠 65 个（同名文件在盘），仅 75−65=10 个正式 id 无同名暂定 slug。偏差不影响定性结论（断链真实存在），但**影响修复工作量估计**（10 对 50 差 5 倍），后续排期应按实测口径。

**m-3 翻滚期间无专用动画姿态**
`_physics_process` 中翻滚（`_roll_left > 0`）期间 `_update_walk_anim` 仍按移动输入走 walk 帧；ranger 影袭残影帧在 MANIFEST note 中列为正式素材指引。规格未要求，占位可接受，记为后续润色项（正式素材阶段）。

**m-4 `_hero_walk_roster()` 文件句柄未显式关闭**
`tools/gen_placeholder_art.py` 中 `json.load(open(ROOT / "data" / "heroes.json", ...))` 未用 `with`。CPython 引用计数下立即回收、无实际泄漏，纯代码卫生（仓库内 `gen_placeholder_art_m2.py:140` 同款写法，属既有惯例）。

### 正面确认（质量维度）

- **热路径合规（Global Constraint 5）：** `_update_walk_anim` 每 `_physics_process` 调用——贴图同一性比较（引用比较）、`anim_frame_index` 纯整数运算、**仅帧号变化时写 `Sprite.frame`**；路径格式化字符串只在 `_load_anim_sheet`（非热路径，且经 `static _anim_sheet_cache` 一次性缓存，null 也缓存不重入）。零分配达标。
- **装配时序闭环：** `run_root.gd:96-101` 先 `add_child(player)`（`_ready` 装帧表，此时无 meta → 缺省 vanguard）再 `HeroApplier.apply` 落 meta；进房 `apply_player_sprite` 写站立像后，下一物理帧懒复位按 meta 解析出**正确英雄**的帧表。`test_walk_anim_redresses_after_sprite_reapply` 直接断言了「站立像写入 → 帧表复位」全链，实现者披露的时序处理属实且有测试锚定。
- **数据驱动 roster + 合并衔接：** `_hero_walk_roster()` = `heroes.json` 行优先 + `HERO_WALK_SPEC` 名录兜底（并集去重）。实测 `m2-t11` 分支 heroes.json 已含 mage(法师·烬)/guardian(守护者·萄)，**名称与 SPEC 逐字一致**；本 worktree heroes.json 3 行（vanguard/ranger/engineer，名字亦一致）。T11/T13 合并后重跑 `--hero-sheets`：6 张表文件名与像素不变（roster 顺序只影响生成次序不影响内容）、MANIFEST 因幂等 mark 直接跳过 → **零漂移**，无人工干预。新英雄仅需在 `HERO_WALK_SPEC` 有视觉规格即自动出表，缺规格则打印跳过 + `ArtLookup.tex` 回落站立像，无双炸路径。
- **窄通道安全性：** `gen_hero_sheets_scoped()` 不清空目录、只写 `characters/hero_*_sheet.png` + 定点拼接 MANIFEST（幂等 mark + 锚点 fail-closed）；独立复跑后 `git status` 为空，其它子树（weapons/enemies/tiles/...）字节未动。**评估为安全的临时 workaround。**
- **测试质量：** 12 例全部为行为断言（文件存在+尺寸、MANIFEST 逐行 contains、纯函数边界数值、场景树内 `spr.frame` 实值、纹理同一性、回落路径），无恒真断言；`FULL_ROSTER` 硬编码六英雄与 `heroes.size() >= 3` 弹性断言并存，合并 T11/T13 后不需改测试。
- **文档同步：** 生成器 docstring 诚实记录断链与窄通道口径；MANIFEST「待补」行更新为已交付口径（T21 敌人动画留了指引）。

## 五、管线断链独立核实（不执行全量入口，纯读代码 + 盘上盘点）

实现者披露逐条核实：

1. **断言必然失败：属实。** `tools/gen_placeholder_art_m2.py:138-147` `gen_weapons_m2()`：rows = `data/weapons.json` 全部行 + `NEW_WEAPONS` 75 条暂定 slug，`assert len(rows) == 115`。本 worktree 实测 weapons.json = **115 行**（T6 已合并）→ rows = 115 + 75 = **190** ≠ 115 → `AssertionError`。该断言隐含的前提是「weapons.json 保持 M1 的 40 行」，T6 落地 115 行后前提失效，且 75 个暂定 slug 中 65 个与正式 id 同名（重叠不去重）、10 个正式 id 在暂定表无对应行。
2. **全量重跑清库后失败：属实。** `gen_placeholder_art.py:1810-1813` `main()` 开头删除 `art/generated/` 下所有文件（仅保留 `.gitkeep`/`MANIFEST.md`）；`:1851-1859` 串联 M2 批次为 `try/except Exception` 只打印 traceback 不中断。后果：清库后 `gen_weapons_m2` 首位炸出 → `generate()` 内其后全部 M2 段（enemies/heroes/buffs/tiles/ui）**一个都不执行** → 盘上 M2 子树被清空且不重建，`write_manifest()` 仍会以残缺 SPEC 重写 MANIFEST。**当前全量入口 = 破坏性操作，禁用正确。**
3. **武器图标缺口：披露数字不准。** 实测 `ui/weapons/` 115 文件在盘、`weapons/` 115 文件在盘；缺图 = 10 个正式 id × 2 类产物 = 20 个文件（详见 m-2）。盘上现存 M2 批次上次成功运行（weapons.json 尚为 40 行时）的产物：40（M1 正式）+ 75（暂定 slug，其中 65 恰与正式 id 同名）。
4. **workaround 评估：安全。** 见第四节「窄通道安全性」。`--hero-sheets` 与断链路径零交集（不进 `main()`、不 import m2 模块、不清库），且幂等可无限重跑。

## 六、测试实测摘要

- 套件：52/52 执行；用例 **822/822 通过**（基线 810 + 本卡 12）。
- 新增 `tests/unit/test_hero_walk_anim.gd` 12 例全过，断言真实性核验通过（详见第四节）。
- 导入后运行（符合 Global Constraint 6 顺序）；`reports/report_5/` 产物在 `/reports/`（已 gitignore），无提交噪音。

## 七、修复建议（按优先级）

1. **（T21 前必须）修复 `gen_weapons_m2` 口径**：rows 组装改为「以 `data/weapons.json` 115 行为单一事实源；`NEW_WEAPONS` 仅对**无正式 id 对应**的暂定 slug 出图并告警」，删除 `len == 115` 的脆断言改为「正式 id 全覆盖 + 暂定 slug 允许但逐条 push_warning」。同时为 10 个缺图正式 id 补暂定视觉（附录 A 转录时可顺手对齐）。修好后全量 `main()` 恢复可用，窄通道可退役。
2. **（一行，可并入 T21 顺车）** `apply_player_sprite` 末尾复位 `hframes/vframes = 1`，消除进房 1 帧裁切中间态（m-1）。
3. **（文档）** 在管线台账（`m2-progress.md`）修正缺图数量为实测 10 id / 20 文件（m-2），避免误导后续排期。
4. **（低优）** `_hero_walk_roster()` 改 `with open(...)`（m-4）；翻滚姿态与影袭残影帧留正式素材阶段（m-3）。
5. **（门禁）** 游戏内行走动画截图确认补进 T34 试玩清单（规格第 10 项 N/A 收口）。

## 八、裁定

| 维度 | 评定 |
|---|---|
| 规格达成 | 9/10 PASS + 1 N/A（截图待试玩） |
| 测试 | 822/822 实测复现；新增 12 例断言真实 |
| 热路径/架构合规 | 达标（零分配、时序闭环、数据驱动） |
| 遗留债务 | 管线断链属实（T6 遗留、已披露、窄通道安全），缺图量化修正为 10 id |
| **总结论** | **PASS —— 建议合并**；M-1 断链修复挂到 T21 开工前，m-1 一行修复可顺车 |
