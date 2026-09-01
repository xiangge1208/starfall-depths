# M3-S-C 像素中文字体全局接线 — 走查清单与改动台账（G-1 输入）

任务卡 S-C 交付：`ui/m3_theme.tres` 全局主题 + `project.godot gui/theme/custom` 接线 +
全 UI 字号归一 12px 基准 + 自动化冒烟。本文档为 G-1 真人/真机走查的输入清单与改动台账。

- 分支：`m3-sc`（基于 main @ bb7eb39）
- 自动化冒烟：`godot --headless --path . res://tests/scenes/font_render_smoke.tscn`
- 全量单测：`tools/run_tests.cmd`（gdUnit4 `-a res://tests/unit`）——**1541/1541 全绿（83/83 套件，0 错误 0 失败）**，既有用例零适配（`tests/unit` 无字号/主题断言，已 grep 核实）。

---

## 1. 主题接线

| 项 | 内容 |
|---|---|
| `ui/m3_theme.tres`（新建） | Theme：`default_font` = fusion-pixel-12px-monospaced-zh_hans.ttf；`default_font_size = 12`。类型项零定义（默认值即可满足，不过度定义） |
| `project.godot` | 仅 `[gui]` 节新增 `theme/custom="res://ui/m3_theme.tres"` 一键（原无 [gui] 节，插于 [editor_plugins] 与 [input] 之间；其余键零触碰） |
| 生效路径 | gui/theme/custom → 所有未显式覆盖的 Control 继承 m3_theme（此前无主题时 Control 落 Godot 内建默认字体 16px——接线本身即全局字体切换） |

### 字体导入参数（`art/fonts/fusion-pixel-12px-monospaced-zh_hans.ttf.import`，前后对比）

| 参数 | 前 | 后 | 理由（README §使用约定：关闭 oversampling、subpixel 关、防灰阶 AA 糊字） |
|---|---|---|---|
| `antialiasing` | 1（灰阶 AA） | **0（None）** | 灰阶边缘像素会糊掉 12px 像素栅格 |
| `subpixel_positioning` | 4 | **0（Disabled）** | 亚像素定位破坏整像素对位 |
| `oversampling` | 0.0（Auto，随视口缩放重栅） | **1.0（钉死）** | 480×270 nearest + canvas_items 整数拉伸下，12px 栅格按 1.0 栅格化、由画布最近邻放大，任意窗口倍率保持锐利 |
| 其余（hinting/mipmaps/msdf/fallback/compress…） | 不变 | 不变 | 最小改动；msdf 本就 false |

引擎实测度量（headless FontFile）：`get_height(12)==12.0`、CJK 步进 12px/字、ASCII 6px/字（2:1 等宽）、ascent 10 / descent 2——完美对齐像素栅格，无额外行距需求（Label 默认 line_spacing 未动）。

---

## 2. 字号归一台账（29 处 grep 命中逐处判定 + tscn 覆盖归一）

判定规则：中文正文/标题 → 12 或 24（12px 整数倍两档；24 仅主菜单大标题与死亡/胜利结算大标题）；纯西文调试层 → 保留并裁定；core/ 与 autoload/fx.gd 超本卡授权 → 零改动记录。

### 2.1 ui/*.gd（grep 命中 19 行：5 处参数化 helper 未改值，13 处直接改，1 处保留；helper 调用点同步归一）

