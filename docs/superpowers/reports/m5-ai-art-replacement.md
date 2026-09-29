# M5 美术升级：AI 生图替换报告（2026-09-29）

- 工具：`tools/gen_ai_art.py` + 清单 `tools/ai_art_manifest.json`（供应商 api.tu-zi.com，OpenAI Images 兼容；`gpt-image-2`，上游 5xx 回退 `gpt-image-2.5`；5 并发）
- 密钥：环境变量 `AI_ART_KEY` 或仓库根 `.ai_art_key`（gitignore，**不入库**——仓库公开）
- 结果：**42 项中 33 项替换入库**，9 项保留原程序化素材；原件备份在 `art_ai/backup/`（`--restore` 可一键回滚，art_ai/ 不入库）

## 1. 范围取舍

纳入 = 游戏内实际渲染的**单张独立贴图**（替换 = 换文件，零动画/图集/平铺风险）：选角立绘 20（`ui/portrait_*.png` 32×32，选角页 64px 显示）+ 设施/陈设 22（`tiles/` 12~20px）。

排除及理由：角色/敌人行走帧表（多帧对齐 AI 不可行）、地板/墙（无缝平铺硬约束）、8~16px 图标/弹幕/拾取物（降采样即糊，程序化像素已达标）、`logo_title`/`icon_app`（游戏内零引用：主菜单标题是 Label、应用图标是 `icon.svg`，替换无可见效果）。

## 2. 降采样管线

供应商约 ⅓ 输出无视透明背景参数（纯白底或画上去的伪棋盘格），脚本自动抠图（边框主色集 flood-fill）。朴素缩放会把 512px 细节平均成灰泥，因此改为：抠图 → 主体框（丢弃远离主体的星点碎屑）→ 目标构图（立绘取顶部正方、设施底对齐）→ 主体调色板量化（32px 16 色 / 更小 10 色）→ 分块多数表决降采样（平涂不产生均值色）→ 1px `#181420` 描边（项目 house style，与 art_qa 底色同源）；第 3 轮项额外去孤立噪点。

## 3. 验图口径（对话模型视觉判定）

验图模型 = 会话同一中转的 `claude-opus-5-5`（Messages API，盲测随机数字/形状/颜色全对，确认真实可见）。

**校准发现**：在 16~32px 下该模型对**原程序化素材**的绝对分同样只有 2~4/10——绝对阈值在此尺寸无区分度。故改为**双向盲评 A/B**：新旧图同尺寸同放大倍率并列，左右位置互换各评一次抵消位置偏置；**两次都判新图更好且新图均分 ≥5 才通过**。之后再过项目自有 `tools/art_qa_check.py` 门禁（对比度/剪影 IoU/主连通域），不扩大棘轮基线。

三轮循环：第 1 轮 14/40 胜（另 2 张供应商断连未出）→ 失败项收紧提示词（极简大色块、≤4~6 平涂色、粗描边、禁道具）第 2 轮 17/28 胜 → 第 3 轮针对性重写 11 张 7 胜。累计 38/42 胜过原件，其中 5 张被 art_qa 门禁拒。

## 4. 已替换（33）