| 文件:行 | 旧 → 新 | 判定 |
|---|---|---|
| buff_pick.gd:62/63/64（经 :102 helper） | 10→12、8→12、8→12 | 三选一卡：标题/稀有度/描述（中文） |
| calamity.gd:99 | 13→12 | 面板标题（中文） |
| calamity.gd:123/124（经 :153 helper） | 10→12、8→12 | 灾厄卡标题/描述 |
| codex.gd:63/68（经 :156 helper） | 7→12、6→12 | 图鉴格名称/解锁条件（长中文，见 §3 布局兜底） |
| hero_select.gd:96/99/102/108（经 :138 helper） | 8→12 ×4；:99 加 autowrap | 选角卡：面板/被动/技能/初始武器（被动长中文需断行防破卡）；:95 名称 12 保持 |
| talents.gd:56（经 :175 helper） | 10→12 | 系列头标 |
| talents.gd:63 | 8→12 | 节点按钮（中文名+价格） |
| main_menu.gd:58 | 11→12 | 试炼入口按钮 |
| toast.gd:70 | 15→12（outline 4→2） | 成就 toast（中文）；12px 像素字配 2px 描边对齐 fx.gd 惯例 |
| forge.gd:294/298 | 10→12 ×2 | 熔铸材料名/稀有度 |
| hud.gd:271 | 8→12 | 武器槽名（中文） |
| hud.gd:289 | 8→12 | 右上层数/种子/金币（中文+数字） |
| hud.gd:336 | 8→12 | Buff 缩写 chip（中文，chip 容器随调见 §3） |
| trial_panel.gd:104/107/136 | 9→12、8→12、8→12 | 因子名/因子文案/历史行 |
| interact_prompt.gd:10 | 8→12 | 交互浮标 action_label（中文） |
| **debug_hud.gd:17** | **8 保留** | 走查裁定：纯 ASCII 调试覆盖层（非玩家正式 UI），8px fusion 栅格不保锐但仅开发期用；G-1 如裁定提级 → 12 |

小计：ui/ 域数值改动 26 处（13 直接 + 13 调用点）+ 1 处保留裁定；5 处 helper 声明行零改动（参数化）。

### 2.2 ui/*.tscn（theme_override_font_sizes 归一）

| 文件 | 改动 | 保留 |
|---|---|---|
| main_menu.tscn | Title 20→24；Subtitle 8→12；6 按钮 11→12（8 处） | **退役旧内联设置面板 6 处（10×1、8×5）不动**——tscn 中 `visible=false`、运行时强制隐藏（m3-sa 退役语义），永不渲染，走查 N/A |
| hero_select.tscn | Title 13→12 | — |
| codex.tscn | Summary 8→12；CloseBtn 11→12；Grid `columns 10→7` | — |
| talents.tscn | Title 13→12；Gems 10→12；Detail 8→12；BackBtn 10→12；Branches 下沿 100→76、Detail 上沿 −44→−52（容器兜底见 §3） | — |
| trial_panel.tscn | Title 11→12；Date/Best/History 8→12；StartBtn/BackBtn 11→12 | — |
| settings_panel.tscn | Title/BackBtn 11→12；10 标签 + 6 开关 8→12（18 处） | — |
| death_summary.tscn | Title/Banner 16→24；Cause/Stats/Gems/Replay 10→12；Hint/ReplayHint 8→12（8 处） | — |
| victory_summary.tscn | Title 16→24；Hero/Stats/Gems/Preview 10→12；Hint 8→12（6 处） | — |
| forge.tscn | Title 14→12；Coins/Preview/Cost/FuseBtn/CloseBtn 10→12（6 处） | — |

### 2.3 core/（grep 命中 8 行——**超本卡修改授权，零改动**，上报 G-1/后续卡）

| 文件:行 | 现值 | 建议 |
|---|---|---|
| core/interact/events.gd:272 | 13（事件标题） | → 12 |
| core/interact/events.gd:275 | 10（事件描述） | → 12 |
| core/interact/shop.gd:570 | 10（货架标签） | → 12 |
| core/interact/drink_machine.gd:235（helper；调用点常量 :20/:21 `HEADER_FONT=10`/`CARD_FONT=8`） | 10/8 | → 12（饮料机卡中文） |
| core/rooms/run_root.gd:294 | 16（A2 入口横幅「已进入第 2 层」） | → 24（大标题档）或 12 |
| core/rooms/run_root.gd:299 | 10（横幅提示行） | → 12 |
| core/rooms/training_room.gd:116/260 | 8 ×2（训练房武器名/地面提示，中文） | → 12 |
| **注**：这些控件接线主题后字体已是 fusion-pixel（无显式 font 覆盖者），仅字号数值未归一——8/10/13/16px 均非 12 整数倍，fusion 栅格非整数缩，锐利度受损，G-1 优先复核 | |

### 2.4 autoload/fx.gd（**零改动区**，J-C 改写进行中；J-D 走查裁定项）

- fx.gd:307 伤害数字 8px；fx.gd:334 元素形状 10px。
- 现值与 12 基准的取舍建议（对照 J4）：伤害数字为纯西文数字 + 2px 描边，8px 非整数缩栅的可读性风险低于中文，且战斗层字号翻倍（8→12）会加重读屏干扰——建议 J-D 真机对照 8/10/12 三档裁定；元素形状为符号（△◇○⚡），同理。主题接线后两者字体已切 fusion-pixel，观感复测必做。

---

## 3. 布局回退防护记录（headless 实测）

冒烟断言「可见控件全局矩形 ⊆ 480×270」（ScrollContainer 裁剪内容豁免）：

1. **settings_panel**（R-B 返工先例场景）：归一后实测面板 ≈212×245 ≤ 270，收下，未复发。
2. **talents**：Detail（8→12，长详情 3~4 行）矩形 40px 不足 → 上沿 −44→−52（48px 容 4 行）；同时 Branches 下沿 100→76 上收列面板，消除与 Detail 的视觉重叠。列内容 12px 实测 ~170px < 调整后 190px 列高，8 节点 ×3 系全收下。
3. **hud**：Buff chip 18×12 → 26×14（12px 2 字缩写 24px 宽 + 内距），buff 行 y=30 起 14px 高，与左上心/条区（y≤21）无碰撞。
4. **codex**：格 40×62/10 列 → 60×104/7 列（名称 4 字 48px 整行、条件长文 5 行×12px）；网格宽 444 = Scroll 宽（断言无横向滚动），17 行纵向滚动承载；名称行加 `AUTOWRAP_ARBITRARY` 兜 5 字名「左轮·正午」防破格。115 格全部收下。
5. **calamity（冒烟发现的预存超界，已修）**：4 卡 ×136 + 间距 24 + 边距 24 = 592px 恒超 480（固定卡宽、与字号无关，m2-t26 起即超界）→ 卡宽 136→108（4×108+24+24=480 恰好收下），12px 描述 3 行内可容。
6. **hero_select（预存超界，走查裁定保留 + 上报）**：场景按 2 英雄设计（卡 206px 固定宽），M2 数据扩到 6 英雄后卡片行 6×206+5×16=1316px 恒超界（与字号无关、字号改动前后等宽）。结构性重排（分页/滚动/缩卡）超本卡授权 → 冒烟豁免该行视口断言，改为「卡内文案不破卡」专项断言（PASS：12px 长被动/技能断行后全部收在卡内）；布局重排上报后续卡（见 §5）。

---

## 4. G-1 真人走查清单（逐项；自动化已覆盖实例化/字体落实/视口收下，以下为真机观感项）

运行 `godot --path .`（1440×810 窗口 / 3× 整数缩放）与全屏两态核对：