| id | 文件 | 尺寸 | 新图均分 | 原图均分 |
|---|---|---|---|---|
| `portrait_vanguard` | `ui/portrait_vanguard.png` | 32×32 | 7.5 | 4.0 |
| `portrait_ranger` | `ui/portrait_ranger.png` | 32×32 | 6.5 | 4.0 |
| `portrait_mage` | `ui/portrait_mage.png` | 32×32 | 7.0 | 3.5 |
| `portrait_engineer` | `ui/portrait_engineer.png` | 32×32 | 7.0 | 4.0 |
| `portrait_guardian` | `ui/portrait_guardian.png` | 32×32 | 7.0 | 3.0 |
| `portrait_berserk` | `ui/portrait_berserk.png` | 32×32 | 5.5 | 4.0 |
| `portrait_hunter` | `ui/portrait_hunter.png` | 32×32 | 5.5 | 3.5 |
| `portrait_monk` | `ui/portrait_monk.png` | 32×32 | 6.0 | 4.0 |
| `portrait_cleric` | `ui/portrait_cleric.png` | 32×32 | 6.0 | 3.5 |
| `portrait_necro` | `ui/portrait_necro.png` | 32×32 | 6.0 | 4.0 |
| `portrait_timeweaver` | `ui/portrait_timeweaver.png` | 32×32 | 6.5 | 3.5 |
| `portrait_alchemist` | `ui/portrait_alchemist.png` | 32×32 | 6.0 | 3.5 |
| `portrait_gunslinger` | `ui/portrait_gunslinger.png` | 32×32 | 6.5 | 4.0 |
| `portrait_bard` | `ui/portrait_bard.png` | 32×32 | 7.5 | 3.5 |
| `portrait_mirage` | `ui/portrait_mirage.png` | 32×32 | 6.5 | 3.5 |
| `portrait_lycan` | `ui/portrait_lycan.png` | 32×32 | 6.0 | 3.0 |
| `portrait_warlock` | `ui/portrait_warlock.png` | 32×32 | 6.0 | 5.0 |
| `portrait_bulwark` | `ui/portrait_bulwark.png` | 32×32 | 6.0 | 4.5 |
| `portrait_staranchor` | `ui/portrait_staranchor.png` | 32×32 | 6.0 | 3.5 |
| `tile_shopkeeper` | `tiles/shopkeeper.png` | 16×18 | 5.0 | 4.0 |
| `tile_shopkeeper_black` | `tiles/shopkeeper_black.png` | 16×18 | 5.5 | 4.0 |
| `tile_shrine_zhanshen` | `tiles/shrine_zhanshen.png` | 16×18 | 6.0 | 4.5 |
| `tile_shrine_jingling` | `tiles/shrine_jingling.png` | 16×18 | 5.5 | 4.0 |
| `tile_shrine_fengshen` | `tiles/shrine_fengshen.png` | 16×18 | 6.5 | 3.5 |
| `tile_shrine_xingsui` | `tiles/shrine_xingsui.png` | 16×18 | 7.0 | 4.0 |
| `tile_fountain_full` | `tiles/fountain_full.png` | 16×16 | 7.0 | 4.0 |
| `tile_fountain_used` | `tiles/fountain_used.png` | 16×16 | 6.0 | 3.5 |
| `tile_event_merchant` | `tiles/event_merchant.png` | 16×18 | 5.5 | 3.0 |
| `tile_event_graffiti` | `tiles/event_graffiti.png` | 18×18 | 6.5 | 4.0 |
| `tile_exit_crystal` | `tiles/exit_crystal.png` | 12×18 | 7.5 | 3.0 |
| `tile_hazard_spikes` | `tiles/hazard_spikes.png` | 16×16 | 7.0 | 2.5 |
| `tile_hazard_vent` | `tiles/hazard_vent.png` | 16×16 | 7.0 | 3.0 |
| `tile_prop_debris` | `tiles/prop_debris.png` | 16×16 | 6.0 | 3.0 |

## 5. 保留原件（9）

| id | 文件 | 尺寸 | 新图均分 | 原图均分 | 原因 |
|---|---|---|---|---|---|
| `portrait_assassin` | `ui/portrait_assassin.png` | 32×32 | 6.0 | 4.0 | art_qa_check 门禁拒（见下） |
| `tile_fusion_forge` | `tiles/fusion_forge.png` | 20×18 | 3.5 | 5.5 | 三轮 A/B 仍输原件 |
| `tile_drink_machine` | `tiles/drink_machine.png` | 16×18 | 3.0 | 6.0 | 三轮 A/B 仍输原件 |
| `tile_shrine_base` | `tiles/shrine.png` | 16×18 | 7.0 | 4.0 | art_qa_check 门禁拒（见下） |
| `tile_event_device` | `tiles/event_device.png` | 16×18 | 3.0 | 7.0 | 三轮 A/B 仍输原件 |
| `tile_event_beggar` | `tiles/event_beggar.png` | 16×18 | 5.0 | 3.0 | art_qa_check 门禁拒（见下） |
| `tile_event_spring` | `tiles/event_spring.png` | 16×18 | 5.0 | 7.0 | 三轮 A/B 仍输原件 |
| `tile_totem_revive` | `tiles/totem_revive.png` | 16×20 | 7.0 | 4.0 | art_qa_check 门禁拒（见下） |
| `tile_recycle_rack` | `tiles/recycle_rack.png` | 16×16 | 5.5 | 4.0 | art_qa_check 门禁拒（见下） |

门禁拒绝的 5 张在 A/B 中都胜过原件，但未过项目美术 QA：刺客立绘对比度 27.4（阈值 30，暗色调设计）、空神龛/复活图腾/回收架剪影 IoU 0.80~0.82（阈值 0.85）、乞丐/回收架主连通域 0.43~0.46（造型本身分离——碗与人、架与物件）。整体提亮试验无改善（撤回），按门禁保留原件而不放宽阈值。

## 6. 复现

```
python tools/gen_ai_art.py                     # 生成缺失项（5 并发）
python tools/gen_ai_art.py --process           # raw → out 降采样
python tools/gen_ai_art.py --qa                # A/B 视觉验图 → art_ai/qa.json
python tools/gen_ai_art.py --only <ids> --force   # 重生成不合格项
python tools/gen_ai_art.py --apply --only <ids>   # 替换入库（先备份原件）
python tools/art_qa_check.py --baseline tools/art_qa_baseline.json
```