| # | 走查项 | 入口 | 检查点 | 状态 |
|---|---|---|---|---|
| 1 | 主菜单 | 启动 | 「星陨地牢」24px 锐利；6 按钮中文 12px 无糊字；副标题/试炼按钮对齐 | 待 G-1 |
| 2 | 选角 | 开始 | 6 卡行**横向超界（预存，§3.6）**——卡内文案 12px 断行可读、无破卡即过；行级布局另卡修 | 待 G-1（含上报项复核） |
| 3 | 战斗 HUD | 进本 | 武器槽名/层数/种子/金币/Buff 缩写 12px；Buff chip 无溢出；低血红晕正常 | 待 G-1 |
| 4 | 交互浮标 | 靠近设施 | 「打开宝箱/进入下一层…」12px 居中无糊 | 待 G-1 |
| 5 | 三选一 | 清层 | 卡标题/描述 12px；长描述 3 行内不截断 | 待 G-1 |
| 6 | 灾厄 4 选 1 | 挑战房 | 面板恰收 480 宽；标题/卡文案 12px 无糊 | 待 G-1 |
| 7 | 死亡结算 | 死亡 | 标题 24px（试炼局冠「每日试炼 · 」同宽复核）；统计/致死原因 12px 两行不截断；回放横幅 24px | 待 G-1 |
| 8 | 胜利结算 | 通关 | 同上口径（Stats 3 行） | 待 G-1 |
| 9 | 设置面板（S-A） | 主菜单→设置 | 10 行 12px 收 270 内；开关「开/关」清晰；滑条标签不截断 | 待 G-1 |
| 10 | 试炼面板 | 主菜单→试炼 | 因子卡名/文案、双列历史 12px；开面板后 270 收下；长角色名行宽复核 | 待 G-1 |
| 11 | 图鉴 | 主菜单→图鉴 | 7 列格 12px：名称整行、解锁条件 5 行内（clip 内截断观感裁定）；滚动顺畅 | 待 G-1 |
| 12 | 天赋 | 主菜单→天赋 | 节点按钮 12px「T8 名 ◆价」不溢出；Detail 4 行不截断；三列不叠 Detail | 待 G-1 |
| 13 | 成就 toast | 触发解锁 | 右下 12px + 2px 描边；中文名不超 340px 行宽 | 待 G-1 |
| 14 | 熔铸台 | 设施交互 | 材料/稀有度/预览/费用 12px | 待 G-1 |
| 15 | 训练房/商店/事件/饮料机（core 域） | 对应场景 | 字号未归一（§2.3）：复核 8/10/13/16px fusion 观感，裁定是否追一卡归一 | 待 G-1（上报） |
| 16 | 伤害数字/元素形状 | 战斗 | fx.gd 零改动区：8/10px fusion 现值对照 12 取舍，J-D 裁定（§2.4） | 归 J-D |
| 17 | **暂停菜单** | — | **SHELVED**：全库无暂停菜单 UI（grep 核实，无对应场景/面板） | SHELVED |
| 18 | **重映射 UI** | — | **SHELVED**：全库无按键重映射界面（仅 save_system/gamepad_aim 内部键名） | SHELVED |

---

## 5. 上报事项汇总

1. **hero_select 6 卡行 1316px 超界（预存，非字号）**：需结构性重排（分页/横向滚动/缩卡），建议独立小卡；G-1 先按「卡内可读」口径走查。
2. **core/ 8 处字号未归一**（§2.3）：超 S-C 授权（修改权仅 ui/*）；主题已使其中无覆盖控件切到 fusion-pixel，非整数倍字号观感需 G-1 复核，建议追一张 core UI 字号归一小卡。
3. **fx.gd 伤害数字 8/元素形状 10**（§2.4）：J-C 改写进行中，本卡零改动；J-D 走查对照 8/10/12 三档。
4. **暂停菜单 / 重映射 UI 不存在**：G-1 走查清单两项 SHELVED（若 M4 计划含暂停层，其字号直接按 12/24 基准新建即可）。
5. **主菜单退役旧设置面板**（main_menu.tscn 内 `SettingsPanel`，visible=false）：字号保留旧值未归一，永不渲染；若后续彻底删除该节点可顺带清理。
6. 图鉴解锁条件 12px 下 5 行内截断（clip_contents 裁在格内）：文案完整可读性由 G-1 观感裁定（数据最长「累计触发 260 次元素共鸣（260/260）」档）。
